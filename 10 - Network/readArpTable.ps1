#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest die IPv4-ARP-Tabelle begrenzt aus und erkennt mögliches ARP-Spoofing.
    EN: Reads a bounded IPv4 ARP table and detects possible ARP spoofing.
.DESCRIPTION
    DE: Liest Get-NetNeighbor (IPv4) und die IPv4-Standard-Gateways (Get-NetRoute
        0.0.0.0/0). Optional werden Rauscheinträge ausgeblendet: Zustand Unreachable/
        Incomplete sowie Multicast- (224.0.0.0/4) und Broadcast-Einträge. Exit 2, wenn
        die MAC-Adresse eines Standard-Gateways auch für eine andere IP-Adresse
        eingetragen ist (mögliches ARP-Spoofing). Achtung: Proxy-ARP oder Router mit
        mehreren IPs auf derselben MAC können Fehlalarme erzeugen. Der Bericht enthält
        MAC-Adressen (Feld-Leserechte einschränken). Keine Änderungen; max. 4000 Zeichen.
    EN: Reads Get-NetNeighbor (IPv4) and the IPv4 default gateways (Get-NetRoute
        0.0.0.0/0). Optionally hides noise: state Unreachable/Incomplete plus multicast
        (224.0.0.0/4) and broadcast entries. Exit 2 if a default gateway's MAC address
        is also registered for another IP address (possible ARP spoofing). Note: proxy
        ARP or routers with several IPs on one MAC can cause false positives. The report
        contains MAC addresses (restrict field read access). No changes; max. 4000 chars.
.PARAMETER ExcludeNoise
    DE: NinjaOne Checkbox/Text networkArpExcludeNoise: true/false/1/0; Standard true.
    EN: NinjaOne checkbox/text networkArpExcludeNoise: true/false/1/0; default true.
.PARAMETER MaxRecords
    DE: NinjaOne Integer networkArpMaxRecords, 1..200; Standard 25.
    EN: NinjaOne Integer networkArpMaxRecords, 1..200; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\readArpTable.ps1
    DE: Bis zu 25 relevante IPv4-Nachbarn; Exit 2 bei doppelter Gateway-MAC.
    EN: Up to 25 relevant IPv4 neighbors; exit 2 on duplicated gateway MAC.
.EXAMPLE
    .\readArpTable.ps1 -ExcludeNoise false -MaxRecords 100 -CustomField arpTable
    DE: Alle IPv4-Einträge (max. 100) ins MultiLine-Feld arpTable.
    EN: All IPv4 entries (max. 100) to the MultiLine field arpTable.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = Gateway-MAC für weitere
        IP-Adresse(n) gefunden. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = gateway MAC found for other IP
        address(es). Read-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExcludeNoise = $env:networkArpExcludeNoise,
    [string]$MaxRecords = $env:networkArpMaxRecords,
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
    $ExcludeNoise = Get-InputText $ExcludeNoise 'true'
    $MaxRecords = Get-InputText $MaxRecords '25'
    $CustomField = Get-InputText $CustomField ''
    if ($ExcludeNoise -notin @('true', 'false', '1', '0')) { throw 'networkArpExcludeNoise: true/false/1/0.' }
    $hideNoise = $ExcludeNoise -in @('true', '1')
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'networkArpMaxRecords: 1..200 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    $neighbors = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object {
        $ip = [string]$_.IPAddress
        $mac = ([string]$_.LinkLayerAddress).Trim().ToUpperInvariant() -replace ':', '-'
        $firstOctet = 0
        [void][int]::TryParse(($ip -split '\.')[0], [ref]$firstOctet)
        [pscustomobject]@{
            IPAddress = $ip; LinkLayerAddress = $mac; State = [string]$_.State
            InterfaceAlias = [string]$_.InterfaceAlias; InterfaceIndex = [int]$_.InterfaceIndex
            Noise = ([string]$_.State -in @('Unreachable', 'Incomplete')) -or ($firstOctet -ge 224 -and $firstOctet -le 239) -or
                ($ip -eq '255.255.255.255') -or ($mac -eq 'FF-FF-FF-FF-FF-FF') -or ($mac -like '01-00-5E-*')
            UsableMac = ($mac -match '^[0-9A-F]{2}(-[0-9A-F]{2}){5}$') -and ($mac -notin @('00-00-00-00-00-00', 'FF-FF-FF-FF-FF-FF'))
        }
    })
    $gateways = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { [string]$_.DestinationPrefix -eq '0.0.0.0/0' -and [string]$_.NextHop -notin @('', '0.0.0.0') } |
        ForEach-Object { [pscustomobject]@{ IPAddress = [string]$_.NextHop; InterfaceIndex = [int]$_.InterfaceIndex } } |
        Sort-Object IPAddress, InterfaceIndex -Unique)

    # DE: Gateway-MAC bei anderer IP (ohne Rauscheinträge) = möglicher Spoofing-Hinweis.
    # EN: Gateway MAC on another IP (noise excluded) = possible spoofing indicator.
    $suspicious = @(foreach ($gateway in $gateways) {
        $entry = $neighbors | Where-Object { $_.IPAddress -eq $gateway.IPAddress -and $_.InterfaceIndex -eq $gateway.InterfaceIndex -and $_.UsableMac -and -not $_.Noise } | Select-Object -First 1
        if (-not $entry) { continue }
        $others = @($neighbors | Where-Object { $_.LinkLayerAddress -eq $entry.LinkLayerAddress -and $_.IPAddress -ne $entry.IPAddress -and -not $_.Noise } |
            Select-Object -ExpandProperty IPAddress -Unique)
        if ($others.Count -gt 0) {
            [pscustomobject]@{
                GatewayIP = $gateway.IPAddress; GatewayMac = $entry.LinkLayerAddress; InterfaceAlias = $entry.InterfaceAlias
                OtherIPs = @($others | Select-Object -First 10); OtherIPCount = $others.Count
            }
        }
    })
    $selected = @($neighbors | Where-Object { -not $hideNoise -or -not $_.Noise } | Sort-Object InterfaceIndex, IPAddress |
        Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias, InterfaceIndex)
    $records = @($selected | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            ExcludeNoise = $hideNoise; DefaultGateways = @($gateways | Select-Object -ExpandProperty IPAddress -Unique)
            SuspiciousGatewayMacs = @($suspicious | Select-Object -First 5); SuspiciousCount = $suspicious.Count
            TotalEntries = $selected.Count; ReportedRecords = $records.Count; Truncated = ($records.Count -lt $selected.Count)
            Neighbors = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($suspicious.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
