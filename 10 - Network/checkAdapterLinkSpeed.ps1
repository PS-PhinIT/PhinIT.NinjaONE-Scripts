#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Verbindungsgeschwindigkeit physischer, verbundener Netzwerkadapter.
    EN: Checks the link speed of physical, connected network adapters.
.DESCRIPTION
    DE: Liest Get-NetAdapter -Physical (Status Up) und berechnet Mbit/s aus den
        numerischen Werten ReceiveLinkSpeed/TransmitLinkSpeed (kleinerer Wert) bzw.
        Speed (bit/s), nicht aus dem lokalisierten LinkSpeed-Text. FullDuplex wird
        gemeldet, falls verfügbar. Exit 2, wenn ein kabelgebundener Adapter (optional
        auch WLAN/WWAN/Bluetooth) unter MinimumMbps liegt. Adapter ohne
        Geschwindigkeitswert werden als SpeedUnknown gemeldet, aber nicht bewertet.
        Ohne verbundenen physischen Adapter: Exit 0 mit leerer Liste. Keine Änderungen.
    EN: Reads Get-NetAdapter -Physical (status Up) and computes Mbit/s from the
        numeric ReceiveLinkSpeed/TransmitLinkSpeed values (lower one) or Speed (bit/s),
        not from the localized LinkSpeed text. FullDuplex is reported if available.
        Exit 2 if a wired adapter (optionally also Wi-Fi/WWAN/Bluetooth) is below
        MinimumMbps. Adapters without a speed value are reported as SpeedUnknown but
        not evaluated. Without a connected physical adapter: exit 0 with an empty list.
        No changes.
.PARAMETER MinimumMbps
    DE: NinjaOne Integer networkMinLinkSpeedMbps, 1..400000; Standard 1000.
    EN: NinjaOne Integer networkMinLinkSpeedMbps, 1..400000; default 1000.
.PARAMETER IncludeWireless
    DE: NinjaOne Checkbox/Text networkLinkSpeedIncludeWireless: true/false/1/0; Standard false.
    EN: NinjaOne checkbox/text networkLinkSpeedIncludeWireless: true/false/1/0; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\checkAdapterLinkSpeed.ps1
    DE: Exit 2, wenn ein LAN-Adapter mit weniger als 1000 Mbit/s verbunden ist.
    EN: Exit 2 if a wired adapter is connected below 1000 Mbit/s.
.EXAMPLE
    .\checkAdapterLinkSpeed.ps1 -MinimumMbps 100 -IncludeWireless true -CustomField linkSpeed
    DE: Mindestens 100 Mbit/s auch für WLAN; JSON ins Feld linkSpeed.
    EN: At least 100 Mbit/s including Wi-Fi; JSON to the field linkSpeed.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = bewerteter Adapter
        unter Mindestgeschwindigkeit. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = evaluated adapter below the
        minimum speed. Read-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MinimumMbps = $env:networkMinLinkSpeedMbps,
    [string]$IncludeWireless = $env:networkLinkSpeedIncludeWireless,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputText {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function Publish-NetworkReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Report, [string]$Field)
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($Report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $Report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    $MinimumMbps = Get-InputText $MinimumMbps '1000'
    $IncludeWireless = Get-InputText $IncludeWireless 'false'
    $CustomField = Get-InputText $CustomField ''
    $minimum = 0
    if (-not [int]::TryParse($MinimumMbps, [ref]$minimum) -or $minimum -lt 1 -or $minimum -gt 400000) { throw 'networkMinLinkSpeedMbps: 1..400000 erforderlich / required.' }
    if ($IncludeWireless -notin @('true', 'false', '1', '0')) { throw 'networkLinkSpeedIncludeWireless: true/false/1/0.' }
    $withWireless = $IncludeWireless -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | Sort-Object InterfaceIndex)
    $records = @(foreach ($adapter in $adapters) {
        # DE: NDIS-Medium 1/8/9/10 = WLAN/WWAN/802.11/Bluetooth. EN: NDIS medium 1/8/9/10 = WLAN/WWAN/802.11/Bluetooth.
        $medium = -1
        [void][int]::TryParse([string]$adapter.NdisPhysicalMedium, [ref]$medium)
        $wireless = ($medium -in @(1, 8, 9, 10)) -or ([string]$adapter.PhysicalMediaType -match '802\.11|Wireless|BroadBand|Bluetooth')
        $speeds = @(@($adapter.ReceiveLinkSpeed, $adapter.TransmitLinkSpeed) | Where-Object { $null -ne $_ -and [double]$_ -gt 0 })
        if ($speeds.Count -eq 0 -and $null -ne $adapter.Speed -and [double]$adapter.Speed -gt 0) { $speeds = @($adapter.Speed) }
        $mbps = $null
        if ($speeds.Count -gt 0) { $mbps = [Math]::Round((($speeds | ForEach-Object { [double]$_ }) | Measure-Object -Minimum).Minimum / 1000000, 1) }
        $evaluated = ($null -ne $mbps) -and ((-not $wireless) -or $withWireless)
        $fullDuplex = $null
        if ($adapter.PSObject.Properties['FullDuplex'] -and $null -ne $adapter.FullDuplex) { $fullDuplex = [bool]$adapter.FullDuplex }
        [pscustomobject]@{
            Name = [string]$adapter.Name; InterfaceDescription = [string]$adapter.InterfaceDescription
            InterfaceIndex = [int]$adapter.InterfaceIndex; Wireless = $wireless; SpeedMbps = $mbps
            SpeedUnknown = ($null -eq $mbps); FullDuplex = $fullDuplex; Evaluated = $evaluated
            BelowMinimum = ($evaluated -and $mbps -lt $minimum)
        }
    })
    $slow = @($records | Where-Object { $_.BelowMinimum })
    $total = $records.Count
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            MinimumMbps = $minimum; IncludeWireless = $withWireless; TotalAdapters = $total
            BelowMinimum = @($slow | ForEach-Object { $_.Name } | Select-Object -First 20)
            ReportedRecords = $records.Count; Truncated = ($records.Count -lt $total); Adapters = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($slow.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
