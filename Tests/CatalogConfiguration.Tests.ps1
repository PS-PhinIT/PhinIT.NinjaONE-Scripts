BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root '09 - Configuration'
    $powerPlanScript = Join-Path $folder 'setPowerPlan.ps1'
    $timeZoneScript = Join-Path $folder 'setTimeZone.ps1'
    $fastStartupScript = Join-Path $folder 'setFastStartup.ps1'
    $rdpScript = Join-Path $folder 'setRemoteDesktop.ps1'
    $serviceScript = Join-Path $folder 'setServiceStartupType.ps1'
    $registryScript = Join-Path $folder 'setRegistryValue.ps1'
    $usbScript = Join-Path $folder 'setUsbStoragePolicy.ps1'
    $consumerScript = Join-Path $folder 'setConsumerFeatures.ps1'
    $edgeScript = Join-Path $folder 'setEdgePolicies.ps1'
    $officeScript = Join-Path $folder 'setOfficeUpdateChannel.ps1'
    $hiberbootPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'

    # DE: Stubs erlauben Mocks ohne Windows/NinjaOne. EN: Stubs allow mocks without Windows/NinjaOne.
    function powercfg { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function w32tm { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Set-TimeZone { param($Id) }
    function Get-NetFirewallRule { param($Group) }
    function Enable-NetFirewallRule { param($Group) }
    function Disable-NetFirewallRule { param($Group) }
    function Get-CimInstance { param($ClassName, $Namespace, $Filter) }
    function Get-Service { param($Name) }
    function Set-Service { param($Name, $StartupType) }
    function Start-Service { param($Name) }
    function Stop-Service { param($Name) }
    function Restart-Service { param($Name) }
    function Start-ScheduledTask { param($TaskPath, $TaskName) }
    function Ninja-Property-Set { param($Name, $Value) }

    # DE: Registry als Hashtable Pfad -> (Name -> Wert/Typ). EN: Registry as hashtable path -> (name -> value/kind).
    function Add-FakeRegistryValue {
        param([hashtable]$Store, [string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord')
        if (-not $Store.ContainsKey($Path)) { $Store[$Path] = @{} }
        if ($Name) { $Store[$Path][$Name] = @{ Value = $Value; Kind = $Kind } }
    }
    function ConvertTo-FakeItemProperty {
        param([hashtable]$Values)
        $properties = [ordered]@{ PSPath = 'fake' }
        foreach ($name in $Values.Keys) { $properties[$name] = $Values[$name].Value }
        [pscustomobject]$properties
    }
    function New-FakeRegistryKey {
        param([hashtable]$Values)
        $key = [pscustomobject]@{ Values = $Values }
        $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { @($this.Values.Keys) }
        $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
            param($Name, $Default, $Options)
            if ($this.Values.ContainsKey($Name)) { , $this.Values[$Name].Value } else { $Default }
        }
        $key | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value { param($Name) $this.Values[$Name].Kind }
        $key
    }
}

Describe 'Configuration catalogue scripts / Konfigurations-Katalogskripte' {
    BeforeEach {
        $savedEnvironment = @{}
        foreach ($name in @('resultCustomField', 'configPowerPlan', 'configPowerMonitorTimeoutAcMinutes', 'configPowerMonitorTimeoutDcMinutes',
                'configPowerStandbyTimeoutAcMinutes', 'configPowerStandbyTimeoutDcMinutes', 'configPowerAllow', 'configTimeZoneId',
                'configTimeZoneAllow', 'configTimeZoneResyncTime', 'configFastStartupEnabled', 'configFastStartupAllow', 'configRdpEnabled',
                'configRdpRequireNla', 'configRdpConfigureFirewall', 'configRdpAllow', 'configServiceName', 'configServiceStartupType',
                'configServiceAction', 'configServiceAllow', 'configRegistryPath', 'configRegistryName', 'configRegistryType',
                'configRegistryValue', 'configRegistryAction', 'configRegistryAllow', 'configUsbStorageBlocked', 'configUsbStorageAllow',
                'configUsbStorageDenyWriteOnly', 'configConsumerFeaturesDisabled', 'configConsumerFeaturesAllow',
                'configEdgeHideFirstRunExperience', 'configEdgeStartupBoostEnabled', 'configEdgeBackgroundModeEnabled',
                'configEdgeShowRecommendationsEnabled', 'configEdgeHomepageLocation', 'configEdgePasswordManagerEnabled', 'configEdgeAllow',
                'configOfficeChannel', 'configOfficeTriggerUpdate', 'configOfficeAllow')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $registry = @{}
        Mock Test-Path { $registry.ContainsKey([string]$LiteralPath) }
        Mock Get-ItemProperty { ConvertTo-FakeItemProperty -Values $registry[[string]$LiteralPath] }
        Mock Get-Item { New-FakeRegistryKey -Values $registry[[string]$LiteralPath] }
        Mock New-Item { $registry[[string]$Path] = @{}; [pscustomobject]@{ PSPath = [string]$Path } }
        Mock New-ItemProperty { $registry[[string]$LiteralPath][[string]$Name] = @{ Value = $Value; Kind = [string]$PropertyType } }
        Mock Remove-ItemProperty { $registry[[string]$LiteralPath].Remove([string]$Name) }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    }

    Context 'setFastStartup' {
        It 'Audit reports default as enabled and changes nothing / Prüfung meldet Standard als aktiv ohne Änderung' {
            $report = & $fastStartupScript -Enabled false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Current | Should -Be 'Default(Enabled)'
            $report.Compliant | Should -BeFalse
            $report.Allowed | Should -BeFalse
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            $null = & $fastStartupScript -Enabled true
            $LASTEXITCODE | Should -Be 0
        }
        It 'Applies the change with opt-in / Ändert mit Opt-in' {
            Add-FakeRegistryValue -Store $registry -Path $hiberbootPath -Name 'HiberbootEnabled' -Value 1
            Add-FakeRegistryValue -Store $registry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -Value 0
            $env:configFastStartupEnabled = 'false'
            $env:configFastStartupAllow = 'true'
            $env:resultCustomField = 'fastStartupReport'
            $report = & $fastStartupScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $report.Compliant | Should -BeTrue
            $report.Current | Should -Be 'Disabled'
            $report.HibernateEnabled | Should -Be 0
            $registry[$hiberbootPath]['HiberbootEnabled'].Kind | Should -Be 'DWord'
            Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'HiberbootEnabled' -and $PropertyType -eq 'DWord' -and $Value -eq 0 }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'fastStartupReport' }
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $fastStartupScript -Enabled false -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            $report.Changed | Should -BeFalse
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
        }
        It 'Fails when verification mismatches / Fehler bei abweichender Verifikation' {
            Mock New-ItemProperty {}
            $null = & $fastStartupScript -Enabled false -Allow true
            $LASTEXITCODE | Should -Be 1
        }
        It 'Treats wrong value types as drift / Falscher Werttyp ist Abweichung' {
            Add-FakeRegistryValue -Store $registry -Path $hiberbootPath -Name 'HiberbootEnabled' -Value '1' -Kind 'String'
            $report = & $fastStartupScript -Enabled true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Current | Should -Be 'Invalid(1)'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{}, @{ Enabled = 'yes' }, @{ Enabled = 'true'; Allow = 'maybe' }, @{ Enabled = 'true'; CustomField = '1bad' })) {
                $null = & $fastStartupScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'setPowerPlan' {
        BeforeEach {
            $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
            $highPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $ultimateCopy = '878f208b-dd80-47bd-ae62-235365a04fed'
            $power = @{ Active = $balanced; Schemes = @($balanced, $highPerformance, 'a1841308-3541-4fab-bc81-f71556f20b4a'); VIDEOIDLE = @(600, 300); STANDBYIDLE = @(1800, 900) }
            # DE: Deutsche Ausgabe belegt die Sprachunabhängigkeit. EN: German output proves locale independence.
            Mock powercfg {
                $a = @($Arguments | ForEach-Object { [string]$_ })
                $global:LASTEXITCODE = 0
                switch ($a[0]) {
                    '/getactivescheme' { 'GUID des Energieschemas: {0}  (Ausbalanciert)' -f $power.Active }
                    '/list' {
                        'Vorhandene Energieschemas (* Aktiv)'
                        foreach ($guid in $power.Schemes) { 'GUID des Energieschemas: {0}  (Plan)' -f $guid }
                    }
                    '/setactive' { if ($power.Schemes -notcontains $a[1]) { $global:LASTEXITCODE = 1 } else { $power.Active = $a[1] } }
                    '/duplicatescheme' { $power.Schemes += $a[2]; 'GUID des Energieschemas: {0}  (Ultimative Leistung)' -f $a[2] }
                    '/change' {
                        $map = @{ 'monitor-timeout-ac' = @('VIDEOIDLE', 0); 'monitor-timeout-dc' = @('VIDEOIDLE', 1); 'standby-timeout-ac' = @('STANDBYIDLE', 0); 'standby-timeout-dc' = @('STANDBYIDLE', 1) }
                        $target = $map[$a[1]]
                        $power[$target[0]][$target[1]] = [int]$a[2] * 60
                    }
                    '/query' {
                        $values = $power[$a[3]]
                        'GUID des Energieschemas: {0}  (Ausbalanciert)' -f $power.Active
                        '  GUID der Energieeinstellung: 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e  (Bildschirm ausschalten nach)'
                        '    Minimale mögliche Einstellung: 0x00000000'
                        '    Maximale mögliche Einstellung: 0xffffffff'
                        '    Mögliche Einstellungsschritte: 0x00000001'
                        '    Einheiten: Sekunden'
                        '  Index der aktuellen Wechselstromeinstellung: 0x{0:x8}' -f $values[0]
                        '  Index der aktuellen Gleichstromeinstellung: 0x{0:x8}' -f $values[1]
                    }
                }
            }
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $powerPlanScript -PowerPlan HighPerformance -MonitorTimeoutAcMinutes 15 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Compliant | Should -BeFalse
            $report.Current.PowerPlan | Should -Be 'Balanced'
            $report.Current.MonitorTimeoutAcMinutes | Should -Be 10
            @($report.Differences).Count | Should -Be 2
            Should -Invoke powercfg -Times 0 -Exactly -ParameterFilter { [string]$Arguments[0] -in @('/setactive', '/change', '/duplicatescheme') }
        }
        It 'Applies plan and timeouts with opt-in / Setzt Plan und Zeitlimits mit Opt-in' {
            $env:configPowerPlan = 'highperformance'
            $env:configPowerMonitorTimeoutAcMinutes = '15'
            $env:configPowerStandbyTimeoutDcMinutes = '0'
            $env:configPowerAllow = 'true'
            $env:resultCustomField = 'powerReport'
            $report = & $powerPlanScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $report.Compliant | Should -BeTrue
            $power.Active | Should -Be $highPerformance
            $power.VIDEOIDLE[0] | Should -Be 900
            $power.STANDBYIDLE[1] | Should -Be 0
            $power.VIDEOIDLE[1] | Should -Be 300
            Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/setactive' }
            Should -Invoke powercfg -Times 2 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/change' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'powerReport' }
        }
        It 'Reports compliance without changes / Meldet Konformität ohne Änderung' {
            $null = & $powerPlanScript -PowerPlan $balanced -StandbyTimeoutAcMinutes 30 -Allow true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke powercfg -Times 0 -Exactly -ParameterFilter { [string]$Arguments[0] -in @('/setactive', '/change') }
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $powerPlanScript -PowerPlan HighPerformance -MonitorTimeoutDcMinutes 5 -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            $report.Changed | Should -BeFalse
            $power.Active | Should -Be $balanced
            Should -Invoke powercfg -Times 0 -Exactly -ParameterFilter { [string]$Arguments[0] -in @('/setactive', '/change', '/duplicatescheme') }
        }
        It 'Duplicates Ultimate Performance only with opt-in and only once / Dupliziert Ultimative Leistung nur mit Opt-in und einmalig' {
            $null = & $powerPlanScript -PowerPlan UltimatePerformance
            $LASTEXITCODE | Should -Be 2
            Should -Invoke powercfg -Times 0 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/duplicatescheme' }
            $report = & $powerPlanScript -PowerPlan UltimatePerformance -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Current.PowerPlan | Should -Be 'UltimatePerformance'
            $power.Active | Should -Be $ultimateCopy
            Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/duplicatescheme' -and [string]$Arguments[1] -eq 'e9a42b02-d5df-448d-aa00-03f14749eb61' -and [string]$Arguments[2] -eq $ultimateCopy }
            $null = & $powerPlanScript -PowerPlan UltimatePerformance -Allow true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/duplicatescheme' }
        }
        It 'Fails for missing plans and powercfg errors / Fehler bei fehlendem Plan und powercfg-Fehler' {
            $null = & $powerPlanScript -PowerPlan '{11111111-2222-3333-4444-555555555555}' -Allow true
            $LASTEXITCODE | Should -Be 1
            Should -Invoke powercfg -Times 0 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/setactive' }
            Mock powercfg { $global:LASTEXITCODE = 5 }
            $null = & $powerPlanScript -PowerPlan Balanced
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{}, @{ PowerPlan = 'Turbo' }, @{ MonitorTimeoutAcMinutes = '1441' }, @{ StandbyTimeoutAcMinutes = '-1' },
                    @{ MonitorTimeoutDcMinutes = 'abc' }, @{ PowerPlan = 'Balanced'; Allow = 'ja' }, @{ PowerPlan = 'Balanced'; CustomField = 'bad-name' })) {
                $null = & $powerPlanScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke powercfg -Times 0 -Exactly
        }
    }

    Context 'setTimeZone' {
        BeforeEach {
            $tz = @{ Current = 'UTC'; Zones = @('UTC', 'W. Europe Standard Time', 'GMT Standard Time') }
            Mock Get-TimeZone { if ($ListAvailable) { foreach ($zone in $tz.Zones) { [pscustomobject]@{ Id = $zone } } } else { [pscustomobject]@{ Id = $tz.Current } } }
            Mock Set-TimeZone { $tz.Current = $Id }
            Mock w32tm { $global:LASTEXITCODE = 0 }
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $timeZoneScript -TimeZoneId 'w. europe standard time' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Current | Should -Be 'UTC'
            $report.Desired | Should -Be 'W. Europe Standard Time'
            Should -Invoke Set-TimeZone -Times 0 -Exactly
        }
        It 'Sets the zone and resyncs with opt-in / Setzt Zone und synchronisiert mit Opt-in' {
            $env:configTimeZoneId = 'W. Europe Standard Time'
            $env:configTimeZoneAllow = 'true'
            $env:configTimeZoneResyncTime = 'true'
            $env:resultCustomField = 'timeZoneReport'
            $report = & $timeZoneScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $tz.Current | Should -Be 'W. Europe Standard Time'
            Should -Invoke Set-TimeZone -Times 1 -Exactly -ParameterFilter { $Id -eq 'W. Europe Standard Time' }
            Should -Invoke w32tm -Times 1 -Exactly -ParameterFilter { [string]$Arguments[0] -eq '/resync' -and [string]$Arguments[1] -eq '/nowait' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'timeZoneReport' }
        }
        It 'Warns when resync fails / Warnt bei fehlgeschlagener Synchronisierung' {
            Mock w32tm { $global:LASTEXITCODE = 1 }
            $report = & $timeZoneScript -TimeZoneId 'GMT Standard Time' -Allow true -ResyncTime true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Compliant | Should -BeTrue
            @($report.Warnings).Count | Should -Be 1
        }
        It 'Does not resync without change / Keine Synchronisierung ohne Änderung' {
            $null = & $timeZoneScript -TimeZoneId UTC -Allow true -ResyncTime true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke w32tm -Times 0 -Exactly
            Should -Invoke Set-TimeZone -Times 0 -Exactly
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $timeZoneScript -TimeZoneId 'GMT Standard Time' -Allow true -ResyncTime true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke Set-TimeZone -Times 0 -Exactly
            Should -Invoke w32tm -Times 0 -Exactly
        }
        It 'Fails when verification mismatches / Fehler bei abweichender Verifikation' {
            Mock Set-TimeZone {}
            $null = & $timeZoneScript -TimeZoneId 'GMT Standard Time' -Allow true
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{}, @{ TimeZoneId = 'Mars Standard Time' }, @{ TimeZoneId = "UTC`n" + 'x' }, @{ TimeZoneId = 'W*' },
                    @{ TimeZoneId = 'UTC'; ResyncTime = 'maybe' }, @{ TimeZoneId = 'UTC'; CustomField = '_x' })) {
                $null = & $timeZoneScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Set-TimeZone -Times 0 -Exactly
        }
    }

    Context 'setRemoteDesktop' {
        BeforeEach {
            $tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
            $rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
            $rdpPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
            Add-FakeRegistryValue -Store $registry -Path $tsPath -Name 'fDenyTSConnections' -Value 1
            Add-FakeRegistryValue -Store $registry -Path $rdpTcpPath -Name 'UserAuthentication' -Value 0
            $fw = @{ Rules = @([pscustomobject]@{ Name = 'RemoteDesktop-UserMode-In-TCP'; Enabled = 'False' }, [pscustomobject]@{ Name = 'RemoteDesktop-UserMode-In-UDP'; Enabled = 'False' }) }
            Mock Get-NetFirewallRule { $fw.Rules }
            Mock Enable-NetFirewallRule { foreach ($rule in $fw.Rules) { $rule.Enabled = 'True' } }
            Mock Disable-NetFirewallRule { foreach ($rule in $fw.Rules) { $rule.Enabled = 'False' } }
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $rdpScript -Enabled true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Current.RdpEnabled | Should -BeFalse
            @($report.Differences).Count | Should -Be 3
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke Enable-NetFirewallRule -Times 0 -Exactly
        }
        It 'Enables RDP with NLA and firewall with opt-in / Aktiviert RDP mit NLA und Firewall per Opt-in' {
            $env:configRdpEnabled = 'true'
            $env:configRdpAllow = 'true'
            $env:resultCustomField = 'rdpReport'
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $report.Compliant | Should -BeTrue
            $registry[$tsPath]['fDenyTSConnections'].Value | Should -Be 0
            $registry[$rdpTcpPath]['UserAuthentication'].Value | Should -Be 1
            Should -Invoke Enable-NetFirewallRule -Times 1 -Exactly -ParameterFilter { $Group -eq '@FirewallAPI.dll,-28752' }
            Should -Invoke Get-NetFirewallRule -ParameterFilter { $Group -eq '@FirewallAPI.dll,-28752' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'rdpReport' }
        }
        It 'Honours NLA false and unmanaged firewall / Beachtet NLA false und unverwaltete Firewall' {
            $report = & $rdpScript -Enabled true -RequireNla false -ConfigureFirewall false -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Desired.UserAuthentication | Should -Be 0
            $registry[$tsPath]['fDenyTSConnections'].Value | Should -Be 0
            Should -Invoke Get-NetFirewallRule -Times 0 -Exactly
            Should -Invoke New-ItemProperty -Times 1 -Exactly
        }
        It 'Disables RDP and the firewall rules / Deaktiviert RDP und Firewallregeln' {
            $registry[$tsPath]['fDenyTSConnections'].Value = 0
            foreach ($rule in $fw.Rules) { $rule.Enabled = 'True' }
            $null = & $rdpScript -Enabled false -Allow true
            $LASTEXITCODE | Should -Be 0
            $registry[$tsPath]['fDenyTSConnections'].Value | Should -Be 1
            $registry[$rdpTcpPath]['UserAuthentication'].Value | Should -Be 0
            Should -Invoke Disable-NetFirewallRule -Times 1 -Exactly
        }
        It 'Reports policy override and changes nothing / Meldet Richtlinienvorrang ohne Änderung' {
            Add-FakeRegistryValue -Store $registry -Path $rdpPolicyPath -Name 'fDenyTSConnections' -Value 1
            $report = & $rdpScript -Enabled true -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.PolicyOverride).Count | Should -Be 1
            $report.Changed | Should -BeFalse
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke Enable-NetFirewallRule -Times 0 -Exactly
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $rdpScript -Enabled true -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke Enable-NetFirewallRule -Times 0 -Exactly
        }
        It 'Fails without firewall rules / Fehler ohne Firewallregeln' {
            Mock Get-NetFirewallRule {}
            $null = & $rdpScript -Enabled true -Allow true
            $LASTEXITCODE | Should -Be 1
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{}, @{ Enabled = 'on' }, @{ Enabled = 'true'; RequireNla = 'x' }, @{ Enabled = 'true'; ConfigureFirewall = '1' },
                    @{ Enabled = 'true'; Allow = 'yes' })) {
                $null = & $rdpScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'setServiceStartupType' {
        BeforeEach {
            $svc = @{ Name = 'Spooler'; DisplayName = 'Print Spooler'; StartMode = 'Auto'; State = 'Running' }
            $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler'
            Add-FakeRegistryValue -Store $registry -Path $servicePath
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_Service' -and $Filter -eq ("Name='{0}'" -f $svc.Name)) {
                    [pscustomobject]@{ Name = $svc.Name; DisplayName = $svc.DisplayName; StartMode = $svc.StartMode; State = $svc.State }
                }
            }
            Mock Set-Service { $svc.StartMode = @{ Automatic = 'Auto'; Manual = 'Manual'; Disabled = 'Disabled' }[[string]$StartupType] }
            Mock Start-Service { $svc.State = 'Running' }
            Mock Stop-Service { $svc.State = 'Stopped' }
            Mock Restart-Service { $svc.State = 'Running' }
            Mock Get-Service {
                $service = [pscustomobject]@{ Name = $Name }
                $service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($Status, $Timeout) }
                $service
            }
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $serviceScript -ServiceName spooler -StartupType Disabled -Action Stop | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.ServiceName | Should -Be 'Spooler'
            $report.Current.StartupType | Should -Be 'Automatic'
            @($report.Differences).Count | Should -Be 2
            Should -Invoke Set-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }
        It 'Disables and stops with opt-in / Deaktiviert und stoppt mit Opt-in' {
            $env:configServiceName = 'Spooler'
            $env:configServiceStartupType = 'Disabled'
            $env:configServiceAction = 'Stop'
            $env:configServiceAllow = 'true'
            $env:resultCustomField = 'serviceReport'
            $report = & $serviceScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Current.StartupType | Should -Be 'Disabled'
            $report.Current.State | Should -Be 'Stopped'
            Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $StartupType -eq 'Disabled' }
            Should -Invoke Stop-Service -Times 1 -Exactly
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'serviceReport' }
        }
        It 'Sets delayed automatic start and starts / Setzt verzögerten Autostart und startet' {
            $svc.StartMode = 'Manual'
            $svc.State = 'Stopped'
            $report = & $serviceScript -ServiceName Spooler -StartupType AutomaticDelayedStart -Action Start -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Current.StartupType | Should -Be 'AutomaticDelayedStart'
            Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $StartupType -eq 'Automatic' }
            Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'DelayedAutostart' -and $Value -eq 1 -and $PropertyType -eq 'DWord' }
            Should -Invoke Start-Service -Times 1 -Exactly
            $null = & $serviceScript -ServiceName Spooler -StartupType AutomaticDelayedStart -Action Start
            $LASTEXITCODE | Should -Be 0
        }
        It 'Treats restart as pending and restarts with opt-in / Neustart ausstehend, mit Opt-in ausgeführt' {
            $null = & $serviceScript -ServiceName Spooler -Action Restart
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Restart-Service -Times 0 -Exactly
            $null = & $serviceScript -ServiceName Spooler -Action Restart -Allow true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Restart-Service -Times 1 -Exactly
        }
        It 'Never disables or stops protected services / Geschützte Dienste werden nie deaktiviert oder gestoppt' {
            foreach ($arguments in @(@{ ServiceName = 'rpcss'; StartupType = 'Disabled' }, @{ ServiceName = 'NinjaRMMAgentPatcher'; Action = 'Stop' },
                    @{ ServiceName = 'WinDefend'; Action = 'Restart' }, @{ ServiceName = 'NinjaRMMAgent'; StartupType = 'Disabled'; Action = 'Stop' })) {
                $null = & $serviceScript @arguments -Allow true
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Get-CimInstance -Times 0 -Exactly
            Should -Invoke Set-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
            Should -Invoke Restart-Service -Times 0 -Exactly
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $serviceScript -ServiceName Spooler -StartupType Manual -Action Stop -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke Set-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }
        It 'Fails for missing services and failed verification / Fehler bei fehlendem Dienst und Verifikation' {
            $null = & $serviceScript -ServiceName MissingSvc -StartupType Manual
            $LASTEXITCODE | Should -Be 1
            Mock Set-Service {}
            $null = & $serviceScript -ServiceName Spooler -StartupType Manual -Allow true
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{}, @{ ServiceName = "Spool'er"; StartupType = 'Manual' }, @{ ServiceName = 'Spooler' }, @{ ServiceName = 'Spooler'; StartupType = 'Boot' },
                    @{ ServiceName = 'Spooler'; Action = 'Pause' }, @{ ServiceName = 'Spooler'; StartupType = 'Disabled'; Action = 'Start' },
                    @{ ServiceName = ('x' * 81); Action = 'Start' })) {
                $null = & $serviceScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Get-CimInstance -Times 0 -Exactly
        }
    }

    Context 'setRegistryValue' {
        BeforeEach {
            $appPath = 'HKLM:\SOFTWARE\Contoso\App'
        }
        It 'Audit reports a missing value and changes nothing / Prüfung meldet fehlenden Wert ohne Änderung' {
            $report = & $registryScript -Path $appPath -Name Mode -Type dword -Value 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Previous.Exists | Should -BeFalse
            $report.Desired.Type | Should -Be 'DWord'
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
        }
        It 'Writes unsigned DWORD and QWORD values correctly / Schreibt vorzeichenlose DWORD/QWORD korrekt' {
            $env:configRegistryPath = $appPath
            $env:configRegistryName = 'Mask'
            $env:configRegistryType = 'DWord'
            $env:configRegistryValue = '4294967295'
            $env:configRegistryAllow = 'true'
            $env:resultCustomField = 'registryReport'
            $report = & $registryScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $report.Current.Value | Should -Be '4294967295'
            $registry[$appPath]['Mask'].Value | Should -Be -1
            $registry[$appPath]['Mask'].Value | Should -BeOfType [int]
            Should -Invoke New-Item -Times 1 -Exactly
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'registryReport' }
            $env:resultCustomField = $null
            $report = & $registryScript -Name Big -Type QWord -Value '0xFFFFFFFFFFFFFFFF' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $registry[$appPath]['Big'].Value | Should -Be ([long]-1)
            $registry[$appPath]['Big'].Kind | Should -Be 'QWord'
            $report.Current.Value | Should -Be '18446744073709551615'
        }
        It 'Writes and compares MultiString and kind / Schreibt MultiString und vergleicht Typ' {
            $null = & $registryScript -Path $appPath -Name Servers -Type MultiString -Value 'srv1|srv2' -Allow true
            $LASTEXITCODE | Should -Be 0
            @($registry[$appPath]['Servers'].Value) | Should -Be @('srv1', 'srv2')
            $null = & $registryScript -Path $appPath -Name Servers -Type MultiString -Value 'srv1|srv2'
            $LASTEXITCODE | Should -Be 0
            $null = & $registryScript -Path $appPath -Name Servers -Type MultiString -Value 'srv1|SRV2'
            $LASTEXITCODE | Should -Be 2
            Add-FakeRegistryValue -Store $registry -Path $appPath -Name 'Root' -Value '%SystemRoot%\x' -Kind 'String'
            $report = & $registryScript -Path $appPath -Name Root -Type ExpandString -Value '%SystemRoot%\x' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Previous.Type | Should -Be 'String'
        }
        It 'Removes values only when present / Entfernt Werte nur wenn vorhanden' {
            $null = & $registryScript -Path $appPath -Name Legacy -Action Remove -Allow true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            Add-FakeRegistryValue -Store $registry -Path $appPath -Name 'Legacy' -Value 'x' -Kind 'String'
            $null = & $registryScript -Path $appPath -Name Legacy -Action Remove
            $LASTEXITCODE | Should -Be 2
            $null = & $registryScript -Path $appPath -Name Legacy -Action remove -Allow true
            $LASTEXITCODE | Should -Be 0
            $registry[$appPath].ContainsKey('Legacy') | Should -BeFalse
            Should -Invoke Remove-ItemProperty -Times 1 -Exactly
        }
        It 'Redacts sensitive values and truncates long values / Schwärzt sensible und kürzt lange Werte' {
            Add-FakeRegistryValue -Store $registry -Path $appPath -Name 'ApiToken' -Value 'old-secret-value' -Kind 'String'
            $output = & $registryScript -Path $appPath -Name ApiToken -Type String -Value 'new-secret-value'
            $LASTEXITCODE | Should -Be 2
            ($output -join "`n") | Should -Not -Match 'secret-value'
            ($output | ConvertFrom-Json).Previous.Value | Should -Be '<redacted>'
            $report = & $registryScript -Path $appPath -Name Long -Type String -Value ('a' * 300) | ConvertFrom-Json
            $report.Desired.Value.Length | Should -Be 203
        }
        It 'Rejects protected and invalid paths / Lehnt geschützte und ungültige Pfade ab' {
            foreach ($path in @('HKLM:\SAM\SAM', 'HKLM:\SECURITY\Policy', 'HKCU:\Software\Contoso', 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa',
                    'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0', 'HKLM:\SYSTEM\CurrentControlSet\Services\NinjaRMMAgent',
                    'HKLM:\SYSTEM\ControlSet001\Services\x', 'HKLM:\SOFTWARE\*', 'HKLM:\SOFTWARE\..\SAM', 'HKLM:\SOFTWARE\', 'HKLM:\SOFTWARE\a\\b',
                    ('HKLM:\SOFTWARE\' + ('x' * 250)))) {
                $null = & $registryScript -Path $path -Name Mode -Type DWord -Value 1 -Allow true
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke Test-Path -Times 0 -Exactly
        }
        It 'Rejects invalid names, types and values / Lehnt ungültige Namen, Typen und Werte ab' {
            foreach ($arguments in @(@{ Name = '(Default)'; Type = 'String'; Value = 'x' }, @{ Name = 'a*'; Type = 'String'; Value = 'x' }, @{ Name = 'Mode'; Value = '1' },
                    @{ Name = 'Mode'; Type = 'Binary'; Value = '1' }, @{ Name = 'Mode'; Type = 'DWord'; Value = '4294967296' }, @{ Name = 'Mode'; Type = 'DWord'; Value = '-1' },
                    @{ Name = 'Mode'; Type = 'DWord'; Value = 'abc' }, @{ Name = 'Mode'; Type = 'QWord'; Value = '18446744073709551616' },
                    @{ Name = 'Mode'; Type = 'String'; Value = ('x' * 4001) }, @{ Name = 'Mode'; Type = 'String'; Value = "a`tb" },
                    @{ Name = 'Mode'; Type = 'String'; Value = 'x'; Action = 'Delete' }, @{ Name = 'Mode'; Type = 'String'; Value = 'x'; CustomField = 'a b' })) {
                $null = & $registryScript -Path $appPath @arguments -Allow true
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'WhatIf and verification failure / WhatIf und Verifikationsfehler' {
            $report = & $registryScript -Path $appPath -Name Mode -Type DWord -Value 0x10 -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            $report.Desired.Value | Should -Be '16'
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Mock New-ItemProperty {}
            $null = & $registryScript -Path $appPath -Name Mode -Type DWord -Value 1 -Allow true
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'setUsbStoragePolicy' {
        BeforeEach {
            $usbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
            $denyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
            Add-FakeRegistryValue -Store $registry -Path $usbPath -Name 'Start' -Value 3
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $usbScript -Blocked true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Current.Blocked | Should -BeFalse
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            $null = & $usbScript -Blocked false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Blocks USB storage with opt-in / Sperrt USB-Speicher mit Opt-in' {
            $env:configUsbStorageBlocked = 'true'
            $env:configUsbStorageAllow = 'true'
            $env:resultCustomField = 'usbReport'
            $report = & $usbScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Changed | Should -BeTrue
            $registry[$usbPath]['Start'].Value | Should -Be 4
            Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'Start' -and $PropertyType -eq 'DWord' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'usbReport' }
        }
        It 'Manages Deny_Write / Verwaltet Deny_Write' {
            $null = & $usbScript -Blocked false -DenyWriteOnly true -Allow true
            $LASTEXITCODE | Should -Be 0
            $registry[$denyPath]['Deny_Write'].Value | Should -Be 1
            Should -Invoke New-Item -Times 1 -Exactly
            $null = & $usbScript -Blocked false -DenyWriteOnly false
            $LASTEXITCODE | Should -Be 2
            $null = & $usbScript -Blocked false -DenyWriteOnly false -Allow true
            $LASTEXITCODE | Should -Be 0
            $registry[$denyPath].ContainsKey('Deny_Write') | Should -BeFalse
            Should -Invoke Remove-ItemProperty -Times 1 -Exactly
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $usbScript -Blocked true -DenyWriteOnly true -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
        }
        It 'Fails without USBSTOR and on invalid input / Fehler ohne USBSTOR und bei ungültigen Eingaben' {
            foreach ($arguments in @(@{}, @{ Blocked = 'blocked' }, @{ Blocked = 'true'; DenyWriteOnly = 'ro' }, @{ Blocked = 'true'; Allow = '2' })) {
                $null = & $usbScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            $registry.Remove($usbPath)
            $null = & $usbScript -Blocked true -Allow true
            $LASTEXITCODE | Should -Be 1
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'setConsumerFeatures' {
        BeforeEach {
            $cloudPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            Add-FakeRegistryValue -Store $registry -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -Value 'Professional' -Kind 'String'
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $consumerScript -Disabled true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Differences).Count | Should -Be 4
            @($report.Notes).Count | Should -Be 1
            Should -Invoke New-ItemProperty -Times 0 -Exactly
            $null = & $consumerScript -Disabled false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Sets all four values with opt-in / Setzt alle vier Werte mit Opt-in' {
            Add-FakeRegistryValue -Store $registry -Path $cloudPath -Name 'DisableSoftLanding' -Value 1
            $env:configConsumerFeaturesDisabled = 'true'
            $env:configConsumerFeaturesAllow = 'true'
            $env:resultCustomField = 'consumerReport'
            $report = & $consumerScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Compliant | Should -BeTrue
            Should -Invoke New-ItemProperty -Times 3 -Exactly -ParameterFilter { $PropertyType -eq 'DWord' -and $Value -eq 1 }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'consumerReport' }
        }
        It 'Removes the values when false / Entfernt die Werte bei false' {
            foreach ($valueName in @('DisableWindowsConsumerFeatures', 'DisableConsumerAccountStateContent', 'DisableSoftLanding', 'DisableCloudOptimizedContent')) {
                Add-FakeRegistryValue -Store $registry -Path $cloudPath -Name $valueName -Value 1
            }
            $null = & $consumerScript -Disabled false
            $LASTEXITCODE | Should -Be 2
            $null = & $consumerScript -Disabled false -Allow true
            $LASTEXITCODE | Should -Be 0
            $registry[$cloudPath].Count | Should -Be 0
            Should -Invoke Remove-ItemProperty -Times 4 -Exactly
        }
        It 'WhatIf changes nothing and invalid input fails / WhatIf ändert nichts, ungültige Eingaben scheitern' {
            $report = & $consumerScript -Disabled true -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            foreach ($arguments in @(@{}, @{ Disabled = 'all' }, @{ Disabled = 'true'; Allow = 'y' }, @{ Disabled = 'true'; CustomField = 'x-y' })) {
                $null = & $consumerScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'setEdgePolicies' {
        BeforeEach {
            $edgePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        }
        It 'Requires at least one setting / Erfordert mindestens eine Einstellung' {
            $null = & $edgeScript -Allow true
            $LASTEXITCODE | Should -Be 1
        }
        It 'Audit reports drift and changes nothing / Prüfung meldet Abweichung ohne Änderung' {
            $report = & $edgeScript -HideFirstRunExperience true -StartupBoostEnabled false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Differences).Count | Should -Be 2
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'Sets and removes policies with opt-in / Setzt und entfernt Richtlinien mit Opt-in' {
            Add-FakeRegistryValue -Store $registry -Path $edgePath -Name 'BackgroundModeEnabled' -Value 1
            $env:configEdgeHideFirstRunExperience = 'true'
            $env:configEdgePasswordManagerEnabled = 'false'
            $env:configEdgeHomepageLocation = 'https://intranet.contoso.com/start'
            $env:configEdgeBackgroundModeEnabled = 'remove'
            $env:configEdgeAllow = 'true'
            $env:resultCustomField = 'edgeReport'
            $report = & $edgeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Compliant | Should -BeTrue
            $registry[$edgePath]['HideFirstRunExperience'].Value | Should -Be 1
            $registry[$edgePath]['PasswordManagerEnabled'].Value | Should -Be 0
            $registry[$edgePath]['HomepageLocation'].Kind | Should -Be 'String'
            $registry[$edgePath].ContainsKey('BackgroundModeEnabled') | Should -BeFalse
            Should -Invoke New-ItemProperty -Times 0 -Exactly -ParameterFilter { $Name -eq 'StartupBoostEnabled' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'edgeReport' }
        }
        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            $report = & $edgeScript -ShowRecommendationsEnabled false -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ HideFirstRunExperience = 'yes' }, @{ HomepageLocation = 'http://contoso.com' }, @{ HomepageLocation = 'https://' },
                    @{ HomepageLocation = 'https://contoso.com/a b' }, @{ HomepageLocation = 'https://contoso.com/' + ('a' * 2048) },
                    @{ StartupBoostEnabled = 'true'; Allow = 'sure' })) {
                $null = & $edgeScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'setOfficeUpdateChannel' {
        BeforeEach {
            $officePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate'
            $c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
            Add-FakeRegistryValue -Store $registry -Path $c2rPath -Name 'CDNBaseUrl' -Value 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60' -Kind 'String'
            Mock Start-ScheduledTask {}
        }
        It 'Audit reports drift and installed channel / Prüfung meldet Abweichung und installierten Kanal' {
            $report = & $officeScript -Channel monthlyenterprise | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.ClickToRunInstalled | Should -BeTrue
            $report.InstalledChannel | Should -Be 'Current'
            $report.Desired | Should -Be 'MonthlyEnterprise'
            $report.ChannelChangePending | Should -BeTrue
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'Sets the policy and triggers the update with opt-in / Setzt Richtlinie und startet Update mit Opt-in' {
            $env:configOfficeChannel = 'SemiAnnual'
            $env:configOfficeAllow = 'true'
            $env:configOfficeTriggerUpdate = 'true'
            $env:resultCustomField = 'officeReport'
            $report = & $officeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.UpdateTaskStarted | Should -BeTrue
            $registry[$officePolicyPath]['updatebranch'].Value | Should -Be 'Deferred'
            $registry[$officePolicyPath]['updatebranch'].Kind | Should -Be 'String'
            Should -Invoke Start-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskPath -eq '\Microsoft\Office\' -and $TaskName -eq 'Office Automatic Updates 2.0' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'officeReport' }
            $env:resultCustomField = $null
            $null = & $officeScript
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-ScheduledTask -Times 1 -Exactly
        }
        It 'Warns when the update task fails / Warnt bei fehlgeschlagener Updateaufgabe' {
            Mock Start-ScheduledTask { throw 'Task not found' }
            $report = & $officeScript -Channel BetaChannel -Allow true -TriggerUpdate true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Compliant | Should -BeTrue
            @($report.Warnings).Count | Should -Be 1
            $registry[$officePolicyPath]['updatebranch'].Value | Should -Be 'InsiderFast'
        }
        It 'Allows the policy without Click-to-Run / Erlaubt Richtlinie ohne Klick-und-Los' {
            $registry.Remove($c2rPath)
            $report = & $officeScript -Channel CurrentPreview -Allow true -TriggerUpdate true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.ClickToRunInstalled | Should -BeFalse
            $report.InstalledChannel | Should -BeNullOrEmpty
            $registry[$officePolicyPath]['updatebranch'].Value | Should -Be 'FirstReleaseCurrent'
            Should -Invoke Start-ScheduledTask -Times 0 -Exactly
        }
        It 'WhatIf changes nothing and invalid input fails / WhatIf ändert nichts, ungültige Eingaben scheitern' {
            $report = & $officeScript -Channel Current -Allow true -TriggerUpdate true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke Start-ScheduledTask -Times 0 -Exactly
            foreach ($arguments in @(@{}, @{ Channel = 'Monthly' }, @{ Channel = 'Deferred' }, @{ Channel = 'Current'; TriggerUpdate = 'now' }, @{ Channel = 'Current'; Allow = '1' })) {
                $null = & $officeScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-ItemProperty -Times 0 -Exactly
        }
        It 'Fails when the field write fails / Fehler wenn das Feld nicht geschrieben wird' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $officeScript -Channel Current -CustomField officeReport
            $LASTEXITCODE | Should -Be 1
        }
    }
}
