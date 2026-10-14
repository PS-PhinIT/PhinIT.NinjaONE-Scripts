#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Konfiguration und Auslastung der Auslagerungsdatei(en).
    EN: Reports page file configuration and usage.
.DESCRIPTION
    DE: Liest per CIM Win32_ComputerSystem (AutomaticManagedPagefile),
        Win32_PageFileUsage (Größe, aktuelle und Spitzenauslastung in MiB) und
        Win32_PageFileSetting (Anfangs-/Maximalgröße bei manueller Konfiguration).
        Ausgabe als JSON (max. 26 Einträge je Liste), optional in ein MultiLine-Feld
        (max. 4000 Zeichen). Exit 0 = OK, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = keine Auslagerungsdatei aktiv oder eine Datei über ThresholdPercent
        aktuell belegt. Nur lesend.
    EN: Reads via CIM Win32_ComputerSystem (AutomaticManagedPagefile),
        Win32_PageFileUsage (size, current and peak usage in MiB) and
        Win32_PageFileSetting (initial/maximum size when configured manually).
        Outputs JSON (max. 26 entries per list), optionally to a MultiLine field
        (max. 4000 characters). Exit 0 = OK, 1 = input, query or write error,
        2 = no active page file or a page file currently used above
        ThresholdPercent. Read-only.
.PARAMETER ThresholdPercent
    DE: NinjaOne Integer systemPageFileThresholdPercent, 1..100; Standard 80.
    EN: NinjaOne Integer systemPageFileThresholdPercent, 1..100; default 80.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readPageFileStatus.ps1
    DE: Warnung ohne Auslagerungsdatei oder über 80 % Belegung.
    EN: Warning without a page file or above 80% usage.
.EXAMPLE
    .\readPageFileStatus.ps1 -ThresholdPercent 60 -CustomField pageFileStatus
    DE: Grenzwert 60 %; JSON ins Feld pageFileStatus.
    EN: Threshold 60%; JSON to the field pageFileStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = keine Auslagerungsdatei oder hohe Belegung. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = no page file or high usage. Read-only.
#>
[CmdletBinding()]
param(
    [string]$ThresholdPercent = $env:systemPageFileThresholdPercent,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $ThresholdPercent = ([string]$ThresholdPercent).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $ThresholdPercent -or $ThresholdPercent -ieq 'null') { $ThresholdPercent = '80' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if (-not [int]::TryParse($ThresholdPercent, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'systemPageFileThresholdPercent: 1..100 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $system = @(Get-CimInstance -ClassName Win32_ComputerSystem)
    if ($system.Count -eq 0) { throw 'Keine Systemdaten / No computer system data.' }
    $usage = @(Get-CimInstance -ClassName Win32_PageFileUsage)
    $settings = @(Get-CimInstance -ClassName Win32_PageFileSetting)
    $highUsage = $false
    $files = @(foreach ($file in ($usage | Select-Object -First 26)) {
        $size = [double]$file.AllocatedBaseSize
        $percent = $null
        if ($size -gt 0) { $percent = [Math]::Round(100 * [double]$file.CurrentUsage / $size, 2) }
        $high = ($null -ne $percent -and $percent -gt $limit)
        if ($high) { $highUsage = $true }
        [pscustomobject]@{
            Name = [string]$file.Name
            AllocatedMiB = [int64]$file.AllocatedBaseSize
            CurrentUsageMiB = [int64]$file.CurrentUsage
            PeakUsageMiB = [int64]$file.PeakUsage
            UsedPercent = $percent
            TempPageFile = [bool]$file.TempPageFile
            HighUsage = $high
        }
    })
    $configured = @(foreach ($setting in ($settings | Select-Object -First 26)) {
        [pscustomobject]@{
            Name = [string]$setting.Name
            InitialSizeMiB = [int64]$setting.InitialSize
            MaximumSizeMiB = [int64]$setting.MaximumSize
            SystemManaged = ([int64]$setting.InitialSize -eq 0 -and [int64]$setting.MaximumSize -eq 0)
        }
    })
    $noPageFile = $usage.Count -eq 0
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        ThresholdPercent = $limit
        AutomaticManagedPagefile = [bool]$system[0].AutomaticManagedPagefile
        PageFileCount = $usage.Count
        NoPageFile = $noPageFile
        HighUsage = $highUsage
        PageFiles = $files
        Settings = $configured
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($noPageFile -or $highUsage) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
