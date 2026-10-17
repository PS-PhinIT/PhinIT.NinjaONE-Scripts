# Silent-Schalter für Installationen / Silent install switches

Diese Übersicht sammelt bewährte Schalter für unbeaufsichtigte (Silent-)Installationen und Deinstallationen gängiger Programme,
Tools und Installer-Frameworks. Sie ergänzt die Skripte in diesem Ordner, deren Standardargumente (`InstallerArguments`) aus
dieser Liste stammen.

*This overview collects proven switches for unattended (silent) installs and uninstalls of common programs, tools and installer
frameworks. It complements the scripts in this folder, whose default arguments (`InstallerArguments`) are taken from this list.*

> **Wichtig / Important:** Schalter ändern sich mit neuen Versionen. Vor dem produktiven Rollout immer auf einem Testgerät
> prüfen und mit der aktuellen Herstellerdokumentation abgleichen. Lizenzbedingungen (z. B. Oracle Java, TeamViewer, AnyDesk,
> Zoom) liegen in der Verantwortung des Betreibers.
> *Switches change with new versions. Always test on a pilot device and compare with the current vendor documentation before a
> production rollout. Licence terms are the operator's responsibility.*

## Inhalt / Contents

- [Grundregeln / Basics](#grundregeln--basics)
- [Rückgabecodes / Exit codes](#rückgabecodes--exit-codes)
- [Installer-Frameworks erkennen / Identify installer frameworks](#installer-frameworks-erkennen--identify-installer-frameworks)
- [Schalter nach Framework / Switches by framework](#schalter-nach-framework--switches-by-framework)
- [Schalter nach Anwendung / Switches by application](#schalter-nach-anwendung--switches-by-application)
  - [Browser](#browser)
  - [Office, PDF und Kommunikation / Office, PDF and communication](#office-pdf-und-kommunikation--office-pdf-and-communication)
  - [Fernwartung, VPN und Remote / Remote access and VPN](#fernwartung-vpn-und-remote--remote-access-and-vpn)
  - [Laufzeiten und Frameworks / Runtimes and frameworks](#laufzeiten-und-frameworks--runtimes-and-frameworks)
  - [Admin- und Entwickler-Tools / Admin and developer tools](#admin--und-entwickler-tools--admin-and-developer-tools)
  - [Werkzeuge und Multimedia / Utilities and multimedia](#werkzeuge-und-multimedia--utilities-and-multimedia)
  - [Hersteller-Tools / OEM tools](#hersteller-tools--oem-tools)
- [winget-IDs der Skripte / winget IDs of the scripts](#winget-ids-der-skripte--winget-ids-of-the-scripts)
- [Deinstallation / Uninstall](#deinstallation--uninstall)
- [Typische Fehler / Common pitfalls](#typische-fehler--common-pitfalls)

## Grundregeln / Basics

| Regel (DE) | Rule (EN) |
| --- | --- |
| NinjaOne führt Skripte als `SYSTEM` aus: Per-Machine-Installer (`ALLUSERS=1`, `/ALLUSERS`, `--scope machine`) bevorzugen. | NinjaOne runs scripts as `SYSTEM`: prefer per-machine installers. |
| MSI-Pakete sind meist einfacher zu steuern (Eigenschaften, Logs, Produktcode) als EXE-Wrapper. | MSI packages are usually easier to control (properties, logs, product code) than EXE wrappers. |
| Immer `/norestart` bzw. `REBOOT=ReallySuppress` setzen und Neustarts geplant über NinjaOne auslösen. | Always suppress reboots and schedule them via NinjaOne. |
| Immer ein Log schreiben (`/l*v` bei MSI, `/LOG=` bei Inno Setup, `/log` bei WiX Burn). | Always write a log file. |
| Installationsquelle per SHA256 prüfen (`installerSha256` in den Skripten). | Verify the installer via SHA256 (`installerSha256` in the scripts). |
| Bei EXE-Dateien zuerst `setup.exe /?`, `/help` oder `-h` testen und die Eigenschaften der Datei (Hersteller, Produktname) ansehen. | For EXE files first try `/?`, `/help` or `-h` and inspect the file properties. |

## Rückgabecodes / Exit codes

| Code | Bedeutung (DE) | Meaning (EN) | Behandlung in den Skripten / Handling in the scripts |
| --- | --- | --- | --- |
| `0` | Erfolgreich | Success | Erfolg / success |
| `3010` | Erfolgreich, Neustart erforderlich | Success, reboot required | Erfolg, `RebootRequired = true` |
| `1641` | Erfolgreich, Installer hat Neustart eingeleitet | Success, installer initiated a reboot | Erfolg, `RebootRequired = true` |
| `1602` | Durch Benutzer abgebrochen | Cancelled by user | Fehler / error |
| `1603` | Schwerwiegender Fehler (Log prüfen) | Fatal error (check log) | Fehler / error |
| `1605` | Produkt nicht installiert (bei Deinstallation) | Product not installed (uninstall) | Fehler / error |
| `1618` | Eine andere Installation läuft bereits | Another installation is in progress | Fehler – später erneut ausführen / retry later |
| `1619` | Paket konnte nicht geöffnet werden | Package could not be opened | Fehler / error |
| `1638` | Andere Version bereits installiert | Another version already installed | Fehler / error |
| `0x8A15002B` (`-1978335189`) | winget: kein Update verfügbar | winget: no applicable update | Erfolg / success |
| `0x8A150061` (`-1978335135`) | winget: Paket bereits installiert | winget: package already installed | Erfolg / success |
| `0x8A150109` (`-1978334967`) | winget: Neustart erforderlich | winget: reboot required to finish | Erfolg, `RebootRequired = true` |
| `0x8A15010B` (`-1978334965`) | winget: Neustart wurde eingeleitet | winget: reboot initiated | Erfolg, `RebootRequired = true` |
| `0x8A150014` (`-1978335212`) | winget: Paket nicht gefunden | winget: no package found | Fehler / error |

Quelle / Source: [MSI error codes](https://learn.microsoft.com/windows/win32/msi/error-codes),
[winget return codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md).

## Installer-Frameworks erkennen / Identify installer frameworks

| Hinweis / Hint | Framework |
| --- | --- |
| Datei endet auf `.msi` | Windows Installer (MSI) |
| `setup.exe /?` zeigt ein Inno-Setup-Hilfefenster, Dateieigenschaften „Inno Setup“ | Inno Setup |
| Fenstertitel „Nullsoft Install System“, Datei enthält `Nullsoft` | NSIS |
| Dateieigenschaften „InstallShield“, entpackt nach `%TEMP%\{GUID}` | InstallShield (Basic MSI / InstallScript) |
| Dateieigenschaften „WiX Toolset“ / „Burn“, `/?` zeigt `/install /repair /uninstall` | WiX Burn Bundle |
| Datei `Setup.exe` mit `.nupkg`, Installation unter `%LOCALAPPDATA%` | Squirrel (nur pro Benutzer / per user only) |
| Dateieigenschaften „Advanced Installer“ | Advanced Installer EXE |
| Dateiendung `.msix`, `.msixbundle`, `.appx` | MSIX / AppX |

## Schalter nach Framework / Switches by framework

| Framework | Silent-Installation / Silent install | Deinstallation / Uninstall | Hinweise / Notes |
| --- | --- | --- | --- |
| MSI | `msiexec.exe /i "app.msi" /qn /norestart /l*v "C:\Windows\Temp\app.log"` | `msiexec.exe /x {ProductCode} /qn /norestart` | Eigenschaften als `NAME=Wert`; Transform per `TRANSFORMS="app.mst"`; `ALLUSERS=1` für Per-Machine. |
| MSI-Patch | `msiexec.exe /p "patch.msp" /qn /norestart` | – | Patch passend zur installierten Version. |
| Inno Setup | `setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="C:\Windows\Temp\app.log"` | `unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` | `/ALLUSERS`, `/DIR="pfad"`, `/TASKS=`, `/MERGETASKS=`, `/COMPONENTS=`, `/LOADINF="datei.inf"` (zuvor mit `/SAVEINF=` aufzeichnen). |
| NSIS | `setup.exe /S` | `uninstall.exe /S` | `/S` ist case-sensitive; `/D=C:\Pfad` muss **letzter** Parameter sein und darf keine Anführungszeichen haben. Der Uninstaller kopiert sich nach `%TEMP%` und kehrt sofort zurück – zum Warten `uninstall.exe /S _?=C:\Installationspfad`. |
| InstallShield (Basic MSI) | `setup.exe /s /v"/qn /norestart"` | `msiexec.exe /x {ProductCode} /qn` | Alles in `/v"…"` wird an msiexec weitergereicht; innere Anführungszeichen mit `\"` maskieren. |
| InstallShield (InstallScript) | `setup.exe /s /f1"C:\Temp\setup.iss" /f2"C:\Temp\setup.log"` | `setup.exe /s /f1"C:\Temp\uninstall.iss"` | Antwortdatei vorher mit `setup.exe /r /f1"C:\Temp\setup.iss"` aufzeichnen. |
| WiX Burn | `bundle.exe /install /quiet /norestart /log "C:\Windows\Temp\app.log"` | `bundle.exe /uninstall /quiet /norestart` | `/passive` zeigt nur den Fortschritt. Eigenschaften als `NAME=Wert`. |
| Advanced Installer | `setup.exe /exenoui /qn /norestart` | `msiexec.exe /x {ProductCode} /qn` | `/exenoui` unterdrückt die EXE-Oberfläche; MSI-Parameter folgen danach. MSI extrahieren: `setup.exe /extract:"C:\Temp\msi"`. |
| Squirrel | `Setup.exe --silent` | `%LOCALAPPDATA%\<App>\Update.exe --uninstall -s` | Installiert nur pro Benutzer – für `SYSTEM` ungeeignet; Hersteller-MSI (Machine-Wide-Installer) bevorzugen. |
| MSIX / AppX | `Add-AppxProvisionedPackage -Online -PackagePath "app.msixbundle" -SkipLicense` | `Remove-AppxProvisionedPackage -Online -PackageName <Name>` | Provisionierung gilt für neue Benutzerprofile; `Add-AppxPackage` installiert nur für den aktuellen Benutzer. |
| winget | `winget install --id <Id> --exact --source winget --silent --accept-package-agreements --accept-source-agreements --scope machine` | `winget uninstall --id <Id> --exact --silent` | Als `SYSTEM` muss `winget.exe` über den vollständigen Pfad unter `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*` aufgerufen werden (in den Skripten automatisiert). |

## Schalter nach Anwendung / Switches by application

Spalte **Skript** verweist auf das passende Installationsskript in diesem Ordner. *Column **Script** links to the matching install script.*

### Browser

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Google Chrome | MSI (Enterprise) | `msiexec.exe /i googlechromestandaloneenterprise64.msi /qn /norestart` | Bevorzugt für Unternehmen; Richtlinien per GPO/Registry. | [installGoogleChrome.ps1](installGoogleChrome.ps1) |
| Google Chrome | EXE (Online) | `ChromeSetup.exe /silent /install` | Lädt zur Laufzeit nach. | [installGoogleChrome.ps1](installGoogleChrome.ps1) |
| Mozilla Firefox | EXE | `Firefox Setup.exe /S /PreventRebootRequired=true` | Weitere Optionen: `/InstallDirectoryPath=`, `/DesktopShortcut=false`, `/MaintenanceService=false`. | [installMozillaFirefox.ps1](installMozillaFirefox.ps1) |
| Mozilla Firefox | MSI | `msiexec.exe /i "Firefox Setup.msi" /qn` | Eigenschaften: `INSTALL_DIRECTORY_PATH=`, `DESKTOP_SHORTCUT=false`, `INSTALL_MAINTENANCE_SERVICE=false`. | [installMozillaFirefox.ps1](installMozillaFirefox.ps1) |
| Microsoft Edge | MSI (Enterprise) | `msiexec.exe /i MicrosoftEdgeEnterpriseX64.msi /qn /norestart` | In Windows 10/11 enthalten; MSI für Server/Kanalwechsel. | – |
| Microsoft Edge WebView2 | EXE (Evergreen) | `MicrosoftEdgeWebview2Setup.exe /silent /install` | Standalone-Variante: `MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install`. | – |
| Brave | EXE | `BraveBrowserStandaloneSilentSetup.exe` | Die „StandaloneSilent“-Variante installiert ohne Schalter. | – |

### Office, PDF und Kommunikation / Office, PDF and communication

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Microsoft 365 Apps / Office LTSC / Visio / Project | Office Deployment Tool | `setup.exe /configure configuration.xml` | XML mit [config.office.com](https://config.office.com) erstellen; `<Display Level="None" AcceptEULA="TRUE" />`. Vorab laden: `setup.exe /download configuration.xml`. | – |
| Microsoft Teams (neu / new) | Bootstrapper | `teamsbootstrapper.exe -p` | Provisioniert für alle Benutzer. Offline: `teamsbootstrapper.exe -p -o "C:\Temp\MSTeams-x64.msix"`. Entfernen: `teamsbootstrapper.exe -x`. | – |
| Microsoft OneDrive | EXE | `OneDriveSetup.exe /allusers /silent` | Per-Machine-Installation unter `C:\Program Files\Microsoft OneDrive`. | – |
| Adobe Acrobat Reader | EXE | `AcroRdrDCx64<ver>.exe /sAll /rs /msi EULA_ACCEPT=YES` | `/sAll` = Silent, `/rs` = kein Neustart; Anpassung per Adobe Customization Wizard (`.mst`). | [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) |
| Adobe Acrobat Reader | MSI | `msiexec.exe /i AcroRead.msi EULA_ACCEPT=YES /qn /norestart` | MSI aus dem EXE extrahiert bzw. Enterprise-Download. | [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) |
| PDF24 Creator | MSI | `msiexec.exe /i pdf24-creator.msi AUTOUPDATE=No DESKTOPICONS=No /qn /norestart` | Weitere Eigenschaft z. B. `REGISTERREADER=No`. | [installPdf24Creator.ps1](installPdf24Creator.ps1) |
| PDF24 Creator | EXE | `pdf24-creator.exe /VERYSILENT /NORESTART /NOUPDATE` | Inno Setup. | [installPdf24Creator.ps1](installPdf24Creator.ps1) |
| Foxit PDF Reader | MSI | `msiexec.exe /i FoxitPDFReader.msi /qn /norestart` | Enterprise-MSI vom Hersteller. | – |
| LibreOffice | MSI | `msiexec.exe /i LibreOffice_x64.msi /qn /norestart ALLUSERS=1 CREATEDESKTOPLINK=0 REGISTER_NO_MSO_TYPES=1 ISCHECKFORPRODUCTUPDATES=0 QUICKSTART=0 RebootYesNo=No` | `UI_LANGS=de` begrenzt Sprachen; `REGISTER_ALL_MSO_TYPES=1` übernimmt Office-Dateitypen. | [installLibreOffice.ps1](installLibreOffice.ps1) |
| Mozilla Thunderbird | EXE / MSI | `Thunderbird Setup.exe /S` bzw. `msiexec.exe /i "Thunderbird Setup.msi" /qn` | Gleiche Optionen wie Firefox. | [installMozillaThunderbird.ps1](installMozillaThunderbird.ps1) |
| Zoom Workplace | MSI | `msiexec.exe /i ZoomInstallerFull.msi /qn /norestart ZoomAutoUpdate=true ZNoDesktopShortCut=true` | Weitere Einstellungen per `ZConfig="…"` bzw. `ZRecommend="…"`. | [installZoomWorkplace.ps1](installZoomWorkplace.ps1) |
| Cisco Webex App | MSI | `msiexec.exe /i Webex.msi ACCEPT_EULA=TRUE ALLUSERS=1 AUTOSTART_WITH_WINDOWS=false /qn` | Per-Machine-Installation. | – |
| Slack | MSI | `msiexec.exe /i slack-standalone-x64.msi /qn` | MSI für Per-Machine-Bereitstellung verwenden (das EXE ist Squirrel). | – |

### Fernwartung, VPN und Remote / Remote access and VPN

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| TeamViewer (Full) | EXE | `TeamViewer_Setup_x64.exe /S` | NSIS; Deinstallation `"C:\Program Files\TeamViewer\uninstall.exe" /S`. | [installTeamViewer.ps1](installTeamViewer.ps1) |
| TeamViewer Host | MSI | `msiexec.exe /i TeamViewer_Host.msi /qn CUSTOMCONFIGID=<ID> APITOKEN=<Token> ASSIGNMENTOPTIONS="--grant-easy-access"` | Token **nicht** im Skript hinterlegen, sondern als geschützte Variable übergeben. | – |
| AnyDesk | EXE | `AnyDesk.exe --install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon` | Optional `--update-disabled`; Deinstallation `AnyDesk.exe --silent --remove`. | [installAnyDesk.ps1](installAnyDesk.ps1) |
| WireGuard | MSI | `msiexec.exe /i wireguard-amd64.msi /qn DO_NOT_LAUNCH=1` | Verhindert den Start der Oberfläche nach der Installation. | [installWireGuard.ps1](installWireGuard.ps1) |
| OpenVPN (Community) | MSI | `msiexec.exe /i OpenVPN-amd64.msi /qn /norestart` | Komponenten per `ADDLOCAL=`. | – |
| FortiClient VPN | MSI / EXE | `msiexec.exe /i FortiClient.msi /quiet /norestart` bzw. `FortiClientSetup.exe /quiet /norestart` | Nicht in winget – nur über Datei-Quelle. | – |
| Cisco Secure Client (AnyConnect) | MSI | `msiexec.exe /package cisco-secure-client-win-<ver>-core-vpn-predeploy-k9.msi /qn /norestart PRE_DEPLOY_DISABLE_VPN=0` | Module (DART, Umbrella …) als eigene MSI-Pakete. | – |
| Citrix Workspace App | EXE | `CitrixWorkspaceApp.exe /silent /noreboot /AutoUpdateCheck=disabled` | Optional `/includeSSON`, `/forceinstall`; Deinstallation `/uninstall /silent`. | [installCitrixWorkspace.ps1](installCitrixWorkspace.ps1) |
| Omnissa (VMware) Horizon Client | EXE | `Horizon-Client.exe /silent /norestart VDM_SERVER=<server>` | – | – |
| VMware Tools | EXE | `setup64.exe /S /v "/qn REBOOT=R"` | InstallShield; `ADDLOCAL=ALL` für alle Komponenten. | – |
| Remote Desktop Client (MSRDC) | MSI | `msiexec.exe /i RemoteDesktop_x64.msi /qn ALLUSERS=1` | Per-Machine-Installation. | – |
| PuTTY | MSI | `msiexec.exe /i putty-64bit-installer.msi /qn /norestart` | – | [installPuTTY.ps1](installPuTTY.ps1) |
| WinSCP | EXE | `WinSCP-Setup.exe /VERYSILENT /ALLUSERS /NORESTART /SUPPRESSMSGBOXES` | Inno Setup; `/CURRENTUSER` für Benutzerinstallation. | [installWinSCP.ps1](installWinSCP.ps1) |
| FileZilla Client | EXE | `FileZilla_win64-setup.exe /S /user=all` | NSIS. | – |
| mRemoteNG | MSI | `msiexec.exe /i mRemoteNG.msi /qn /norestart` | – | – |

### Laufzeiten und Frameworks / Runtimes and frameworks

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Visual C++ Redistributable 2015–2022 | EXE (Burn) | `VC_redist.x64.exe /install /quiet /norestart` | x86-Variante für 32-Bit-Programme zusätzlich installieren. | [installVcRedistX64.ps1](installVcRedistX64.ps1) |
| Visual C++ 2010 / 2012 / 2013 | EXE | 2010: `vcredist_x64.exe /q /norestart`; 2012/2013: `vcredist_x64.exe /install /quiet /norestart` | Nicht mehr unterstützt – nur bei Bedarf. | – |
| .NET Desktop Runtime / ASP.NET Core / .NET Runtime | EXE (Burn) | `windowsdesktop-runtime-<ver>-win-x64.exe /install /quiet /norestart` | Gleiche Schalter für alle .NET-Runtimes. | [installDotNetDesktopRuntime10.ps1](installDotNetDesktopRuntime10.ps1) |
| .NET Framework 4.8 / 4.8.1 | EXE | `ndp48-x86-x64-allos-enu.exe /q /norestart` | Rückgabe `3010` → Neustart erforderlich. | – |
| Eclipse Temurin JRE/JDK | MSI | `msiexec.exe /i OpenJDK21U-jre_x64_windows_hotspot.msi /qn ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` | `INSTALLDIR="…"` für eigenen Pfad. | [installTemurinJre21.ps1](installTemurinJre21.ps1) |
| Oracle Java 8 (JRE) | EXE | `jre-8u<ver>-windows-x64.exe /s INSTALL_SILENT=1 AUTO_UPDATE=0 REBOOT=0` | Alternativ `INSTALLCFG="C:\Temp\java.cfg"`. **Lizenzpflichtig** für kommerzielle Nutzung. | – |
| Python 3 | EXE | `python-3.<ver>-amd64.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0` | Deinstallation mit demselben Installer: `/uninstall /quiet`. | – |
| Node.js | MSI | `msiexec.exe /i node-v<ver>-x64.msi /qn /norestart` | – | – |
| PowerShell 7 | MSI | `msiexec.exe /i PowerShell-7-win-x64.msi /qn ADD_PATH=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1` | Optional `ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1`, `ENABLE_PSREMOTING=1`. | [installPowerShell7.ps1](installPowerShell7.ps1) |

### Admin- und Entwickler-Tools / Admin and developer tools

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Visual Studio Code (System) | EXE | `VSCodeSetup-x64.exe /VERYSILENT /NORESTART /MERGETASKS=!runcode` | System-Installer verwenden (nicht User-Setup). | [installVisualStudioCode.ps1](installVisualStudioCode.ps1) |
| Git for Windows | EXE | `Git-<ver>-64-bit.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES` | Optionen per `/LOADINF="git.inf"`. | [installGit.ps1](installGit.ps1) |
| Notepad++ | EXE | `npp.<ver>.Installer.x64.exe /S` | NSIS; Deinstallation `"C:\Program Files\Notepad++\uninstall.exe" /S`. | [installNotepadPlusPlus.ps1](installNotepadPlusPlus.ps1) |
| KeePassXC | MSI | `msiexec.exe /i KeePassXC-<ver>-Win64.msi /qn /norestart` | – | [installKeePassXC.ps1](installKeePassXC.ps1) |
| KeePass 2 | EXE / MSI | `KeePass-<ver>-Setup.exe /VERYSILENT /NORESTART` bzw. `msiexec.exe /i KeePass-<ver>.msi /qn` | Inno Setup. | – |
| Bitwarden Desktop | EXE | `Bitwarden-Installer.exe /allusers /S` | NSIS. | – |
| Microsoft PowerToys (Machine) | EXE (Burn) | `PowerToysSetup-x64.exe /quiet /norestart` | Machine-Wide-Installer verwenden. | – |
| Visual Studio 2022 | EXE | `vs_enterprise.exe --quiet --wait --norestart --add Microsoft.VisualStudio.Workload.ManagedDesktop` | `--wait` ist nötig, damit der Rückgabecode stimmt. | – |
| SQL Server Management Studio ≤ 20 | EXE | `SSMS-Setup-ENU.exe /install /quiet /norestart` | Ab SSMS 21 Visual-Studio-Installer (`--quiet --wait`). | – |
| Docker Desktop | EXE | `"Docker Desktop Installer.exe" install --quiet --accept-license` | Benötigt WSL2/Hyper-V und Lizenz für größere Unternehmen. | – |
| Azure CLI / AWS CLI | MSI | `msiexec.exe /i azure-cli.msi /qn` bzw. `msiexec.exe /i AWSCLIV2.msi /qn` | – | – |
| Wireshark | EXE | `Wireshark-<ver>-x64.exe /S /desktopicon=no` | Npcap ist nur in der OEM-Edition silent installierbar. | – |
| Sysinternals Suite | ZIP | Entpacken nach `C:\Program Files\Sysinternals`; Tools mit `-accepteula` starten. | Kein Installer. | – |
| TreeSize Free | EXE | `TreeSizeFreeSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` | Inno Setup. | [installTreeSizeFree.ps1](installTreeSizeFree.ps1) |
| Everything (voidtools) | EXE | `Everything-<ver>.x64-Setup.exe /S` | NSIS. | – |
| Microsoft Power BI Desktop | EXE | `PBIDesktopSetup_x64.exe -quiet -norestart ACCEPT_EULA=1` | – | – |

### Werkzeuge und Multimedia / Utilities and multimedia

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| 7-Zip | EXE / MSI | `7z<ver>-x64.exe /S` bzw. `msiexec.exe /i 7z<ver>-x64.msi /qn` | NSIS; Zielordner `/D=C:\Program Files\7-Zip` (letzter Parameter). | [install7Zip.ps1](install7Zip.ps1) |
| VLC media player | EXE / MSI | `vlc-<ver>-win64.exe /L=1031 /S` bzw. `msiexec.exe /i vlc-<ver>-win64.msi /qn` | `/L=1031` = Deutsch. | [installVlcMediaPlayer.ps1](installVlcMediaPlayer.ps1) |
| Greenshot | EXE | `Greenshot-INSTALLER-<ver>.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Inno Setup. | [installGreenshot.ps1](installGreenshot.ps1) |
| ShareX | EXE | `ShareX-<ver>-setup.exe /VERYSILENT /NORESTART` | Inno Setup. | – |
| IrfanView | EXE | `iview<ver>_x64_setup.exe /silent /desktop=0 /thumbs=0 /group=1 /allusers=1 /assoc=1` | Plugins separat: `/silent`. | – |
| paint.net | EXE | `paint.net.<ver>.install.x64.exe /auto` | MSI erzeugen: `/createMsi`. | – |
| GIMP | EXE | `gimp-<ver>-setup.exe /VERYSILENT /NORESTART /ALLUSERS` | Inno Setup. | – |
| Audacity | EXE | `audacity-win-<ver>-64bit.exe /VERYSILENT /NORESTART` | Inno Setup. | – |

### Hersteller-Tools / OEM tools

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Dell Command \| Update | EXE | `Dell-Command-Update-Application_<ver>.EXE /s` | Danach z. B. `dcu-cli.exe /applyUpdates -reboot=disable`. | – |
| Lenovo System Update | EXE | `system_update_<ver>.exe /VERYSILENT /NORESTART` | Inno Setup. | – |
| HP Image Assistant | EXE | `hp-hpia-<ver>.exe /s /e /f "C:\HPIA"` | Entpackt das Tool; danach `HPImageAssistant.exe /Operation:Analyze /Action:Install /Silent`. | – |

## winget-IDs der Skripte / winget IDs of the scripts

Alle Skripte nutzen standardmäßig winget (`installSource = Winget`) mit `--scope machine`. Die IDs wurden gegen
[microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) geprüft.
*All scripts use winget by default with `--scope machine`; IDs were checked against microsoft/winget-pkgs.*

| Skript / Script | winget-ID | Standardargumente bei Datei-Quelle / Default arguments for file source |
| --- | --- | --- |
| [install7Zip.ps1](install7Zip.ps1) | `7zip.7zip` | EXE `/S`; MSI `/qn /norestart` |
| [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) | `Adobe.Acrobat.Reader.64-bit` | EXE `/sAll /rs /msi EULA_ACCEPT=YES`; MSI `EULA_ACCEPT=YES` |
| [installAnyDesk.ps1](installAnyDesk.ps1) | `AnyDesk.AnyDesk` | EXE `--install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon` |
| [installCitrixWorkspace.ps1](installCitrixWorkspace.ps1) | `Citrix.Workspace` | EXE `/silent /noreboot /AutoUpdateCheck=disabled` |
| [installDotNetDesktopRuntime10.ps1](installDotNetDesktopRuntime10.ps1) | `Microsoft.DotNet.DesktopRuntime.10` | EXE `/install /quiet /norestart` |
| [installGit.ps1](installGit.ps1) | `Git.Git` | EXE `/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES` |
| [installGoogleChrome.ps1](installGoogleChrome.ps1) | `Google.Chrome` | EXE `/silent /install`; MSI `/qn /norestart` |
| [installGreenshot.ps1](installGreenshot.ps1) | `Greenshot.Greenshot` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installKeePassXC.ps1](installKeePassXC.ps1) | `KeePassXCTeam.KeePassXC` | MSI `/qn /norestart` |
| [installLibreOffice.ps1](installLibreOffice.ps1) | `TheDocumentFoundation.LibreOffice` | MSI `CREATEDESKTOPLINK=0 REGISTER_NO_MSO_TYPES=1 ISCHECKFORPRODUCTUPDATES=0 QUICKSTART=0 RebootYesNo=No` |
| [installMozillaFirefox.ps1](installMozillaFirefox.ps1) | `Mozilla.Firefox.de` | EXE `/S /PreventRebootRequired=true`; MSI `/qn /norestart` |
| [installMozillaThunderbird.ps1](installMozillaThunderbird.ps1) | `Mozilla.Thunderbird.de` | EXE `/S`; MSI `/qn /norestart` |
| [installNotepadPlusPlus.ps1](installNotepadPlusPlus.ps1) | `Notepad++.Notepad++` | EXE `/S` |
| [installPdf24Creator.ps1](installPdf24Creator.ps1) | `geeksoftwareGmbH.PDF24Creator` | EXE `/VERYSILENT /NORESTART /NOUPDATE`; MSI `/qn /norestart` |
| [installPowerShell7.ps1](installPowerShell7.ps1) | `Microsoft.PowerShell` | MSI `ADD_PATH=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1` |
| [installPuTTY.ps1](installPuTTY.ps1) | `PuTTY.PuTTY` | MSI `/qn /norestart` |
| [installTeamViewer.ps1](installTeamViewer.ps1) | `TeamViewer.TeamViewer` | EXE `/S` |
| [installTemurinJre21.ps1](installTemurinJre21.ps1) | `EclipseAdoptium.Temurin.21.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTreeSizeFree.ps1](installTreeSizeFree.ps1) | `JAMSoftware.TreeSize.Free` | EXE `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| [installVcRedistX64.ps1](installVcRedistX64.ps1) | `Microsoft.VCRedist.2015+.x64` | EXE `/install /quiet /norestart` |
| [installVisualStudioCode.ps1](installVisualStudioCode.ps1) | `Microsoft.VisualStudioCode` | EXE `/VERYSILENT /NORESTART /MERGETASKS=!runcode` |
| [installVlcMediaPlayer.ps1](installVlcMediaPlayer.ps1) | `VideoLAN.VLC` | EXE `/L=1031 /S`; MSI `/qn /norestart` |
| [installWinSCP.ps1](installWinSCP.ps1) | `WinSCP.WinSCP` | EXE `/VERYSILENT /ALLUSERS /NORESTART /SUPPRESSMSGBOXES` |
| [installWireGuard.ps1](installWireGuard.ps1) | `WireGuard.WireGuard` | MSI `DO_NOT_LAUNCH=1` |
| [installZoomWorkplace.ps1](installZoomWorkplace.ps1) | `Zoom.Zoom` | MSI `/qn /norestart` |

MSI-Pakete werden von den Skripten immer mit `/i "<datei>" /qn /norestart /l*v "<log>"` aufgerufen; die Tabelle nennt die
zusätzlichen Eigenschaften. `installerArguments` ersetzt die Standardargumente (bei MSI nur die zusätzlichen Eigenschaften).
*MSI packages are always started with `/i "<file>" /qn /norestart /l*v "<log>"`; the table lists the additional properties.
`installerArguments` replaces the default arguments (for MSI only the additional properties).*

Weitere nützliche IDs / Further useful IDs: `Microsoft.Edge`, `Microsoft.EdgeWebView2Runtime`, `Microsoft.Teams`,
`Microsoft.OneDrive`, `Microsoft.PowerToys`, `Python.Python.3.13`, `OpenJS.NodeJS.LTS`, `WiresharkFoundation.Wireshark`,
`voidtools.Everything`, `ShareX.ShareX`, `IrfanSkiljan.IrfanView`, `dotPDN.PaintDotNet`, `GIMP.GIMP`, `Audacity.Audacity`,
`mRemoteNG.mRemoteNG`, `Bitwarden.Bitwarden`, `DominikReichl.KeePass`, `Foxit.FoxitReader`,
`Cisco.Webex`, `OpenVPNTechnologies.OpenVPN`, `Microsoft.AzureCLI`, `Amazon.AWSCLI`, `Dell.CommandUpdate`. Vor Verwendung mit
`winget show --id <Id> --exact` prüfen. *Verify with `winget show --id <Id> --exact` before use.*

## Deinstallation / Uninstall

| Methode / Method | Befehl / Command | Hinweise / Notes |
| --- | --- | --- |
| Registry-Eintrag lesen / Read registry | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` und `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*` | `QuietUninstallString` bevorzugen, sonst `UninstallString` mit Silent-Schalter ergänzen. |
| MSI | `msiexec.exe /x {ProductCode} /qn /norestart /l*v "C:\Windows\Temp\uninstall.log"` | Produktcode aus `PSChildName` des Uninstall-Schlüssels. |
| Inno Setup | `"C:\Program Files\<App>\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` | – |
| NSIS | `"C:\Program Files\<App>\uninstall.exe" /S _?=C:\Program Files\<App>` | `_?=` sorgt dafür, dass auf das Ende gewartet wird (Ordner danach manuell entfernen). |
| WiX Burn | `"C:\ProgramData\Package Cache\{GUID}\bundle.exe" /uninstall /quiet /norestart` | – |
| Google Chrome | `"C:\Program Files\Google\Chrome\Application\<ver>\Installer\setup.exe" --uninstall --system-level --force-uninstall` | Bei MSI-Installation `msiexec /x`. |
| Mozilla Firefox / Thunderbird | `"C:\Program Files\Mozilla Firefox\uninstall\helper.exe" /S` | – |
| Microsoft 365 Apps | `setup.exe /configure remove.xml` mit `<Remove All="TRUE" />` | Office Deployment Tool. |
| winget | `winget uninstall --id <Id> --exact --silent` | Als `SYSTEM` vollständigen Pfad zu `winget.exe` verwenden. |
| AppX/MSIX | `Get-AppxProvisionedPackage -Online` → `Remove-AppxProvisionedPackage`; `Get-AppxPackage -AllUsers` → `Remove-AppxPackage -AllUsers` | – |

Die Skripte im Ordner `08 - Cleanup` übernehmen die Deinstallation geprüft (Opt-in, `-WhatIf`, Bericht).
*The scripts in `08 - Cleanup` perform uninstalls in a controlled way (opt-in, `-WhatIf`, report).*

## Typische Fehler / Common pitfalls

| Problem (DE) | Problem (EN) | Lösung / Solution |
| --- | --- | --- |
| Installation hängt unsichtbar (Dialog im Session-0-Kontext). | Install hangs invisibly (dialog in session 0). | Silent-Schalter prüfen, `TimeoutMinutes` setzen, Log auswerten. |
| Rückgabe `1618`. | Exit code `1618`. | Andere Installation (z. B. Windows Update) abwarten und erneut ausführen. |
| Programm nur für den Benutzer `SYSTEM` installiert. | Program installed only for the `SYSTEM` user. | Per-Machine-Installer bzw. `ALLUSERS=1`, `/ALLUSERS`, `--scope machine` verwenden. |
| NSIS ignoriert `/s`. | NSIS ignores `/s`. | Großes `/S` verwenden. |
| `/D=` bei NSIS wirkt nicht. | NSIS `/D=` has no effect. | Als letzten Parameter ohne Anführungszeichen angeben. |
| EXE kehrt sofort zurück, Installation läuft weiter. | EXE returns immediately while installing. | MSI verwenden oder Herstelleroption zum Warten (`--wait`, `_?=`) nutzen; danach Erkennung prüfen (die Skripte prüfen die Registry nach der Installation erneut). |
| winget als `SYSTEM` nicht gefunden. | winget not found as `SYSTEM`. | Vollständigen Pfad unter `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*` verwenden; App Installer aktuell halten (siehe `03 - Software/checkWingetStatus.ps1`). |
