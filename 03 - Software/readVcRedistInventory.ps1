#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert Visual C++ Redistributables (Jahr, Architektur, Version) und meldet nicht mehr unterstützte.
    EN: Inventories Visual C++ Redistributables (year, architecture, version) and reports out-of-support ones.
.DESCRIPTION
    DE: Liest die 64- und 32-Bit-Uninstall-Schlüssel unter HKLM; verschwundene Unterschlüssel werden übersprungen.
        Erfasst Anzeigenamen "Microsoft Visual C++ <Jahr>[-<Jahr>] ... Redistributable ...". Die Architektur stammt
        aus dem Anzeigenamen (x86/x64/ARM64), da Bundles auch im 32-Bit-Zweig registriert sein können.
        Maßgeblich für "nicht unterstützt" ist das erste Jahr (2015-2022 = 2015, unterstützt).
        Nichts wird deinstalliert. Begrenzte Liste (4000 Zeichen), nicht unterstützte Einträge zuerst.
        Exit 0 = OK/Inventar, 1 = Eingabe-, Registry- oder Schreibfehler,
        2 = WarnUnsupported=true und mindestens ein Redistributable aus UnsupportedYears installiert.
    EN: Reads the 64- and 32-bit HKLM uninstall keys; vanished subkeys are skipped.
        Matches display names "Microsoft Visual C++ <year>[-<year>] ... Redistributable ...". The architecture is
        taken from the display name (x86/x64/ARM64) because bundles may register in the 32-bit branch.
        The first year decides support status (2015-2022 = 2015, supported).
        Nothing is uninstalled. Bounded list (4000 characters), unsupported entries first.
        Exit 0 = OK/inventory, 1 = input, registry or write error,
        2 = WarnUnsupported=true and at least one redistributable from UnsupportedYears is installed.
.PARAMETER WarnUnsupported
    DE: NinjaOne Checkbox/Text softwareVcRedistWarnUnsupported; true/false; Standard true.
    EN: NinjaOne checkbox/text softwareVcRedistWarnUnsupported; true/false; default true.
.PARAMETER UnsupportedYears
    DE: NinjaOne Text softwareVcRedistUnsupportedYears; kommagetrennte Jahre 2005..2099 (max. 20);
        Standard 2005,2008,2010,2012,2013.
    EN: NinjaOne Text softwareVcRedistUnsupportedYears; comma-separated years 2005..2099 (max. 20);
        default 2005,2008,2010,2012,2013.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readVcRedistInventory.ps1
    DE: Exit 2, wenn 2005/2008/2010/2012/2013-Redistributables installiert sind.
    EN: Exit 2 if 2005/2008/2010/2012/2013 redistributables are installed.
.EXAMPLE
    .\readVcRedistInventory.ps1 -WarnUnsupported false -CustomField vcRedistInventory
    DE: Nur Inventar ohne Warnung; JSON in vcRedistInventory.
    EN: Inventory only without warning; JSON to vcRedistInventory.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = nicht unterstützte Version vorhanden.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = out-of-support version present.
#>
[CmdletBinding()]
param(
    [string]$WarnUnsupported = $env:softwareVcRedistWarnUnsupported,
    [string]$UnsupportedYears = $env:softwareVcRedistUnsupportedYears,
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
    $WarnUnsupported = Resolve-Setting $WarnUnsupported 'true'
    $UnsupportedYears = Resolve-Setting $UnsupportedYears '2005,2008,2010,2012,2013'
    $CustomField = Resolve-Setting $CustomField ''
    $warn = $false
    if (-not [bool]::TryParse($WarnUnsupported, [ref]$warn)) { throw 'softwareVcRedistWarnUnsupported: true/false.' }
    $years = @($UnsupportedYears.Split(',') | ForEach-Object { $_.Trim() })
    if ($years.Count -gt 20 -or @($years | Where-Object { $_ -notmatch '^20\d\d$' -or [int]$_ -lt 2005 }).Count -gt 0) {
        throw 'softwareVcRedistUnsupportedYears: Jahre 2005..2099 / years 2005..2099.'
    }
    $years = @($years | Sort-Object -Unique)
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $all = @(foreach ($entry in @(Get-UninstallEntry)) {
        $match = [regex]::Match($entry.Name, '^Microsoft Visual C\+\+ (?<from>\d{4})(?:-(?<to>\d{4}))?\b.*\bRedistributable\b', 'IgnoreCase')
        if (-not $match.Success) { continue }
        $arch = [regex]::Match($entry.Name, '\b(x64|x86|arm64|ia64)\b', 'IgnoreCase')
        $year = $match.Groups['from'].Value
        [pscustomobject]@{
            Name = $entry.Name
            Year = if ($match.Groups['to'].Success) { '{0}-{1}' -f $year, $match.Groups['to'].Value } else { $year }
            Architecture = if ($arch.Success) { $arch.Groups[1].Value.ToLowerInvariant() } else { 'unknown' }
            Version = $entry.Version; RegistryView = $entry.RegistryView
            Unsupported = $years -contains $year
        }
    })
    $all = @($all | Sort-Object @{ Expression = { -not $_.Unsupported } }, Year, Architecture, Name)
    $unsupportedCount = @($all | Where-Object { $_.Unsupported }).Count
    $records = @($all | Select-Object -First 60)
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; WarnUnsupported = $warn; UnsupportedYears = $years
            TotalEntries = $all.Count; UnsupportedCount = $unsupportedCount
            ReportedRecords = $records.Count; Truncated = $records.Count -lt $all.Count; Redistributables = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warn -and $unsupportedCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
