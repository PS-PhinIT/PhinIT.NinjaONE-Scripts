#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Akkustatus und Akkugesundheit (Verschleiß) und warnt unter einem Grenzwert.
    EN: Reports battery status and health (wear) and warns below a threshold.
.DESCRIPTION
    DE: Liest Win32_Battery (Name, Status, Ladestand, Chemie) sowie aus root/wmi
        BatteryStaticData (DesignedCapacity) und BatteryFullChargedCapacity
        (FullChargedCapacity), Zuordnung über InstanceName. Gesundheit =
        volle Ladekapazität / Designkapazität in Prozent, Verschleiß = 100 - Gesundheit.
        Ohne Akku: HasBattery=false und Exit 0. Sind die Kapazitätsdaten nicht
        verfügbar (Treiber/Firmware), wird CapacityDataAvailable=false gemeldet
        (keine Warnung). Listen max. 8 Einträge. Ausgabe als JSON, optional in ein
        MultiLine-Feld (max. 4000 Zeichen). Exit 0 = OK oder kein Akku, 1 = Eingabe-,
        Abfrage- oder Schreibfehler, 2 = Gesundheit eines Akkus unter MinHealthPercent.
        Nur lesend.
    EN: Reads Win32_Battery (name, status, charge, chemistry) and from root/wmi
        BatteryStaticData (DesignedCapacity) and BatteryFullChargedCapacity
        (FullChargedCapacity), matched by InstanceName. Health = full charge
        capacity / design capacity in percent, wear = 100 - health.
        No battery: HasBattery=false and exit 0. If capacity data is unavailable
        (driver/firmware), CapacityDataAvailable=false is reported (no warning).
        Lists max. 8 entries. Outputs JSON, optionally to a MultiLine field
        (max. 4000 characters). Exit 0 = OK or no battery, 1 = input, query or
        write error, 2 = health of a battery below MinHealthPercent. Read-only.
.PARAMETER MinHealthPercent
    DE: NinjaOne Integer systemBatteryMinHealthPercent, 1..100; Standard 60.
    EN: NinjaOne Integer systemBatteryMinHealthPercent, 1..100; default 60.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readBatteryHealth.ps1
    DE: Warnung, wenn ein Akku unter 60 % seiner Designkapazität liegt.
    EN: Warning if a battery is below 60% of its design capacity.
.EXAMPLE
    .\readBatteryHealth.ps1 -MinHealthPercent 70 -CustomField batteryHealth
    DE: Grenzwert 70 %; JSON ins Feld batteryHealth.
    EN: Threshold 70%; JSON to the field batteryHealth.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK/kein Akku, 1 = Fehler, 2 = Akku verschlissen. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK/no battery, 1 = error, 2 = battery worn. Read-only.
#>
[CmdletBinding()]
param(
    [string]$MinHealthPercent = $env:systemBatteryMinHealthPercent,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MinHealthPercent = ([string]$MinHealthPercent).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $MinHealthPercent -or $MinHealthPercent -ieq 'null') { $MinHealthPercent = '60' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if (-not [int]::TryParse($MinHealthPercent, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'systemBatteryMinHealthPercent: 1..100 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $statusMap = @{ 1 = 'Discharging'; 2 = 'AC'; 3 = 'FullyCharged'; 4 = 'Low'; 5 = 'Critical'; 6 = 'Charging'
        7 = 'ChargingHigh'; 8 = 'ChargingLow'; 9 = 'ChargingCritical'; 10 = 'Undefined'; 11 = 'PartiallyCharged' }
    $chemMap = @{ 1 = 'Other'; 2 = 'Unknown'; 3 = 'LeadAcid'; 4 = 'NickelCadmium'; 5 = 'NickelMetalHydride'
        6 = 'LithiumIon'; 7 = 'ZincAir'; 8 = 'LithiumPolymer' }
    $batteries = @(Get-CimInstance -ClassName Win32_Battery)
    $batteryRecords = @(foreach ($battery in ($batteries | Select-Object -First 8)) {
        $name = (([string]$battery.Name) -replace '[\x00-\x1F\x7F]', '').Trim()
        [pscustomobject]@{
            Name = $name.Substring(0, [Math]::Min(80, $name.Length))
            Status = $(if ($statusMap.ContainsKey([int]$battery.BatteryStatus)) { $statusMap[[int]$battery.BatteryStatus] } else { 'Unknown' })
            ChargePercent = $battery.EstimatedChargeRemaining
            Chemistry = $(if ($chemMap.ContainsKey([int]$battery.Chemistry)) { $chemMap[[int]$battery.Chemistry] } else { 'Unknown' })
        }
    })
    $capacityRecords = @()
    $capacityAvailable = $false
    $lowHealth = $false
    if ($batteries.Count -gt 0) {
        # DE: Kapazitätsdaten sind optional (Treiberabhängig). EN: Capacity data is optional (driver-dependent).
        $static = @(); $full = @()
        try {
            $static = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction Stop)
            $full = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop)
        }
        catch { $static = @(); $full = @() }
        $capacityRecords = @(foreach ($entry in ($static | Sort-Object { [string]$_.InstanceName } | Select-Object -First 8)) {
            $match = @($full | Where-Object { [string]$_.InstanceName -eq [string]$entry.InstanceName })
            $designed = [double]$entry.DesignedCapacity
            if ($match.Count -eq 0 -or $designed -le 0) { continue }
            $fullCap = [double]$match[0].FullChargedCapacity
            $health = [Math]::Round([Math]::Min(100, 100 * $fullCap / $designed), 2)
            $low = $health -lt $limit
            if ($low) { $lowHealth = $true }
            $instance = ([string]$entry.InstanceName) -replace '[\x00-\x1F\x7F]', ''
            [pscustomobject]@{
                InstanceName = $instance.Substring(0, [Math]::Min(120, $instance.Length))
                DesignedCapacityMWh = [int64]$designed
                FullChargedCapacityMWh = [int64]$fullCap
                HealthPercent = $health
                WearPercent = [Math]::Round(100 - $health, 2)
                LowHealth = $low
            }
        })
        $capacityAvailable = $capacityRecords.Count -gt 0
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        HasBattery = $batteries.Count -gt 0
        BatteryCount = $batteries.Count
        MinHealthPercent = $limit
        CapacityDataAvailable = $capacityAvailable
        LowHealth = $lowHealth
        Batteries = $batteryRecords
        Capacity = $capacityRecords
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($lowHealth) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
