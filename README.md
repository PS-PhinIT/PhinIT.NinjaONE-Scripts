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

# Lizenz
* Dieses Repository steht unter der MIT-Lizenz.
* Sie dürfen die Skripte frei verwenden, ändern und in Ihren RMM-Umgebungen verteilen. 

---

# Keine Garantie / Haftung !!!
