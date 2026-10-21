# Mitwirken / Contributing

Pull Requests und Issues sind willkommen! / Pull requests and issues are welcome!

## Konventionen für Skripte / Script conventions

- **Ziel:** Windows PowerShell 5.1, Ausführung in NinjaOne als **SYSTEM, 64-Bit**.
  Keine PowerShell-7-Syntax (`??`, `?:`, `ForEach-Object -Parallel`).
  / Target Windows PowerShell 5.1, run by NinjaOne as SYSTEM, 64-bit. No
  PowerShell 7-only syntax.
- **Ablage:** eigenständige Skripte im passenden Themenordner
  (`01 - System` … `50 - Misc`); Dateinamen in camelCase mit Verb
  (`read…`, `check…`, `audit…`, `list…`). Bereinigung in `08 - Cleanup`
  (`cleanup…`, `remove…`, `uninstall…`), Einstellungen in `09 - Configuration`
  (`set…`), Installationen in `Installations-Scripte` (`install<Tool>.ps1`, ein
  Skript je Tool; Silent-Schalter zusätzlich in
  `Installations-Scripte/SilentSwitches.md` dokumentieren).
  / One standalone script per file in the matching topic folder; cleanup in
  `08 - Cleanup`, settings in `09 - Configuration`, one install script per tool
  in `Installations-Scripte` (document its switches in `SilentSwitches.md`).
- **Installationsskripte:** Die Logik ab `function Resolve-Setting` ist in allen
  `install*.ps1` identisch (wird von `Tests/InstallScripts.Tests.ps1` geprüft);
  ein neues Tool erhält eine Kopie eines bestehenden Skripts, in der nur Hilfe und
  die `$Tool`-Tabelle (Name, winget-ID, Erkennungsmuster, Standardargumente)
  angepasst werden. Änderungen an der Logik in allen Skripten gleich vornehmen
  und das Tool in `Tests/InstallScripts.Tests.ps1` ergänzen. Optional:
  `DownloadUrl` (HTTPS, `.msi`/`.exe`) und `DownloadSigner` (erwarteter
  Authenticode-Signierer) für `installSource = Download`, `DefaultSource` für
  eine abweichende Standardquelle (nur wenn winget unzuverlässig ist),
  `WingetInstallerType` (z. B. `wix`) für `winget --installer-type`, wenn das
  Manifest zusätzlich MSIX anbietet (MSIX ignoriert `--scope machine`).
  / The logic from `function Resolve-Setting` onwards is identical in all
  `install*.ps1` scripts (checked by tests); new tools copy an existing script and
  only change the help and the `$Tool` table. Apply engine changes to all scripts.
- **Kodierung:** UTF-8 **mit BOM** (sonst werden Umlaute unter PowerShell 5.1
  falsch gelesen). / Encoding: UTF-8 **with BOM**.
- **Hilfe:** Kommentarbasierte Hilfe mit `.SYNOPSIS`, `.DESCRIPTION`,
  `.PARAMETER` je Parameter, mindestens einem `.EXAMPLE` und den Rückgabecodes,
  zweisprachig (DE/EN). Nur gültige Hilfe-Schlüsselwörter verwenden, sonst
  ignoriert `Get-Help` den gesamten Block.
  / Comment-based help with synopsis, description, every parameter, at least one
  example and exit codes, bilingual. Use only valid help keywords.
- **NinjaOne:** `[CmdletBinding()]`; Skriptvariablen werden als
  Umgebungsvariablen gelesen, explizite Parameter haben Vorrang; leere Werte und
  `null` gelten als nicht gesetzt. Optionaler Export über die Text-Variable
  `resultCustomField` (interner Name eines MultiLine-Feldes); Berichte über
  4000 Zeichen nicht still abschneiden.
  / Script variables are read from environment variables; explicit parameters
  win; optional export through `resultCustomField`.
- **Rückgabecodes / Exit codes:** `0` = OK, `1` = Eingabe-/Abfrage-/Schreibfehler,
  `2` = Warnbefund (in der Hilfe beschreiben).
- **Sicherheit:** zustandsändernde Skripte nur mit ausdrücklichem Opt-in und
  `SupportsShouldProcess`; keine Geheimnisse ausgeben; keine Downloads zur
  Laufzeit (Ausnahme: geprüfte Quellen der Installationsskripte). Siehe
  [SECURITY.md](SECURITY.md).

## Prüfung vor dem Pull Request / Checks before a pull request

```powershell
# Syntax und Analyse / Syntax and static analysis
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning

# Tests (Pester 5)
Invoke-Pester -Path ./Tests
```

Linux-/Mock-Tests ersetzen keinen Test unter Windows PowerShell 5.1 mit
NinjaOne-Agent (inkl. Custom-Field-Schreibrechten).
/ Linux/mock tests do not replace testing on Windows PowerShell 5.1 with a
NinjaOne agent (including custom field write permissions).

## Dokumentation / Documentation

- Neue oder geänderte Skripte im Katalog der [README.md](README.md) eintragen.
- Jede Änderung in der [CHANGELOG.md](CHANGELOG.md) unter einer Überschrift mit
  dem Änderungsdatum (`## JJJJ-MM-TT – Titel`, neueste zuerst) festhalten.
  / Record every change in the changelog under a dated heading
  (`## YYYY-MM-DD – title`, newest first).
- Signierte Skripte nach Änderungen neu signieren oder den veralteten
  Signaturblock entfernen (siehe [SECURITY.md](SECURITY.md)).
