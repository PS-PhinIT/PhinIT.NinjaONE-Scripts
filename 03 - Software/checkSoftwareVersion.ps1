#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob eine installierte Software mindestens eine vorgegebene Version hat.
    EN: Checks that an installed software product meets a minimum version.
.DESCRIPTION
    DE: Liest die 64- und 32-Bit-Uninstall-Schlüssel unter HKLM; verschwundene Unterschlüssel werden übersprungen.
        SoftwareName ist ein exakter Anzeigename (MatchMode Exact) oder ein literaler Teilstring (Contains), ohne Wildcards.
        Versionen werden normalisiert: führender numerischer Teil (max. 4 Komponenten, z. B. "v1.2.3-beta" -> 1.2.3.0),
        fehlende Komponenten = 0, Vergleich per [version]. Nicht auswertbare Versionen gelten als Befund.
        Bei mehreren Treffern (z. B. x64 und x86) führt jeder Treffer unter dem Minimum zu Exit 2.
        Exit 0 = alle Treffer >= Minimum (oder nicht installiert mit MissingIsWarning=false),
        1 = Eingabe-, Registry- oder Schreibfehler, 2 = Version zu alt/nicht auswertbar oder nicht installiert (Standard).
    EN: Reads the 64- and 32-bit HKLM uninstall keys; subkeys that vanish are skipped.
        SoftwareName is an exact display name (MatchMode Exact) or a literal substring (Contains), no wildcards.
        Versions are normalized: leading numeric part (max. 4 components, e.g. "v1.2.3-beta" -> 1.2.3.0),
        missing components = 0, compared as [version]. Unparseable versions are treated as a finding.
        With several matches (e.g. x64 and x86) any match below the minimum causes exit 2.
        Exit 0 = all matches >= minimum (or not installed with MissingIsWarning=false),
        1 = input, registry or write error, 2 = version too old/unparseable or not installed (default).
.PARAMETER SoftwareName
    DE: NinjaOne Text softwareVersionName; erforderlich; 1-200 Zeichen, keine Steuerzeichen, * oder ?.
    EN: NinjaOne Text softwareVersionName; required; 1-200 characters, no control characters, * or ?.
.PARAMETER MinimumVersion
    DE: NinjaOne Text softwareVersionMinimum; erforderlich; 1-4 numerische Komponenten, z. B. 23.1 oder 120.0.6099.71.
    EN: NinjaOne Text softwareVersionMinimum; required; 1-4 numeric components, e.g. 23.1 or 120.0.6099.71.
.PARAMETER MatchMode
    DE: NinjaOne Text softwareVersionMatchMode; Exact oder Contains; Standard Exact.
    EN: NinjaOne Text softwareVersionMatchMode; Exact or Contains; default Exact.
.PARAMETER MissingIsWarning
    DE: NinjaOne Checkbox/Text softwareVersionMissingIsWarning; true/false; Standard true (nicht installiert = Exit 2).
    EN: NinjaOne checkbox/text softwareVersionMissingIsWarning; true/false; default true (not installed = exit 2).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\checkSoftwareVersion.ps1 -SoftwareName 'Google Chrome' -MinimumVersion 120.0
    DE: Exit 2, wenn Google Chrome fehlt oder älter als 120.0 ist.
    EN: Exit 2 if Google Chrome is missing or older than 120.0.
.EXAMPLE
    .\checkSoftwareVersion.ps1 -SoftwareName '7-Zip' -MatchMode Contains -MinimumVersion 23.01 -MissingIsWarning false -CustomField zipVersion
    DE: Fehlendes 7-Zip ist OK; zu alte Versionen ergeben Exit 2; JSON in zipVersion.
    EN: Missing 7-Zip is OK; outdated versions return exit 2; JSON to zipVersion.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = veraltet/nicht auswertbar/fehlend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = outdated/unparseable/missing.
#>
[CmdletBinding()]
param(
    [string]$SoftwareName = $env:softwareVersionName,
    [string]$MinimumVersion = $env:softwareVersionMinimum,
    [string]$MatchMode = $env:softwareVersionMatchMode,
    [string]$MissingIsWarning = $env:softwareVersionMissingIsWarning,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-NormalizedVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text.Trim(), '^[vV]?(\d+(?:\.\d+){0,3})')
    if (-not $match.Success) { return $null }
    $parts = @($match.Groups[1].Value.Split('.'))
    while ($parts.Count -lt 4) { $parts += '0' }
    $parsed = $null
    if ([version]::TryParse(($parts -join '.'), [ref]$parsed)) { return $parsed }
    return $null
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
    $SoftwareName = Resolve-Setting $SoftwareName ''
    $MinimumVersion = Resolve-Setting $MinimumVersion ''
    $MatchMode = Resolve-Setting $MatchMode 'Exact'
    $MissingIsWarning = Resolve-Setting $MissingIsWarning 'true'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $SoftwareName -or $SoftwareName.Length -gt 200 -or $SoftwareName -match '[\x00-\x1f*?]') {
        throw 'softwareVersionName: 1-200 Zeichen ohne Wildcards / 1-200 characters without wildcards.'
    }
    if ($MinimumVersion -notmatch '^\d{1,9}(\.\d{1,9}){0,3}$') { throw 'softwareVersionMinimum: z. B. / e.g. 1.2.3' }
    $minimum = ConvertTo-NormalizedVersion $MinimumVersion
    if ($null -eq $minimum) { throw 'softwareVersionMinimum ungültig / invalid.' }
    if ($MatchMode -notin @('Exact', 'Contains')) { throw 'softwareVersionMatchMode: Exact oder/or Contains.' }
    $MatchMode = if ($MatchMode -eq 'Exact') { 'Exact' } else { 'Contains' }
    $missingWarn = $false
    if (-not [bool]::TryParse($MissingIsWarning, [ref]$missingWarn)) { throw 'softwareVersionMissingIsWarning: true/false.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $found = @(Get-UninstallEntry | Where-Object {
        if ($MatchMode -eq 'Exact') { $_.Name -eq $SoftwareName } else { $_.Name.IndexOf($SoftwareName, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
    } | Sort-Object Name, RegistryView)
    $evaluated = @(foreach ($item in $found) {
        $normalized = ConvertTo-NormalizedVersion $item.Version
        $itemStatus = if ($null -eq $normalized) { 'Unparseable' } elseif ($normalized -lt $minimum) { 'Outdated' } else { 'OK' }
        [pscustomobject]@{
            Name = $item.Name; Version = $item.Version; RegistryView = $item.RegistryView
            NormalizedVersion = if ($normalized) { $normalized.ToString() } else { $null }; Status = $itemStatus
        }
    })
    $outdated = @($evaluated | Where-Object { $_.Status -ne 'OK' }).Count
    # DE: Befunde zuerst, maximal 20 Einträge. EN: Findings first, at most 20 records.
    $records = @(@($evaluated | Where-Object { $_.Status -ne 'OK' }) + @($evaluated | Where-Object { $_.Status -eq 'OK' }) | Select-Object -First 20)
    $status = if ($found.Count -eq 0) { 'NotInstalled' } elseif ($outdated -gt 0) { 'Outdated' } else { 'OK' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; SoftwareName = $SoftwareName; MatchMode = $MatchMode
        MinimumVersion = $minimum.ToString(); Status = $status; TotalMatches = $found.Count
        Truncated = $found.Count -gt $records.Count; Installations = $records
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($status -eq 'Outdated' -or ($status -eq 'NotInstalled' -and $missingWarn)) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
