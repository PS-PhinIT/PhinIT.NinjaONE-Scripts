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
| Microsoft Edge | MSI (Enterprise) | `msiexec.exe /i MicrosoftEdgeEnterpriseX64.msi /qn /norestart` | In Windows 10/11 enthalten; MSI für Server/Kanalwechsel. | [installMicrosoftEdge.ps1](installMicrosoftEdge.ps1) |
| Microsoft Edge WebView2 | EXE (Evergreen) | `MicrosoftEdgeWebview2Setup.exe /silent /install` | Standalone-Variante: `MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install`. | [installMicrosoftEdgeWebView2.ps1](installMicrosoftEdgeWebView2.ps1) |
| Brave | EXE | `BraveBrowserStandaloneSilentSetup.exe` | Die „StandaloneSilent“-Variante installiert ohne Schalter. | [installBraveBrowser.ps1](installBraveBrowser.ps1) |
| Mozilla Firefox ESR | MSI / EXE | `msiexec.exe /i Firefox_Setup_ESR_de.msi /qn /norestart` bzw. `setup.exe /S /PreventRebootRequired=true` | Extended Support Release (deutsch) für Unternehmen; nicht parallel zur Standardversion (installMozillaFirefox.ps1) verteilen. | [installMozillaFirefoxEsr.ps1](installMozillaFirefoxEsr.ps1) |

### Office, PDF und Kommunikation / Office, PDF and communication

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Microsoft 365 Apps / Office LTSC / Visio / Project | Office Deployment Tool | `setup.exe /configure configuration.xml` | XML mit [config.office.com](https://config.office.com) erstellen; `<Display Level="None" AcceptEULA="TRUE" />`. Vorab laden: `setup.exe /download configuration.xml`. Das Skript lädt `setup.exe` standardmäßig signaturgeprüft von `officecdn.microsoft.com` (`installSource = Download`), da winget bei `Microsoft.Office` oft „Installer hash does not match“ meldet; `--override` bzw. `installerArguments` braucht `/configure <Rohdaten-URL oder Pfad>`. | [installMicrosoft365Apps.ps1](installMicrosoft365Apps.ps1) |
| Microsoft Teams (neu / new) | Bootstrapper | `teamsbootstrapper.exe -p` | Provisioniert für alle Benutzer. Offline: `teamsbootstrapper.exe -p -o "C:\Temp\MSTeams-x64.msix"`. Entfernen: `teamsbootstrapper.exe -x`. | – |
| Microsoft OneDrive | EXE | `OneDriveSetup.exe /allusers /silent` | Per-Machine-Installation unter `C:\Program Files\Microsoft OneDrive`. | [installMicrosoftOneDrive.ps1](installMicrosoftOneDrive.ps1) |
| Adobe Acrobat Reader | EXE | `AcroRdrDCx64<ver>.exe /sAll /rs /msi EULA_ACCEPT=YES` | `/sAll` = Silent, `/rs` = kein Neustart; Anpassung per Adobe Customization Wizard (`.mst`). | [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) |
| Adobe Acrobat Reader | MSI | `msiexec.exe /i AcroRead.msi EULA_ACCEPT=YES /qn /norestart` | MSI aus dem EXE extrahiert bzw. Enterprise-Download. | [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) |
| PDF24 Creator | MSI | `msiexec.exe /i pdf24-creator.msi AUTOUPDATE=No DESKTOPICONS=No /qn /norestart` | Weitere Eigenschaft z. B. `REGISTERREADER=No`. | [installPdf24Creator.ps1](installPdf24Creator.ps1) |
| PDF24 Creator | EXE | `pdf24-creator.exe /VERYSILENT /NORESTART /NOUPDATE` | Inno Setup. | [installPdf24Creator.ps1](installPdf24Creator.ps1) |
| Foxit PDF Reader | MSI | `msiexec.exe /i FoxitPDFReader.msi /qn /norestart` | Enterprise-MSI vom Hersteller. | [installFoxitPdfReader.ps1](installFoxitPdfReader.ps1) |
| LibreOffice | MSI | `msiexec.exe /i LibreOffice_x64.msi /qn /norestart ALLUSERS=1 CREATEDESKTOPLINK=0 REGISTER_NO_MSO_TYPES=1 ISCHECKFORPRODUCTUPDATES=0 QUICKSTART=0 RebootYesNo=No` | `UI_LANGS=de` begrenzt Sprachen; `REGISTER_ALL_MSO_TYPES=1` übernimmt Office-Dateitypen. | [installLibreOffice.ps1](installLibreOffice.ps1) |
| Mozilla Thunderbird | EXE / MSI | `Thunderbird Setup.exe /S` bzw. `msiexec.exe /i "Thunderbird Setup.msi" /qn` | Gleiche Optionen wie Firefox. | [installMozillaThunderbird.ps1](installMozillaThunderbird.ps1) |
| Zoom Workplace | MSI | `msiexec.exe /i ZoomInstallerFull.msi /qn /norestart ZoomAutoUpdate=true ZNoDesktopShortCut=true` | Weitere Einstellungen per `ZConfig="…"` bzw. `ZRecommend="…"`. | [installZoomWorkplace.ps1](installZoomWorkplace.ps1) |
| Cisco Webex App | MSI | `msiexec.exe /i Webex.msi ACCEPT_EULA=TRUE ALLUSERS=1 AUTOSTART_WITH_WINDOWS=false /qn` | Per-Machine-Installation. | [installCiscoWebex.ps1](installCiscoWebex.ps1) |
| Slack | MSI | `msiexec.exe /i slack-standalone-x64.msi /qn` | MSI für Per-Machine-Bereitstellung verwenden (das EXE ist Squirrel). | – |
| Foxit PDF Editor | MSI / EXE | `msiexec.exe /i FoxitPDFEditor_de.msi /qn /norestart` bzw. `setup.exe /quiet /norestart` | Lizenzpflichtig; Aktivierung gemäß Foxit-Admin-Handbuch (MSI-Eigenschaften über installerArguments). Erkennt auch Foxit PhantomPDF. | [installFoxitPdfEditor.ps1](installFoxitPdfEditor.ps1) |
| PDF-XChange Editor | MSI / EXE | `msiexec.exe /i EditorV10.x64.msi /qn /norestart` bzw. `setup.exe /quiet /norestart` | Anzeigen kostenlos, Bearbeitungsfunktionen lizenzpflichtig; Lizenzschlüssel gemäß Herstellerdokumentation per installerArguments. | [installPdfXChangeEditor.ps1](installPdfXChangeEditor.ps1) |
| PDFsam Basic | MSI | `msiexec.exe /i pdfsam-basic-windows.msi /qn /norestart SKIPTHANKSPAGE=Yes` | Java-Laufzeit ist enthalten; SKIPTHANKSPAGE=Yes unterdrückt die Dankeseite im Browser. | [installPdfsamBasic.ps1](installPdfsamBasic.ps1) |
| ONLYOFFICE Desktop Editors | MSI / EXE | `msiexec.exe /i DesktopEditors_x64.msi /qn /norestart` bzw. `setup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Office-Suite (DOCX/XLSX/PPTX); EXE ist Inno Setup, MSI für Softwareverteilung. | [installOnlyOfficeDesktopEditors.ps1](installOnlyOfficeDesktopEditors.ps1) |
| eM Client | MSI | `msiexec.exe /i setup-emclient.msi /qn /norestart` | E-Mail-/Kalender-Client; Lizenz (Pro/Business) wird in der Anwendung hinterlegt. | [installEmClient.ps1](installEmClient.ps1) |
| Power Automate for desktop | EXE | `Setup.Microsoft.PowerAutomate.exe -Silent -ACCEPTEULA` | RPA-Werkzeug von Microsoft; Anmeldung/Lizenz über Microsoft Entra ID, Maschinenregistrierung separat. | [installPowerAutomateDesktop.ps1](installPowerAutomateDesktop.ps1) |
| Cisco Jabber | MSI | `msiexec.exe /i CiscoJabberSetup.msi /qn /norestart` | Servereinstellungen per MSI-Eigenschaften (z. B. AUTHENTICATOR=, SERVICES_DOMAIN=) über installerArguments. | [installCiscoJabber.ps1](installCiscoJabber.ps1) |
| GoTo Meeting | MSI | `msiexec.exe /i G2MSetup.msi /qn /norestart G2MINSTALLFORALLUSERS=1` | G2MINSTALLFORALLUSERS=1 installiert maschinenweit statt pro Benutzer. | [installGoToMeeting.ps1](installGoToMeeting.ps1) |
| Zoom Outlook Plugin | MSI | `msiexec.exe /i ZoomOutlookPluginSetup.msi /qn /norestart` | Klassisches COM-Add-In für Outlook; für Outlook (neu) das Zoom-Web-Add-In über Microsoft 365 verteilen. | [installZoomOutlookPlugin.ps1](installZoomOutlookPlugin.ps1) |
| Mattermost | MSI | `msiexec.exe /i mattermost-desktop-x64.msi /qn /norestart` | Per-Machine-MSI; Serverliste per Richtlinie (Registry) vorgeben. | [installMattermostDesktop.ps1](installMattermostDesktop.ps1) |
| Nextcloud Desktop | MSI | `msiexec.exe /i Nextcloud-x64.msi /qn /norestart` | Optional SKIPAUTOUPDATE=1 per installerArguments (Updates über NinjaOne); Neustart für die Explorer-Integration ggf. erforderlich. | [installNextcloudDesktop.ps1](installNextcloudDesktop.ps1) |
| Dropbox | EXE | `DropboxOfflineInstaller.x64.exe /S` | Offline-Installer (NSIS) installiert maschinenweit; Anmeldung erfolgt durch den Benutzer. | [installDropbox.ps1](installDropbox.ps1) |
| Google Drive | EXE | `GoogleDriveSetup.exe --silent --skip_launch_new --gsuite_shortcuts=false` | Google Drive for desktop; --gsuite_shortcuts=false verhindert Desktop-Verknüpfungen für Docs/Sheets/Slides. | [installGoogleDrive.ps1](installGoogleDrive.ps1) |
| Box Drive | MSI | `msiexec.exe /i Box-x64.msi /qn /norestart` | Box Drive (Per-Machine-MSI); Box Tools/Box Edit sind eigene Pakete. | [installBoxDrive.ps1](installBoxDrive.ps1) |
| draw.io | EXE | `draw.io-windows-installer.exe /S /allusers` | Diagramm-Werkzeug (Electron, NSIS); /allusers installiert maschinenweit. | [installDrawIo.ps1](installDrawIo.ps1) |

### Fernwartung, VPN und Remote / Remote access and VPN

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| TeamViewer (Full) | EXE | `TeamViewer_Setup_x64.exe /S` | NSIS; Deinstallation `"C:\Program Files\TeamViewer\uninstall.exe" /S`. | [installTeamViewer.ps1](installTeamViewer.ps1) |
| TeamViewer Host | MSI | `msiexec.exe /i TeamViewer_Host.msi /qn CUSTOMCONFIGID=<ID> APITOKEN=<Token> ASSIGNMENTOPTIONS="--grant-easy-access"` | Token **nicht** im Skript hinterlegen, sondern als geschützte Variable übergeben. | [installTeamViewerHost.ps1](installTeamViewerHost.ps1) |
| AnyDesk | EXE | `AnyDesk.exe --install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon` | Optional `--update-disabled`; Deinstallation `AnyDesk.exe --silent --remove`. | [installAnyDesk.ps1](installAnyDesk.ps1) |
| WireGuard | MSI | `msiexec.exe /i wireguard-amd64.msi /qn DO_NOT_LAUNCH=1` | Verhindert den Start der Oberfläche nach der Installation. | [installWireGuard.ps1](installWireGuard.ps1) |
| OpenVPN (Community) | MSI | `msiexec.exe /i OpenVPN-amd64.msi /qn /norestart` | Komponenten per `ADDLOCAL=`. | [installOpenVpn.ps1](installOpenVpn.ps1) |
| FortiClient VPN | MSI / EXE | `msiexec.exe /i FortiClient.msi /quiet /norestart` bzw. `FortiClientSetup.exe /quiet /norestart` | Nicht in winget – nur über Datei-Quelle. | – |
| Cisco Secure Client (AnyConnect) | MSI | `msiexec.exe /package cisco-secure-client-win-<ver>-core-vpn-predeploy-k9.msi /qn /norestart PRE_DEPLOY_DISABLE_VPN=0` | Module (DART, Umbrella …) als eigene MSI-Pakete. | – |
| Citrix Workspace App | EXE | `CitrixWorkspaceApp.exe /silent /noreboot /AutoUpdateCheck=disabled` | Optional `/includeSSON`, `/forceinstall`; Deinstallation `/uninstall /silent`. | [installCitrixWorkspace.ps1](installCitrixWorkspace.ps1) |
| Omnissa (VMware) Horizon Client | EXE | `Horizon-Client.exe /silent /norestart VDM_SERVER=<server>` | – | [installOmnissaHorizonClient.ps1](installOmnissaHorizonClient.ps1) |
| VMware Tools | EXE | `setup64.exe /S /v "/qn REBOOT=R"` | InstallShield; `ADDLOCAL=ALL` für alle Komponenten. | – |
| Remote Desktop Client (MSRDC) | MSI | `msiexec.exe /i RemoteDesktop_x64.msi /qn ALLUSERS=1` | Per-Machine-Installation. | – |
| PuTTY | MSI | `msiexec.exe /i putty-64bit-installer.msi /qn /norestart` | – | [installPuTTY.ps1](installPuTTY.ps1) |
| WinSCP | EXE | `WinSCP-Setup.exe /VERYSILENT /ALLUSERS /NORESTART /SUPPRESSMSGBOXES` | Inno Setup; `/CURRENTUSER` für Benutzerinstallation. | [installWinSCP.ps1](installWinSCP.ps1) |
| FileZilla Client | EXE | `FileZilla_win64-setup.exe /S /user=all` | NSIS. | – |
| mRemoteNG | MSI | `msiexec.exe /i mRemoteNG.msi /qn /norestart` | – | [installMRemoteNG.ps1](installMRemoteNG.ps1) |
| OpenVPN Connect | MSI | `msiexec.exe /i openvpn-connect-windows.msi /qn /norestart` | Client für OpenVPN Access Server/CloudConnexa; Profile werden getrennt verteilt. | [installOpenVpnConnect.ps1](installOpenVpnConnect.ps1) |
| Tailscale | MSI / EXE | `msiexec.exe /i tailscale-setup-amd64.msi /qn /norestart` bzw. `setup.exe /install /quiet /norestart` | Anmeldung/Auth-Key nicht in Skriptvariablen ablegen; MSI-Eigenschaften (z. B. TS_UNATTENDEDMODE) gemäß Tailscale-Dokumentation. | [installTailscale.ps1](installTailscale.ps1) |
| RealVNC Viewer | MSI | `msiexec.exe /i VNC-Viewer-Windows-64bit.msi /qn /norestart` | Nur der Viewer; RealVNC Server ist ein eigenes, lizenzpflichtiges Paket. | [installRealVncViewer.ps1](installRealVncViewer.ps1) |
| Remote Desktop Manager | MSI | `msiexec.exe /i Setup.RemoteDesktopManager.msi /qn /norestart` | Devolutions RDM; Lizenz/Datenquelle (Devolutions Server/Hub) per Richtlinie bzw. in der Anwendung. | [installRemoteDesktopManager.ps1](installRemoteDesktopManager.ps1) |
| Royal TS V7 | MSI | `msiexec.exe /i RoyalTSInstaller_7.x64.msi /qn /norestart` | Lizenzpflichtig (Lizenz in der Anwendung bzw. per Dokument); Hauptversion ist in der winget-ID enthalten. | [installRoyalTs.ps1](installRoyalTs.ps1) |
| Splashtop Business | MSI | `msiexec.exe /i Splashtop_Business_Win_INSTALLER.msi /qn /norestart` | Client-App für Splashtop Business Access; der Streamer (Zielgerät) ist ein eigenes Paket. | [installSplashtopBusiness.ps1](installSplashtopBusiness.ps1) |
| MobaXterm | MSI | `msiexec.exe /i MobaXterm_installer.msi /qn /norestart` | Installer-Edition (MSI aus dem ZIP); Professional-Lizenz per Custom-Datei möglich. | [installMobaXterm.ps1](installMobaXterm.ps1) |
| SonicWall NetExtender | MSI / EXE | `msiexec.exe /i NetExtender-x64.msi /qn /norestart` bzw. `setup.exe /S` | SSL-VPN-Client für SonicWall-Firewalls; Verbindungsprofil per MSI-Eigenschaften (z. B. SERVER=, DOMAIN=) laut Herstellerdokumentation. | [installSonicWallNetExtender.ps1](installSonicWallNetExtender.ps1) |
| Microsoft Remote Help | EXE | `remotehelpinstaller.exe acceptTerms=1 /quiet /norestart` | Intune-Remote-Help (Lizenz erforderlich); benötigt die WebView2-Laufzeit (installMicrosoftEdgeWebView2.ps1). | [installMicrosoftRemoteHelp.ps1](installMicrosoftRemoteHelp.ps1) |

### Laufzeiten und Frameworks / Runtimes and frameworks

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Visual C++ Redistributable 2015–2022 | EXE (Burn) | `VC_redist.x64.exe /install /quiet /norestart` | x86-Variante für 32-Bit-Programme zusätzlich installieren. | [installVcRedistX64.ps1](installVcRedistX64.ps1), [installVcRedistX86.ps1](installVcRedistX86.ps1) |
| Visual C++ 2010 / 2012 / 2013 | EXE | 2010: `vcredist_x64.exe /q /norestart`; 2012/2013: `vcredist_x64.exe /install /quiet /norestart` | Nicht mehr unterstützt – nur bei Bedarf. | [installVcRedist2013X64.ps1](installVcRedist2013X64.ps1) |
| .NET Desktop Runtime / ASP.NET Core / .NET Runtime | EXE (Burn) | `windowsdesktop-runtime-<ver>-win-x64.exe /install /quiet /norestart` | Gleiche Schalter für alle .NET-Runtimes. | [installDotNetDesktopRuntime8.ps1](installDotNetDesktopRuntime8.ps1), [installDotNetDesktopRuntime10.ps1](installDotNetDesktopRuntime10.ps1), [installDotNetRuntime8.ps1](installDotNetRuntime8.ps1), [installDotNetRuntime10.ps1](installDotNetRuntime10.ps1), [installDotNetAspNetCoreRuntime8.ps1](installDotNetAspNetCoreRuntime8.ps1), [installDotNetAspNetCoreRuntime10.ps1](installDotNetAspNetCoreRuntime10.ps1), [installDotNetHostingBundle8.ps1](installDotNetHostingBundle8.ps1), [installDotNetHostingBundle10.ps1](installDotNetHostingBundle10.ps1) |
| .NET Framework 4.8 / 4.8.1 | EXE | `ndp48-x86-x64-allos-enu.exe /q /norestart` | Rückgabe `3010` → Neustart erforderlich. | – |
| Eclipse Temurin JRE/JDK | MSI | `msiexec.exe /i OpenJDK21U-jre_x64_windows_hotspot.msi /qn ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` | `INSTALLDIR="…"` für eigenen Pfad. | [installTemurinJre8.ps1](installTemurinJre8.ps1), [installTemurinJre11.ps1](installTemurinJre11.ps1), [installTemurinJre17.ps1](installTemurinJre17.ps1), [installTemurinJre21.ps1](installTemurinJre21.ps1), [installTemurinJre25.ps1](installTemurinJre25.ps1), [installTemurinJdk21.ps1](installTemurinJdk21.ps1) |
| Oracle Java 8 (JRE) | EXE | `jre-8u<ver>-windows-x64.exe /s INSTALL_SILENT=1 AUTO_UPDATE=0 REBOOT=0` | Alternativ `INSTALLCFG="C:\Temp\java.cfg"`. **Lizenzpflichtig** für kommerzielle Nutzung. | – |
| Python 3 | EXE | `python-3.<ver>-amd64.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0` | Deinstallation mit demselben Installer: `/uninstall /quiet`. | [installPython314.ps1](installPython314.ps1) |
| Node.js | MSI | `msiexec.exe /i node-v<ver>-x64.msi /qn /norestart` | – | [installNodeJsLts.ps1](installNodeJsLts.ps1) |
| PowerShell 7 | MSI | `msiexec.exe /i PowerShell-7-win-x64.msi /qn ADD_PATH=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1` | Optional `ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1`, `ENABLE_PSREMOTING=1`. | [installPowerShell7.ps1](installPowerShell7.ps1) |
| Microsoft ODBC Driver 18 for SQL Server | MSI | `msiexec.exe /i msodbcsql.msi /qn /norestart IACCEPTMSODBCSQLLICENSETERMS=YES` | Datenbanktreiber für Business-Anwendungen (ERP/CRM); IACCEPTMSODBCSQLLICENSETERMS=YES ist Pflicht. Treiber 17 bleibt parallel bestehen. | [installMsOdbcSql18.ps1](installMsOdbcSql18.ps1) |

### Admin- und Entwickler-Tools / Admin and developer tools

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Visual Studio Code (System) | EXE | `VSCodeSetup-x64.exe /VERYSILENT /NORESTART /MERGETASKS=!runcode` | System-Installer verwenden (nicht User-Setup). | [installVisualStudioCode.ps1](installVisualStudioCode.ps1) |
| Git for Windows | EXE | `Git-<ver>-64-bit.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES` | Optionen per `/LOADINF="git.inf"`. | [installGit.ps1](installGit.ps1) |
| Notepad++ | EXE | `npp.<ver>.Installer.x64.exe /S` | NSIS; Deinstallation `"C:\Program Files\Notepad++\uninstall.exe" /S`. | [installNotepadPlusPlus.ps1](installNotepadPlusPlus.ps1) |
| KeePassXC | MSI | `msiexec.exe /i KeePassXC-<ver>-Win64.msi /qn /norestart` | – | [installKeePassXC.ps1](installKeePassXC.ps1) |
| KeePass 2 | EXE / MSI | `KeePass-<ver>-Setup.exe /VERYSILENT /NORESTART` bzw. `msiexec.exe /i KeePass-<ver>.msi /qn` | Inno Setup. | [installKeePass.ps1](installKeePass.ps1) |
| Bitwarden Desktop | EXE | `Bitwarden-Installer.exe /allusers /S` | NSIS. | [installBitwarden.ps1](installBitwarden.ps1) |
| Microsoft PowerToys (Machine) | EXE (Burn) | `PowerToysSetup-x64.exe /quiet /norestart` | Machine-Wide-Installer verwenden. | [installPowerToys.ps1](installPowerToys.ps1) |
| Visual Studio 2022 | EXE | `vs_enterprise.exe --quiet --wait --norestart --add Microsoft.VisualStudio.Workload.ManagedDesktop` | `--wait` ist nötig, damit der Rückgabecode stimmt. | – |
| SQL Server Management Studio ≤ 20 | EXE | `SSMS-Setup-ENU.exe /install /quiet /norestart` | Ab SSMS 21 Visual-Studio-Installer (`--quiet --wait`). | – |
| Docker Desktop | EXE | `"Docker Desktop Installer.exe" install --quiet --accept-license` | Benötigt WSL2/Hyper-V und Lizenz für größere Unternehmen. | – |
| Azure CLI / AWS CLI | MSI | `msiexec.exe /i azure-cli.msi /qn` bzw. `msiexec.exe /i AWSCLIV2.msi /qn` | – | [installAzureCli.ps1](installAzureCli.ps1), [installAwsCli.ps1](installAwsCli.ps1) |
| Wireshark | EXE | `Wireshark-<ver>-x64.exe /S /desktopicon=no` | Npcap ist nur in der OEM-Edition silent installierbar. | [installWireshark.ps1](installWireshark.ps1) |
| Sysinternals Suite | ZIP | Entpacken nach `C:\Program Files\Sysinternals`; Tools mit `-accepteula` starten. | Kein Installer. | – |
| TreeSize Free | EXE | `TreeSizeFreeSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` | Inno Setup. | [installTreeSizeFree.ps1](installTreeSizeFree.ps1) |
| Everything (voidtools) | EXE | `Everything-<ver>.x64-Setup.exe /S` | NSIS. | [installEverything.ps1](installEverything.ps1) |
| Microsoft Power BI Desktop | EXE | `PBIDesktopSetup_x64.exe -quiet -norestart ACCEPT_EULA=1` | – | [installPowerBIDesktop.ps1](installPowerBIDesktop.ps1) |
| 1Password | MSI | `msiexec.exe /i 1PasswordSetup-latest.msi /qn /norestart` | Unternehmens-MSI (maschinenweit); Browser-Erweiterungen separat per Richtlinie verteilen. | [install1Password.ps1](install1Password.ps1) |
| Gpg4win | EXE | `gpg4win.exe /S` | E-Mail-/Dateiverschlüsselung (OpenPGP/S-MIME) inkl. Kleopatra und GpgOL für Outlook. | [installGpg4win.ps1](installGpg4win.ps1) |
| VeraCrypt | MSI | `msiexec.exe /i VeraCrypt_Setup_x64.msi /qn /norestart ACCEPTLICENSE=YES` | MSI erfordert ACCEPTLICENSE=YES; für den Treiber kann ein Neustart erforderlich sein (RebootRequired). | [installVeraCrypt.ps1](installVeraCrypt.ps1) |
| Yubico Authenticator | MSI | `msiexec.exe /i yubico-authenticator-windows.msi /qn /norestart` | Verwaltung von OATH/TOTP und YubiKey-Einstellungen; ersetzt den eingestellten YubiKey Manager. | [installYubicoAuthenticator.ps1](installYubicoAuthenticator.ps1) |
| SQL Server Management Studio 22 | EXE | `vs_SSMS.exe --quiet --wait --norestart` | Visual-Studio-Installer: --wait ist für den richtigen Rückgabecode nötig; installTimeoutMinutes 60 empfohlen. | [installSqlServerManagementStudio.ps1](installSqlServerManagementStudio.ps1) |
| Microsoft Azure Storage Explorer | EXE | `StorageExplorer-windows-x64.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /ALLUSERS` | Inno Setup; /ALLUSERS installiert maschinenweit. | [installAzureStorageExplorer.ps1](installAzureStorageExplorer.ps1) |
| WinMerge | EXE | `WinMerge-x64-Setup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Per-Machine-Installer verwenden (nicht die PerUser-Variante). | [installWinMerge.ps1](installWinMerge.ps1) |
| TortoiseGit | MSI | `msiexec.exe /i TortoiseGit-64bit.msi /qn /norestart` | Explorer-Integration für Git; setzt Git for Windows (installGit.ps1) voraus, Neustart des Explorers empfohlen. | [installTortoiseGit.ps1](installTortoiseGit.ps1) |
| TortoiseSVN | MSI | `msiexec.exe /i TortoiseSVN-x64.msi /qn /norestart` | Explorer-Integration für Subversion; Neustart des Explorers empfohlen. | [installTortoiseSvn.ps1](installTortoiseSvn.ps1) |
| Advanced IP Scanner | EXE | `Advanced_IP_Scanner.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Netzwerkscanner; nur aus der Herstellerquelle (winget) installieren – gefälschte Downloads sind verbreitet. | [installAdvancedIpScanner.ps1](installAdvancedIpScanner.ps1) |
| DBeaver Community | EXE | `dbeaver-ce-x86_64-setup.exe /S /allusers` | Datenbank-Werkzeug (Java enthalten); /allusers installiert maschinenweit. | [installDBeaverCommunity.ps1](installDBeaverCommunity.ps1) |

### Werkzeuge und Multimedia / Utilities and multimedia

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| 7-Zip | EXE / MSI | `7z<ver>-x64.exe /S` bzw. `msiexec.exe /i 7z<ver>-x64.msi /qn` | NSIS; Zielordner `/D=C:\Program Files\7-Zip` (letzter Parameter). | [install7Zip.ps1](install7Zip.ps1) |
| VLC media player | EXE / MSI | `vlc-<ver>-win64.exe /L=1031 /S` bzw. `msiexec.exe /i vlc-<ver>-win64.msi /qn` | `/L=1031` = Deutsch. | [installVlcMediaPlayer.ps1](installVlcMediaPlayer.ps1) |
| Greenshot | EXE | `Greenshot-INSTALLER-<ver>.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Inno Setup. | [installGreenshot.ps1](installGreenshot.ps1) |
| ShareX | EXE | `ShareX-<ver>-setup.exe /VERYSILENT /NORESTART` | Inno Setup. | [installShareX.ps1](installShareX.ps1) |
| IrfanView | EXE | `iview<ver>_x64_setup.exe /silent /desktop=0 /thumbs=0 /group=1 /allusers=1 /assoc=1` | Plugins separat: `/silent`. | [installIrfanView.ps1](installIrfanView.ps1) |
| paint.net | EXE | `paint.net.<ver>.install.x64.exe /auto` | MSI erzeugen: `/createMsi`. | – |
| GIMP | EXE | `gimp-<ver>-setup.exe /VERYSILENT /NORESTART /ALLUSERS` | Inno Setup. | – |
| Audacity | EXE | `audacity-win-<ver>-64bit.exe /VERYSILENT /NORESTART` | Inno Setup. | – |
| PeaZip | EXE | `peazip.WIN64.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` | Inno Setup; Open-Source-Packer (LGPL) als Alternative zu WinRAR. | [installPeaZip.ps1](installPeaZip.ps1) |
| WinRAR | EXE | `winrar-x64.exe /S` | Lizenzpflichtig; Lizenzdatei rarreg.key nach der Installation nach %ProgramFiles%\WinRAR kopieren. | [installWinRar.ps1](installWinRar.ps1) |

### Hersteller-Tools / OEM tools

| Anwendung / Application | Paket / Package | Silent-Installation / Silent install | Hinweise / Notes | Skript / Script |
| --- | --- | --- | --- | --- |
| Dell Command \| Update | EXE | `Dell-Command-Update-Application_<ver>.EXE /s` | Danach z. B. `dcu-cli.exe /applyUpdates -reboot=disable`. | [installDellCommandUpdate.ps1](installDellCommandUpdate.ps1) |
| Lenovo System Update | EXE | `system_update_<ver>.exe /VERYSILENT /NORESTART` | Inno Setup. | [installLenovoSystemUpdate.ps1](installLenovoSystemUpdate.ps1) |
| HP Image Assistant | EXE | `hp-hpia-<ver>.exe /s /e /f "C:\HPIA"` | Entpackt das Tool; danach `HPImageAssistant.exe /Operation:Analyze /Action:Install /Silent`. | – |
| Intel Driver & Support Assistant | EXE | `Intel-Driver-and-Support-Assistant-Installer.exe /quiet /norestart` | Treiberaktualisierung für Intel-Komponenten (WLAN, Grafik, Bluetooth); WiX-Burn-Bundle. | [installIntelDriverSupportAssistant.ps1](installIntelDriverSupportAssistant.ps1) |
| Jabra Direct | EXE | `JabraDirectSetup.exe /install /quiet /norestart` | Verwaltung und Firmware-Updates für Jabra-Headsets; WiX-Burn-Bundle. | [installJabraDirect.ps1](installJabraDirect.ps1) |

## winget-IDs der Skripte / winget IDs of the scripts

Alle Skripte nutzen standardmäßig winget (`installSource = Winget`) mit `--scope machine`; Ausnahme ist
`installMicrosoft365Apps.ps1` (Standard `Download`: Office Deployment Tool von Microsoft, Authenticode-geprüft).
`installPowerShell7.ps1` ergänzt `--installer-type wix`, da winget sonst das MSIX-Paket wählt (ignoriert
`--scope machine`, kein Uninstall-Eintrag).
Die IDs wurden gegen [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) geprüft.
*All scripts use winget by default with `--scope machine`, except `installMicrosoft365Apps.ps1` (default `Download`:
Office Deployment Tool from Microsoft, Authenticode-verified); IDs were checked against microsoft/winget-pkgs.
`installPowerShell7.ps1` adds `--installer-type wix`, otherwise winget picks the MSIX package (ignores
`--scope machine`, no Uninstall entry).*

| Skript / Script | winget-ID | Standardargumente bei Datei-Quelle / Default arguments for file source |
| --- | --- | --- |
| [install1Password.ps1](install1Password.ps1) | `AgileBits.1Password` | MSI `/qn /norestart` |
| [install7Zip.ps1](install7Zip.ps1) | `7zip.7zip` | EXE `/S`; MSI `/qn /norestart` |
| [installAdobeAcrobatReader.ps1](installAdobeAcrobatReader.ps1) | `Adobe.Acrobat.Reader.64-bit` | EXE `/sAll /rs /msi EULA_ACCEPT=YES`; MSI `EULA_ACCEPT=YES` |
| [installAdvancedIpScanner.ps1](installAdvancedIpScanner.ps1) | `Famatech.AdvancedIPScanner` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installAnyDesk.ps1](installAnyDesk.ps1) | `AnyDesk.AnyDesk` | EXE `--install "C:\Program Files (x86)\AnyDesk" --start-with-win --silent --create-shortcuts --create-desktop-icon` |
| [installAwsCli.ps1](installAwsCli.ps1) | `Amazon.AWSCLI` | MSI `/qn /norestart` |
| [installAzureCli.ps1](installAzureCli.ps1) | `Microsoft.AzureCLI` | MSI `/qn /norestart` |
| [installAzureStorageExplorer.ps1](installAzureStorageExplorer.ps1) | `Microsoft.Azure.StorageExplorer` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /ALLUSERS` |
| [installBitwarden.ps1](installBitwarden.ps1) | `Bitwarden.Bitwarden` | EXE `/allusers /S` |
| [installBoxDrive.ps1](installBoxDrive.ps1) | `Box.Box` | MSI `/qn /norestart` |
| [installBraveBrowser.ps1](installBraveBrowser.ps1) | `Brave.Brave` | EXE `/silent /install` |
| [installCiscoJabber.ps1](installCiscoJabber.ps1) | `Cisco.Jabber` | MSI `/qn /norestart` |
| [installCiscoWebex.ps1](installCiscoWebex.ps1) | `Cisco.Webex` | MSI `ACCEPT_EULA=TRUE ALLUSERS=1 AUTOSTART_WITH_WINDOWS=false` |
| [installCitrixWorkspace.ps1](installCitrixWorkspace.ps1) | `Citrix.Workspace` | EXE `/silent /noreboot /AutoUpdateCheck=disabled` |
| [installDBeaverCommunity.ps1](installDBeaverCommunity.ps1) | `DBeaver.DBeaver.Community` | EXE `/S /allusers` |
| [installDellCommandUpdate.ps1](installDellCommandUpdate.ps1) | `Dell.CommandUpdate.Universal` | EXE `/s` |
| [installDotNetAspNetCoreRuntime10.ps1](installDotNetAspNetCoreRuntime10.ps1) | `Microsoft.DotNet.AspNetCore.10` | EXE `/install /quiet /norestart` |
| [installDotNetAspNetCoreRuntime8.ps1](installDotNetAspNetCoreRuntime8.ps1) | `Microsoft.DotNet.AspNetCore.8` | EXE `/install /quiet /norestart` |
| [installDotNetDesktopRuntime10.ps1](installDotNetDesktopRuntime10.ps1) | `Microsoft.DotNet.DesktopRuntime.10` | EXE `/install /quiet /norestart` |
| [installDotNetDesktopRuntime8.ps1](installDotNetDesktopRuntime8.ps1) | `Microsoft.DotNet.DesktopRuntime.8` | EXE `/install /quiet /norestart` |
| [installDotNetHostingBundle10.ps1](installDotNetHostingBundle10.ps1) | `Microsoft.DotNet.HostingBundle.10` | EXE `/install /quiet /norestart` |
| [installDotNetHostingBundle8.ps1](installDotNetHostingBundle8.ps1) | `Microsoft.DotNet.HostingBundle.8` | EXE `/install /quiet /norestart` |
| [installDotNetRuntime10.ps1](installDotNetRuntime10.ps1) | `Microsoft.DotNet.Runtime.10` | EXE `/install /quiet /norestart` |
| [installDotNetRuntime8.ps1](installDotNetRuntime8.ps1) | `Microsoft.DotNet.Runtime.8` | EXE `/install /quiet /norestart` |
| [installDrawIo.ps1](installDrawIo.ps1) | `JGraph.Draw` | EXE `/S /allusers` |
| [installDropbox.ps1](installDropbox.ps1) | `Dropbox.Dropbox` | EXE `/S` |
| [installEmClient.ps1](installEmClient.ps1) | `eMClient.eMClient` | MSI `/qn /norestart` |
| [installEverything.ps1](installEverything.ps1) | `voidtools.Everything` | EXE `/S`; MSI `/qn /norestart` |
| [installFoxitPdfEditor.ps1](installFoxitPdfEditor.ps1) | `Foxit.PhantomPDF` | EXE `/quiet /norestart`; MSI `/qn /norestart` |
| [installFoxitPdfReader.ps1](installFoxitPdfReader.ps1) | `Foxit.FoxitReader` | EXE `/quiet`; MSI `/qn /norestart` |
| [installGit.ps1](installGit.ps1) | `Git.Git` | EXE `/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES` |
| [installGoogleChrome.ps1](installGoogleChrome.ps1) | `Google.Chrome` | EXE `/silent /install`; MSI `/qn /norestart` |
| [installGoogleDrive.ps1](installGoogleDrive.ps1) | `Google.GoogleDrive` | EXE `--silent --skip_launch_new --gsuite_shortcuts=false` |
| [installGoToMeeting.ps1](installGoToMeeting.ps1) | `GoTo.GoToMeeting` | MSI `G2MINSTALLFORALLUSERS=1` |
| [installGpg4win.ps1](installGpg4win.ps1) | `GnuPG.Gpg4win` | EXE `/S` |
| [installGreenshot.ps1](installGreenshot.ps1) | `Greenshot.Greenshot` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installIntelDriverSupportAssistant.ps1](installIntelDriverSupportAssistant.ps1) | `Intel.IntelDriverAndSupportAssistant` | EXE `/quiet /norestart` |
| [installIrfanView.ps1](installIrfanView.ps1) | `IrfanSkiljan.IrfanView` | EXE `/silent /desktop=0 /thumbs=0 /group=1 /allusers=1 /assoc=1` |
| [installJabraDirect.ps1](installJabraDirect.ps1) | `Jabra.Direct` | EXE `/install /quiet /norestart` |
| [installKeePass.ps1](installKeePass.ps1) | `DominikReichl.KeePass` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS`; MSI `/qn /norestart` |
| [installKeePassXC.ps1](installKeePassXC.ps1) | `KeePassXCTeam.KeePassXC` | MSI `/qn /norestart` |
| [installLenovoSystemUpdate.ps1](installLenovoSystemUpdate.ps1) | `Lenovo.SystemUpdate` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installLibreOffice.ps1](installLibreOffice.ps1) | `TheDocumentFoundation.LibreOffice` | MSI `CREATEDESKTOPLINK=0 REGISTER_NO_MSO_TYPES=1 ISCHECKFORPRODUCTUPDATES=0 QUICKSTART=0 RebootYesNo=No` |
| [installMattermostDesktop.ps1](installMattermostDesktop.ps1) | `Mattermost.MattermostDesktop` | MSI `/qn /norestart` |
| [installMicrosoft365Apps.ps1](installMicrosoft365Apps.ps1) | `Microsoft.Office` | EXE `/configure https://aka.ms/fhlwingetconfig` (auch für / also for `Download`; eigene XML / own XML: `installerArguments` `/configure \\server\share\config.xml`) |
| [installMicrosoftEdge.ps1](installMicrosoftEdge.ps1) | `Microsoft.Edge` | MSI `/qn /norestart` |
| [installMicrosoftEdgeWebView2.ps1](installMicrosoftEdgeWebView2.ps1) | `Microsoft.EdgeWebView2Runtime` | EXE `/silent /install` |
| [installMicrosoftOneDrive.ps1](installMicrosoftOneDrive.ps1) | `Microsoft.OneDrive` | EXE `/allusers /silent` |
| [installMicrosoftRemoteHelp.ps1](installMicrosoftRemoteHelp.ps1) | `Microsoft.RemoteHelp` | EXE `acceptTerms=1 /quiet /norestart` |
| [installMobaXterm.ps1](installMobaXterm.ps1) | `Mobatek.MobaXterm` | MSI `/qn /norestart` |
| [installMozillaFirefox.ps1](installMozillaFirefox.ps1) | `Mozilla.Firefox.de` | EXE `/S /PreventRebootRequired=true`; MSI `/qn /norestart` |
| [installMozillaFirefoxEsr.ps1](installMozillaFirefoxEsr.ps1) | `Mozilla.Firefox.ESR.de` | EXE `/S /PreventRebootRequired=true`; MSI `/qn /norestart` |
| [installMozillaThunderbird.ps1](installMozillaThunderbird.ps1) | `Mozilla.Thunderbird.de` | EXE `/S`; MSI `/qn /norestart` |
| [installMRemoteNG.ps1](installMRemoteNG.ps1) | `mRemoteNG.mRemoteNG` | MSI `/qn /norestart` |
| [installMsOdbcSql18.ps1](installMsOdbcSql18.ps1) | `Microsoft.msodbcsql.18` | MSI `IACCEPTMSODBCSQLLICENSETERMS=YES` |
| [installNextcloudDesktop.ps1](installNextcloudDesktop.ps1) | `Nextcloud.NextcloudDesktop` | MSI `/qn /norestart` |
| [installNodeJsLts.ps1](installNodeJsLts.ps1) | `OpenJS.NodeJS.LTS` | MSI `/qn /norestart` |
| [installNotepadPlusPlus.ps1](installNotepadPlusPlus.ps1) | `Notepad++.Notepad++` | EXE `/S` |
| [installOmnissaHorizonClient.ps1](installOmnissaHorizonClient.ps1) | `Omnissa.HorizonClient` | EXE `/silent /norestart` |
| [installOnlyOfficeDesktopEditors.ps1](installOnlyOfficeDesktopEditors.ps1) | `ONLYOFFICE.DesktopEditors` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-`; MSI `/qn /norestart` |
| [installOpenVpn.ps1](installOpenVpn.ps1) | `OpenVPNTechnologies.OpenVPN` | MSI `/qn /norestart` |
| [installOpenVpnConnect.ps1](installOpenVpnConnect.ps1) | `OpenVPNTechnologies.OpenVPNConnect` | MSI `/qn /norestart` |
| [installPdf24Creator.ps1](installPdf24Creator.ps1) | `geeksoftwareGmbH.PDF24Creator` | EXE `/VERYSILENT /NORESTART /NOUPDATE`; MSI `/qn /norestart` |
| [installPdfsamBasic.ps1](installPdfsamBasic.ps1) | `PDFsam.PDFsam` | MSI `SKIPTHANKSPAGE=Yes` |
| [installPdfXChangeEditor.ps1](installPdfXChangeEditor.ps1) | `TrackerSoftware.PDF-XChangeEditor` | EXE `/quiet /norestart`; MSI `/qn /norestart` |
| [installPeaZip.ps1](installPeaZip.ps1) | `Giorgiotani.Peazip` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installPowerAutomateDesktop.ps1](installPowerAutomateDesktop.ps1) | `Microsoft.PowerAutomateDesktop` | EXE `-Silent -ACCEPTEULA` |
| [installPowerBIDesktop.ps1](installPowerBIDesktop.ps1) | `Microsoft.PowerBI` | EXE `-quiet -norestart ACCEPT_EULA=1` |
| [installPowerShell7.ps1](installPowerShell7.ps1) | `Microsoft.PowerShell` (winget `--installer-type wix`) | MSI `ADD_PATH=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1` |
| [installPowerToys.ps1](installPowerToys.ps1) | `Microsoft.PowerToys` | EXE `/quiet /norestart` |
| [installPuTTY.ps1](installPuTTY.ps1) | `PuTTY.PuTTY` | MSI `/qn /norestart` |
| [installPython314.ps1](installPython314.ps1) | `Python.Python.3.14` | EXE `/quiet InstallAllUsers=1 PrependPath=1 Include_test=0` |
| [installRealVncViewer.ps1](installRealVncViewer.ps1) | `RealVNC.VNCViewer` | MSI `/qn /norestart` |
| [installRemoteDesktopManager.ps1](installRemoteDesktopManager.ps1) | `Devolutions.RemoteDesktopManager` | MSI `/qn /norestart` |
| [installRoyalTs.ps1](installRoyalTs.ps1) | `RoyalApps.RoyalTS.7` | MSI `/qn /norestart` |
| [installShareX.ps1](installShareX.ps1) | `ShareX.ShareX` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /NORUN` |
| [installSonicWallNetExtender.ps1](installSonicWallNetExtender.ps1) | `SonicWall.NetExtender` | EXE `/S`; MSI `/qn /norestart` |
| [installSplashtopBusiness.ps1](installSplashtopBusiness.ps1) | `Splashtop.SplashtopBusiness` | MSI `/qn /norestart` |
| [installSqlServerManagementStudio.ps1](installSqlServerManagementStudio.ps1) | `Microsoft.SQLServerManagementStudio.22` | EXE `--quiet --wait --norestart` |
| [installTailscale.ps1](installTailscale.ps1) | `Tailscale.Tailscale` | EXE `/install /quiet /norestart`; MSI `/qn /norestart` |
| [installTeamViewer.ps1](installTeamViewer.ps1) | `TeamViewer.TeamViewer` | EXE `/S` |
| [installTeamViewerHost.ps1](installTeamViewerHost.ps1) | `TeamViewer.TeamViewer.Host` | EXE `/S`; MSI `/qn /norestart` |
| [installTemurinJdk21.ps1](installTemurinJdk21.ps1) | `EclipseAdoptium.Temurin.21.JDK` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTemurinJre11.ps1](installTemurinJre11.ps1) | `EclipseAdoptium.Temurin.11.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTemurinJre17.ps1](installTemurinJre17.ps1) | `EclipseAdoptium.Temurin.17.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTemurinJre21.ps1](installTemurinJre21.ps1) | `EclipseAdoptium.Temurin.21.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTemurinJre25.ps1](installTemurinJre25.ps1) | `EclipseAdoptium.Temurin.25.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTemurinJre8.ps1](installTemurinJre8.ps1) | `EclipseAdoptium.Temurin.8.JRE` | MSI `ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome` |
| [installTortoiseGit.ps1](installTortoiseGit.ps1) | `TortoiseGit.TortoiseGit` | MSI `/qn /norestart` |
| [installTortoiseSvn.ps1](installTortoiseSvn.ps1) | `TortoiseSVN.TortoiseSVN` | MSI `/qn /norestart` |
| [installTreeSizeFree.ps1](installTreeSizeFree.ps1) | `JAMSoftware.TreeSize.Free` | EXE `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| [installVcRedist2013X64.ps1](installVcRedist2013X64.ps1) | `Microsoft.VCRedist.2013.x64` | EXE `/install /quiet /norestart` |
| [installVcRedistX64.ps1](installVcRedistX64.ps1) | `Microsoft.VCRedist.2015+.x64` | EXE `/install /quiet /norestart` |
| [installVcRedistX86.ps1](installVcRedistX86.ps1) | `Microsoft.VCRedist.2015+.x86` | EXE `/install /quiet /norestart` |
| [installVeraCrypt.ps1](installVeraCrypt.ps1) | `IDRIX.VeraCrypt` | MSI `ACCEPTLICENSE=YES` |
| [installVisualStudioCode.ps1](installVisualStudioCode.ps1) | `Microsoft.VisualStudioCode` | EXE `/VERYSILENT /NORESTART /MERGETASKS=!runcode` |
| [installVlcMediaPlayer.ps1](installVlcMediaPlayer.ps1) | `VideoLAN.VLC` | EXE `/L=1031 /S`; MSI `/qn /norestart` |
| [installWinMerge.ps1](installWinMerge.ps1) | `WinMerge.WinMerge` | EXE `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` |
| [installWinRar.ps1](installWinRar.ps1) | `RARLab.WinRAR` | EXE `/S` |
| [installWinSCP.ps1](installWinSCP.ps1) | `WinSCP.WinSCP` | EXE `/VERYSILENT /ALLUSERS /NORESTART /SUPPRESSMSGBOXES` |
| [installWireGuard.ps1](installWireGuard.ps1) | `WireGuard.WireGuard` | MSI `DO_NOT_LAUNCH=1` |
| [installWireshark.ps1](installWireshark.ps1) | `WiresharkFoundation.Wireshark` | EXE `/S /desktopicon=no`; MSI `/qn /norestart` |
| [installYubicoAuthenticator.ps1](installYubicoAuthenticator.ps1) | `Yubico.Authenticator` | MSI `/qn /norestart` |
| [installZoomOutlookPlugin.ps1](installZoomOutlookPlugin.ps1) | `Zoom.ZoomOutlookPlugin` | MSI `/qn /norestart` |
| [installZoomWorkplace.ps1](installZoomWorkplace.ps1) | `Zoom.Zoom` | MSI `/qn /norestart` |

MSI-Pakete werden von den Skripten immer mit `/i "<datei>" /qn /norestart /l*v "<log>"` aufgerufen; die Tabelle nennt die
zusätzlichen Eigenschaften. `installerArguments` ersetzt die Standardargumente (bei MSI nur die zusätzlichen Eigenschaften).
*MSI packages are always started with `/i "<file>" /qn /norestart /l*v "<log>"`; the table lists the additional properties.
`installerArguments` replaces the default arguments (for MSI only the additional properties).*

Weitere nützliche IDs / Further useful IDs: `dotPDN.PaintDotNet`, `GIMP.GIMP`, `Audacity.Audacity`, `Docker.DockerDesktop`,
`Microsoft.VisualStudio.2022.Professional`. Vor Verwendung mit `winget show --id <Id> --exact` prüfen; MSIX- und reine
Benutzerpakete (z. B. `Microsoft.Teams`, `SlackTechnologies.Slack`) eignen sich nicht für `SYSTEM` (Teams: Bootstrapper bzw. Slack: MSI, siehe oben).
*Verify with `winget show --id <Id> --exact` before use; MSIX and per-user packages are not suitable for `SYSTEM`.*

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
