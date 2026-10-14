#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft den Zustand physischer Datenträger (Storage-API und optional SMART).
    EN: Checks physical disk health (Storage API and optional SMART).
.DESCRIPTION
    DE: Liest MSFT_PhysicalDisk (root/Microsoft/Windows/Storage) per CIM mit
        HealthStatus, OperationalStatus, MediaType, BusType und Größe, ohne
        Seriennummern. Zusätzlich optional MSStorageDriver_FailurePredictStatus
        (root/wmi, SMART PredictFailure); ist SMART nicht verfügbar (z. B. VM, NVMe,
        RAID), wird SmartAvailable=false gemeldet und das ist kein Fehler.
        Listen sind auf MaxRecords begrenzt und werden gekürzt, bis der Bericht
        4000 Zeichen nicht überschreitet (Truncated, TotalDisks).
        Exit 0 = alle Datenträger gesund, 1 = Eingabe-, Abfrage- oder Schreibfehler
        bzw. keine Datenträger, 2 = HealthStatus Warning/Unhealthy, problematischer
        OperationalStatus (z. B. Degraded, Predictive Failure, Error, Lost
        Communication) oder SMART PredictFailure. HealthStatus Unknown wird nur
        gemeldet. Nur lesend.
    EN: Reads MSFT_PhysicalDisk (root/Microsoft/Windows/Storage) via CIM with
        HealthStatus, OperationalStatus, MediaType, BusType and size, without
        serial numbers. Optionally also MSStorageDriver_FailurePredictStatus
        (root/wmi, SMART PredictFailure); if SMART is unavailable (e.g. VM, NVMe,
        RAID), SmartAvailable=false is reported and this is not an error.
        Lists are bounded by MaxRecords and shrink until the report fits
        4000 characters (Truncated, TotalDisks).
        Exit 0 = all disks healthy, 1 = input, query or write error or no disks,
        2 = HealthStatus Warning/Unhealthy, problematic OperationalStatus (e.g.
        Degraded, Predictive Failure, Error, Lost Communication) or SMART
        PredictFailure. HealthStatus Unknown is reported only. Read-only.
.PARAMETER MaxRecords
    DE: NinjaOne Integer systemDiskMaxRecords, 1..64; Standard 16.
    EN: NinjaOne Integer systemDiskMaxRecords, 1..64; default 16.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\checkPhysicalDiskHealth.ps1
    DE: Prüft alle physischen Datenträger und SMART-Vorhersagen.
    EN: Checks all physical disks and SMART predictions.
.EXAMPLE
    .\checkPhysicalDiskHealth.ps1 -MaxRecords 8 -CustomField diskHealth
    DE: Höchstens 8 Datenträger melden; JSON ins Feld diskHealth.
    EN: Report at most 8 disks; JSON to the field diskHealth.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit, Windows 8/Server 2012 oder neuer.
        Parameter überschreiben Variablen. Exit 0 = OK, 1 = Fehler,
        2 = ungesunder Datenträger oder SMART-Ausfallvorhersage. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit, Windows 8/Server 2012 or later.
        Parameters override variables. Exit 0 = OK, 1 = error,
        2 = unhealthy disk or SMART failure prediction. Read-only.
#>
[CmdletBinding()]
param(
    [string]$MaxRecords = $env:systemDiskMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '16' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 64) {
        throw 'systemDiskMaxRecords: 1..64 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $healthMap = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' }
    $mediaMap = @{ 0 = 'Unspecified'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
    $busMap = @{ 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'; 6 = 'FibreChannel'; 7 = 'USB'; 8 = 'RAID'
        9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 14 = 'Virtual'; 15 = 'FileBackedVirtual'
        16 = 'StorageSpaces'; 17 = 'NVMe' }
    $opMap = @{ 0 = 'Unknown'; 1 = 'Other'; 2 = 'OK'; 3 = 'Degraded'; 4 = 'Stressed'; 5 = 'Predictive Failure'
        6 = 'Error'; 7 = 'Non-Recoverable Error'; 8 = 'Starting'; 9 = 'Stopping'; 10 = 'Stopped'; 11 = 'In Service'
        12 = 'No Contact'; 13 = 'Lost Communication'; 14 = 'Aborted'; 15 = 'Dormant'; 16 = 'Supporting Entity in Error'
        17 = 'Completed'; 18 = 'Power Mode' }
    $badOp = @(3, 5, 6, 7, 10, 12, 13, 14, 16)
    $disks = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk |
        Sort-Object { [string]$_.DeviceId })
    if ($disks.Count -eq 0) { throw 'Keine physischen Datenträger / No physical disks.' }
    $warning = $false
    $allDisks = @(foreach ($disk in $disks) {
        $health = 5
        if ($null -ne $disk.HealthStatus) { $health = [int]$disk.HealthStatus }
        $ops = @($disk.OperationalStatus | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
        $opText = @($ops | ForEach-Object { if ($opMap.ContainsKey($_)) { $opMap[$_] } else { "Code $_" } })
        $problem = ($health -eq 1 -or $health -eq 2 -or @($ops | Where-Object { $badOp -contains $_ }).Count -gt 0)
        if ($problem) { $warning = $true }
        $name = ([string]$disk.FriendlyName) -replace '[\x00-\x1F\x7F]', ''
        [pscustomobject]@{
            DeviceId = [string]$disk.DeviceId
            FriendlyName = $name.Substring(0, [Math]::Min(80, $name.Length))
            MediaType = $(if ($mediaMap.ContainsKey([int]$disk.MediaType)) { $mediaMap[[int]$disk.MediaType] } else { "Code $($disk.MediaType)" })
            BusType = $(if ($busMap.ContainsKey([int]$disk.BusType)) { $busMap[[int]$disk.BusType] } else { 'Unknown' })
            SizeGiB = [Math]::Round([double]$disk.Size / 1GB, 2)
            HealthStatus = $(if ($healthMap.ContainsKey($health)) { $healthMap[$health] } else { "Code $health" })
            OperationalStatus = ($opText -join ', ')
            Problem = $problem
        }
    })
    # DE: SMART ist optional; Nichtverfügbarkeit ist kein Fehler. EN: SMART is optional; unavailability is not an error.
    $smartAvailable = $true
    $smart = @()
    try {
        $smart = @(Get-CimInstance -Namespace 'root/wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop |
            Sort-Object { [string]$_.InstanceName })
    }
    catch { $smartAvailable = $false }
    if ($smart.Count -eq 0) { $smartAvailable = $false }
    $allSmart = @(foreach ($entry in $smart) {
        if ([bool]$entry.PredictFailure) { $warning = $true }
        $instance = ([string]$entry.InstanceName) -replace '[\x00-\x1F\x7F]', ''
        [pscustomobject]@{
            InstanceName = $instance.Substring(0, [Math]::Min(120, $instance.Length))
            PredictFailure = [bool]$entry.PredictFailure
            Reason = [int64]$entry.Reason
        }
    })
    $problemCount = @($allDisks | Where-Object { $_.Problem }).Count
    $failCount = @($allSmart | Where-Object { $_.PredictFailure }).Count
    # DE: Problematische Einträge zuerst behalten. EN: Keep problematic entries first.
    $diskRecords = @(@($allDisks | Where-Object { $_.Problem }) + @($allDisks | Where-Object { -not $_.Problem }) | Select-Object -First $limit)
    $smartRecords = @(@($allSmart | Where-Object { $_.PredictFailure }) + @($allSmart | Where-Object { -not $_.PredictFailure }) | Select-Object -First $limit)
    do {
        $truncated = ($diskRecords.Count -lt $allDisks.Count -or $smartRecords.Count -lt $allSmart.Count)
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            TotalDisks = $allDisks.Count; ProblemDisks = $problemCount
            SmartAvailable = $smartAvailable; SmartPredictFailures = $failCount
            Truncated = $truncated; Disks = $diskRecords; Smart = $smartRecords
        })
        if ($report.Length -le 4000) { break }
        if ($diskRecords.Count -le 1 -and $smartRecords.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        if ($smartRecords.Count -ge $diskRecords.Count -and $smartRecords.Count -gt 0) {
            $smartRecords = @($smartRecords | Select-Object -First ($smartRecords.Count - 1))
        }
        else { $diskRecords = @($diskRecords | Select-Object -First ($diskRecords.Count - 1)) }
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
