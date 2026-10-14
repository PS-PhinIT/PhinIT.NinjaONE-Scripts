BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $cpuScript = Join-Path $root '01 - System/readCpuUsage.ps1'
    $memoryScript = Join-Path $root '01 - System/readMemoryUsage.ps1'
    $pageFileScript = Join-Path $root '01 - System/readPageFileStatus.ps1'
    $diskHealthScript = Join-Path $root '01 - System/checkPhysicalDiskHealth.ps1'
    $biosScript = Join-Path $root '01 - System/readBiosFirmware.ps1'
    $secureBootScript = Join-Path $root '01 - System/checkSecureBootStatus.ps1'
    $batteryScript = Join-Path $root '01 - System/readBatteryHealth.ps1'
    $topProcessScript = Join-Path $root '01 - System/readTopProcesses.ps1'
    $activationScript = Join-Path $root '01 - System/checkWindowsActivation.ps1'
    $deviceScript = Join-Path $root '01 - System/readDeviceProblems.ps1'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Namespace, $Filter) }
    function Confirm-SecureBootUEFI { [CmdletBinding()] param() }
    function Ninja-Property-Set { param($Name, $Value) }
    function ConvertFrom-ScriptOutput { param($Output) ($Output -join "`n") | ConvertFrom-Json }
}

Describe 'System catalogue scripts / System-Katalogskripte' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('systemCpuThresholdPercent', 'systemCpuSampleCount', 'systemCpuSampleIntervalSeconds',
                'systemMemoryThresholdPercent', 'systemMemoryCommitThresholdPercent', 'systemPageFileThresholdPercent',
                'systemDiskMaxRecords', 'systemBiosMaxAgeDays', 'systemSecureBootAllowUnsupported',
                'systemBatteryMinHealthPercent', 'systemTopProcessCount', 'systemTopProcessSortBy',
                'systemDeviceMaxRecords', 'systemDeviceIgnoreCodes', 'resultCustomField')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Ninja-Property-Set {}
        Mock Start-Sleep {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'readCpuUsage' {
        It 'Reports average CPU below threshold / Meldet CPU-Mittelwert unter Grenzwert' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = '_Total'; PercentProcessorTime = 20 } }
            $report = ConvertFrom-ScriptOutput (& $cpuScript -SampleCount 3 -SampleIntervalSeconds 1)
            $LASTEXITCODE | Should -Be 0
            $report.AveragePercent | Should -Be 20
            @($report.Samples).Count | Should -Be 3
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }
        It 'Warns above threshold and writes field / Warnt über Grenzwert und schreibt Feld' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = '_Total'; PercentProcessorTime = 95 } }
            $env:systemCpuThresholdPercent = '90'
            $env:systemCpuSampleCount = '2'
            $env:resultCustomField = 'cpuUsage'
            $null = & $cpuScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'cpuUsage' }
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            Mock Get-CimInstance { [pscustomobject]@{ PercentProcessorTime = 5 } }
            foreach ($value in @('0', '101', 'abc', '1.5')) {
                $null = & $cpuScript -ThresholdPercent $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $cpuScript -SampleCount 30 -SampleIntervalSeconds 10
            $LASTEXITCODE | Should -Be 1
            $null = & $cpuScript -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-CimInstance -Times 0 -Exactly
        }
        It 'Fails on missing performance data / Fehler bei fehlenden Leistungsdaten' {
            Mock Get-CimInstance {}
            $null = & $cpuScript -SampleCount 1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readMemoryUsage' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 8388608
                    TotalVirtualMemorySize = 33554432; FreeVirtualMemory = 16777216 } }
        }
        It 'Reports memory and commit usage / Meldet Speicher- und Commit-Nutzung' {
            $report = ConvertFrom-ScriptOutput (& $memoryScript)
            $LASTEXITCODE | Should -Be 0
            $report.UsedPercent | Should -Be 50
            $report.CommitUsedPercent | Should -Be 50
            $report.TotalGiB | Should -Be 16
        }
        It 'Warns on high physical memory / Warnt bei hoher RAM-Nutzung' {
            Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 1048576
                    TotalVirtualMemorySize = 33554432; FreeVirtualMemory = 16777216 } }
            $null = & $memoryScript -CustomField 'memoryUsage'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'memoryUsage' }
        }
        It 'Warns on commit only when enabled / Warnt bei Commit nur wenn aktiv' {
            Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 8388608
                    TotalVirtualMemorySize = 33554432; FreeVirtualMemory = 524288 } }
            $null = & $memoryScript
            $LASTEXITCODE | Should -Be 2
            $env:systemMemoryCommitThresholdPercent = '0'
            $null = & $memoryScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '101', 'x')) {
                $env:systemMemoryThresholdPercent = $value
                $null = & $memoryScript
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $memoryScript -ThresholdPercent 'null' -CommitThresholdPercent '-1'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readPageFileStatus' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ AutomaticManagedPagefile = $true } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'C:\pagefile.sys'; AllocatedBaseSize = 4096; CurrentUsage = 512; PeakUsage = 1024; TempPageFile = $false } } -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' }
            Mock Get-CimInstance {} -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
        }
        It 'Reports page file usage / Meldet Auslagerungsdatei' {
            $report = ConvertFrom-ScriptOutput (& $pageFileScript)
            $LASTEXITCODE | Should -Be 0
            $report.AutomaticManagedPagefile | Should -BeTrue
            $report.PageFiles[0].UsedPercent | Should -Be 12.5
        }
        It 'Warns without page file / Warnt ohne Auslagerungsdatei' {
            Mock Get-CimInstance {} -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' }
            $report = ConvertFrom-ScriptOutput (& $pageFileScript)
            $LASTEXITCODE | Should -Be 2
            $report.NoPageFile | Should -BeTrue
        }
        It 'Warns on high usage and writes field / Warnt bei hoher Nutzung und schreibt Feld' {
            $env:systemPageFileThresholdPercent = '10'
            $env:resultCustomField = 'pageFileStatus'
            $null = & $pageFileScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'pageFileStatus' }
        }
        It 'Rejects invalid threshold / Lehnt ungültigen Grenzwert ab' {
            $null = & $pageFileScript -ThresholdPercent '0'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkPhysicalDiskHealth' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ DeviceId = '0'; FriendlyName = 'NVMe Disk'; MediaType = 4; BusType = 17
                    Size = 512GB; HealthStatus = 0; OperationalStatus = @(2) } } -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
            Mock Get-CimInstance { throw 'Not supported' } -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' }
        }
        It 'Reports healthy disks without SMART / Meldet gesunde Datenträger ohne SMART' {
            $report = ConvertFrom-ScriptOutput (& $diskHealthScript)
            $LASTEXITCODE | Should -Be 0
            $report.SmartAvailable | Should -BeFalse
            $report.Disks[0].HealthStatus | Should -Be 'Healthy'
            $report.Disks[0].MediaType | Should -Be 'SSD'
            $report.Disks[0].BusType | Should -Be 'NVMe'
        }
        It 'Warns on unhealthy disk / Warnt bei ungesundem Datenträger' {
            Mock Get-CimInstance { [pscustomobject]@{ DeviceId = '1'; FriendlyName = 'HDD'; MediaType = 3; BusType = 11
                    Size = 1TB; HealthStatus = 1; OperationalStatus = @(5) } } -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
            $report = ConvertFrom-ScriptOutput (& $diskHealthScript)
            $LASTEXITCODE | Should -Be 2
            $report.Disks[0].OperationalStatus | Should -Be 'Predictive Failure'
        }
        It 'Warns on SMART predicted failure / Warnt bei SMART-Ausfallvorhersage' {
            Mock Get-CimInstance { [pscustomobject]@{ InstanceName = 'SCSI\Disk_0'; PredictFailure = $true; Reason = 5 } } -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictStatus' }
            $report = ConvertFrom-ScriptOutput (& $diskHealthScript -CustomField 'diskHealth')
            $LASTEXITCODE | Should -Be 2
            $report.SmartPredictFailures | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'diskHealth' }
        }
        It 'Shrinks oversized lists / Kürzt übergroße Listen' {
            Mock Get-CimInstance {
                foreach ($i in 1..64) {
                    [pscustomobject]@{ DeviceId = [string]$i; FriendlyName = ('Disk' + $i).PadRight(120, 'x'); MediaType = 3
                        BusType = 11; Size = 1TB; HealthStatus = 0; OperationalStatus = @(2) }
                }
            } -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
            $output = & $diskHealthScript -MaxRecords 64 -CustomField 'diskHealth'
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n").Length | Should -BeLessOrEqual 4000
            (ConvertFrom-ScriptOutput $output).Truncated | Should -BeTrue
        }
        It 'Fails without disks or with invalid input / Fehler ohne Datenträger oder bei ungültiger Eingabe' {
            $null = & $diskHealthScript -MaxRecords '0'
            $LASTEXITCODE | Should -Be 1
            Mock Get-CimInstance {} -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
            $null = & $diskHealthScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readBiosFirmware' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ Manufacturer = 'Contoso'; SMBIOSBIOSVersion = '1.2.3'; Version = 'CONTSO - 1'
                    ReleaseDate = (Get-Date).AddDays(-100); SerialNumber = 'SN123'; SMBIOSMajorVersion = 3; SMBIOSMinorVersion = 4 } }
            Mock Get-ItemProperty { [pscustomobject]@{ PEFirmwareType = 2 } } -ParameterFilter { $Name -eq 'PEFirmwareType' }
        }
        It 'Reports firmware data / Meldet Firmwaredaten' {
            $report = ConvertFrom-ScriptOutput (& $biosScript)
            $LASTEXITCODE | Should -Be 0
            $report.FirmwareType | Should -Be 'UEFI'
            $report.SerialNumber | Should -Be 'SN123'
            $report.SmbiosVersion | Should -Be '3.4'
            $report.AgeDays | Should -Be 100
        }
        It 'Warns on outdated BIOS / Warnt bei veraltetem BIOS' {
            $env:systemBiosMaxAgeDays = '30'
            $env:resultCustomField = 'biosFirmware'
            $null = & $biosScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'biosFirmware' }
        }
        It 'Reports unknown firmware type and legacy BIOS / Meldet unbekannten Typ und Legacy-BIOS' {
            Mock Get-ItemProperty { throw 'missing' } -ParameterFilter { $Name -eq 'PEFirmwareType' }
            (ConvertFrom-ScriptOutput (& $biosScript)).FirmwareType | Should -Be 'Unknown'
            Mock Get-ItemProperty { [pscustomobject]@{ PEFirmwareType = 1 } } -ParameterFilter { $Name -eq 'PEFirmwareType' }
            (ConvertFrom-ScriptOutput (& $biosScript)).FirmwareType | Should -Be 'BIOS'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('-1', '36501', 'abc')) {
                $null = & $biosScript -MaxAgeDays $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkSecureBootStatus' {
        BeforeEach {
            Mock Get-ItemProperty { [pscustomobject]@{ PEFirmwareType = 2 } } -ParameterFilter { $Name -eq 'PEFirmwareType' }
        }
        It 'Accepts enabled Secure Boot / Akzeptiert aktiviertes Secure Boot' {
            Mock Confirm-SecureBootUEFI { $true }
            $report = ConvertFrom-ScriptOutput (& $secureBootScript)
            $LASTEXITCODE | Should -Be 0
            $report.SecureBoot | Should -Be 'Enabled'
        }
        It 'Warns when disabled / Warnt wenn deaktiviert' {
            Mock Confirm-SecureBootUEFI { $false }
            $null = & $secureBootScript -CustomField 'secureBootStatus'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'secureBootStatus' }
        }
        It 'Handles unsupported platforms / Behandelt nicht unterstützte Plattformen' {
            Mock Confirm-SecureBootUEFI { throw [System.PlatformNotSupportedException]::new('Cmdlet not supported on this platform') }
            $report = ConvertFrom-ScriptOutput (& $secureBootScript)
            $LASTEXITCODE | Should -Be 2
            $report.SecureBoot | Should -Be 'NotSupported'
            $env:systemSecureBootAllowUnsupported = 'true'
            $null = & $secureBootScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Reports access errors and invalid input / Meldet Zugriffsfehler und ungültige Eingaben' {
            Mock Confirm-SecureBootUEFI { throw [System.UnauthorizedAccessException]::new('Access denied') }
            $null = & $secureBootScript
            $LASTEXITCODE | Should -Be 1
            $null = & $secureBootScript -AllowUnsupported 'yes'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readBatteryHealth' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Primary'; BatteryStatus = 2; EstimatedChargeRemaining = 80; Chemistry = 6 } } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
            Mock Get-CimInstance { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; DesignedCapacity = 50000 } } -ParameterFilter { $ClassName -eq 'BatteryStaticData' }
            Mock Get-CimInstance { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = 45000 } } -ParameterFilter { $ClassName -eq 'BatteryFullChargedCapacity' }
        }
        It 'Reports healthy battery / Meldet gesunden Akku' {
            $report = ConvertFrom-ScriptOutput (& $batteryScript)
            $LASTEXITCODE | Should -Be 0
            $report.HasBattery | Should -BeTrue
            $report.Capacity[0].HealthPercent | Should -Be 90
            $report.Capacity[0].WearPercent | Should -Be 10
            $report.Batteries[0].Status | Should -Be 'AC'
        }
        It 'Warns on worn battery / Warnt bei verschlissenem Akku' {
            Mock Get-CimInstance { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = 20000 } } -ParameterFilter { $ClassName -eq 'BatteryFullChargedCapacity' }
            $env:resultCustomField = 'batteryHealth'
            $null = & $batteryScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'batteryHealth' }
        }
        It 'Handles missing battery and capacity data / Behandelt fehlenden Akku und fehlende Kapazität' {
            Mock Get-CimInstance { throw 'Not supported' } -ParameterFilter { $ClassName -eq 'BatteryStaticData' }
            $report = ConvertFrom-ScriptOutput (& $batteryScript)
            $LASTEXITCODE | Should -Be 0
            $report.CapacityDataAvailable | Should -BeFalse
            Mock Get-CimInstance {} -ParameterFilter { $ClassName -eq 'Win32_Battery' }
            $report = ConvertFrom-ScriptOutput (& $batteryScript)
            $LASTEXITCODE | Should -Be 0
            $report.HasBattery | Should -BeFalse
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $batteryScript -MinHealthPercent '0'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readTopProcesses' {
        BeforeEach {
            Mock Get-Process {
                [pscustomobject]@{ ProcessName = 'alpha'; Id = 10; CPU = 5.0; WorkingSet64 = 300MB; PrivateMemorySize64 = 100MB; HandleCount = 10 }
                [pscustomobject]@{ ProcessName = 'beta'; Id = 20; CPU = 50.0; WorkingSet64 = 100MB; PrivateMemorySize64 = 50MB; HandleCount = 20 }
                [pscustomobject]@{ ProcessName = 'System'; Id = 4; CPU = $null; WorkingSet64 = 1MB; PrivateMemorySize64 = 0; HandleCount = 30 }
            }
        }
        It 'Sorts by CPU / Sortiert nach CPU' {
            $report = ConvertFrom-ScriptOutput (& $topProcessScript -Top 2)
            $LASTEXITCODE | Should -Be 0
            @($report.Processes).Count | Should -Be 2
            $report.Processes[0].Name | Should -Be 'beta'
            $report.TotalProcesses | Should -Be 3
        }
        It 'Sorts by memory from variables / Sortiert nach Speicher aus Variablen' {
            $env:systemTopProcessSortBy = 'memory'
            $env:resultCustomField = 'topProcesses'
            $report = ConvertFrom-ScriptOutput (& $topProcessScript)
            $LASTEXITCODE | Should -Be 0
            $report.Processes[0].Name | Should -Be 'alpha'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'topProcesses' }
        }
        It 'Shrinks oversized reports / Kürzt übergroße Berichte' {
            Mock Get-Process {
                foreach ($i in 1..60) {
                    [pscustomobject]@{ ProcessName = ('proc' + $i).PadRight(64, 'x'); Id = $i; CPU = $i; WorkingSet64 = 1MB; PrivateMemorySize64 = 1MB; HandleCount = 1 }
                }
            }
            $output = & $topProcessScript -Top 50
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n").Length | Should -BeLessOrEqual 4000
            (ConvertFrom-ScriptOutput $output).Truncated | Should -BeTrue
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $topProcessScript -SortBy 'Disk'
            $LASTEXITCODE | Should -Be 1
            foreach ($value in @('0', '51', 'ten')) {
                $null = & $topProcessScript -Top $value
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Get-Process -Times 0 -Exactly
        }
    }

    Context 'checkWindowsActivation' {
        It 'Accepts licensed Windows without full key / Akzeptiert Lizenz ohne vollständigen Schlüssel' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Windows(R), Professional edition'; LicenseStatus = 1; PartialProductKey = 'ABCDE'; ProductKeyChannel = 'Retail'; GracePeriodRemaining = 0 } }
            $output = & $activationScript
            $LASTEXITCODE | Should -Be 0
            $report = ConvertFrom-ScriptOutput $output
            $report.Activated | Should -BeTrue
            $report.Products[0].LicenseStatus | Should -Be 'Licensed'
            $report.Products[0].PartialProductKey | Should -Be 'ABCDE'
        }
        It 'Never outputs malformed or full keys / Gibt keine vollständigen Schlüssel aus' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Windows'; LicenseStatus = 1; PartialProductKey = 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' } }
            $output = & $activationScript
            ($output -join "`n") | Should -Not -Match 'AAAAA'
            (ConvertFrom-ScriptOutput $output).Products[0].PartialProductKey | Should -BeNullOrEmpty
        }
        It 'Warns when not licensed / Warnt ohne Lizenz' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Windows'; LicenseStatus = 5; PartialProductKey = 'ABCDE' } }
            $report = ConvertFrom-ScriptOutput (& $activationScript -CustomField 'windowsActivation')
            $LASTEXITCODE | Should -Be 2
            $report.Products[0].LicenseStatus | Should -Be 'Notification'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'windowsActivation' }
            Mock Get-CimInstance {}
            $null = & $activationScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Reports query errors and invalid field names / Meldet Abfragefehler und ungültige Feldnamen' {
            Mock Get-CimInstance { throw 'Simulated CIM failure' }
            $null = & $activationScript
            $LASTEXITCODE | Should -Be 1
            $null = & $activationScript -CustomField '1field'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readDeviceProblems' {
        It 'Accepts systems without problem devices / Akzeptiert Systeme ohne Problemgeräte' {
            Mock Get-CimInstance {}
            $report = ConvertFrom-ScriptOutput (& $deviceScript)
            $LASTEXITCODE | Should -Be 0
            $report.TotalProblems | Should -Be 0
        }
        It 'Warns on problem devices / Warnt bei Problemgeräten' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Unknown device'; PNPClass = $null; ConfigManagerErrorCode = 28; PNPDeviceID = 'PCI\VEN_1234&DEV_5678\0' } }
            $env:resultCustomField = 'deviceProblems'
            $report = ConvertFrom-ScriptOutput (& $deviceScript)
            $LASTEXITCODE | Should -Be 2
            $report.Devices[0].Problem | Should -Be 'Drivers not installed'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'deviceProblems' }
        }
        It 'Ignores configured codes / Ignoriert konfigurierte Codes' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'Disabled NIC'; PNPClass = 'Net'; ConfigManagerErrorCode = 22; PNPDeviceID = 'PCI\X' } }
            $report = ConvertFrom-ScriptOutput (& $deviceScript -IgnoreCodes '22, 45')
            $LASTEXITCODE | Should -Be 0
            $report.IgnoredDevices | Should -Be 1
        }
        It 'Shrinks oversized lists / Kürzt übergroße Listen' {
            Mock Get-CimInstance {
                foreach ($i in 1..100) {
                    [pscustomobject]@{ Name = ('Device' + $i).PadRight(100, 'x'); PNPClass = 'USB'; ConfigManagerErrorCode = 43; PNPDeviceID = ('USB\' + $i).PadRight(120, 'y') }
                }
            }
            $output = & $deviceScript -MaxRecords 100
            $LASTEXITCODE | Should -Be 2
            ($output -join "`n").Length | Should -BeLessOrEqual 4000
            $report = ConvertFrom-ScriptOutput $output
            $report.Truncated | Should -BeTrue
            $report.TotalProblems | Should -Be 100
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            Mock Get-CimInstance {}
            foreach ($value in @('abc', '0', '22,,45', '100')) {
                $null = & $deviceScript -IgnoreCodes $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $deviceScript -MaxRecords '101'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-CimInstance -Times 0 -Exactly
        }
    }
}
