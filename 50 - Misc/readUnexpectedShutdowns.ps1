#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet unerwartete Herunterfahr-Vorgänge (Kernel-Power 41, EventLog 6008).
    EN: Reports unexpected shutdowns (Kernel-Power 41, EventLog 6008).
.DESCRIPTION
    DE: Liest im System-Log Microsoft-Windows-Kernel-Power 41 und EventLog 6008 im
        Zeitraum LookbackDays (je Abfrage max. 1000 Ereignisse, EventCapReached).
        Ein Vorfall erzeugt meist beide Ereignisse; daher gilt als geschätzte Anzahl
        EstimatedIncidents = Maximum der beiden Zählwerte. Für Ereignis 41 wird der
        BugcheckCode (EventData-Index 0, hex) mit ausgegeben. Keine Message, keine
        Benutzer. JSON, max. 4000 Zeichen (Liste wird gekürzt). Nur lesend.
    EN: Reads Microsoft-Windows-Kernel-Power 41 and EventLog 6008 from the System log
        within LookbackDays (max. 1000 events per query, EventCapReached). One incident
        usually logs both events; therefore EstimatedIncidents = maximum of both counts.
        For event 41 the BugcheckCode (EventData index 0, hex) is included. No message,
        no users. JSON, max. 4000 characters (list is shortened). Read-only.
.PARAMETER LookbackDays
    DE: NinjaOne Integer shutdownLookbackDays, 1..365; Standard 30.
    EN: NinjaOne Integer shutdownLookbackDays, 1..365; default 30.
.PARAMETER Threshold
    DE: NinjaOne Integer shutdownThreshold, 1..1000; Standard 1 (Vergleich mit EstimatedIncidents).
    EN: NinjaOne Integer shutdownThreshold, 1..1000; default 1 (compared with EstimatedIncidents).
.PARAMETER MaxRecords
    DE: NinjaOne Integer shutdownMaxRecords, 1..100; Standard 20.
    EN: NinjaOne Integer shutdownMaxRecords, 1..100; default 20.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readUnexpectedShutdowns.ps1
    DE: Warnt bei mindestens einem unerwarteten Herunterfahren in 30 Tagen.
    EN: Warns on at least one unexpected shutdown within 30 days.
.EXAMPLE
    .\readUnexpectedShutdowns.ps1 -LookbackDays 7 -Threshold 3 -CustomField shutdownReport
    DE: Warnt ab 3 Vorfällen in 7 Tagen; JSON in shutdownReport.
    EN: Warns from 3 incidents within 7 days; JSON to shutdownReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = unter Grenzwert, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = EstimatedIncidents >= Threshold.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = below threshold, 1 = input/query/write error,
        2 = EstimatedIncidents >= Threshold.
#>
[CmdletBinding()]
param(
    [string]$LookbackDays = $env:shutdownLookbackDays,
    [string]$Threshold = $env:shutdownThreshold,
    [string]$MaxRecords = $env:shutdownMaxRecords,
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
    $days = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $LookbackDays '30') 'shutdownLookbackDays' 1 365
    $minimum = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $Threshold '1') 'shutdownThreshold' 1 1000
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '20') 'shutdownMaxRecords' 1 100
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $cap = 1000
    $start = (Get-Date).AddDays(-$days)
    $power = @(Get-BoundedEvent @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $start } $cap)
    $dirty = @(Get-BoundedEvent @{ LogName = 'System'; ProviderName = 'EventLog'; Id = 6008; StartTime = $start } $cap)
    $all = @(@($power) + @($dirty) | Sort-Object TimeCreated -Descending | ForEach-Object {
        $code = ''
        $value = [uint64]0
        if ($_.Id -eq 41 -and @($_.Properties).Count -gt 0 -and [uint64]::TryParse([string]$_.Properties[0].Value, [ref]$value)) { $code = '0x{0:X8}' -f $value }
        [pscustomobject]@{ TimeUtc = $_.TimeCreated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Id = $_.Id; BugcheckCode = $code }
    })
    $incidents = [Math]::Max($power.Count, $dirty.Count)
    $shown = $limit
    do {
        $records = @($all | Select-Object -First $shown)
        $report = [ordered]@{
            LookbackDays = $days; StartTimeUtc = $start.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Threshold = $minimum
            KernelPower41Count = $power.Count; EventLog6008Count = $dirty.Count; EstimatedIncidents = $incidents
            EventCapReached = ($power.Count -ge $cap -or $dirty.Count -ge $cap)
            ReportedRecords = $records.Count; Truncated = ($records.Count -lt $all.Count); Events = $records
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
    if ($incidents -ge $minimum) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
