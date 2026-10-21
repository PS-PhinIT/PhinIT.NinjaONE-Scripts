BeforeDiscovery {
    $installScriptCases = @(Get-ChildItem -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Installations-Scripte') -Filter 'install*.ps1' |
        ForEach-Object { @{ Script = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root 'Installations-Scripte'
    $sevenZipScript = Join-Path $folder 'install7Zip.ps1'
    $puttyScript = Join-Path $folder 'installPuTTY.ps1'
    $officeScript = Join-Path $folder 'installMicrosoft365Apps.ps1'
    $pwshScript = Join-Path $folder 'installPowerShell7.ps1'
    $officeCdn = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
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
    function Get-AuthenticodeSignature { param($LiteralPath, $ErrorAction) }
    function New-FakeSignature {
        param([string]$Status = 'Valid', [string]$Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US')
        [pscustomobject]@{ Status = $Status; SignerCertificate = [pscustomobject]@{ Subject = $Subject } }
    }
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
        'install1Password.ps1'                   = @('1Password')
        'install7Zip.ps1'                        = @('7-Zip 26.04 (x64)', '7-Zip 24.09')
        'installAdobeAcrobatReader.ps1'          = @('Adobe Acrobat (64-bit)', 'Adobe Acrobat Reader DC MUI')
        'installAdvancedIpScanner.ps1'           = @('Advanced IP Scanner 2.5.4594.1')
        'installAnyDesk.ps1'                     = @('AnyDesk')
        'installAwsCli.ps1'                      = @('AWS Command Line Interface v2')
        'installAzureCli.ps1'                    = @('Microsoft Azure CLI (64-bit)', 'Microsoft Azure CLI')
        'installAzureStorageExplorer.ps1'        = @('Microsoft Azure Storage Explorer version 1.46.0')
        'installBitwarden.ps1'                   = @('Bitwarden 2026.10.0', 'Bitwarden')
        'installBoxDrive.ps1'                    = @('Box')
        'installBraveBrowser.ps1'                = @('Brave')
        'installCiscoJabber.ps1'                 = @('Cisco Jabber')
        'installCiscoWebex.ps1'                  = @('Webex', 'Cisco Webex')
        'installCitrixWorkspace.ps1'             = @('Citrix Workspace 2409')
        'installDBeaverCommunity.ps1'            = @('DBeaver 26.2.0')
        'installDellCommandUpdate.ps1'           = @('Dell Command | Update for Windows Universal', 'Dell Command | Update')
        'installDotNetAspNetCoreRuntime10.ps1'   = @('Microsoft ASP.NET Core Runtime - 10.0.13 (x64)', 'Microsoft ASP.NET Core 10.0.13 - Shared Framework (x64)')
        'installDotNetAspNetCoreRuntime8.ps1'    = @('Microsoft ASP.NET Core 8.0.32 - Shared Framework (x64)')
        'installDotNetDesktopRuntime10.ps1'      = @('Microsoft Windows Desktop Runtime - 10.0.5 (x64)')
        'installDotNetDesktopRuntime8.ps1'       = @('Microsoft Windows Desktop Runtime - 8.0.32 (x64)')
        'installDotNetHostingBundle10.ps1'       = @('Microsoft .NET 10.0.13 - Windows Server Hosting')
        'installDotNetHostingBundle8.ps1'        = @('Microsoft .NET 8.0.32 - Windows Server Hosting')
        'installDotNetRuntime10.ps1'             = @('Microsoft .NET Runtime - 10.0.13 (x64)')
        'installDotNetRuntime8.ps1'              = @('Microsoft .NET Runtime - 8.0.32 (x64)')
        'installDrawIo.ps1'                      = @('draw.io 29.0.3')
        'installDropbox.ps1'                     = @('Dropbox')
        'installEmClient.ps1'                    = @('eM Client')
        'installEverything.ps1'                  = @('Everything 1.4.1.1032 (x64)')
        'installFoxitPdfEditor.ps1'              = @('Foxit PDF Editor', 'Foxit PhantomPDF')
        'installFoxitPdfReader.ps1'              = @('Foxit PDF Reader')
        'installGit.ps1'                         = @('Git', 'Git version 2.40.0')
        'installGoogleChrome.ps1'                = @('Google Chrome')
        'installGoogleDrive.ps1'                 = @('Google Drive')
        'installGoToMeeting.ps1'                 = @('GoToMeeting 10.19.0.19950', 'GoTo Meeting')
        'installGpg4win.ps1'                     = @('Gpg4win (5.1.1)', 'Gpg4win')
        'installGreenshot.ps1'                   = @('Greenshot 1.3.290')
        'installIntelDriverSupportAssistant.ps1' = @('Intel® Driver & Support Assistant', 'Intel(R) Driver & Support Assistant')
        'installIrfanView.ps1'                   = @('IrfanView 4.76 (64-bit)')
        'installJabraDirect.ps1'                 = @('Jabra Direct')
        'installKeePass.ps1'                     = @('KeePass Password Safe 2.61.1')
        'installKeePassXC.ps1'                   = @('KeePassXC')
        'installLenovoSystemUpdate.ps1'          = @('Lenovo System Update')
        'installLibreOffice.ps1'                 = @('LibreOffice 25.8.2.2')
        'installMattermostDesktop.ps1'           = @('Mattermost')
        'installMicrosoft365Apps.ps1'            = @('Microsoft 365 Apps for enterprise - de-de', 'Microsoft 365 Apps for business - en-us', 'Microsoft Office 365 ProPlus - de-de')
        'installMicrosoftEdge.ps1'               = @('Microsoft Edge')
        'installMicrosoftEdgeWebView2.ps1'       = @('Microsoft Edge WebView2 Runtime')
        'installMicrosoftOneDrive.ps1'           = @('Microsoft OneDrive')
        'installMicrosoftRemoteHelp.ps1'         = @('Remote Help')
        'installMobaXterm.ps1'                   = @('MobaXterm')
        'installMozillaFirefox.ps1'              = @('Mozilla Firefox (x64 de)')
        'installMozillaFirefoxEsr.ps1'           = @('Mozilla Firefox ESR (x64 de)', 'Mozilla Firefox 128.5.0 ESR (x64 de)')
        'installMozillaThunderbird.ps1'          = @('Mozilla Thunderbird (x64 de)')
        'installMRemoteNG.ps1'                   = @('mRemoteNG')
        'installMsOdbcSql18.ps1'                 = @('Microsoft ODBC Driver 18 for SQL Server')
        'installNextcloudDesktop.ps1'            = @('Nextcloud')
        'installNodeJsLts.ps1'                   = @('Node.js')
        'installNotepadPlusPlus.ps1'             = @('Notepad++ (64-bit x64)')
        'installOmnissaHorizonClient.ps1'        = @('Omnissa Horizon Client', 'VMware Horizon Client')
        'installOnlyOfficeDesktopEditors.ps1'    = @('ONLYOFFICE 10.0.0 (x64)', 'ONLYOFFICE Desktop Editors 8.1.1 (x64)')
        'installOpenVpn.ps1'                     = @('OpenVPN 2.7.7-I001 amd64')
        'installOpenVpnConnect.ps1'              = @('OpenVPN Connect')
        'installPdf24Creator.ps1'                = @('PDF24 Creator')
        'installPdfsamBasic.ps1'                 = @('PDFsam Basic')
        'installPdfXChangeEditor.ps1'            = @('PDF-XChange Editor')
        'installPeaZip.ps1'                      = @('PeaZip 11.2.0 (WIN64)')
        'installPowerAutomateDesktop.ps1'        = @('Power Automate for desktop')
        'installPowerBIDesktop.ps1'              = @('Microsoft PowerBI Desktop (x64)', 'Microsoft Power BI Desktop (x64)')
        'installPowerShell7.ps1'                 = @('PowerShell 7-x64')
        'installPowerToys.ps1'                   = @('PowerToys (Preview) x64')
        'installPuTTY.ps1'                       = @('PuTTY release 0.83 (64-bit)')
        'installPython314.ps1'                   = @('Python 3.14.7 (64-bit)')
        'installRealVncViewer.ps1'               = @('RealVNC Viewer 7.15.1', 'VNC Viewer 6.22.826')
        'installRemoteDesktopManager.ps1'        = @('Remote Desktop Manager', 'Remote Desktop Manager Free')
        'installRoyalTs.ps1'                     = @('Royal TS V7')
        'installShareX.ps1'                      = @('ShareX')
        'installSonicWallNetExtender.ps1'        = @('SonicWall NetExtender', 'Dell SonicWALL NetExtender')
        'installSplashtopBusiness.ps1'           = @('Splashtop Business')
        'installSqlServerManagementStudio.ps1'   = @('Microsoft SQL Server Management Studio 22', 'SQL Server Management Studio 22')
        'installTailscale.ps1'                   = @('Tailscale')
        'installTeamViewer.ps1'                  = @('TeamViewer', 'TeamViewer 15')
        'installTeamViewerHost.ps1'              = @('TeamViewer Host')
        'installTemurinJdk21.ps1'                = @('Eclipse Temurin JDK with Hotspot 21.0.5+11 (x64)')
        'installTemurinJre11.ps1'                = @('Eclipse Temurin JRE with Hotspot 11.0.25+9 (x64)')
        'installTemurinJre17.ps1'                = @('Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64)')
        'installTemurinJre21.ps1'                = @('Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTemurinJre25.ps1'                = @('Eclipse Temurin JRE with Hotspot 25.0.4+7 (x64)')
        'installTemurinJre8.ps1'                 = @('Eclipse Temurin JRE with Hotspot 8u482-b08 (x64)')
        'installTortoiseGit.ps1'                 = @('TortoiseGit 2.19.1.0 (64 bit)')
        'installTortoiseSvn.ps1'                 = @('TortoiseSVN 1.14.9.29743 (64 bit)')
        'installTreeSizeFree.ps1'                = @('TreeSize Free V4.7.3')
        'installVcRedist2013X64.ps1'             = @('Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664')
        'installVcRedistX64.ps1'                 = @('Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.40.33810', 'Microsoft Visual C++ v14 Redistributable (x64) - 14.50.35719')
        'installVcRedistX86.ps1'                 = @('Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.40.33810', 'Microsoft Visual C++ v14 Redistributable (x86) - 14.50.35719')
        'installVeraCrypt.ps1'                   = @('VeraCrypt 1.26.29', 'VeraCrypt')
        'installVisualStudioCode.ps1'            = @('Microsoft Visual Studio Code')
        'installVlcMediaPlayer.ps1'              = @('VLC media player')
        'installWinMerge.ps1'                    = @('WinMerge 2.16.58.2 x64')
        'installWinRar.ps1'                      = @('WinRAR 7.23 (64-bit)')
        'installWinSCP.ps1'                      = @('WinSCP 6.5.3')
        'installWireGuard.ps1'                   = @('WireGuard')
        'installWireshark.ps1'                   = @('Wireshark 4.6.9 x64')
        'installYubicoAuthenticator.ps1'         = @('Yubico Authenticator')
        'installZoomOutlookPlugin.ps1'           = @('Zoom Outlook Plugin')
        'installZoomWorkplace.ps1'               = @('Zoom Workplace (64-bit)', 'Zoom(64bit)')
    }
    # DE: Ähnliche Fremdprodukte dürfen nicht erkannt werden. EN: Similar foreign products must not be detected.
    $negativeDisplayNames = @{
        'install1Password.ps1'                   = @('1Password CLI')
        'installAdvancedIpScanner.ps1'           = @('Advanced Port Scanner 2.5')
        'installAwsCli.ps1'                      = @('AWS Tools for Windows')
        'installAzureCli.ps1'                    = @('Microsoft Azure Storage Explorer version 1.46.0')
        'installAzureStorageExplorer.ps1'        = @('Microsoft Azure CLI (64-bit)')
        'installBitwarden.ps1'                   = @('Bitwarden Directory Connector')
        'installBoxDrive.ps1'                    = @('Box Tools', 'Box Edit')
        'installBraveBrowser.ps1'                = @('Brave Beta', 'Brave Nightly')
        'installCiscoJabber.ps1'                 = @('Webex')
        'installCiscoWebex.ps1'                  = @('Cisco Webex Meetings', 'Webex Productivity Tools')
        'installDBeaverCommunity.ps1'            = @('HeidiSQL 12.10.0.7000')
        'installDellCommandUpdate.ps1'           = @('Dell SupportAssist')
        'installDotNetAspNetCoreRuntime10.ps1'   = @('Microsoft ASP.NET Core Runtime - 10.0.13 (x86)', 'Microsoft ASP.NET Core 8.0.32 - Shared Framework (x64)')
        'installDotNetAspNetCoreRuntime8.ps1'    = @('Microsoft ASP.NET Core 8.0.32 - Shared Framework (x86)', 'Microsoft ASP.NET Core Runtime - 10.0.13 (x64)')
        'installDotNetDesktopRuntime10.ps1'      = @('Microsoft Windows Desktop Runtime - 8.0.11 (x64)')
        'installDotNetDesktopRuntime8.ps1'       = @('Microsoft Windows Desktop Runtime - 8.0.32 (x86)', 'Microsoft Windows Desktop Runtime - 10.0.5 (x64)')
        'installDotNetHostingBundle10.ps1'       = @('Microsoft .NET 8.0.32 - Windows Server Hosting')
        'installDotNetHostingBundle8.ps1'        = @('Microsoft .NET 10.0.13 - Windows Server Hosting')
        'installDotNetRuntime10.ps1'             = @('Microsoft .NET Runtime - 10.0.13 (x86)', 'Microsoft .NET Runtime - 8.0.32 (x64)')
        'installDotNetRuntime8.ps1'              = @('Microsoft .NET Runtime - 8.0.32 (x86)', 'Microsoft .NET Runtime - 10.0.13 (x64)')
        'installDrawIo.ps1'                      = @('Microsoft Visio Viewer 2016')
        'installDropbox.ps1'                     = @('Dropbox Update Helper')
        'installEmClient.ps1'                    = @('Mozilla Thunderbird (x64 de)')
        'installEverything.ps1'                  = @('Everything Toolbar')
        'installFoxitPdfEditor.ps1'              = @('Foxit PDF Reader')
        'installFoxitPdfReader.ps1'              = @('Foxit PDF Editor')
        'installGit.ps1'                         = @('GitHub Desktop')
        'installGoogleChrome.ps1'                = @('Google Chrome Beta', 'Google Update Helper')
        'installGoogleDrive.ps1'                 = @('Google Chrome')
        'installGoToMeeting.ps1'                 = @('GoTo Opener')
        'installGpg4win.ps1'                     = @('GnuPG (2.4.7)')
        'installIntelDriverSupportAssistant.ps1' = @('Intel(R) Computing Improvement Program')
        'installIrfanView.ps1'                   = @('IrfanView PlugIns 4.76 (64-bit)')
        'installJabraDirect.ps1'                 = @('Jabra Xpress')
        'installKeePass.ps1'                     = @('KeePassXC')
        'installLenovoSystemUpdate.ps1'          = @('Lenovo Vantage Service')
        'installMattermostDesktop.ps1'           = @('Slack (Machine - MSI)')
        'installMicrosoft365Apps.ps1'            = @('Microsoft Office Professional Plus 2019 - de-de', 'Microsoft Teams', 'Office 16 Click-to-Run Extensibility Component')
        'installMicrosoftEdge.ps1'               = @('Microsoft Edge WebView2 Runtime', 'Microsoft Edge Update')
        'installMicrosoftEdgeWebView2.ps1'       = @('Microsoft Edge')
        'installMicrosoftOneDrive.ps1'           = @('Microsoft OneNote - de-de')
        'installMicrosoftRemoteHelp.ps1'         = @('Remote Desktop')
        'installMobaXterm.ps1'                   = @('PuTTY release 0.83 (64-bit)')
        'installMozillaFirefoxEsr.ps1'           = @('Mozilla Firefox (x64 de)', 'Mozilla Maintenance Service')
        'installMRemoteNG.ps1'                   = @('Remote Desktop Manager')
        'installMsOdbcSql18.ps1'                 = @('Microsoft ODBC Driver 17 for SQL Server')
        'installNextcloudDesktop.ps1'            = @('Nextcloud Talk')
        'installNodeJsLts.ps1'                   = @('Node.js Tools for Visual Studio')
        'installOmnissaHorizonClient.ps1'        = @('VMware Tools')
        'installOnlyOfficeDesktopEditors.ps1'    = @('LibreOffice 25.8.2.2')
        'installOpenVpn.ps1'                     = @('OpenVPN Connect')
        'installOpenVpnConnect.ps1'              = @('OpenVPN 2.6.12-I001 amd64')
        'installPdfsamBasic.ps1'                 = @('PDFsam Enhanced 7')
        'installPdfXChangeEditor.ps1'            = @('PDF-XChange Viewer')
        'installPeaZip.ps1'                      = @('7-Zip 24.09')
        'installPowerAutomateDesktop.ps1'        = @('Microsoft Power BI Desktop (x64)')
        'installPowerBIDesktop.ps1'              = @('Microsoft Power BI Report Builder')
        'installPowerToys.ps1'                   = @('Microsoft PowerShell')
        'installPython314.ps1'                   = @('Python 3.14.7 Core Interpreter (64-bit)', 'Python 3.13.15 (64-bit)', 'Python Launcher')
        'installRealVncViewer.ps1'               = @('RealVNC Server 7.18.0')
        'installRemoteDesktopManager.ps1'        = @('Remote Desktop Connection Manager')
        'installRoyalTs.ps1'                     = @('Royal TS V6')
        'installShareX.ps1'                      = @('Greenshot 1.3.290')
        'installSonicWallNetExtender.ps1'        = @('SonicWall Connect Tunnel')
        'installSplashtopBusiness.ps1'           = @('Splashtop Streamer')
        'installSqlServerManagementStudio.ps1'   = @('Microsoft SQL Server Management Studio - 20.2', 'SQL Server Management Studio 21')
        'installTailscale.ps1'                   = @('WireGuard')
        'installTeamViewer.ps1'                  = @('TeamViewer Meeting Add-In')
        'installTeamViewerHost.ps1'              = @('TeamViewer', 'TeamViewer 15')
        'installTemurinJdk21.ps1'                = @('Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTemurinJre11.ps1'                = @('Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64)')
        'installTemurinJre17.ps1'                = @('Eclipse Temurin JRE with Hotspot 11.0.25+9 (x64)', 'Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTemurinJre21.ps1'                = @('Eclipse Temurin JRE with Hotspot 17.0.13+11 (x64)')
        'installTemurinJre25.ps1'                = @('Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTemurinJre8.ps1'                 = @('Eclipse Temurin JDK with Hotspot 8u482-b08 (x64)', 'Eclipse Temurin JRE with Hotspot 21.0.5+11 (x64)')
        'installTortoiseGit.ps1'                 = @('TortoiseSVN 1.14.9.29743 (64 bit)', 'Git')
        'installTortoiseSvn.ps1'                 = @('TortoiseGit 2.19.1.0 (64 bit)')
        'installVcRedist2013X64.ps1'             = @('Microsoft Visual C++ 2013 Redistributable (x86) - 12.0.40664', 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.40.33810')
        'installVcRedistX64.ps1'                 = @('Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.40.33810', 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664')
        'installVcRedistX86.ps1'                 = @('Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.40.33810', 'Microsoft Visual C++ 2013 Redistributable (x86) - 12.0.40664')
        'installVeraCrypt.ps1'                   = @('BitLocker Drive Encryption')
        'installVisualStudioCode.ps1'            = @('Microsoft Visual Studio Code Insiders')
        'installWinMerge.ps1'                    = @('TortoiseGit 2.19.1.0 (64 bit)')
        'installWinRar.ps1'                      = @('7-Zip 24.09')
        'installWireshark.ps1'                   = @('Npcap')
        'installYubicoAuthenticator.ps1'         = @('YubiKey Manager')
        'installZoomOutlookPlugin.ps1'           = @('Zoom Workplace (64-bit)')
        'installZoomWorkplace.ps1'               = @('Zoom Outlook Plugin')
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
        Mock Invoke-WebRequest {}
        Mock Get-AuthenticodeSignature { New-FakeSignature }
        Mock Get-Content { @() }
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
            $report = & $Path -AllowInstall true -Source Winget | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Action | Should -Be 'Installed'
            $report.WingetPath | Should -Be $wingetExe
            $id = [regex]::Escape($report.WingetId)
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $wingetExe -and $ArgumentList -match "^install --id $id --exact --source winget --silent " -and
                $ArgumentList -match '--accept-package-agreements' -and $ArgumentList -match '--disable-interactivity' -and $ArgumentList -match '--scope machine$' -and
                $RedirectStandardOutput -like '*-winget.log'
            }
        }
        It 'SilentSwitches.md documents every script / SilentSwitches.md dokumentiert jedes Skript' {
            $markdownPath = Join-Path $folder 'SilentSwitches.md'
            [IO.File]::Exists($markdownPath) | Should -BeTrue
            $markdown = [IO.File]::ReadAllText($markdownPath)
            foreach ($file in [IO.Directory]::GetFiles($folder, '*.ps1')) {
                $markdown | Should -Match ([regex]::Escape('(' + [IO.Path]::GetFileName($file) + ')'))
            }
        }

        It 'All scripts share the identical engine / Alle Skripte nutzen dieselbe Logik' {
            # DE: Änderungen an der Logik müssen in allen Skripten gleich erfolgen. EN: Engine changes must be applied to all scripts alike.
            $files = @([IO.Directory]::GetFiles($folder, 'install*.ps1'))
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
        It 'Explains a winget hash mismatch and only names existing logs / Erklärt Hash-Fehler und nennt nur vorhandene Logs' {
            $installFake.Process = New-FakeProcess -ExitCode -1978335215
            Mock Test-Path { $true } -ParameterFilter { [string]$LiteralPath -like '*-winget.log' }
            Mock Get-Content { @('Found 7-Zip [7zip.7zip]', "`r  ██████  6.30 MB / 6.30 MB", 'Installer hash does not match.') }
            $output = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            $text = $output -join ' '
            $text | Should -Match '0x8A150011'
            $text | Should -Match 'Log: .*-winget\.log;'
            $text | Should -Not -Match 'install7Zip-\d{8}-\d{6}\.log'
            $text | Should -Match 'Installer hash does not match\.'
            $text | Should -Not -Match 'MB /'
            $text | Should -Match 'installSource=Download'
        }
        It 'Reports no log when none was written / Meldet fehlendes Log' {
            $installFake.Process = New-FakeProcess -ExitCode -1978335224
            $output = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'kein Log / no log'
        }
        It 'Fails when the product is not detected afterwards / Fehler ohne Erkennung danach' {
            $installFake.OnInstall = $null
            Mock Test-Path { $true } -ParameterFilter { [string]$LiteralPath -like '*-winget.log' }
            Mock Get-Content { @('Successfully installed') }
            $output = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            $text = $output -join ' '
            $text | Should -Match 'not detected after installation \(Exitcode / exit code 0\); Log: .*-winget\.log; Successfully installed'
        }
        It 'Forces the PowerShell 7 MSI instead of MSIX / Erzwingt das PowerShell-7-MSI statt MSIX' {
            $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key 'Pwsh' -DisplayName 'PowerShell 7-x64' -Version '7.6.7.0' }
            $report = & $pwshScript -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Action | Should -Be 'Installed'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match ' --installer-type wix --scope machine$' }
            $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key '7-Zip' -DisplayName '7-Zip 26.04 (x64)' -Version '26.04' }
            $null = & $sevenZipScript -AllowInstall true
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -match '--installer-type' }
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
        It 'Installs Microsoft 365 Apps via the signed Office Deployment Tool by default / Installiert Microsoft 365 Apps per signiertem ODT' {
            $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key 'O365' -DisplayName 'Microsoft 365 Apps for enterprise - de-de' }
            $report = & $officeScript -AllowInstall true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'Download'
            $report.Action | Should -Be 'Installed'
            $report.DownloadUrl | Should -Be $officeCdn
            $report.InstallerSigner | Should -Match '^CN=Microsoft Corporation,'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $officeCdn -and $OutFile -like '*PhinIT-Install-*installer.exe' -and $UseBasicParsing }
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -like '*PhinIT-Install-*installer.exe' -and $ArgumentList -eq '/configure https://aka.ms/fhlwingetconfig' -and -not $RedirectStandardOutput
            }
            Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*PhinIT-Install-*' -and $Recurse }
            $installFake.Reg.Clear()
            $null = & $officeScript -AllowInstall true -InstallerArguments '/configure https://raw.githubusercontent.com/o/r/main/office365.xml'
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '/configure https://raw.githubusercontent.com/o/r/main/office365.xml' }
        }
        It 'Refuses a download with an invalid signature / Verweigert Download mit ungültiger Signatur' {
            foreach ($signature in @((New-FakeSignature -Status 'HashMismatch'), (New-FakeSignature -Subject 'CN=Contoso Ltd, O=Contoso'), [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null })) {
                Mock Get-AuthenticodeSignature { $signature }.GetNewClosure()
                $output = & $officeScript -AllowInstall true
                $LASTEXITCODE | Should -Be 1
                ($output -join ' ') | Should -Match 'Signatur'
            }
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 3 -Exactly -ParameterFilter { $LiteralPath -like '*PhinIT-Install-*' }
        }
        It 'Rejects Download for tools without a vendor URL / Lehnt Download ohne Hersteller-URL ab' {
            $null = & $sevenZipScript -AllowInstall true -Source Download
            $LASTEXITCODE | Should -Be 1
            $null = & $officeScript -AllowInstall true -Source Download -InstallerPath 'C:\Install\setup.exe'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        It 'Still installs Microsoft 365 Apps via winget on request / Installiert Microsoft 365 Apps auf Wunsch per winget' {
            $installFake.OnInstall = { Add-UninstallEntry -Root $uninstall64 -Key 'O365' -DisplayName 'Microsoft 365 Apps for enterprise - en-us' }
            $report = & $officeScript -AllowInstall true -Source winget | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'Winget'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
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
