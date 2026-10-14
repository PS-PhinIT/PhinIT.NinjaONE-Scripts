#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Fasst BitLocker-Fehler- und Warnereignisse der letzten Tage nach Ereignis-ID zusammen.
    EN: Summarizes BitLocker error and warning events of the last days grouped by event ID.
.DESCRIPTION
    DE: Liest per Get-WinEvent (FilterHashtable mit Level 2/3, StartTime, MaxEvents je Protokoll)
        die Protokolle Microsoft-Windows-BitLocker/BitLocker Management und .../BitLocker Operational
        (Anbieter BitLocker-API) sowie Microsoft-Windows-BitLocker-DrivePreparationTool/Admin und
        /Operational. Nicht vorhandene Protokolle oder keine Treffer sind kein Fehler (MissingLogs).
        Ausgabe je Protokoll+ID+Level: Anzahl, letzter Zeitpunkt und eine auf 160 Zeichen gekürzte
        erste Meldungszeile; 48-stellige Recovery-Kennwörter werden vorsorglich maskiert.
    EN: Reads via Get-WinEvent (FilterHashtable with level 2/3, StartTime, MaxEvents per log) the
        logs Microsoft-Windows-BitLocker/BitLocker Management and .../BitLocker Operational
        (provider BitLocker-API) plus Microsoft-Windows-BitLocker-DrivePreparationTool/Admin and
        /Operational. Missing logs or no matches are not errors (MissingLogs). Output per
        log+ID+level: count, latest time and the first message line truncated to 160 characters;
        48-digit recovery passwords are masked as a precaution.
.PARAMETER Days
    DE: NinjaOne Integer bitlockerEventDays; 1..90; Standard 7.
    EN: NinjaOne Integer bitlockerEventDays; 1..90; default 7.
.PARAMETER MaxEvents
    DE: NinjaOne Integer bitlockerEventMaxEvents; 1..1000 je Protokoll; Standard 200.
    EN: NinjaOne Integer bitlockerEventMaxEvents; 1..1000 per log; default 200.
.PARAMETER MaxRecords
    DE: NinjaOne Integer bitlockerEventMaxRecords; 1..50 ausgegebene Gruppen; Standard 20.
    EN: NinjaOne Integer bitlockerEventMaxRecords; 1..50 reported groups; default 20.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\readBitLockerEventErrors.ps1
    DE: Fehler und Warnungen der letzten 7 Tage, gruppiert.
    EN: Errors and warnings of the last 7 days, grouped.
.EXAMPLE
    .\readBitLockerEventErrors.ps1 -Days 30 -MaxRecords 10 -CustomField bitlockerEvents
    DE: 30 Tage, höchstens 10 Gruppen; JSON ins Feld bitlockerEvents.
    EN: 30 days, at most 10 groups; JSON to field bitlockerEvents.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = keine Fehlerereignisse (Warnungen werden nur gemeldet), 1 = Eingabe-/Abfrage-/
        Schreibfehler, 2 = mindestens ein Fehlerereignis (Level 2) im Zeitraum.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = no error events (warnings are only reported), 1 = input/query/write error,
        2 = at least one error event (level 2) in the period.
#>
[CmdletBinding()]
param(
    [string]$Days = $env:bitlockerEventDays,
    [string]$MaxEvents = $env:bitlockerEventMaxEvents,
    [string]$MaxRecords = $env:bitlockerEventMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $Days = ([string]$Days).Trim(); $MaxEvents = ([string]$MaxEvents).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim(); $CustomField = ([string]$CustomField).Trim()
    if ($Days -ieq 'null') { $Days = '' }
    if ($MaxEvents -ieq 'null') { $MaxEvents = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $Days) { $Days = '7' }
    if (-not $MaxEvents) { $MaxEvents = '200' }
    if (-not $MaxRecords) { $MaxRecords = '20' }
    $dayCount = 0; $eventLimit = 0; $recordLimit = 0
    if (-not [int]::TryParse($Days, [ref]$dayCount) -or $dayCount -lt 1 -or $dayCount -gt 90) { throw 'bitlockerEventDays: 1..90.' }
    if (-not [int]::TryParse($MaxEvents, [ref]$eventLimit) -or $eventLimit -lt 1 -or $eventLimit -gt 1000) { throw 'bitlockerEventMaxEvents: 1..1000.' }
    if (-not [int]::TryParse($MaxRecords, [ref]$recordLimit) -or $recordLimit -lt 1 -or $recordLimit -gt 50) { throw 'bitlockerEventMaxRecords: 1..50.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $logs = @(
        'Microsoft-Windows-BitLocker/BitLocker Management', 'Microsoft-Windows-BitLocker/BitLocker Operational',
        'Microsoft-Windows-BitLocker-DrivePreparationTool/Admin', 'Microsoft-Windows-BitLocker-DrivePreparationTool/Operational'
    )
    $start = (Get-Date).AddDays(-$dayCount)
    $missing = New-Object System.Collections.Generic.List[string]
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($log in $logs) {
        try {
            foreach ($entry in @(Get-WinEvent -FilterHashtable @{ LogName = $log; Level = @(2, 3); StartTime = $start } -MaxEvents $eventLimit)) { $events.Add($entry) }
        } catch {
            # DE: Keine Treffer/kein Protokoll ist kein Fehler. EN: No matches/no log is not an error.
            $id = [string]$_.FullyQualifiedErrorId
            if ($id -like 'NoMatchingEventsFound*') { continue }
            if ($id -like 'NoMatchingLogsFound*' -or $_.CategoryInfo.Category -eq 'ObjectNotFound') { $missing.Add($log); continue }
            throw
        }
    }
    $groups = @($events | Group-Object -Property LogName, Id, Level | ForEach-Object {
        $latest = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $sample = ([string]$latest.Message -split "`r?`n")[0]
        $sample = $sample -replace '\d{6}(-\d{6}){7}', '[REDACTED]'
        if ($sample.Length -gt 160) { $sample = $sample.Substring(0, 160) }
        $levelName = 'Warning'
        if ([int]$latest.Level -eq 2) { $levelName = 'Error' }
        [pscustomobject]@{
            LogName = [string]$latest.LogName; Id = [int]$latest.Id; Level = $levelName; Count = $_.Count
            Latest = ([datetime]$latest.TimeCreated).ToString('o'); Sample = $sample
        }
    } | Sort-Object @{ Expression = { $_.Level -eq 'Error' }; Descending = $true }, @{ Expression = 'Latest'; Descending = $true })
    $errorCount = @($events | Where-Object { [int]$_.Level -eq 2 }).Count
    $records = @($groups | Select-Object -First $recordLimit)
    do {
        $report = ConvertTo-Json -InputObject ([ordered]@{
            Days = $dayCount; TotalEvents = $events.Count; ErrorEvents = $errorCount
            WarningEvents = ($events.Count - $errorCount); TotalGroups = $groups.Count
            Truncated = ($records.Count -lt $groups.Count); MissingLogs = @($missing); Groups = $records
        }) -Depth 4 -Compress
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($errorCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
