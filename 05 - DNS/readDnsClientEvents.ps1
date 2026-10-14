#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Zählt DNS-Client-Ereignisse (z. B. 1014 Timeout) gruppiert nach Name.
    EN: Counts DNS client events (e.g. 1014 timeout) grouped by name.
.DESCRIPTION
    DE: Liest im System-Log Ereignisse des Anbieters Microsoft-Windows-DNS-Client mit
        den gewählten IDs (Standard 1014 = Namensauflösung abgelaufen) der letzten N
        Stunden per Get-WinEvent -FilterHashtable (StartTime, MaxEvents) und gruppiert
        nach Ereignis-ID und abgefragtem Namen (erste Ereigniseigenschaft, nur
        DNS-Namenszeichen, sonst "(unknown)"). Gruppen begrenzt und nach Anzahl
        sortiert; "keine Ereignisse" ist kein Fehler. Maximal 4000 Zeichen. Nur lesend.
    EN: Reads System log events of provider Microsoft-Windows-DNS-Client with the
        selected IDs (default 1014 = name resolution timeout) of the last N hours via
        Get-WinEvent -FilterHashtable (StartTime, MaxEvents) and groups them by event ID
        and queried name (first event property, DNS name characters only, otherwise
        "(unknown)"). Groups are bounded and sorted by count; "no events" is not an
        error. At most 4000 characters. Read-only.
.PARAMETER Hours
    DE: NinjaOne Integer dnsEventHours, 1..720; Standard 24.
    EN: NinjaOne Integer dnsEventHours, 1..720; default 24.
.PARAMETER Threshold
    DE: NinjaOne Integer dnsEventThreshold, 1..100000 Ereignisse; Standard 10.
    EN: NinjaOne Integer dnsEventThreshold, 1..100000 events; default 10.
.PARAMETER EventIds
    DE: NinjaOne Text dnsEventIds: kommagetrennte Ereignis-IDs 1..65535 (max. 10); Standard 1014.
    EN: NinjaOne Text dnsEventIds: comma-separated event IDs 1..65535 (max. 10); default 1014.
.PARAMETER MaxEvents
    DE: NinjaOne Integer dnsEventMaxEvents, 1..5000 gelesene Ereignisse; Standard 1000.
    EN: NinjaOne Integer dnsEventMaxEvents, 1..5000 events read; default 1000.
.PARAMETER MaxRecords
    DE: NinjaOne Integer dnsEventMaxRecords, 1..100 gemeldete Gruppen; Standard 20.
    EN: NinjaOne Integer dnsEventMaxRecords, 1..100 reported groups; default 20.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\readDnsClientEvents.ps1
    DE: Warnt, wenn in 24 Stunden mindestens 10 Ereignisse 1014 auftraten.
    EN: Warns if at least 10 events 1014 occurred within 24 hours.
.EXAMPLE
    .\readDnsClientEvents.ps1 -Hours 72 -Threshold 25 -EventIds '1014,8015,8018' -CustomField dnsClientEvents
    DE: 72 Stunden, Grenzwert 25, auch Registrierungsfehler; JSON in dnsClientEvents.
    EN: 72 hours, threshold 25, including registration failures; JSON to dnsClientEvents.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = weniger Ereignisse als der Grenzwert, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = Anzahl gelesener Ereignisse >= dnsEventThreshold. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = fewer events than the threshold, 1 = input, query or write error,
        2 = number of events read >= dnsEventThreshold. Read-only.
#>
[CmdletBinding()]
param(
    [string]$Hours = $env:dnsEventHours,
    [string]$Threshold = $env:dnsEventThreshold,
    [string]$EventIds = $env:dnsEventIds,
    [string]$MaxEvents = $env:dnsEventMaxEvents,
    [string]$MaxRecords = $env:dnsEventMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Default, [int]$Minimum, [int]$Maximum, [string]$Name)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { $text = $Default }
    $number = 0
    if (-not [int]::TryParse($text, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0} muss {1}..{2} sein / must be {1}..{2}.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
try {
    $hoursValue = ConvertTo-BoundedInt -Value $Hours -Default '24' -Minimum 1 -Maximum 720 -Name 'dnsEventHours'
    $thresholdValue = ConvertTo-BoundedInt -Value $Threshold -Default '10' -Minimum 1 -Maximum 100000 -Name 'dnsEventThreshold'
    $maxEventsValue = ConvertTo-BoundedInt -Value $MaxEvents -Default '1000' -Minimum 1 -Maximum 5000 -Name 'dnsEventMaxEvents'
    $limit = ConvertTo-BoundedInt -Value $MaxRecords -Default '20' -Minimum 1 -Maximum 100 -Name 'dnsEventMaxRecords'
    $EventIds = ([string]$EventIds).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($EventIds -ieq 'null') { $EventIds = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $EventIds) { $EventIds = '1014' }
    $ids = @(foreach ($entry in $EventIds.Split(',')) {
        $id = 0
        if (-not [int]::TryParse($entry.Trim(), [ref]$id) -or $id -lt 1 -or $id -gt 65535) { throw 'dnsEventIds: 1..65535.' }
        $id
    })
    $ids = @($ids | Sort-Object -Unique)
    if ($ids.Count -gt 10) { throw 'dnsEventIds: maximal 10 / at most 10.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $startTime = (Get-Date).AddHours(-$hoursValue)
    $filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-DNS-Client'; Id = $ids; StartTime = $startTime }
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $maxEventsValue -ErrorAction Stop)
    }
    catch {
        # DE: Nur "keine Treffer" ist Erfolg; Zugriffs-/Abfragefehler bleiben Fehler.
        # EN: Only "no matches" is success; access/query failures remain errors.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
    $items = @(foreach ($logEvent in $events) {
        $name = '(unknown)'
        $first = @($logEvent.Properties) | Select-Object -First 1
        if ($first) {
            $candidate = ([string]$first.Value).Trim()
            if ($candidate -match '^[A-Za-z0-9_.:-]{1,253}$') { $name = $candidate.TrimEnd('.').ToLowerInvariant() }
        }
        [pscustomobject]@{ Id = [int]$logEvent.Id; Name = $name; Time = $logEvent.TimeCreated }
    })
    $groups = @($items | Group-Object Id, Name | ForEach-Object {
        $latest = ($_.Group | Measure-Object -Property Time -Maximum).Maximum
        $lastSeen = ''
        if ($latest) { $lastSeen = ([datetime]$latest).ToUniversalTime().ToString('o') }
        [pscustomobject]@{ EventId = $_.Group[0].Id; Name = $_.Group[0].Name; Count = $_.Count; LastSeenUtc = $lastSeen }
    } | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
    $records = @($groups | Select-Object -First $limit)
    do {
        $report = [ordered]@{
            StartTimeUtc = $startTime.ToUniversalTime().ToString('o'); EventIds = $ids; Threshold = $thresholdValue
            TotalEvents = $events.Count; MaxEventsReached = ($events.Count -ge $maxEventsValue)
            TotalGroups = $groups.Count; ReportedGroups = $records.Count; Truncated = ($records.Count -lt $groups.Count)
            Groups = $records
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($events.Count -ge $thresholdValue) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
