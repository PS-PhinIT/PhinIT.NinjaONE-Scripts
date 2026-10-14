#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet abgestürzte und fehlerhafte Windows-Dienste, gruppiert nach Dienst.
    EN: Reports crashed and failing Windows services grouped by service.
.DESCRIPTION
    DE: Liest im System-Log "Service Control Manager" 7031 und 7034 (unerwartet beendet)
        sowie 7023 und 7024 (Dienst mit Fehler beendet) im Zeitraum LookbackDays (max.
        2000 Ereignisse, EventCapReached). Der Dienstname stammt aus Property-Index 0
        (Anzeigename des Dienstes); Steuerzeichen werden entfernt, Länge max. 100.
        Keine Message, keine Fehlertexte. JSON, max. 4000 Zeichen (Liste wird
        gekürzt). Nur lesend.
    EN: Reads "Service Control Manager" 7031 and 7034 (terminated unexpectedly) and
        7023 and 7024 (service terminated with error) from the System log within
        LookbackDays (max. 2000 events, EventCapReached). The service name comes from
        property index 0 (service display name); control characters are removed, max.
        length 100. No message, no error text. JSON, max. 4000 characters (list is
        shortened). Read-only.
.PARAMETER LookbackDays
    DE: NinjaOne Integer serviceCrashLookbackDays, 1..90; Standard 7.
    EN: NinjaOne Integer serviceCrashLookbackDays, 1..90; default 7.
.PARAMETER MaxRecords
    DE: NinjaOne Integer serviceCrashMaxRecords, 1..100; Standard 25 (Dienste).
    EN: NinjaOne Integer serviceCrashMaxRecords, 1..100; default 25 (services).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readServiceCrashes.ps1
    DE: Dienstabstürze/-fehler der letzten 7 Tage, max. 25 Dienste.
    EN: Service crashes/errors from the last 7 days, max. 25 services.
.EXAMPLE
    .\readServiceCrashes.ps1 -LookbackDays 30 -MaxRecords 10 -CustomField serviceCrashReport
    DE: 30 Tage, 10 Dienste; JSON in serviceCrashReport.
    EN: 30 days, 10 services; JSON to serviceCrashReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = keine Ereignisse, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = mindestens ein Ereignis 7023/7024/7031/7034.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = no events, 1 = input/query/write error,
        2 = at least one 7023/7024/7031/7034 event.
#>
[CmdletBinding()]
param(
    [string]$LookbackDays = $env:serviceCrashLookbackDays,
    [string]$MaxRecords = $env:serviceCrashMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-CleanSetting {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInteger {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
        $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0}: {1}..{2} erforderlich / required.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
try {
    $days = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $LookbackDays '7') 'serviceCrashLookbackDays' 1 90
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '25') 'serviceCrashMaxRecords' 1 100
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $cap = 2000
    $start = (Get-Date).AddDays(-$days)
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = @(7023, 7024, 7031, 7034); StartTime = $start } -MaxEvents $cap -ErrorAction Stop)
    }
    catch {
        # DE: Nur "keine Treffer" ist kein Fehler. EN: Only "no matches" is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
    $groups = @{}
    foreach ($evt in $events) {
        $name = ''
        if (@($evt.Properties).Count -gt 0) { $name = ([string]$evt.Properties[0].Value) -replace '[\x00-\x1F\x7F]', '' }
        $name = $name.Trim()
        if (-not $name) { $name = 'Unknown' }
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) }
        $key = $name.ToLowerInvariant()
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{ Service = $name; UnexpectedTerminations = 0; ErrorTerminations = 0; Total = 0; LastUtc = [datetime]::MinValue }
        }
        $entry = $groups[$key]
        if ($evt.Id -in @(7031, 7034)) { $entry.UnexpectedTerminations++ } else { $entry.ErrorTerminations++ }
        $entry.Total++
        $time = $evt.TimeCreated.ToUniversalTime()
        if ($time -gt $entry.LastUtc) { $entry.LastUtc = $time }
    }
    $ranked = @($groups.Values | Sort-Object @{ Expression = 'Total'; Descending = $true }, Service | ForEach-Object {
        [pscustomobject]@{
            Service = $_.Service; UnexpectedTerminations = $_.UnexpectedTerminations; ErrorTerminations = $_.ErrorTerminations
            Total = $_.Total; LastUtc = $_.LastUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    })
    $shown = $limit
    do {
        $records = @($ranked | Select-Object -First $shown)
        $report = [ordered]@{
            LookbackDays = $days; StartTimeUtc = $start.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            TotalEvents = $events.Count; EventCapReached = ($events.Count -ge $cap); DistinctServices = $ranked.Count
            ReportedServices = $records.Count; Truncated = ($records.Count -lt $ranked.Count); Services = $records
        } | ConvertTo-Json -Depth 4 -Compress
        if ($report.Length -le 4000) { break }
        if ($shown -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $shown--
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($events.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
