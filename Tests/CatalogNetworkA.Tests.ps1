BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root '10 - Network'
    $pingScript = Join-Path $folder 'testPingTargets.ps1'
    $traceScript = Join-Path $folder 'testTraceRoute.ps1'
    $wifiStatusScript = Join-Path $folder 'readWifiStatus.ps1'
    $wifiProfilesScript = Join-Path $folder 'readWifiProfiles.ps1'
    $proxyScript = Join-Path $folder 'checkProxySettings.ps1'
    $vpnScript = Join-Path $folder 'checkVpnConnections.ps1'
    $internetScript = Join-Path $folder 'checkInternetConnectivity.ps1'

    # DE: Stubs erlauben Tests ohne Windows und ohne NinjaOne-Agent.
    # EN: Stubs allow testing without Windows or a NinjaOne agent.
    function Get-Service { [CmdletBinding()] param($Name) }
    function Get-VpnConnection { [CmdletBinding()] param([switch]$AllUserConnection) }
    function Resolve-DnsName { [CmdletBinding()] param($Name, [switch]$DnsOnly, [switch]$QuickTimeout) }
    function netsh { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }

    # DE: Ping-Ersatz mit Antwortfolge. EN: Ping replacement returning a reply sequence.
    function New-FakePing {
        param([object[]]$Replies)
        $fake = [pscustomobject]@{ Replies = $Replies; Index = 0 }
        $fake | Add-Member -MemberType ScriptMethod -Name Send -Value {
            $reply = $this.Replies[[math]::Min($this.Index, $this.Replies.Count - 1)]
            $this.Index++
            if ($reply -eq 'throw') { throw 'Simulated DNS failure' }
            $reply
        }
        $fake | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $fake
    }
    function New-Reply {
        param([string]$Status, [long]$Ms = 10, [string]$Address = '10.0.0.1')
        [pscustomobject]@{ Status = $Status; RoundtripTime = $Ms; Address = $Address }
    }
    function New-WinHttpBytes {
        param([int]$Flags, [string]$Proxy, [string]$Bypass)
        $bytes = New-Object System.Collections.Generic.List[byte]
        $bytes.AddRange([BitConverter]::GetBytes([int]40))
        $bytes.AddRange([BitConverter]::GetBytes([int]0))
        $bytes.AddRange([BitConverter]::GetBytes($Flags))
        foreach ($text in @($Proxy, $Bypass)) {
            $raw = [Text.Encoding]::ASCII.GetBytes([string]$text)
            $bytes.AddRange([BitConverter]::GetBytes([int]$raw.Length))
            $bytes.AddRange($raw)
        }
        , $bytes.ToArray()
    }
}

Describe 'Network catalogue A / Netzwerkkatalog A' {
    BeforeEach {
        $savedEnv = @{}
        foreach ($name in @('networkPingTargets', 'networkPingCount', 'networkPingTimeoutMs', 'networkMaxLossPercent',
                'networkMaxLatencyMs', 'networkTraceTarget', 'networkTraceMaxHops', 'networkTraceTimeoutMs',
                'networkMinSignalPercent', 'networkWifiMaxProfiles', 'networkExpectedProxy', 'networkRequiredVpnName',
                'networkVpnMaxRecords', 'networkProbeUrl', 'networkProbeExpectedContent', 'networkProbeDnsHost',
                'networkProbeTimeoutMs', 'resultCustomField')) {
            $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Ninja-Property-Set { $global:LASTEXITCODE = 0 }
        Mock Get-Service { [pscustomobject]@{ Name = 'WlanSvc'; Status = 'Running' } }
    }
    AfterEach {
        foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
    }

    Context 'testPingTargets' {
        It 'Reports healthy targets and writes the field / Meldet gesunde Ziele und schreibt das Feld' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } {
                New-FakePing -Replies @((New-Reply -Status Success -Ms 5), (New-Reply -Status Success -Ms 15))
            }
            $env:networkPingTargets = '192.168.1.1, gateway.contoso.local'
            $env:resultCustomField = 'pingStatus'
            $report = (& $pingScript -EchoCount 2) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.targets).Count | Should -Be 2
            $report.targets[0].avgMs | Should -Be 10
            $report.targets[0].maxMs | Should -Be 15
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'pingStatus' }
        }
        It 'Warns on loss and latency / Warnt bei Verlust und Latenz' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } {
                New-FakePing -Replies @((New-Reply -Status Success), (New-Reply -Status TimedOut))
            }
            $report = (& $pingScript -Targets 10.0.0.1 -EchoCount 2) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.targets[0].lossPercent | Should -Be 50
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } {
                New-FakePing -Replies @((New-Reply -Status Success -Ms 500))
            }
            $null = & $pingScript -Targets 10.0.0.1 -EchoCount 1
            $LASTEXITCODE | Should -Be 2
        }
        It 'Counts DNS failures as total loss / Wertet DNS-Fehler als Totalverlust' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } { New-FakePing -Replies @('throw') }
            $report = (& $pingScript -Targets unknown.contoso.local) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.targets[0].lossPercent | Should -Be 100
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } { New-FakePing -Replies @((New-Reply -Status Success)) }
            foreach ($case in @(
                    @{ Targets = '' }, @{ Targets = 'null' }, @{ Targets = 'http://x.local' }, @{ Targets = '10.1' },
                    @{ Targets = '1.1.1.1;2.2.2.2;3.3.3.3;4.4.4.4;5.5.5.5;6.6.6.6;7.7.7.7;8.8.8.8;9.9.9.9;10.10.10.10;11.11.11.11' },
                    @{ Targets = 'a.local'; EchoCount = '0' }, @{ Targets = 'a.local'; TimeoutMs = '50' },
                    @{ Targets = 'a.local'; MaxLossPercent = '101' }, @{ Targets = 'a.local'; CustomField = 'bad-name' },
                    @{ Targets = 'a.local,b.local,c.local'; EchoCount = '10'; TimeoutMs = '5000' })) {
                $null = & $pingScript @case
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
        }
        It 'Skips the field write with WhatIf / Ueberspringt Feldschreiben mit WhatIf' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } { New-FakePing -Replies @((New-Reply -Status Success)) }
            $null = & $pingScript -Targets 10.0.0.1 -CustomField pingStatus -WhatIf
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Ninja-Property-Set -Times 0 -Exactly
        }
    }

    Context 'testTraceRoute' {
        It 'Reports hops until the target / Meldet Hops bis zum Ziel' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } {
                New-FakePing -Replies @((New-Reply -Status TtlExpired -Address 10.0.0.1), (New-Reply -Status TimedOut -Address 0.0.0.0), (New-Reply -Status Success -Address 8.8.8.8))
            }
            $report = (& $traceScript -Target 8.8.8.8 -CustomField traceRoute) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.hopCount | Should -Be 3
            $report.hops[1].address | Should -BeNullOrEmpty
            $report.hops[2].address | Should -Be '8.8.8.8'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when the target is not reached / Warnt, wenn das Ziel nicht erreicht wird' {
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } { New-FakePing -Replies @((New-Reply -Status TimedOut)) }
            $env:networkTraceTarget = 'remote.contoso.com'
            $env:networkTraceMaxHops = '5'
            $report = (& $traceScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.hopCount | Should -Be 5
            Mock New-Object -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' } { New-FakePing -Replies @((New-Reply -Status DestinationHostUnreachable)) }
            $report = (& $traceScript -Target 10.9.9.9) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.hopCount | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($case in @(@{ Target = '' }, @{ Target = 'a.local b.local' }, @{ Target = 'x.local'; MaxHops = '31' },
                    @{ Target = 'x.local'; MaxHops = 'abc' }, @{ Target = 'x.local'; TimeoutMs = '6000' })) {
                $null = & $traceScript @case
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'readWifiStatus' {
        BeforeEach {
            $global:NetTestA_wifiLines = @(
                'There is 1 interface on the system:', '',
                '    Name                   : Wi-Fi', '    Description            : Intel(R) Wi-Fi 6 AX201',
                '    State                  : connected', '    SSID                   : Contoso',
                '    BSSID                  : aa:bb:cc:dd:ee:ff', '    Radio type             : 802.11ax',
                '    Authentication         : WPA2-Enterprise', '    Channel                : 36',
                '    Signal                 : 78%', '    Profile                : Contoso')
            Mock netsh { $global:LASTEXITCODE = 0; $global:NetTestA_wifiLines }
        }
        It 'Parses English output / Liest englische Ausgabe' {
            $report = (& $wifiStatusScript -CustomField wifiStatus) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.status | Should -Be 'Wireless'
            $report.interfaces[0].ssid | Should -Be 'Contoso'
            $report.interfaces[0].bssid | Should -Be 'aa:bb:cc:dd:ee:ff'
            $report.interfaces[0].signalPercent | Should -Be 78
            $report.interfaces[0].channel | Should -Be '36'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'wifiStatus' }
        }
        It 'Warns on weak German signal / Warnt bei schwachem Signal (deutsch)' {
            $global:NetTestA_wifiLines = @('    Name                   : WLAN', '    Status                 : Verbunden',
                '    SSID                   : Gast', '    Funktyp                : 802.11ac', '    Kanal                  : 6',
                '    Authentifizierung      : WPA2-Personal', '    Signal                 : 30 %')
            $report = (& $wifiStatusScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.interfaces[0].radioType | Should -Be '802.11ac'
            $report.interfaces[0].lowSignal | Should -BeTrue
        }
        It 'Reports NoWireless without WLAN service / Meldet NoWireless ohne WLAN-Dienst' {
            Mock Get-Service { }
            $report = (& $wifiStatusScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.status | Should -Be 'NoWireless'
            Should -Invoke netsh -Times 0 -Exactly
            $global:NetTestA_wifiLines = @('There is no wireless interface on the system.')
            Mock Get-Service { [pscustomobject]@{ Name = 'WlanSvc'; Status = 'Running' } }
            $report = (& $wifiStatusScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.status | Should -Be 'NoWireless'
        }
        It 'Fails on netsh errors and invalid input / Fehler bei netsh und Eingaben' {
            Mock netsh { $global:LASTEXITCODE = 1; 'Access is denied.' }
            $null = & $wifiStatusScript
            $LASTEXITCODE | Should -Be 1
            $null = & $wifiStatusScript -MinSignalPercent 0
            $LASTEXITCODE | Should -Be 1
            $env:networkMinSignalPercent = 'abc'
            $null = & $wifiStatusScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readWifiProfiles' {
        BeforeEach {
            Mock netsh {
                $global:LASTEXITCODE = 0
                $joined = $Arguments -join '|'
                if ($joined -eq 'wlan|show|profiles') {
                    'Profiles on interface Wi-Fi:', '', 'User profiles', '-------------',
                    '    All User Profile     : Contoso Corp', '    All User Profile     : Cafe: Free',
                    '    Profil fuer alle Benutzer : OldWep', '    All User Profile     : Bad"Name'
                } elseif ($joined -eq 'wlan|show|profile|name=Contoso Corp') {
                    '    Connection mode        : Connect automatically', '    Authentication         : WPA2-Enterprise',
                    '    Cipher                 : CCMP', '    Security key           : Absent'
                } elseif ($joined -eq 'wlan|show|profile|name=Cafe: Free') {
                    '    Authentication         : Open', '    Cipher                 : None', '    Security key           : Absent'
                } elseif ($joined -eq 'wlan|show|profile|name=OldWep') {
                    '    Authentifizierung      : Offen', '    Verschluesselung       : WEP', '    Sicherheitsschluessel  : Vorhanden'
                } else {
                    $global:LASTEXITCODE = 1
                    'Profile not found'
                }
            }
        }
        It 'Classifies profiles and never requests keys / Klassifiziert ohne Schluesselabfrage' {
            $report = (& $wifiProfilesScript -CustomField wifiProfiles) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.totalProfiles | Should -Be 4
            $report.insecureProfiles | Should -Be 2
            ($report.profiles | Where-Object name -eq 'Contoso Corp').classification | Should -Be 'Secured'
            ($report.profiles | Where-Object name -eq 'Cafe: Free').classification | Should -Be 'Open'
            ($report.profiles | Where-Object name -eq 'OldWep').classification | Should -Be 'WEP'
            ($report.profiles | Where-Object name -eq 'Bad"Name').classification | Should -Be 'Skipped'
            Should -Invoke netsh -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -match 'key=' }
            Should -Invoke netsh -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -match 'Bad' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Returns 0 for secured profiles only / Exit 0 nur mit sicheren Profilen' {
            $report = (& $wifiProfilesScript -MaxProfiles 1) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.truncated | Should -BeTrue
            $report.queriedProfiles | Should -Be 1
        }
        It 'Reports NoWireless and rejects invalid input / NoWireless und ungueltige Eingaben' {
            Mock Get-Service { [pscustomobject]@{ Name = 'WlanSvc'; Status = 'Stopped' } }
            $report = (& $wifiProfilesScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.status | Should -Be 'NoWireless'
            foreach ($value in @('0', '101', 'x')) {
                $null = & $wifiProfilesScript -MaxProfiles $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkProxySettings' {
        BeforeEach {
            $global:NetTestA_winHttp = New-WinHttpBytes -Flags 3 -Proxy 'proxy.contoso.local:8080' -Bypass '<local>'
            Mock Get-ItemProperty {
                if ($Path -like '*\Connections') { [pscustomobject]@{ WinHttpSettings = $global:NetTestA_winHttp } }
                elseif ($Path -like '*Policies*') { [pscustomobject]@{ ProxySettingsPerUser = 0 } }
                else { [pscustomobject]@{ ProxyEnable = 1; ProxyServer = 'user:secret@proxy.contoso.local:8080' } }
            }
        }
        It 'Decodes WinHTTP and hides credentials / Dekodiert WinHTTP ohne Zugangsdaten' {
            $output = & $proxyScript -ExpectedProxy 'PROXY.contoso.local:8080' -CustomField proxyStatus
            $LASTEXITCODE | Should -Be 0
            $output | Should -Not -Match 'secret'
            $report = $output | ConvertFrom-Json
            $report.winHttp.accessType | Should -Be 'NamedProxy'
            $report.winHttp.bypassList | Should -Be '<local>'
            $report.proxyScope | Should -Match 'MachineWide'
            $report.machineInternetSettings.proxyServer | Should -Be 'proxy.contoso.local:8080'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on mismatch / Warnt bei Abweichung' {
            $env:networkExpectedProxy = 'direct'
            $report = (& $proxyScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.matchesExpected | Should -BeFalse
            $global:NetTestA_winHttp = New-WinHttpBytes -Flags 1 -Proxy '' -Bypass ''
            $null = & $proxyScript -ExpectedProxy direct
            $LASTEXITCODE | Should -Be 0
            $null = & $proxyScript -ExpectedProxy other.local:3128
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input and malformed data / Lehnt ungueltige Daten ab' {
            $null = & $proxyScript -ExpectedProxy 'http://proxy/ x'
            $LASTEXITCODE | Should -Be 1
            $global:NetTestA_winHttp = [byte[]](40, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 255, 0, 0, 0, 65)
            $null = & $proxyScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkVpnConnections' {
        BeforeEach {
            Mock Get-VpnConnection {
                [pscustomobject]@{ Name = 'Contoso VPN'; ServerAddress = 'vpn.contoso.com'; TunnelType = 'Ikev2'; AuthenticationMethod = @('Eap'); SplitTunneling = $true; ConnectionStatus = 'Disconnected' }
                [pscustomobject]@{ Name = 'Backup'; ServerAddress = 'vpn2.contoso.com'; TunnelType = 'Sstp'; AuthenticationMethod = @('MSChapv2'); SplitTunneling = $false; ConnectionStatus = 'Connected' }
            }
        }
        It 'Inventories connections / Inventarisiert Verbindungen' {
            $report = (& $vpnScript -RequiredConnection 'contoso vpn' -CustomField vpnConnections) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 2
            $report.requiredPresent | Should -BeTrue
            ($report.connections | Where-Object name -eq 'Contoso VPN').splitTunneling | Should -BeTrue
            Should -Invoke Get-VpnConnection -Times 1 -Exactly -ParameterFilter { $AllUserConnection }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when the required connection is missing / Warnt bei fehlender Pflichtverbindung' {
            $env:networkRequiredVpnName = 'Fabrikam VPN'
            $report = (& $vpnScript -MaxRecords 1) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.truncated | Should -BeTrue
            Mock Get-VpnConnection { }
            $null = & $vpnScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input and query errors / Lehnt Eingaben und Abfragefehler ab' {
            foreach ($case in @(@{ RequiredConnection = 'VPN*' }, @{ MaxRecords = '0' }, @{ CustomField = '1field' })) {
                $null = & $vpnScript @case
                $LASTEXITCODE | Should -Be 1
            }
            Mock Get-VpnConnection { Write-Error -Message 'Access denied' -Category PermissionDenied }
            $null = & $vpnScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkInternetConnectivity' {
        BeforeAll {
            $probe = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
            $probe.Start()
            $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
            $probe.Stop()
            $baseUrl = 'http://127.0.0.1:{0}/' -f $port
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add($baseUrl)
            $listener.Start()
            $server = [powershell]::Create()
            $null = $server.AddScript({
                    param($l)
                    while ($l.IsListening) {
                        try { $context = $l.GetContext() } catch { break }
                        $path = $context.Request.Url.AbsolutePath
                        $text = 'Microsoft Connect Test'
                        if ($path -eq '/portal') { $context.Response.StatusCode = 302; $context.Response.RedirectLocation = 'http://portal.local/'; $text = '' }
                        elseif ($path -eq '/other') { $text = '<html>login</html>' }
                        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
                        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                        $context.Response.Close()
                    }
                }).AddArgument($listener)
            $null = $server.BeginInvoke()
            $closedPort = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
            $closedPort.Start()
            $deadUrl = 'http://127.0.0.1:{0}/' -f ([System.Net.IPEndPoint]$closedPort.LocalEndpoint).Port
            $closedPort.Stop()
        }
        AfterAll {
            $listener.Stop()
            $listener.Close()
            $server.Dispose()
        }
        BeforeEach {
            Mock Resolve-DnsName { [pscustomobject]@{ Name = $Name; IPAddress = '192.0.2.10' } }
        }
        It 'Confirms connectivity / Bestaetigt Verbindung' {
            $report = (& $internetScript -ProbeUrl ($baseUrl + 'connecttest.txt') -DnsProbeHost www.msftconnecttest.com -CustomField internetProbe) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.dnsResolved | Should -BeTrue
            $report.httpStatus | Should -Be 200
            $report.contentMatches | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on mismatch, redirect, DNS and connection failure / Warnt bei Abweichung, Weiterleitung, DNS- und Verbindungsfehler' {
            $report = (& $internetScript -ProbeUrl ($baseUrl + 'other')) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.dnsResolved | Should -BeNullOrEmpty
            $report.result | Should -Match 'mismatch'
            $report = (& $internetScript -ProbeUrl ($baseUrl + 'portal')) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.httpStatus | Should -Be 302
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            $report = (& $internetScript -ProbeUrl ($baseUrl + 'connecttest.txt') -DnsProbeHost missing.contoso.local) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.dnsResolved | Should -BeFalse
            $env:networkProbeUrl = $deadUrl
            $env:networkProbeTimeoutMs = '2000'
            $report = (& $internetScript) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.result | Should -Match 'unreachable'
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($case in @(@{ ProbeUrl = 'ftp://example.com/x' }, @{ ProbeUrl = 'file:///c:/windows/win.ini' },
                    @{ ProbeUrl = ('http://user:pw' + '@example.com/') }, @{ ProbeUrl = 'not a url' },
                    @{ TimeoutMs = '500' }, @{ DnsProbeHost = 'bad host' }, @{ ExpectedContent = ('x' * 201) })) {
                $null = & $internetScript @case
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
    }
}
