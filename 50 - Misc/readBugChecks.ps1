#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Bluescreens (BugChecks) und Minidump-Dateien der letzten Tage.
    EN: Reports blue screens (bug checks) and minidump files from recent days.
.DESCRIPTION
    DE: Liest im System-Log Microsoft-Windows-WER-SystemErrorReporting 1001 (BugCheck;
        Code aus Property-Index 0, Text "0x...") und Microsoft-Windows-Kernel-Power 41
        mit BugcheckCode ungleich 0 (EventData-Index 0) im Zeitraum LookbackDays.
        Je Abfrage höchstens 500 Ereignisse (EventCapReached). Ein Absturz erzeugt oft
        beide Ereignisse; gezählt werden Ereignisse, nicht Vorfälle. Zusätzlich Anzahl und
        neueste Dateien in %SystemRoot%\Minidump\*.dmp (nur Name, Datum, Größe; Inhalte
        werden nicht gelesen). JSON, max. 4000 Zeichen (Listen werden gekürzt). Nur lesend.
    EN: Reads Microsoft-Windows-WER-SystemErrorReporting 1001 (bug check; code from
        property index 0, text "0x...") and Microsoft-Windows-Kernel-Power 41 with
        BugcheckCode not 0 (EventData index 0) from the System log within LookbackDays.
        At most 500 events per query (EventCapReached). One crash often logs both events;
        events are counted, not incidents. Also reports count and newest files in
        %SystemRoot%\Minidump\*.dmp (name, date, size only; contents are never read).
        JSON, max. 4000 characters (lists are shortened). Read-only.
.PARAMETER LookbackDays
    DE: NinjaOne Integer bugCheckLookbackDays, 1..365; Standard 30.
    EN: NinjaOne Integer bugCheckLookbackDays, 1..365; default 30.
.PARAMETER MaxRecords
    DE: NinjaOne Integer bugCheckMaxRecords, 1..50; Standard 10 (je Liste).
    EN: NinjaOne Integer bugCheckMaxRecords, 1..50; default 10 (per list).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readBugChecks.ps1
    DE: BugChecks und Minidumps der letzten 30 Tage.
    EN: Bug checks and minidumps from the last 30 days.
.EXAMPLE
    .\readBugChecks.ps1 -LookbackDays 7 -MaxRecords 5 -CustomField bugCheckReport
    DE: Letzte 7 Tage, je 5 Einträge; JSON in bugCheckReport.
    EN: Last 7 days, 5 entries each; JSON to bugCheckReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = keine BugChecks/Minidumps im Zeitraum, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = mindestens ein BugCheck-Ereignis oder ein Minidump mit Datum im Zeitraum.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = no bug checks/minidumps in range, 1 = input/query/write error,
        2 = at least one bug check event or a minidump dated within the range.
#>
[CmdletBinding()]
param(
    [string]$LookbackDays = $env:bugCheckLookbackDays,
    [string]$MaxRecords = $env:bugCheckMaxRecords,
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
    $days = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $LookbackDays '30') 'bugCheckLookbackDays' 1 365
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '10') 'bugCheckMaxRecords' 1 50
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) { throw 'Get-WinEvent fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { throw 'SystemRoot fehlt / is missing.' }
    $cap = 500
    $start = (Get-Date).AddDays(-$days)
    $wer = @(Get-BoundedEvent @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $start } $cap)
    $power = @(Get-BoundedEvent @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $start } $cap)
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($evt in $wer) {
        $code = ''
        if (@($evt.Properties).Count -gt 0 -and ([string]$evt.Properties[0].Value) -match '0x[0-9A-Fa-f]{1,16}') { $code = $Matches[0] }
        $found.Add([pscustomobject]@{ TimeUtc = $evt.TimeCreated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Source = 'WER-1001'; BugcheckCode = $code })
    }
    foreach ($evt in $power) {
        $value = [uint64]0
        if (@($evt.Properties).Count -eq 0 -or -not [uint64]::TryParse([string]$evt.Properties[0].Value, [ref]$value) -or $value -eq 0) { continue }
        $found.Add([pscustomobject]@{ TimeUtc = $evt.TimeCreated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Source = 'KernelPower-41'; BugcheckCode = ('0x{0:X8}' -f $value) })
    }
    $events = @($found | Sort-Object TimeUtc -Descending)
    $dumpDir = $env:SystemRoot.TrimEnd('\') + '\Minidump'
    $dumps = @()
    if (Test-Path -LiteralPath $dumpDir -PathType Container) {
        $dumps = @(Get-ChildItem -LiteralPath $dumpDir -Filter '*.dmp' -Force -ErrorAction Stop | Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTimeUtc -Descending)
    }
    $startUtc = $start.ToUniversalTime()
    $recentDumps = @($dumps | Where-Object { $_.LastWriteTimeUtc -ge $startUtc })
    $latest = ''
    if ($dumps.Count -gt 0) { $latest = $dumps[0].LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $shown = $limit
    do {
        $eventRecords = @($events | Select-Object -First $shown)
        $dumpRecords = @($dumps | Select-Object -First $shown | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; LastWriteUtc = $_.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'); SizeKB = [Math]::Round($_.Length / 1KB, 0) }
        })
        $report = [ordered]@{
            LookbackDays = $days; StartTimeUtc = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
            BugCheckEventCount = $events.Count; EventCapReached = ($wer.Count -ge $cap -or $power.Count -ge $cap)
            MinidumpCount = $dumps.Count; RecentMinidumpCount = $recentDumps.Count; LatestMinidumpUtc = $latest
            Truncated = ($eventRecords.Count -lt $events.Count -or $dumpRecords.Count -lt $dumps.Count)
            Events = $eventRecords; Minidumps = $dumpRecords
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
    if ($events.Count -gt 0 -or $recentDumps.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
