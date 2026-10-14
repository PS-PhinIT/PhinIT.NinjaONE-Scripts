#Requires -Version 5.1

<#
.SYNOPSIS
DE: Aktuell angemeldete Benutzersitzungen lesen. EN: Read currently logged-on user sessions.
.DESCRIPTION
DE: Liest Sitzungen mit quser (Benutzer, Sitzungsname/-typ, ID, Status, Leerlauf, Anmeldezeit).
quser mit Exit 1 und "No User exists" bedeutet keine Sitzungen (kein Fehler). Fehlt quser oder
schlaegt es anders fehl, werden die Besitzer von explorer.exe (Win32_Process, GetOwner) gemeldet.
EN: Reads sessions with quser (user, session name/type, ID, state, idle, logon time).
quser exit 1 with "No User exists" means no sessions (not an error). If quser is missing or fails
otherwise, owners of explorer.exe (Win32_Process, GetOwner) are reported as fallback.
DE: Gebietsschema-Hinweis: quser-Kopfzeile, Status, Leerlauf und Anmeldezeit sind lokalisiert und
werden als Rohtext gemeldet; "No User exists" wird nur englisch erkannt (sonst Fallback).
EN: Locale caveat: quser header, state, idle and logon time are localized and reported as raw text;
"No User exists" is only recognized in English (otherwise the fallback is used).
DE: Nur lesend; keine SIDs, keine Prozessdetails. Informativ, kein Alarm.
EN: Read-only; no SIDs, no process details. Informational, no alert.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\readLoggedOnUsers.ps1
DE: Bis zu 25 Sitzungen als JSON. EN: Up to 25 sessions as JSON.
.EXAMPLE
.\readLoggedOnUsers.ps1 -MaxRecords 50 -CustomField loggedOnUsers
DE: Bis zu 50 Sitzungen; JSON in loggedOnUsers. EN: Up to 50 sessions; JSON to loggedOnUsers.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = Erfolg, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = nicht verwendet.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = success, 1 = input/query/write error, 2 = not used.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MaxRecords = $env:userMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputValue {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0} must be {1}..{2} / muss {1}..{2} sein.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([System.Collections.IDictionary]$Report, [int]$Limit, [string]$Field)
    $all = @($Report['records'])
    $count = [Math]::Min($all.Count, $Limit)
    while ($true) {
        $Report['records'] = @($all | Select-Object -First $count)
        $Report['returned'] = $count
        $Report['truncated'] = ($count -lt $all.Count)
        $content = ConvertTo-Json -InputObject $Report -Depth 5
        if ($content.Length -le 4000 -or $count -eq 0) { break }
        $count--
    }
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $sessions = New-Object System.Collections.Generic.List[object]
    $method = 'quser'
    $note = $null
    $quserUsable = $false
    if (Get-Command quser -ErrorAction SilentlyContinue) {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $global:LASTEXITCODE = 0
            $lines = @(quser 2>&1 | ForEach-Object { [string]$_ })
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }
        if ($code -eq 0) {
            $quserUsable = $true
            foreach ($line in $lines) {
                $tokens = @($line.TrimStart(' ', '>').Split([char[]]@(' ', "`t"), [StringSplitOptions]::RemoveEmptyEntries))
                # DE: Erstes reines Zahlen-Token nach dem Benutzer ist die Sitzungs-ID. EN: First numeric token after the user is the session ID.
                $idIndex = -1
                for ($i = 1; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -match '^\d+$') { $idIndex = $i; break } }
                if ($idIndex -lt 1 -or $tokens.Count -lt $idIndex + 3) { continue }
                $sessionName = ''
                if ($idIndex -gt 1) { $sessionName = $tokens[1..($idIndex - 1)] -join ' ' }
                $sessionType = 'Other'
                if (-not $sessionName) { $sessionType = 'None (disconnected)' }
                elseif ($sessionName -ieq 'console') { $sessionType = 'Console' }
                elseif ($sessionName -imatch '^rdp-') { $sessionType = 'RDP' }
                $logonTime = $null
                if ($tokens.Count -gt $idIndex + 3) { $logonTime = $tokens[($idIndex + 3)..($tokens.Count - 1)] -join ' ' }
                $sessions.Add([pscustomobject]@{
                    userName = $tokens[0]; sessionName = $sessionName; sessionType = $sessionType
                    sessionId = [int]$tokens[$idIndex]; state = $tokens[$idIndex + 1]
                    idleTime = $tokens[$idIndex + 2]; logonTime = $logonTime
                })
            }
        } elseif ($code -eq 1 -and ($lines -join ' ') -match 'No User exists') {
            $quserUsable = $true
            $note = 'No sessions / Keine Sitzungen'
        } else {
            $note = 'quser exit {0}; fallback Win32_Process' -f $code
        }
    } else {
        $note = 'quser unavailable / nicht verfuegbar; fallback Win32_Process'
    }
    if (-not $quserUsable) {
        $method = 'Win32_Process explorer.exe GetOwner'
        $seen = @{}
        $ownerErrors = 0
        $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction Stop)
        foreach ($process in $processes) {
            try { $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop } catch { $ownerErrors++; continue }
            if ($owner.ReturnValue -ne 0 -or -not $owner.User) { $ownerErrors++; continue }
            $user = [string]$owner.User
            if ($owner.Domain) { $user = '{0}\{1}' -f $owner.Domain, $owner.User }
            $key = '{0}|{1}' -f $user, $process.SessionId
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $started = $null
            if ($process.CreationDate -is [DateTime]) { $started = $process.CreationDate.ToUniversalTime().ToString('o') }
            $sessions.Add([pscustomobject]@{
                userName = $user; sessionName = $null; sessionType = 'Unknown'; sessionId = [int]$process.SessionId
                state = 'Unknown'; idleTime = $null; logonTime = $started
            })
        }
        if ($ownerErrors -gt 0) { $note = '{0}; owner lookup errors / Besitzerfehler: {1}' -f $note, $ownerErrors }
    }
    $report = [ordered]@{
        check = 'Logged-on users / Angemeldete Benutzer'; method = $method; note = $note
        total = $sessions.Count; returned = 0; truncated = $false
        records = @($sessions | Sort-Object sessionId, userName)
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
