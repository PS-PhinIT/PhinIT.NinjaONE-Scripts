BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $uptimeScript = Join-Path $root '01 - System/readUptime.ps1'
    $systemScript = Join-Path $root '01 - System/readSystemInfo.ps1'
    $rebootScript = Join-Path $root '50 - Misc/restartPendingCheck.ps1'

    # DE: Stubs erlauben Tests ohne Windows und ohne NinjaOne-Agent.
    # EN: Stubs allow testing without Windows or a NinjaOne agent.
    function Get-CimInstance { param($ClassName) }
    function Ninja-Property-Set { param($Name, $Value) }
}

Describe 'NinjaOne diagnostics / NinjaOne-Diagnose' {
    BeforeEach {
        $savedVariables = @{}
        foreach ($name in @('maximumUptimeHours', 'uptimeCustomField', 'systemInfoCustomField', 'rebootPendingCustomField')) {
            $savedVariables[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Get-CimInstance {
            switch ($ClassName) {
                'Win32_OperatingSystem' {
                    [pscustomobject]@{
                        LastBootUpTime = [DateTime]::Now.AddMinutes(-150)
                        Caption = 'Windows Test'
                        Version = '10.0'
                        BuildNumber = '12345'
                        OSArchitecture = '64-bit'
                    }
                }
                'Win32_ComputerSystem' {
                    [pscustomobject]@{
                        Name = 'TEST-PC'
                        Manufacturer = 'Test'
                        Model = 'Virtual'
                        NumberOfLogicalProcessors = 4
                        TotalPhysicalMemory = 8GB
                    }
                }
                'Win32_Processor' { [pscustomobject]@{ Name = 'Test CPU' } }
            }
        }
        Mock Ninja-Property-Set {}
    }

    AfterEach {
        foreach ($name in $savedVariables.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedVariables[$name])
        }
    }

    It 'Uses defaults without NinjaOne / Nutzt Standardwerte ohne NinjaOne' {
        $output = & $uptimeScript
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '2 h; Limit: 720 h'
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Uses script variables and reports a warning / Nutzt Variablen und meldet Warnung' {
        $env:maximumUptimeHours = '2'
        $env:uptimeCustomField = 'uptimeHours'
        $null = & $uptimeScript
        $LASTEXITCODE | Should -Be 2
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'uptimeHours' -and $Value -eq 2
        }
    }

    It 'Explicit parameters win / Explizite Parameter haben Vorrang' {
        $env:maximumUptimeHours = '2'
        $env:uptimeCustomField = 'unusedField'
        $null = & $uptimeScript -MaximumUptimeHours 10 -CustomField ''
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Treats null variables as empty / Behandelt null-Variablen als leer' {
        $env:maximumUptimeHours = 'null'
        $env:uptimeCustomField = 'null'
        $null = & $uptimeScript
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }

    It 'Rejects invalid thresholds / Lehnt ungültige Grenzwerte ab' {
        foreach ($value in @('0', '-1', '87601', 'abc', '2.5', '2147483648')) {
            $null = & $uptimeScript -MaximumUptimeHours $value
            $LASTEXITCODE | Should -Be 1
        }
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'Rejects missing and future boot times / Lehnt fehlende und zukünftige Startzeiten ab' {
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = $null } }
        $null = & $uptimeScript
        $LASTEXITCODE | Should -Be 1
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = [DateTime]::Now.AddHours(1) } }
        $null = & $uptimeScript
        $LASTEXITCODE | Should -Be 1
    }

    It 'Reports query failures / Meldet Abfragefehler' {
        Mock Get-CimInstance { throw 'Simulated CIM failure' }
        foreach ($script in @($uptimeScript, $systemScript)) {
            $null = & $script
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'Writes structured system information / Schreibt strukturierte Systemdaten' {
        $env:systemInfoCustomField = 'systemInfo'
        $output = & $systemScript
        $LASTEXITCODE | Should -Be 0
        $data = $output | ConvertFrom-Json
        $data.MemoryGiB | Should -Be 8
        $data.Cpu | Should -Be 'Test CPU'
        $data.ComputerName | Should -Be 'TEST-PC'
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'systemInfo' -and ($Value | ConvertFrom-Json).MemoryGiB -eq 8
        }
    }

    It 'Rejects incomplete system information / Lehnt unvollständige Systemdaten ab' {
        Mock Get-CimInstance { $null }
        $null = & $systemScript
        $LASTEXITCODE | Should -Be 1
    }

    It 'Reports custom field write errors / Meldet Custom-Field-Schreibfehler' {
        Mock Ninja-Property-Set { Write-Error 'Simulated field failure' }
        foreach ($script in @($uptimeScript, $systemScript)) {
            $null = & $script -CustomField 'testField'
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'Reports native CLI failures / Meldet native CLI-Fehler' {
        Mock Ninja-Property-Set { $global:LASTEXITCODE = 9 }
        foreach ($script in @($uptimeScript, $systemScript)) {
            $null = & $script -CustomField 'testField'
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'Fails clearly when NinjaOne is unavailable / Meldet fehlendes NinjaOne' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Ninja-Property-Set' }
        foreach ($script in @($uptimeScript, $systemScript, $rebootScript)) {
            $output = & $script -CustomField 'testField'
            $LASTEXITCODE | Should -Be 1
            $output | Should -Match 'Ninja-Property-Set'
        }
    }
}
