#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Misst die CPU-Auslastung über mehrere Stichproben und warnt über einem Grenzwert.
    EN: Samples CPU load over several samples and warns above a threshold.
.DESCRIPTION
    DE: Liest Win32_PerfFormattedData_PerfOS_Processor (Instanz _Total) per CIM
        SampleCount-mal im Abstand von SampleIntervalSeconds und gibt Minimum,
        Maximum, Mittelwert und Einzelwerte als JSON aus. Optionaler Export in ein
        MultiLine-Feld (max. 4000 Zeichen). Gesamtlaufzeit ist auf 120 Sekunden
        begrenzt. Exit 0 = Mittelwert <= ThresholdPercent, 1 = Eingabe-, Abfrage-
        oder Schreibfehler, 2 = Mittelwert über ThresholdPercent. Nur lesend.
        Hinweis: Der erste formatierte Leistungswert kann systembedingt 0 sein;
        mehrere Stichproben verwenden.
    EN: Reads Win32_PerfFormattedData_PerfOS_Processor (instance _Total) via CIM
        SampleCount times, SampleIntervalSeconds apart, and outputs minimum,
        maximum, average and individual samples as JSON. Optional export to a
        MultiLine field (max. 4000 characters). Total runtime is bounded to 120
        seconds. Exit 0 = average <= ThresholdPercent, 1 = input, query or write
        error, 2 = average above ThresholdPercent. Read-only.
        Note: the first formatted performance value may be 0 by design; use
        several samples.
.PARAMETER ThresholdPercent
    DE: NinjaOne Integer systemCpuThresholdPercent, 1..100; Standard 90.
    EN: NinjaOne Integer systemCpuThresholdPercent, 1..100; default 90.
.PARAMETER SampleCount
    DE: NinjaOne Integer systemCpuSampleCount, 1..30; Standard 5.
    EN: NinjaOne Integer systemCpuSampleCount, 1..30; default 5.
.PARAMETER SampleIntervalSeconds
    DE: NinjaOne Integer systemCpuSampleIntervalSeconds, 1..10; Standard 2.
        SampleCount * SampleIntervalSeconds darf 120 nicht überschreiten.
    EN: NinjaOne Integer systemCpuSampleIntervalSeconds, 1..10; default 2.
        SampleCount * SampleIntervalSeconds must not exceed 120.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readCpuUsage.ps1
    DE: 5 Stichproben im Abstand von 2 s; Warnung über 90 % im Mittel.
    EN: 5 samples 2 s apart; warning above 90% on average.
.EXAMPLE
    .\readCpuUsage.ps1 -ThresholdPercent 75 -SampleCount 10 -SampleIntervalSeconds 3 -CustomField cpuUsage
    DE: 10 Stichproben, Grenzwert 75 %, JSON ins Feld cpuUsage.
    EN: 10 samples, threshold 75%, JSON to the field cpuUsage.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = hohe CPU-Last. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = high CPU load. Read-only.
#>
[CmdletBinding()]
param(
    [string]$ThresholdPercent = $env:systemCpuThresholdPercent,
    [string]$SampleCount = $env:systemCpuSampleCount,
    [string]$SampleIntervalSeconds = $env:systemCpuSampleIntervalSeconds,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $ThresholdPercent = ([string]$ThresholdPercent).Trim()
    $SampleCount = ([string]$SampleCount).Trim()
    $SampleIntervalSeconds = ([string]$SampleIntervalSeconds).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $ThresholdPercent -or $ThresholdPercent -ieq 'null') { $ThresholdPercent = '90' }
    if (-not $SampleCount -or $SampleCount -ieq 'null') { $SampleCount = '5' }
    if (-not $SampleIntervalSeconds -or $SampleIntervalSeconds -ieq 'null') { $SampleIntervalSeconds = '2' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0; $count = 0; $interval = 0
    if (-not [int]::TryParse($ThresholdPercent, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'systemCpuThresholdPercent: 1..100 erforderlich / required.'
    }
    if (-not [int]::TryParse($SampleCount, [ref]$count) -or $count -lt 1 -or $count -gt 30) {
        throw 'systemCpuSampleCount: 1..30 erforderlich / required.'
    }
    if (-not [int]::TryParse($SampleIntervalSeconds, [ref]$interval) -or $interval -lt 1 -or $interval -gt 10) {
        throw 'systemCpuSampleIntervalSeconds: 1..10 erforderlich / required.'
    }
    if ($count * $interval -gt 120) { throw 'Laufzeit über 120 s / Runtime exceeds 120 s (count * interval).' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $samples = New-Object System.Collections.Generic.List[double]
    for ($i = 1; $i -le $count; $i++) {
        $cpu = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name = '_Total'")
        if ($cpu.Count -eq 0 -or $null -eq $cpu[0].PercentProcessorTime) {
            throw 'Keine CPU-Leistungsdaten / No CPU performance data.'
        }
        $samples.Add([double]$cpu[0].PercentProcessorTime)
        if ($i -lt $count) { Start-Sleep -Seconds $interval }
    }
    $stats = $samples | Measure-Object -Average -Maximum -Minimum
    $average = [Math]::Round($stats.Average, 2)
    $warning = $average -gt $limit
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        ThresholdPercent = $limit
        SampleCount = $count
        SampleIntervalSeconds = $interval
        AveragePercent = $average
        MaximumPercent = [Math]::Round($stats.Maximum, 2)
        MinimumPercent = [Math]::Round($stats.Minimum, 2)
        HighLoad = $warning
        Samples = @($samples.ToArray())
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
