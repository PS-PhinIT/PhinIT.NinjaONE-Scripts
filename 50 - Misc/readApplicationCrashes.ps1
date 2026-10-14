#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Anwendungsabstürze und -hänger, gruppiert nach Anwendung.
    EN: Reports application crashes and hangs grouped by application.
.DESCRIPTION
    DE: Liest im Application-Log "Application Error" 1000 (Absturz) und
        "Application Hang" 1002 (Hänger) im Zeitraum LookbackDays (je Abfrage max.
        2000 Ereignisse, EventCapReached). Der Name der fehlerhaften Anwendung wird aus
        Property-Index 0 der Ereignisdaten gelesen (bei 1000 und 1002 ist das der
        Programmname, z. B. explorer.exe); Steuerzeichen werden entfernt, Länge max. 100.
        Keine Pfade, Module, Message oder Benutzer. Ausgabe der Top-N-Anwendungen als
        JSON, max. 4000 Zeichen (Liste wird gekürzt). Nur lesend.
    EN: Reads "Application Error" 1000 (crash) and "Application Hang" 1002 (hang) from
        the Application log within LookbackDays (max. 2000 events per query,
        EventCapReached). The faulting application name is read from event data
        property index 0 (for 1000 and 1002 this is the program name, e.g.
        explorer.exe); control characters are removed, max. length 100. No paths,
        modules, message or users. Outputs the top N applications as JSON, max. 4000
        characters (list is shortened). Read-only.
.PARAMETER LookbackDays
    DE: NinjaOne Integer appCrashLookbackDays, 1..90; Standard 7.
    EN: NinjaOne Integer appCrashLookbackDays, 1..90; default 7.
.PARAMETER Threshold
    DE: NinjaOne Integer appCrashThreshold, 1..10000; Standard 10 (Summe Abstürze+Hänger).
    EN: NinjaOne Integer appCrashThreshold, 1..10000; default 10 (sum of crashes+hangs).
.PARAMETER Top
    DE: NinjaOne Integer appCrashTopApps, 1..50; Standard 10.
    EN: NinjaOne Integer appCrashTopApps, 1..50; default 10.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readApplicationCrashes.ps1
    DE: Top 10 der Anwendungen mit Abstürzen/Hängern der letzten 7 Tage.
    EN: Top 10 applications with crashes/hangs in the last 7 days.
.EXAMPLE
    .\readApplicationCrashes.ps1 -LookbackDays 30 -Threshold 25 -Top 5 -CustomField appCrashReport
    DE: 30 Tage, Warnung ab 25 Ereignissen, Top 5; JSON in appCrashReport.
    EN: 30 days, warning from 25 events, top 5; JSON to appCrashReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = unter Grenzwert, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = Summe der Ereignisse >= Threshold.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = below threshold, 1 = input/query/write error,
        2 = total events >= Threshold.
#>
[CmdletBinding()]
param(
    [string]$LookbackDays = $env:appCrashLookbackDays,
    [string]$Threshold = $env:appCrashThreshold,
    [string]$Top = $env:appCrashTopApps,
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
function Get-BoundedEvent {
    param([hashtable]$Filter, [int]$MaxEvents)
    try { Get-WinEvent -FilterHashtable $Filter -MaxEvents $MaxEvents -ErrorAction Stop }
    catch {
        # DE: Nur "keine Treffer" ist kein Fehler. EN: Only "no matches" is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
}
try {
    $days = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $LookbackDays '7') 'appCrashLookbackDays' 1 90
    $minimum = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $Threshold '10') 'appCrashThreshold' 1 10000
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $Top '10') 'appCrashTopApps' 1 50
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $cap = 2000
    $start = (Get-Date).AddDays(-$days)
    $crashes = @(Get-BoundedEvent @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $start } $cap)
    $hangs = @(Get-BoundedEvent @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $start } $cap)
    $groups = @{}
    foreach ($evt in @($crashes) + @($hangs)) {
        $name = ''
        if (@($evt.Properties).Count -gt 0) { $name = ([string]$evt.Properties[0].Value) -replace '[\x00-\x1F\x7F]', '' }
        $name = $name.Trim()
        if (-not $name) { $name = 'Unknown' }
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) }
        $key = $name.ToLowerInvariant()
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{ Application = $name; Crashes = 0; Hangs = 0; Total = 0; LastUtc = [datetime]::MinValue }
        }
        $entry = $groups[$key]
        if ($evt.Id -eq 1000) { $entry.Crashes++ } else { $entry.Hangs++ }
        $entry.Total++
        $time = $evt.TimeCreated.ToUniversalTime()
        if ($time -gt $entry.LastUtc) { $entry.LastUtc = $time }
    }
    $ranked = @($groups.Values | Sort-Object @{ Expression = 'Total'; Descending = $true }, Application | ForEach-Object {
        [pscustomobject]@{ Application = $_.Application; Crashes = $_.Crashes; Hangs = $_.Hangs; Total = $_.Total; LastUtc = $_.LastUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    })
    $total = $crashes.Count + $hangs.Count
    $shown = $limit
    do {
        $records = @($ranked | Select-Object -First $shown)
        $report = [ordered]@{
            LookbackDays = $days; StartTimeUtc = $start.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Threshold = $minimum
            CrashEvents = $crashes.Count; HangEvents = $hangs.Count; TotalEvents = $total
            EventCapReached = ($crashes.Count -ge $cap -or $hangs.Count -ge $cap); DistinctApplications = $ranked.Count
            ReportedApplications = $records.Count; Truncated = ($records.Count -lt $ranked.Count); Applications = $records
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
    if ($total -ge $minimum) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
