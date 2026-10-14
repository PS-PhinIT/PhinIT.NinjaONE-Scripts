#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob vorgegebene Software maschinenweit installiert ist (Pflichtliste), ohne etwas zu installieren.
    EN: Checks that required software is installed machine-wide (allow/required list) without installing anything.
.DESCRIPTION
    DE: Liest die 64- und 32-Bit-Uninstall-Schlüssel unter HKLM (keine Benutzerprofile, keine AppX-Pakete).
        Während der Abfrage verschwundene Unterschlüssel werden übersprungen. RequiredNames ist eine
        kommagetrennte Liste von Anzeigenamen. MatchMode Exact = exakter Anzeigename (Groß-/Kleinschreibung egal),
        Contains = literaler Teilstring ohne Wildcards (* und ? sind nicht erlaubt).
        Bericht als JSON, optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
        Exit 0 = alle vorhanden, 1 = Eingabe-, Registry- oder Schreibfehler, 2 = mindestens ein Name fehlt.
    EN: Reads the 64- and 32-bit HKLM uninstall keys (no user profiles, no AppX packages).
        Subkeys that vanish during the query are skipped. RequiredNames is a comma-separated list of
        display names. MatchMode Exact = exact display name (case-insensitive), Contains = literal
        substring without wildcards (* and ? are rejected).
        JSON report, optionally written to a MultiLine field (max. 4000 characters, otherwise exit 1).
        Exit 0 = all present, 1 = input, registry or write error, 2 = at least one name missing.
.PARAMETER RequiredNames
    DE: NinjaOne Text softwareRequiredNames; erforderlich, kein Standard; 1-50 kommagetrennte Namen, je 1-200 Zeichen,
        gesamt max. 3000; keine Steuerzeichen, * oder ?.
    EN: NinjaOne Text softwareRequiredNames; required, no default; 1-50 comma-separated names, each 1-200 characters,
        max. 3000 total; no control characters, * or ?.
.PARAMETER MatchMode
    DE: NinjaOne Dropdown/Text softwareRequiredMatchMode; Exact oder Contains; Standard Exact.
    EN: NinjaOne drop-down/text softwareRequiredMatchMode; Exact or Contains; default Exact.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\checkRequiredSoftware.ps1 -RequiredNames '7-Zip 23.01 (x64),Microsoft Edge'
    DE: Exit 2, wenn einer der beiden exakten Anzeigenamen fehlt.
    EN: Exit 2 if one of the two exact display names is missing.
.EXAMPLE
    .\checkRequiredSoftware.ps1 -RequiredNames '7-Zip,Sophos Endpoint Agent' -MatchMode Contains -CustomField requiredSoftwareReport
    DE: Teilstring-Vergleich; JSON in requiredSoftwareReport schreiben.
    EN: Substring match; write JSON to requiredSoftwareReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = Pflichtsoftware fehlt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = required software missing.
#>
[CmdletBinding()]
param(
    [string]$RequiredNames = $env:softwareRequiredNames,
    [string]$MatchMode = $env:softwareRequiredMatchMode,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function Get-UninstallEntry {
    $roots = [ordered]@{
        Registry64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Registry32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    }
    foreach ($view in $roots.Keys) {
        if (-not (Test-Path -LiteralPath $roots[$view])) { continue }
        $enumErrors = $null
        $keys = @(Get-ChildItem -LiteralPath $roots[$view] -ErrorAction SilentlyContinue -ErrorVariable enumErrors)
        foreach ($enumError in @($enumErrors)) {
            if ($enumError.Exception -isnot [System.Management.Automation.ItemNotFoundException]) { throw $enumError.Exception }
        }
        foreach ($key in $keys) {
            # DE: Während Installationen entfernte Schlüssel überspringen. EN: Skip keys removed during installs.
            try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            $display = [string]$props.DisplayName
            if ([string]::IsNullOrWhiteSpace($display)) { continue }
            [pscustomobject]@{ Name = $display.Trim(); Version = [string]$props.DisplayVersion; RegistryView = $view }
        }
    }
}
try {
    $RequiredNames = Resolve-Setting $RequiredNames ''
    $MatchMode = Resolve-Setting $MatchMode 'Exact'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $RequiredNames -or $RequiredNames.Length -gt 3000) { throw 'softwareRequiredNames erforderlich (max. 3000 Zeichen) / required (max. 3000 characters).' }
    $names = @($RequiredNames.Split(',') | ForEach-Object { $_.Trim() })
    if ($names.Count -gt 50 -or @($names | Where-Object { -not $_ -or $_.Length -gt 200 -or $_ -match '[\x00-\x1f*?]' }).Count -gt 0) {
        throw 'Ungültige Namensliste / Invalid name list.'
    }
    $names = @($names | Sort-Object -Unique)
    if ($MatchMode -notin @('Exact', 'Contains')) { throw 'softwareRequiredMatchMode: Exact oder/or Contains.' }
    $MatchMode = if ($MatchMode -eq 'Exact') { 'Exact' } else { 'Contains' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $installed = @(Get-UninstallEntry)
    $missing = 0
    $results = @(foreach ($name in $names) {
        $found = @($installed | Where-Object {
            if ($MatchMode -eq 'Exact') { $_.Name -eq $name } else { $_.Name.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
        } | Sort-Object Name, RegistryView)
        if ($found.Count -eq 0) { $missing++ }
        [pscustomobject]@{
            RequiredName = $name
            Installed = $found.Count -gt 0
            MatchCount = $found.Count
            Matches = @($found | Select-Object -First 3)
        }
    })
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; MatchMode = $MatchMode; ScannedEntries = $installed.Count
        MissingCount = $missing; Results = $results
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($missing -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
