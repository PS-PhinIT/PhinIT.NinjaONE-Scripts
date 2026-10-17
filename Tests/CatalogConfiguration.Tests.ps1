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
}
