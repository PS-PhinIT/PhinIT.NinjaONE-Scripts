#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Zaehlt fehlgeschlagene Anmeldungen (4625) und Kontosperrungen (4740) begrenzt und gruppiert.
    EN: Counts failed logons (4625) and account lockouts (4740), bounded and grouped.
.DESCRIPTION
    DE: Liest das Security-Protokoll per Get-WinEvent -FilterHashtable (StartTime, MaxEvents) fuer die
        letzten Hours Stunden. 4625-Ereignisse werden per XML-EventData nach TargetUserName, IpAddress und
        LogonType gruppiert (haeufigste zuerst, max. MaxRecords Gruppen, bis 4000 Zeichen gekuerzt).
        4740 (Konto gesperrt) wird gezaehlt, die gesperrten Kontonamen begrenzt gelistet. Keine Kennwoerter
        oder Ereignistexte. EventLimitReached = MaxEvents erreicht, Summe ist dann eine Untergrenze.
        Keine Treffer sind kein Fehler.
    EN: Reads the Security log via Get-WinEvent -FilterHashtable (StartTime, MaxEvents) for the last
        Hours hours. 4625 events are grouped by TargetUserName, IpAddress and LogonType from XML EventData
        (most frequent first, max. MaxRecords groups, shrunk to 4000 characters). 4740 (account locked out)
        is counted and locked account names are listed (bounded). No passwords or message texts.
        EventLimitReached = MaxEvents hit, the total is then a lower bound. No matches are not an error.
.PARAMETER Hours
    DE: NinjaOne Integer securityFailedLogonHours, 1..720; Standard 24.
    EN: NinjaOne Integer securityFailedLogonHours, 1..720; default 24.
.PARAMETER Threshold
    DE: NinjaOne Integer securityFailedLogonThreshold, 1..100000; Standard 20. Exit 2 ab dieser Anzahl 4625.
    EN: NinjaOne Integer securityFailedLogonThreshold, 1..100000; default 20. Exit 2 at this many 4625 events.
.PARAMETER MaxEvents
    DE: NinjaOne Integer securityFailedLogonMaxEvents, 1..20000; Standard 5000 (je Ereignis-ID).
    EN: NinjaOne Integer securityFailedLogonMaxEvents, 1..20000; default 5000 (per event ID).
.PARAMETER MaxRecords
    DE: NinjaOne Integer securityFailedLogonMaxRecords, 1..50; Standard 10 (Gruppen bzw. gesperrte Konten).
    EN: NinjaOne Integer securityFailedLogonMaxRecords, 1..50; default 10 (groups or locked accounts).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\readFailedLogons.ps1
    DE: Letzte 24 Stunden; Exit 2 ab 20 fehlgeschlagenen Anmeldungen.
    EN: Last 24 hours; exit 2 at 20 or more failed logons.
.EXAMPLE
    .\readFailedLogons.ps1 -Hours 4 -Threshold 50 -MaxRecords 5 -CustomField failedLogons
    DE: Letzte 4 Stunden, Grenzwert 50, Top 5; JSON ins Feld failedLogons.
    EN: Last 4 hours, threshold 50, top 5; JSON to the field failedLogons.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend; Ueberwachung "Anmelden" (Failure) noetig.
        Parameter vor Variablen. Exit 0 = unter Grenzwert, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = Anzahl 4625 >= Threshold.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only; requires "Logon" failure auditing.
        Parameters override variables. Exit 0 = below threshold, 1 = input/query/write error,
        2 = 4625 count >= Threshold.
#>
[CmdletBinding()]
param(
    [string]$Hours = $env:securityFailedLogonHours,
    [string]$Threshold = $env:securityFailedLogonThreshold,
    [string]$MaxEvents = $env:securityFailedLogonMaxEvents,
    [string]$MaxRecords = $env:securityFailedLogonMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-IntSetting {
    param([string]$Value, [int]$Default, [int]$Minimum, [int]$Maximum, [string]$Name)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    $number = 0
    if (-not [int]::TryParse($text, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0}: {1}..{2} erforderlich / required.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Get-SecurityEvent {
    param([int]$Id, [datetime]$Start, [int]$Limit)
    try { Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $Id; StartTime = $Start } -MaxEvents $Limit -ErrorAction Stop }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
}
function Get-EventField {
    param($Record)
    $map = @{}
    foreach ($data in @(([xml]$Record.ToXml()).Event.EventData.Data)) {
        $value = ([string]$data.InnerText) -replace '[\x00-\x1F\x7F]', ''
        if ($value.Length -gt 64) { $value = $value.Substring(0, 64) }
        $map[[string]$data.Name] = $value
    }
    return $map
}
try {
    $hourCount = Get-IntSetting $Hours 24 1 720 'securityFailedLogonHours'
    $limit = Get-IntSetting $Threshold 20 1 100000 'securityFailedLogonThreshold'
    $eventLimit = Get-IntSetting $MaxEvents 5000 1 20000 'securityFailedLogonMaxEvents'
    $recordLimit = Get-IntSetting $MaxRecords 10 1 50 'securityFailedLogonMaxRecords'
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }

    $start = (Get-Date).AddHours(-$hourCount)
    $failed = @(Get-SecurityEvent -Id 4625 -Start $start -Limit $eventLimit)
    $lockouts = @(Get-SecurityEvent -Id 4740 -Start $start -Limit $eventLimit)
    $logonTypes = @{ '2' = 'Interactive'; '3' = 'Network'; '4' = 'Batch'; '5' = 'Service'; '7' = 'Unlock'; '8' = 'NetworkCleartext'; '9' = 'NewCredentials'; '10' = 'RemoteInteractive'; '11' = 'CachedInteractive' }
    $groups = @{}
    foreach ($logEntry in $failed) {
        $fields = Get-EventField $logEntry
        $key = '{0}|{1}|{2}' -f $fields['TargetUserName'], $fields['IpAddress'], $fields['LogonType']
        if (-not $groups.ContainsKey($key)) {
            $type = [string]$fields['LogonType']
            $groups[$key] = [pscustomobject]@{
                TargetUserName = $fields['TargetUserName']; IpAddress = $fields['IpAddress']; LogonType = $type
                LogonTypeName = $logonTypes[$type]; Attempts = 0; LastUtc = $null
            }
        }
        $group = $groups[$key]
        $group.Attempts++
        $time = ([datetime]$logEntry.TimeCreated).ToUniversalTime().ToString('o')
        if ($null -eq $group.LastUtc -or $time -gt $group.LastUtc) { $group.LastUtc = $time }
    }
    $lockedNames = @{}
    foreach ($logEntry in $lockouts) {
        $name = [string](Get-EventField $logEntry)['TargetUserName']
        if ($lockedNames.ContainsKey($name)) { $lockedNames[$name]++ } else { $lockedNames[$name] = 1 }
    }
    $sortedGroups = @($groups.Values | Sort-Object -Property @{ Expression = 'Attempts'; Descending = $true }, @{ Expression = 'TargetUserName'; Descending = $false })
    $sortedLocked = @($lockedNames.GetEnumerator() | Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } |
        ForEach-Object { [pscustomobject]@{ TargetUserName = $_.Key; Count = $_.Value } })
    $records = @($sortedGroups | Select-Object -First $recordLimit)
    $lockRecords = @($sortedLocked | Select-Object -First $recordLimit)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Hours = $hourCount; Threshold = $limit; FailedLogonCount = $failed.Count; LockoutCount = $lockouts.Count
            EventLimitReached = ($failed.Count -ge $eventLimit -or $lockouts.Count -ge $eventLimit)
            TotalGroups = $sortedGroups.Count; TotalLockedAccounts = $sortedLocked.Count
            Truncated = ($records.Count -lt $sortedGroups.Count -or $lockRecords.Count -lt $sortedLocked.Count)
            Groups = $records; LockedAccounts = $lockRecords
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0 -and $lockRecords.Count -eq 0) { throw 'Bericht zu gross / Report too large.' }
        if ($records.Count -ge $lockRecords.Count) { $records = @($records | Select-Object -First ($records.Count - 1)) }
        else { $lockRecords = @($lockRecords | Select-Object -First ($lockRecords.Count - 1)) }
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($failed.Count -ge $limit) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
