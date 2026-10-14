#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet fehlgeschlagene/abgebrochene Einträge im Windows-Update-Verlauf der letzten N Tage.
    EN: Reports failed/aborted Windows Update history entries of the last N days.
.DESCRIPTION
    DE: Liest den lokalen Verlauf (Microsoft.Update.Session, nur QueryHistory, keine Suche)
        bis maximal 1000 Einträge und filtert Einträge im Zeitraum Days mit ResultCode 4
        (fehlgeschlagen) oder 5 (abgebrochen). Ausgabe: Datum (UTC), Titel, Ergebnis,
        HResult (hex) und Vorgang (Installation/Deinstallation), begrenzt auf MaxRecords und
        4000 Zeichen (TotalFailures/Truncated). Im Unterschied zu readWindowsUpdateStatus
        wird nach Zeitraum gefiltert und nur Fehler werden gelistet. Exit 0 = keine Fehler im
        Zeitraum, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = mindestens ein
        fehlgeschlagener oder abgebrochener Eintrag im Zeitraum.
    EN: Reads the local history (Microsoft.Update.Session, QueryHistory only, no search) up to
        1000 entries and filters entries within Days with ResultCode 4 (failed) or 5 (aborted).
        Output: date (UTC), title, result, HResult (hex) and operation (installation/
        uninstallation), bounded by MaxRecords and 4000 characters (TotalFailures/Truncated).
        Unlike readWindowsUpdateStatus it filters by time window and lists failures only.
        Exit 0 = no failures in the window, 1 = input, query or write error, 2 = at least one
        failed or aborted entry in the window.
.PARAMETER Days
    DE: NinjaOne Integer updateFailureDays, 1..365; Standard 30.
    EN: NinjaOne Integer updateFailureDays, 1..365; default 30.
.PARAMETER MaxRecords
    DE: NinjaOne Integer updateFailureMaxRecords, 1..100; Standard 20.
    EN: NinjaOne Integer updateFailureMaxRecords, 1..100; default 20.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\readUpdateHistoryFailures.ps1
    DE: Fehlgeschlagene/abgebrochene Updates der letzten 30 Tage (max. 20 Einträge).
    EN: Failed/aborted updates of the last 30 days (max. 20 records).
.EXAMPLE
    .\readUpdateHistoryFailures.ps1 -Days 7 -MaxRecords 10 -CustomField updateFailures
    DE: Letzte 7 Tage, max. 10 Einträge, JSON ins Feld updateFailures.
    EN: Last 7 days, max. 10 records, JSON to the field updateFailures.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Ein erfolgreicher späterer
        Versuch hebt den Befund nicht auf. Exit 0 = OK, 1 = Fehler, 2 = Fehler im Verlauf.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. A later successful retry does not
        clear the finding. Exit 0 = OK, 1 = error, 2 = failures in history.
#>
[CmdletBinding()]
param(
    [string]$Days = $env:updateFailureDays,
    [string]$MaxRecords = $env:updateFailureMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($Days) -or $Days.Trim() -eq 'null') { $Days = '30' }
    if ([string]::IsNullOrWhiteSpace($MaxRecords) -or $MaxRecords.Trim() -eq 'null') { $MaxRecords = '20' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    $window = 0
    if (-not [int]::TryParse($Days.Trim(), [ref]$window) -or $window -lt 1 -or $window -gt 365) {
        throw 'updateFailureDays: 1..365 erforderlich / required.'
    }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords.Trim(), [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'updateFailureMaxRecords: 1..100 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    $cutoff = [DateTime]::UtcNow.AddDays(-$window)
    $resultNames = @{ 4 = 'Failed'; 5 = 'Aborted' }
    $operationNames = @{ 1 = 'Installation'; 2 = 'Uninstallation'; 3 = 'Other' }
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $total = [int]$searcher.GetTotalHistoryCount()
    $scanned = 0
    $failures = @()
    if ($total -gt 0) {
        $failures = @(foreach ($entry in @($searcher.QueryHistory(0, [Math]::Min($total, 1000)))) {
            $scanned++
            $code = [int]$entry.ResultCode
            if ($code -notin @(4, 5) -or $null -eq $entry.Date) { continue }
            # DE: WUA liefert UTC ohne Kind. EN: WUA returns UTC without kind.
            $date = [DateTime]::SpecifyKind([DateTime]$entry.Date, [DateTimeKind]::Utc)
            if ($date -lt $cutoff) { continue }
            $title = [string]$entry.Title
            if ($title.Length -gt 150) { $title = $title.Substring(0, 150) }
            $operation = $operationNames[[int]$entry.Operation]
            if (-not $operation) { $operation = [string]$entry.Operation }
            [pscustomobject]@{
                DateUtc = $date.ToString('o'); Title = $title; Result = $resultNames[$code]
                HResult = ('0x{0:X8}' -f [int]$entry.HResult); Operation = $operation
            }
        })
    }
    $failures = @($failures | Sort-Object DateUtc -Descending)
    $failedCount = @($failures | Where-Object { $_.Result -eq 'Failed' }).Count
    $records = @($failures | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $failures.Count
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Days = $window; TotalHistoryEntries = $total; ScannedEntries = $scanned
            TotalFailures = $failures.Count; FailedCount = $failedCount; AbortedCount = $failures.Count - $failedCount
            ReportedRecords = $records.Count; Truncated = $truncated; Failures = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($failures.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
