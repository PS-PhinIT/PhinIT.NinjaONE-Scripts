# Changelog

Alle nennenswerten Änderungen an diesem Repository werden in dieser Datei
dokumentiert. / All notable changes to this repository are documented in this
file.

Das Repository verwendet keine Release-Tags. Jeder Eintrag trägt daher das
Datum der Änderung (neueste zuerst); ältere Einträge wurden aus der
Git-Historie und den Pull Requests rekonstruiert.
/ The repository has no release tags. Every entry is therefore dated (newest
first); older entries were reconstructed from the Git history and pull requests.

## 2026-10-18 – 80 weitere Installations-Scripte / 80 additional installation scripts

### Hinzugefügt / Added
- `Installations-Scripte`: 80 weitere Silent-Installationsskripte (insgesamt 105)
  mit derselben Engine wie die bestehenden Skripte; winget-IDs, Scope und
  Anzeigenamen gegen `microsoft/winget-pkgs` geprüft. Schwerpunkt
  Business-Anwendungen:
  - Browser: Microsoft Edge, Edge WebView2, Brave, Firefox ESR.
  - Office, PDF, Kommunikation und Cloud: Microsoft 365 Apps, Foxit PDF
    Reader/Editor, PDF-XChange Editor, PDFsam Basic, ONLYOFFICE, eM Client,
    Power BI Desktop, Power Automate for desktop, Webex, Jabber, GoTo Meeting,
    Zoom Outlook Plugin, Mattermost, Nextcloud, Dropbox, Google Drive, Box Drive,
    OneDrive, draw.io.
  - Sicherheit: 1Password, Bitwarden, KeePass, Gpg4win, VeraCrypt, Yubico
    Authenticator.
  - Fernwartung und VPN: OpenVPN, OpenVPN Connect, Tailscale, Omnissa Horizon
    Client, RealVNC Viewer, mRemoteNG, Remote Desktop Manager, Royal TS,
    Splashtop Business, TeamViewer Host, MobaXterm, SonicWall NetExtender,
    Microsoft Remote Help.
  - Laufzeiten: .NET 8/10 (Desktop, Runtime, ASP.NET Core, Hosting Bundle),
    Visual C++ x86 und 2013, Temurin JRE 8/11/17/25 und JDK 21, Python 3.14,
    Node.js LTS, ODBC Driver 18 for SQL Server.
  - Admin-Werkzeuge: PowerToys, SSMS, Azure CLI, AWS CLI, Azure Storage
    Explorer, Wireshark, Everything, WinMerge, TortoiseGit, TortoiseSVN,
    Advanced IP Scanner, DBeaver, ShareX, IrfanView, PeaZip, WinRAR.
  - Hersteller-Tools: Dell Command | Update, Lenovo System Update, Intel Driver
    & Support Assistant, Jabra Direct.
  / 80 additional silent install scripts (105 in total) sharing the existing
  engine, focused on business applications; winget IDs, scope and display names
  verified against `microsoft/winget-pkgs`.

### Geändert / Changed
- `SilentSwitches.md`: winget-Tabelle und Anwendungstabellen um die neuen
  Skripte ergänzt. / winget and application tables list the new scripts.
- `Tests/InstallScripts.Tests.ps1`: Beispiel- und Negativ-Anzeigenamen für alle
  neuen Skripte. / sample and negative display names for all new scripts.
- `README.md`: Katalog und Tabelle der Installations-Scripte aktualisiert.
  / catalog and installation script table updated.

## 2026-10-17 – Bereinigung, Einstellungen und Installations-Scripte / Cleanup, configuration and installation scripts

### Hinzugefügt / Added
- `08 - Cleanup`: 9 Bereinigungsskripte (Temp-Dateien, Papierkorb, WER-Berichte,
  Übermittlungsoptimierungs-Cache, Komponentenspeicher, Browser-Cache, veraltete
  Benutzerprofile, Software-Deinstallation, AppX-Bloatware). Ohne Opt-in nur
  Inventur; `-WhatIf`/`-Confirm`, JSON-Bericht, `resultCustomField`, Exit 0/1/2.
  / 9 cleanup scripts; audit only without opt-in, `-WhatIf`/`-Confirm`, JSON
  report, `resultCustomField`, exit 0/1/2.
- `09 - Configuration`: 10 Einstellungsskripte für System und Programme
  (Energiesparplan, Zeitzone, Schnellstart, Remotedesktop, Dienst-Starttyp,
  Registrywert, USB-Speicher, Consumer-Funktionen, Edge-Richtlinien,
  Microsoft-365-Updatekanal) mit Soll-/Ist-Vergleich und Opt-in.
  / 10 configuration scripts for system and program settings with desired-state
  comparison and opt-in.
- `Installations-Scripte`: 25 Silent-Installationsskripte (je Tool eines) über
  winget oder eine lokale/UNC-Datei mit optionaler SHA256-Prüfung, sowie
  `SilentSwitches.md` mit Silent-Schaltern, Rückgabecodes und
  Deinstallationsbefehlen für Installer-Frameworks und viele Programme.
  / 25 silent install scripts (one per tool) via winget or a local/UNC file with
  optional SHA256 verification, plus `SilentSwitches.md` with silent switches,
  exit codes and uninstall commands.
- Tests: `Tests/CatalogCleanup.Tests.ps1`, `Tests/CatalogConfiguration.Tests.ps1`,
  `Tests/InstallScripts.Tests.ps1`.

### Geändert / Changed
- README (Katalog, Variablen, sichere Nutzung), CONTRIBUTING (Ablage/Namensregeln)
  und SECURITY (Ausnahme für geprüfte Installationsquellen) ergänzt.
  / README, CONTRIBUTING and SECURITY updated accordingly.

## 2026-10-14 – Erweiterung der Skriptbibliothek um 114 Skripte / Script library extended by 114 scripts

### Hinzugefügt / Added
Je Themenordner 10–14 neue, rein lesende NinjaOne-Diagnose-/Prüfskripte
(Windows PowerShell 5.1, SYSTEM, 64-Bit) mit zweisprachiger Hilfe, JSON-Bericht,
optionalem Export über `resultCustomField` und Rückgabecodes 0/1/2.
/ 10–14 new read-only NinjaOne diagnostic/check scripts per topic folder with
bilingual help, JSON report, optional `resultCustomField` export and exit codes 0/1/2.

- `01 - System` (+10): `checkPhysicalDiskHealth.ps1`, `checkSecureBootStatus.ps1`, `checkWindowsActivation.ps1`, `readBatteryHealth.ps1`, `readBiosFirmware.ps1`, `readCpuUsage.ps1`, `readDeviceProblems.ps1`, `readMemoryUsage.ps1`, `readPageFileStatus.ps1`, `readTopProcesses.ps1`
- `02 - Updates` (+10): `checkComponentStoreHealth.ps1`, `checkTargetReleaseVersion.ps1`, `checkUpdatePauseState.ps1`, `checkWindowsUpdatePolicy.ps1`, `checkWsusConfiguration.ps1`, `readDeliveryOptimizationStatus.ps1`, `readLastUpdateInstall.ps1`, `readOfficeUpdateChannel.ps1`, `readPendingUpdates.ps1`, `readUpdateHistoryFailures.ps1`
- `03 - Software` (+11): `checkRequiredSoftware.ps1`, `checkSoftwareVersion.ps1`, `checkWindowsOptionalFeatures.ps1`, `checkWingetStatus.ps1`, `readAppxProvisionedPackages.ps1`, `readBrowserVersions.ps1`, `readJavaInstallations.ps1`, `readPowerShellEngines.ps1`, `readRecentSoftwareChanges.ps1`, `readStartupPrograms.ps1`, `readVcRedistInventory.ps1`
- `04 - Certificates` (+12): `checkAutoEnrollmentPolicy.ps1`, `checkCertificateChain.ps1`, `checkCertificatePresence.ps1`, `checkCodeSigningCertificates.ps1`, `checkDotNetStrongCrypto.ps1`, `checkRdpCertificate.ps1`, `checkRemoteTlsCertificate.ps1`, `checkRootAutoUpdate.ps1`, `checkSchannelProtocols.ps1`, `checkSslBindingCertificates.ps1`, `checkWeakCertificates.ps1`, `readDisallowedCertificates.ps1`
- `05 - DNS` (+11): `checkDnsOverHttps.ps1`, `checkDnsRegistration.ps1`, `checkDnsSuffixSearchList.ps1`, `checkDomainSrvRecords.ps1`, `checkHostsFile.ps1`, `checkLlmnrNetbiosStatus.ps1`, `checkReverseDnsRecord.ps1`, `compareDnsServerResponses.ps1`, `readDnsClientEvents.ps1`, `readNrptPolicy.ps1`, `testDnsServerResponse.ps1`
- `06 - Bitlocker` (+10): `checkBitLockerCompliance.ps1`, `checkBitLockerPolicy.ps1`, `checkBitLockerSuspended.ps1`, `checkDeviceEncryptionSupport.ps1`, `checkPreBootAuthentication.ps1`, `checkRemovableDriveEncryption.ps1`, `checkUsedSpaceOnlyEncryption.ps1`, `checkWinREStatus.ps1`, `readBitLockerEventErrors.ps1`, `readRecoveryKeyEscrowEvents.ps1`
- `07 - Security` (+14): `checkAuditPolicy.ps1`, `checkBuiltinAccounts.ps1`, `checkCredentialGuard.ps1`, `checkDefenderAsrRules.ps1`, `checkDefenderExclusions.ps1`, `checkLapsStatus.ps1`, `checkLegacyAuthentication.ps1`, `checkLsaProtection.ps1`, `checkPasswordPolicy.ps1`, `checkRdpSecurity.ps1`, `checkSmbSigning.ps1`, `checkSmbv1Status.ps1`, `checkUacSettings.ps1`, `readFailedLogons.ps1`
- `10 - Network` (+13): `checkAdapterLinkSpeed.ps1`, `checkInternetConnectivity.ps1`, `checkIpAddressConflicts.ps1`, `checkNetworkProfile.ps1`, `checkProxySettings.ps1`, `checkVpnConnections.ps1`, `readArpTable.ps1`, `readRoutingTable.ps1`, `readSmbShares.ps1`, `readWifiProfiles.ps1`, `readWifiStatus.ps1`, `testPingTargets.ps1`, `testTraceRoute.ps1`
- `11 - User` (+11): `checkAutoLogon.ps1`, `checkInactiveLocalUsers.ps1`, `checkLockedOutUsers.ps1`, `checkPasswordNeverExpires.ps1`, `checkStaleProfiles.ps1`, `checkTemporaryProfiles.ps1`, `readEntraJoinStatus.ps1`, `readLoggedOnUsers.ps1`, `readLogonEvents.ps1`, `readRdpSessionHistory.ps1`, `readUserProfileSizes.ps1`
- `50 - Misc` (+12): `checkPowerPlan.ps1`, `checkPrinterStatus.ps1`, `checkTempFolderSize.ps1`, `readApplicationCrashes.ps1`, `readBugChecks.ps1`, `readLargeFiles.ps1`, `readNinjaAgentStatus.ps1`, `readReliabilityIndex.ps1`, `readServiceCrashes.ps1`, `readUnexpectedShutdowns.ps1`, `readUsbStorageHistory.ps1`, `readWheaErrors.ps1`

### Sicherheit / Security
- Keine der neuen Skripte ändert das System; Geheimnisse (Kennwörter,
  WLAN-Schlüssel, Recovery-Passwörter, Produktschlüssel, private Schlüssel)
  werden nie ausgegeben – z. B. meldet `checkAutoLogon.ps1` nur das
  Vorhandensein von `DefaultPassword`, `readWifiProfiles.ps1` nutzt nie
  `key=clear`, `readStartupPrograms.ps1` gibt Befehlszeilen nur auf Wunsch aus.
  / None of the new scripts change the system; secrets are never output.

### Tests
- Neu: `Tests/CatalogSystem`, `CatalogUpdates`, `CatalogSoftware`,
  `CatalogCertificates`, `CatalogDns`, `CatalogBitlocker`, `CatalogSecurityA`,
  `CatalogSecurityB`, `CatalogNetworkA`, `CatalogNetworkB`, `CatalogUser`,
  `CatalogMisc` (`*.Tests.ps1`, Pester 5, Windows-Cmdlets simuliert).

### Dokumentation / Documentation
- README: Themen- und Dateikatalog aktualisiert, Übersicht der neuen Skripte
  mit NinjaOne-Variablen.

## 2026-10-14 – Audit: Sicherheit, Performance, Funktionen, Verweise / Security, performance, functions, references

### Sicherheit / Security
- `05 - DNS`: DNS-Server-Werte aus Custom Fields werden vor der Zuweisung strikt
  als IPv4-Punktnotation geprüft (vorher führten z. B. `1` oder IPv6-Werte zu
  unbehandelten Ausnahmen oder wurden von `[IPAddress]::Parse` als `0.0.0.1`
  akzeptiert). `TargetGateway` wird ebenfalls validiert.
  / DNS values from custom fields are strictly validated as dotted IPv4 before
  assignment; `TargetGateway` is validated as well.
- `05 - DNS`: Die Authenticode-Signaturblöcke von `00-readDNSSettingsClient.ps1`
  und `01-setDNSSettingsClient.ps1` wurden entfernt, weil die Inhaltsänderungen
  sie ungültig machen (`HashMismatch`). **Die Skripte müssen vom Herausgeber neu
  signiert werden**, falls `AllSigned` genutzt wird (siehe [SECURITY.md](SECURITY.md)).
  / Signature blocks were removed because the content changes invalidated them;
  the publisher must re-sign the scripts if `AllSigned` is used.

### Behoben / Fixed
- `01-setDNSSettingsClient.ps1`:
  - IPv4-Adresse und Gateway eines Adapters mit genau einer Adresse wurden als
    erstes **Zeichen** statt als Adresse gelesen (`("192.168.1.1")[0]` = `1`).
    Dadurch griffen `-TargetGateway`/`-TargetSubnet` praktisch nie.
  - Fehler von `Set-DnsClientServerAddress` im Hintergrundjob wurden verschluckt
    und als Erfolg gezählt; `Stop-Job -Force` (Parameter existiert nicht) brach
    den Timeout-Pfad ab. Fehler lösen jetzt zuverlässig den `netsh`-Fallback aus.
  - `netsh … index=($i+1)` übergab `index=` und `2` als getrennte Argumente;
    `netsh`-Exitcodes werden jetzt geprüft. Fehlgeschlagene Adapter führen zu
    Exitcode `1` statt `0`.
  - `LinkSpeed` (Text) wurde numerisch verglichen – jetzt `Speed`.
  - Die Hardware-ID-Prüfung lief nur für bereits qualifizierte Adapter (wirkungslos,
    aber teuer) – jetzt nur für Adapter, die nicht über die Beschreibung erkannt werden.
  - `-AdapterName` nutzt echten Wildcard-Vergleich (`-like`) statt eines
    unverankerten Regex (`Ethernet` traf vorher auch `Ethernet 2`).
  - `-ResetDHCP` erkennt bereits auf DHCP stehende Adapter (Exitcode `2`).
  - `DNS_LastChange` wird nur noch nach tatsächlichen Änderungen geschrieben,
    `ipconfig /flushdns` nur nach Änderungen ausgeführt; `-WhatIf` ändert nichts.
  - Leeres Checkbox-Feld `DNS_ResetToDHCP` erzeugt keine Warnung mehr.
  - Ungültiges Hilfe-Schlüsselwort `.EXITCODES` entfernt – `Get-Help` funktioniert
    wieder; Beispiele ergänzt.
- `00-readDNSSettingsClient.ps1`:
  - Das dokumentierte Custom Field `DNS_Mismatch` wurde nie geschrieben – jetzt
    gesetzt (Checkbox).
  - Die Mismatch-Warnung wurde erst nach der Berichtsausgabe angehängt und war
    nie sichtbar.
  - Literale `\n` im Bericht durch echte Zeilenumbrüche ersetzt.
  - `-LogRetentionDays` als Text (NinjaOne-Übergabe) wurde ignoriert; jetzt
    geparst und auf 0–3650 begrenzt. Rotation umfasst auch `DNS*.log` und
    temporäre CSV-Anhänge.
  - `Ninja-Property-Set`-Fehler werden zuverlässig erkannt.
- Beide DNS-Hauptskripte: UTF-8 **mit BOM** gespeichert, damit Umlaute unter
  Windows PowerShell 5.1 korrekt dargestellt werden.
- `03 - Software/checkPowerShellPolicy.ps1`: verglich die Prozess-Policy (unter
  NinjaOne immer `Bypass`) – jetzt wird die konfigurierte Policy (GPO
  MachinePolicy/UserPolicy, dann CurrentUser/LocalMachine) geprüft; die effektive
  Policy bleibt als Info im Bericht.
  / Compared the process policy (always `Bypass` under NinjaOne); now checks the
  configured policy.
- `03 - Software/checkBlockedSoftware.ps1`, `readInstalledSoftware.ps1`: ein
  zwischenzeitlich gelöschter Uninstall-Schlüssel (`OpenSubKey` = `$null`) brach
  den gesamten Lauf ab – wird jetzt übersprungen.
- `07 - Security/detectUnauthorizedLocalAdmins.ps1`: Mitglieder mit Leerzeichen
  in der Domäne (z. B. `NT AUTHORITY\SYSTEM`) wurden als ungültig abgelehnt –
  Namensprüfung korrigiert; bekannte `Get-LocalGroupMember`-Einschränkung
  (verwaiste SIDs/Entra ID) dokumentiert.
- `10 - Network/testTcpEndpoint.ps1`: Kurzformen wie `1234` oder `10.1` wurden
  von `[IPAddress]::TryParse` als IP akzeptiert (`0.0.4.210`) – jetzt nur volle
  IPv4-Punktnotation oder IPv6.
- `50 - Misc/readTimeSyncStatus.ps1`: Ausgaben von `w32tm` auf stderr führten
  unter Windows PowerShell 5.1 mit `ErrorActionPreference = Stop` zum Abbruch,
  bevor der Exitcode ausgewertet wurde.
- `01 - System/checkDiskSpace.ps1`: ein gesperrtes/unformatiertes Volume (z. B.
  BitLocker) ließ die ganze Prüfung mit Exit `1` scheitern – es wird jetzt unter
  `UnavailableDrives` gemeldet; Exit `1` nur, wenn kein Laufwerk auswertbar ist.
- `Get-Help` lieferte in 29 Skripten keine Hilfe, weil `<#` direkt auf
  `#Requires` folgte – Leerzeile ergänzt.
  / `Get-Help` returned no help in 29 scripts because `<#` directly followed
  `#Requires`; a blank line was added.

### Performance
- `00-readDNSSettingsClient.ps1`: `Get-ComputerInfo` (oft 10–60 s) durch
  `Get-CimInstance` ersetzt; WMI-Fallback nutzt CIM statt `Get-WmiObject`.
- `01-setDNSSettingsClient.ps1`: keine überflüssigen `Get-NetAdapterHardwareInfo`-Aufrufe.
- `10 - Network/auditTcpConnections.ps1`: filtert den Verbindungsstatus direkt
  über `Get-NetTCPConnection -State` statt alle Verbindungen zu laden.
- `50 - Misc/emptyFolders.ps1`: kein zusätzliches `Get-Item` pro Ordner mehr
  (DirectoryInfo-Objekte werden direkt eingereiht).

### Dokumentation / Documentation
- Neu: `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (MIT, wie in
  der README angegeben).
- DNS-README/-Guides: defekte Links auf das alte Repository/alte Pfade, veraltete
  Skriptnamen und Inhaltsverzeichnis-Anker korrigiert; Exitcodes und
  Rotationsverhalten präzisiert.
- `.EXAMPLE`-Abschnitte in allen Skripten; fehlende `.DESCRIPTION`/Exitcode-Hinweise ergänzt.

### Tests
- Neu: `Tests/DnsScripts.Tests.ps1` (Pester, Windows-Cmdlets simuliert) für
  Adapterauswahl, Fallback, WhatIf, Custom Fields, Mismatch und Rotation.
- `Tests/SystemChecks.Tests.ps1`: Test für nicht auswertbare Volumes ergänzt.

## 2026-10-11 – PR [#1](https://github.com/PS-PhinIT/PhinIT.NinjaONE-Scripts/pull/1): 51 NinjaOne-PowerShell-Skripte mit DE/EN-Hilfe

### Hinzugefügt / Added
- Bilinguale Diagnose-Skripte `readSystemInfo.ps1`, `readUptime.ps1`,
  `restartPendingCheck.ps1` inkl. Pester-Tests (`Tests/Diagnostics.Tests.ps1`).
- Katalog mit mindestens fünf Skripten je Themenordner (System, Updates, Software,
  Zertifikate, DNS, BitLocker, Security, Netzwerk, Benutzer, Misc); leere
  Platzhalter implementiert, `Tests/SystemChecks.Tests.ps1`.
- `checkChocolateyStatus.ps1` (nach `03 - Software` verschoben) als reine
  Bereitschaftsdiagnose ohne Installation/Bootstrap-Download.
- Einheitliche NinjaOne-Integration: Skriptvariablen, optionales
  `resultCustomField`, explizite Parameter vor Umgebungsvariablen,
  dokumentierte Rückgabecodes, keine still abgeschnittenen Feldberichte.

### Sicherheit / Security
- Wartung/Richtlinienänderungen/AD-DS-Escrow nur per ausdrücklichem Opt-in;
  kein Klartext-Export von Recovery-Passwörtern oder privaten Schlüsseln;
  leere Ordner werden nur gemeldet; TCP-Test auf ein Ziel begrenzt.
- Opt-in-Update-Wartung für unbeaufsichtigte NinjaOne-Läufe angepasst.

## 2025-10-30

### Sicherheit / Security
- Authenticode-Signaturblock für `00-readDNSSettingsClient.ps1` und
  `01-setDNSSettingsClient.ps1` hinzugefügt.

## 2025-05-30

### Geändert / Changed
- DNS-Skripte: Umstellung der Bezeichnungen NinjaRMM → NinjaOne.
- `NinjaONE-DNS_Guide_DE.md` überarbeitet (Custom Field `DNS_Summary`, Import).

## 2025-05-28 – Erstveröffentlichung / Initial release

### Hinzugefügt / Added
- Initial commit und README.
- DNS-Skripte `readDNSSettingsClient.ps1` und `setDNSSettingsClient.ps1`
  (später `00-`/`01-`-Präfix) mit Custom-Field-Integration, CSV-Bericht und
  `netsh`-Fallback.
- NinjaOne-Integrationsleitfaden (DE/EN) und DNS-README (DE/EN).
- Ordnerstruktur `01 - System` … `50 - Misc` mit Platzhalterdateien.
