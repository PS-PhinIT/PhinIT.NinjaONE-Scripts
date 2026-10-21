# Sicherheitsrichtlinie / Security Policy

## Unterstützte Versionen / Supported versions

Unterstützt wird ausschließlich der aktuelle Stand des Branches `main`.
/ Only the current state of the `main` branch is supported.

## Schwachstellen melden / Reporting a vulnerability

Bitte **keine öffentlichen Issues** für Sicherheitslücken anlegen. Nutzen Sie
stattdessen die private Meldung über GitHub
(**Security → Report a vulnerability**) dieses Repositorys. Bitte angeben:
betroffenes Skript, Windows-/PowerShell-Version, NinjaOne-Agent-Version,
Reproduktionsschritte und erwartete Auswirkung.
/ Please do **not** open public issues for vulnerabilities. Use GitHub's private
reporting (**Security → Report a vulnerability**) and include the affected
script, Windows/PowerShell version, NinjaOne agent version, reproduction steps and
expected impact.

## Sicherheitsgrundsätze der Skripte / Script security principles

- Diagnose ist Standard; zustandsändernde Skripte erfordern ein ausdrückliches
  Opt-in und unterstützen `-WhatIf`/`-Confirm`.
  / Diagnostics are the default; state-changing scripts require explicit opt-in
  and support `-WhatIf`/`-Confirm`.
- Keine Ausgabe von BitLocker-Recovery-Passwörtern, privaten Schlüsseln oder
  anderen Geheimnissen in Konsole, Logs oder Custom Fields.
  / No BitLocker recovery passwords, private keys or other secrets in output,
  logs or custom fields.
- Eingaben aus NinjaOne-Skriptvariablen und Custom Fields werden vor der Nutzung
  validiert (z. B. IPv4-Punktnotation, Wertebereiche, keine Wildcards).
  / Inputs from NinjaOne script variables and custom fields are validated before
  use.
- Keine Downloads oder Ausführung externer Skripte zur Laufzeit.
  / No runtime download or execution of external scripts.
  **Ausnahme / Exception:** Die Skripte in `Installations-Scripte` installieren
  Software ausschließlich nach Opt-in (`installAllow`) und nur aus drei Quellen:
  winget (feste Paket-ID, Quelle `winget`, Hash-Prüfung durch winget), eine
  vom Administrator angegebene lokale/UNC-Datei (`.msi`/`.exe`, optional mit
  SHA256-Prüfung) oder eine im Skript fest hinterlegte HTTPS-Herstellerquelle
  (`Download`, derzeit nur das Office Deployment Tool von
  `officecdn.microsoft.com`), deren Authenticode-Signatur gültig und vom
  erwarteten Herausgeber (`CN=Microsoft Corporation`) sein muss. Dateien werden
  vor der Ausführung in ein nur für SYSTEM und Administratoren beschreibbares
  Arbeitsverzeichnis kopiert bzw. geladen. Beliebige URLs werden nicht unterstützt.
  / The scripts in `Installations-Scripte` install software only after opt-in
  and only from winget (fixed package ID, `winget` source, hash verified by
  winget), an admin-supplied local/UNC file (optionally SHA256-verified) or a
  built-in HTTPS vendor source (`Download`, currently only the Office Deployment
  Tool from `officecdn.microsoft.com`) whose Authenticode signature must be valid
  and issued to the expected publisher. Files are copied/downloaded to a working
  directory writable only by SYSTEM and administrators before execution.
  Arbitrary URLs are not supported.
- Custom-Field-Inhalte können interne Metadaten enthalten (Benutzer, Netzwerk);
  Leserechte in NinjaOne entsprechend einschränken.
  / Custom fields may contain internal metadata; restrict read permissions.

## Code-Signierung / Code signing

Einzelne Skripte (insbesondere `05 - DNS/00-readDNSSettingsClient.ps1` und
`05 - DNS/01-setDNSSettingsClient.ps1`) wurden früher mit Authenticode signiert.
Jede inhaltliche Änderung macht eine Signatur ungültig (`HashMismatch`);
veraltete Signaturblöcke werden daher entfernt. Wer die Ausführungsrichtlinie
`AllSigned` nutzt, muss die Skripte nach jeder Änderung neu signieren, z. B.:

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
Set-AuthenticodeSignature -FilePath '.\05 - DNS\01-setDNSSettingsClient.ps1' `
    -Certificate $cert -TimestampServer 'http://time.certum.pl' -HashAlgorithm SHA256
Get-AuthenticodeSignature -FilePath '.\05 - DNS\01-setDNSSettingsClient.ps1'
```

/ Some scripts were previously Authenticode-signed. Any content change
invalidates the signature (`HashMismatch`), so stale signature blocks are
removed. Environments using `AllSigned` must re-sign the scripts after every
change (see example above).
