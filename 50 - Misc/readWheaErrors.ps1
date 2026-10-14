#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet WHEA-Hardwarefehler (korrigiert/schwerwiegend) aus dem System-Log.
    EN: Reports WHEA hardware errors (corrected/fatal) from the System log.
.DESCRIPTION
    DE: Liest Microsoft-Windows-WHEA-Logger im System-Log im Zeitraum LookbackDays
        (max. 5000 Ereignisse, EventCapReached) und gruppiert nach Id und Level.
        Einstufung: Level 1 (Kritisch) und 2 (Fehler) = Fatal (nicht korrigiert,
        z. B. Id 1/18), Level 3 (Warnung) = Corrected (z. B. Id 17/19/47), sonst
        Informational. Keine Message oder Rohdaten. JSON, max. 4000 Zeichen.
        Nur lesend.
    EN: Reads Microsoft-Windows-WHEA-Logger from the System log within LookbackDays
        (max. 5000 events, EventCapReached) and groups by Id and level.
        Classification: level 1 (critical) and 2 (error) = Fatal (uncorrected, e.g.
        Id 1/18), level 3 (warning) = Corrected (e.g. Id 17/19/47), otherwise
        Informational. No message or raw data. JSON, max. 4000 characters. Read-only.
.PARAMETER LookbackDays
    DE: NinjaOne Integer wheaLookbackDays, 1..365; Standard 30.
    EN: NinjaOne Integer wheaLookbackDays, 1..365; default 30.
.PARAMETER CorrectedThreshold
    DE: NinjaOne Integer wheaCorrectedThreshold, 1..100000; Standard 10.
    EN: NinjaOne Integer wheaCorrectedThreshold, 1..100000; default 10.
.PARAMETER MaxRecords
    DE: NinjaOne Integer wheaMaxRecords, 1..50; Standard 20 (Gruppen).
    EN: NinjaOne Integer wheaMaxRecords, 1..50; default 20 (groups).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readWheaErrors.ps1
    DE: WHEA-Ereignisse der letzten 30 Tage; Warnung bei Fatal oder >= 10 korrigierten.
    EN: WHEA events from the last 30 days; warning on fatal or >= 10 corrected.
.EXAMPLE
    .\readWheaErrors.ps1 -LookbackDays 7 -CorrectedThreshold 1 -CustomField wheaReport
    DE: 7 Tage, jede WHEA-Warnung meldet; JSON in wheaReport.
    EN: 7 days, any WHEA warning is reported; JSON to wheaReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = unauffällig, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = mindestens ein Fatal-Ereignis oder Corrected >= CorrectedThreshold.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = no finding, 1 = input/query/write error,
        2 = at least one fatal event or corrected >= CorrectedThreshold.
#>
[CmdletBinding()]
param(
    [string]$LookbackDays = $env:wheaLookbackDays,
    [string]$CorrectedThreshold = $env:wheaCorrectedThreshold,
    [string]$MaxRecords = $env:wheaMaxRecords,
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
    $days = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $LookbackDays '30') 'wheaLookbackDays' 1 365
    $minimum = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $CorrectedThreshold '10') 'wheaCorrectedThreshold' 1 100000
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '20') 'wheaMaxRecords' 1 50
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $cap = 5000
    $start = (Get-Date).AddDays(-$days)
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $start } -MaxEvents $cap -ErrorAction Stop)
    }
    catch {
        # DE: Nur "keine Treffer" ist kein Fehler. EN: Only "no matches" is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
    $fatal = 0
    $corrected = 0
    $groups = @{}
    foreach ($evt in $events) {
        $level = [int]$evt.Level
        $severity = 'Informational'
        if ($level -in @(1, 2)) { $severity = 'Fatal'; $fatal++ }
        elseif ($level -eq 3) { $severity = 'Corrected'; $corrected++ }
        $key = '{0}|{1}' -f $evt.Id, $level
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{ Id = [int]$evt.Id; Level = $level; Severity = $severity; Count = 0; LastUtc = [datetime]::MinValue }
        }
        $entry = $groups[$key]
        $entry.Count++
        $time = $evt.TimeCreated.ToUniversalTime()
        if ($time -gt $entry.LastUtc) { $entry.LastUtc = $time }
    }
    $ranked = @($groups.Values | Sort-Object Level, @{ Expression = 'Count'; Descending = $true }, Id | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Level = $_.Level; Severity = $_.Severity; Count = $_.Count; LastUtc = $_.LastUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    })
    $shown = $limit
    do {
        $records = @($ranked | Select-Object -First $shown)
        $report = [ordered]@{
            LookbackDays = $days; StartTimeUtc = $start.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); CorrectedThreshold = $minimum
            TotalEvents = $events.Count; FatalEvents = $fatal; CorrectedEvents = $corrected
            InformationalEvents = ($events.Count - $fatal - $corrected); EventCapReached = ($events.Count -ge $cap)
            ReportedGroups = $records.Count; Truncated = ($records.Count -lt $ranked.Count); Groups = $records
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
    if ($fatal -gt 0 -or $corrected -ge $minimum) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
