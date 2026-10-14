#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest die Routingtabelle begrenzt aus und prüft IPv4-Standardrouten.
    EN: Reads a bounded routing table inventory and checks IPv4 default routes.
.DESCRIPTION
    DE: Liest Routen per Get-NetRoute (aktiver Speicher) und Schnittstellen per
        Get-NetIPInterface. Die Ausgabe enthält Ziel, Next Hop, Schnittstelle sowie
        Routen-, Schnittstellen- und effektive Metrik (Summe) als JSON. Standardrouten
        (0.0.0.0/0, ::/0) werden nur auf verbundenen Schnittstellen gezählt.
        Exit 2, wenn keine IPv4-Standardroute existiert oder mehrere IPv4-Standardrouten
        dieselbe effektive Metrik haben (nicht deterministische Pfadwahl). Die
        Bewertung gilt immer für IPv4, auch wenn nur IPv6 inventarisiert wird.
        Keine Änderungen; Bericht max. 4000 Zeichen, Liste wird bei Bedarf gekürzt.
    EN: Reads routes via Get-NetRoute (active store) and interfaces via
        Get-NetIPInterface. Outputs destination, next hop, interface plus route,
        interface and effective metric (sum) as JSON. Default routes (0.0.0.0/0, ::/0)
        are counted on connected interfaces only. Exit 2 if no IPv4 default route
        exists or several IPv4 default routes share the same effective metric
        (non-deterministic path selection). The check always applies to IPv4, even
        when only IPv6 is inventoried. No changes; report max. 4000 characters,
        the record list is shortened if needed.
.PARAMETER AddressFamily
    DE: NinjaOne Text networkRouteAddressFamily: IPv4, IPv6 oder All; Standard IPv4.
    EN: NinjaOne Text networkRouteAddressFamily: IPv4, IPv6 or All; default IPv4.
.PARAMETER MaxRecords
    DE: NinjaOne Integer networkRouteMaxRecords, 1..200; Standard 25.
    EN: NinjaOne Integer networkRouteMaxRecords, 1..200; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\readRoutingTable.ps1
    DE: Bis zu 25 IPv4-Routen als JSON; Exit 2 bei fehlender/mehrdeutiger Standardroute.
    EN: Up to 25 IPv4 routes as JSON; exit 2 on missing/ambiguous default route.
.EXAMPLE
    .\readRoutingTable.ps1 -AddressFamily All -MaxRecords 100 -CustomField routingTable
    DE: IPv4- und IPv6-Routen (max. 100) ins MultiLine-Feld routingTable schreiben.
    EN: Write IPv4 and IPv6 routes (max. 100) to the MultiLine field routingTable.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = keine oder mehrdeutige
        IPv4-Standardroute. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = missing or ambiguous IPv4
        default route. Read-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AddressFamily = $env:networkRouteAddressFamily,
    [string]$MaxRecords = $env:networkRouteMaxRecords,
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
    $AddressFamily = Get-InputText $AddressFamily 'IPv4'
    $MaxRecords = Get-InputText $MaxRecords '25'
    $CustomField = Get-InputText $CustomField ''
    if ($AddressFamily -notin @('IPv4', 'IPv6', 'All')) { throw 'networkRouteAddressFamily: IPv4, IPv6 oder/or All.' }
    $AddressFamily = @('IPv4', 'IPv6', 'All') | Where-Object { $_ -ieq $AddressFamily }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'networkRouteMaxRecords: 1..200 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    # DE: Verbundene Schnittstellen je Adressfamilie mit Schnittstellenmetrik.
    # EN: Connected interfaces per address family with interface metric.
    $interfaces = @{}
    foreach ($interface in @(Get-NetIPInterface -ErrorAction Stop)) {
        $interfaces[('{0}|{1}' -f $interface.InterfaceIndex, [string]$interface.AddressFamily)] = $interface
    }
    $routes = @(Get-NetRoute -ErrorAction Stop | ForEach-Object {
        $family = [string]$_.AddressFamily
        $interface = $interfaces[('{0}|{1}' -f $_.InterfaceIndex, $family)]
        $interfaceMetric = $null
        $connected = $false
        if ($interface) {
            $interfaceMetric = [int]$interface.InterfaceMetric
            $connected = ([string]$interface.ConnectionState -eq 'Connected')
        }
        $effective = $null
        if ($null -ne $interfaceMetric) { $effective = [int]$_.RouteMetric + $interfaceMetric }
        [pscustomobject]@{
            AddressFamily = $family; DestinationPrefix = [string]$_.DestinationPrefix; NextHop = [string]$_.NextHop
            InterfaceAlias = [string]$_.InterfaceAlias; InterfaceIndex = [int]$_.InterfaceIndex
            RouteMetric = [int]$_.RouteMetric; InterfaceMetric = $interfaceMetric; EffectiveMetric = $effective
            Connected = $connected; IsDefault = ([string]$_.DestinationPrefix -in @('0.0.0.0/0', '::/0'))
        }
    })
    $defaults4 = @($routes | Where-Object { $_.IsDefault -and $_.Connected -and $_.AddressFamily -eq 'IPv4' } | Sort-Object EffectiveMetric)
    $defaults6 = @($routes | Where-Object { $_.IsDefault -and $_.Connected -and $_.AddressFamily -eq 'IPv6' })
    $tiedMetrics = @($defaults4 | Group-Object EffectiveMetric | Where-Object { $_.Count -gt 1 } | ForEach-Object { [int]$_.Name })
    $findings = New-Object System.Collections.Generic.List[string]
    if ($defaults4.Count -eq 0) { $findings.Add('NoIPv4DefaultRoute') }
    if ($tiedMetrics.Count -gt 0) { $findings.Add('IPv4DefaultRoutesWithEqualMetric') }

    $selected = @($routes | Where-Object { $AddressFamily -eq 'All' -or $_.AddressFamily -eq $AddressFamily } |
        Sort-Object @{ Expression = { -not $_.IsDefault } }, @{ Expression = { -not $_.Connected } }, AddressFamily, EffectiveMetric, DestinationPrefix)
    $records = @($selected | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            AddressFamily = $AddressFamily; IPv4DefaultRoutes = $defaults4.Count; IPv6DefaultRoutes = $defaults6.Count
            IPv4DefaultTiedMetrics = $tiedMetrics; Findings = @($findings)
            TotalRoutes = $selected.Count; ReportedRecords = $records.Count; Truncated = ($records.Count -lt $selected.Count)
            Routes = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
