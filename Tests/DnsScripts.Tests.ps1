BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $setScript = Join-Path $root '05 - DNS/01-setDNSSettingsClient.ps1'
    $readScript = Join-Path $root '05 - DNS/00-readDNSSettingsClient.ps1'

    # DE: Stubs erlauben Tests ohne Windows und ohne NinjaOne-Agent.
    # EN: Stubs allow testing without Windows or a NinjaOne agent.
    function Get-NetAdapter { [CmdletBinding()] param($InterfaceIndex) }
    function Get-NetAdapterHardwareInfo { [CmdletBinding()] param($InterfaceIndex) }
    function Get-NetIPConfiguration { [CmdletBinding()] param($InterfaceIndex) }
    function Get-DnsClientServerAddress { [CmdletBinding()] param($InterfaceIndex, $AddressFamily) }
    function Get-DnsClient { [CmdletBinding()] param($InterfaceIndex) }
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Filter) }
    function Ninja-Property-Get { [CmdletBinding()] param([Parameter(Position = 0)]$Name) }
    function Ninja-Property-Set { [CmdletBinding()] param([Parameter(Position = 0)]$Name, [Parameter(Position = 1)]$Value) }
    function netsh { $global:LASTEXITCODE = $global:DnsTest_netshExitCode; 'netsh' }
    function ipconfig { }
    # DE: Job-Stubs ohne Typbindung, damit Testobjekte statt echter Jobs genutzt werden können.
    # EN: Untyped job stubs so test objects can replace real jobs.
    function Start-Job { param($ScriptBlock, $ArgumentList) }
    function Wait-Job { param([Parameter(Position = 0)]$Job, $Timeout) $Job }
    function Receive-Job { [CmdletBinding()] param([Parameter(Position = 0)]$Job) }
    function Remove-Job { param([Parameter(Position = 0)]$Job, [switch]$Force) }
    function Stop-Job { param([Parameter(Position = 0)]$Job) }

    function New-TestAdapter {
        param([int]$Index, [string]$Name, [string]$Ip, [string]$Gateway)
        [pscustomobject]@{
            Name = $Name; InterfaceAlias = $Name; ifIndex = $Index; InterfaceIndex = $Index
            InterfaceDescription = 'Intel(R) Ethernet Connection'; Status = 'Up'; Speed = 1000000000
            InterfaceGuid = "{0000000$Index-0000-0000-0000-000000000000}"
            TestIp = $Ip; TestGateway = $Gateway
        }
    }
}

Describe 'DNS set script / DNS-Setzskript' {
    BeforeEach {
        $global:DnsTest_netshExitCode = 0
        $global:DnsTest_customFields = @{}
        $global:DnsTest_adapters = @(New-TestAdapter -Index 5 -Name 'Ethernet' -Ip '192.168.10.20' -Gateway '192.168.10.1')
        $global:DnsTest_currentDns = '192.168.10.1'
        $global:DnsTest_nameServer = '192.168.10.1'
        $savedProgramData = $env:ProgramData
        $savedTemp = $env:TEMP
        $env:ProgramData = $TestDrive
        $env:TEMP = $TestDrive

        Mock Get-NetAdapter {
            if ($InterfaceIndex) { $global:DnsTest_adapters | Where-Object ifIndex -eq $InterfaceIndex } else { $global:DnsTest_adapters }
        }
        Mock Get-NetIPConfiguration {
            $a = $global:DnsTest_adapters | Where-Object ifIndex -eq $InterfaceIndex
            # DE: Einzelne Adresse wie unter Windows (kein Array). EN: Single address as on Windows (no array).
            [pscustomobject]@{
                IPv4Address = [pscustomobject]@{ IPAddress = $a.TestIp }
                IPv4DefaultGateway = if ($a.TestGateway) { [pscustomobject]@{ NextHop = $a.TestGateway } }
            }
        }
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @($global:DnsTest_currentDns -split ',') } }
        Mock Get-ItemProperty { [pscustomobject]@{ NameServer = $global:DnsTest_nameServer } }
        Mock Ninja-Property-Get { $global:DnsTest_customFields[$Name] }
        Mock Ninja-Property-Set {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock Start-Job { [pscustomobject]@{ State = 'Completed' } }
        Mock Wait-Job { $Job }
        Mock Receive-Job {}
        Mock Remove-Job {}
        Mock Stop-Job {}
        Mock netsh { $global:LASTEXITCODE = $global:DnsTest_netshExitCode }
    }
    AfterEach {
        $env:ProgramData = $savedProgramData
        $env:TEMP = $savedTemp
    }

    It 'Matches single-address adapters by gateway / Erkennt Adapter mit einer Adresse per Gateway' {
        $null = & $setScript -PrimaryDNS 10.0.0.10 -SecondaryDNS 10.0.0.11 -TargetGateway 192.168.10.1 4>$null
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Start-Job -Times 1 -Exactly
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'DNS_LastChange' }
    }

    It 'Matches single-address adapters by subnet / Erkennt Adapter mit einer Adresse per Subnetz' {
        $null = & $setScript -PrimaryDNS 10.0.0.10 -TargetSubnet 192.168.10.0/24 4>$null
        $LASTEXITCODE | Should -Be 0
    }

    It 'Reports nothing to do without writing the field / Meldet nichts zu tun ohne Feldschreibvorgang' {
        $global:DnsTest_currentDns = '10.0.0.10'
        $global:DnsTest_nameServer = '10.0.0.10'
        $null = & $setScript -PrimaryDNS 10.0.0.10 4>$null
        $LASTEXITCODE | Should -Be 2
        Should -Invoke Start-Job -Times 0 -Exactly
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Falls back to netsh with valid index arguments / Nutzt netsh mit gültigen Index-Argumenten' {
        Mock Start-Job { [pscustomobject]@{ State = 'Failed' } }
        $null = & $setScript -PrimaryDNS 10.0.0.10 -SecondaryDNS 10.0.0.11 4>$null 3>$null
        $LASTEXITCODE | Should -Be 0
        Should -Invoke netsh -Times 1 -Exactly -ParameterFilter { $args -contains 'index=2' }
    }

    It 'Fails when both methods fail / Meldet Fehler, wenn beide Methoden scheitern' {
        Mock Start-Job { [pscustomobject]@{ State = 'Failed' } }
        $global:DnsTest_netshExitCode = 1
        $null = & $setScript -PrimaryDNS 10.0.0.10 4>$null 3>$null 2>$null
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Rejects invalid custom field DNS values / Lehnt ungültige DNS-Werte aus Custom Fields ab' {
        $global:DnsTest_customFields['DNS_PrimaryServer'] = '1'
        $null = & $setScript 4>$null 2>$null
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Start-Job -Times 0 -Exactly
    }

    It 'Does not warn for an empty DHCP checkbox / Warnt nicht bei leerer DHCP-Checkbox' {
        $global:DnsTest_customFields['DNS_PrimaryServer'] = '10.0.0.10'
        $warnings = & $setScript 4>$null 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $warnings | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 0
    }

    It 'Skips adapters already using DHCP / Überspringt Adapter mit DHCP-DNS' {
        $global:DnsTest_nameServer = ''
        $null = & $setScript -ResetDHCP 4>$null
        $LASTEXITCODE | Should -Be 2
        Should -Invoke Start-Job -Times 0 -Exactly
    }

    It 'Changes nothing with WhatIf / Ändert nichts mit WhatIf' {
        $null = & $setScript -PrimaryDNS 10.0.0.10 -WhatIf 4>$null 6>$null
        $LASTEXITCODE | Should -Be 2
        Should -Invoke Start-Job -Times 0 -Exactly
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Uses exact wildcard adapter names / Nutzt exakte Wildcard-Adapternamen' {
        $global:DnsTest_adapters = @(New-TestAdapter -Index 7 -Name 'Ethernet 2' -Ip '192.168.10.30' -Gateway '192.168.10.1')
        $null = & $setScript -PrimaryDNS 10.0.0.10 -AdapterName 'Ethernet' 4>$null 2>$null
        $LASTEXITCODE | Should -Be 1
        $null = & $setScript -PrimaryDNS 10.0.0.10 -AdapterName 'Ethernet*' 4>$null
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'DNS read script / DNS-Leseskript' {
    BeforeEach {
        $savedProgramData = $env:ProgramData
        $savedTemp = $env:TEMP
        $env:ProgramData = $TestDrive
        $env:TEMP = $TestDrive
        $global:DnsTest_adapters = @(
            New-TestAdapter -Index 5 -Name 'Ethernet' -Ip '192.168.10.20' -Gateway '192.168.10.1'
            New-TestAdapter -Index 6 -Name 'WLAN' -Ip '192.168.20.20' -Gateway '192.168.20.1'
        )
        $global:DnsTest_dnsByIndex = @{ 5 = @('10.0.0.10'); 6 = @('10.0.0.10') }
        Mock Get-NetAdapter { $global:DnsTest_adapters }
        Mock Get-NetIPConfiguration {
            $a = $global:DnsTest_adapters | Where-Object ifIndex -eq $InterfaceIndex
            [pscustomobject]@{
                IPv4Address = [pscustomobject]@{ IPAddress = $a.TestIp }
                IPv6Address = $null
                IPv4DefaultGateway = [pscustomobject]@{ NextHop = $a.TestGateway }
            }
        }
        Mock Get-DnsClientServerAddress {
            [pscustomobject]@{ AddressFamily = 2; ServerAddresses = $global:DnsTest_dnsByIndex[[int]$InterfaceIndex] }
        }
        Mock Get-DnsClient { [pscustomobject]@{ ConnectionSpecificSuffix = 'example.local' } }
        Mock Get-CimInstance {
            switch ($ClassName) {
                'Win32_ComputerSystem' { [pscustomobject]@{ Name = 'TEST-PC'; Domain = 'example.local' } }
                'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Windows Test'; Version = '10.0' } }
            }
        }
        Mock Ninja-Property-Set {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
    }
    AfterEach {
        $env:ProgramData = $savedProgramData
        $env:TEMP = $savedTemp
    }

    It 'Writes summary and no mismatch / Schreibt Zusammenfassung ohne Abweichung' {
        $output = (& $readScript -NoCSV 4>$null) -join "`n"
        $LASTEXITCODE | Should -Be 0
        $output | Should -Not -Match '\\n'
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'DNS_Summary' -and $Value -eq '10.0.0.10' }
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'DNS_Mismatch' -and $Value -eq $false }
    }

    It 'Reports and stores DNS mismatches / Meldet und speichert DNS-Abweichungen' {
        $global:DnsTest_dnsByIndex[6] = @('8.8.8.8')
        $output = (& $readScript -NoCSV 4>$null) -join "`n"
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'Unterschiedliche DNS-Server'
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'DNS_Mismatch' -and $Value -eq $true }
    }

    It 'Accepts text retention values and rotates old files / Akzeptiert Text-Aufbewahrung und rotiert Dateien' {
        $logDir = Join-Path $TestDrive 'NinjaRMMAgent/Logs'
        $reportDir = Join-Path $logDir 'Reports'
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        $old = New-Item -ItemType File -Path (Join-Path $reportDir 'DNS_Report_old.csv') -Force
        $old.LastWriteTime = (Get-Date).AddDays(-20)
        $warnings = & $readScript -LogRetentionDays '14' -NoCustomField 4>$null 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $LASTEXITCODE | Should -Be 0
        $warnings | Should -BeNullOrEmpty
        Test-Path $old.FullName | Should -BeFalse
        @(Get-ChildItem $reportDir -Filter 'DNS_Report_TEST-PC_*.csv').Count | Should -Be 1
    }
}
