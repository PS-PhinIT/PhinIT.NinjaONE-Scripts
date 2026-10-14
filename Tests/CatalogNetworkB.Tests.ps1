BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $routeScript = Join-Path $root '10 - Network/readRoutingTable.ps1'
    $profileScript = Join-Path $root '10 - Network/checkNetworkProfile.ps1'
    $arpScript = Join-Path $root '10 - Network/readArpTable.ps1'
    $conflictScript = Join-Path $root '10 - Network/checkIpAddressConflicts.ps1'
    $speedScript = Join-Path $root '10 - Network/checkAdapterLinkSpeed.ps1'
    $smbScript = Join-Path $root '10 - Network/readSmbShares.ps1'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-NetIPInterface { [CmdletBinding()] param($AddressFamily) }
    function Get-NetRoute { [CmdletBinding()] param($AddressFamily, $DestinationPrefix) }
    function Get-NetConnectionProfile { [CmdletBinding()] param() }
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Namespace, $Filter) }
    function Get-NetNeighbor { [CmdletBinding()] param($AddressFamily) }
    function Get-NetAdapter { [CmdletBinding()] param([switch]$Physical) }
    function Get-NetIPAddress { [CmdletBinding()] param($AddressFamily) }
    function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $MaxEvents) }
    function Get-SmbShare { [CmdletBinding()] param($Name) }
    function Get-SmbShareAccess { [CmdletBinding()] param($Name, $ScopeName) }
    function Ninja-Property-Set { param($Name, $Value) }
}

Describe 'Network catalogue B / Netzwerkkatalog B' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('networkRouteAddressFamily', 'networkRouteMaxRecords', 'networkExpectedCategory', 'networkArpExcludeNoise',
                'networkArpMaxRecords', 'networkConflictDays', 'networkConflictMaxEvents', 'networkMinLinkSpeedMbps',
                'networkLinkSpeedIncludeWireless', 'networkSmbExcludeSpecialShares', 'networkSmbMaxRecords', 'resultCustomField')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Ninja-Property-Set {}
        Mock Get-NetIPInterface {
            [pscustomobject]@{ InterfaceIndex = 5; AddressFamily = 'IPv4'; ConnectionState = 'Connected'; InterfaceMetric = 25 }
            [pscustomobject]@{ InterfaceIndex = 5; AddressFamily = 'IPv6'; ConnectionState = 'Connected'; InterfaceMetric = 25 }
            [pscustomobject]@{ InterfaceIndex = 7; AddressFamily = 'IPv4'; ConnectionState = 'Connected'; InterfaceMetric = 35 }
            [pscustomobject]@{ InterfaceIndex = 9; AddressFamily = 'IPv4'; ConnectionState = 'Disconnected'; InterfaceMetric = 5 }
        }
        Mock Get-NetRoute {
            [pscustomobject]@{ AddressFamily = 'IPv4'; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 0 }
            [pscustomobject]@{ AddressFamily = 'IPv4'; DestinationPrefix = '192.168.1.0/24'; NextHop = '0.0.0.0'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 256 }
            [pscustomobject]@{ AddressFamily = 'IPv4'; DestinationPrefix = '0.0.0.0/0'; NextHop = '10.0.0.1'; InterfaceAlias = 'Old'; InterfaceIndex = 9; RouteMetric = 0 }
            [pscustomobject]@{ AddressFamily = 'IPv6'; DestinationPrefix = '::/0'; NextHop = 'fe80::1'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 0 }
        }
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true } }
        Mock Get-NetConnectionProfile {
            [pscustomobject]@{ Name = 'corp.example'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; NetworkCategory = 'DomainAuthenticated'; IPv4Connectivity = 'Internet'; IPv6Connectivity = 'NoTraffic' }
        }
        Mock Get-NetNeighbor {
            [pscustomobject]@{ IPAddress = '192.168.1.1'; LinkLayerAddress = 'AA-BB-CC-00-00-01'; State = 'Reachable'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
            [pscustomobject]@{ IPAddress = '192.168.1.20'; LinkLayerAddress = 'AA-BB-CC-00-00-20'; State = 'Stale'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
            [pscustomobject]@{ IPAddress = '192.168.1.30'; LinkLayerAddress = '00-00-00-00-00-00'; State = 'Unreachable'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
            [pscustomobject]@{ IPAddress = '224.0.0.22'; LinkLayerAddress = '01-00-5E-00-00-16'; State = 'Permanent'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
            [pscustomobject]@{ IPAddress = '192.168.1.255'; LinkLayerAddress = 'FF-FF-FF-FF-FF-FF'; State = 'Permanent'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
        }
        Mock Get-NetAdapter {
            [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Intel I219'; InterfaceIndex = 5; Status = 'Up'; NdisPhysicalMedium = 14; PhysicalMediaType = '802.3'; ReceiveLinkSpeed = 1000000000; TransmitLinkSpeed = 1000000000; Speed = 1000000000; FullDuplex = $true }
            [pscustomobject]@{ Name = 'WLAN'; InterfaceDescription = 'Wi-Fi 6'; InterfaceIndex = 7; Status = 'Up'; NdisPhysicalMedium = 9; PhysicalMediaType = 'Native 802.11'; ReceiveLinkSpeed = 300000000; TransmitLinkSpeed = 200000000; Speed = 300000000 }
            [pscustomobject]@{ Name = 'Ethernet 2'; InterfaceDescription = 'USB NIC'; InterfaceIndex = 9; Status = 'Disconnected'; NdisPhysicalMedium = 14; PhysicalMediaType = '802.3'; Speed = 0 }
        }
        Mock Get-NetIPAddress {
            [pscustomobject]@{ InterfaceIndex = 5; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4'; IPAddress = '192.168.1.10'; AddressState = 'Preferred'; PrefixOrigin = 'Dhcp' }
            [pscustomobject]@{ InterfaceIndex = 9; InterfaceAlias = 'Ethernet 2'; AddressFamily = 'IPv4'; IPAddress = '169.254.3.4'; AddressState = 'Preferred'; PrefixOrigin = 'WellKnown' }
        }
        Mock Get-WinEvent {}
        Mock Get-SmbShare {
            [pscustomobject]@{ Name = 'ADMIN$'; Path = 'C:\Windows'; Special = $true; ScopeName = '*' }
            [pscustomobject]@{ Name = 'Data'; Path = 'D:\Data'; Special = $false; ScopeName = '*' }
        }
        Mock Get-SmbShareAccess {
            [pscustomobject]@{ AccountName = 'BUILTIN\Administrators'; AccessControlType = 'Allow'; AccessRight = 'Full' }
            [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Read' }
        }
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'readRoutingTable' {
        It 'Reports one IPv4 default route on connected interfaces / Meldet eine Standardroute' {
            $report = & $routeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.IPv4DefaultRoutes | Should -Be 1
            $report.IPv6DefaultRoutes | Should -Be 1
            @($report.Routes).Count | Should -Be 3
            $report.Routes[0].EffectiveMetric | Should -Be 25
        }
        It 'Warns on equal-metric IPv4 default routes / Warnt bei gleicher Metrik' {
            Mock Get-NetRoute {
                [pscustomobject]@{ AddressFamily = 'IPv4'; DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.1.1'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 10 }
                [pscustomobject]@{ AddressFamily = 'IPv4'; DestinationPrefix = '0.0.0.0/0'; NextHop = '10.1.1.1'; InterfaceAlias = 'WLAN'; InterfaceIndex = 7; RouteMetric = 0 }
            }
            $env:resultCustomField = 'routingTable'
            $report = & $routeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'IPv4DefaultRoutesWithEqualMetric'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'routingTable' }
        }
        It 'Warns without IPv4 default route and bounds records / Warnt ohne Standardroute' {
            Mock Get-NetRoute {
                [pscustomobject]@{ AddressFamily = 'IPv6'; DestinationPrefix = '::/0'; NextHop = 'fe80::1'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 0 }
                [pscustomobject]@{ AddressFamily = 'IPv6'; DestinationPrefix = 'fe80::/64'; NextHop = '::'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5; RouteMetric = 256 }
            }
            $report = & $routeScript -AddressFamily ipv6 -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Truncated | Should -BeTrue
            $report.Findings | Should -Contain 'NoIPv4DefaultRoute'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('IPv5', '*')) { $null = & $routeScript -AddressFamily $value; $LASTEXITCODE | Should -Be 1 }
            foreach ($value in @('0', '201', 'abc')) { $env:networkRouteMaxRecords = $value; $null = & $routeScript; $LASTEXITCODE | Should -Be 1 }
            $null = & $routeScript -MaxRecords 5 -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-NetRoute -Times 0 -Exactly
        }
        It 'Skips the field write with -WhatIf / Überspringt Feld mit -WhatIf' {
            $null = & $routeScript -CustomField 'routingTable' -WhatIf
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Ninja-Property-Set -Times 0 -Exactly
        }
    }

    Context 'checkNetworkProfile' {
        It 'Accepts domain profile / Akzeptiert Domänenprofil' {
            $report = & $profileScript -CustomField 'networkProfile' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Profiles[0].NetworkCategory | Should -Be 'DomainAuthenticated'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on Public profile of a domain member / Warnt bei Public auf Domänengerät' {
            Mock Get-NetConnectionProfile { [pscustomobject]@{ Name = 'Hotel'; InterfaceAlias = 'WLAN'; InterfaceIndex = 7; NetworkCategory = 'Public'; IPv4Connectivity = 'Internet'; IPv6Connectivity = 'NoTraffic' } }
            $null = & $profileScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Warns on unexpected category / Warnt bei abweichender Kategorie' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false } }
            $env:networkExpectedCategory = 'private'
            $report = & $profileScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Profiles[0].Issues | Should -Contain 'UnexpectedCategory'
        }
        It 'Rejects invalid category / Lehnt ungültige Kategorie ab' {
            $null = & $profileScript -ExpectedCategory 'Work'
            $LASTEXITCODE | Should -Be 1
        }
        It 'Reports query errors / Meldet Abfragefehler' {
            Mock Get-CimInstance { throw 'CIM failure' }
            $null = & $profileScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readArpTable' {
        It 'Hides noise and accepts a unique gateway MAC / Blendet Rauschen aus' {
            $report = & $arpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Neighbors).Count | Should -Be 2
            $report.DefaultGateways | Should -Contain '192.168.1.1'
            $report.SuspiciousCount | Should -Be 0
        }
        It 'Includes noise on request / Zeigt Rauschen auf Wunsch' {
            $report = & $arpScript -ExcludeNoise false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Neighbors).Count | Should -Be 5
        }
        It 'Detects gateway MAC reused by another IP / Erkennt doppelte Gateway-MAC' {
            Mock Get-NetNeighbor {
                [pscustomobject]@{ IPAddress = '192.168.1.1'; LinkLayerAddress = 'aa-bb-cc-00-00-66'; State = 'Reachable'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
                [pscustomobject]@{ IPAddress = '192.168.1.66'; LinkLayerAddress = 'AA-BB-CC-00-00-66'; State = 'Reachable'; InterfaceAlias = 'Ethernet'; InterfaceIndex = 5 }
            }
            $env:resultCustomField = 'arpTable'
            $report = & $arpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.SuspiciousGatewayMacs[0].OtherIPs | Should -Contain '192.168.1.66'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $arpScript -ExcludeNoise 'maybe'
            $LASTEXITCODE | Should -Be 1
            $null = & $arpScript -MaxRecords '500'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkIpAddressConflicts' {
        It 'Ignores APIPA on disconnected adapters / Ignoriert getrennte Adapter' {
            $report = & $conflictScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalFindings | Should -Be 0
            Should -Invoke Get-WinEvent -Times 1 -Exactly -ParameterFilter { $FilterHashtable.Id -eq 4199 -and $MaxEvents -eq 50 }
        }
        It 'Detects APIPA, duplicate state and conflict events / Erkennt APIPA, Duplikate und Ereignisse' {
            Mock Get-NetIPAddress {
                [pscustomobject]@{ InterfaceIndex = 5; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4'; IPAddress = '169.254.10.1'; AddressState = 'Preferred'; PrefixOrigin = 'WellKnown' }
                [pscustomobject]@{ InterfaceIndex = 7; InterfaceAlias = 'WLAN'; AddressFamily = 'IPv4'; IPAddress = '10.0.0.5'; AddressState = 'Duplicate'; PrefixOrigin = 'Manual' }
            }
            Mock Get-WinEvent { [pscustomobject]@{ ProviderName = 'Tcpip'; TimeCreated = (Get-Date); Message = "The system detected an address conflict`r`nfor IP 10.0.0.5" } }
            $env:resultCustomField = 'ipConflicts'
            $report = & $conflictScript -Days 30 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.TotalFindings | Should -Be 3
            $report.Findings.Type | Should -Contain 'APIPA'
            $report.Findings.Type | Should -Contain 'AddressStateDuplicate'
            $report.Findings.Type | Should -Contain 'ConflictEvent4199'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '91', 'x')) { $null = & $conflictScript -Days $value; $LASTEXITCODE | Should -Be 1 }
            $env:networkConflictMaxEvents = '501'
            $null = & $conflictScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkAdapterLinkSpeed' {
        It 'Accepts gigabit wired adapter and ignores Wi-Fi / Akzeptiert Gigabit-LAN' {
            $report = & $speedScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalAdapters | Should -Be 2
            ($report.Adapters | Where-Object Name -eq 'WLAN').SpeedMbps | Should -Be 200
            ($report.Adapters | Where-Object Name -eq 'WLAN').Evaluated | Should -BeFalse
            ($report.Adapters | Where-Object Name -eq 'Ethernet').FullDuplex | Should -BeTrue
        }
        It 'Warns on slow Wi-Fi when included / Warnt bei langsamem WLAN' {
            $env:networkLinkSpeedIncludeWireless = 'true'
            $env:resultCustomField = 'linkSpeed'
            $report = & $speedScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.BelowMinimum | Should -Be @('WLAN')
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on slow wired adapter / Warnt bei langsamem LAN' {
            $null = & $speedScript -MinimumMbps 2500
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '400001', '1.5')) { $null = & $speedScript -MinimumMbps $value; $LASTEXITCODE | Should -Be 1 }
            $null = & $speedScript -IncludeWireless 'yes'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readSmbShares' {
        It 'Excludes special shares and accepts safe ACL / Akzeptiert sichere Rechte' {
            $report = & $smbScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalShares | Should -Be 1
            $report.Shares[0].Name | Should -Be 'Data'
            Should -Invoke Get-SmbShareAccess -Times 1 -Exactly -ParameterFilter { $Name -eq 'Data' -and -not $ScopeName }
        }
        It 'Flags broad Full/Change access / Meldet weitreichende Rechte' {
            Mock Get-SmbShareAccess {
                [pscustomobject]@{ AccountName = 'NT AUTHORITY\Authenticated Users'; AccessControlType = 'Allow'; AccessRight = 'Change' }
                [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Deny'; AccessRight = 'Full' }
            }
            $env:resultCustomField = 'smbShares'
            $report = & $smbScript -ExcludeSpecial false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.RiskyShareCount | Should -Be 2
            $report.Shares[0].RiskyAccess | Should -Be @('NT AUTHORITY\Authenticated Users:Change')
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input and query errors / Lehnt Fehler ab' {
            $null = & $smbScript -MaxRecords '0'
            $LASTEXITCODE | Should -Be 1
            Mock Get-SmbShare { throw 'Server service stopped' }
            $null = & $smbScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Reports field write failures / Meldet Schreibfehler' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $smbScript -CustomField 'smbShares'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
