BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:serverScript = Join-Path $root '05 - DNS/testDnsServerResponse.ps1'
    $script:suffixScript = Join-Path $root '05 - DNS/checkDnsSuffixSearchList.ps1'
    $script:hostsScript = Join-Path $root '05 - DNS/checkHostsFile.ps1'
    $script:registrationScript = Join-Path $root '05 - DNS/checkDnsRegistration.ps1'
    $script:reverseScript = Join-Path $root '05 - DNS/checkReverseDnsRecord.ps1'
    $script:nrptScript = Join-Path $root '05 - DNS/readNrptPolicy.ps1'
    $script:dohScript = Join-Path $root '05 - DNS/checkDnsOverHttps.ps1'
    $script:llmnrScript = Join-Path $root '05 - DNS/checkLlmnrNetbiosStatus.ps1'
    $script:compareScript = Join-Path $root '05 - DNS/compareDnsServerResponses.ps1'
    $script:srvScript = Join-Path $root '05 - DNS/checkDomainSrvRecords.ps1'
    $script:eventScript = Join-Path $root '05 - DNS/readDnsClientEvents.ps1'

    # DE: Stubs für Windows-Cmdlets und NinjaOne, damit Mock unter Linux funktioniert.
    # EN: Stubs for Windows cmdlets and NinjaOne so Mock works on Linux.
    function Resolve-DnsName { param($Name, $Type, $Server, [switch]$DnsOnly, [switch]$NoHostsFile, [switch]$QuickTimeout) }
    function Get-NetAdapter { param($InterfaceIndex) }
    function Get-NetIPAddress { param($AddressFamily, $InterfaceIndex) }
    function Get-DnsClientServerAddress { param($InterfaceIndex, $AddressFamily) }
    function Get-DnsClientGlobalSetting { }
    function Get-DnsClientNrptPolicy { }
    function Get-DnsClientNrptRule { }
    function Get-DnsClientDohServerAddress { }
    function Get-CimInstance { param($ClassName, $Namespace, $Filter) }
    function Get-WinEvent { param($FilterHashtable, $MaxEvents) }
    function Ninja-Property-Set { param($Name, $Value) }

    $script:envNames = @(
        'dnsTestName', 'dnsTestServers', 'dnsLatencyThresholdMs', 'dnsExpectedSuffixSearchList', 'dnsSuffixOrderMatters',
        'dnsExpectedPrimarySuffix', 'dnsHostsAllowList', 'dnsHostsWarnOnAnyEntry', 'dnsHostsMaxRecords', 'dnsRegistrationFqdn',
        'dnsRegistrationServer', 'dnsReverseExpectedName', 'dnsReverseServer', 'dnsNrptMaxRecords', 'dnsRequireDoh',
        'dnsRequireMdnsDisabled', 'dnsCompareHostName', 'dnsCompareServers', 'dnsCompareRecordType', 'dnsSrvServer',
        'dnsEventHours', 'dnsEventThreshold', 'dnsEventIds', 'dnsEventMaxEvents', 'dnsEventMaxRecords', 'resultCustomField',
        'SystemRoot', 'COMPUTERNAME'
    )
}

Describe 'DNS catalogue checks / DNS-Katalogprüfungen' {
    BeforeEach {
        $script:saved = @{}
        foreach ($name in $script:envNames) {
            $script:saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $global:DnsCatalog_Tcpip = [pscustomobject]@{ Hostname = 'pc01'; Domain = 'corp.contoso.com'; 'NV Domain' = 'corp.contoso.com' }
        Mock Ninja-Property-Set { }
        Mock Get-NetAdapter {
            [pscustomobject]@{ InterfaceIndex = 5; Status = 'Up' }
            [pscustomobject]@{ InterfaceIndex = 7; Status = 'Disconnected' }
        }
        Mock Get-NetIPAddress {
            [pscustomobject]@{ InterfaceIndex = 5; IPAddress = '10.0.0.20'; AddressState = 'Preferred' }
            [pscustomobject]@{ InterfaceIndex = 5; IPAddress = '169.254.10.1'; AddressState = 'Preferred' }
            [pscustomobject]@{ InterfaceIndex = 5; IPAddress = 'fe80::1%5'; AddressState = 'Preferred' }
            [pscustomobject]@{ InterfaceIndex = 1; IPAddress = '127.0.0.1'; AddressState = 'Preferred' }
            [pscustomobject]@{ InterfaceIndex = 7; IPAddress = '10.5.5.5'; AddressState = 'Preferred' }
        }
        Mock Get-DnsClientServerAddress {
            [pscustomobject]@{ InterfaceIndex = 5; ServerAddresses = @('10.0.0.10', 'fec0:0:0:ffff::1') }
            [pscustomobject]@{ InterfaceIndex = 7; ServerAddresses = @('10.9.9.9') }
        }
        Mock Get-ItemProperty { $global:DnsCatalog_Tcpip } -ParameterFilter { "$LiteralPath" -like '*Tcpip\Parameters' }
    }
    AfterEach {
        foreach ($name in $script:saved.Keys) { [Environment]::SetEnvironmentVariable($name, $script:saved[$name]) }
    }

    Context 'testDnsServerResponse' {
        BeforeEach {
            Mock Resolve-DnsName { [pscustomobject]@{ Name = $Name; Type = 'A'; Section = 'Answer'; IPAddress = '20.1.2.3' } }
        }
        It 'Tests configured servers of connected adapters / Prüft Server verbundener Adapter' {
            $report = & $script:serverScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'Configured'
            @($report.Results).Count | Should -Be 1
            $report.Results[0].Server | Should -Be '10.0.0.10'
            $report.Results[0].Status | Should -Be 'OK'
        }
        It 'Warns on a failing explicit server and writes the field / Warnt bei Fehler und schreibt Feld' {
            Mock Resolve-DnsName { if ($Server -eq '10.0.0.11') { throw 'timeout' } [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '20.1.2.3' } }
            $env:dnsTestServers = '10.0.0.10, 10.0.0.11'
            $env:resultCustomField = 'dnsServerHealth'
            $report = & $script:serverScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FailedServers | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'dnsServerHealth' }
        }
        It 'Warns on slow servers / Warnt bei langsamen Servern' {
            Mock Resolve-DnsName { Start-Sleep -Milliseconds 80; [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '20.1.2.3' } }
            $report = & $script:serverScript -LatencyThresholdMs 10 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.SlowServers | Should -Be 1
        }
        It 'Warns when no DNS server is configured / Warnt ohne DNS-Server' {
            Mock Get-DnsClientServerAddress { }
            $null = & $script:serverScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ TestName = '*.contoso.com' }, @{ Servers = 'dns.contoso.com' }, @{ LatencyThresholdMs = '0' }, @{ CustomField = '1bad' })) {
                $null = & $script:serverScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
    }

    Context 'checkDnsSuffixSearchList' {
        BeforeEach {
            Mock Get-DnsClientGlobalSetting { [pscustomobject]@{ SuffixSearchList = @('corp.contoso.com', 'contoso.com') } }
        }
        It 'Matches regardless of order / Stimmt unabhängig von Reihenfolge' {
            $env:dnsExpectedSuffixSearchList = 'Contoso.com., corp.contoso.com'
            $report = & $script:suffixScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.ListMatches | Should -BeTrue
            $report.PrimaryDnsSuffix | Should -Be 'corp.contoso.com'
        }
        It 'Warns on order mismatch when order matters / Warnt bei falscher Reihenfolge' {
            $report = & $script:suffixScript -ExpectedSuffixes 'contoso.com,corp.contoso.com' -OrderMatters true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.OrderMatches | Should -BeFalse
        }
        It 'Warns on missing suffix and wrong primary suffix / Warnt bei fehlendem Suffix' {
            $report = & $script:suffixScript -ExpectedSuffixes 'corp.contoso.com,contoso.com,fabrikam.com' -ExpectedPrimarySuffix fabrikam.com -CustomField dnsSuffixReport | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.MissingSuffixes) | Should -Be @('fabrikam.com')
            $report.PrimarySuffixMatches | Should -BeFalse
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Reports only without expected values / Nur Bericht ohne Sollwerte' {
            $report = & $script:suffixScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.ListCompared | Should -BeFalse
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ ExpectedSuffixes = 'bad suffix' }, @{ OrderMatters = 'maybe' }, @{ ExpectedPrimarySuffix = '-x.com' })) {
                $null = & $script:suffixScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Get-DnsClientGlobalSetting -Times 0 -Exactly
        }
    }

    Context 'checkHostsFile' {
        BeforeEach {
            $env:SystemRoot = Join-Path $TestDrive 'Windows'
            $script:etc = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'drivers', 'etc')
            $null = New-Item -ItemType Directory -Path $script:etc -Force
            $script:hostsPath = Join-Path $script:etc 'hosts'
            Set-Content -LiteralPath $script:hostsPath -Value @('# comment', '#  10.0.0.1 commented.example.com', '127.0.0.1 localhost', '') -Encoding ascii
        }
        It 'Accepts comments and localhost / Akzeptiert Kommentare und localhost' {
            $report = & $script:hostsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Exists | Should -BeTrue
            $report.TotalActiveEntries | Should -Be 1
            $report.Sha256 | Should -Match '^[0-9A-F]{64}$'
        }
        It 'Warns on any active entry by default / Warnt standardmäßig bei aktiven Einträgen' {
            Add-Content -LiteralPath $script:hostsPath -Value "10.1.1.1`tevil.example.com alias.example.com # note"
            $report = & $script:hostsScript -CustomField hostsFileReport | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.UnexpectedEntries | Should -Be 2
            $report.Entries[0].HostName | Should -Be 'evil.example.com'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'hostsFileReport' }
        }
        It 'Honours the allowlist / Beachtet die Positivliste' {
            Add-Content -LiteralPath $script:hostsPath -Value '10.1.1.1 Intranet.contoso.com'
            $env:dnsHostsAllowList = 'intranet.contoso.com'
            $null = & $script:hostsScript
            $LASTEXITCODE | Should -Be 0
            $null = & $script:hostsScript -AllowedHostNames 'other.contoso.com'
            $LASTEXITCODE | Should -Be 2
        }
        It 'Is informational without allowlist when warning is off / Nur Bericht ohne Warnung' {
            Add-Content -LiteralPath $script:hostsPath -Value '10.1.1.1 intranet.contoso.com'
            $null = & $script:hostsScript -WarnOnAnyEntry false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Flags malformed lines and truncates records / Meldet fehlerhafte Zeilen und kürzt' {
            Add-Content -LiteralPath $script:hostsPath -Value @('not-an-ip host.example.com', '10.1.1.1 a.example.com', '10.1.1.2 b.example.com')
            $report = & $script:hostsScript -MaxRecords 2 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.MalformedLines | Should -Be 1
            $report.Truncated | Should -BeTrue
            @($report.Entries).Count | Should -Be 2
        }
        It 'Treats a missing hosts file as OK / Fehlende Datei ist OK' {
            Remove-Item -LiteralPath $script:hostsPath
            $report = & $script:hostsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Exists | Should -BeFalse
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ AllowedHostNames = '*.contoso.com' }, @{ MaxRecords = '0' }, @{ WarnOnAnyEntry = 'yes' })) {
                $null = & $script:hostsScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkDnsRegistration' {
        BeforeEach {
            Mock Resolve-DnsName {
                if ($Type -eq 'A') { [pscustomobject]@{ Name = $Name; Type = 'A'; Section = 'Answer'; IPAddress = '10.0.0.20' } }
                else { [pscustomobject]@{ Name = 'contoso.com'; Type = 'SOA'; Section = 'Authority' } }
            }
        }
        It 'Matches the local address / Passt zur lokalen Adresse' {
            $report = & $script:registrationScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Fqdn | Should -Be 'pc01.corp.contoso.com'
            $report.Status | Should -Be 'OK'
            @($report.LocalAddresses) | Should -Be @('10.0.0.20')
        }
        It 'Warns on stale records / Warnt bei veralteten Einträgen' {
            Mock Resolve-DnsName {
                if ($Type -eq 'A') {
                    [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '10.0.0.20' }
                    [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '10.0.0.99' }
                }
            }
            $report = & $script:registrationScript -CustomField dnsRegistrationReport | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'Stale'
            @($report.StaleAddresses) | Should -Be @('10.0.0.99')
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when not registered / Warnt ohne Eintrag' {
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            $report = & $script:registrationScript -Fqdn 'pc02.corp.contoso.com' -Server '10.0.0.10' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'NotRegistered'
            Should -Invoke Resolve-DnsName -ParameterFilter { $Server -eq '10.0.0.10' -and $Name -eq 'pc02.corp.contoso.com' }
        }
        It 'Is not applicable without primary suffix / Ohne primäres Suffix nicht anwendbar' {
            $global:DnsCatalog_Tcpip = [pscustomobject]@{ Hostname = 'pc01'; Domain = '' }
            $report = & $script:registrationScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'NotApplicable'
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ Server = 'dns01' }, @{ Fqdn = 'bad_name.contoso.com' }, @{ CustomField = 'bad-field' })) {
                $null = & $script:registrationScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkReverseDnsRecord' {
        BeforeEach {
            Mock Resolve-DnsName { [pscustomobject]@{ Type = 'PTR'; Section = 'Answer'; NameHost = 'PC01.corp.contoso.com.' } }
        }
        It 'Matches PTR to FQDN / PTR passt zum FQDN' {
            $report = & $script:reverseScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Results).Count | Should -Be 1
            $report.Results[0].Address | Should -Be '10.0.0.20'
            $report.Results[0].Status | Should -Be 'OK'
        }
        It 'Warns on mismatch / Warnt bei Abweichung' {
            Mock Resolve-DnsName { [pscustomobject]@{ Type = 'PTR'; Section = 'Answer'; NameHost = 'old-pc.corp.contoso.com' } }
            $report = & $script:reverseScript -CustomField dnsReverseReport | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Results[0].Status | Should -Be 'Mismatch'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on missing PTR / Warnt bei fehlendem PTR' {
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            $report = & $script:reverseScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Results[0].Status | Should -Be 'Missing'
        }
        It 'Compares the first label without primary suffix / Vergleicht Label ohne Suffix' {
            $global:DnsCatalog_Tcpip = [pscustomobject]@{ Hostname = 'pc01'; Domain = '' }
            $null = & $script:reverseScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ Server = '10.0.0.300' }, @{ ExpectedName = 'a..b' })) {
                $null = & $script:reverseScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
    }

    Context 'readNrptPolicy' {
        BeforeEach {
            Mock Get-DnsClientNrptPolicy { [pscustomobject]@{ Namespace = '.corp.contoso.com'; NameServers = @('10.0.0.10'); QueryPolicy = 'QueryIPv6Only' } }
            Mock Get-DnsClientNrptRule {
                [pscustomobject]@{ Name = '{A}'; Namespace = @('.corp.contoso.com'); NameServers = @('10.0.0.10', '10.0.0.11'); DirectAccessEnabled = $false }
                [pscustomobject]@{ Name = '{B}'; Namespace = @('.lab.contoso.com'); NameServers = @('10.1.0.10'); DnsSecEnabled = $true }
            }
        }
        It 'Reports policy and rules / Meldet Richtlinie und Regeln' {
            $report = & $script:nrptScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalRules | Should -Be 2
            $report.Rules[0].NameServers | Should -Be '10.0.0.10,10.0.0.11'
        }
        It 'Truncates and writes the field / Kürzt und schreibt Feld' {
            $env:dnsNrptMaxRecords = '1'
            $env:resultCustomField = 'dnsNrptReport'
            $report = & $script:nrptScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RulesTruncated | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'dnsNrptReport' }
        }
        It 'Reports field write failures / Meldet Schreibfehler' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $script:nrptScript -CustomField dnsNrptReport
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input and query errors / Lehnt Fehler ab' {
            $null = & $script:nrptScript -MaxRecords 101
            $LASTEXITCODE | Should -Be 1
            Mock Get-DnsClientNrptRule { throw 'access denied' }
            $null = & $script:nrptScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkDnsOverHttps' {
        BeforeEach {
            $global:DnsCatalog_DohPolicy = $null
            Mock Test-Path { $null -ne $global:DnsCatalog_DohPolicy } -ParameterFilter { "$LiteralPath" -like '*Windows NT\DNSClient' }
            Mock Get-ItemProperty { [pscustomobject]@{ DoHPolicy = $global:DnsCatalog_DohPolicy } } -ParameterFilter { "$LiteralPath" -like '*Windows NT\DNSClient' }
            Mock Get-DnsClientDohServerAddress {
                [pscustomobject]@{ ServerAddress = '10.0.0.10'; DohTemplate = 'https://dns.contoso.com/dns-query'; AllowFallbackToUdp = $true; AutoUpgrade = $false }
            }
        }
        It 'Reports without requirement / Meldet ohne Anforderung' {
            $report = & $script:dohScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Supported | Should -BeTrue
            $report.Status | Should -Be 'NotEnforced'
            $report.ConfiguredServers[0].State | Should -Be 'DohWithFallback'
        }
        It 'Warns when DoH is required but not enforced / Warnt bei fehlender Erzwingung' {
            $null = & $script:dohScript -RequireDoh true -CustomField dnsDohReport
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Accepts the Require policy / Akzeptiert Require-Richtlinie' {
            $global:DnsCatalog_DohPolicy = 3
            $report = & $script:dohScript -RequireDoh 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.DoHPolicyText | Should -Be 'Require'
        }
        It 'Accepts DoH-only servers / Akzeptiert DoH-only-Server' {
            Mock Get-DnsClientDohServerAddress { [pscustomobject]@{ ServerAddress = '10.0.0.10'; DohTemplate = 'https://dns.contoso.com/dns-query'; AllowFallbackToUdp = $false } }
            $env:dnsRequireDoh = 'true'
            $null = & $script:dohScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Reports NotSupported without error / Meldet NotSupported ohne Fehler' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-DnsClientDohServerAddress' }
            $report = & $script:dohScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'NotSupported'
            $null = & $script:dohScript -RequireDoh true
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $script:dohScript -RequireDoh yes
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkLlmnrNetbiosStatus' {
        BeforeEach {
            $global:DnsCatalog_Llmnr = 0
            $global:DnsCatalog_Mdns = 0
            Mock Test-Path { $true } -ParameterFilter { "$LiteralPath" -like 'HKLM:*' }
            Mock Get-ItemProperty { [pscustomobject]@{ EnableMulticast = $global:DnsCatalog_Llmnr } } -ParameterFilter { "$LiteralPath" -like '*Windows NT\DNSClient' }
            Mock Get-ItemProperty { [pscustomobject]@{ EnableMDNS = $global:DnsCatalog_Mdns } } -ParameterFilter { "$LiteralPath" -like '*Dnscache\Parameters' }
            Mock Get-CimInstance { [pscustomobject]@{ Index = 1; InterfaceIndex = 5; Description = 'Ethernet'; TcpipNetbiosOptions = 2 } }
        }
        It 'Reports a hardened system / Meldet gehärtetes System' {
            $report = & $script:llmnrScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.LlmnrEnabled | Should -BeFalse
            $report.Adapters[0].NetbiosState | Should -Be 'Disabled'
        }
        It 'Warns when the LLMNR policy is missing / Warnt ohne LLMNR-Richtlinie' {
            $global:DnsCatalog_Llmnr = $null
            $report = & $script:llmnrScript -CustomField dnsLegacyResolution | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.LlmnrEnabled | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on NetBIOS default / Warnt bei NetBIOS-Standard' {
            Mock Get-CimInstance { [pscustomobject]@{ Index = 1; InterfaceIndex = 5; Description = 'Ethernet'; TcpipNetbiosOptions = 0 } }
            $report = & $script:llmnrScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.NetbiosEnabledAdapters | Should -Be 1
        }
        It 'Treats mDNS as finding only on request / mDNS nur auf Wunsch als Befund' {
            $global:DnsCatalog_Mdns = $null
            $null = & $script:llmnrScript
            $LASTEXITCODE | Should -Be 0
            $env:dnsRequireMdnsDisabled = 'true'
            $null = & $script:llmnrScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $script:llmnrScript -RequireMdnsDisabled maybe
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-CimInstance -Times 0 -Exactly
        }
    }

    Context 'compareDnsServerResponses' {
        BeforeEach {
            Mock Resolve-DnsName {
                if ($Type -eq 'A') {
                    [pscustomobject]@{ Type = 'CNAME'; Section = 'Answer'; NameHost = 'edge.contoso.com' }
                    [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '20.1.1.2' }
                    [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '20.1.1.1' }
                }
            }
        }
        It 'Reports consistent answers / Meldet gleiche Antworten' {
            $report = & $script:compareScript -HostName www.contoso.com -Servers '10.0.0.10,10.0.0.11' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Consistent | Should -BeTrue
            @($report.Results[0].Answers) | Should -Be @('20.1.1.1', '20.1.1.2')
        }
        It 'Warns on differing answers / Warnt bei Abweichungen' {
            Mock Resolve-DnsName { if ($Type -eq 'A') { [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = $(if ($Server -eq '1.1.1.1') { '6.6.6.6' } else { '20.1.1.1' }) } } }
            $env:dnsCompareHostName = 'www.contoso.com'
            $env:dnsCompareServers = '10.0.0.10,1.1.1.1'
            $env:resultCustomField = 'dnsCompareReport'
            $report = & $script:compareScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.DistinctAnswerSets | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when a server fails / Warnt bei Serverfehler' {
            Mock Resolve-DnsName { if ($Server -eq '10.0.0.11') { throw 'timeout' } if ($Type -eq 'A') { [pscustomobject]@{ Type = 'A'; Section = 'Answer'; IPAddress = '20.1.1.1' } } }
            $report = & $script:compareScript -HostName www.contoso.com -Servers '10.0.0.10,10.0.0.11' -RecordType A | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FailedServers | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(
                    @{ Servers = '10.0.0.10,10.0.0.11' },
                    @{ HostName = 'www.contoso.com'; Servers = '10.0.0.10' },
                    @{ HostName = 'www.contoso.com'; Servers = '10.0.0.10,10.0.0.10' },
                    @{ HostName = 'www.contoso.com'; Servers = '1.1.1.1,1.1.1.2,1.1.1.3,1.1.1.4,1.1.1.5,1.1.1.6' },
                    @{ HostName = 'www.contoso.com'; Servers = '10.0.0.10,10.0.0.11'; RecordType = 'MX' })) {
                $null = & $script:compareScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
    }

    Context 'checkDomainSrvRecords' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; Domain = 'corp.contoso.com' } }
            Mock Resolve-DnsName {
                [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; NameTarget = 'dc01.corp.contoso.com'; Port = 389; Priority = 0; Weight = 100 }
                [pscustomobject]@{ Type = 'A'; Section = 'Additional'; IPAddress = '10.0.0.10' }
            }
        }
        It 'Reports SRV records / Meldet SRV-Einträge' {
            $report = & $script:srvScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'OK'
            $report.Queries[0].Query | Should -Be '_ldap._tcp.dc._msdcs.corp.contoso.com'
            $report.Queries[1].Records[0].Target | Should -Be 'dc01.corp.contoso.com'
        }
        It 'Warns on missing records / Warnt bei fehlenden Einträgen' {
            Mock Resolve-DnsName { if ($Name -like '_kerberos*') { throw 'DNS name does not exist' } [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; NameTarget = 'dc01'; Port = 389 } }
            $report = & $script:srvScript -Server 10.0.0.10 -CustomField dnsSrvReport | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'MissingRecords'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Skips workgroup computers / Überspringt Arbeitsgruppen' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false; Domain = 'WORKGROUP' } }
            $report = & $script:srvScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'NotDomainJoined'
            Should -Invoke Resolve-DnsName -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $script:srvScript -Server 'dc01'
            $LASTEXITCODE | Should -Be 1
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; Domain = 'bad domain' } }
            $null = & $script:srvScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readDnsClientEvents' {
        BeforeEach {
            Mock Get-WinEvent {
                $now = Get-Date
                foreach ($i in 1..8) { [pscustomobject]@{ Id = 1014; TimeCreated = $now.AddMinutes(-$i); Properties = @([pscustomobject]@{ Value = 'intranet.contoso.com' }) } }
                foreach ($i in 1..3) { [pscustomobject]@{ Id = 1014; TimeCreated = $now.AddMinutes(-$i); Properties = @([pscustomobject]@{ Value = 'files.contoso.com' }) } }
                [pscustomobject]@{ Id = 1014; TimeCreated = $now; Properties = @([pscustomobject]@{ Value = 'bad name <x>' }) }
            }
        }
        It 'Treats no matching events as OK / Keine Ereignisse sind OK' {
            Mock Get-WinEvent {
                throw [System.Management.Automation.ErrorRecord]::new([Exception]::new('No events were found'), 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
            }
            $report = & $script:eventScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 0
        }
        It 'Groups events and warns at threshold / Gruppiert und warnt ab Grenzwert' {
            $report = & $script:eventScript -CustomField dnsClientEvents | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.TotalEvents | Should -Be 12
            $report.Groups[0].Name | Should -Be 'intranet.contoso.com'
            $report.Groups[0].Count | Should -Be 8
            @($report.Groups.Name) | Should -Contain '(unknown)'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
            Should -Invoke Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-DNS-Client' -and $MaxEvents -eq 1000 -and $FilterHashtable.Id -contains 1014 }
        }
        It 'Stays OK below threshold and truncates groups / Unter Grenzwert OK und gekürzt' {
            $env:dnsEventThreshold = '13'
            $env:dnsEventMaxRecords = '1'
            $report = & $script:eventScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Truncated | Should -BeTrue
            @($report.Groups).Count | Should -Be 1
        }
        It 'Rejects invalid input and query errors / Lehnt Fehler ab' {
            foreach ($arguments in @(@{ Hours = '0' }, @{ EventIds = 'abc' }, @{ MaxEvents = '5001' }, @{ Threshold = '-1' })) {
                $null = & $script:eventScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Get-WinEvent -Times 0 -Exactly
            Mock Get-WinEvent { throw 'Access denied' }
            $null = & $script:eventScript
            $LASTEXITCODE | Should -Be 1
        }
    }
}
