#Requires -Version 5.1

<#
.SYNOPSIS
DE: Installierte Software gegen eine vorgegebene Sperrliste prüfen, ohne Deinstallation.
EN: Check installed software against a supplied deny list without uninstalling anything.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. BlockedNames: semikolongetrennte exakte Anzeigenamen, keine Wildcards.
EN: Windows SYSTEM, 64-bit. BlockedNames: semicolon-separated exact display names, no wildcards.
DE: Nur maschinenweite Uninstall-Einträge; kein Beweis für Ausführungsblockierung. Treffer: Exit 2.
EN: Machine-wide uninstall entries only; not evidence of execution blocking. Match: exit 2.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters.
DE: Exit 0 = kein Treffer, 1 = Eingabe-, Registry- oder Schreibfehler, 2 = mindestens ein gesperrter Anzeigename gefunden.
EN: Exit 0 = no match, 1 = input, registry or write error, 2 = at least one blocked display name found.
.PARAMETER BlockedNames
DE: String; NinjaOne blockedSoftwareNames; kein Standard, erforderlich; 1-50 exakte Namen, semikolongetrennt; je 1-200, insgesamt maximal 3000 Zeichen; keine Steuerzeichen, * oder ?.
EN: String; NinjaOne blockedSoftwareNames; no default, required; 1-50 exact names separated by semicolons; each 1-200, maximum 3000 total characters; no control characters, * or ?.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\checkBlockedSoftware.ps1 -BlockedNames 'TeamViewer;AnyDesk'
DE: Meldet Exit 2, wenn TeamViewer oder AnyDesk exakt so maschinenweit installiert ist.
EN: Returns exit 2 if TeamViewer or AnyDesk is installed machine-wide with exactly that name.
.EXAMPLE
.\checkBlockedSoftware.ps1 -BlockedNames 'WinRAR 6.02 (64-bit);Google Toolbar for Internet Explorer' -CustomField blockedSoftwareReport
DE: Prüft zwei exakte Anzeigenamen und schreibt das JSON in blockedSoftwareReport.
EN: Checks two exact display names and writes the JSON to blockedSoftwareReport.
#>
[CmdletBinding()]
param(
    [string]$BlockedNames = $env:blockedSoftwareNames,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $BlockedNames = if ([string]::IsNullOrWhiteSpace($BlockedNames) -or $BlockedNames.Trim() -eq 'null') { '' } else { $BlockedNames.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($BlockedNames) -or $BlockedNames.Trim() -eq 'null' -or $BlockedNames.Length -gt 3000) { throw 'BlockedNames ist erforderlich (max. 3000 Zeichen) / BlockedNames required (max. 3000 characters).' }
    $names = @($BlockedNames.Split(';') | ForEach-Object { $_.Trim() })
    if ($names.Count -gt 50 -or @($names | Where-Object { -not $_ -or $_.Length -gt 200 -or $_ -match '[\x00-\x1f*?]' }).Count) { throw 'Ungültige Sperrliste / Invalid deny list.' }
    $names = @($names | Sort-Object -Unique)
    $detections = @(foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null
        $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $key) { continue }
            foreach ($name in $key.GetSubKeyNames()) {
                $entry = $key.OpenSubKey($name)
                # DE: Während Installationen entfernte Schlüssel überspringen. EN: Skip keys removed during installs.
                if ($null -eq $entry) { continue }
                try {
                    $display = [string]$entry.GetValue('DisplayName')
                    if ($names -contains $display) {
                        [pscustomobject]@{ Name = $display; Version = [string]$entry.GetValue('DisplayVersion'); RegistryView = [string]$view }
                    }
                } finally { $entry.Dispose() }
            }
        } finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
    })
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; CheckedNames = $names; MatchCount = $detections.Count; Matches = @($detections | Sort-Object Name, RegistryView) } | ConvertTo-Json -Depth 5
    Write-Output $json
    $field = if ($null -eq $CustomField) { '' } else { $CustomField.Trim() }
    if ($field -and $field -ne 'null') {
        if ($field.Length -gt 128 -or $field -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
        if ($json.Length -gt 4000) { throw 'JSON überschreitet 4000 Zeichen / JSON exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $field -Value $json -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "Ninja-Property-Set Exitcode / exit code: $global:LASTEXITCODE" }
    }
    if ($detections.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Error ("Sperrlistenprüfung fehlgeschlagen / Deny-list audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}