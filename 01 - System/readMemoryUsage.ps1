#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet die Arbeitsspeicher- und Commit-Auslastung und warnt über Grenzwerten.
    EN: Reports physical memory and commit charge usage and warns above thresholds.
.DESCRIPTION
    DE: Liest Win32_OperatingSystem per CIM: physischer Speicher (TotalVisibleMemorySize,
        FreePhysicalMemory) und Commit (TotalVirtualMemorySize = Commit-Limit,
        FreeVirtualMemory). Ausgabe als JSON, optional in ein MultiLine-Feld
        (max. 4000 Zeichen). Exit 0 = unter den Grenzwerten, 1 = Eingabe-, Abfrage-
        oder Schreibfehler, 2 = physische Auslastung über ThresholdPercent oder
        Commit-Auslastung über CommitThresholdPercent (wenn nicht 0). Nur lesend.
    EN: Reads Win32_OperatingSystem via CIM: physical memory (TotalVisibleMemorySize,
        FreePhysicalMemory) and commit (TotalVirtualMemorySize = commit limit,
        FreeVirtualMemory). Outputs JSON, optionally to a MultiLine field
        (max. 4000 characters). Exit 0 = below thresholds, 1 = input, query or
        write error, 2 = physical usage above ThresholdPercent or commit usage
        above CommitThresholdPercent (unless 0). Read-only.
.PARAMETER ThresholdPercent
    DE: NinjaOne Integer systemMemoryThresholdPercent, 1..100; Standard 90.
    EN: NinjaOne Integer systemMemoryThresholdPercent, 1..100; default 90.
.PARAMETER CommitThresholdPercent
    DE: NinjaOne Integer systemMemoryCommitThresholdPercent, 0..100; Standard 95; 0 = deaktiviert.
    EN: NinjaOne Integer systemMemoryCommitThresholdPercent, 0..100; default 95; 0 = disabled.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readMemoryUsage.ps1
    DE: Warnung über 90 % RAM oder 95 % Commit.
    EN: Warning above 90% RAM or 95% commit.
.EXAMPLE
    .\readMemoryUsage.ps1 -ThresholdPercent 80 -CommitThresholdPercent 0 -CustomField memoryUsage
    DE: Nur RAM über 80 % prüfen; JSON ins Feld memoryUsage.
    EN: Check RAM above 80% only; JSON to the field memoryUsage.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = hohe Speicher-/Commit-Auslastung. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = high memory/commit usage. Read-only.
#>
[CmdletBinding()]
param(
    [string]$ThresholdPercent = $env:systemMemoryThresholdPercent,
    [string]$CommitThresholdPercent = $env:systemMemoryCommitThresholdPercent,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $ThresholdPercent = ([string]$ThresholdPercent).Trim()
    $CommitThresholdPercent = ([string]$CommitThresholdPercent).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $ThresholdPercent -or $ThresholdPercent -ieq 'null') { $ThresholdPercent = '90' }
    if (-not $CommitThresholdPercent -or $CommitThresholdPercent -ieq 'null') { $CommitThresholdPercent = '95' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0; $commitLimit = 0
    if (-not [int]::TryParse($ThresholdPercent, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'systemMemoryThresholdPercent: 1..100 erforderlich / required.'
    }
    if (-not [int]::TryParse($CommitThresholdPercent, [ref]$commitLimit) -or $commitLimit -lt 0 -or $commitLimit -gt 100) {
        throw 'systemMemoryCommitThresholdPercent: 0..100 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $os = @(Get-CimInstance -ClassName Win32_OperatingSystem)
    if ($os.Count -eq 0) { throw 'Keine Betriebssystemdaten / No operating system data.' }
    $os = $os[0]
    # DE: Werte von Win32_OperatingSystem sind in KiB. EN: Win32_OperatingSystem values are in KiB.
    $totalKiB = [double]$os.TotalVisibleMemorySize
    $freeKiB = [double]$os.FreePhysicalMemory
    $commitLimitKiB = [double]$os.TotalVirtualMemorySize
    $commitFreeKiB = [double]$os.FreeVirtualMemory
    if ($totalKiB -le 0 -or $freeKiB -lt 0 -or $freeKiB -gt $totalKiB) { throw 'Ungültige Speicherdaten / Invalid memory data.' }
    $usedPercent = [Math]::Round(100 * ($totalKiB - $freeKiB) / $totalKiB, 2)
    $commitPercent = $null
    if ($commitLimitKiB -gt 0 -and $commitFreeKiB -ge 0 -and $commitFreeKiB -le $commitLimitKiB) {
        $commitPercent = [Math]::Round(100 * ($commitLimitKiB - $commitFreeKiB) / $commitLimitKiB, 2)
    }
    $highMemory = $usedPercent -gt $limit
    $highCommit = ($commitLimit -gt 0 -and $null -ne $commitPercent -and $commitPercent -gt $commitLimit)
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        ThresholdPercent = $limit
        CommitThresholdPercent = $commitLimit
        TotalGiB = [Math]::Round($totalKiB / 1MB, 2)
        UsedGiB = [Math]::Round(($totalKiB - $freeKiB) / 1MB, 2)
        FreeGiB = [Math]::Round($freeKiB / 1MB, 2)
        UsedPercent = $usedPercent
        CommitLimitGiB = [Math]::Round($commitLimitKiB / 1MB, 2)
        CommitUsedGiB = [Math]::Round([Math]::Max(0, $commitLimitKiB - $commitFreeKiB) / 1MB, 2)
        CommitUsedPercent = $commitPercent
        HighMemory = $highMemory
        HighCommit = $highCommit
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($highMemory -or $highCommit) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
