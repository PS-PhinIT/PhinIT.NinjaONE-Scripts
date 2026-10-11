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
* Pull-Requests und Issues sind willkommen!

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

Jeder nummerierte Themenordner enthält mindestens fünf eigenständige Skripte.
Die bestehenden DNS-Hauptskripte bleiben unverändert; ihre eigenen Anleitungen
und Rückgabecodes gelten weiterhin. / Each numbered topic folder contains at
least five standalone scripts. Existing main DNS scripts are unchanged; their
own guides and exit codes still apply.

| Bereich / Topic | Aufgaben / Tasks |
| --- | --- |
| `01 - System` | Systemdaten, Laufzeit, Speicherplatz, benötigte Dienste, Zeitzone / system information, uptime, disk space, required services, time zone |
| `02 - Updates` | Update-Status, Cache-Wartung, Dienstreparatur und Update-Inventar / update status, cache maintenance, service repair and update inventory |
| `03 - Software` | Installiertes Inventar, blockierte Software, PowerShell-Richtlinien, Dienste, .NET und Chocolatey-Bereitschaft / installed inventory, blocked software, PowerShell policies, services, .NET and Chocolatey readiness |
| `04 - Certificates` | Zertifikatsinventar, Ablaufprüfung und öffentliche Zertifikate / certificate inventory, expiry checks and public certificates |
| `05 - DNS` | Bestehende DNS-Konfiguration/-Änderung plus DNS-Auflösung, Cache und Client-Inventar / existing DNS configuration/change plus resolution, cache and client inventory |
| `06 - Bitlocker` | Verschlüsselung, Schutzmechanismen, TPM und Recovery-Escrow / encryption, protectors, TPM and recovery escrow |
| `07 - Security` | Defender, weitere Schutzprodukte, lokale Administratoren, Sperrzeit und Firewall / Defender, other protection products, local administrators, lock timeout and firewall |
| `10 - Network` | Lokale Verbindungen/Ports, Adapter, Einzelziel-Verbindungstest und Netzwerkdiagnose / local connections/ports, adapters, single-target connection test and network diagnostics |
| `11 - User` | Profilinventar, Profilnutzung, lokale Benutzer, Gruppen und Mitgliedschaften / profile inventory, profile usage, local users, groups and memberships |
| `50 - Misc` | Neustart-Indikatoren, leere Ordner, Zeitsynchronisation, geplante Aufgaben und Ereignisse / reboot indicators, empty folders, time synchronization, scheduled tasks and events |

| Ordner / Folder | Skriptdateien / Script files |
| --- | --- |
| `01 - System` | `readSystemInfo.ps1`, `readUptime.ps1`, `checkDiskSpace.ps1`, `checkRequiredServices.ps1`, `checkTimeZone.ps1` |
| `02 - Updates` | `readWindowsUpdateStatus.ps1`, `cleanupWindowsUpdateCache.ps1`, `repairWindowsUpdate.ps1`, `checkWindowsUpdateServices.ps1`, `readHotfixInventory.ps1` |
| `03 - Software` | `readInstalledSoftware.ps1`, `checkBlockedSoftware.ps1`, `checkPowerShellPolicy.ps1`, `checkSoftwareServices.ps1`, `readDotNetInventory.ps1`, `checkChocolateyStatus.ps1` |
| `04 - Certificates` | `checkExpiredCertificates.ps1`, `exportCertificateStore.ps1`, `readCertificateInventory.ps1`, `checkSelfSignedCertificates.ps1`, `checkTrustedRootCertificates.ps1` |
| `05 - DNS` | `00-readDNSSettingsClient.ps1`, `01-setDNSSettingsClient.ps1`, `resolveDnsName.ps1`, `readDnsCache.ps1`, `readDnsClientConfiguration.ps1` |
| `06 - Bitlocker` | `readBitLockerStatus.ps1`, `exportRecoveryKeys.ps1`, `auditKeyProtectors.ps1`, `auditVolumeEncryption.ps1`, `checkTpmReadiness.ps1` |
| `07 - Security` | `checkWindowsDefender.ps1`, `checkAnotherSecurityProduct.ps1`, `detectUnauthorizedLocalAdmins.ps1`, `enforceScreensaverTimeout.ps1`, `auditWindowsFirewall.ps1` |
| `10 - Network` | `auditTcpConnections.ps1`, `checkOpenPorts.ps1`, `listNetworkAdapters.ps1`, `testTcpEndpoint.ps1`, `auditFirewallProfiles.ps1` |
| `11 - User` | `listUsersProfiles.ps1`, `readLastLogonTimes.ps1`, `listLocalUsers.ps1`, `listLocalGroups.ps1`, `listLocalGroupMembers.ps1` |
| `50 - Misc` | `restartPendingCheck.ps1`, `emptyFolders.ps1`, `readTimeSyncStatus.ps1`, `readScheduledTaskState.ps1`, `readEventLogErrors.ps1` |

### Gemeinsame NinjaOne-Konfiguration / Common NinjaOne configuration

Beispielkonfiguration für die neuen Systemprüfungen / Example configuration for
the new system checks:

| Skript / Script | Variable | Typ / Type | Standard / Default |
| --- | --- | --- | --- |
| `checkDiskSpace.ps1` | `minimumFreePercent` | Integer, 1..99 | `15` |
| `checkRequiredServices.ps1` | `requiredServiceNames` | Text, kommagetrennte interne Dienstnamen / comma-separated internal service names, max. 20 | Pflicht / required |
| `checkTimeZone.ps1` | `expectedTimeZone` | Text, installierte Windows-Zeitzonen-ID / installed Windows time zone ID | leer: nur Inventar / empty: inventory only |
| alle drei / all three | `resultCustomField` | Text, interner MultiLine-Feldname / internal MultiLine field name | leer: kein Export / empty: no export |

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

Zusätzliche Systemtests:
`Invoke-Pester -Path ./Tests/SystemChecks.Tests.ps1`.
Linux-Parsing/Mock-Tests ersetzen keinen Windows-PowerShell-5.1-/NinjaOne-Test.
/ Additional system tests: `Invoke-Pester -Path ./Tests/SystemChecks.Tests.ps1`.
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
* Dieses Repository steht unter der MIT-Lizenz.
* Sie dürfen die Skripte frei verwenden, ändern und in Ihren RMM-Umgebungen verteilen. 

---

# Keine Garantie / Haftung !!!
