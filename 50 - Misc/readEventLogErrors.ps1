#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet begrenzte Metadaten aktueller kritischer/Fehler-Ereignisse.
    EN: Reports bounded metadata of recent critical/error events.
.DESCRIPTION
    DE: Nur Application oder System. Keine Message, XML, Eventdaten oder Benutzer.
        Abfrage auf MaxRecords+1 begrenzt; Gesamtzahl ist nicht bekannt.
        ObservedMatches ist eine Untergrenze bei Kürzung. Maximal 4000 Zeichen.
    EN: Application or System only. No Message, XML, event data or users.
        Query limited to MaxRecords+1; full total is unknown.
        ObservedMatches is a lower bound when truncated. At most 4000 characters.
.PARAMETER LogName
    DE: System oder Application; eventLogName, Standard System.
    EN: System or Application; eventLogName, default System.
.PARAMETER LookbackHours
    DE: 1..720; eventLogLookbackHours, Standard 24.
    EN: 1..720; eventLogLookbackHours, default 24.
.PARAMETER MaxRecords
    DE: 1..100; eventLogMaxRecords, Standard 25.
    EN: 1..100; eventLogMaxRecords, default 25.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.EXAMPLE
    .\readEventLogErrors.ps1 -LogName System -LookbackHours 24
    DE: Kritische/Fehler-Ereignisse im System-Log der letzten 24 Stunden.
    EN: Critical/error events in the System log from the last 24 hours.
.EXAMPLE
    .\readEventLogErrors.ps1 -LogName Application -LookbackHours 72 -MaxRecords 50 -CustomField eventLogErrors
    DE: Application-Log, 72 Stunden, bis zu 50 Einträge; JSON in eventLogErrors.
    EN: Application log, 72 hours, up to 50 entries; JSON to eventLogErrors.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen;
        leere Werte verwenden Standards. Keine Änderungen.
        Exit 0 = keine Fehlerereignisse, 1 = Fehler, 2 = Ereignisse/gekürzt.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment;
        empty values use defaults. No changes.
        Exit 0 = no error events, 1 = error, 2 = events/truncated.
#>
[CmdletBinding()]
param(
    [string]$LogName = $env:eventLogName,
    [string]$LookbackHours = $env:eventLogLookbackHours,
    [string]$MaxRecords = $env:eventLogMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $LogName = $LogName.Trim()
    $LookbackHours = $LookbackHours.Trim()
    $MaxRecords = $MaxRecords.Trim()
    $CustomField = $CustomField.Trim()
    if ($LogName -eq 'null') { $LogName = '' }
    if ($LookbackHours -eq 'null') { $LookbackHours = '' }
    if ($MaxRecords -eq 'null') { $MaxRecords = '' }
    if ($CustomField -eq 'null') { $CustomField = '' }
    if (-not $LogName) { $LogName = 'System' }
    if (-not $LookbackHours) { $LookbackHours = '24' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    if ($LogName -notin @('System', 'Application')) { throw 'Ungültiges LogName / Invalid LogName.' }
    $hours = 0
    $limit = 0
    if (-not [int]::TryParse($LookbackHours, [ref]$hours) -or $hours -lt 1 -or $hours -gt 720) {
        throw 'LookbackHours muss 1..720 sein / LookbackHours must be 1..720.'
    }
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'MaxRecords muss 1..100 sein / MaxRecords must be 1..100.'
    }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $startTime = (Get-Date).AddHours(-$hours)
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = $LogName; Level = @(1, 2); StartTime = $startTime } -MaxEvents ($limit + 1) -ErrorAction Stop |
            Select-Object @{ Name = 'TimeCreated'; Expression = { $_.TimeCreated.ToUniversalTime().ToString('o') } },
                Id, Level, ProviderName, RecordId)
    }
    catch {
        # DE: Nur „keine Treffer“ ist Erfolg; Zugriffs-/Abfragefehler bleiben Fehler.
        # EN: Only "no matches" is success; access/query failures remain errors.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
    $records = @($events | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $events.Count
        $report = [ordered]@{
            LogName = $LogName; StartTimeUtc = $startTime.ToUniversalTime().ToString('o')
            ObservedMatches = $events.Count; TotalMatchesKnown = ($events.Count -le $limit)
            ReportedRecords = $records.Count; Truncated = $truncated; Events = $records
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
    if ($events.Count -gt 0 -or $truncated) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
