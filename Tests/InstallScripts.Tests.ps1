BeforeDiscovery {
    $installScriptCases = @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Installations-Scripte') -Filter '*.ps1' |
        ForEach-Object { @{ Script = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root 'Installations-Scripte'
    $sevenZipScript = Join-Path $folder 'install7Zip.ps1'
    $puttyScript = Join-Path $folder 'installPuTTY.ps1'
    $uninstall64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $uninstall32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    $appsRoot = 'C:\Program Files\WindowsApps'
    $wingetDir = 'Microsoft.DesktopAppInstaller_1.25.340.0_x64__8wekyb3d8bbwe'
    $wingetExe = '{0}\{1}\winget.exe' -f $appsRoot, $wingetDir
    # DE: Gemeinsamer Fake-Zustand. EN: Shared fake state.
    $installFake = @{ Reg = @{}; Files = @{}; Process = $null; OnInstall = $null }
    # DE: Windows-/NinjaOne-Aufrufe isolieren. EN: Isolate Windows/NinjaOne calls.
    function icacls { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }
    function Add-UninstallEntry {
        param([string]$Root, [string]$Key, [string]$DisplayName, [string]$Version = '1.0')
        $installFake.Reg[('{0}\{1}' -f $Root, $Key)] = @{ DisplayName = $DisplayName; DisplayVersion = $Version; Publisher = 'Vendor' }
    }
    function New-FakeProcess {
        param([int]$ExitCode = 0, [bool]$Finished = $true)
        $process = [pscustomobject]@{ ExitCode = $ExitCode; Handle = [IntPtr]::Zero; Finished = $Finished }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) $this.Finished }
        $process
    }
    # DE: Beispiel-Anzeigenamen je Skript für die Erkennungsmuster. EN: Sample display names per script for detection patterns.
    $sampleDisplayNames = @{
        'install7Zip.ps1'                   = @('7-Zip 26.04 (x64)', '7-Zip 24.09')
        'installAdobeAcrobatReader.ps1'     = @('Adobe Acrobat (64-bit)', 'Adobe Acrobat Reader DC MUI')
        'installAnyDesk.ps1'                = @('AnyDesk')
        'installCitrixWorkspace.ps1'        = @('Citrix Workspace 2409')
        'installDotNetDesktopRuntime10.ps1' = @('Microsoft Windows Desktop Runtime - 10.0.5 (x64)')
        'installGit.ps1'                    = @('Git', 'Git version 2.40.0')
        'installGoogleChrome.ps1'           = @('Google Chrome')
        'installGreenshot.ps1'              = @('Greenshot 1.3.290')
        'installKeePassXC.ps1'              = @('KeePassXC')
        'installLibreOffice.ps1'            = @('LibreOffice 25.8.2.2')
        'installMozillaFirefox.ps1'         = @('Mozilla Firefox (x64 de)')
        'installMozillaThunderbird.ps1'     = @('Mozilla Thunderbird (x64 de)')
        'installNotepadPlusPlus.ps1'        = @('Notepad++ (64-bit x64)')
        'installPdf24Creator.ps1'           = @('PDF24 Creator')
        'installPowerShell7.ps1'            = @('PowerShell 7-x64')
        'installPuTTY.ps1'                  = @('PuTTY release 0.83 (64-bit)')
        'installTeamViewer.ps1'             = @('TeamViewer', 'TeamViewer 15')
        'installTemurinJre21.ps1'           = @('Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTreeSizeFree.ps1'           = @('TreeSize Free V4.7.3')
        'installVcRedistX64.ps1'            = @('Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.40.33810', 'Microsoft Visual C++ v14 Redistributable (x64) - 14.50.35719')
        'installVisualStudioCode.ps1'       = @('Microsoft Visual Studio Code')
        'installVlcMediaPlayer.ps1'         = @('VLC media player')
        'installWinSCP.ps1'                 = @('WinSCP 6.5.3')
        'installWireGuard.ps1'              = @('WireGuard')
        'installZoomWorkplace.ps1'          = @('Zoom Workplace (64-bit)', 'Zoom(64bit)')
    }
    # DE: Ähnliche Fremdprodukte dürfen nicht erkannt werden. EN: Similar foreign products must not be detected.
    $negativeDisplayNames = @{
        'installGoogleChrome.ps1'        = @('Google Chrome Beta', 'Google Update Helper')
        'installVcRedistX64.ps1'         = @('Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.40.33810', 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664')
        'installDotNetDesktopRuntime10.ps1' = @('Microsoft Windows Desktop Runtime - 8.0.11 (x64)')
        'installTemurinJre21.ps1'        = @('Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64)')
        'installVisualStudioCode.ps1'    = @('Microsoft Visual Studio Code Insiders')
        'installZoomWorkplace.ps1'       = @('Zoom Outlook Plugin')
        'installGit.ps1'                 = @('GitHub Desktop')
        'installTeamViewer.ps1'          = @('TeamViewer Meeting Add-In')
    }
}

Describe 'Installation scripts / Installations-Skripte' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('installAllow', 'installSource', 'installerPath', 'installerSha256', 'installerArguments',
                'installUpgrade', 'installTimeoutMinutes', 'resultCustomField', 'ProgramFiles')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:ProgramFiles = 'C:\Program Files'
        $installFake.Reg.Clear()
        $installFake.Files.Clear()
        $installFake.Files[$wingetExe] = $true
        $installFake.Process = New-FakeProcess
        $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key '7-Zip' -DisplayName '7-Zip 26.04 (x64)' -Version '26.04' }
        Mock Test-Path {
            $path = [string]($LiteralPath | Select-Object -First 1)
            if ($path -eq $uninstall64 -or $path -eq $uninstall32) { return $true }
            if ($path -eq $appsRoot) { return $PathType -ne 'Leaf' }
            if ($installFake.Files.ContainsKey($path)) { return $PathType -ne 'Container' }
            if ($path -like '*PhinIT-Install-*') { return $true }
            return $false
        }
        Mock Get-ChildItem {
            $path = [string]($LiteralPath | Select-Object -First 1)
            if ($path -eq $appsRoot) {
                return [pscustomobject]@{ Name = $wingetDir; PSIsContainer = $true }
            }
            $prefix = $path + '\'
            foreach ($key in @($installFake.Reg.Keys | Sort-Object)) {
                if ($key.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { [pscustomobject]@{ PSPath = $key } }
            }
        }
        Mock Get-ItemProperty { [pscustomobject]$installFake.Reg[[string]$LiteralPath] }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock Start-Process { if ($installFake.OnInstall) { & $installFake.OnInstall }; $installFake.Process }
        Mock New-Item { [pscustomobject]@{ FullName = $Path } }
        Mock icacls { $global:LASTEXITCODE = 0 }
        Mock Copy-Item {}
        Mock Remove-Item {}
        Mock Get-FileHash { [pscustomobject]@{ Hash = ('ab' * 32) } }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'All installation scripts / Alle Installationsskripte' {
        It '<Script> has UTF-8 BOM and parsable help / hat BOM und lesbare Hilfe' -TestCases $installScriptCases {
            param($Script, $Path)
            $bytes = [IO.File]::ReadAllBytes($Path)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            (Get-Help $Path).Synopsis | Should -Match 'DE: Installiert'
            $tokens = $null; $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0
        }
        It '<Script> only audits by default / prüft standardmäßig nur' -TestCases $installScriptCases {
            param($Script, $Path)
            $report = & $Path | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Mode | Should -Be 'Audit'
            $report.Action | Should -Be 'NotInstalled'
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It '<Script> detects its product and ignores similar ones / erkennt sein Produkt' -TestCases $installScriptCases {
            param($Script, $Path)
            $sampleDisplayNames.ContainsKey($Script) | Should -BeTrue -Because 'every script needs sample display names'
            $index = 0
            foreach ($negative in @($negativeDisplayNames[$Script])) {
                if ($negative) { Add-UninstallEntry -Root $uninstall32 -Key ('Other{0}' -f $index++) -DisplayName $negative }
            }
            $null = & $Path
            $LASTEXITCODE | Should -Be 2
            foreach ($displayName in $sampleDisplayNames[$Script]) {
                $installFake.Reg.Clear()
                Add-UninstallEntry -Root $uninstall64 -Key 'Product' -DisplayName $displayName
                $report = & $Path | ConvertFrom-Json
                $LASTEXITCODE | Should -Be 0 -Because $displayName
                $report.Action | Should -Be 'AlreadyInstalled'
                $report.InstalledBefore[0].Name | Should -Be $displayName
            }
        }
        It '<Script> installs via winget with machine scope / installiert per winget' -TestCases $installScriptCases {
            param($Script, $Path)
            $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key 'Product' -DisplayName ($sampleDisplayNames[$Script][0]) }
            $report = & $Path -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Action | Should -Be 'Installed'
            $report.WingetPath | Should -Be $wingetExe
            $id = [regex]::Escape($report.WingetId)
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $wingetExe -and $ArgumentList -match "^install --id $id --exact --source winget --silent " -and
                $ArgumentList -match '--accept-package-agreements' -and $ArgumentList -match '--disable-interactivity' -and $ArgumentList -match '--scope machine$'
            }
        }
        It 'All scripts share the identical engine / Alle Skripte nutzen dieselbe Logik' {
            # DE: Änderungen an der Logik müssen in allen Skripten gleich erfolgen. EN: Engine changes must be applied to all scripts alike.
            $files = @([IO.Directory]::GetFiles($folder, '*.ps1'))
            $files.Count | Should -BeGreaterOrEqual 20
            $engines = @($files | ForEach-Object {
                    $text = [IO.File]::ReadAllText($_)
                    $text.Substring($text.IndexOf('function Resolve-Setting'))
                } | Sort-Object -Unique)
            $engines.Count | Should -Be 1
        }
    }

    Context 'Installation engine / Installationslogik' {
        It 'Does nothing when already installed / Macht nichts bei vorhandener Installation' {
            Add-UninstallEntry -Root $uninstall32 -Key '7-Zip' -DisplayName '7-Zip 24.09' -Version '24.09'
            $report = & $sevenZipScript -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Action | Should -Be 'AlreadyInstalled'
            $report.InstalledBefore[0].RegistryView | Should -Be 'Registry32'
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Upgrades with installUpgrade / Aktualisiert mit installUpgrade' {
            Add-UninstallEntry -Root $uninstall64 -Key '7-Zip' -DisplayName '7-Zip 24.09' -Version '24.09'
            $env:installAllow = 'TRUE'
            $env:installUpgrade = 'true'
            $report = & $sevenZipScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Mode | Should -Be 'Upgrade'
            $report.Action | Should -Be 'Upgraded'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -like 'upgrade --id 7zip.7zip --exact*' }
        }
        It 'Simulates with -WhatIf / Simuliert mit -WhatIf' {
            $report = & $sevenZipScript -AllowInstall true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Action | Should -Be 'WhatIf'
            $report.WhatIf | Should -BeTrue
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Fails without winget / Fehler ohne winget' {
            $installFake.Files.Clear()
            $null = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Accepts winget reboot and no-update codes / Akzeptiert Neustart- und Kein-Update-Codes' {
            $installFake.Process = New-FakeProcess -ExitCode -1978334967
            $report = & $sevenZipScript -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RebootRequired | Should -BeTrue
            $installFake.Reg.Clear()
            $installFake.Process = New-FakeProcess -ExitCode -1978335189
            $report = & $sevenZipScript -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RebootRequired | Should -BeFalse
        }
        It 'Fails on installer errors / Fehler bei Installerfehlern' {
            $installFake.Process = New-FakeProcess -ExitCode -1978335224
            $output = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match '0x8A150008'
        }
        It 'Fails when the product is not detected afterwards / Fehler ohne Erkennung danach' {
            $installFake.OnInstall = $null
            $null = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
        }
        It 'Fails on timeout / Fehler bei Zeitüberschreitung' {
            $installFake.Process = New-FakeProcess -Finished $false
            $output = & $sevenZipScript -AllowInstall true -TimeoutMinutes 1
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'Timeout'
        }
        It 'Installs an MSI from a share with hash check / Installiert MSI von Freigabe mit Hashprüfung' {
            $installFake.Files['\\srv\share\7z-x64.msi'] = $true
            $report = & $sevenZipScript -AllowInstall true -Source file -InstallerPath '\\srv\share\7z-x64.msi' -InstallerSha256 ('AB' * 32) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'File'
            $report.InstallerSha256 | Should -Be ('AB' * 32)
            Should -Invoke icacls -Times 1 -Exactly
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq '\\srv\share\7z-x64.msi' -and $Destination -like '*PhinIT-Install-*installer.msi' }
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'msiexec.exe' -and $ArgumentList -match '^/i ".*PhinIT-Install-.*installer\.msi" /qn /norestart /l\*v ".*install7Zip-.*\.log"$'
            }
            Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*PhinIT-Install-*' -and $Recurse }
        }
        It 'Uses default and custom EXE switches / Nutzt Standard- und eigene EXE-Schalter' {
            $installFake.Files['C:\Install\7z-x64.exe'] = $true
            $null = & $sevenZipScript -AllowInstall true -Source File -InstallerPath 'C:\Install\7z-x64.exe'
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -like '*installer.exe' -and $ArgumentList -eq '/S' }
            $installFake.Reg.Clear()
            $null = & $sevenZipScript -AllowInstall true -Source File -InstallerPath 'C:\Install\7z-x64.exe' -InstallerArguments '/S /D=C:\Tools\7-Zip'
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '/S /D=C:\Tools\7-Zip' }
        }
        It 'Refuses a hash mismatch / Verweigert abweichenden Hash' {
            $installFake.Files['C:\Install\7z-x64.msi'] = $true
            $output = & $sevenZipScript -AllowInstall true -Source File -InstallerPath 'C:\Install\7z-x64.msi' -InstallerSha256 ('cd' * 32)
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'SHA256'
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 1 -Exactly
        }
        It 'Fails when icacls fails / Fehler wenn icacls scheitert' {
            $installFake.Files['C:\Install\7z-x64.msi'] = $true
            Mock icacls { $global:LASTEXITCODE = 5 }
            $null = & $sevenZipScript -AllowInstall true -Source File -InstallerPath 'C:\Install\7z-x64.msi'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Copy-Item -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Requires installer arguments for EXE without known switches / Verlangt Argumente für EXE ohne Schalter' {
            $installFake.Files['C:\Install\putty.exe'] = $true
            $null = & $puttyScript -AllowInstall true -Source File -InstallerPath 'C:\Install\putty.exe'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Fails for a missing installer file / Fehler bei fehlender Datei' {
            $null = & $sevenZipScript -AllowInstall true -Source File -InstallerPath 'C:\Install\missing.msi'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Copy-Item -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $cases = @(
                @{ AllowInstall = 'yes' },
                @{ Source = 'Chocolatey' },
                @{ TimeoutMinutes = '0' },
                @{ TimeoutMinutes = '241' },
                @{ Upgrade = 'maybe' },
                @{ CustomField = '1field' },
                @{ InstallerPath = 'C:\Install\7z.msi' },
                @{ Source = 'File' },
                @{ Source = 'File'; InstallerPath = 'Install\7z.msi' },
                @{ Source = 'File'; InstallerPath = 'C:\Install\*.msi' },
                @{ Source = 'File'; InstallerPath = 'C:\Install\..\7z.msi' },
                @{ Source = 'File'; InstallerPath = 'C:\Install\7z.zip' },
                @{ Source = 'File'; InstallerPath = 'C:\Install\7z.msi'; InstallerSha256 = 'abc' },
                @{ Source = 'File'; InstallerPath = 'C:\Install\7z.msi'; InstallerArguments = "/qn`r`nfoo" }
            )
            foreach ($case in $cases) {
                $null = & $sevenZipScript @case
                $LASTEXITCODE | Should -Be 1 -Because ($case | ConvertTo-Json -Compress)
            }
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Treats null values as unset / Behandelt null als nicht gesetzt' {
            $env:installAllow = 'null'
            $env:installSource = ' NULL '
            $env:installTimeoutMinutes = 'null'
            $null = & $sevenZipScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Writes the custom field / Schreibt das Custom Field' {
            $env:resultCustomField = 'installReport'
            $null = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'installReport' -and ($Value | ConvertFrom-Json).Action -eq 'Installed' }
        }
    }
}
