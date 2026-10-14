BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root '03 - Software'
    $requiredScript = Join-Path $folder 'checkRequiredSoftware.ps1'
    $versionScript = Join-Path $folder 'checkSoftwareVersion.ps1'
    $startupScript = Join-Path $folder 'readStartupPrograms.ps1'
    $browserScript = Join-Path $folder 'readBrowserVersions.ps1'
    $appxScript = Join-Path $folder 'readAppxProvisionedPackages.ps1'
    $javaScript = Join-Path $folder 'readJavaInstallations.ps1'
    $wingetScript = Join-Path $folder 'checkWingetStatus.ps1'
    $vcScript = Join-Path $folder 'readVcRedistInventory.ps1'
    $featureScript = Join-Path $folder 'checkWindowsOptionalFeatures.ps1'
    $changesScript = Join-Path $folder 'readRecentSoftwareChanges.ps1'
    $engineScript = Join-Path $folder 'readPowerShellEngines.ps1'
    $uninstall64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $uninstall32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    # DE: Gemeinsamer Fake-Zustand (Registry, Dateien, Ordner). EN: Shared fake state (registry, files, folders).
    $softwareFake = @{ Reg = @{}; Files = @{}; Dirs = @{}; Gone = @() }
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-CimInstance { param($ClassName, $Namespace, $Filter) }
    function Get-AppxProvisionedPackage { param([switch]$Online) }
    function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName) }
    function Get-WinEvent { param($FilterHashtable, $MaxEvents) }
    function Ninja-Property-Set { param($Name, $Value) }
    function Add-RegKey {
        param([string]$Path, [hashtable]$Values = @{})
        $softwareFake.Reg[$Path] = $Values
    }
    function Add-FakeFile {
        param([string]$Path, [string]$Version)
        $softwareFake.Files[$Path] = $Version
    }
    function Get-FakeEvent {
        param([int]$Id, [object[]]$Values)
        [pscustomobject]@{ Id = $Id; TimeCreated = (Get-Date).AddHours(-1); Properties = @($Values | ForEach-Object { [pscustomobject]@{ Value = $_ } }) }
    }
}
Describe 'Software catalogue scripts / Software-Katalogskripte' {
    BeforeEach {
        $saved = @{}
        $variables = @(
            'softwareRequiredNames', 'softwareRequiredMatchMode', 'softwareVersionName', 'softwareVersionMinimum',
            'softwareVersionMatchMode', 'softwareVersionMissingIsWarning', 'softwareStartupAllowedNames',
            'softwareStartupMaxRecords', 'softwareStartupIncludeCommands', 'softwareBrowserMinChrome',
            'softwareBrowserMinEdge', 'softwareBrowserMinFirefox', 'softwareBrowserMinBrave', 'softwareAppxUnwantedNames',
            'softwareAppxMaxRecords', 'softwareJavaWarnIfPresent', 'softwareJavaMinimumVersion', 'softwareWingetRequired',
            'softwareWingetMinimumVersion', 'softwareVcRedistWarnUnsupported', 'softwareVcRedistUnsupportedYears',
            'softwareFeaturesMustBeDisabled', 'softwareFeaturesMustBeEnabled', 'softwareChangesDays',
            'softwareChangesMaxEvents', 'softwareChangesWarnOnChange', 'resultCustomField', 'ProgramFiles', 'ProgramFiles(x86)'
        )
        foreach ($name in $variables) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:ProgramFiles = 'C:\Program Files'
        [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', 'C:\Program Files (x86)')
        $softwareFake.Reg.Clear()
        $softwareFake.Files.Clear()
        $softwareFake.Dirs.Clear()
        $softwareFake.Gone = @()
        Mock Test-Path {
            $LiteralPath = [string]($LiteralPath | Select-Object -First 1)
            $prefix = $LiteralPath + '\'
            if ($softwareFake.Reg.ContainsKey($LiteralPath) -or @($softwareFake.Reg.Keys | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return $PathType -ne 'Leaf' }
            if ($softwareFake.Files.ContainsKey($LiteralPath)) { return $PathType -ne 'Container' }
            if ($softwareFake.Dirs.ContainsKey($LiteralPath)) { return $PathType -ne 'Leaf' }
            return $false
        }
        Mock Get-ChildItem {
            $LiteralPath = [string]($LiteralPath | Select-Object -First 1)
            if ($softwareFake.Dirs.ContainsKey($LiteralPath)) {
                foreach ($dirName in @($softwareFake.Dirs[$LiteralPath])) {
                    if (-not $Filter -or $dirName -like $Filter) { [pscustomobject]@{ Name = $dirName; FullName = "$LiteralPath\$dirName"; PSIsContainer = $true } }
                }
                return
            }
            $prefix = $LiteralPath + '\'
            foreach ($path in @(@($softwareFake.Reg.Keys) + @($softwareFake.Gone) | Sort-Object)) {
                if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $path.Substring($prefix.Length) -notmatch '\\') {
                    [pscustomobject]@{ PSPath = $path; PSChildName = $path.Substring($prefix.Length) }
                }
            }
        }
        Mock Get-ItemProperty {
            $LiteralPath = [string]($LiteralPath | Select-Object -First 1)
            if ($softwareFake.Gone -contains $LiteralPath -or -not $softwareFake.Reg.ContainsKey($LiteralPath)) {
                throw [System.Management.Automation.ItemNotFoundException]::new("Cannot find path '$LiteralPath'.")
            }
            [pscustomobject]$softwareFake.Reg[$LiteralPath]
        }
        Mock Get-Item {
            $LiteralPath = [string]($LiteralPath | Select-Object -First 1)
            $parts = @($softwareFake.Files[$LiteralPath].Split('.') | ForEach-Object { [int]$_ })
            [pscustomobject]@{ VersionInfo = [pscustomobject]@{ FileMajorPart = $parts[0]; FileMinorPart = $parts[1]; FileBuildPart = $parts[2]; FilePrivatePart = $parts[3] } }
        }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'checkRequiredSoftware' {
        BeforeEach {
            Add-RegKey "$uninstall64\7zip" @{ DisplayName = '7-Zip 23.01 (x64)'; DisplayVersion = '23.01' }
            Add-RegKey "$uninstall32\Edge" @{ DisplayName = 'Microsoft Edge'; DisplayVersion = '120.0.2210.91' }
            Add-RegKey "$uninstall64\NoName" @{ SystemComponent = 1 }
            $softwareFake.Gone = @("$uninstall64\Vanished")
        }
        It 'Passes when all exact names exist and skips vanished keys / OK bei exakten Namen' {
            $report = & $requiredScript -RequiredNames '7-Zip 23.01 (x64), microsoft edge' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.MissingCount | Should -Be 0
            $report.ScannedEntries | Should -Be 2
        }
        It 'Warns on missing software and writes the field / Warnt bei fehlender Software' {
            $env:softwareRequiredNames = '7-Zip,Sophos'
            $env:softwareRequiredMatchMode = 'Contains'
            $env:resultCustomField = 'requiredSoftware'
            $report = & $requiredScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            ($report.Results | Where-Object RequiredName -eq 'Sophos').Installed | Should -BeFalse
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'requiredSoftware' }
        }
        It 'Exact mode does not match substrings / Exakt-Modus ohne Teilstring' {
            $null = & $requiredScript -RequiredNames '7-Zip'
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('', 'null', '7-Zip*', 'a,,b')) {
                $null = & $requiredScript -RequiredNames $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $requiredScript -RequiredNames '7-Zip' -MatchMode 'Regex'
            $LASTEXITCODE | Should -Be 1
            $null = & $requiredScript -RequiredNames '7-Zip' -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
        }
        It 'Reports field write failures / Meldet Schreibfehler' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $requiredScript -RequiredNames 'Microsoft Edge' -CustomField 'requiredSoftware'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkSoftwareVersion' {
        BeforeEach {
            Add-RegKey "$uninstall64\7zip" @{ DisplayName = '7-Zip 23.01 (x64)'; DisplayVersion = '23.01' }
            Add-RegKey "$uninstall32\Odd" @{ DisplayName = 'Odd Tool'; DisplayVersion = 'unknown' }
        }
        It 'Accepts equal normalized versions / Akzeptiert gleiche Versionen' {
            $report = & $versionScript -SoftwareName '7-Zip' -MatchMode Contains -MinimumVersion '23.1' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Installations[0].NormalizedVersion | Should -Be '23.1.0.0'
        }
        It 'Warns when outdated and writes the field / Warnt bei veralteter Version' {
            $env:softwareVersionName = '7-Zip 23.01 (x64)'
            $env:softwareVersionMinimum = '24.07'
            $env:resultCustomField = 'zipVersion'
            $report = & $versionScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'Outdated'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Missing software is configurable / Fehlende Software konfigurierbar' {
            $null = & $versionScript -SoftwareName 'Not There' -MinimumVersion 1
            $LASTEXITCODE | Should -Be 2
            $report = & $versionScript -SoftwareName 'Not There' -MinimumVersion 1 -MissingIsWarning false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'NotInstalled'
        }
        It 'Treats unparseable versions as finding / Nicht auswertbare Version ist Befund' {
            $null = & $versionScript -SoftwareName 'Odd Tool' -MinimumVersion 1
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($minimum in @('', 'abc', '1.2.3.4.5', '1.-2')) {
                $null = & $versionScript -SoftwareName '7-Zip' -MinimumVersion $minimum
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $versionScript -SoftwareName '7-Zip' -MinimumVersion 1 -MissingIsWarning 'yes'
            $LASTEXITCODE | Should -Be 1
            $null = & $versionScript -SoftwareName '7*' -MinimumVersion 1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readStartupPrograms' {
        BeforeEach {
            Mock Get-CimInstance {
                [pscustomobject]@{ Name = 'SecurityHealth'; Command = '%windir%\system32\SecurityHealthSystray.exe'; Location = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; User = 'Public' }
                [pscustomobject]@{ Name = 'Updater'; Command = '"C:\Program Files\Tool\upd.exe" --token=SECRET'; Location = 'Common Startup'; User = 'Public' }
            } -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' }
            Add-RegKey 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' @{ SecurityHealth = '%windir%\system32\SecurityHealthSystray.exe'; Agent = 'C:\Agent\agent.exe /silent' }
        }
        It 'Inventories and deduplicates without arguments / Inventar ohne Argumente' {
            $raw = & $startupScript
            $LASTEXITCODE | Should -Be 0
            $raw | Out-String | Should -Not -Match 'SECRET'
            $report = $raw | ConvertFrom-Json
            $report.TotalEntries | Should -Be 3
            ($report.Entries | Where-Object Name -eq 'Updater').Executable | Should -Be 'C:\Program Files\Tool\upd.exe'
            ($report.Entries | Where-Object Name -eq 'Agent').Executable | Should -Be 'C:\Agent\agent.exe'
        }
        It 'Includes commands only on opt-in / Befehle nur mit Opt-in' {
            $report = & $startupScript -IncludeCommands true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Entries | Where-Object Name -eq 'Updater').Command | Should -Match 'token'
        }
        It 'Warns about entries outside the allowlist / Warnt bei unbekannten Einträgen' {
            $env:softwareStartupAllowedNames = 'SecurityHealth,Agent'
            $env:resultCustomField = 'startupReport'
            $report = & $startupScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.UnknownEntries | Should -Be 1
            $report.Entries[0].Name | Should -Be 'Updater'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Bounds records / Begrenzt Einträge' {
            $report = & $startupScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Truncated | Should -BeTrue
            @($report.Entries).Count | Should -Be 1
        }
        It 'Rejects invalid input and query errors / Lehnt Fehler ab' {
            foreach ($value in @('0', '201', 'x')) {
                $null = & $startupScript -MaxRecords $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $startupScript -AllowedNames 'A*'
            $LASTEXITCODE | Should -Be 1
            Mock Get-CimInstance { throw 'CIM failure' } -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' }
            $null = & $startupScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readBrowserVersions' {
        BeforeEach {
            Add-FakeFile 'C:\Program Files\Google\Chrome\Application\chrome.exe' '120.0.6099.71'
            Add-FakeFile 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' '121.0.2277.83'
            Add-RegKey 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe' @{ '(default)' = '\\server\share\firefox.exe' }
            Add-RegKey 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\brave.exe' @{ '(default)' = '"D:\Apps\Brave\brave.exe"' }
            Add-FakeFile 'D:\Apps\Brave\brave.exe' '120.1.61.104'
            Add-FakeFile '\\server\share\firefox.exe' '115.0.0.0'
        }
        It 'Reads versions from paths and App Paths / Liest Versionen' {
            $report = & $browserScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Browsers | Where-Object Browser -eq 'Chrome').Installations[0].FileVersion | Should -Be '120.0.6099.71'
            ($report.Browsers | Where-Object Browser -eq 'Edge').Installed | Should -BeTrue
            ($report.Browsers | Where-Object Browser -eq 'Brave').Installations[0].Source | Should -Be 'AppPaths'
            ($report.Browsers | Where-Object Browser -eq 'Firefox').Installed | Should -BeFalse
        }
        It 'Warns below browser minimum and writes field / Warnt unter Mindestversion' {
            $env:softwareBrowserMinChrome = '121'
            $env:softwareBrowserMinFirefox = '200'
            $env:resultCustomField = 'browserVersions'
            $null = & $browserScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Accepts satisfied minimums / Akzeptiert erfüllte Mindestversionen' {
            $null = & $browserScript -MinChrome '120.0.6099.71' -MinEdge '121'
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid minimums / Lehnt ungültige Mindestversion ab' {
            $null = & $browserScript -MinEdge 'latest'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readAppxProvisionedPackages' {
        BeforeEach {
            Mock Get-AppxProvisionedPackage {
                [pscustomobject]@{ DisplayName = 'Microsoft.WindowsCalculator'; Version = '11.2307.4.0' }
                [pscustomobject]@{ DisplayName = 'Microsoft.BingNews'; Version = '4.55.62231.0' }
            }
        }
        It 'Inventories packages / Inventarisiert Pakete' {
            $report = & $appxScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalPackages | Should -Be 2
        }
        It 'Warns on unwanted packages and writes field / Warnt bei unerwünschten Paketen' {
            $env:softwareAppxUnwantedNames = 'microsoft.bingnews,Microsoft.XboxApp'
            $env:resultCustomField = 'appxReport'
            $report = & $appxScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.UnwantedFound) | Should -Be @('Microsoft.BingNews')
            $report.Packages[0].DisplayName | Should -Be 'Microsoft.BingNews'
            $report.Truncated | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $appxScript -UnwantedNames 'Microsoft.*'
            $LASTEXITCODE | Should -Be 1
            $null = & $appxScript -MaxRecords '0'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readJavaInstallations' {
        BeforeEach {
            Add-RegKey "$uninstall64\Oracle8" @{ DisplayName = 'Java 8 Update 391 (64-bit)'; DisplayVersion = '8.0.3910.13'; Publisher = 'Oracle Corporation' }
            Add-RegKey "$uninstall64\Temurin" @{ DisplayName = 'Eclipse Temurin JDK with Hotspot 17.0.9+9 (x64)'; DisplayVersion = '17.0.9.9'; Publisher = 'Eclipse Adoptium'; InstallLocation = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.9.9-hotspot\' }
            Add-RegKey "$uninstall32\Updater" @{ DisplayName = 'Java Auto Updater'; DisplayVersion = '2.8.391.13'; Publisher = 'Oracle Corporation' }
            Add-RegKey "$uninstall32\Script" @{ DisplayName = 'JavaScript Tools'; DisplayVersion = '1.0' }
            Add-RegKey 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment' @{ CurrentVersion = '1.8' }
            Add-RegKey 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\1.8' @{ JavaHome = 'C:\Program Files\Java\jre-1.8' }
            Add-RegKey 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_391' @{ JavaHome = 'C:\Program Files\Java\jre-1.8' }
        }
        It 'Inventories vendors and normalizes versions / Inventar mit Normalisierung' {
            $report = & $javaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEntries | Should -Be 3
            ($report.Installations | Where-Object Source -eq 'JavaSoft').NormalizedVersion | Should -Be '8.0.391.0'
            ($report.Installations | Where-Object Name -like 'Java 8*').NormalizedVersion | Should -Be '8.0.391.0'
            ($report.Installations | Where-Object Name -like 'Eclipse*').Vendor | Should -Be 'Eclipse Adoptium'
            ($report.Installations | Where-Object Source -eq 'JavaSoft').Vendor | Should -Be 'Oracle'
        }
        It 'Warns below minimum and writes field / Warnt unter Mindestversion' {
            $env:softwareJavaMinimumVersion = '8.0.401'
            $env:resultCustomField = 'javaReport'
            $report = & $javaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.BelowMinimumCount | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when any Java is present on request / Warnt bei vorhandenem Java' {
            $null = & $javaScript -WarnIfPresent true
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $javaScript -MinimumVersion '1.8.0_391'
            $LASTEXITCODE | Should -Be 1
            $null = & $javaScript -WarnIfPresent 'maybe'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkWingetStatus' {
        BeforeEach {
            $softwareFake.Dirs['C:\Program Files\WindowsApps'] = @(
                'Microsoft.DesktopAppInstaller_1.21.3482.0_x64__8wekyb3d8bbwe',
                'Microsoft.DesktopAppInstaller_1.22.10582.0_x64__8wekyb3d8bbwe',
                'Microsoft.DesktopAppInstaller_1.23.1.0_x64__8wekyb3d8bbwe',
                'Microsoft.Other_1.0.0.0_x64__8wekyb3d8bbwe'
            )
            Add-FakeFile 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.21.3482.0_x64__8wekyb3d8bbwe\winget.exe' '1.21.3482.0'
            Add-FakeFile 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.22.10582.0_x64__8wekyb3d8bbwe\winget.exe' '1.22.10582.0'
        }
        It 'Selects the highest version containing winget.exe / Wählt höchste Version mit winget.exe' {
            $report = & $wingetScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'Ready'
            $report.SelectedPackageVersion | Should -Be '1.22.10582.0'
            $report.WingetFileVersion | Should -Be '1.22.10582.0'
            $report.PackageCount | Should -Be 3
        }
        It 'Warns when missing and required / Warnt wenn erforderlich und fehlend' {
            $softwareFake.Dirs['C:\Program Files\WindowsApps'] = @()
            $env:resultCustomField = 'wingetStatus'
            $report = & $wingetScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'NotFound'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
            $null = & $wingetScript -Required false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Warns below minimum version / Warnt unter Mindestversion' {
            $null = & $wingetScript -MinimumVersion '1.23'
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $wingetScript -Required 'ja'
            $LASTEXITCODE | Should -Be 1
            $null = & $wingetScript -MinimumVersion 'v1'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readVcRedistInventory' {
        BeforeEach {
            Add-RegKey "$uninstall32\Bundle" @{ DisplayName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.38.33130'; DisplayVersion = '14.38.33130.0' }
            Add-RegKey "$uninstall64\MinRuntime" @{ DisplayName = 'Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.38.33130'; DisplayVersion = '14.38.33130' }
        }
        It 'Passes with supported redistributables only / OK nur mit unterstützten Paketen' {
            $report = & $vcScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEntries | Should -Be 1
            $report.Redistributables[0].Year | Should -Be '2015-2022'
            $report.Redistributables[0].Architecture | Should -Be 'x64'
        }
        It 'Warns about out-of-support versions and writes field / Warnt bei veralteten Paketen' {
            Add-RegKey "$uninstall32\Old" @{ DisplayName = 'Microsoft Visual C++ 2010  x86 Redistributable - 10.0.40219'; DisplayVersion = '10.0.40219' }
            $env:resultCustomField = 'vcRedist'
            $report = & $vcScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.UnsupportedCount | Should -Be 1
            $report.Redistributables[0].Year | Should -Be '2010'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
            $null = & $vcScript -WarnUnsupported false
            $LASTEXITCODE | Should -Be 0
            $null = & $vcScript -UnsupportedYears '2005,2008'
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('1999', '2010,abc', '2010;2012')) {
                $null = & $vcScript -UnsupportedYears $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $vcScript -WarnUnsupported 'nein'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkWindowsOptionalFeatures' {
        BeforeEach {
            Mock Get-WindowsOptionalFeature {
                [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Disabled' }
                [pscustomobject]@{ FeatureName = 'MicrosoftWindowsPowerShellV2Root'; State = 'DisabledWithPayloadRemoved' }
                [pscustomobject]@{ FeatureName = 'TelnetClient'; State = 'Disabled' }
                [pscustomobject]@{ FeatureName = 'NetFx4-AdvSrvs'; State = 'Enabled' }
            }
        }
        It 'Passes with default list and reports unknown names as NotPresent / OK mit Standardliste' {
            $report = & $featureScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Results | Where-Object Feature -eq 'TFTP').State | Should -Be 'NotPresent'
        }
        It 'Warns on enabled insecure feature and writes field / Warnt bei aktiviertem Feature' {
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Enabled' } }
            $env:resultCustomField = 'featureCompliance'
            $report = & $featureScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Violations | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Checks required enabled features / Prüft geforderte aktivierte Features' {
            $null = & $featureScript -MustBeEnabled 'NetFx4-AdvSrvs'
            $LASTEXITCODE | Should -Be 0
            $env:softwareFeaturesMustBeEnabled = 'NetFx4-AdvSrvs,Missing-Feature'
            $null = & $featureScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid or overlapping input / Lehnt ungültige Listen ab' {
            $null = & $featureScript -MustBeDisabled 'SMB1*'
            $LASTEXITCODE | Should -Be 1
            $null = & $featureScript -MustBeDisabled 'TFTP' -MustBeEnabled 'tftp'
            $LASTEXITCODE | Should -Be 1
            Mock Get-WindowsOptionalFeature { throw 'DISM failure' }
            $null = & $featureScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readRecentSoftwareChanges' {
        BeforeEach {
            Mock Get-WinEvent {
                Get-FakeEvent 11707 @('Product: Contoso Agent -- Installation completed successfully.', '(NULL)')
                Get-FakeEvent 1033 @('Contoso Agent', '5.1.0', '1033', '0', 'Contoso Ltd.')
                Get-FakeEvent 11724 @('Produkt: Old Tool -- Entfernung erfolgreich abgeschlossen.')
            }
        }
        It 'Reports changes informationally / Meldet Änderungen informativ' {
            $report = & $changesScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 3
            $report.Changes[0].Product | Should -Be 'Contoso Agent'
            $report.Changes[1].Manufacturer | Should -Be 'Contoso Ltd.'
            $report.Changes[2].Product | Should -Be 'Old Tool'
            $report.Changes[2].Action | Should -Be 'Uninstall'
            Should -Invoke Get-WinEvent -Times 1 -Exactly -ParameterFilter { $MaxEvents -eq 100 -and $FilterHashtable.StartTime -is [datetime] }
        }
        It 'Warns on change when requested and writes field / Warnt bei Änderung auf Wunsch' {
            $env:softwareChangesWarnOnChange = 'true'
            $env:resultCustomField = 'softwareChanges'
            $null = & $changesScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Treats no events as success / Keine Ereignisse sind kein Fehler' {
            Mock Get-WinEvent {
                $record = New-Object System.Management.Automation.ErrorRecord (New-Object Exception 'No events were found'), 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', ([System.Management.Automation.ErrorCategory]::ObjectNotFound), $null
                throw $record
            }
            $report = & $changesScript -WarnOnChange true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 0
        }
        It 'Reports query errors and invalid input / Meldet Fehler' {
            Mock Get-WinEvent { throw 'Access denied' }
            $null = & $changesScript
            $LASTEXITCODE | Should -Be 1
            foreach ($value in @('0', '91', 'x')) {
                $null = & $changesScript -Days $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $changesScript -MaxEvents 501
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readPowerShellEngines' {
        BeforeEach {
            Add-RegKey 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine' @{ PowerShellVersion = '2.0' }
            Add-RegKey 'HKLM:\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine' @{ PowerShellVersion = '5.1.19041.1' }
            Add-RegKey 'HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\{31ab5147-9a97-4452-8443-d9709f0516e1}' @{ SemanticVersion = '7.4.1'; InstallLocation = 'C:\Program Files\PowerShell\7\' }
            $softwareFake.Dirs['C:\Program Files\PowerShell'] = @('7')
            Add-FakeFile 'C:\Program Files\PowerShell\7\pwsh.exe' '7.4.1.500'
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = $FeatureName; State = 'Disabled' } }
        }
        It 'Reports engines without PowerShell 2.0 enabled / Meldet Engines ohne PS 2.0' {
            $report = & $engineScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.PowerShell2.Enabled | Should -BeFalse
            $report.WindowsPowerShell.RegistryVersion | Should -Be '5.1.19041.1'
            $report.PowerShell7.Count | Should -Be 1
            $report.PowerShell7.Installations[0].Source | Should -Be 'Registry+File'
            $report.PowerShell7.Installations[0].FileVersion | Should -Be '7.4.1.500'
        }
        It 'Warns when PowerShell 2.0 is enabled and writes field / Warnt bei aktivem PS 2.0' {
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = $FeatureName; State = 'Enabled' } }
            $env:resultCustomField = 'powerShellEngines'
            $null = & $engineScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Falls back to the registry when features are not queryable / Registry-Fallback' {
            Mock Get-WindowsOptionalFeature { throw 'Feature unknown' }
            $report = & $engineScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.PowerShell2.FeatureStates.MicrosoftWindowsPowerShellV2Root | Should -Be 'Unknown'
            $softwareFake.Reg.Remove('HKLM:\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine')
            $null = & $engineScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid field names / Lehnt ungültige Feldnamen ab' {
            $null = & $engineScript -CustomField '1field'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
