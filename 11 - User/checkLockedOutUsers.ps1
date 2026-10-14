#Requires -Version 5.1

<#
.SYNOPSIS
DE: Gesperrte lokale Konten und Sperrereignisse melden. EN: Report locked-out local accounts and lockout events.
.DESCRIPTION
DE: Liest Win32_UserAccount (LocalAccount = True, Lockout = True) fuer aktuell gesperrte lokale Konten
und Security-Ereignis 4740 (Konto gesperrt) der letzten N Stunden (max. 200). Bei 4740 ist
TargetDomainName der aufrufende Computer. Nur lesend; keine Entsperrung, keine SIDs.
EN: Reads Win32_UserAccount (LocalAccount = True, Lockout = True) for currently locked-out local
accounts and Security event 4740 (account locked out) within the last N hours (max 200). For 4740,
TargetDomainName is the caller computer. Read-only; no unlock, no SIDs.
DE: Auf Domaenencontrollern betreffen 4740-Ereignisse Domaenenkonten. Erfordert SYSTEM/Administrator
und aktivierte Ueberwachung der Kontoverwaltung fuer 4740.
EN: On domain controllers 4740 events refer to domain accounts. Requires SYSTEM/administrator and
enabled account management auditing for 4740.
.PARAMETER EventHours
DE: NinjaOne userLockoutEventHours (Integer), 1..720; Standard 24.
EN: NinjaOne userLockoutEventHours (integer), 1..720; default 24.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkLockedOutUsers.ps1
DE: Gesperrte Konten und 4740-Ereignisse der letzten 24 Stunden. EN: Locked accounts and 4740 events of the last 24 hours.
.EXAMPLE
.\checkLockedOutUsers.ps1 -EventHours 168 -CustomField lockedOutUsers
DE: Ereignisse der letzten 7 Tage; JSON in lockedOutUsers. EN: Events of the last 7 days; JSON to lockedOutUsers.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = kein Konto aktuell gesperrt, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein lokales Konto aktuell gesperrt (4740-Ereignisse allein sind informativ).
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no account currently locked, 1 = input/query/write error, 2 = at least one local account currently locked out (4740 events alone are informational).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$EventHours = $env:userLockoutEventHours,
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
function Get-BoundedEvent {
    param([hashtable]$Filter, [int]$Maximum)
    try { Get-WinEvent -FilterHashtable $Filter -MaxEvents $Maximum -ErrorAction Stop }
    catch {
        # DE: Keine Treffer sind kein Fehler. EN: No matching events is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
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
    $hours = ConvertTo-BoundedInt -Value (Get-InputValue $EventHours '24') -Name 'userLockoutEventHours' -Minimum 1 -Maximum 720
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $locked = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True AND Lockout = True' -ErrorAction Stop | Sort-Object Name)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($account in $locked) {
        $records.Add([pscustomobject]@{ source = 'CurrentLockout'; account = [string]$account.Name; callerComputer = $null; timeUtc = $null })
    }
    $filter = @{ LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddHours(-$hours) }
    $events = @(Get-BoundedEvent -Filter $filter -Maximum 200)
    $parseErrors = 0
    foreach ($logEvent in ($events | Sort-Object TimeCreated -Descending)) {
        try {
            $data = @{}
            foreach ($node in ([xml]$logEvent.ToXml()).Event.EventData.Data) { $data[[string]$node.Name] = [string]$node.InnerText }
        } catch { $parseErrors++; continue }
        $records.Add([pscustomobject]@{
            source = 'Event4740'; account = $data['TargetUserName']; callerComputer = $data['TargetDomainName']
            timeUtc = ([DateTime]$logEvent.TimeCreated).ToUniversalTime().ToString('o')
        })
    }
    $report = [ordered]@{
        check = 'Locked-out accounts / Gesperrte Konten'; eventHours = $hours
        lockedNow = $locked.Count; lockoutEvents = $events.Count; eventLimitReached = ($events.Count -ge 200)
        parseErrors = $parseErrors
        total = $records.Count; returned = 0; truncated = $false; records = $records.ToArray()
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($locked.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
