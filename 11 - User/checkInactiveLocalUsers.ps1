#Requires -Version 5.1

<#
.SYNOPSIS
DE: Inaktive aktivierte lokale Benutzer finden. EN: Find inactive enabled local users.
.DESCRIPTION
DE: Prueft aktivierte lokale Konten (Get-LocalUser), deren LastLogon aelter als N Tage ist oder
die sich nie angemeldet haben. Integrierte Konten (RID 500 Administrator, 501 Gast, 503
DefaultAccount, 504 WDAGUtilityAccount) werden optional ausgeschlossen. Nur lesend; keine SIDs,
Kennwoerter oder Beschreibungen. LastLogon gilt nur fuer diese lokale SAM.
EN: Checks enabled local accounts (Get-LocalUser) whose LastLogon is older than N days or that
never logged on. Built-in accounts (RID 500 Administrator, 501 Guest, 503 DefaultAccount, 504
WDAGUtilityAccount) are optionally excluded. Read-only; no SIDs, passwords or descriptions.
LastLogon applies to this local SAM only.
DE: Benoetigt Get-LocalUser (Windows 10/Server 2016+); Domaenencontroller haben keine lokale SAM.
EN: Requires Get-LocalUser (Windows 10/Server 2016+); domain controllers have no local SAM.
.PARAMETER InactiveDays
DE: NinjaOne userInactiveDays (Integer), 1..3650; Standard 90.
EN: NinjaOne userInactiveDays (integer), 1..3650; default 90.
.PARAMETER ExcludeBuiltIn
DE: NinjaOne userExcludeBuiltIn (Text/Checkbox), true/false/1/0; Standard true.
EN: NinjaOne userExcludeBuiltIn (text/checkbox), true/false/1/0; default true.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkInactiveLocalUsers.ps1
DE: Exit 2 bei aktivierten Konten ohne Anmeldung seit 90 Tagen. EN: Exit 2 for enabled accounts without logon for 90 days.
.EXAMPLE
.\checkInactiveLocalUsers.ps1 -InactiveDays 30 -ExcludeBuiltIn false -CustomField inactiveLocalUsers
DE: Grenze 30 Tage inkl. integrierter Konten; JSON in inactiveLocalUsers. EN: 30-day limit incl. built-in accounts; JSON to inactiveLocalUsers.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = keine inaktiven Konten, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein aktiviertes Konto inaktiv oder nie angemeldet.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no inactive accounts, 1 = input/query/write error, 2 = at least one enabled account inactive or never logged on.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InactiveDays = $env:userInactiveDays,
    [string]$ExcludeBuiltIn = $env:userExcludeBuiltIn,
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
    $days = ConvertTo-BoundedInt -Value (Get-InputValue $InactiveDays '90') -Name 'userInactiveDays' -Minimum 1 -Maximum 3650
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $ExcludeBuiltIn = Get-InputValue $ExcludeBuiltIn 'true'
    if ($ExcludeBuiltIn -notin @('true', 'false', '1', '0')) { throw 'userExcludeBuiltIn must be true/false/1/0 / muss true/false/1/0 sein.' }
    $skipBuiltIn = $ExcludeBuiltIn -in @('true', '1')
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) { throw 'Get-LocalUser unavailable / nicht verfuegbar.' }
    $now = [DateTime]::UtcNow
    $users = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled })
    $excluded = 0
    $findings = @(foreach ($user in $users) {
        # DE: Integrierte Konten ueber RID erkennen (sprachunabhaengig). EN: Detect built-in accounts by RID (language independent).
        if ($skipBuiltIn -and ([string]$user.SID) -match '-50[0134]$') { $excluded++; continue }
        $last = $null
        $age = $null
        if ($null -ne $user.LastLogon) {
            $last = ([DateTime]$user.LastLogon).ToUniversalTime()
            $age = [int][Math]::Floor(($now - $last).TotalDays)
        }
        if ($null -eq $last -or $age -ge $days) {
            $lastText = $null
            if ($null -ne $last) { $lastText = $last.ToString('o') }
            [pscustomobject]@{ name = [string]$user.Name; lastLogonUtc = $lastText; ageDays = $age; neverLoggedOn = ($null -eq $last) }
        }
    })
    $sorted = @($findings | Sort-Object @{ Expression = 'neverLoggedOn'; Descending = $true }, @{ Expression = 'ageDays'; Descending = $true }, name)
    $report = [ordered]@{
        check = 'Inactive enabled local users / Inaktive aktivierte lokale Benutzer'
        thresholdDays = $days; builtInExcluded = $skipBuiltIn; excludedBuiltInCount = $excluded
        enabledUsers = $users.Count; total = $sorted.Count; returned = 0; truncated = $false; records = $sorted
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($sorted.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
