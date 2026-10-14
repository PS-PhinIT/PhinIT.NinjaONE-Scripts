#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest den Windows-Zuverlässigkeitsindex (1..10) und seinen Verlauf.
    EN: Reads the Windows reliability (stability) index (1..10) and its trend.
.DESCRIPTION
    DE: Liest Win32_ReliabilityStabilityMetrics per CIM (TimeGenerated ab Beginn des
        Zeitraums) und meldet den neuesten SystemStabilityIndex sowie je Tag (UTC) den
        letzten und kleinsten Wert und die Veränderung im Zeitraum. Die
        Zuverlässigkeitsdaten können deaktiviert sein (z. B. Server ohne
        Richtlinie "Reliability WMI-Anbieter konfigurieren" oder deaktivierte Aufgabe
        \Microsoft\Windows\RAC\RacTask) oder es liegen im Zeitraum keine Werte vor:
        dann Available=false/Status NotAvailable und Exit 0 (kein Befund). JSON,
        max. 4000 Zeichen (Verlauf wird gekürzt). Nur lesend.
    EN: Reads Win32_ReliabilityStabilityMetrics via CIM (TimeGenerated since the start
        of the range) and reports the latest SystemStabilityIndex plus per day (UTC)
        the last and minimum value and the change within the range. Reliability data
        may be disabled (e.g. servers without the "Configure Reliability WMI
        Provider" policy or a disabled \Microsoft\Windows\RAC\RacTask task) or no
        values exist in the range: then Available=false/Status NotAvailable and exit 0
        (no finding). JSON, max. 4000 characters (trend is shortened). Read-only.
.PARAMETER MinimumIndex
    DE: NinjaOne Text reliabilityMinimumIndex, 1.0..10.0 (Punkt als Dezimaltrenner); Standard 5.0.
    EN: NinjaOne Text reliabilityMinimumIndex, 1.0..10.0 (dot as decimal separator); default 5.0.
.PARAMETER LookbackDays
    DE: NinjaOne Integer reliabilityLookbackDays, 1..90; Standard 7.
    EN: NinjaOne Integer reliabilityLookbackDays, 1..90; default 7.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readReliabilityIndex.ps1
    DE: Warnt, wenn der aktuelle Index unter 5.0 liegt; Verlauf 7 Tage.
    EN: Warns if the current index is below 5.0; 7-day trend.
.EXAMPLE
    .\readReliabilityIndex.ps1 -MinimumIndex 7.5 -LookbackDays 30 -CustomField reliabilityReport
    DE: Grenzwert 7.5, Verlauf 30 Tage; JSON in reliabilityReport.
    EN: Threshold 7.5, 30-day trend; JSON to reliabilityReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Index >= Grenzwert oder Daten nicht verfügbar (Available=false),
        1 = Eingabe-/Abfrage-/Schreibfehler, 2 = neuester Index < MinimumIndex.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = index >= threshold or data not available (Available=false),
        1 = input/query/write error, 2 = latest index < MinimumIndex.
#>
[CmdletBinding()]
param(
    [string]$MinimumIndex = $env:reliabilityMinimumIndex,
    [string]$LookbackDays = $env:reliabilityLookbackDays,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MinimumIndex = ([string]$MinimumIndex).Trim()
    $LookbackDays = ([string]$LookbackDays).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($MinimumIndex -ieq 'null' -or -not $MinimumIndex) { $MinimumIndex = '5.0' }
    if ($LookbackDays -ieq 'null' -or -not $LookbackDays) { $LookbackDays = '7' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $minimum = 0.0
    if ($MinimumIndex -notmatch '^\d{1,2}(\.\d{1,2})?$' -or -not [double]::TryParse($MinimumIndex, [Globalization.NumberStyles]::AllowDecimalPoint, $invariant, [ref]$minimum) -or
        $minimum -lt 1 -or $minimum -gt 10) {
        throw 'reliabilityMinimumIndex: 1.0..10.0 erforderlich / required.'
    }
    $days = 0
    if (-not [int]::TryParse($LookbackDays, [Globalization.NumberStyles]::None, $invariant, [ref]$days) -or $days -lt 1 -or $days -gt 90) {
        throw 'reliabilityLookbackDays: 1..90 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $startUtc = (Get-Date).ToUniversalTime().AddDays(-$days)
    $dmtf = $startUtc.ToString('yyyyMMddHHmmss', $invariant) + '.000000+000'
    $metrics = @()
    $available = $true
    try {
        $metrics = @(Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -Filter ("TimeGenerated >= '{0}'" -f $dmtf) -ErrorAction Stop |
            Where-Object { $null -ne $_.SystemStabilityIndex -and $null -ne $_.TimeGenerated } |
            Sort-Object TimeGenerated -Descending)
    }
    catch {
        # DE: Fehlende Klasse/keine Instanzen = Funktion deaktiviert. EN: Missing class/no instances = feature disabled.
        $text = '{0} {1}' -f $_.FullyQualifiedErrorId, $_.Exception.Message
        if ($text -notmatch '(?i)InvalidClass|Invalid class|NotFound|Not found|0x80041010|0x80041002') { throw }
        $available = $false
    }
    if ($metrics.Count -eq 0) { $available = $false }
    $latest = $null
    $latestTime = ''
    $change = $null
    $trend = @()
    if ($available) {
        $latest = [Math]::Round([double]$metrics[0].SystemStabilityIndex, 2)
        $latestTime = $metrics[0].TimeGenerated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $change = [Math]::Round($latest - [double]$metrics[-1].SystemStabilityIndex, 2)
        $trend = @($metrics | Group-Object { $_.TimeGenerated.ToUniversalTime().ToString('yyyy-MM-dd') } | Sort-Object Name -Descending | ForEach-Object {
            $values = @($_.Group | ForEach-Object { [double]$_.SystemStabilityIndex })
            [pscustomobject]@{ Date = $_.Name; Last = [Math]::Round($values[0], 2); Min = [Math]::Round(($values | Measure-Object -Minimum).Minimum, 2) }
        })
    }
    $status = 'NotAvailable'
    if ($available) { $status = 'OK'; if ($latest -lt $minimum) { $status = 'BelowThreshold' } }
    $shown = $trend.Count
    do {
        $records = @($trend | Select-Object -First $shown)
        $report = [ordered]@{
            Available = $available; Status = $status; MinimumIndex = $minimum; LookbackDays = $days
            LatestIndex = $latest; LatestTimeUtc = $latestTime; ChangeInRange = $change; Samples = $metrics.Count
            TrendTruncated = ($records.Count -lt $trend.Count); DailyTrend = $records
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
    if ($status -eq 'BelowThreshold') { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
