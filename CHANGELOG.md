# Changelog

Alle nennenswerten Änderungen an diesem Repository werden in dieser Datei
dokumentiert. / All notable changes to this repository are documented in this
file.

Das Repository verwendet keine Release-Tags. Jeder Eintrag trägt daher das
Datum der Änderung (neueste zuerst); ältere Einträge wurden aus der
Git-Historie und den Pull Requests rekonstruiert.
/ The repository has no release tags. Every entry is therefore dated (newest
first); older entries were reconstructed from the Git history and pull requests.

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
