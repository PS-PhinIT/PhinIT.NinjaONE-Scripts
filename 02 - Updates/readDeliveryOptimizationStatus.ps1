#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest Status und Konfiguration der Übermittlungsoptimierung (Delivery Optimization).
    EN: Reads Delivery Optimization status and configuration.
.DESCRIPTION
    DE: Nutzt Get-DeliveryOptimizationPerfSnap (Cache, Peers, Verbindungen, Bandbreite) und
        Get-DOConfig (ab Windows 10 1903), sofern vorhanden, sowie die Registry:
        Richtlinie HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization (DODownloadMode,
        DOCacheHost, Cache-/Bandbreitengrenzen), MDM HKLM\SOFTWARE\Microsoft\PolicyManager\
        current\device\DeliveryOptimization und lokale Einstellung HKLM\SOFTWARE\Microsoft\
        Windows\CurrentVersion\DeliveryOptimization\Config. DOGroupId wird nicht ausgegeben,
        nur GroupIdConfigured. Der wirksame Downloadmodus (0 HttpOnly, 1 Lan, 2 Group,
        3 Internet, 99 Simple, 100 Bypass) wird in der Reihenfolge Gruppenrichtlinie, MDM,
        lokale Einstellung, Get-DOConfig bestimmt. Informativ: Exit 0 = Daten gelesen,
        1 = Eingabe- oder Schreibfehler bzw. weder Cmdlets noch Registry-Daten verfügbar.
        Exit 2 wird nicht verwendet.
    EN: Uses Get-DeliveryOptimizationPerfSnap (cache, peers, connections, bandwidth) and
        Get-DOConfig (Windows 10 1903+) when available, plus the registry: policy
        HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization (DODownloadMode,
        DOCacheHost, cache/bandwidth limits), MDM HKLM\SOFTWARE\Microsoft\PolicyManager\
        current\device\DeliveryOptimization and the local setting HKLM\SOFTWARE\Microsoft\
        Windows\CurrentVersion\DeliveryOptimization\Config. DOGroupId is not printed, only
        GroupIdConfigured. The effective download mode (0 HttpOnly, 1 Lan, 2 Group, 3 Internet,
        99 Simple, 100 Bypass) is resolved in the order Group Policy, MDM, local setting,
        Get-DOConfig. Informational: exit 0 = data read, 1 = input or write error, or neither
        cmdlets nor registry data available. Exit 2 is not used.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\readDeliveryOptimizationStatus.ps1
    DE: Gibt Downloadmodus, Cache- und Peerstatus als JSON aus.
    EN: Outputs download mode, cache and peer status as JSON.
.EXAMPLE
    .\readDeliveryOptimizationStatus.ps1 -CustomField deliveryOptimization
    DE: Schreibt den JSON-Bericht ins MultiLine-Feld deliveryOptimization.
    EN: Writes the JSON report to the MultiLine field deliveryOptimization.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Leistungswerte sind eine
        Momentaufnahme. Exit 0 = OK, 1 = Fehler/keine Daten.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Performance values are a
        snapshot. Exit 0 = OK, 1 = error/no data.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryValueTable {
    param([string]$Path, [string[]]$Names)
    $table = [ordered]@{}
    $item = $null
    if (Test-Path -LiteralPath $Path) { $item = Get-ItemProperty -LiteralPath $Path }
    foreach ($name in $Names) {
        $value = $null
        if ($null -ne $item -and $item.PSObject.Properties[$name]) { $value = $item.$name }
        $table[$name] = $value
    }
    $table
}
function Get-PropertySubset {
    param($InputObject, [string[]]$Names)
    if ($null -eq $InputObject) { return $null }
    $table = [ordered]@{}
    foreach ($property in @($InputObject.PSObject.Properties)) {
        if ($property.Name -match '^(PS|Cim)' -or $property.Name -match 'GroupId$') { continue }
        if ($Names -and $Names -notcontains $property.Name) { continue }
        if ($table.Count -ge 30) { break }
        $value = $property.Value
        if ($null -ne $value -and $value -isnot [ValueType]) {
            $value = [string]$value
            if ($value.Length -gt 200) { $value = $value.Substring(0, 200) }
        }
        $table[$property.Name] = $value
    }
    $table
}
try {
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $perfNames = @('FileCount', 'CacheSizeBytes', 'TotalDiskBytes', 'AvailableDiskBytes', 'CpuUsagePct', 'MemUsageKB', 'NumberOfPeers',
        'CacheHostConnections', 'CdnConnections', 'LanConnections', 'LinkLocalConnections', 'GroupConnections', 'InternetConnections',
        'DownlinkBps', 'DownlinkUsageBps', 'UplinkBps', 'UplinkUsageBps', 'ForegroundDownloadRatePct', 'BackgroundDownloadRatePct',
        'UploadRatePct', 'ForegroundDownloadsPending', 'BackgroundDownloadsPending')
    $perf = $null; $config = $null; $errors = [System.Collections.Generic.List[string]]::new()
    if (Get-Command -Name Get-DeliveryOptimizationPerfSnap -ErrorAction SilentlyContinue) {
        try { $perf = Get-PropertySubset -InputObject (Get-DeliveryOptimizationPerfSnap | Select-Object -First 1) -Names $perfNames }
        catch { $errors.Add('PerfSnap: ' + $_.Exception.Message) }
    }
    else { $errors.Add('Get-DeliveryOptimizationPerfSnap nicht verfügbar / unavailable') }
    if (Get-Command -Name Get-DOConfig -ErrorAction SilentlyContinue) {
        try { $config = Get-PropertySubset -InputObject (Get-DOConfig | Select-Object -First 1) -Names @() }
        catch { $errors.Add('DOConfig: ' + $_.Exception.Message) }
    }
    else { $errors.Add('Get-DOConfig nicht verfügbar / unavailable') }
    $policyNames = @('DODownloadMode', 'DOGroupIdSource', 'DOCacheHost', 'DOCacheHostSource', 'DOMaxCacheSize', 'DOAbsoluteMaxCacheSize', 'DOMaxCacheAge',
        'DOPercentageMaxForegroundBandwidth', 'DOPercentageMaxBackgroundBandwidth', 'DOMinRAMAllowedToPeer', 'DORestrictPeerSelectionBy', 'DOGroupId')
    $gpo = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Names $policyNames
    $mdm = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization' -Names @('DODownloadMode', 'DOCacheHost', 'DOGroupId')
    $local = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' -Names @('DODownloadMode')
    $groupIdConfigured = [bool]([string]$gpo.DOGroupId) -or [bool]([string]$mdm.DOGroupId)
    $gpo.Remove('DOGroupId'); $mdm.Remove('DOGroupId')
    $registryData = @(@($gpo.Values) + @($mdm.Values) + @($local.Values) | Where-Object { $null -ne $_ }).Count -gt 0
    if ($null -eq $perf -and $null -eq $config -and -not $registryData) {
        throw ('Keine Delivery-Optimization-Daten / No Delivery Optimization data: ' + ($errors -join '; '))
    }
    $mode = $null; $modeName = $null; $modeSource = $null
    foreach ($candidate in @(@('GroupPolicy', $gpo.DODownloadMode), @('MDM', $mdm.DODownloadMode), @('LocalSetting', $local.DODownloadMode))) {
        if ($null -ne $candidate[1] -and [string]$candidate[1] -ne '') { $mode = [int]$candidate[1]; $modeSource = $candidate[0]; break }
    }
    if ($null -eq $mode -and $null -ne $config -and $config.Contains('DownloadMode')) {
        $parsedMode = 0
        if ([int]::TryParse([string]$config['DownloadMode'], [ref]$parsedMode)) { $mode = $parsedMode; $modeSource = 'Get-DOConfig' }
        else { $modeName = [string]$config['DownloadMode']; $modeSource = 'Get-DOConfig' }
    }
    $modeNames = @{ 0 = 'HttpOnly'; 1 = 'Lan'; 2 = 'Group'; 3 = 'Internet'; 99 = 'Simple'; 100 = 'Bypass' }
    if ($null -ne $mode) { $modeName = $modeNames[$mode] }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; EffectiveDownloadMode = $mode
        EffectiveDownloadModeName = $modeName; DownloadModeSource = $modeSource
        GroupIdConfigured = $groupIdConfigured; PerfSnap = $perf; DOConfig = $config
        GroupPolicy = $gpo; MdmPolicy = $mdm; LocalSetting = $local; Errors = @($errors)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
