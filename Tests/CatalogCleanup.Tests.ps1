#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Cleanup catalog / Bereinigungskatalog' {
    BeforeAll {
        $cleanupTest = @{}
        $cleanupTest.folder = Join-Path (Split-Path $PSScriptRoot -Parent) '08 - Cleanup'
        $cleanupTest.scripts = @{
            Temp      = Join-Path $cleanupTest.folder 'cleanupTempFiles.ps1'
            Recycle   = Join-Path $cleanupTest.folder 'cleanupRecycleBin.ps1'
            Wer       = Join-Path $cleanupTest.folder 'cleanupWindowsErrorReports.ps1'
            Do        = Join-Path $cleanupTest.folder 'cleanupDeliveryOptimizationCache.ps1'
            Component = Join-Path $cleanupTest.folder 'cleanupComponentStore.ps1'
            Browser   = Join-Path $cleanupTest.folder 'cleanupBrowserCache.ps1'
            Profiles  = Join-Path $cleanupTest.folder 'removeStaleUserProfiles.ps1'
            Uninstall = Join-Path $cleanupTest.folder 'uninstallSoftware.ps1'
            Appx      = Join-Path $cleanupTest.folder 'removeAppxBloatware.ps1'
        }

        $cleanupTest.envNames = @(
            'resultCustomField', 'windir', 'ProgramData', 'PUBLIC', 'TEMP',
            'cleanupTempAllow', 'cleanupTempMinimumAgeDays', 'cleanupTempIncludeUserProfiles', 'cleanupTempRemoveEmptyFolders', 'cleanupTempTimeBudgetSeconds',
            'cleanupRecycleBinAllow', 'cleanupRecycleBinMinimumAgeDays',
            'cleanupWerAllow', 'cleanupWerMinimumAgeDays', 'cleanupWerIncludeCrashDumps',
            'cleanupDoAllow', 'cleanupDoMinimumCacheMB',
            'cleanupComponentStoreAllow', 'cleanupComponentStoreResetBase',
            'cleanupBrowserCacheAllow', 'cleanupBrowserCacheBrowsers', 'cleanupBrowserCacheSkipRunning',
            'cleanupProfilesAllow', 'cleanupProfilesMinimumAgeDays', 'cleanupProfilesExclude', 'cleanupProfilesMaxRemovals', 'cleanupProfilesIncludeUnknownAge',
            'uninstallSoftwareName', 'uninstallMatchMode', 'uninstallAllow', 'uninstallMaxMatches', 'uninstallExeArguments', 'uninstallTimeoutMinutes',
            'appxRemoveAllow', 'appxRemoveNames', 'appxRemoveDeprovision'
        )

        function Get-CimInstance { [CmdletBinding()] param($ClassName, $Filter, $Namespace) }
        function Invoke-CimMethod { [CmdletBinding()] param($InputObject, $MethodName) }
        function Remove-CimInstance { [CmdletBinding()] param($InputObject) }
        function dism { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
        function Get-DeliveryOptimizationPerfSnap { [CmdletBinding()] param() }
        function Get-DOConfig { [CmdletBinding()] param() }
        function Delete-DeliveryOptimizationCache { [CmdletBinding()] param([switch]$Force) }
        function Get-AppxPackage { [CmdletBinding()] param([switch]$AllUsers, $Name) }
        function Remove-AppxPackage { [CmdletBinding()] param($Package, [switch]$AllUsers) }
        function Get-AppxProvisionedPackage { [CmdletBinding()] param([switch]$Online) }
        function Remove-AppxProvisionedPackage { [CmdletBinding()] param([switch]$Online, $PackageName) }
        function Ninja-Property-Set { [CmdletBinding()] param($Name, $Value) }

        function New-AgedFile {
            param([string]$Path, [int]$AgeDays, [string]$Content = 'data')
            $directory = Split-Path -Path $Path -Parent
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath $Path -Value $Content
            $stamp = [DateTime]::UtcNow.AddDays(-$AgeDays)
            $item = Get-Item -LiteralPath $Path -Force
            $item.CreationTimeUtc = $stamp
            $item.LastWriteTimeUtc = $stamp
        }

        function New-AgedFolder {
            param([string]$Path, [int]$AgeDays)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $stamp = [DateTime]::UtcNow.AddDays(-$AgeDays)
            $item = Get-Item -LiteralPath $Path -Force
            $item.CreationTimeUtc = $stamp
            $item.LastWriteTimeUtc = $stamp
        }

        function ConvertFrom-ScriptOutput {
            param([object[]]$Output)
            ($Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine | ConvertFrom-Json
        }
    }

    BeforeEach {
        $cleanupTest.savedEnv = @{}
        foreach ($name in $cleanupTest.envNames) {
            $cleanupTest.savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }

        $cleanupTest.sb = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:windir = Join-Path $cleanupTest.sb 'Windows'
        $env:ProgramData = Join-Path $cleanupTest.sb 'ProgramData'
        $env:PUBLIC = Join-Path (Join-Path $cleanupTest.sb 'Users') 'Public'
        $env:TEMP = Join-Path $cleanupTest.sb 'SystemTemp'
        foreach ($path in @($env:windir, $env:ProgramData, $env:PUBLIC, $env:TEMP)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        $cleanupTest.outside = Join-Path $cleanupTest.sb 'Outside'
        $cleanupTest.outsideFile = Join-Path $cleanupTest.outside 'keep.txt'
        New-AgedFile -Path $cleanupTest.outsideFile -AgeDays 400

        Mock Ninja-Property-Set { $global:LASTEXITCODE = 0 }
    }

    AfterEach {
        foreach ($name in $cleanupTest.envNames) {
            [Environment]::SetEnvironmentVariable($name, $cleanupTest.savedEnv[$name])
        }
    }

    It 'All scripts exist, start with a UTF-8 BOM and have a synopsis / Alle Skripte existieren, haben BOM und Synopsis' {
        foreach ($path in $cleanupTest.scripts.Values) {
            Test-Path -LiteralPath $path | Should -BeTrue
            $bytes = [IO.File]::ReadAllBytes($path)
            $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
            (Get-Help $path -Full).Synopsis | Should -Match 'DE:'
            (Get-Help $path -Full).Synopsis | Should -Match 'EN:'
        }
    }

    Context 'cleanupTempFiles.ps1' {
        BeforeEach {
            $cleanupTest.tempRoot = Join-Path $env:windir 'Temp'
            $cleanupTest.usersRoot = Join-Path $cleanupTest.sb 'Users'
            New-AgedFile -Path (Join-Path $cleanupTest.tempRoot 'old.log') -AgeDays 30
            New-AgedFile -Path (Join-Path $cleanupTest.tempRoot 'young.log') -AgeDays 1
            New-AgedFile -Path (Join-Path (Join-Path $cleanupTest.tempRoot 'sub') 'nested.log') -AgeDays 30
            New-AgedFolder -Path (Join-Path $cleanupTest.tempRoot 'emptyOld') -AgeDays 30
            New-Item -ItemType Directory -Path (Join-Path $cleanupTest.tempRoot 'emptyYoung') -Force | Out-Null
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupTest.tempRoot 'link') -Target $cleanupTest.outside | Out-Null
            $cleanupTest.bobTemp = Join-Path $cleanupTest.usersRoot 'bob/AppData/Local/Temp'
            New-AgedFile -Path (Join-Path $cleanupTest.bobTemp 'user.tmp') -AgeDays 30
            $cleanupTest.publicTemp = Join-Path $cleanupTest.usersRoot 'Public/AppData/Local/Temp'
            New-AgedFile -Path (Join-Path $cleanupTest.publicTemp 'public.tmp') -AgeDays 30
        }

        It 'Audit mode reports old files, deletes nothing and exits 2 / Auditmodus meldet alte Dateien, löscht nichts, Exit 2' {
            Mock Remove-Item {}
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Temp)
            $LASTEXITCODE | Should -Be 2
            $report.Allowed | Should -BeFalse
            $report.EligibleFiles | Should -Be 3
            $report.EmptyFolders | Should -Be 1
            $report.DeletedFiles | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'emptyOld') | Should -BeTrue
        }

        It 'Deletes old files only, keeps young files and does not follow links / Löscht nur alte Dateien, folgt keinen Links' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Temp -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedFiles | Should -Be 3
            $report.Skipped | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path (Join-Path $cleanupTest.tempRoot 'sub') 'nested.log') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobTemp 'user.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'young.log') | Should -BeTrue
            Test-Path -LiteralPath $cleanupTest.outsideFile | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'link') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.publicTemp 'public.tmp') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'emptyOld') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'emptyYoung') | Should -BeTrue
        }

        It 'Keeps empty folders when RemoveEmptyFolders is false / Behält leere Ordner ohne RemoveEmptyFolders' {
            & $cleanupTest.scripts.Temp -Allow 'true' -RemoveEmptyFolders 'false' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'emptyOld') | Should -BeTrue
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            Mock Remove-Item {}
            & $cleanupTest.scripts.Temp -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'emptyOld') | Should -BeTrue
        }

        It 'Skips user profiles when disabled / Überspringt Benutzerprofile, wenn deaktiviert' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Temp -Allow 'true' -IncludeUserProfiles 'false')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedFiles | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobTemp 'user.tmp') | Should -BeTrue
        }

        It 'Locked files are counted as skipped and exit 2 / Gesperrte Dateien werden übersprungen, Exit 2' {
            Mock Remove-Item { throw [System.IO.IOException]::new('locked') } -ParameterFilter { [string]$LiteralPath -like '*old.log' }
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Temp -Allow 'true')
            $LASTEXITCODE | Should -Be 2
            $report.Skipped | Should -Be 1
            $report.DeletedFiles | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeTrue
        }

        It 'Uses the ProfileList registry and skips system SIDs / Nutzt ProfileList und überspringt System-SIDs' {
            $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
            New-AgedFile -Path (Join-Path $cleanupTest.usersRoot 'carol/AppData/Local/Temp/carol.tmp') -AgeDays 30
            Mock Test-Path { $true } -ParameterFilter { [string]$LiteralPath -eq $profileList }
            Mock Get-ChildItem {
                @(
                    [pscustomobject]@{ PSChildName = 'S-1-5-21-1-2-3-1001'; PSPath = "$profileList\S-1-5-21-1-2-3-1001" }
                    [pscustomobject]@{ PSChildName = 'S-1-5-18'; PSPath = "$profileList\S-1-5-18" }
                )
            } -ParameterFilter { [string]$LiteralPath -eq $profileList }
            Mock Get-ItemProperty { [pscustomobject]@{ ProfileImagePath = (Join-Path $cleanupTest.usersRoot 'bob') } } -ParameterFilter { [string]$LiteralPath -like '*S-1-5-21-1-2-3-1001' }
            Mock Get-ItemProperty { [pscustomobject]@{ ProfileImagePath = (Join-Path $cleanupTest.usersRoot 'carol') } } -ParameterFilter { [string]$LiteralPath -like '*S-1-5-18' }
            & $cleanupTest.scripts.Temp -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobTemp 'user.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.usersRoot 'carol/AppData/Local/Temp/carol.tmp') | Should -BeTrue
        }

        It 'Never deletes through a reparse point in the root path / Löscht nie über einen Analysepunkt im Stammpfad' {
            $target = Join-Path $cleanupTest.sb 'Elsewhere'
            New-AgedFile -Path (Join-Path $target 'Local/Temp/victim.tmp') -AgeDays 400
            $carolHome = Join-Path $cleanupTest.usersRoot 'carol'
            New-Item -ItemType Directory -Path $carolHome -Force | Out-Null
            New-Item -ItemType SymbolicLink -Path (Join-Path $carolHome 'AppData') -Target $target | Out-Null
            & $cleanupTest.scripts.Temp -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $target 'Local/Temp/victim.tmp') | Should -BeTrue
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Temp -CustomField 'cleanupReport' | Out-Null
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'cleanupReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ MinimumAgeDays = '0' } }
            @{ Parameters = @{ MinimumAgeDays = '3651' } }
            @{ Parameters = @{ MinimumAgeDays = 'abc' } }
            @{ Parameters = @{ Allow = 'yes' } }
            @{ Parameters = @{ TimeBudgetSeconds = '5' } }
            @{ Parameters = @{ IncludeUserProfiles = 'maybe' } }
            @{ Parameters = @{ CustomField = 'bad-name!' } }
        ) {
            Mock Remove-Item {}
            $parameters = $Parameters.Clone()
            $parameters.Allow = if ($parameters.ContainsKey('Allow')) { $parameters.Allow } else { 'true' }
            & $cleanupTest.scripts.Temp @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Remove-Item -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeTrue
        }

        It 'Reads settings from environment variables / Liest Einstellungen aus Umgebungsvariablen' {
            $env:cleanupTempAllow = 'true'
            $env:cleanupTempMinimumAgeDays = '60'
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Temp)
            $LASTEXITCODE | Should -Be 0
            $report.MinimumAgeDays | Should -Be 60
            $report.DeletedFiles | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.tempRoot 'old.log') | Should -BeTrue
        }
    }

    Context 'cleanupRecycleBin.ps1' {
        BeforeEach {
            $cleanupTest.drive = Join-Path $cleanupTest.sb 'DriveC'
            $cleanupTest.bin = Join-Path (Join-Path $cleanupTest.drive '$Recycle.Bin') 'S-1-5-21-1-2-3-1001'
            New-AgedFile -Path (Join-Path $cleanupTest.bin '$IABC123.txt') -AgeDays 40
            New-AgedFile -Path (Join-Path $cleanupTest.bin '$RABC123.txt') -AgeDays 40
            New-AgedFile -Path (Join-Path $cleanupTest.bin '$IDEF456') -AgeDays 40
            $cleanupTest.folderItem = Join-Path $cleanupTest.bin '$RDEF456'
            New-AgedFile -Path (Join-Path (Join-Path $cleanupTest.folderItem 'inner') 'doc.txt') -AgeDays 40
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupTest.folderItem 'link') -Target $cleanupTest.outside | Out-Null
            New-AgedFile -Path (Join-Path $cleanupTest.bin '$IYNG789.txt') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.bin '$RYNG789.txt') -AgeDays 1
            Mock Get-CimInstance { [pscustomobject]@{ DeviceID = $cleanupTest.drive } } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        }

        It 'Audit mode reports old items and exits 2 / Auditmodus meldet alte Elemente, Exit 2' {
            Mock Remove-Item {}
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Recycle)
            $LASTEXITCODE | Should -Be 2
            $report.EligibleItems | Should -Be 2
            Should -Invoke Remove-Item -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$RABC123.txt') | Should -BeTrue
        }

        It 'Removes old items with their metadata and keeps young items and link targets / Entfernt alte Elemente, behält junge und Linkziele' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Recycle -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedItems | Should -Be 2
            foreach ($name in @('$IABC123.txt', '$RABC123.txt', '$IDEF456', '$RDEF456')) {
                Test-Path -LiteralPath (Join-Path $cleanupTest.bin $name) | Should -BeFalse
            }
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$IYNG789.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$RYNG789.txt') | Should -BeTrue
            Test-Path -LiteralPath $cleanupTest.outsideFile | Should -BeTrue
        }

        It 'MinimumAgeDays 0 removes everything / MinimumAgeDays 0 entfernt alles' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Recycle -Allow 'true' -MinimumAgeDays '0')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedItems | Should -Be 3
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$RYNG789.txt') | Should -BeFalse
            Test-Path -LiteralPath $cleanupTest.outsideFile | Should -BeTrue
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Recycle -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$RABC123.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.folderItem 'inner') | Should -BeTrue
        }

        It 'Failed items lead to exit 2 / Fehlgeschlagene Elemente führen zu Exit 2' {
            Mock Remove-Item { throw [System.IO.IOException]::new('locked') } -ParameterFilter { [string]$LiteralPath -like '*$RABC123.txt' }
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Recycle -Allow 'true')
            $LASTEXITCODE | Should -Be 2
            $report.Failed | Should -Be 1
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$IABC123.txt') | Should -BeTrue
        }

        It 'Nothing old means exit 0 / Nichts Altes bedeutet Exit 0' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Recycle -MinimumAgeDays '365')
            $LASTEXITCODE | Should -Be 0
            $report.EligibleItems | Should -Be 0
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Recycle -CustomField 'binReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'binReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Days = '-1' }
            @{ Days = '3651' }
            @{ Days = 'abc' }
        ) {
            & $cleanupTest.scripts.Recycle -Allow 'true' -MinimumAgeDays $Days | Out-Null
            $LASTEXITCODE | Should -Be 1
            Test-Path -LiteralPath (Join-Path $cleanupTest.bin '$RABC123.txt') | Should -BeTrue
        }

        It 'Drive enumeration errors exit 1 / Fehler bei Laufwerksabfrage führen zu Exit 1' {
            Mock Get-CimInstance { throw 'CIM unavailable' } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
            & $cleanupTest.scripts.Recycle | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'cleanupWindowsErrorReports.ps1' {
        BeforeEach {
            $cleanupTest.werRoot = Join-Path $env:ProgramData 'Microsoft/Windows/WER'
            New-AgedFile -Path (Join-Path $cleanupTest.werRoot 'ReportArchive/Report1/Report.wer') -AgeDays 30
            New-AgedFile -Path (Join-Path $cleanupTest.werRoot 'ReportQueue/Report2/Report.wer') -AgeDays 2
            New-AgedFile -Path (Join-Path $cleanupTest.werRoot 'Temp/old.tmp') -AgeDays 30
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupTest.werRoot 'ReportArchive/link') -Target $cleanupTest.outside | Out-Null
            New-AgedFile -Path (Join-Path $env:windir 'Minidump/010124-01.dmp') -AgeDays 30
            New-AgedFile -Path (Join-Path $env:windir 'MEMORY.DMP') -AgeDays 30
            New-AgedFile -Path (Join-Path $env:windir 'LiveKernelReports/WATCHDOG/wd.dmp') -AgeDays 30
            New-AgedFile -Path (Join-Path $env:windir 'LiveKernelReports/readme.txt') -AgeDays 30
        }

        It 'Audit mode reports old reports only and exits 2 / Auditmodus meldet nur alte Berichte, Exit 2' {
            Mock Remove-Item {}
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Wer)
            $LASTEXITCODE | Should -Be 2
            $report.EligibleFiles | Should -Be 2
            Should -Invoke Remove-Item -Times 0 -Exactly
        }

        It 'Deletes old reports, keeps young ones, dumps and link targets / Löscht alte Berichte, behält junge, Dumps und Linkziele' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Wer -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedFiles | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cleanupTest.werRoot 'ReportArchive/Report1/Report.wer') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.werRoot 'Temp/old.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.werRoot 'ReportQueue/Report2/Report.wer') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $env:windir 'MEMORY.DMP') | Should -BeTrue
            Test-Path -LiteralPath $cleanupTest.outsideFile | Should -BeTrue
        }

        It 'Includes crash dumps when requested / Bezieht Absturzabbilder auf Wunsch ein' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Wer -Allow 'true' -IncludeCrashDumps 'true')
            $LASTEXITCODE | Should -Be 0
            $report.DeletedFiles | Should -Be 5
            Test-Path -LiteralPath (Join-Path $env:windir 'Minidump/010124-01.dmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $env:windir 'MEMORY.DMP') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $env:windir 'LiveKernelReports/WATCHDOG/wd.dmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $env:windir 'LiveKernelReports/readme.txt') | Should -BeTrue
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Wer -Allow 'true' -IncludeCrashDumps 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.werRoot 'Temp/old.tmp') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $env:windir 'MEMORY.DMP') | Should -BeTrue
        }

        It 'Locked files lead to exit 2 / Gesperrte Dateien führen zu Exit 2' {
            Mock Remove-Item { throw [System.IO.IOException]::new('locked') } -ParameterFilter { [string]$LiteralPath -like '*old.tmp' }
            & $cleanupTest.scripts.Wer -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 2
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Wer -CustomField 'werReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'werReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ MinimumAgeDays = '0' } }
            @{ Parameters = @{ MinimumAgeDays = '9999' } }
            @{ Parameters = @{ IncludeCrashDumps = 'sometimes' } }
        ) {
            $parameters = $Parameters.Clone()
            $parameters.Allow = 'true'
            & $cleanupTest.scripts.Wer @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Test-Path -LiteralPath (Join-Path $cleanupTest.werRoot 'Temp/old.tmp') | Should -BeTrue
        }
    }

    Context 'cleanupDeliveryOptimizationCache.ps1' {
        BeforeEach {
            Mock Get-DeliveryOptimizationPerfSnap { [pscustomobject]@{ CacheSizeBytes = 500MB } }
            Mock Get-DOConfig { [pscustomobject]@{ WorkingDirectory = 'C:\DO' } }
            Mock Delete-DeliveryOptimizationCache {}
        }

        It 'Audit mode reports the cache and exits 2 / Auditmodus meldet den Cache, Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Do)
            $LASTEXITCODE | Should -Be 2
            $report.CacheMB | Should -Be 500
            Should -Invoke Delete-DeliveryOptimizationCache -Times 0 -Exactly
        }

        It 'Cache below the threshold exits 0 / Cache unter Schwellwert ergibt Exit 0' {
            & $cleanupTest.scripts.Do -Allow 'true' -MinimumCacheMB '1024' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Delete-DeliveryOptimizationCache -Times 0 -Exactly
        }

        It 'Clears the cache with opt-in / Leert den Cache mit Opt-in' {
            & $cleanupTest.scripts.Do -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Delete-DeliveryOptimizationCache -Times 1 -Exactly -ParameterFilter { $Force }
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Do -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Delete-DeliveryOptimizationCache -Times 0 -Exactly
        }

        It 'Missing delete cmdlet exits 1 / Fehlendes Lösch-Cmdlet ergibt Exit 1' {
            Mock Get-Command { $null } -ParameterFilter { $Name -contains 'Delete-DeliveryOptimizationCache' }
            & $cleanupTest.scripts.Do -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Delete-DeliveryOptimizationCache -Times 0 -Exactly
        }

        It 'Falls back to the cache folder size / Nutzt ersatzweise die Ordnergröße' {
            Mock Get-Command { $null } -ParameterFilter { $Name -contains 'Get-DeliveryOptimizationPerfSnap' -or $Name -contains 'Get-DOConfig' }
            $cache = Join-Path $env:windir 'ServiceProfiles/NetworkService/AppData/Local/Microsoft/Windows/DeliveryOptimization/Cache'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $cache 'piece.bin'), (New-Object byte[] 4096))
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Do)
            $LASTEXITCODE | Should -Be 2
            $report.CacheBytes | Should -Be 4096
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Do -CustomField 'doReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'doReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ MinimumCacheMB = '-1' } }
            @{ Parameters = @{ MinimumCacheMB = '1048577' } }
            @{ Parameters = @{ MinimumCacheMB = 'big' } }
            @{ Parameters = @{ Allow = '1' } }
        ) {
            $parameters = $Parameters.Clone()
            if (-not $parameters.ContainsKey('Allow')) { $parameters.Allow = 'true' }
            & $cleanupTest.scripts.Do @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Delete-DeliveryOptimizationCache -Times 0 -Exactly
        }
    }

    Context 'cleanupComponentStore.ps1' {
        BeforeEach {
            $cleanupTest.analyzeLines = @(
                'Actual Size of Component Store : 8.50 GB',
                'Backups and Disabled Features : 1.20 GB',
                'Date of Last Cleanup : 2024-01-01 10:00:00',
                'Component Store Cleanup Recommended : Yes'
            )
            $cleanupTest.analyzeExit = 0
            $cleanupTest.cleanupExit = 0
            Mock dism { $global:LASTEXITCODE = $cleanupTest.analyzeExit; $cleanupTest.analyzeLines } -ParameterFilter { $Arguments -contains '/AnalyzeComponentStore' }
            Mock dism { $global:LASTEXITCODE = $cleanupTest.cleanupExit; 'The operation completed successfully.' } -ParameterFilter { $Arguments -contains '/StartComponentCleanup' }
        }

        It 'Audit mode with cleanup recommended exits 2 / Auditmodus mit Empfehlung ergibt Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Component)
            $LASTEXITCODE | Should -Be 2
            $report.CleanupRecommended | Should -BeTrue
            Should -Invoke dism -Times 0 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' }
        }

        It 'No recommendation exits 0 and does not clean / Keine Empfehlung ergibt Exit 0 ohne Bereinigung' {
            $cleanupTest.analyzeLines = @('Component Store Cleanup Recommended : No')
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Component -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.CleanupRecommended | Should -BeFalse
            Should -Invoke dism -Times 0 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' }
        }

        It 'Unparsable output reports null / Nicht auswertbare Ausgabe meldet null' {
            $cleanupTest.analyzeLines = @('Bereinigung des Komponentenspeichers empfohlen : Ja')
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Component)
            $LASTEXITCODE | Should -Be 0
            $report.CleanupRecommended | Should -BeNullOrEmpty
        }

        It 'Runs cleanup without ResetBase by default / Bereinigt standardmäßig ohne ResetBase' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Component -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.RebootRequired | Should -BeFalse
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' -and $Arguments -notcontains '/ResetBase' }
        }

        It 'Adds ResetBase when requested / Ergänzt ResetBase auf Wunsch' {
            & $cleanupTest.scripts.Component -Allow 'true' -ResetBase 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' -and $Arguments -contains '/ResetBase' }
        }

        It 'Exit code 3010 sets RebootRequired / Exitcode 3010 setzt RebootRequired' {
            $cleanupTest.cleanupExit = 3010
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Component -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.RebootRequired | Should -BeTrue
        }

        It 'Failed cleanup exits 1 / Fehlgeschlagene Bereinigung ergibt Exit 1' {
            $cleanupTest.cleanupExit = 5
            & $cleanupTest.scripts.Component -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It 'Failed analysis exits 1 / Fehlgeschlagene Analyse ergibt Exit 1' {
            $cleanupTest.analyzeExit = 87
            & $cleanupTest.scripts.Component -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke dism -Times 0 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' }
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Component -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke dism -Times 0 -Exactly -ParameterFilter { $Arguments -contains '/StartComponentCleanup' }
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Component -CustomField 'winsxsReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'winsxsReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ Allow = 'ja' } }
            @{ Parameters = @{ Allow = 'true'; ResetBase = 'perhaps' } }
        ) {
            & $cleanupTest.scripts.Component @Parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke dism -Times 0 -Exactly
        }
    }

    Context 'cleanupBrowserCache.ps1' {
        BeforeEach {
            $cleanupTest.usersRoot = Join-Path $cleanupTest.sb 'Users'
            $cleanupTest.aliceChrome = Join-Path $cleanupTest.usersRoot 'alice/AppData/Local/Google/Chrome/User Data'
            $cleanupTest.aliceEdge = Join-Path $cleanupTest.usersRoot 'alice/AppData/Local/Microsoft/Edge/User Data'
            $cleanupTest.aliceFirefox = Join-Path $cleanupTest.usersRoot 'alice/AppData/Local/Mozilla/Firefox/Profiles/abc.default-release'
            $cleanupTest.bobChrome = Join-Path $cleanupTest.usersRoot 'bob/AppData/Local/Google/Chrome/User Data'

            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Default/Code Cache/js/index') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Default/GPUCache/data_0') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Default/Cookies') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Default/History') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'Profile 1/Cache/Cache_Data/f_000002') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceChrome 'System Profile/Cache/Cache_Data/f_000003') -AgeDays 1
            New-Item -ItemType SymbolicLink -Path (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/link') -Target $cleanupTest.outside | Out-Null
            New-AgedFile -Path (Join-Path $cleanupTest.aliceEdge 'Default/Cache/Cache_Data/f_000004') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceEdge 'Default/Login Data') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceFirefox 'cache2/entries/ABCDEF') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.aliceFirefox 'places.sqlite') -AgeDays 1
            New-AgedFile -Path (Join-Path $cleanupTest.bobChrome 'Default/Cache/Cache_Data/f_000005') -AgeDays 1

            $cleanupTest.processes = @()
            Mock Get-CimInstance {
                $wanted = ([regex]::Match([string]$Filter, "Name='([^']+)'")).Groups[1].Value
                @($cleanupTest.processes | Where-Object { $_.Name -eq $wanted })
            } -ParameterFilter { $ClassName -eq 'Win32_Process' }
            Mock Invoke-CimMethod {
                if ($MethodName -eq 'GetOwner') {
                    if ($InputObject.Owner -eq 'THROW') { throw 'access denied' }
                    return [pscustomobject]@{ ReturnValue = 0; User = $InputObject.Owner; Domain = 'CONTOSO' }
                }
                [pscustomobject]@{ ReturnValue = 2; Sid = $null }
            }
        }

        It 'Audit mode reports caches and deletes nothing / Auditmodus meldet Caches und löscht nichts' {
            Mock Remove-Item {}
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Browser)
            $LASTEXITCODE | Should -Be 2
            $report.EligibleFiles | Should -BeGreaterThan 0
            Should -Invoke Remove-Item -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeTrue
        }

        It 'Clears cache folders only and keeps profile data / Leert nur Cacheordner und behält Profildaten' {
            & $cleanupTest.scripts.Browser -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Code Cache/js/index') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/GPUCache/data_0') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Profile 1/Cache/Cache_Data/f_000002') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceEdge 'Default/Cache/Cache_Data/f_000004') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceFirefox 'cache2/entries/ABCDEF') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobChrome 'Default/Cache/Cache_Data/f_000005') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cookies') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/History') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceEdge 'Default/Login Data') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceFirefox 'places.sqlite') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'System Profile/Cache/Cache_Data/f_000003') | Should -BeTrue
            Test-Path -LiteralPath $cleanupTest.outsideFile | Should -BeTrue
        }

        It 'Skips a browser for the user running it and exits 2 / Überspringt laufenden Browser des Benutzers, Exit 2' {
            $cleanupTest.processes = @([pscustomobject]@{ Name = 'chrome.exe'; ProcessId = 10; Owner = 'bob' })
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Browser -Allow 'true')
            $LASTEXITCODE | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobChrome 'Default/Cache/Cache_Data/f_000005') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeFalse
            @($report.Entries | Where-Object { $_.Status -eq 'SkippedRunning' }).Count | Should -BeGreaterThan 0
        }

        It 'Skips the browser for all users when the owner is unknown / Überspringt Browser für alle bei unbekanntem Besitzer' {
            $cleanupTest.processes = @([pscustomobject]@{ Name = 'msedge.exe'; ProcessId = 11; Owner = 'THROW' })
            & $cleanupTest.scripts.Browser -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceEdge 'Default/Cache/Cache_Data/f_000004') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeFalse
        }

        It 'Cleans running browsers when SkipRunning is false / Bereinigt laufende Browser ohne SkipRunning' {
            $cleanupTest.processes = @([pscustomobject]@{ Name = 'chrome.exe'; ProcessId = 10; Owner = 'bob' })
            & $cleanupTest.scripts.Browser -Allow 'true' -SkipRunning 'false' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.bobChrome 'Default/Cache/Cache_Data/f_000005') | Should -BeFalse
        }

        It 'Restricts cleanup to the selected browsers / Beschränkt die Bereinigung auf ausgewählte Browser' {
            & $cleanupTest.scripts.Browser -Allow 'true' -Browsers 'Edge' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceEdge 'Default/Cache/Cache_Data/f_000004') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceFirefox 'cache2/entries/ABCDEF') | Should -BeTrue
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Browser -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeTrue
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Browser -CustomField 'browserReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'browserReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ Browsers = 'Opera' } }
            @{ Parameters = @{ Browsers = 'Chrome;Edge' } }
            @{ Parameters = @{ SkipRunning = 'no' } }
        ) {
            $parameters = $Parameters.Clone()
            $parameters.Allow = 'true'
            & $cleanupTest.scripts.Browser @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Test-Path -LiteralPath (Join-Path $cleanupTest.aliceChrome 'Default/Cache/Cache_Data/f_000001') | Should -BeTrue
        }
    }

    Context 'removeStaleUserProfiles.ps1' {
        BeforeEach {
            $now = Get-Date
            $cleanupTest.userProfiles = @(
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1001'; LocalPath = 'C:\Users\olduser'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1002'; LocalPath = 'C:\Users\older'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-300) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1003'; LocalPath = 'C:\Users\young'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-10) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1004'; LocalPath = 'C:\Users\loaded'; Loaded = $true; Special = $false; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1005'; LocalPath = 'C:\Users\special'; Loaded = $false; Special = $true; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-18'; LocalPath = 'C:\Windows\system32\config\systemprofile'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-500'; LocalPath = 'C:\Users\Administrator'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1006'; LocalPath = 'C:\Users\unknownage'; Loaded = $false; Special = $false; LastUseTime = $null }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1007'; LocalPath = 'C:\Users\svc_keep'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-200) }
                [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1008'; LocalPath = 'C:\Users\carol'; Loaded = $false; Special = $false; LastUseTime = $now.AddDays(-200) }
            )
            $cleanupTest.recheckLoaded = $false
            Mock Get-CimInstance { [pscustomobject]@{ UserName = 'CONTOSO\carol' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { @() } -ParameterFilter { $ClassName -eq 'Win32_Process' }
            Mock Get-CimInstance {
                if ($Filter) {
                    $match = @($cleanupTest.userProfiles | Where-Object { "SID='$($_.SID)'" -eq $Filter })
                    if ($cleanupTest.recheckLoaded) {
                        return @($match | ForEach-Object { $copy = $_.PSObject.Copy(); $copy.Loaded = $true; $copy })
                    }
                    return $match
                }
                $cleanupTest.userProfiles
            } -ParameterFilter { $ClassName -eq 'Win32_UserProfile' }
            Mock Remove-CimInstance {}
        }

        It 'Audit mode lists stale profiles only and exits 2 / Auditmodus listet nur veraltete Profile, Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Profiles -Exclude 'svc_keep')
            $LASTEXITCODE | Should -Be 2
            $candidates = @($report.Candidates | Where-Object { $_.Status -eq 'Candidate' })
            ($candidates.LocalPath | Sort-Object) | Should -Be @('C:\Users\older', 'C:\Users\olduser')
            Should -Invoke Remove-CimInstance -Times 0 -Exactly
        }

        It 'Removes only eligible profiles and never protected ones / Entfernt nur zulässige, nie geschützte Profile' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep')
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-CimInstance -Times 2 -Exactly
            Should -Invoke Remove-CimInstance -Times 0 -Exactly -ParameterFilter {
                $InputObject.SID -in @('S-1-5-21-1-2-3-1003', 'S-1-5-21-1-2-3-1004', 'S-1-5-21-1-2-3-1005', 'S-1-5-18', 'S-1-5-21-1-2-3-500', 'S-1-5-21-1-2-3-1006', 'S-1-5-21-1-2-3-1007', 'S-1-5-21-1-2-3-1008')
            }
            @($report.Candidates | Where-Object { $_.Status -eq 'Removed' }).Count | Should -Be 2
        }

        It 'Includes profiles without LastUseTime only on request / Bezieht Profile ohne LastUseTime nur auf Wunsch ein' {
            & $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep' -IncludeUnknownAge 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-CimInstance -Times 1 -Exactly -ParameterFilter { $InputObject.SID -eq 'S-1-5-21-1-2-3-1006' }
        }

        It 'Respects MaxRemovals and defers the rest / Beachtet MaxRemovals und stellt den Rest zurück' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep' -MaxRemovals '1')
            Should -Invoke Remove-CimInstance -Times 1 -Exactly
            @($report.Candidates | Where-Object { $_.Status -eq 'Deferred' }).Count | Should -Be 1
            $LASTEXITCODE | Should -Be 0
        }

        It 'Skips profiles loaded at removal time and exits 2 / Überspringt beim Entfernen geladene Profile, Exit 2' {
            $cleanupTest.recheckLoaded = $true
            & $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep' | Out-Null
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Remove-CimInstance -Times 0 -Exactly
        }

        It 'Removal errors lead to exit 2 / Fehler beim Entfernen führen zu Exit 2' {
            Mock Remove-CimInstance { throw 'in use' }
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep')
            $LASTEXITCODE | Should -Be 2
            @($report.Candidates | Where-Object { $_.Status -like 'Failed*' }).Count | Should -Be 2
        }

        It 'Protects logged-on users detected via explorer.exe / Schützt über explorer.exe angemeldete Benutzer' {
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { @([pscustomobject]@{ Name = 'explorer.exe'; ProcessId = 5 }) } -ParameterFilter { $ClassName -eq 'Win32_Process' }
            Mock Invoke-CimMethod {
                if ($MethodName -eq 'GetOwnerSid') { return [pscustomobject]@{ ReturnValue = 0; Sid = 'S-1-5-21-1-2-3-1001' } }
                [pscustomobject]@{ ReturnValue = 0; User = 'carol'; Domain = 'CONTOSO' }
            }
            & $cleanupTest.scripts.Profiles -Allow 'true' -Exclude 'svc_keep' | Out-Null
            Should -Invoke Remove-CimInstance -Times 0 -Exactly -ParameterFilter { $InputObject.SID -in @('S-1-5-21-1-2-3-1001', 'S-1-5-21-1-2-3-1008') }
            Should -Invoke Remove-CimInstance -Times 1 -Exactly -ParameterFilter { $InputObject.SID -eq 'S-1-5-21-1-2-3-1002' }
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Profiles -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-CimInstance -Times 0 -Exactly
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Profiles -CustomField 'profileReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'profileReport' }
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ MinimumAgeDays = '29' } }
            @{ Parameters = @{ MinimumAgeDays = '3651' } }
            @{ Parameters = @{ MaxRemovals = '0' } }
            @{ Parameters = @{ MaxRemovals = '51' } }
            @{ Parameters = @{ Exclude = 'admin*' } }
            @{ Parameters = @{ Exclude = ((1..51 | ForEach-Object { "user$_" }) -join ',') } }
            @{ Parameters = @{ IncludeUnknownAge = 'often' } }
        ) {
            $parameters = $Parameters.Clone()
            $parameters.Allow = 'true'
            & $cleanupTest.scripts.Profiles @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Remove-CimInstance -Times 0 -Exactly
        }
    }

    Context 'uninstallSoftware.ps1' {
        BeforeAll {
            $cleanupTest.root64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            $cleanupTest.root32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            $cleanupTest.regFake = @{}
            $cleanupTest.processPlan = @{ ExitCode = 0; Completed = $true; RemoveKeys = @() }
        }

        BeforeEach {
            $cleanupTest.regFake.Clear()
            $cleanupTest.processPlan.ExitCode = 0
            $cleanupTest.processPlan.Completed = $true
            $cleanupTest.processPlan.RemoveKeys = @()
            $cleanupTest.msiGuid = '{11111111-2222-3333-4444-555555555555}'
            $cleanupTest.msiKey = "$($cleanupTest.root64)\$($cleanupTest.msiGuid)"
            $cleanupTest.regFake[$cleanupTest.msiKey] = @{ DisplayName = 'Contoso Agent'; DisplayVersion = '1.2.3'; Publisher = 'Contoso'; WindowsInstaller = 1; UninstallString = "MsiExec.exe /X$($cleanupTest.msiGuid)" }

            Mock Test-Path {
                $path = [string]$LiteralPath
                if ($path -eq $cleanupTest.root64 -or $path -eq $cleanupTest.root32) { return $true }
                $cleanupTest.regFake.ContainsKey($path)
            } -ParameterFilter { [string]$LiteralPath -like 'HKLM:*' }
            Mock Get-ChildItem {
                $path = [string]$LiteralPath
                foreach ($key in @($cleanupTest.regFake.Keys)) {
                    if ($key.StartsWith("$path\")) { [pscustomobject]@{ PSChildName = $key.Substring($path.Length + 1) } }
                }
            } -ParameterFilter { [string]$LiteralPath -like 'HKLM:*' }
            Mock Get-ItemProperty {
                $path = [string]$LiteralPath
                if (-not $cleanupTest.regFake.ContainsKey($path)) { throw [System.Management.Automation.ItemNotFoundException]::new('not found') }
                [pscustomobject]$cleanupTest.regFake[$path]
            } -ParameterFilter { [string]$LiteralPath -like 'HKLM:*' }
            Mock Start-Process {
                foreach ($key in $cleanupTest.processPlan.RemoveKeys) { $cleanupTest.regFake.Remove($key) }
                $process = [pscustomobject]@{ Handle = [IntPtr]1; ExitCode = $cleanupTest.processPlan.ExitCode; Completed = $cleanupTest.processPlan.Completed }
                $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) $this.Completed }
                $process
            }
        }

        It 'Audit mode lists the match and exits 2 / Auditmodus listet den Treffer, Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent')
            $LASTEXITCODE | Should -Be 2
            $report.Matches.Count | Should -Be 1
            $report.Matches[0].Method | Should -Be 'Msi'
            $report.Matches[0].Version | Should -Be '1.2.3'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'No match exits 0 / Kein Treffer ergibt Exit 0' {
            & $cleanupTest.scripts.Uninstall -Name 'Fabrikam Tool' -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Uninstalls MSI products silently via msiexec /x / Deinstalliert MSI still über msiexec /x' {
            $cleanupTest.processPlan.RemoveKeys = @($cleanupTest.msiKey)
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.Matches[0].Result | Should -Be 'Succeeded'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'msiexec.exe' -and (($ArgumentList -join ' ') -like "/x $($cleanupTest.msiGuid) /qn /norestart /l*v *")
            }
        }

        It 'Exit code 3010 means success with reboot / Exitcode 3010 bedeutet Erfolg mit Neustart' {
            $cleanupTest.processPlan.ExitCode = 3010
            $cleanupTest.processPlan.RemoveKeys = @($cleanupTest.msiKey)
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.RebootRequired | Should -BeTrue
        }

        It 'Exit code 1605 is treated as already removed / Exitcode 1605 gilt als bereits entfernt' {
            $cleanupTest.processPlan.ExitCode = 1605
            $cleanupTest.processPlan.RemoveKeys = @($cleanupTest.msiKey)
            & $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'A failing uninstaller exits 1 / Fehlgeschlagener Uninstaller ergibt Exit 1' {
            $cleanupTest.processPlan.ExitCode = 1603
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true')
            $LASTEXITCODE | Should -Be 1
            $report.Matches[0].Result | Should -Be 'Failed'
        }

        It 'A timeout exits 1 without killing the process / Zeitüberschreitung ergibt Exit 1 ohne Abbruch' {
            Mock Stop-Process {}
            $cleanupTest.processPlan.Completed = $false
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true' -TimeoutMinutes '1')
            $LASTEXITCODE | Should -Be 1
            $report.Matches[0].Result | Should -Be 'Timeout'
            Should -Invoke Stop-Process -Times 0 -Exactly
        }

        It 'Success with a remaining entry exits 2 / Erfolg mit verbleibendem Eintrag ergibt Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true')
            $LASTEXITCODE | Should -Be 2
            $report.Matches[0].Result | Should -Be 'SucceededEntryRemains'
        }

        It 'Too many matches exit 1 without uninstalling / Zu viele Treffer ergeben Exit 1 ohne Deinstallation' {
            $cleanupTest.regFake["$($cleanupTest.root32)\ContosoTools"] = @{ DisplayName = 'Contoso Agent Tools'; QuietUninstallString = 'C:\x\unins.exe /S' }
            & $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -MatchMode 'Contains' -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Exact mode does not match partial names / Exact-Modus trifft keine Teilnamen' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Contoso')
            $LASTEXITCODE | Should -Be 0
            @($report.Matches).Count | Should -Be 0
        }

        It 'Ignores system components and updates / Ignoriert Systemkomponenten und Updates' {
            $cleanupTest.regFake["$($cleanupTest.root64)\SysComp"] = @{ DisplayName = 'Hidden Thing'; SystemComponent = 1; QuietUninstallString = 'C:\x\a.exe /S' }
            $cleanupTest.regFake["$($cleanupTest.root64)\KB123"] = @{ DisplayName = 'Hidden Thing'; ParentKeyName = 'Office'; QuietUninstallString = 'C:\x\a.exe /S' }
            & $cleanupTest.scripts.Uninstall -Name 'Hidden Thing' -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Uses QuietUninstallString for EXE uninstallers / Nutzt QuietUninstallString für EXE-Uninstaller' {
            $exe = Join-Path $cleanupTest.sb 'Apps/Fabrikam/unins000.exe'
            New-AgedFile -Path $exe -AgeDays 1
            $key = "$($cleanupTest.root32)\Fabrikam_is1"
            $cleanupTest.regFake[$key] = @{ DisplayName = 'Fabrikam Editor'; QuietUninstallString = "`"$exe`" /VERYSILENT /NORESTART"; UninstallString = "`"$exe`"" }
            $cleanupTest.processPlan.RemoveKeys = @($key)
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Fabrikam Editor' -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            $report.Matches[0].Method | Should -Be 'QuietUninstallString'
            $report.Matches[0].RegistryView | Should -Be 'Registry32'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $exe -and (($ArgumentList -join ' ') -eq '/VERYSILENT /NORESTART') }
        }

        It 'Uses UninstallString plus ExeArguments for unquoted paths / Nutzt UninstallString plus ExeArguments bei Pfaden ohne Anführungszeichen' {
            $exe = Join-Path $cleanupTest.sb 'Apps/My App/uninst.exe'
            New-AgedFile -Path $exe -AgeDays 1
            $key = "$($cleanupTest.root64)\MyApp"
            $cleanupTest.regFake[$key] = @{ DisplayName = 'My App'; UninstallString = "$exe --mode remove" }
            $cleanupTest.processPlan.RemoveKeys = @($key)
            & $cleanupTest.scripts.Uninstall -Name 'My App' -Allow 'true' -ExeArguments '/S' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $exe -and (($ArgumentList -join ' ') -eq '--mode remove /S') }
        }

        It 'Refuses interactive uninstallers without silent arguments / Verweigert interaktive Uninstaller ohne Silent-Argumente' {
            $exe = Join-Path $cleanupTest.sb 'Apps/Inter/uninst.exe'
            New-AgedFile -Path $exe -AgeDays 1
            $cleanupTest.regFake["$($cleanupTest.root64)\Inter"] = @{ DisplayName = 'Interactive App'; UninstallString = "`"$exe`"" }
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Uninstall -Name 'Interactive App' -Allow 'true')
            $LASTEXITCODE | Should -Be 1
            $report.Matches[0].Result | Should -Be 'NoSilentMethod'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Converts MsiExec /I strings to msiexec /x / Wandelt MsiExec /I in msiexec /x um' {
            $guid = '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
            $key = "$($cleanupTest.root32)\LegacyProduct"
            $cleanupTest.regFake[$key] = @{ DisplayName = 'Legacy Product'; UninstallString = "MsiExec.exe /I$guid" }
            $cleanupTest.processPlan.RemoveKeys = @($key)
            & $cleanupTest.scripts.Uninstall -Name 'Legacy Product' -Allow 'true' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'msiexec.exe' -and (($ArgumentList -join ' ') -like "/x $guid /qn /norestart*") }
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Uninstall -Name 'Contoso Agent' -CustomField 'uninstallReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'uninstallReport' }
        }

        It 'Reads the name from the environment / Liest den Namen aus der Umgebung' {
            $env:uninstallSoftwareName = 'Contoso Agent'
            & $cleanupTest.scripts.Uninstall | Out-Null
            $LASTEXITCODE | Should -Be 2
        }

        It 'Rejects invalid input with exit 1 / Lehnt ungültige Eingaben mit Exit 1 ab' -ForEach @(
            @{ Parameters = @{ Name = '' } }
            @{ Parameters = @{ Name = 'Contoso*' } }
            @{ Parameters = @{ Name = ('x' * 201) } }
            @{ Parameters = @{ Name = "Contoso`tAgent" } }
            @{ Parameters = @{ Name = 'Contoso Agent'; MatchMode = 'Regex' } }
            @{ Parameters = @{ Name = 'Contoso Agent'; MaxMatches = '11' } }
            @{ Parameters = @{ Name = 'Contoso Agent'; MaxMatches = '0' } }
            @{ Parameters = @{ Name = 'Contoso Agent'; ExeArguments = "/S`n/X" } }
            @{ Parameters = @{ Name = 'Contoso Agent'; ExeArguments = ('a' * 501) } }
            @{ Parameters = @{ Name = 'Contoso Agent'; TimeoutMinutes = '0' } }
            @{ Parameters = @{ Name = 'Contoso Agent'; TimeoutMinutes = '241' } }
        ) {
            $parameters = $Parameters.Clone()
            $parameters.Allow = 'true'
            & $cleanupTest.scripts.Uninstall @parameters | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Start-Process -Times 0 -Exactly
        }
    }

    Context 'removeAppxBloatware.ps1' {
        BeforeEach {
            $cleanupTest.installed = @(
                [pscustomobject]@{ Name = 'Microsoft.BingNews'; PackageFullName = 'Microsoft.BingNews_4.0.0.0_x64__8wekyb3d8bbwe'; IsFramework = $false; NonRemovable = $false }
                [pscustomobject]@{ Name = 'Microsoft.ZuneMusic'; PackageFullName = 'Microsoft.ZuneMusic_11.0.0.0_x64__8wekyb3d8bbwe'; IsFramework = $false; NonRemovable = $true }
                [pscustomobject]@{ Name = 'MicrosoftCorporationII.QuickAssist'; PackageFullName = 'MicrosoftCorporationII.QuickAssist_2.0.0.0_x64__8wekyb3d8bbwe'; IsFramework = $false; NonRemovable = $false }
            )
            $cleanupTest.provisioned = @(
                [pscustomobject]@{ DisplayName = 'Microsoft.BingNews'; PackageName = 'Microsoft.BingNews_4.0.0.0_neutral_~_8wekyb3d8bbwe' }
                [pscustomobject]@{ DisplayName = 'MicrosoftCorporationII.QuickAssist'; PackageName = 'MicrosoftCorporationII.QuickAssist_2.0.0.0_neutral_~_8wekyb3d8bbwe' }
            )
            Mock Get-AppxPackage { @($cleanupTest.installed | Where-Object { $_.Name -eq $Name }) }
            Mock Get-AppxProvisionedPackage { $cleanupTest.provisioned }
            Mock Remove-AppxPackage {}
            Mock Remove-AppxProvisionedPackage {}
        }

        It 'Audit mode reports default bloatware and exits 2 / Auditmodus meldet Standard-Bloatware, Exit 2' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Appx)
            $LASTEXITCODE | Should -Be 2
            ($report.Items | Where-Object { $_.Name -eq 'Microsoft.BingNews' }) | Should -Not -BeNullOrEmpty
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
        }

        It 'Removes and deprovisions default bloatware but never QuickAssist / Entfernt Bloatware, aber nie QuickAssist' {
            $report = ConvertFrom-ScriptOutput (& $cleanupTest.scripts.Appx -Allow 'true')
            $LASTEXITCODE | Should -Be 0
            ($report.Items | Where-Object { $_.Name -eq 'Microsoft.ZuneMusic' }).Skipped | Should -Be 1
            Should -Invoke Remove-AppxPackage -Times 1 -Exactly -ParameterFilter { $Package -eq 'Microsoft.BingNews_4.0.0.0_x64__8wekyb3d8bbwe' -and $AllUsers }
            Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter { $PackageName -eq 'Microsoft.BingNews_4.0.0.0_neutral_~_8wekyb3d8bbwe' -and $Online }
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly -ParameterFilter { $Package -like '*QuickAssist*' }
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly -ParameterFilter { $Package -like '*ZuneMusic*' }
        }

        It 'Succeeds with exit 0 when everything is removed / Erfolg mit Exit 0, wenn alles entfernt ist' {
            & $cleanupTest.scripts.Appx -Allow 'true' -Names 'Microsoft.BingNews' | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'Skips deprovisioning when disabled / Überspringt Deprovisionierung, wenn deaktiviert' {
            & $cleanupTest.scripts.Appx -Allow 'true' -Names 'Microsoft.BingNews' -Deprovision 'false' | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
            Should -Invoke Get-AppxProvisionedPackage -Times 0 -Exactly
        }

        It 'Nothing installed exits 0 / Nichts installiert ergibt Exit 0' {
            & $cleanupTest.scripts.Appx -Names 'Microsoft.BingWeather' | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'Partial failures exit 2 / Teilfehler ergeben Exit 2' {
            Mock Remove-AppxPackage { throw 'Deployment failed' }
            & $cleanupTest.scripts.Appx -Allow 'true' -Names 'Microsoft.BingNews' | Out-Null
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly
        }

        It 'WhatIf changes nothing / WhatIf ändert nichts' {
            & $cleanupTest.scripts.Appx -Allow 'true' -WhatIf | Out-Null
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
        }

        It 'Writes the report to the custom field / Schreibt den Bericht ins Custom Field' {
            & $cleanupTest.scripts.Appx -CustomField 'appxReport' | Out-Null
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'appxReport' }
        }

        It 'Refuses protected packages with exit 1 / Verweigert geschützte Pakete mit Exit 1' -ForEach @(
            @{ Names = 'Microsoft.WindowsStore' }
            @{ Names = 'Microsoft.BingNews,microsoft.desktopappinstaller' }
            @{ Names = 'Microsoft.VCLibs.140.00' }
            @{ Names = 'Microsoft.UI.Xaml.2.8' }
            @{ Names = 'Microsoft.SecHealthUI' }
            @{ Names = 'windows.immersivecontrolpanel' }
        ) {
            & $cleanupTest.scripts.Appx -Allow 'true' -Names $Names | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly
            Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
        }

        It 'Rejects invalid names with exit 1 / Lehnt ungültige Namen mit Exit 1 ab' -ForEach @(
            @{ Names = 'Microsoft.*' }
            @{ Names = 'Bad Name' }
            @{ Names = ((1..61 | ForEach-Object { "Contoso.App$_" }) -join ',') }
            @{ Names = 'Microsoft.BingNews;Microsoft.BingWeather' }
        ) {
            & $cleanupTest.scripts.Appx -Allow 'true' -Names $Names | Out-Null
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Remove-AppxPackage -Times 0 -Exactly
        }
    }
}
