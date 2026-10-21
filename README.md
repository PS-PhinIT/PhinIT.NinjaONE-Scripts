# NinjaOne Script-Collection ⚙️

---

**Willkommen in meinem  GitHub-Repository für NinjaOne.**

---

# Infos
* Windows Skripte, sortiert nach Themen.  
* Jede Skriptdatei enthält eine ausführ­liche `Synopsis`

# Voraussetzungen
* NinjaOne-Agent ≥ v5.3
* Windows PowerShell 5.1
* Für einige Module: .NET 4.8 oder höher

# Mitwirken
* Pull-Requests und Issues sind willkommen! Regeln: [CONTRIBUTING.md](CONTRIBUTING.md)
* Änderungshistorie: [CHANGELOG.md](CHANGELOG.md)
* Sicherheitslücken bitte vertraulich melden: [SECURITY.md](SECURITY.md)

# Diagnose-Skripte / Diagnostic scripts

Die folgenden Skripte sind eigenständig und enthalten deutsche und englische
Hilfetexte und Kommentare. Sie verändern keine Windows-Einstellungen und lösen
keinen Neustart aus. / These standalone scripts include German and English help
and comments. They do not change Windows settings or initiate a reboot.

| Skript / Script | NinjaOne-Skriptvariable / Script variable | Geräteattribut / Device custom field |
| --- | --- | --- |
| [readSystemInfo.ps1](01%20-%20System/readSystemInfo.ps1) | `systemInfoCustomField` (Text) | MultiLine: grundlegende Systemdaten als JSON / basic system data as JSON |
| [readUptime.ps1](01%20-%20System/readUptime.ps1) | `maximumUptimeHours` (Integer, Standard/default `720`); `uptimeCustomField` (Text) | Integer: abgerundete Laufzeit in Stunden / whole uptime hours |
| [restartPendingCheck.ps1](50%20-%20Misc/restartPendingCheck.ps1) | `rebootPendingCustomField` (Text) | Checkbox: Neustart-Indikator / reboot indicator |

## Einrichtung in NinjaOne / NinjaOne setup

1. Skript in die Automatisierungsbibliothek importieren: Windows, PowerShell,
   SYSTEM, 64-Bit. / Import into the automation library: Windows, PowerShell,
   SYSTEM, 64-bit.
2. Die Variablen mit den **exakten Namen** aus der Tabelle anlegen. NinjaOne
   übergibt sie als Umgebungsvariablen; PowerShell-Parameter haben Vorrang.
   / Create variables using the **exact names** above. NinjaOne injects them as
   environment variables; explicit PowerShell parameters take precedence.
3. Optional Geräte-Custom-Fields mit dem angegebenen Typ anlegen und
   Skript-Schreibzugriff erlauben. Die Textvariable enthält den **internen
   Feldnamen**, nicht dessen Anzeigenamen oder Wert. Zum Beispiel:
   `uptimeCustomField` = `uptimeHours`. Leere Werte oder `null` deaktivieren den
   Feldexport; die Diagnose bleibt aktiv.
   / Optionally create device custom fields of the specified types and allow
   script write access. The text variable contains the **internal field name**,
   not its display name or value. For example: `uptimeCustomField` = `uptimeHours`.
   Empty values or `null` disable field export, not diagnostics.
4. `maximumUptimeHours` muss zwischen 1 und 87600 liegen; leer oder `null` bedeutet
   720. Vor dem flächendeckenden Einsatz auf einem Windows-Testgerät prüfen.
   / `maximumUptimeHours` must be between 1 and 87600; empty or `null` means 720.
   Validate on a Windows test device before broad deployment.

**Rückgabecodes / Exit codes:** `0` = erfolgreich bzw. kein Warnindikator /
success or no warning; `1` = ungültige Eingabe, Abfrage- oder Custom-Field-Fehler /
invalid input, query or custom field failure; `2` = Laufzeitgrenze erreicht oder
Neustart-Indikator vorhanden / uptime threshold reached or reboot indicator
present. NinjaOne kann `2` als fehlgeschlagene Automation anzeigen; entsprechende
Überwachung bewusst konfigurieren. / NinjaOne may display `2` as a failed
automation; configure monitoring accordingly.

Die Neustartprüfung umfasst CBS, Windows Update und Dateiumbenennungen, nicht
alle möglichen Anwendungen. Ein Indikator kann veraltet sein; kein automatischer
Neustart wird empfohlen oder durchgeführt. / Reboot checks cover CBS, Windows
Update and file renames, not every application. Indicators can be stale; no
automatic reboot is recommended or performed.

## Prüfung / Validation

Pester-Tests liegen in `Tests/Diagnostics.Tests.ps1` und können mit
`Invoke-Pester -Path ./Tests/Diagnostics.Tests.ps1` ausgeführt werden. CIM- und
NinjaOne-Aufrufe werden isoliert simuliert. Die Windows-Registry-Prüfung muss
zusätzlich unter Windows PowerShell 5.1 auf einem Testgerät mit und ohne
Neustart-Indikatoren geprüft werden, einschließlich Feld-Schreibrechten.
/ Pester tests are in `Tests/Diagnostics.Tests.ps1`; run
`Invoke-Pester -Path ./Tests/Diagnostics.Tests.ps1`. CIM and NinjaOne calls are
simulated in isolation. Also test the Windows registry check on a Windows
PowerShell 5.1 device with and without reboot indicators, including field write
permissions.

## Themenkatalog / Topic catalogue

Die Diagnose-Themenordner enthalten jeweils mindestens 15 eigenständige
Skripte; `08 - Cleanup` (Bereinigung), `09 - Configuration` (Einstellungen) und
`Installations-Scripte` (Silent-Installationen) ändern das System nur nach
ausdrücklichem Opt-in. Für die DNS-Hauptskripte (`00-`/`01-`) gelten ihre eigenen
Anleitungen und Rückgabecodes. / The diagnostic topic folders each contain at
least 15 standalone scripts; `08 - Cleanup`, `09 - Configuration` and
`Installations-Scripte` only change the system after explicit opt-in. The main
DNS scripts (`00-`/`01-`) keep their own guides and exit codes.

| Bereich / Topic | Aufgaben / Tasks |
| --- | --- |
| `01 - System` | Systemdaten, Laufzeit, Speicherplatz, Dienste, Zeitzone, CPU/RAM/Auslagerung, Datenträgerzustand, BIOS/Secure Boot, Akku, Aktivierung, Gerätefehler / system information, uptime, disk space, services, time zone, CPU/RAM/page file, disk health, BIOS/Secure Boot, battery, activation, device problems |
| `02 - Updates` | Update-Status, Cache-Wartung, Dienstreparatur, Update-Inventar, ausstehende/fehlgeschlagene Updates, WSUS/WUfB-Richtlinien, Pause, Zielversion, Komponentenspeicher, Microsoft-365-Kanal / update status, cache maintenance, service repair, inventory, pending/failed updates, WSUS/WUfB policies, pause, target version, component store, Microsoft 365 channel |
| `03 - Software` | Inventar, blockierte/erforderliche Software, Mindestversionen, Autostart, Browser, AppX, Java, VC++, winget, optionale Features, PowerShell-Engines und -Richtlinien / inventory, blocked/required software, minimum versions, startup, browsers, AppX, Java, VC++, winget, optional features, PowerShell engines and policies |
| `04 - Certificates` | Inventar, Ablauf, RDP-/HTTP.sys-/Remote-TLS-Zertifikate, Ketten, schwache Zertifikate, Autoenrollment, Root-Update, SCHANNEL/.NET-TLS / inventory, expiry, RDP/HTTP.sys/remote TLS certificates, chains, weak certificates, auto-enrollment, root update, SCHANNEL/.NET TLS |
| `05 - DNS` | DNS-Konfiguration/-Änderung, Auflösung, Cache, Serverantwort, Registrierung/PTR, hosts-Datei, Suffixe, NRPT, DoH, LLMNR/NetBIOS, DC-SRV-Einträge, DNS-Ereignisse / DNS configuration/change, resolution, cache, server response, registration/PTR, hosts file, suffixes, NRPT, DoH, LLMNR/NetBIOS, DC SRV records, DNS events |
| `06 - Bitlocker` | Verschlüsselung, Schutzmechanismen, TPM, Recovery-Escrow, Compliance, Pause, Richtlinien, Pre-Boot-PIN, Wechseldatenträger, WinRE, Ereignisse / encryption, protectors, TPM, recovery escrow, compliance, suspension, policies, pre-boot PIN, removable drives, WinRE, events |
| `07 - Security` | Defender (inkl. Ausschlüsse/ASR), Firewall, lokale Admins, UAC, SMB1/-Signierung, Credential Guard, LSA-Schutz, NTLM/WDigest, LAPS, RDP, Kennwort-/Überwachungsrichtlinie, fehlgeschlagene Anmeldungen, integrierte Konten / Defender (incl. exclusions/ASR), firewall, local admins, UAC, SMB1/signing, Credential Guard, LSA protection, NTLM/WDigest, LAPS, RDP, password/audit policy, failed logons, built-in accounts |
| `08 - Cleanup` | Temp-Dateien, Papierkorb, Fehlerberichte (WER), Übermittlungsoptimierungs-Cache, Komponentenspeicher (WinSxS), Browser-Cache, veraltete Benutzerprofile, Software-Deinstallation, AppX-Bloatware / temp files, recycle bin, error reports (WER), Delivery Optimization cache, component store (WinSxS), browser cache, stale user profiles, software uninstall, AppX bloatware |
| `09 - Configuration` | Energiesparplan, Zeitzone, Schnellstart, Remotedesktop, Dienst-Starttyp, Registrywerte, USB-Speicher-Richtlinie, Consumer-Funktionen, Edge-Richtlinien, Microsoft-365-Updatekanal / power plan, time zone, Fast Startup, Remote Desktop, service startup type, registry values, USB storage policy, consumer features, Edge policies, Microsoft 365 update channel |
| `10 - Network` | Verbindungen/Ports, Adapter und Linkgeschwindigkeit, Ping/Traceroute/TCP-Test, WLAN, Proxy, VPN, Routing, ARP, IP-Konflikte, Netzwerkprofil, SMB-Freigaben, Internetverbindung / connections/ports, adapters and link speed, ping/traceroute/TCP test, Wi-Fi, proxy, VPN, routing, ARP, IP conflicts, network profile, SMB shares, internet connectivity |
| `11 - User` | Profile (Größe, veraltet, temporär), lokale Benutzer/Gruppen, Sitzungen, Anmelde-/RDP-Verlauf, inaktive/gesperrte Konten, Kennwortablauf, Entra-Join, Autologon / profiles (size, stale, temporary), local users/groups, sessions, logon/RDP history, inactive/locked accounts, password expiry, Entra join, autologon |
| `50 - Misc` | Neustart-Indikatoren, leere Ordner, Zeitsync, Aufgaben, Ereignisse, Bluescreens, unerwartete Abschaltungen, App-/Dienstabstürze, WHEA, Drucker, USB-Verlauf, Temp/große Dateien, Energieplan, Zuverlässigkeit, NinjaOne-Agent / reboot indicators, empty folders, time sync, tasks, events, bug checks, unexpected shutdowns, app/service crashes, WHEA, printers, USB history, temp/large files, power plan, reliability, NinjaOne agent |

| Ordner / Folder | Anzahl / Count | Skriptdateien / Script files |
| --- | --- | --- |
| `01 - System` | 15 | `checkDiskSpace.ps1`, `checkPhysicalDiskHealth.ps1`, `checkRequiredServices.ps1`, `checkSecureBootStatus.ps1`, `checkTimeZone.ps1`, `checkWindowsActivation.ps1`, `readBatteryHealth.ps1`, `readBiosFirmware.ps1`, `readCpuUsage.ps1`, `readDeviceProblems.ps1`, `readMemoryUsage.ps1`, `readPageFileStatus.ps1`, `readSystemInfo.ps1`, `readTopProcesses.ps1`, `readUptime.ps1` |
| `02 - Updates` | 15 | `checkComponentStoreHealth.ps1`, `checkTargetReleaseVersion.ps1`, `checkUpdatePauseState.ps1`, `checkWindowsUpdatePolicy.ps1`, `checkWindowsUpdateServices.ps1`, `checkWsusConfiguration.ps1`, `cleanupWindowsUpdateCache.ps1`, `readDeliveryOptimizationStatus.ps1`, `readHotfixInventory.ps1`, `readLastUpdateInstall.ps1`, `readOfficeUpdateChannel.ps1`, `readPendingUpdates.ps1`, `readUpdateHistoryFailures.ps1`, `readWindowsUpdateStatus.ps1`, `repairWindowsUpdate.ps1` |
| `03 - Software` | 17 | `checkBlockedSoftware.ps1`, `checkChocolateyStatus.ps1`, `checkPowerShellPolicy.ps1`, `checkRequiredSoftware.ps1`, `checkSoftwareServices.ps1`, `checkSoftwareVersion.ps1`, `checkWindowsOptionalFeatures.ps1`, `checkWingetStatus.ps1`, `readAppxProvisionedPackages.ps1`, `readBrowserVersions.ps1`, `readDotNetInventory.ps1`, `readInstalledSoftware.ps1`, `readJavaInstallations.ps1`, `readPowerShellEngines.ps1`, `readRecentSoftwareChanges.ps1`, `readStartupPrograms.ps1`, `readVcRedistInventory.ps1` |
| `04 - Certificates` | 17 | `checkAutoEnrollmentPolicy.ps1`, `checkCertificateChain.ps1`, `checkCertificatePresence.ps1`, `checkCodeSigningCertificates.ps1`, `checkDotNetStrongCrypto.ps1`, `checkExpiredCertificates.ps1`, `checkRdpCertificate.ps1`, `checkRemoteTlsCertificate.ps1`, `checkRootAutoUpdate.ps1`, `checkSchannelProtocols.ps1`, `checkSelfSignedCertificates.ps1`, `checkSslBindingCertificates.ps1`, `checkTrustedRootCertificates.ps1`, `checkWeakCertificates.ps1`, `exportCertificateStore.ps1`, `readCertificateInventory.ps1`, `readDisallowedCertificates.ps1` |
| `05 - DNS` | 16 | `00-readDNSSettingsClient.ps1`, `01-setDNSSettingsClient.ps1`, `checkDnsOverHttps.ps1`, `checkDnsRegistration.ps1`, `checkDnsSuffixSearchList.ps1`, `checkDomainSrvRecords.ps1`, `checkHostsFile.ps1`, `checkLlmnrNetbiosStatus.ps1`, `checkReverseDnsRecord.ps1`, `compareDnsServerResponses.ps1`, `readDnsCache.ps1`, `readDnsClientConfiguration.ps1`, `readDnsClientEvents.ps1`, `readNrptPolicy.ps1`, `resolveDnsName.ps1`, `testDnsServerResponse.ps1` |
| `06 - Bitlocker` | 15 | `auditKeyProtectors.ps1`, `auditVolumeEncryption.ps1`, `checkBitLockerCompliance.ps1`, `checkBitLockerPolicy.ps1`, `checkBitLockerSuspended.ps1`, `checkDeviceEncryptionSupport.ps1`, `checkPreBootAuthentication.ps1`, `checkRemovableDriveEncryption.ps1`, `checkTpmReadiness.ps1`, `checkUsedSpaceOnlyEncryption.ps1`, `checkWinREStatus.ps1`, `exportRecoveryKeys.ps1`, `readBitLockerEventErrors.ps1`, `readBitLockerStatus.ps1`, `readRecoveryKeyEscrowEvents.ps1` |
| `07 - Security` | 19 | `auditWindowsFirewall.ps1`, `checkAnotherSecurityProduct.ps1`, `checkAuditPolicy.ps1`, `checkBuiltinAccounts.ps1`, `checkCredentialGuard.ps1`, `checkDefenderAsrRules.ps1`, `checkDefenderExclusions.ps1`, `checkLapsStatus.ps1`, `checkLegacyAuthentication.ps1`, `checkLsaProtection.ps1`, `checkPasswordPolicy.ps1`, `checkRdpSecurity.ps1`, `checkSmbSigning.ps1`, `checkSmbv1Status.ps1`, `checkUacSettings.ps1`, `checkWindowsDefender.ps1`, `detectUnauthorizedLocalAdmins.ps1`, `enforceScreensaverTimeout.ps1`, `readFailedLogons.ps1` |
| `08 - Cleanup` | 9 | `cleanupBrowserCache.ps1`, `cleanupComponentStore.ps1`, `cleanupDeliveryOptimizationCache.ps1`, `cleanupRecycleBin.ps1`, `cleanupTempFiles.ps1`, `cleanupWindowsErrorReports.ps1`, `removeAppxBloatware.ps1`, `removeStaleUserProfiles.ps1`, `uninstallSoftware.ps1` |
| `09 - Configuration` | 10 | `setConsumerFeatures.ps1`, `setEdgePolicies.ps1`, `setFastStartup.ps1`, `setOfficeUpdateChannel.ps1`, `setPowerPlan.ps1`, `setRegistryValue.ps1`, `setRemoteDesktop.ps1`, `setServiceStartupType.ps1`, `setTimeZone.ps1`, `setUsbStoragePolicy.ps1` |
| `10 - Network` | 18 | `auditFirewallProfiles.ps1`, `auditTcpConnections.ps1`, `checkAdapterLinkSpeed.ps1`, `checkInternetConnectivity.ps1`, `checkIpAddressConflicts.ps1`, `checkNetworkProfile.ps1`, `checkOpenPorts.ps1`, `checkProxySettings.ps1`, `checkVpnConnections.ps1`, `listNetworkAdapters.ps1`, `readArpTable.ps1`, `readRoutingTable.ps1`, `readSmbShares.ps1`, `readWifiProfiles.ps1`, `readWifiStatus.ps1`, `testPingTargets.ps1`, `testTcpEndpoint.ps1`, `testTraceRoute.ps1` |
| `11 - User` | 16 | `checkAutoLogon.ps1`, `checkInactiveLocalUsers.ps1`, `checkLockedOutUsers.ps1`, `checkPasswordNeverExpires.ps1`, `checkStaleProfiles.ps1`, `checkTemporaryProfiles.ps1`, `listLocalGroupMembers.ps1`, `listLocalGroups.ps1`, `listLocalUsers.ps1`, `listUsersProfiles.ps1`, `readEntraJoinStatus.ps1`, `readLastLogonTimes.ps1`, `readLoggedOnUsers.ps1`, `readLogonEvents.ps1`, `readRdpSessionHistory.ps1`, `readUserProfileSizes.ps1` |
| `50 - Misc` | 17 | `checkPowerPlan.ps1`, `checkPrinterStatus.ps1`, `checkTempFolderSize.ps1`, `emptyFolders.ps1`, `readApplicationCrashes.ps1`, `readBugChecks.ps1`, `readEventLogErrors.ps1`, `readLargeFiles.ps1`, `readNinjaAgentStatus.ps1`, `readReliabilityIndex.ps1`, `readScheduledTaskState.ps1`, `readServiceCrashes.ps1`, `readTimeSyncStatus.ps1`, `readUnexpectedShutdowns.ps1`, `readUsbStorageHistory.ps1`, `readWheaErrors.ps1`, `restartPendingCheck.ps1` |
| `Installations-Scripte` | 105 | `install1Password.ps1`, `install7Zip.ps1`, `installAdobeAcrobatReader.ps1`, `installAdvancedIpScanner.ps1`, `installAnyDesk.ps1`, `installAwsCli.ps1`, `installAzureCli.ps1`, `installAzureStorageExplorer.ps1`, `installBitwarden.ps1`, `installBoxDrive.ps1`, `installBraveBrowser.ps1`, `installCiscoJabber.ps1`, `installCiscoWebex.ps1`, `installCitrixWorkspace.ps1`, `installDBeaverCommunity.ps1`, `installDellCommandUpdate.ps1`, `installDotNetAspNetCoreRuntime10.ps1`, `installDotNetAspNetCoreRuntime8.ps1`, `installDotNetDesktopRuntime10.ps1`, `installDotNetDesktopRuntime8.ps1`, `installDotNetHostingBundle10.ps1`, `installDotNetHostingBundle8.ps1`, `installDotNetRuntime10.ps1`, `installDotNetRuntime8.ps1`, `installDrawIo.ps1`, `installDropbox.ps1`, `installEmClient.ps1`, `installEverything.ps1`, `installFoxitPdfEditor.ps1`, `installFoxitPdfReader.ps1`, `installGit.ps1`, `installGoogleChrome.ps1`, `installGoogleDrive.ps1`, `installGoToMeeting.ps1`, `installGpg4win.ps1`, `installGreenshot.ps1`, `installIntelDriverSupportAssistant.ps1`, `installIrfanView.ps1`, `installJabraDirect.ps1`, `installKeePass.ps1`, `installKeePassXC.ps1`, `installLenovoSystemUpdate.ps1`, `installLibreOffice.ps1`, `installMattermostDesktop.ps1`, `installMicrosoft365Apps.ps1`, `installMicrosoftEdge.ps1`, `installMicrosoftEdgeWebView2.ps1`, `installMicrosoftOneDrive.ps1`, `installMicrosoftRemoteHelp.ps1`, `installMobaXterm.ps1`, `installMozillaFirefox.ps1`, `installMozillaFirefoxEsr.ps1`, `installMozillaThunderbird.ps1`, `installMRemoteNG.ps1`, `installMsOdbcSql18.ps1`, `installNextcloudDesktop.ps1`, `installNodeJsLts.ps1`, `installNotepadPlusPlus.ps1`, `installOmnissaHorizonClient.ps1`, `installOnlyOfficeDesktopEditors.ps1`, `installOpenVpn.ps1`, `installOpenVpnConnect.ps1`, `installPdf24Creator.ps1`, `installPdfsamBasic.ps1`, `installPdfXChangeEditor.ps1`, `installPeaZip.ps1`, `installPowerAutomateDesktop.ps1`, `installPowerBIDesktop.ps1`, `installPowerShell7.ps1`, `installPowerToys.ps1`, `installPuTTY.ps1`, `installPython314.ps1`, `installRealVncViewer.ps1`, `installRemoteDesktopManager.ps1`, `installRoyalTs.ps1`, `installShareX.ps1`, `installSonicWallNetExtender.ps1`, `installSplashtopBusiness.ps1`, `installSqlServerManagementStudio.ps1`, `installTailscale.ps1`, `installTeamViewer.ps1`, `installTeamViewerHost.ps1`, `installTemurinJdk21.ps1`, `installTemurinJre11.ps1`, `installTemurinJre17.ps1`, `installTemurinJre21.ps1`, `installTemurinJre25.ps1`, `installTemurinJre8.ps1`, `installTortoiseGit.ps1`, `installTortoiseSvn.ps1`, `installTreeSizeFree.ps1`, `installVcRedist2013X64.ps1`, `installVcRedistX64.ps1`, `installVcRedistX86.ps1`, `installVeraCrypt.ps1`, `installVisualStudioCode.ps1`, `installVlcMediaPlayer.ps1`, `installWinMerge.ps1`, `installWinRar.ps1`, `installWinSCP.ps1`, `installWireGuard.ps1`, `installWireshark.ps1`, `installYubicoAuthenticator.ps1`, `installZoomOutlookPlugin.ps1`, `installZoomWorkplace.ps1` |

### Erweiterung 2026-10-14 / Extension 2026-10-14

Die folgenden Skripte erweitern jeden Themenordner. Alle sind **lesend**
(Diagnose/Prüfung, keine Systemänderung), schreiben optional den JSON-Bericht in
das MultiLine-Feld aus `resultCustomField` und nutzen `0` = OK, `1` = Fehler,
`2` = Warnbefund. Bedeutung von Exit 2, Grenzwerte und Standardwerte stehen in
der Hilfe jedes Skripts (`Get-Help .\skript.ps1 -Full`). Tests:
`Tests/Catalog*.Tests.ps1`.
/ The following scripts extend every topic folder. All are **read-only**
(diagnostics/checks, no system changes), optionally write their JSON report to the
MultiLine field named by `resultCustomField` and use `0` = OK, `1` = error,
`2` = warning finding. Exit 2 meaning, thresholds and defaults are documented in
each script's help. Tests: `Tests/Catalog*.Tests.ps1`.

#### `01 - System`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkPhysicalDiskHealth.ps1` | Prüft den Zustand physischer Datenträger (Storage-API und optional SMART). | Checks physical disk health (Storage API and optional SMART). | `systemDiskMaxRecords` |
| `checkSecureBootStatus.ps1` | Prüft, ob Secure Boot aktiviert ist. | Checks whether Secure Boot is enabled. | `systemSecureBootAllowUnsupported` |
| `checkWindowsActivation.ps1` | Prüft den Aktivierungsstatus von Windows, ohne Produktschlüssel auszugeben. | Checks the Windows activation status without exposing product keys. | – |
| `readBatteryHealth.ps1` | Meldet Akkustatus und Akkugesundheit (Verschleiß) und warnt unter einem Grenzwert. | Reports battery status and health (wear) and warns below a threshold. | `systemBatteryMinHealthPercent` |
| `readBiosFirmware.ps1` | Meldet BIOS-/Firmware-Hersteller, Version, Datum, Seriennummer und Firmwaretyp. | Reports BIOS/firmware vendor, version, date, serial number and firmware type. | `systemBiosMaxAgeDays` |
| `readCpuUsage.ps1` | Misst die CPU-Auslastung über mehrere Stichproben und warnt über einem Grenzwert. | Samples CPU load over several samples and warns above a threshold. | `systemCpuThresholdPercent`, `systemCpuSampleCount`, `systemCpuSampleIntervalSeconds` |
| `readDeviceProblems.ps1` | Listet Geräte mit Problemcode im Geräte-Manager (ConfigManagerErrorCode). | Lists devices with a Device Manager problem code (ConfigManagerErrorCode). | `systemDeviceMaxRecords`, `systemDeviceIgnoreCodes` |
| `readMemoryUsage.ps1` | Meldet die Arbeitsspeicher- und Commit-Auslastung und warnt über Grenzwerten. | Reports physical memory and commit charge usage and warns above thresholds. | `systemMemoryThresholdPercent`, `systemMemoryCommitThresholdPercent` |
| `readPageFileStatus.ps1` | Meldet Konfiguration und Auslastung der Auslagerungsdatei(en). | Reports page file configuration and usage. | `systemPageFileThresholdPercent` |
| `readTopProcesses.ps1` | Listet die Top-N-Prozesse nach CPU-Zeit oder Arbeitsspeicher (informativ). | Lists the top N processes by CPU time or working set (informational). | `systemTopProcessCount`, `systemTopProcessSortBy` |

#### `02 - Updates`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkComponentStoreHealth.ps1` | Prüft den Komponentenspeicher (WinSxS) schnell und schreibgeschützt mit DISM /CheckHealth. | Checks the component store (WinSxS) quickly and read-only with DISM /CheckHealth. | – |
| `checkTargetReleaseVersion.ps1` | Vergleicht installierte Windows-Version mit der TargetReleaseVersion-Richtlinie. | Compares the installed Windows version with the TargetReleaseVersion policy. | `updateTargetExpectedVersion`, `updateTargetExpectedProduct` |
| `checkUpdatePauseState.ps1` | Prüft, ob Windows Updates lokal, per Gruppenrichtlinie oder MDM pausiert sind. | Checks whether Windows updates are paused locally, by Group Policy or by MDM. | – |
| `checkWindowsUpdatePolicy.ps1` | Prüft Richtlinien für automatische Updates und Windows-Update-for-Business-Rückstellungen. | Checks automatic update policies and Windows Update for Business deferrals. | `updatePolicyMaxQualityDeferralDays` |
| `checkWsusConfiguration.ps1` | Prüft die WSUS-Richtlinienkonfiguration (WUServer, UseWUServer, Zielgruppe). | Checks the WSUS policy configuration (WUServer, UseWUServer, target group). | `updateWsusExpectedServer`, `updateWsusExpectedTargetGroup` |
| `readDeliveryOptimizationStatus.ps1` | Liest Status und Konfiguration der Übermittlungsoptimierung (Delivery Optimization). | Reads Delivery Optimization status and configuration. | – |
| `readLastUpdateInstall.ps1` | Ermittelt die Tage seit der letzten erfolgreichen Updateinstallation. | Determines the days since the last successful update installation. | `updateLastInstallMaxDays`, `updateLastInstallIncludeDefinitions` |
| `readOfficeUpdateChannel.ps1` | Liest Updatekanal und Updatestatus von Microsoft 365 Apps (Klick-und-Los). | Reads the update channel and update state of Microsoft 365 Apps (Click-to-Run). | `updateOfficeExpectedChannel` |
| `readPendingUpdates.ps1` | Listet ausstehende Softwareupdates (nur Suche, kein Download/keine Installation). | Lists pending software updates (search only, no download/no installation). | `updatePendingWarnOn`, `updatePendingOnlineSearch`, `updatePendingMaxRecords` |
| `readUpdateHistoryFailures.ps1` | Meldet fehlgeschlagene/abgebrochene Einträge im Windows-Update-Verlauf der letzten N Tage. | Reports failed/aborted Windows Update history entries of the last N days. | `updateFailureDays`, `updateFailureMaxRecords` |

#### `03 - Software`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkRequiredSoftware.ps1` | Prüft, ob vorgegebene Software maschinenweit installiert ist (Pflichtliste), ohne etwas zu installieren. | Checks that required software is installed machine-wide (allow/required list) without installing anything. | `softwareRequiredNames`, `softwareRequiredMatchMode` |
| `checkSoftwareVersion.ps1` | Prüft, ob eine installierte Software mindestens eine vorgegebene Version hat. | Checks that an installed software product meets a minimum version. | `softwareVersionName`, `softwareVersionMinimum`, `softwareVersionMatchMode`, `softwareVersionMissingIsWarning` |
| `checkWindowsOptionalFeatures.ps1` | Prüft, dass unsichere optionale Windows-Features deaktiviert und geforderte Features aktiviert sind. | Checks that insecure Windows optional features are disabled and required features are enabled. | `softwareFeaturesMustBeDisabled`, `softwareFeaturesMustBeEnabled` |
| `checkWingetStatus.ps1` | Prüft, ob winget.exe (App Installer) für SYSTEM auffindbar ist, ohne etwas zu installieren. | Checks whether winget.exe (App Installer) can be located for SYSTEM without installing anything. | `softwareWingetRequired`, `softwareWingetMinimumVersion` |
| `readAppxProvisionedPackages.ps1` | Inventarisiert provisionierte AppX-Pakete des Images; optional Warnung bei unerwünschten Paketen. | Inventories provisioned AppX packages of the image; optionally warns about unwanted packages. | `softwareAppxUnwantedNames`, `softwareAppxMaxRecords` |
| `readBrowserVersions.ps1` | Liest die Dateiversionen von Chrome, Edge, Firefox und Brave; optional Mindestversionen je Browser. | Reads file versions of Chrome, Edge, Firefox and Brave; optional minimum versions per browser. | `softwareBrowserMinChrome`, `softwareBrowserMinEdge`, `softwareBrowserMinFirefox`, `softwareBrowserMinBrave` |
| `readJavaInstallations.ps1` | Inventarisiert Java-Laufzeiten/JDKs (Oracle, OpenJDK, Adoptium, Zulu, Microsoft u. a.) mit Hersteller und Version. | Inventories Java runtimes/JDKs (Oracle, OpenJDK, Adoptium, Zulu, Microsoft etc.) with vendor and version. | `softwareJavaWarnIfPresent`, `softwareJavaMinimumVersion` |
| `readPowerShellEngines.ps1` | Meldet installierte PowerShell-Engines (2.0, 5.1, 7.x) und warnt, wenn PowerShell 2.0 aktiviert ist. | Reports installed PowerShell engines (2.0, 5.1, 7.x) and warns if PowerShell 2.0 is enabled. | – |
| `readRecentSoftwareChanges.ps1` | Listet MSI-Installationen und -Deinstallationen der letzten N Tage aus dem Anwendungsprotokoll. | Lists MSI installs and uninstalls of the last N days from the Application log. | `softwareChangesDays`, `softwareChangesMaxEvents`, `softwareChangesWarnOnChange` |
| `readStartupPrograms.ps1` | Inventarisiert Autostart-Einträge (Win32_StartupCommand und HKLM Run/RunOnce), optional mit Allowlist. | Inventories startup entries (Win32_StartupCommand and HKLM Run/RunOnce), optionally against an allowlist. | `softwareStartupAllowedNames`, `softwareStartupMaxRecords`, `softwareStartupIncludeCommands` |
| `readVcRedistInventory.ps1` | Inventarisiert Visual C++ Redistributables (Jahr, Architektur, Version) und meldet nicht mehr unterstützte. | Inventories Visual C++ Redistributables (year, architecture, version) and reports out-of-support ones. | `softwareVcRedistWarnUnsupported`, `softwareVcRedistUnsupportedYears` |

#### `04 - Certificates`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkAutoEnrollmentPolicy.ps1` | Liest und dekodiert die Computer-Richtlinie für Zertifikat-Autoregistrierung (AEPolicy). | Reads and decodes the computer certificate autoenrollment policy (AEPolicy). | `certAutoEnrollRequireEnabled` |
| `checkCertificateChain.ps1` | Baut Zertifikatsketten für Maschinenzertifikate mit privatem Schlüssel und meldet Kettenfehler. | Builds certificate chains for machine certificates with a private key and reports chain errors. | `certChainRevocationMode`, `certChainMaxCertificates` |
| `checkCertificatePresence.ps1` | Prüft, ob bestimmte Zertifikate (Thumbprint und/oder exakter Betreff) in einem Maschinenspeicher vorhanden und gültig sind. | Checks whether specific certificates (thumbprint and/or exact subject) exist and are valid in a machine store. | `certPresenceStoreName`, `certPresenceThumbprints`, `certPresenceSubject` |
| `checkCodeSigningCertificates.ps1` | Prüft Codesignatur-Zertifikate (EKU 1.3.6.1.5.5.7.3.3) in LocalMachine\My und TrustedPublisher auf Ablauf. | Checks code-signing certificates (EKU 1.3.6.1.5.5.7.3.3) in LocalMachine\My and TrustedPublisher for expiry. | `certCodeSigningWarningDays`, `certCodeSigningMaxRecords` |
| `checkDotNetStrongCrypto.ps1` | Prüft SchUseStrongCrypto und SystemDefaultTlsVersions für .NET Framework (64- und 32-Bit). | Checks SchUseStrongCrypto and SystemDefaultTlsVersions for .NET Framework (64- and 32-bit). | `certDotNetIncludeV2` |
| `checkRdpCertificate.ps1` | Prüft das Zertifikat des RDP-Listeners RDP-Tcp (Ablauf, selbst signiert). | Checks the certificate of the RDP-Tcp listener (expiry, self-signed). | `certRdpWarningDays`, `certRdpFailOnSelfSigned` |
| `checkRemoteTlsCertificate.ps1` | Prüft das TLS-Zertifikat genau eines entfernten Endpunkts (Host:Port). | Checks the TLS certificate of exactly one remote endpoint (host:port). | `certTlsTargetHost`, `certTlsTargetPort`, `certTlsTimeoutMs`, `certTlsWarningDays` |
| `checkRootAutoUpdate.ps1` | Prüft automatische Aktualisierung von Stamm- und nicht vertrauenswürdigen Zertifikaten. | Checks automatic updates of root and untrusted (disallowed) certificates. | `certRootMaxSyncAgeDays` |
| `checkSchannelProtocols.ps1` | Meldet die SCHANNEL-Protokollkonfiguration (SSL 2.0 bis TLS 1.3, Server/Client). | Reports the SCHANNEL protocol configuration (SSL 2.0 to TLS 1.3, server/client). | `certSchannelStrictMode` |
| `checkSslBindingCertificates.ps1` | Prüft Zertifikate der HTTP.sys-SSL-Bindungen (netsh http show sslcert). | Checks certificates of HTTP.sys SSL bindings (netsh http show sslcert). | `certSslBindingWarningDays`, `certSslBindingMaxRecords` |
| `checkWeakCertificates.ps1` | Findet Zertifikate mit schwacher Signatur (MD2/MD4/MD5/SHA1) oder zu kurzen Schlüsseln. | Finds certificates with weak signatures (MD2/MD4/MD5/SHA1) or short keys. | `certWeakAdditionalStores`, `certWeakMaxRecords` |
| `readDisallowedCertificates.ps1` | Inventarisiert LocalMachine\Disallowed (nicht vertrauenswürdige Zertifikate), optional mit Pflichtliste. | Inventories LocalMachine\Disallowed (untrusted certificates), optionally with a required list. | `certDisallowedRequiredThumbprints`, `certDisallowedMaxRecords` |

#### `05 - DNS`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkDnsOverHttps.ps1` | Meldet DNS-over-HTTPS-Konfiguration und prüft optional, ob DoH verlangt wird. | Reports DNS-over-HTTPS configuration and optionally checks that DoH is required. | `dnsRequireDoh` |
| `checkDnsRegistration.ps1` | Prüft, ob der eigene DNS-Eintrag (A/AAAA) zu den lokalen IP-Adressen passt. | Checks whether the own DNS record (A/AAAA) matches the local IP addresses. | `dnsRegistrationFqdn`, `dnsRegistrationServer` |
| `checkDnsSuffixSearchList.ps1` | Vergleicht DNS-Suffixsuchliste und primäres DNS-Suffix mit Sollwerten. | Compares the DNS suffix search list and primary DNS suffix with expected values. | `dnsExpectedSuffixSearchList`, `dnsSuffixOrderMatters`, `dnsExpectedPrimarySuffix` |
| `checkDomainSrvRecords.ps1` | Prüft die DNS-SRV-Einträge der Domänencontroller (LDAP/Kerberos). | Checks the domain controller DNS SRV records (LDAP/Kerberos). | `dnsSrvServer` |
| `checkHostsFile.ps1` | Prüft aktive Einträge der hosts-Datei gegen eine optionale Positivliste. | Checks active hosts file entries against an optional allowlist. | `dnsHostsAllowList`, `dnsHostsWarnOnAnyEntry`, `dnsHostsMaxRecords` |
| `checkLlmnrNetbiosStatus.ps1` | Härtungsprüfung für LLMNR, NetBIOS über TCP/IP und mDNS. | Hardening check for LLMNR, NetBIOS over TCP/IP and mDNS. | `dnsRequireMdnsDisabled` |
| `checkReverseDnsRecord.ps1` | Prüft PTR-Einträge der lokalen IPv4-Adressen gegen Hostname/FQDN. | Checks PTR records of local IPv4 addresses against host name/FQDN. | `dnsReverseExpectedName`, `dnsReverseServer` |
| `compareDnsServerResponses.ps1` | Vergleicht die A/AAAA-Antworten mehrerer DNS-Server für einen Namen. | Compares A/AAAA answers of several DNS servers for one name. | `dnsCompareHostName`, `dnsCompareServers`, `dnsCompareRecordType` |
| `readDnsClientEvents.ps1` | Zählt DNS-Client-Ereignisse (z. B. 1014 Timeout) gruppiert nach Name. | Counts DNS client events (e.g. 1014 timeout) grouped by name. | `dnsEventHours`, `dnsEventThreshold`, `dnsEventIds`, `dnsEventMaxEvents`, `dnsEventMaxRecords` |
| `readNrptPolicy.ps1` | Inventarisiert NRPT-Richtlinie und -Regeln des DNS-Clients (begrenzt). | Inventories the DNS client NRPT policy and rules (bounded). | `dnsNrptMaxRecords` |
| `testDnsServerResponse.ps1` | Prüft Antwort und Latenz jedes DNS-Servers mit einem Testnamen. | Tests response and latency of each DNS server with a test name. | `dnsTestName`, `dnsTestServers`, `dnsLatencyThresholdMs` |

#### `06 - Bitlocker`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkBitLockerCompliance.ps1` | Prüft, ob Betriebssystem- und feste Datenvolumes vollständig mit BitLocker geschützt sind. | Checks whether operating system and fixed data volumes are fully protected by BitLocker. | `bitlockerAllowedEncryptionMethods`, `bitlockerIncludeFixedDataDrives` |
| `checkBitLockerPolicy.ps1` | Liest die BitLocker-Gruppenrichtlinienwerte (FVE) und dekodiert sie in Namen. | Reads BitLocker Group Policy (FVE) values and decodes them to names. | `bitlockerExpectedMinimumMethod` |
| `checkBitLockerSuspended.ps1` | Erkennt verschlüsselte Volumes mit angehaltenem (suspendiertem) BitLocker-Schutz. | Detects encrypted volumes whose BitLocker protection is suspended. | – |
| `checkDeviceEncryptionSupport.ps1` | Prüft die Voraussetzungen für die automatische Geräteverschlüsselung (Device Encryption). | Checks prerequisites for automatic device encryption. | `bitlockerRequireDeviceEncryptionSupport` |
| `checkPreBootAuthentication.ps1` | Prüft die Pre-Boot-Authentifizierung (TPM/TPM+PIN) des Betriebssystemvolumes. | Checks pre-boot authentication (TPM/TPM+PIN) of the operating system volume. | `bitlockerRequirePin` |
| `checkRemovableDriveEncryption.ps1` | Prüft angeschlossene Wechseldatenträger auf BitLocker-Verschlüsselung (BitLocker To Go). | Checks attached removable drives for BitLocker encryption (BitLocker To Go). | `bitlockerRequireRemovableEncryption` |
| `checkUsedSpaceOnlyEncryption.ps1` | Ermittelt je Volume, ob BitLocker nur den belegten Speicher oder den ganzen Datenträger verschlüsselt hat. | Determines per volume whether BitLocker encrypted used space only or the full disk. | `bitlockerRequireFullDiskEncryption` |
| `checkWinREStatus.ps1` | Prüft, ob die Windows-Wiederherstellungsumgebung (WinRE) aktiviert ist, und meldet den Speicherort. | Checks whether the Windows Recovery Environment (WinRE) is enabled and reports its location. | – |
| `readBitLockerEventErrors.ps1` | Fasst BitLocker-Fehler- und Warnereignisse der letzten Tage nach Ereignis-ID zusammen. | Summarizes BitLocker error and warning events of the last days grouped by event ID. | `bitlockerEventDays`, `bitlockerEventMaxEvents`, `bitlockerEventMaxRecords` |
| `readRecoveryKeyEscrowEvents.ps1` | Wertet BitLocker-Escrow-Ereignisse (Sicherung in Entra ID / AD DS) für das OS-Volume aus. | Evaluates BitLocker escrow events (backup to Entra ID / AD DS) for the OS volume. | `bitlockerEscrowDays`, `bitlockerEscrowMaxEvents`, `bitlockerEscrowTarget`, `bitlockerEscrowRequireEvent` |

#### `07 - Security`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkAuditPolicy.ps1` | Prueft die erweiterte Ueberwachungsrichtlinie gegen eine Liste Pflicht-Unterkategorien (GUID-basiert). | Checks the advanced audit policy against a list of required subcategories (GUID based). | `securityAuditRequiredSubcategories` |
| `checkBuiltinAccounts.ps1` | Prueft eingebaute lokale Konten (Administrator -500, Gast -501, DefaultAccount -503) per SID. | Checks built-in local accounts (Administrator -500, Guest -501, DefaultAccount -503) by SID. | `securityAllowBuiltinAdminEnabled`, `securityRequireBuiltinAdminRenamed` |
| `checkCredentialGuard.ps1` | Prueft, ob Credential Guard und optional HVCI (Speicherintegritaet) laufen. | Checks whether Credential Guard and optionally HVCI (memory integrity) are running. | `securityRequireCredentialGuard`, `securityRequireHvci` |
| `checkDefenderAsrRules.ps1` | Meldet Microsoft-Defender-ASR-Regeln mit Namen und Modus und prueft optionale Pflichtregeln. | Reports Microsoft Defender ASR rules with name and mode and checks optional required rules. | `securityAsrRequiredRules`, `securityAsrAllowAudit` |
| `checkDefenderExclusions.ps1` | Inventarisiert Microsoft-Defender-Ausschluesse und vergleicht sie mit einer Allowlist. | Inventories Microsoft Defender exclusions and compares them with an allowlist. | `securityDefenderExclusionAllowlist`, `securityDefenderWarnOnAnyExclusion`, `securityDefenderWarnOnHiddenExclusions`, `securityDefenderExclusionMaxRecords` |
| `checkLapsStatus.ps1` | Prueft Windows-LAPS-/Legacy-LAPS-Konfiguration und Rotationsereignisse, ohne Kennwoerter zu lesen. | Checks Windows LAPS / legacy LAPS configuration and rotation events without reading passwords. | `securityLapsMaxSuccessAgeDays` |
| `checkLegacyAuthentication.ps1` | Prueft Legacy-Authentifizierung: LM/NTLM-Stufe, LM-Hashes, WDigest und Anonymous-Einschraenkungen. | Audits legacy authentication: LM/NTLM level, LM hashes, WDigest and anonymous restrictions. | `securityLmCompatibilityMinimum` |
| `checkLsaProtection.ps1` | Prueft den LSA-Schutz (LSASS als geschuetzter Prozess, RunAsPPL). | Checks LSA protection (LSASS as a protected process, RunAsPPL). | `securityLsaCheckEvent`, `securityLsaRequireEvent` |
| `checkPasswordPolicy.ps1` | Prueft lokale Kennwort- und Sperrrichtlinie sprachunabhaengig per secedit-Export. | Checks local password and lockout policy locale-independently via secedit export. | `securityPasswordMinLength`, `securityPasswordRequireComplexity`, `securityPasswordMinHistory`, `securityPasswordMaxAgeDays`, `securityLockoutMaxThreshold` |
| `checkRdpSecurity.ps1` | Prueft die RDP-Sicherheitskonfiguration (NLA, SecurityLayer, Verschluesselung, Port) nur lesend. | Checks the RDP security configuration (NLA, security layer, encryption, port) read-only. | `securityRdpAllow` |
| `checkSmbSigning.ps1` | Prueft, ob SMB-Signierung fuer Server und/oder Client erzwungen wird. | Checks whether SMB signing is required for the server and/or client. | `securitySmbSigningRequiredSide`, `securitySmbRequireEncryption` |
| `checkSmbv1Status.ps1` | Prueft, ob SMBv1 (Server, Client-Treiber oder optionales Feature) aktiv ist. | Checks whether SMBv1 (server, client driver or optional feature) is enabled. | `securitySmb1IncludeFeature` |
| `checkUacSettings.ps1` | Prueft die Einstellungen der Benutzerkontensteuerung (UAC), ohne etwas zu aendern. | Audits User Account Control (UAC) settings without changing anything. | – |
| `readFailedLogons.ps1` | Zaehlt fehlgeschlagene Anmeldungen (4625) und Kontosperrungen (4740) begrenzt und gruppiert. | Counts failed logons (4625) and account lockouts (4740), bounded and grouped. | `securityFailedLogonHours`, `securityFailedLogonThreshold`, `securityFailedLogonMaxEvents`, `securityFailedLogonMaxRecords` |

#### `10 - Network`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkAdapterLinkSpeed.ps1` | Prüft die Verbindungsgeschwindigkeit physischer, verbundener Netzwerkadapter. | Checks the link speed of physical, connected network adapters. | `networkMinLinkSpeedMbps`, `networkLinkSpeedIncludeWireless` |
| `checkInternetConnectivity.ps1` | Internetverbindung im NCSI-Stil pruefen. EN: Check internet connectivity NCSI-style. | Check internet connectivity NCSI-style. | `networkProbeUrl`, `networkProbeExpectedContent`, `networkProbeDnsHost`, `networkProbeTimeoutMs` |
| `checkIpAddressConflicts.ps1` | Erkennt IP-Adresskonflikte, APIPA-Adressen und ungültige Adresszustände. | Detects IP address conflicts, APIPA addresses and invalid address states. | `networkConflictDays`, `networkConflictMaxEvents` |
| `checkNetworkProfile.ps1` | Prüft die Netzwerkkategorie (Firewallprofil) aktiver Verbindungen. | Checks the network category (firewall profile) of active connections. | `networkExpectedCategory` |
| `checkProxySettings.ps1` | Maschinenweite Proxy-Einstellungen pruefen. EN: Check machine-wide proxy settings. | Check machine-wide proxy settings. | `networkExpectedProxy` |
| `checkVpnConnections.ps1` | VPN-Verbindungen fuer alle Benutzer inventarisieren. EN: Inventory all-user VPN connections. | Inventory all-user VPN connections. | `networkRequiredVpnName`, `networkVpnMaxRecords` |
| `readArpTable.ps1` | Liest die IPv4-ARP-Tabelle begrenzt aus und erkennt mögliches ARP-Spoofing. | Reads a bounded IPv4 ARP table and detects possible ARP spoofing. | `networkArpExcludeNoise`, `networkArpMaxRecords` |
| `readRoutingTable.ps1` | Liest die Routingtabelle begrenzt aus und prüft IPv4-Standardrouten. | Reads a bounded routing table inventory and checks IPv4 default routes. | `networkRouteAddressFamily`, `networkRouteMaxRecords` |
| `readSmbShares.ps1` | Inventarisiert SMB-Freigaben und meldet zu weit gefasste Freigabeberechtigungen. | Inventories SMB shares and reports overly broad share permissions. | `networkSmbExcludeSpecialShares`, `networkSmbMaxRecords` |
| `readWifiProfiles.ps1` | Gespeicherte WLAN-Profile und deren Sicherheit melden. EN: Report saved Wi-Fi profiles and their security. | Report saved Wi-Fi profiles and their security. | `networkWifiMaxProfiles` |
| `readWifiStatus.ps1` | WLAN-Verbindungsstatus lesen. EN: Read Wi-Fi connection status. | Read Wi-Fi connection status. | `networkMinSignalPercent` |
| `testPingTargets.ps1` | ICMP-Erreichbarkeit von 1..10 Zielen pruefen. EN: Check ICMP reachability of 1..10 targets. | Check ICMP reachability of 1..10 targets. | `networkPingTargets`, `networkPingCount`, `networkPingTimeoutMs`, `networkMaxLossPercent`, `networkMaxLatencyMs` |
| `testTraceRoute.ps1` | Traceroute zu einem Ziel per ICMP und TTL. EN: Trace route to one target via ICMP and TTL. | Trace route to one target via ICMP and TTL. | `networkTraceTarget`, `networkTraceMaxHops`, `networkTraceTimeoutMs` |

#### `11 - User`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkAutoLogon.ps1` | Automatische Windows-Anmeldung (AutoAdminLogon) pruefen. EN: Check automatic Windows logon (AutoAdminLogon). | Check automatic Windows logon (AutoAdminLogon). | – |
| `checkInactiveLocalUsers.ps1` | Inaktive aktivierte lokale Benutzer finden. EN: Find inactive enabled local users. | Find inactive enabled local users. | `userInactiveDays`, `userExcludeBuiltIn`, `userMaxRecords` |
| `checkLockedOutUsers.ps1` | Gesperrte lokale Konten und Sperrereignisse melden. EN: Report locked-out local accounts and lockout events. | Report locked-out local accounts and lockout events. | `userLockoutEventHours`, `userMaxRecords` |
| `checkPasswordNeverExpires.ps1` | Lokale Konten mit nie ablaufendem/nicht erforderlichem Kennwort finden. EN: Find local accounts with non-expiring or not-required passwords. | Find local accounts with non-expiring or not-required passwords. | `userPasswordCheckMode`, `userPasswordAllowlist`, `userMaxRecords` |
| `checkStaleProfiles.ps1` | Veraltete, nicht geladene Benutzerprofile melden (ohne Loeschung). EN: Report stale unloaded user profiles (no deletion). | Report stale unloaded user profiles (no deletion). | `userStaleProfileDays`, `userStaleIncludeUnknown`, `userMaxRecords` |
| `checkTemporaryProfiles.ps1` | Temporaere und beschaedigte Benutzerprofile erkennen. EN: Detect temporary and corrupted user profiles. | Detect temporary and corrupted user profiles. | `userTempProfileEventDays`, `userMaxRecords` |
| `readEntraJoinStatus.ps1` | Entra-ID-/Domaenen-Beitrittsstatus des Geraets lesen. EN: Read the device Entra ID/domain join state. | Read the device Entra ID/domain join state. | `userExpectedJoinType` |
| `readLoggedOnUsers.ps1` | Aktuell angemeldete Benutzersitzungen lesen. EN: Read currently logged-on user sessions. | Read currently logged-on user sessions. | `userMaxRecords` |
| `readLogonEvents.ps1` | Interaktive Anmeldungen (Security 4624) je Benutzer zusammenfassen. EN: Summarize interactive logons (Security 4624) per user. | Summarize interactive logons (Security 4624) per user. | `userLogonTypes`, `userLogonEventDays`, `userLogonMaxEvents`, `userMaxRecords` |
| `readRdpSessionHistory.ps1` | RDP-/Sitzungsverlauf aus dem LocalSessionManager-Protokoll lesen. EN: Read RDP/session history from the LocalSessionManager log. | Read RDP/session history from the LocalSessionManager log. | `userRdpHistoryDays`, `userRdpMaxEvents`, `userMaxRecords` |
| `readUserProfileSizes.ps1` | Groesse der Benutzerprofilordner zeitbegrenzt messen. EN: Measure user profile folder sizes within a time budget. | Measure user profile folder sizes within a time budget. | `userProfileSizeBudgetSeconds`, `userProfileSizeThresholdGB`, `userMaxRecords` |

#### `50 - Misc`

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `checkPowerPlan.ps1` | Liest den aktiven Energiesparplan und vergleicht ihn optional mit einem Sollwert. | Reads the active power plan and optionally compares it with an expected plan. | `powerExpectedPlan` |
| `checkPrinterStatus.ps1` | Prüft Druckwarteschlangendienst, Druckerfehler und hängende Druckaufträge. | Checks the print spooler service, printer errors and stuck print jobs. | `printerStuckJobMinutes`, `printerWarnOffline`, `printerMaxRecords` |
| `checkTempFolderSize.ps1` | Misst die Größe temporärer Ordner (System- und optional Benutzer-Temp), ohne zu löschen. | Measures the size of temporary folders (system and optionally user temp) without deleting. | `tempThresholdMB`, `tempIncludeUserProfiles`, `tempTimeBudgetSeconds`, `tempMaxRecords` |
| `readApplicationCrashes.ps1` | Meldet Anwendungsabstürze und -hänger, gruppiert nach Anwendung. | Reports application crashes and hangs grouped by application. | `appCrashLookbackDays`, `appCrashThreshold`, `appCrashTopApps` |
| `readBugChecks.ps1` | Meldet Bluescreens (BugChecks) und Minidump-Dateien der letzten Tage. | Reports blue screens (bug checks) and minidump files from recent days. | `bugCheckLookbackDays`, `bugCheckMaxRecords` |
| `readLargeFiles.ps1` | Meldet die größten Dateien unter einem lokalen Pfad (nur Bericht, kein Löschen). | Reports the largest files under a local path (report only, no deletion). | `largeFilesRootPath`, `largeFilesTop`, `largeFilesTimeBudgetSeconds`, `largeFilesMaxFiles` |
| `readNinjaAgentStatus.ps1` | Meldet Status, Version, Installationspfad und Laufzeit der NinjaOne-Agent-Dienste. | Reports state, version, install path and uptime of the NinjaOne agent services. | – |
| `readReliabilityIndex.ps1` | Liest den Windows-Zuverlässigkeitsindex (1..10) und seinen Verlauf. | Reads the Windows reliability (stability) index (1..10) and its trend. | `reliabilityMinimumIndex`, `reliabilityLookbackDays` |
| `readServiceCrashes.ps1` | Meldet abgestürzte und fehlerhafte Windows-Dienste, gruppiert nach Dienst. | Reports crashed and failing Windows services grouped by service. | `serviceCrashLookbackDays`, `serviceCrashMaxRecords` |
| `readUnexpectedShutdowns.ps1` | Meldet unerwartete Herunterfahr-Vorgänge (Kernel-Power 41, EventLog 6008). | Reports unexpected shutdowns (Kernel-Power 41, EventLog 6008). | `shutdownLookbackDays`, `shutdownThreshold`, `shutdownMaxRecords` |
| `readUsbStorageHistory.ps1` | Meldet bekannte USB-Massenspeicher (USBSTOR) und die USBSTOR-Sperrrichtlinie. | Reports known USB mass storage devices (USBSTOR) and the USBSTOR block policy. | `usbIncludeSerial`, `usbRequireBlocked`, `usbMaxRecords` |
| `readWheaErrors.ps1` | Meldet WHEA-Hardwarefehler (korrigiert/schwerwiegend) aus dem System-Log. | Reports WHEA hardware errors (corrected/fatal) from the System log. | `wheaLookbackDays`, `wheaCorrectedThreshold`, `wheaMaxRecords` |

### `08 - Cleanup` – Bereinigung / Cleanup

Alle Skripte arbeiten **ohne Opt-in nur prüfend** (Bericht, was entfernt würde)
und löschen bzw. deinstallieren erst mit der jeweiligen `…Allow`-Variable =
`true`. Sie unterstützen `-WhatIf`/`-Confirm`, schreiben einen JSON-Bericht
(optional in `resultCustomField`) und nutzen `0` = OK/bereinigt, `1` = Fehler,
`2` = Bereinigung nötig, aber nicht erlaubt bzw. Teilfehler (Details in der
Skripthilfe). Tests: `Tests/CatalogCleanup.Tests.ps1`.
/ Without opt-in all scripts only **audit** (report what would be removed) and
only delete/uninstall when their `…Allow` variable is `true`. They support
`-WhatIf`/`-Confirm`, write a JSON report (optionally to `resultCustomField`) and
use `0` = OK/cleaned, `1` = error, `2` = cleanup needed but not allowed or partial
failure (see script help).

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `cleanupBrowserCache.ps1` | Leert nur die Cacheordner von Chrome/Edge/Firefox (keine Verläufe, Kennwörter oder Cookies). | Clears only Chrome/Edge/Firefox cache folders (no history, passwords or cookies). | `cleanupBrowserCacheAllow`, `cleanupBrowserCacheBrowsers`, `cleanupBrowserCacheSkipRunning` |
| `cleanupComponentStore.ps1` | Analysiert und bereinigt den Komponentenspeicher (WinSxS) per DISM, optional `/ResetBase`. | Analyses and cleans the component store (WinSxS) via DISM, optionally `/ResetBase`. | `cleanupComponentStoreAllow`, `cleanupComponentStoreResetBase` |
| `cleanupDeliveryOptimizationCache.ps1` | Meldet und leert den Cache der Übermittlungsoptimierung. | Reports and clears the Delivery Optimization cache. | `cleanupDoAllow`, `cleanupDoMinimumCacheMB` |
| `cleanupRecycleBin.ps1` | Entfernt alte Papierkorb-Elemente aller Benutzer auf festen Laufwerken. | Removes old recycle bin items of all users on fixed drives. | `cleanupRecycleBinAllow`, `cleanupRecycleBinMinimumAgeDays` |
| `cleanupTempFiles.ps1` | Löscht alte Dateien in `C:\Windows\Temp` und optional in Benutzer-Temp-Ordnern, optional leere Ordner. | Deletes old files in `C:\Windows\Temp` and optionally user temp folders, optionally empty folders. | `cleanupTempAllow`, `cleanupTempMinimumAgeDays`, `cleanupTempIncludeUserProfiles`, `cleanupTempRemoveEmptyFolders`, `cleanupTempTimeBudgetSeconds` |
| `cleanupWindowsErrorReports.ps1` | Löscht alte Windows-Fehlerberichte (WER), optional Absturzabbilder. | Deletes old Windows Error Reporting reports, optionally crash dumps. | `cleanupWerAllow`, `cleanupWerMinimumAgeDays`, `cleanupWerIncludeCrashDumps` |
| `removeAppxBloatware.ps1` | Entfernt und deprovisioniert unerwünschte AppX-Apps nach Namensliste. | Removes and deprovisions unwanted AppX apps by name list. | `appxRemoveAllow`, `appxRemoveNames`, `appxRemoveDeprovision` |
| `removeStaleUserProfiles.ps1` | Entfernt lange ungenutzte lokale Benutzerprofile (mit Ausschlussliste und Höchstzahl). | Removes long-unused local user profiles (with exclusion list and maximum count). | `cleanupProfilesAllow`, `cleanupProfilesMinimumAgeDays`, `cleanupProfilesExclude`, `cleanupProfilesMaxRemovals`, `cleanupProfilesIncludeUnknownAge` |
| `uninstallSoftware.ps1` | Deinstalliert Programme still per Anzeigename (MSI-Produktcode oder `QuietUninstallString`/EXE-Schalter). | Silently uninstalls programs by display name (MSI product code or `QuietUninstallString`/EXE switches). | `uninstallSoftwareName`, `uninstallMatchMode`, `uninstallAllow`, `uninstallMaxMatches`, `uninstallExeArguments`, `uninstallTimeoutMinutes` |

### `09 - Configuration` – Einstellungen / Settings

Die Skripte vergleichen den Ist- mit dem Sollzustand und ändern ihn erst mit
der jeweiligen `…Allow`-Variable = `true` (`-WhatIf`/`-Confirm` werden
unterstützt). Rückgabecodes: `0` = konform bzw. geändert, `1` = Fehler,
`2` = Abweichung ohne Opt-in oder per `-Confirm` abgelehnt. Tests:
`Tests/CatalogConfiguration.Tests.ps1`.
/ The scripts compare the current with the desired state and only change it when
their `…Allow` variable is `true` (`-WhatIf`/`-Confirm` supported). Exit codes:
`0` = compliant or changed, `1` = error, `2` = deviation without opt-in or declined via
`-Confirm`.

| Skript / Script | Zweck (DE) | Purpose (EN) | NinjaOne-Variablen / variables |
| --- | --- | --- | --- |
| `setConsumerFeatures.ps1` | Deaktiviert Windows-Consumer-Funktionen (automatische App-Installationen, Vorschläge) per Richtlinie. | Disables Windows consumer features (automatic app installs, suggestions) via policy. | `configConsumerFeaturesDisabled`, `configConsumerFeaturesAllow` |
| `setEdgePolicies.ps1` | Setzt ausgewählte Microsoft-Edge-Computerrichtlinien. | Sets selected Microsoft Edge machine policies. | `configEdgeHideFirstRunExperience`, `configEdgeStartupBoostEnabled`, `configEdgeBackgroundModeEnabled`, `configEdgeShowRecommendationsEnabled`, `configEdgeHomepageLocation`, `configEdgePasswordManagerEnabled`, `configEdgeAllow` |
| `setFastStartup.ps1` | Aktiviert oder deaktiviert den Schnellstart (`HiberbootEnabled`). | Enables or disables Fast Startup (`HiberbootEnabled`). | `configFastStartupEnabled`, `configFastStartupAllow` |
| `setOfficeUpdateChannel.ps1` | Setzt die Richtlinie für den Microsoft-365-Updatekanal, optional Update anstoßen. | Sets the Microsoft 365 update channel policy, optionally triggers an update. | `configOfficeChannel`, `configOfficeTriggerUpdate`, `configOfficeAllow` |
| `setPowerPlan.ps1` | Setzt Energiesparplan sowie Bildschirm- und Standby-Zeitlimits (Netz/Akku). | Sets power plan and monitor/standby timeouts (AC/DC). | `configPowerPlan`, `configPowerMonitorTimeoutAcMinutes`, `configPowerMonitorTimeoutDcMinutes`, `configPowerStandbyTimeoutAcMinutes`, `configPowerStandbyTimeoutDcMinutes`, `configPowerAllow` |
| `setRegistryValue.ps1` | Setzt oder entfernt einen Registrywert unter `HKLM:\SOFTWARE\` bzw. `HKLM:\SYSTEM\CurrentControlSet\` (geschützte Pfade gesperrt). | Sets or removes a registry value under `HKLM:\SOFTWARE\` or `HKLM:\SYSTEM\CurrentControlSet\` (protected paths blocked). | `configRegistryPath`, `configRegistryName`, `configRegistryType`, `configRegistryValue`, `configRegistryAction`, `configRegistryAllow` |
| `setRemoteDesktop.ps1` | Aktiviert/deaktiviert Remotedesktop inkl. NLA und Firewallregeln. | Enables/disables Remote Desktop incl. NLA and firewall rules. | `configRdpEnabled`, `configRdpRequireNla`, `configRdpConfigureFirewall`, `configRdpAllow` |
| `setServiceStartupType.ps1` | Setzt Starttyp und optional Aktion (Start/Stopp/Neustart) eines Dienstes; kritische Dienste sind gesperrt. | Sets a service's startup type and optional action (start/stop/restart); critical services are blocked. | `configServiceName`, `configServiceStartupType`, `configServiceAction`, `configServiceAllow` |
| `setTimeZone.ps1` | Setzt die Windows-Zeitzone, optional mit Zeitsynchronisierung. | Sets the Windows time zone, optionally with time resync. | `configTimeZoneId`, `configTimeZoneResyncTime`, `configTimeZoneAllow` |
| `setUsbStoragePolicy.ps1` | Sperrt USB-Massenspeicher oder setzt einen Schreibschutz. | Blocks USB mass storage or sets write protection. | `configUsbStorageBlocked`, `configUsbStorageDenyWriteOnly`, `configUsbStorageAllow` |

### Installations-Scripte / Installation scripts

Der Ordner `Installations-Scripte` enthält **ein Skript je Tool** für die
unbeaufsichtigte Installation (Silent Install) sowie
[`SilentSwitches.md`](Installations-Scripte/SilentSwitches.md) mit
Silent-Schaltern, Rückgabecodes und Deinstallationsbefehlen für viele weitere
Programme und Installer-Frameworks. Tests: `Tests/InstallScripts.Tests.ps1`.
Zusätzlich bietet `Installations-Scripte/InstallationAuswahl/InstallationAuswahl.ps1`
eine eigenständige WPF-Oberfläche für kategorisierte Mehrfachauswahl und
Installationsstart außerhalb von NinjaOne. Sie benötigt Windows PowerShell 5.1
und eine administrative Sitzung.
/ `Installations-Scripte/InstallationAuswahl/InstallationAuswahl.ps1` also
provides a standalone WPF interface for categorized multi-selection and
installation outside NinjaOne. It requires Windows PowerShell 5.1 and an
elevated session.
/ The `Installations-Scripte` folder contains **one script per tool** for
unattended (silent) installation plus `SilentSwitches.md` with silent switches,
exit codes and uninstall commands for many more programs and installer frameworks.

Ohne `installAllow = true` prüfen die Skripte nur, ob das Tool installiert ist
(Exit `0` = installiert, `2` = nicht installiert). Mit Opt-in wird über
**winget** (`--scope machine`, Quelle `winget`) oder eine **lokale/UNC-Datei**
(`.msi`/`.exe`, optional SHA256-geprüft) installiert; `installMicrosoft365Apps.ps1`
lädt standardmäßig das Office Deployment Tool signaturgeprüft direkt von Microsoft
(`installSource = Download`), weil winget bei `Microsoft.Office` häufig mit
„Installer hash does not match“ abbricht; ein bereits installiertes
Tool wird nur mit `installUpgrade = true` aktualisiert. Es wird nie ein Neustart
ausgelöst – `RebootRequired` im Bericht zeigt einen ausstehenden Neustart an.
/ Without `installAllow = true` the scripts only check whether the tool is
installed (exit `0` = installed, `2` = not installed). With opt-in they install
via **winget** or a **local/UNC file** (optionally SHA256-verified);
`installMicrosoft365Apps.ps1` downloads the Authenticode-verified Office Deployment
Tool from Microsoft by default (`installSource = Download`); installed
tools are only upgraded with `installUpgrade = true`. No reboot is ever triggered;
`RebootRequired` in the report flags a pending reboot.

| Skript / Script | Tool | winget-ID |
| --- | --- | --- |
| `install1Password.ps1` | 1Password | `AgileBits.1Password` |
| `install7Zip.ps1` | 7-Zip | `7zip.7zip` |
| `installAdobeAcrobatReader.ps1` | Adobe Acrobat Reader (64-bit) | `Adobe.Acrobat.Reader.64-bit` |
| `installAdvancedIpScanner.ps1` | Advanced IP Scanner | `Famatech.AdvancedIPScanner` |
| `installAnyDesk.ps1` | AnyDesk | `AnyDesk.AnyDesk` |
| `installAwsCli.ps1` | AWS Command Line Interface v2 | `Amazon.AWSCLI` |
| `installAzureCli.ps1` | Microsoft Azure CLI | `Microsoft.AzureCLI` |
| `installAzureStorageExplorer.ps1` | Microsoft Azure Storage Explorer | `Microsoft.Azure.StorageExplorer` |
| `installBitwarden.ps1` | Bitwarden | `Bitwarden.Bitwarden` |
| `installBoxDrive.ps1` | Box Drive | `Box.Box` |
| `installBraveBrowser.ps1` | Brave | `Brave.Brave` |
| `installCiscoJabber.ps1` | Cisco Jabber | `Cisco.Jabber` |
| `installCiscoWebex.ps1` | Webex | `Cisco.Webex` |
| `installCitrixWorkspace.ps1` | Citrix Workspace | `Citrix.Workspace` |
| `installDBeaverCommunity.ps1` | DBeaver Community | `DBeaver.DBeaver.Community` |
| `installDellCommandUpdate.ps1` | Dell Command \| Update | `Dell.CommandUpdate.Universal` |
| `installDotNetAspNetCoreRuntime10.ps1` | ASP.NET Core Runtime 10 | `Microsoft.DotNet.AspNetCore.10` |
| `installDotNetAspNetCoreRuntime8.ps1` | ASP.NET Core Runtime 8 | `Microsoft.DotNet.AspNetCore.8` |
| `installDotNetDesktopRuntime10.ps1` | .NET Desktop Runtime 10 | `Microsoft.DotNet.DesktopRuntime.10` |
| `installDotNetDesktopRuntime8.ps1` | .NET Desktop Runtime 8 | `Microsoft.DotNet.DesktopRuntime.8` |
| `installDotNetHostingBundle10.ps1` | .NET 10 Windows Server Hosting Bundle | `Microsoft.DotNet.HostingBundle.10` |
| `installDotNetHostingBundle8.ps1` | .NET 8 Windows Server Hosting Bundle | `Microsoft.DotNet.HostingBundle.8` |
| `installDotNetRuntime10.ps1` | .NET Runtime 10 | `Microsoft.DotNet.Runtime.10` |
| `installDotNetRuntime8.ps1` | .NET Runtime 8 | `Microsoft.DotNet.Runtime.8` |
| `installDrawIo.ps1` | draw.io | `JGraph.Draw` |
| `installDropbox.ps1` | Dropbox | `Dropbox.Dropbox` |
| `installEmClient.ps1` | eM Client | `eMClient.eMClient` |
| `installEverything.ps1` | Everything | `voidtools.Everything` |
| `installFoxitPdfEditor.ps1` | Foxit PDF Editor | `Foxit.PhantomPDF` |
| `installFoxitPdfReader.ps1` | Foxit PDF Reader | `Foxit.FoxitReader` |
| `installGit.ps1` | Git for Windows | `Git.Git` |
| `installGoogleChrome.ps1` | Google Chrome | `Google.Chrome` |
| `installGoogleDrive.ps1` | Google Drive | `Google.GoogleDrive` |
| `installGoToMeeting.ps1` | GoTo Meeting | `GoTo.GoToMeeting` |
| `installGpg4win.ps1` | Gpg4win | `GnuPG.Gpg4win` |
| `installGreenshot.ps1` | Greenshot | `Greenshot.Greenshot` |
| `installIntelDriverSupportAssistant.ps1` | Intel Driver & Support Assistant | `Intel.IntelDriverAndSupportAssistant` |
| `installIrfanView.ps1` | IrfanView | `IrfanSkiljan.IrfanView` |
| `installJabraDirect.ps1` | Jabra Direct | `Jabra.Direct` |
| `installKeePass.ps1` | KeePass Password Safe 2 | `DominikReichl.KeePass` |
| `installKeePassXC.ps1` | KeePassXC | `KeePassXCTeam.KeePassXC` |
| `installLenovoSystemUpdate.ps1` | Lenovo System Update | `Lenovo.SystemUpdate` |
| `installLibreOffice.ps1` | LibreOffice | `TheDocumentFoundation.LibreOffice` |
| `installMattermostDesktop.ps1` | Mattermost | `Mattermost.MattermostDesktop` |
| `installMicrosoft365Apps.ps1` | Microsoft 365 Apps | `Microsoft.Office` |
| `installMicrosoftEdge.ps1` | Microsoft Edge | `Microsoft.Edge` |
| `installMicrosoftEdgeWebView2.ps1` | Microsoft Edge WebView2 Runtime | `Microsoft.EdgeWebView2Runtime` |
| `installMicrosoftOneDrive.ps1` | Microsoft OneDrive | `Microsoft.OneDrive` |
| `installMicrosoftRemoteHelp.ps1` | Microsoft Remote Help | `Microsoft.RemoteHelp` |
| `installMobaXterm.ps1` | MobaXterm | `Mobatek.MobaXterm` |
| `installMozillaFirefox.ps1` | Mozilla Firefox | `Mozilla.Firefox.de` |
| `installMozillaFirefoxEsr.ps1` | Mozilla Firefox ESR | `Mozilla.Firefox.ESR.de` |
| `installMozillaThunderbird.ps1` | Mozilla Thunderbird | `Mozilla.Thunderbird.de` |
| `installMRemoteNG.ps1` | mRemoteNG | `mRemoteNG.mRemoteNG` |
| `installMsOdbcSql18.ps1` | Microsoft ODBC Driver 18 for SQL Server | `Microsoft.msodbcsql.18` |
| `installNextcloudDesktop.ps1` | Nextcloud Desktop | `Nextcloud.NextcloudDesktop` |
| `installNodeJsLts.ps1` | Node.js LTS | `OpenJS.NodeJS.LTS` |
| `installNotepadPlusPlus.ps1` | Notepad++ | `Notepad++.Notepad++` |
| `installOmnissaHorizonClient.ps1` | Omnissa Horizon Client | `Omnissa.HorizonClient` |
| `installOnlyOfficeDesktopEditors.ps1` | ONLYOFFICE Desktop Editors | `ONLYOFFICE.DesktopEditors` |
| `installOpenVpn.ps1` | OpenVPN (Community) | `OpenVPNTechnologies.OpenVPN` |
| `installOpenVpnConnect.ps1` | OpenVPN Connect | `OpenVPNTechnologies.OpenVPNConnect` |
| `installPdf24Creator.ps1` | PDF24 Creator | `geeksoftwareGmbH.PDF24Creator` |
| `installPdfsamBasic.ps1` | PDFsam Basic | `PDFsam.PDFsam` |
| `installPdfXChangeEditor.ps1` | PDF-XChange Editor | `TrackerSoftware.PDF-XChangeEditor` |
| `installPeaZip.ps1` | PeaZip | `Giorgiotani.Peazip` |
| `installPowerAutomateDesktop.ps1` | Power Automate for desktop | `Microsoft.PowerAutomateDesktop` |
| `installPowerBIDesktop.ps1` | Microsoft Power BI Desktop | `Microsoft.PowerBI` |
| `installPowerShell7.ps1` | PowerShell 7 | `Microsoft.PowerShell` |
| `installPowerToys.ps1` | Microsoft PowerToys | `Microsoft.PowerToys` |
| `installPuTTY.ps1` | PuTTY | `PuTTY.PuTTY` |
| `installPython314.ps1` | Python 3.14 | `Python.Python.3.14` |
| `installRealVncViewer.ps1` | RealVNC Viewer | `RealVNC.VNCViewer` |
| `installRemoteDesktopManager.ps1` | Remote Desktop Manager | `Devolutions.RemoteDesktopManager` |
| `installRoyalTs.ps1` | Royal TS V7 | `RoyalApps.RoyalTS.7` |
| `installShareX.ps1` | ShareX | `ShareX.ShareX` |
| `installSonicWallNetExtender.ps1` | SonicWall NetExtender | `SonicWall.NetExtender` |
| `installSplashtopBusiness.ps1` | Splashtop Business | `Splashtop.SplashtopBusiness` |
| `installSqlServerManagementStudio.ps1` | SQL Server Management Studio 22 | `Microsoft.SQLServerManagementStudio.22` |
| `installTailscale.ps1` | Tailscale | `Tailscale.Tailscale` |
| `installTeamViewer.ps1` | TeamViewer | `TeamViewer.TeamViewer` |
| `installTeamViewerHost.ps1` | TeamViewer Host | `TeamViewer.TeamViewer.Host` |
| `installTemurinJdk21.ps1` | Eclipse Temurin JDK 21 | `EclipseAdoptium.Temurin.21.JDK` |
| `installTemurinJre11.ps1` | Eclipse Temurin JRE 11 | `EclipseAdoptium.Temurin.11.JRE` |
| `installTemurinJre17.ps1` | Eclipse Temurin JRE 17 | `EclipseAdoptium.Temurin.17.JRE` |
| `installTemurinJre21.ps1` | Eclipse Temurin JRE 21 | `EclipseAdoptium.Temurin.21.JRE` |
| `installTemurinJre25.ps1` | Eclipse Temurin JRE 25 | `EclipseAdoptium.Temurin.25.JRE` |
| `installTemurinJre8.ps1` | Eclipse Temurin JRE 8 | `EclipseAdoptium.Temurin.8.JRE` |
| `installTortoiseGit.ps1` | TortoiseGit | `TortoiseGit.TortoiseGit` |
| `installTortoiseSvn.ps1` | TortoiseSVN | `TortoiseSVN.TortoiseSVN` |
| `installTreeSizeFree.ps1` | TreeSize Free | `JAMSoftware.TreeSize.Free` |
| `installVcRedist2013X64.ps1` | Microsoft Visual C++ 2013 Redistributable (x64) | `Microsoft.VCRedist.2013.x64` |
| `installVcRedistX64.ps1` | Microsoft Visual C++ Redistributable 2015-2022+ (x64) | `Microsoft.VCRedist.2015+.x64` |
| `installVcRedistX86.ps1` | Microsoft Visual C++ Redistributable 2015-2022+ (x86) | `Microsoft.VCRedist.2015+.x86` |
| `installVeraCrypt.ps1` | VeraCrypt | `IDRIX.VeraCrypt` |
| `installVisualStudioCode.ps1` | Visual Studio Code | `Microsoft.VisualStudioCode` |
| `installVlcMediaPlayer.ps1` | VLC media player | `VideoLAN.VLC` |
| `installWinMerge.ps1` | WinMerge | `WinMerge.WinMerge` |
| `installWinRar.ps1` | WinRAR | `RARLab.WinRAR` |
| `installWinSCP.ps1` | WinSCP | `WinSCP.WinSCP` |
| `installWireGuard.ps1` | WireGuard | `WireGuard.WireGuard` |
| `installWireshark.ps1` | Wireshark | `WiresharkFoundation.Wireshark` |
| `installYubicoAuthenticator.ps1` | Yubico Authenticator | `Yubico.Authenticator` |
| `installZoomOutlookPlugin.ps1` | Zoom Outlook Plugin | `Zoom.ZoomOutlookPlugin` |
| `installZoomWorkplace.ps1` | Zoom Workplace | `Zoom.Zoom` |

| NinjaOne-Variable | Typ / Type | Standard / Default | Bedeutung / Meaning |
| --- | --- | --- | --- |
| `installAllow` | Checkbox | `false` | Installation erlauben (sonst nur Prüfung) / allow installation (otherwise audit only) |
| `installSource` | Dropdown `Winget` / `File` / `Download` | `Winget` (`installMicrosoft365Apps.ps1`: `Download`) | Installationsquelle; `Download` nur bei fest hinterlegter Hersteller-URL / installation source; `Download` only with a built-in vendor URL |
| `installerPath` | Text | – | Nur `File`: lokaler (`C:\…`) oder UNC-Pfad zu `.msi`/`.exe` / `File` only: local or UNC path |
| `installerSha256` | Text | – | Optional (`File`/`Download`): erwarteter SHA256-Hash der Datei / expected SHA256 hash |
| `installerArguments` | Text | Werte aus `SilentSwitches.md` / values from `SilentSwitches.md` | Nur `File`/`Download`: ersetzt die Standard-Schalter (bei MSI die Zusatz-Eigenschaften) / replaces default switches |
| `installUpgrade` | Checkbox | `false` | Vorhandene Installation aktualisieren / upgrade existing installation |
| `installTimeoutMinutes` | Integer, 1..240 | `30` | Maximale Wartezeit / maximum wait time |
| `resultCustomField` | Text | – | Interner Name eines MultiLine-Feldes für den JSON-Bericht / internal MultiLine field name |

### Gemeinsame NinjaOne-Konfiguration / Common NinjaOne configuration

Beispielkonfiguration für die neuen Systemprüfungen / Example configuration for
the new system checks:

| Skript / Script | Variable | Typ / Type | Standard / Default |
| --- | --- | --- | --- |
| `checkDiskSpace.ps1` | `minimumFreePercent` | Integer, 1..99 | `15` |
| `checkRequiredServices.ps1` | `requiredServiceNames` | Text, kommagetrennte interne Dienstnamen / comma-separated internal service names, max. 20 | Pflicht / required |
| `checkTimeZone.ps1` | `expectedTimeZone` | Text, installierte Windows-Zeitzonen-ID / installed Windows time zone ID | leer: nur Inventar / empty: inventory only |
| alle drei / all three | `resultCustomField` | Text, interner MultiLine-Feldname / internal MultiLine field name | leer: kein Export / empty: no export |

Weitere zentrale Eingaben / Other key inputs:

| Funktion / Function | NinjaOne-Variablen / Variables |
| --- | --- |
| DNS-Auflösung / resolution | `dnsHostName`, `dnsRecordType`, `dnsServer` |
| TCP-Einzelziel / single endpoint | `targetHost`, `targetPort`, `connectionTimeoutMs` |
| Administrator-Allowlist / administrator allowlist | `securityAllowedAdminIdentities` |
| AD-DS-Recovery-Escrow | `bitlockerEscrowMountPoint`, `bitlockerEnableAdDsEscrow` (`true` ausdrücklich / explicitly) |
| Computer-Inaktivität / machine inactivity | `securityInactivityTimeoutSeconds`, `securityApplyMachineInactivityPolicy` (`true` ausdrücklich / explicitly) |
| Update-Wartung / maintenance | `updateCacheAllowCleanup`, `updateCacheMinimumAgeDays`, `updateRepairAllowRestart` |
| Blockierte Software / blocked software | `blockedSoftwareNames` |
| Chocolatey-Standardinstallation erforderlich / require standard installation | `chocolateyStatusRequireInstalled` |
| Leere Ordner / empty folders | `emptyFoldersRootPath`, `emptyFoldersMaxFolders`, `emptyFoldersMaxRecords` |
| Bereinigung / cleanup (`08 - Cleanup`) | `cleanupTempAllow`, `cleanupRecycleBinAllow`, `cleanupWerAllow`, `cleanupDoAllow`, `cleanupComponentStoreAllow`, `cleanupBrowserCacheAllow`, `cleanupProfilesAllow`, `uninstallAllow`, `appxRemoveAllow` (`true` ausdrücklich / explicitly) |
| Einstellungen / settings (`09 - Configuration`) | `config…Allow` je Skript / per script (`true` ausdrücklich / explicitly) |
| Installation (`Installations-Scripte`) | `installAllow`, `installSource`, `installerPath`, `installerSha256`, `installerArguments`, `installUpgrade`, `installTimeoutMinutes` |

Die detaillierte Parameterhilfe bleibt maßgeblich für Syntax, Grenzwerte und
Standardwerte. / Detailed parameter help remains authoritative for syntax,
limits and defaults.

- Alle neuen Skripte einzeln als Windows PowerShell-Automation importieren,
  als **SYSTEM und 64-Bit** ausführen. Benötigte Windows-Module sind
  betriebssystemabhängig; fehlende Module werden als Fehler gemeldet.
  / Import each new script separately as a Windows PowerShell automation, run as
  **SYSTEM and 64-bit**. Required Windows modules depend on the operating system;
  missing modules are reported as errors.
- Die `.PARAMETER`-Hilfe jeder Datei nennt ihre NinjaOne-Skriptvariablen,
  Standardwerte und Grenzen. Variablennamen exakt übernehmen; ausdrücklich
  übergebene PowerShell-Parameter haben Vorrang vor Umgebungsvariablen.
  / Each file's `.PARAMETER` help lists its NinjaOne script variables, defaults
  and limits. Use exact variable names; explicitly supplied PowerShell parameters
  take precedence over environment variables.
- Neue Katalog-Skripte nutzen optional die **Text-Skriptvariable**
  `resultCustomField`: interner Name eines **MultiLine-Geräte-Custom-Fields**
  mit Skript-Schreibrecht, zum Beispiel `diskReport`. Leer oder `null` deaktiviert
  den Export. Die drei oben dokumentierten Diagnose-Skripte und die bestehenden
  DNS-Hauptskripte behalten ihre bisherigen Variablen/Feldtypen.
  / New catalogue scripts optionally use the **Text script variable**
  `resultCustomField`: internal name of a **MultiLine device custom field** with
  script write access, e.g. `diskReport`. Empty or `null` disables export.
  The three diagnostics above and existing main DNS scripts retain their
  existing variables/field types.
- Für neue Skripte gilt `0` = erfolgreich, `1` = Eingabe-/Abfrage-/Schreibfehler,
  `2` = erkannter Warnbefund, sofern die jeweilige Skripthilfe dies vorsieht.
  Feldberichte über 4000 Zeichen werden nicht still abgeschnitten: Skripte
  begrenzen dokumentiert die Datensätze oder melden einen Exportfehler.
  / New scripts use `0` = success, `1` = input/query/write error, `2` = detected
  warning where specified in script help. Field reports exceeding 4000 characters
  are not silently truncated: scripts explicitly limit records or report an
  export failure.

### Sichere Nutzung / Safe operation

Zuerst auf einem Windows-Testgerät mit und ohne Custom-Field-Schreibrechte
ausführen. Änderungen sind opt-in und müssen in der Skripthilfe geprüft werden;
`-WhatIf` nutzen, wenn angeboten. Wartungsfenster für Update-/Policy-Änderungen
einplanen. Kein Skript bietet eine Garantie für vollständige Sicherheits- oder
Patch-Konformität. / First run on a Windows test device with and without custom
field write permissions. Changes are opt-in and must be reviewed in script help;
use `-WhatIf` where supported. Schedule maintenance windows for update/policy
changes. No script guarantees complete security or patch compliance.

Recovery-Passwörter und private Zertifikatsschlüssel werden nicht exportiert.
`exportRecoveryKeys.ps1` dient ausschließlich dem ausdrücklich aktivierten
Recovery-Escrow, nicht einer Klartext-Schlüsselausgabe. `emptyFolders.ps1` meldet
leere Ordner, löscht sie aber nicht. Benutzer-/Netzwerkinventar kann interne
Metadaten enthalten; Gerätefeld-Leserechte entsprechend einschränken.
/ Recovery passwords and private certificate keys are not exported.
`exportRecoveryKeys.ps1` is for explicitly enabled recovery escrow, not plaintext
key output. `emptyFolders.ps1` reports empty folders without deleting them.
User/network inventories may contain internal metadata; restrict device field
read permissions accordingly.

`readLastLogonTimes.ps1` beschreibt Profilnutzung, nicht verlässlich den letzten
interaktiven Benutzer-Login. Registry- und Sicherheitsprüfungen sind Diagnose,
keine vollständige Compliance-Bewertung. / `readLastLogonTimes.ps1` describes
profile usage, not an authoritative last interactive user login. Registry and
security checks are diagnostics, not complete compliance assessments.

Die Legacy-Datei `enforceScreensaverTimeout.ps1` betrifft die
**Computer-Inaktivitätssperre**, nicht den Bildschirmschoner des angemeldeten
Benutzers. Bei SYSTEM-Ausführung wäre dessen HKCU nicht das Benutzerprofil.
Die gesetzte Richtlinie kann durch GPO/MDM überschrieben werden.
/ The legacy file `enforceScreensaverTimeout.ps1` addresses the **machine
inactivity lock**, not the signed-in user's screensaver. Under SYSTEM, HKCU
would not be that user's profile. GPO/MDM may override the configured policy.

`checkChocolateyStatus.ps1` ist eine Bereitschaftsdiagnose, keine automatische
Softwareverteilung: keine Paketinstallation/-aktualisierung und kein Download
von Bootstrap-Skripten. / `checkChocolateyStatus.ps1` is a readiness diagnostic,
not automatic software distribution: no package installation/upgrade and no
bootstrap script downloads.

Für unbeaufsichtigtes BitLocker-Escrow bzw. die Inaktivitätsrichtlinie sind
zusätzlich zum expliziten Opt-in die Bestätigungsparameter zu beachten:
nach Prüfung `-Confirm:$false` angeben. Netzwerk-/Benutzerinventare unterstützen
`-WhatIf` für die Feldveröffentlichung; ihre lesenden Abfragen und der einzelne
TCP-Verbindungstest werden dabei weiterhin ausgeführt.
/ For unattended BitLocker escrow or inactivity policy changes, also observe
confirmation parameters in addition to explicit opt-in: supply `-Confirm:$false`
after review. Network/user inventories support `-WhatIf` for field publication;
read-only queries and the single TCP connection test still execute.

Bereinigungs-, Einstellungs- und Installationsskripte zuerst ohne Opt-in
(Audit) bzw. mit `-WhatIf` ausführen und den Bericht prüfen.
`removeStaleUserProfiles.ps1` und `uninstallSoftware.ps1` löschen Daten bzw.
Programme unwiderruflich – Ausschlussliste, Höchstzahl und Namensabgleich
(`Exact`) bewusst setzen. Installationsskripte laden Software nur über winget,
aus einer fest hinterlegten, signaturgeprüften Herstellerquelle oder aus einer
vom Administrator angegebenen lokalen/UNC-Quelle (siehe
[SECURITY.md](SECURITY.md)) und lösen keinen Neustart aus.
/ Run cleanup, configuration and installation scripts first without opt-in
(audit) or with `-WhatIf` and review the report. `removeStaleUserProfiles.ps1`
and `uninstallSoftware.ps1` remove data/programs irreversibly – set exclusion
list, maximum count and name matching (`Exact`) deliberately. Installation
scripts only obtain software via winget, a built-in signature-verified vendor
source or an admin-supplied local/UNC source and
never trigger a reboot.

Zusätzliche Systemtests:
`Invoke-Pester -Path ./Tests/SystemChecks.Tests.ps1`; DNS-Skripte:
`Invoke-Pester -Path ./Tests/DnsScripts.Tests.ps1`; Bereinigung/Einstellungen/Installation:
`Tests/CatalogCleanup.Tests.ps1`, `Tests/CatalogConfiguration.Tests.ps1`,
`Tests/InstallScripts.Tests.ps1`; alle Tests: `Invoke-Pester -Path ./Tests`.
Linux-Parsing/Mock-Tests ersetzen keinen Windows-PowerShell-5.1-/NinjaOne-Test.
/ Additional system tests: `Invoke-Pester -Path ./Tests/SystemChecks.Tests.ps1`;
DNS scripts: `Invoke-Pester -Path ./Tests/DnsScripts.Tests.ps1`; all tests: `Invoke-Pester -Path ./Tests`.
Linux parsing/mock tests do not replace Windows PowerShell 5.1/NinjaOne testing.

## Referenzen / References

Eigenständige Implementierungen; kein übernommener Fremdcode. Die verlinkten
Sammlungen dienen als NinjaOne-Kontext. / Original implementations; no copied
third-party code. Linked collections provide NinjaOne context.

- https://github.com/UnifiedTechs/NinjaOne
- https://gist.github.com/cjdajer/dd2d765ff5df661ade1535544ab09ca5
- https://github.com/mennotech/ninjaone-scripts
- https://github.com/jeffhunterninja/NinjaOne-Scripts
- https://www.ninjaone.com/script-hub/
- https://www.ninjaone.com/docs/administration/script-library/
- https://www.ninjaone.com/de/blog/
- https://www.ninjaone.com/de/ressourcen/
- https://www.ninjaone.com/de/docs/
- https://marcogriep.de/posts/bitlocker-ninja-one-powershell-automatisierung/
- https://github.com/NinjaRMM
- https://github.com/NinjaRMM/ninjaone_scripts
- https://marcogriep.de/posts/ninjaone-chocolatey-softwareverteilung-effizient-automatisieren/

Die zusätzlich verlinkten Webseiten konnten in der Entwicklungsumgebung nicht
abgerufen werden; ihre konkreten Inhalte wurden daher nicht als verifiziert
übernommen. Die Themen BitLocker-Escrow und Chocolatey-Bereitschaft werden durch
eigene Implementierungen berücksichtigt. Keine fremden Skripte werden kopiert;
insbesondere gelten für NinjaRMM/ninjaone_scripts eigene Nutzungs- und
Weitergabebeschränkungen. / The additional websites could not be retrieved in the
development environment; their specific contents were not treated as verified.
BitLocker escrow and Chocolatey readiness are covered by original implementations.
No third-party scripts are copied; NinjaRMM/ninjaone_scripts in particular has
its own usage and redistribution restrictions.

# Lizenz
* Dieses Repository steht unter der MIT-Lizenz ([LICENSE](LICENSE)).
* Sie dürfen die Skripte frei verwenden, ändern und in Ihren RMM-Umgebungen verteilen. 

---

# Keine Garantie / Haftung !!!
