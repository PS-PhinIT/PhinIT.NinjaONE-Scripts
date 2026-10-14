### NinjaOne bringt (Frühjahr 2025) keinen „fertigen" Bericht mit, der systemübergreifend alle auf den Endpunkten konfigurierten DNS-Server sammelt und in einem Dashboard/Report anzeigt.

**NinjaOne Integration Guide**
* [NinjaONE-DNS_Guide_DE.md](NinjaONE-DNS_Guide_DE.md) · Englisch: [README.md](README.md), [NinjaONE-DNS_Guide_ENG.md](NinjaONE-DNS_Guide_ENG.md)

---

# DNS-Client-Skripte für NinjaOne

Dieser Ordner enthält **zwei Haupt-Skripte**, die Hand in Hand arbeiten
(zusätzlich die lesenden Diagnosen `resolveDnsName.ps1`, `readDnsCache.ps1` und
`readDnsClientConfiguration.ps1`, siehe [Haupt-README](../README.md)):

| Skript | Zweck |
| ------ | ------- |
| **01-setDNSSettingsClient.ps1** | Setzt _statische_ IPv4-DNS-Server **oder** setzt Adapter auf DHCP zurück, auf allen *produktiven* physischen Adaptern. |
| **00-readDNSSettingsClient.ps1** | Liest die aktuellen DNS-Einstellungen von allen produktiven Adaptern und erstellt einen menschenlesbaren Bericht (Markdown/Konsole), einen optionalen CSV-Export und aktualisiert Zusammenfassungs-Custom-Fields in NinjaOne. |

Beide Skripte wurden von **Andreas Hepp** entwickelt - **www.phinit.de** oder **www.psscripts.de**

---

## 1. Funktionen auf einen Blick

### 01-setDNSSettingsClient.ps1

* Erkennt *produktive* Adapter (Standard-GW vorhanden **oder** innerhalb des Ziel-Subnetzes **oder** passend zum expliziten Gateway).
* Unterstützt nur physische LAN/WLAN – schließt vNICs, VPN, Hyper-V, WSL, Docker usw. aus.
* Verwendet `Set-DnsClientServerAddress` mit `netsh`-Fallback für ältere Betriebssysteme/hängende Treiber.
* Optionale Custom-Field-Aktualisierung (`DNS_LastChange`) mit vollständiger Audit-Zeichenfolge - nur wenn mindestens ein Adapter geändert wurde.
* Unterstützt `-WhatIf` (keine Änderung, kein Custom-Field-Schreibvorgang).
* Gibt **Exit-Codes** zurück:  
  `0` = geändert | `2` = nichts zu tun (oder `-WhatIf`) | `1` = Fehler, auch wenn mindestens ein Adapter nicht geändert werden konnte | `3` = DNS geändert, aber CF-Update fehlgeschlagen.

### 00-readDNSSettingsClient.ps1

* Moderne `Get-DnsClient*`-Cmdlets mit automatischem WMI-Fallback für ≤ Win 2008 R2.
* Erstellt Konsolen-Markdown plus optionales CSV (`C:\ProgramData\NinjaRMMAgent\Logs\Reports`).
* Erkennt DNS-Abweichungen zwischen aktiven Adaptern.
* Schreibt `DNS_Summary` (Text) und `DNS_Mismatch` (Boolean) Custom-Fields.
* Log- & Berichtsrotation (`LogRetentionDays`, 0-3650, Standard 30; zusammen mit dem CSV-Export).
* Exit-Codes: `0` = Bericht erstellt | `1` = keine Adapter / Abfragefehler.

---

## 2. Parameter

| Skript | Hauptparameter | Hinweise |
| ------ | -------------- | ----- |
| **01-setDNSSettingsClient.ps1** | `-PrimaryDNS` `-SecondaryDNS` `-TargetSubnet` `-TargetGateway` `-AdapterName` `-ResetDHCP` `-NoCustomField` | `-PrimaryDNS` erforderlich, außer bei `-ResetDHCP`. Alle Parameter können über Custom Fields vorausgefüllt werden. |
| **00-readDNSSettingsClient.ps1** | `-NoCSV` `-NoCustomField` `-LogRetentionDays` | Sicher eigenständig oder im Zeitplan ausführbar. |

Führen Sie beide Skripte mit `-Verbose` aus, um den detaillierten Ablauf zu sehen.

---

## 3. Erforderliche Custom Fields

| Feldname | Typ | Verwendet von | Zweck |
| ---------- | ---- | ------- | ------- |
| `DNS_PrimaryServer` | Text | set | Wert für `-PrimaryDNS`, wenn Parameter weggelassen |
| `DNS_SecondaryServer` | Text | set | Wert für `-SecondaryDNS` |
| `DNS_TargetSubnet` | Text | set | z.B. `192.168.10.0/24` |
| `DNS_TargetGateway` | Text | set | Explizite Gateway-IP |
| `DNS_AdapterAliases` | Text | set | Kommagetrennte Wildcard-Adapternamen |
| `DNS_ResetToDHCP` | Checkbox/Boolean | set | Wenn **true**, erzwingt `-ResetDHCP`-Modus |
| `DNS_LastChange` | Text (mehrzeilig) | set | Vom Skript mit Zeitstempel aktualisiert |
| `DNS_Summary` | Text (mehrzeilig) | read | Konsolidierte IPv4-DNS-Liste |
| `DNS_Mismatch` | Checkbox/Boolean | read | **true**, wenn Adapter unterschiedliche DNS verwenden |

---

## 4. Dateispeicherorte

Alle Logs und CSVs werden hier gespeichert:

```
C:\ProgramData\NinjaRMMAgent\Logs
└─ Reports
```

Die Rotation von `DNS_Report_*.csv`, `DNS*.log` und temporären `DNSReport_*.csv`-Anhängen übernimmt das Leseskript (außer mit `-NoCSV`).
