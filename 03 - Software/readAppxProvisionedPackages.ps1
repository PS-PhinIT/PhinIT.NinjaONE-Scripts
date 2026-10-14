#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert provisionierte AppX-Pakete des Images; optional Warnung bei unerwünschten Paketen.
    EN: Inventories provisioned AppX packages of the image; optionally warns about unwanted packages.
.DESCRIPTION
    DE: Liest Get-AppxProvisionedPackage -Online (Pakete, die neuen Benutzerprofilen bereitgestellt werden).
        Per-User-Installationen (Get-AppxPackage) werden nicht erfasst. Nichts wird entfernt.
        UnwantedNames vergleicht exakte DisplayNames (z. B. Microsoft.BingNews), Groß-/Kleinschreibung egal.
        Liste begrenzt (MaxRecords, 4000 Zeichen), unerwünschte Pakete zuerst; Kürzung ist kein Befund.
        Exit 0 = OK/Inventar, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = mindestens ein unerwünschtes Paket ist provisioniert.
    EN: Reads Get-AppxProvisionedPackage -Online (packages staged for new user profiles).
        Per-user installs (Get-AppxPackage) are not covered. Nothing is removed.
        UnwantedNames matches exact DisplayNames (e.g. Microsoft.BingNews), case-insensitive.
        Bounded list (MaxRecords, 4000 characters), unwanted packages first; truncation is not a finding.
        Exit 0 = OK/inventory, 1 = input, query or write error,
        2 = at least one unwanted package is provisioned.
.PARAMETER UnwantedNames
    DE: NinjaOne Text softwareAppxUnwantedNames; Standard leer (nur Inventar); 1-30 kommagetrennte Paketnamen,
        Muster ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ (keine Wildcards).
    EN: NinjaOne Text softwareAppxUnwantedNames; default empty (inventory only); 1-30 comma-separated package names,
        pattern ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ (no wildcards).
.PARAMETER MaxRecords
    DE: NinjaOne Integer softwareAppxMaxRecords; 1..200; Standard 40.
    EN: NinjaOne Integer softwareAppxMaxRecords; 1..200; default 40.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readAppxProvisionedPackages.ps1
    DE: Listet bis zu 40 provisionierte Pakete.
    EN: Lists up to 40 provisioned packages.
.EXAMPLE
    .\readAppxProvisionedPackages.ps1 -UnwantedNames 'Microsoft.BingNews,Microsoft.XboxApp' -CustomField appxProvisioned
    DE: Exit 2, wenn eines der Pakete provisioniert ist; JSON in appxProvisioned.
    EN: Exit 2 if one of the packages is provisioned; JSON to appxProvisioned.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit, DISM-Modul. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = unerwünschtes Paket provisioniert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit, DISM module. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = unwanted package provisioned.
#>
[CmdletBinding()]
param(
    [string]$UnwantedNames = $env:softwareAppxUnwantedNames,
    [string]$MaxRecords = $env:softwareAppxMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
try {
    $UnwantedNames = Resolve-Setting $UnwantedNames ''
    $MaxRecords = Resolve-Setting $MaxRecords '40'
    $CustomField = Resolve-Setting $CustomField ''
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'softwareAppxMaxRecords: 1..200.' }
    $unwanted = @()
    if ($UnwantedNames) {
        $unwanted = @($UnwantedNames.Split(',') | ForEach-Object { $_.Trim() })
        if ($unwanted.Count -gt 30 -or @($unwanted | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' }).Count -gt 0) {
            throw 'Ungültige softwareAppxUnwantedNames / Invalid softwareAppxUnwantedNames.'
        }
        $unwanted = @($unwanted | Sort-Object -Unique)
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue)) { throw 'Get-AppxProvisionedPackage fehlt / unavailable.' }

    $packages = @(Get-AppxProvisionedPackage -Online | ForEach-Object {
        $name = [string]$_.DisplayName
        [pscustomobject]@{ DisplayName = $name; Version = [string]$_.Version; Unwanted = ($unwanted.Count -gt 0 -and $unwanted -contains $name) }
    } | Sort-Object @{ Expression = { -not $_.Unwanted } }, DisplayName)
    $found = @($packages | Where-Object { $_.Unwanted } | ForEach-Object { $_.DisplayName } | Sort-Object -Unique)
    $records = @($packages | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; TotalPackages = $packages.Count; UnwantedChecked = $unwanted
            UnwantedFound = $found; ReportedRecords = $records.Count; Truncated = $records.Count -lt $packages.Count
            Packages = $records
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
    if ($found.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
