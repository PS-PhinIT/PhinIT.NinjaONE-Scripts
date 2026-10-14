#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Listet MSI-Installationen und -Deinstallationen der letzten N Tage aus dem Anwendungsprotokoll.
    EN: Lists MSI installs and uninstalls of the last N days from the Application log.
.DESCRIPTION
    DE: Liest MsiInstaller-Ereignisse (Application-Protokoll) mit IDs 11707 (Installation erfolgreich),
        11724 (Entfernung erfolgreich), 1033 (Installationsergebnis) und 1034 (Entfernungsergebnis) per
        Get-WinEvent -FilterHashtable mit StartTime und MaxEvents. Produktname, Version, Hersteller und
        Status stammen bei 1033/1034 aus den Ereigniseigenschaften (sprachunabhängig); bei 11707/11724 wird
        der Produktname aus dem Text "<Produkt>: <Name> -- ..." gelesen (sprachabhängiger Präfix, generisch
        geparst). Keine Benutzer-SIDs. Nicht-MSI-Installer (EXE/AppX) werden nicht erfasst. Keine Ereignisse
        sind kein Fehler. Begrenzte Liste (4000 Zeichen).
        Exit 0 = Information, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = WarnOnChange=true und mindestens eine Änderung im Zeitraum.
    EN: Reads MsiInstaller events (Application log) with IDs 11707 (install succeeded), 11724 (removal
        succeeded), 1033 (install result) and 1034 (removal result) via Get-WinEvent -FilterHashtable with
        StartTime and MaxEvents. For 1033/1034 product name, version, manufacturer and status come from the
        event properties (locale-independent); for 11707/11724 the product name is parsed from the text
        "<Product>: <name> -- ..." (localized prefix, parsed generically). No user SIDs. Non-MSI installers
        (EXE/AppX) are not covered. No events is not an error. Bounded list (4000 characters).
        Exit 0 = informational, 1 = input, query or write error,
        2 = WarnOnChange=true and at least one change in the period.
.PARAMETER Days
    DE: NinjaOne Integer softwareChangesDays; 1..90; Standard 7.
    EN: NinjaOne Integer softwareChangesDays; 1..90; default 7.
.PARAMETER MaxEvents
    DE: NinjaOne Integer softwareChangesMaxEvents; 1..500; Standard 100.
    EN: NinjaOne Integer softwareChangesMaxEvents; 1..500; default 100.
.PARAMETER WarnOnChange
    DE: NinjaOne Checkbox/Text softwareChangesWarnOnChange; true/false; Standard false.
    EN: NinjaOne checkbox/text softwareChangesWarnOnChange; true/false; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readRecentSoftwareChanges.ps1
    DE: MSI-Änderungen der letzten 7 Tage (max. 100 Ereignisse), immer Exit 0.
    EN: MSI changes of the last 7 days (max. 100 events), always exit 0.
.EXAMPLE
    .\readRecentSoftwareChanges.ps1 -Days 1 -WarnOnChange true -CustomField softwareChanges
    DE: Exit 2 bei Änderungen in den letzten 24 Stunden; JSON in softwareChanges.
    EN: Exit 2 on changes within the last 24 hours; JSON to softwareChanges.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = Änderungen gefunden (nur mit WarnOnChange).
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = changes found (only with WarnOnChange).
#>
[CmdletBinding()]
param(
    [string]$Days = $env:softwareChangesDays,
    [string]$MaxEvents = $env:softwareChangesMaxEvents,
    [string]$WarnOnChange = $env:softwareChangesWarnOnChange,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function Get-PropertyText {
    param($EventRecord, [int]$Index)
    $properties = @($EventRecord.Properties)
    if ($properties.Count -le $Index -or $null -eq $properties[$Index]) { return $null }
    $text = ([string]$properties[$Index].Value).Trim()
    if ($text.Length -gt 200) { $text = $text.Substring(0, 200) }
    return $text
}
try {
    $Days = Resolve-Setting $Days '7'
    $MaxEvents = Resolve-Setting $MaxEvents '100'
    $WarnOnChange = Resolve-Setting $WarnOnChange 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $dayCount = 0
    if (-not [int]::TryParse($Days, [ref]$dayCount) -or $dayCount -lt 1 -or $dayCount -gt 90) { throw 'softwareChangesDays: 1..90.' }
    $eventLimit = 0
    if (-not [int]::TryParse($MaxEvents, [ref]$eventLimit) -or $eventLimit -lt 1 -or $eventLimit -gt 500) { throw 'softwareChangesMaxEvents: 1..500.' }
    $warn = $false
    if (-not [bool]::TryParse($WarnOnChange, [ref]$warn)) { throw 'softwareChangesWarnOnChange: true/false.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }

    $start = (Get-Date).AddDays(-$dayCount)
    $filter = @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = @(11707, 11724, 1033, 1034); StartTime = $start }
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $eventLimit -ErrorAction Stop) }
    catch {
        # DE: Keine Treffer ist kein Fehler. EN: No matching events is not an error.
        if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound' -and $_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
    $actions = @{ 11707 = 'Install'; 11724 = 'Uninstall'; 1033 = 'InstallResult'; 1034 = 'RemovalResult' }
    $changes = @(foreach ($record in $events) {
        $id = [int]$record.Id
        $item = [ordered]@{
            TimeUtc = ([datetime]$record.TimeCreated).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            EventId = $id; Action = $actions[$id]; Product = $null; Version = $null; Manufacturer = $null; Status = $null
        }
        if ($id -eq 1033 -or $id -eq 1034) {
            $item.Product = Get-PropertyText $record 0
            $item.Version = Get-PropertyText $record 1
            $item.Status = Get-PropertyText $record 3
            $item.Manufacturer = Get-PropertyText $record 4
        } else {
            $text = Get-PropertyText $record 0
            $match = [regex]::Match([string]$text, '^[^:]{1,40}:\s*(.+?)\s+--\s')
            $item.Product = if ($match.Success) { $match.Groups[1].Value } else { $text }
            $item.Status = '0'
        }
        [pscustomobject]$item
    })
    $records = $changes
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Days = $dayCount; StartTimeUtc = $start.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            MaxEvents = $eventLimit; TotalEvents = $changes.Count; EventLimitReached = $changes.Count -ge $eventLimit
            ReportedRecords = $records.Count; Truncated = $records.Count -lt $changes.Count; Changes = $records
        })
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
    if ($warn -and $changes.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
