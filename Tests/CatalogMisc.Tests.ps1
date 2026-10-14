BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $misc = Join-Path $root '50 - Misc'
    $bugCheckScript = Join-Path $misc 'readBugChecks.ps1'
    $shutdownScript = Join-Path $misc 'readUnexpectedShutdowns.ps1'
    $printerScript = Join-Path $misc 'checkPrinterStatus.ps1'
    $usbScript = Join-Path $misc 'readUsbStorageHistory.ps1'
    $tempScript = Join-Path $misc 'checkTempFolderSize.ps1'
    $powerScript = Join-Path $misc 'checkPowerPlan.ps1'
    $reliabilityScript = Join-Path $misc 'readReliabilityIndex.ps1'
    $appCrashScript = Join-Path $misc 'readApplicationCrashes.ps1'
    $ninjaScript = Join-Path $misc 'readNinjaAgentStatus.ps1'
    $largeFilesScript = Join-Path $misc 'readLargeFiles.ps1'
    $serviceCrashScript = Join-Path $misc 'readServiceCrashes.ps1'
    $wheaScript = Join-Path $misc 'readWheaErrors.ps1'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $MaxEvents) }
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Namespace, $Filter) }
    function Ninja-Property-Set { param($Name, $Value) }
    function powercfg { }
    function New-TestEvent {
        param([int]$Id, [object[]]$Values = @(), [int]$Level = 2, [datetime]$Time = (Get-Date).AddDays(-1))
        [pscustomobject]@{ Id = $Id; Level = $Level; TimeCreated = $Time; Properties = @($Values | ForEach-Object { [pscustomobject]@{ Value = $_ } }) }
    }
    function New-TestItem {
        param([string]$FullName, [int64]$Length = 0, [switch]$Directory, [switch]$Reparse)
        $attributes = [IO.FileAttributes]::Archive
        if ($Directory) { $attributes = [IO.FileAttributes]::Directory }
        if ($Reparse) { $attributes = $attributes -bor [IO.FileAttributes]::ReparsePoint }
        [pscustomobject]@{
            FullName = $FullName; Name = ($FullName -split '\\')[-1]; Length = $Length; PSIsContainer = [bool]$Directory
            Attributes = $attributes; LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-2)
            PSProvider = [pscustomobject]@{ Name = 'FileSystem' }
        }
    }
    $script:noEvents = {
        throw (New-Object System.Management.Automation.ErrorRecord((New-Object Exception 'No events'), 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null))
    }
    $script:envNames = @(
        'bugCheckLookbackDays', 'bugCheckMaxRecords', 'shutdownLookbackDays', 'shutdownThreshold', 'shutdownMaxRecords',
        'printerStuckJobMinutes', 'printerWarnOffline', 'printerMaxRecords', 'usbIncludeSerial', 'usbRequireBlocked', 'usbMaxRecords',
        'tempThresholdMB', 'tempIncludeUserProfiles', 'tempTimeBudgetSeconds', 'tempMaxRecords', 'powerExpectedPlan',
        'reliabilityMinimumIndex', 'reliabilityLookbackDays', 'appCrashLookbackDays', 'appCrashThreshold', 'appCrashTopApps',
        'largeFilesRootPath', 'largeFilesTop', 'largeFilesTimeBudgetSeconds', 'largeFilesMaxFiles',
        'serviceCrashLookbackDays', 'serviceCrashMaxRecords', 'wheaLookbackDays', 'wheaCorrectedThreshold', 'wheaMaxRecords',
        'resultCustomField', 'SystemRoot', 'SystemDrive'
    )
}

Describe 'Misc catalogue scripts / Misc-Katalogskripte' {
    BeforeEach {
        $saved = @{}
        foreach ($name in $script:envNames) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:SystemRoot = 'C:\Windows'
        $env:SystemDrive = 'C:'
        Mock Ninja-Property-Set {}
        Mock Get-WinEvent $script:noEvents
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'readBugChecks' {
        BeforeEach { Mock Test-Path { $false } }
        It 'Reports no bug checks / Meldet keine BugChecks' {
            $report = & $bugCheckScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.BugCheckEventCount | Should -Be 0
            $report.MinidumpCount | Should -Be 0
        }
        It 'Detects WER and Kernel-Power bug checks / Erkennt BugChecks' {
            Mock Get-WinEvent { New-TestEvent -Id 1001 -Values @('0x0000009f (0x3, 0x0)', 'C:\Windows\MEMORY.DMP', 'abc') } -ParameterFilter { $FilterHashtable.Id -eq 1001 }
            Mock Get-WinEvent { New-TestEvent -Id 41 -Values @(159); New-TestEvent -Id 41 -Values @(0) } -ParameterFilter { $FilterHashtable.Id -eq 41 }
            $report = & $bugCheckScript -CustomField 'bugCheckReport' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.BugCheckEventCount | Should -Be 2
            @($report.Events.BugcheckCode) | Should -Contain '0x0000009F'
            @($report.Events.BugcheckCode) | Should -Contain '0x0000009f'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'bugCheckReport' }
        }
        It 'Warns on recent minidumps / Warnt bei neuen Minidumps' {
            Mock Test-Path { $true }
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'Mini1.dmp'; Length = 300KB; LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-1) } }
            $report = & $bugCheckScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.RecentMinidumpCount | Should -Be 1
            $report.Minidumps[0].Name | Should -Be 'Mini1.dmp'
        }
        It 'Rejects invalid input and query errors / Lehnt Fehler ab' {
            foreach ($value in @('0', '366', 'abc', '-1')) {
                $null = & $bugCheckScript -LookbackDays $value
                $LASTEXITCODE | Should -Be 1
            }
            Mock Get-WinEvent { throw 'Access denied' }
            $null = & $bugCheckScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readUnexpectedShutdowns' {
        It 'Reports no shutdowns / Meldet keine Abschaltungen' {
            $report = & $shutdownScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.EstimatedIncidents | Should -Be 0
        }
        It 'Estimates incidents against threshold / Schätzt Vorfälle gegen Grenzwert' {
            Mock Get-WinEvent { New-TestEvent -Id 41 -Values @(0); New-TestEvent -Id 41 -Values @(0) } -ParameterFilter { $FilterHashtable.Id -eq 41 }
            Mock Get-WinEvent { New-TestEvent -Id 6008 -Values @('10:00', '01.01.2026') } -ParameterFilter { $FilterHashtable.Id -eq 6008 }
            $env:shutdownThreshold = '2'
            $report = & $shutdownScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.EstimatedIncidents | Should -Be 2
            @($report.Events).Count | Should -Be 3
            $null = & $shutdownScript -Threshold 3
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid thresholds / Lehnt ungültige Grenzwerte ab' {
            foreach ($value in @('0', '1001', '1.5')) {
                $null = & $shutdownScript -Threshold $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkPrinterStatus' {
        BeforeEach {
            $testSpoolerState = 'Running'
            $testSpoolerMode = 'Auto'
            $testPrinterOffline = $false
            $testJobAge = 5
            Mock Get-CimInstance {
                switch ($ClassName) {
                    'Win32_Service' { [pscustomobject]@{ Name = 'Spooler'; State = $testSpoolerState; StartMode = $testSpoolerMode } }
                    'Win32_Printer' { [pscustomobject]@{ Name = 'Office'; Network = $true; WorkOffline = $testPrinterOffline; PrinterStatus = 3; DetectedErrorState = 2 } }
                    'Win32_PrintJob' { [pscustomobject]@{ Name = 'Office, 12'; TimeSubmitted = (Get-Date).AddMinutes(-$testJobAge); Document = 'secret.docx' } }
                }
            }
        }
        It 'Accepts a healthy queue / Akzeptiert gesunde Warteschlange' {
            $text = & $printerScript
            $LASTEXITCODE | Should -Be 0
            $text | Should -Not -Match 'secret'
            $report = $text | ConvertFrom-Json
            $report.Printers[0].QueuedJobs | Should -Be 1
            $report.Printers[0].State | Should -Be 'OK'
        }
        It 'Warns on stuck jobs / Warnt bei hängenden Aufträgen' {
            $testJobAge = 120
            $report = & $printerScript -CustomField 'printerReport' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.StuckJobs | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'printerReport' }
        }
        It 'Warns on stopped spooler but accepts disabled spooler / Spooler gestoppt vs. deaktiviert' {
            $testSpoolerState = 'Stopped'
            $null = & $printerScript
            $LASTEXITCODE | Should -Be 2
            $testSpoolerMode = 'Disabled'
            $report = & $printerScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.SpoolerDisabled | Should -BeTrue
        }
        It 'Warns on offline printers only on request / Offline nur auf Wunsch' {
            $testPrinterOffline = $true
            $null = & $printerScript
            $LASTEXITCODE | Should -Be 0
            $null = & $printerScript -WarnOffline 'true'
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $printerScript -WarnOffline 'yes'
            $LASTEXITCODE | Should -Be 1
            $null = & $printerScript -StuckJobMinutes '0'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readUsbStorageHistory' {
        BeforeEach {
            $testUsbStart = 3
            Mock Test-Path { $true }
            Mock Get-ChildItem { [pscustomobject]@{ PSChildName = 'Disk&Ven_SanDisk&Prod_Cruzer&Rev_1.00'; PSPath = 'TestRegistry::Class1' } } -ParameterFilter { $LiteralPath -like '*Enum\USBSTOR' }
            Mock Get-ChildItem { [pscustomobject]@{ PSChildName = '4C530001231117115012&0'; PSPath = 'TestRegistry::Instance1' } } -ParameterFilter { $LiteralPath -eq 'TestRegistry::Class1' }
            Mock Get-ItemProperty { [pscustomobject]@{ FriendlyName = 'SanDisk Cruzer USB Device' } } -ParameterFilter { $LiteralPath -eq 'TestRegistry::Instance1' }
            Mock Get-ItemProperty { [pscustomobject]@{ Start = $testUsbStart } } -ParameterFilter { $LiteralPath -like '*Services\USBSTOR' }
        }
        It 'Lists devices without serials by default / Ohne Seriennummer' {
            $text = & $usbScript
            $LASTEXITCODE | Should -Be 0
            $text | Should -Not -Match '4C530001231117115012'
            $report = $text | ConvertFrom-Json
            $report.Devices[0].Vendor | Should -Be 'SanDisk'
            $report.Devices[0].FriendlyName | Should -Be 'SanDisk Cruzer USB Device'
            $report.UsbStorageBlocked | Should -BeFalse
        }
        It 'Includes serials only on request / Seriennummer nur auf Wunsch' {
            $report = & $usbScript -IncludeSerial 'true' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Devices[0].Serial | Should -Be '4C530001231117115012'
        }
        It 'Enforces blocking when required / Prüft Sperre' {
            $env:usbRequireBlocked = 'true'
            $env:resultCustomField = 'usbReport'
            $null = & $usbScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'usbReport' }
            $testUsbStart = 4
            $null = & $usbScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '101', 'x')) {
                $null = & $usbScript -MaxRecords $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $usbScript -RequireBlocked 'maybe'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkTempFolderSize' {
        BeforeEach {
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                New-TestItem -FullName 'C:\Windows\Temp\big.tmp' -Length 10MB
                New-TestItem -FullName 'C:\Windows\Temp\sub' -Directory
                New-TestItem -FullName 'C:\Windows\Temp\link' -Directory -Reparse
            } -ParameterFilter { $LiteralPath -eq 'C:\Windows\Temp' }
            Mock Get-ChildItem { New-TestItem -FullName 'C:\Windows\Temp\sub\a.log' -Length 5MB } -ParameterFilter { $LiteralPath -eq 'C:\Windows\Temp\sub' }
            Mock Get-ChildItem {
                New-TestItem -FullName 'C:\Users\alice' -Directory
                New-TestItem -FullName 'C:\Users\All Users' -Directory -Reparse
            } -ParameterFilter { $LiteralPath -eq 'C:\Users' }
            Mock Get-ChildItem { New-TestItem -FullName 'C:\Users\alice\AppData\Local\Temp\x.tmp' -Length 20MB } -ParameterFilter { $LiteralPath -eq 'C:\Users\alice\AppData\Local\Temp' }
        }
        It 'Measures system temp and skips reparse points / Misst System-Temp' {
            $report = & $tempScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalMB | Should -Be 15
            $report.SkippedReparsePoints | Should -Be 1
            $report.FoldersMeasured | Should -Be 1
        }
        It 'Warns above threshold incl. user temp / Warnt über Grenzwert' {
            $report = & $tempScript -ThresholdMB 30 -IncludeUserTemp 'true' -CustomField 'tempReport' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.TotalMB | Should -Be 35
            $report.FoldersMeasured | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'tempReport' }
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $tempScript -IncludeUserTemp 'maybe'
            $LASTEXITCODE | Should -Be 1
            $null = & $tempScript -TimeBudgetSeconds '4'
            $LASTEXITCODE | Should -Be 1
            $null = & $tempScript -ThresholdMB '1e3'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkPowerPlan' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ InstanceID = 'Microsoft:PowerPlan\{381b4222-f694-41f0-9685-ff5bb260df2e}'; ElementName = 'Ausbalanciert' } }
            Mock powercfg { $global:LASTEXITCODE = 0; 'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)' }
        }
        It 'Reads active plan via CIM / Liest aktiven Plan per CIM' {
            $report = & $powerScript -ExpectedPlan 'balanced' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.KnownPlan | Should -Be 'Balanced'
            $report.Source | Should -Be 'CIM'
            Should -Invoke powercfg -Times 0 -Exactly
        }
        It 'Warns on mismatch / Warnt bei Abweichung' {
            $env:powerExpectedPlan = '{8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C}'
            $null = & $powerScript -CustomField 'powerReport'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'powerReport' }
        }
        It 'Falls back to powercfg / Fällt auf powercfg zurück' {
            Mock Get-CimInstance { throw 'Invalid namespace' }
            $report = & $powerScript -ExpectedPlan 'HighPerformance' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'powercfg'
            $report.ActivePlanName | Should -Be 'High performance'
        }
        It 'Reports powercfg failures and invalid input / Meldet Fehler' {
            Mock Get-CimInstance { throw 'Invalid namespace' }
            Mock powercfg { $global:LASTEXITCODE = 1; 'error' }
            $null = & $powerScript
            $LASTEXITCODE | Should -Be 1
            $null = & $powerScript -ExpectedPlan 'Turbo'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readReliabilityIndex' {
        BeforeEach {
            Mock Get-CimInstance {
                [pscustomobject]@{ SystemStabilityIndex = 4.2; TimeGenerated = (Get-Date).AddHours(-1) }
                [pscustomobject]@{ SystemStabilityIndex = 6.5; TimeGenerated = (Get-Date).AddDays(-2) }
                [pscustomobject]@{ SystemStabilityIndex = 8.0; TimeGenerated = (Get-Date).AddDays(-3) }
            }
        }
        It 'Warns below the default threshold / Warnt unter Standardgrenzwert' {
            $report = & $reliabilityScript -CustomField 'reliabilityReport' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.LatestIndex | Should -Be 4.2
            $report.ChangeInRange | Should -Be -3.8
            @($report.DailyTrend).Count | Should -Be 3
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Accepts index above custom threshold / Akzeptiert Index über Grenzwert' {
            $null = & $reliabilityScript -MinimumIndex '4.0'
            $LASTEXITCODE | Should -Be 0
        }
        It 'Reports NotAvailable as exit 0 / Meldet NotAvailable mit Exit 0' {
            Mock Get-CimInstance { throw 'Invalid class "Win32_ReliabilityStabilityMetrics"' }
            $report = & $reliabilityScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Available | Should -BeFalse
            Mock Get-CimInstance {}
            $report = & $reliabilityScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'NotAvailable'
        }
        It 'Rejects query errors and invalid input / Lehnt Fehler ab' {
            Mock Get-CimInstance { throw 'Access denied' }
            $null = & $reliabilityScript
            $LASTEXITCODE | Should -Be 1
            foreach ($value in @('5,0', '11', '0.5', 'abc')) {
                $null = & $reliabilityScript -MinimumIndex $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'readApplicationCrashes' {
        BeforeEach {
            Mock Get-WinEvent { 1..3 | ForEach-Object { New-TestEvent -Id 1000 -Values @('App.exe', '1.0') } } -ParameterFilter { $FilterHashtable.Id -eq 1000 }
            Mock Get-WinEvent { New-TestEvent -Id 1002 -Values @('other.exe', '2.0') } -ParameterFilter { $FilterHashtable.Id -eq 1002 }
        }
        It 'Groups by application / Gruppiert nach Anwendung' {
            $report = & $appCrashScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 4
            $report.Applications[0].Application | Should -Be 'App.exe'
            $report.Applications[0].Crashes | Should -Be 3
            $report.Applications[1].Hangs | Should -Be 1
        }
        It 'Warns at threshold and limits top list / Warnt am Grenzwert' {
            $report = & $appCrashScript -Threshold 4 -Top 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Applications).Count | Should -Be 1
            $report.Truncated | Should -BeTrue
        }
        It 'Rejects invalid input and write failures / Lehnt Fehler ab' {
            $null = & $appCrashScript -Top '0'
            $LASTEXITCODE | Should -Be 1
            $null = & $appCrashScript -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 5 }
            $null = & $appCrashScript -CustomField 'appCrashReport'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readNinjaAgentStatus' {
        BeforeEach {
            $testAgentState = 'Running'
            Mock Get-CimInstance {
                switch ($ClassName) {
                    'Win32_Service' {
                        [pscustomobject]@{ Name = 'NinjaRMMAgent'; DisplayName = 'NinjaRMMAgent'; State = $testAgentState; StartMode = 'Auto'
                            PathName = '"C:\Program Files (x86)\Org\NinjaRMMAgent.exe" /service /token=SECRETVALUE'; ProcessId = 1234 }
                    }
                    'Win32_Process' { [pscustomobject]@{ ProcessId = 1234; CreationDate = (Get-Date).AddHours(-5) } }
                }
            }
            Mock Get-Item { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ FileVersion = '5.9.1234' } } }
        }
        It 'Reports running agent without arguments / Meldet laufenden Agent ohne Argumente' {
            $text = & $ninjaScript
            $LASTEXITCODE | Should -Be 0
            $text | Should -Not -Match 'SECRETVALUE'
            $report = $text | ConvertFrom-Json
            $report.AgentVersion | Should -Be '5.9.1234'
            $report.Services[0].InstallPath | Should -Be 'C:\Program Files (x86)\Org'
            $report.Services[0].UptimeHours | Should -BeGreaterOrEqual 4.9
        }
        It 'Warns when stopped or missing / Warnt bei gestopptem oder fehlendem Agent' {
            $testAgentState = 'Stopped'
            $null = & $ninjaScript -CustomField 'ninjaAgentStatus'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'ninjaAgentStatus' }
            Mock Get-CimInstance {}
            $report = & $ninjaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Problems) | Should -Contain 'NoNinjaRMMAgentService'
        }
        It 'Rejects invalid field names / Lehnt ungültige Feldnamen ab' {
            $null = & $ninjaScript -CustomField '1bad'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readLargeFiles' {
        BeforeEach {
            $testDriveType = 3
            Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'D:'; DriveType = $testDriveType } }
            Mock Get-Item { New-TestItem -FullName 'D:\Data' -Directory }
            Mock Get-ChildItem {
                New-TestItem -FullName 'D:\Data\a.iso' -Length 4GB
                New-TestItem -FullName 'D:\Data\b.vhdx' -Length 8GB
                New-TestItem -FullName 'D:\Data\c.txt' -Length 1KB
                New-TestItem -FullName 'D:\Data\sub' -Directory
                New-TestItem -FullName 'D:\Data\cloud.bin' -Length 50GB -Reparse
            } -ParameterFilter { $LiteralPath -eq 'D:\Data' }
            Mock Get-ChildItem { New-TestItem -FullName 'D:\Data\sub\d.bak' -Length 2GB } -ParameterFilter { $LiteralPath -eq 'D:\Data\sub' }
        }
        It 'Reports top files and skips reparse points / Meldet größte Dateien' {
            $report = & $largeFilesScript -RootPath 'D:\Data' -Top 2 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Files.Path) | Should -Be @('D:\Data\b.vhdx', 'D:\Data\a.iso')
            $report.FilesScanned | Should -Be 4
            $report.SkippedReparsePoints | Should -Be 1
        }
        It 'Warns when truncated by MaxFiles / Warnt bei Kürzung' {
            Mock Get-ChildItem { 1..1001 | ForEach-Object { New-TestItem -FullName ('D:\Data\f{0}.dat' -f $_) -Length $_ } } -ParameterFilter { $LiteralPath -eq 'D:\Data' }
            $env:largeFilesRootPath = 'D:\Data'
            $report = & $largeFilesScript -MaxFiles 1000 -Top 3 -CustomField 'largeFiles' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.StopReason | Should -Be 'MaxFiles'
            $report.Files[0].Path | Should -Be 'D:\Data\f1000.dat'
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Rejects non-local or unsafe paths / Lehnt unsichere Pfade ab' {
            foreach ($value in @('\\server\share', 'Data', 'D:\Data\..\Windows', 'D:/Data', 'D:\Da*ta')) {
                $null = & $largeFilesScript -RootPath $value
                $LASTEXITCODE | Should -Be 1
            }
            $testDriveType = 4
            $null = & $largeFilesScript -RootPath 'D:\Data'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readServiceCrashes' {
        It 'Reports no service crashes / Meldet keine Dienstabstürze' {
            $report = & $serviceCrashScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 0
        }
        It 'Groups crashes by service / Gruppiert nach Dienst' {
            Mock Get-WinEvent {
                New-TestEvent -Id 7031 -Values @('Print Spooler', 1)
                New-TestEvent -Id 7034 -Values @('Print Spooler', 2)
                New-TestEvent -Id 7023 -Values @('Example Service', 'error')
            }
            $report = & $serviceCrashScript -CustomField 'serviceCrashes' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Services[0].Service | Should -Be 'Print Spooler'
            $report.Services[0].UnexpectedTerminations | Should -Be 2
            $report.Services[1].ErrorTerminations | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $serviceCrashScript -LookbackDays '91'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readWheaErrors' {
        It 'Accepts few corrected errors / Akzeptiert wenige korrigierte Fehler' {
            Mock Get-WinEvent { New-TestEvent -Id 19 -Level 3; New-TestEvent -Id 19 -Level 3 }
            $report = & $wheaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.CorrectedEvents | Should -Be 2
            $report.Groups[0].Count | Should -Be 2
        }
        It 'Warns on fatal or many corrected errors / Warnt bei Fatal oder vielen korrigierten' {
            Mock Get-WinEvent { New-TestEvent -Id 18 -Level 2 }
            $report = & $wheaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FatalEvents | Should -Be 1
            Mock Get-WinEvent { 1..3 | ForEach-Object { New-TestEvent -Id 47 -Level 3 } }
            $null = & $wheaScript -CorrectedThreshold 3
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $wheaScript -CorrectedThreshold '0'
            $LASTEXITCODE | Should -Be 1
            $null = & $wheaScript -MaxRecords '51'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
