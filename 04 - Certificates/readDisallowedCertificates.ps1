#Requires -Version 5.1

<#
.SYNOPSIS
DE: Inventarisiert LocalMachine\Disallowed (nicht vertrauenswürdige Zertifikate), optional mit Pflichtliste.
EN: Inventories LocalMachine\Disallowed (untrusted certificates), optionally with a required list.
.DESCRIPTION
DE: Liest Cert:\LocalMachine\Disallowed per Get-ChildItem und meldet Thumbprint, Betreff und Ablauf
    (sortiert nach Thumbprint, begrenzt auf MaxRecords, 4000-Zeichen-Kürzung mit Truncated/TotalCertificates).
    Optional: Thumbprints, die im Speicher vorhanden sein müssen (z. B. bewusst gesperrte Zertifikate).
    Fehlt der Speicher, gilt er als leer. Nur lesend; keine privaten Schlüssel.
EN: Reads Cert:\LocalMachine\Disallowed via Get-ChildItem and reports thumbprint, subject and expiry
    (sorted by thumbprint, bounded by MaxRecords, 4000-char shrinking with Truncated/TotalCertificates).
    Optional: thumbprints that must be present in the store (e.g. deliberately blocked certificates).
    A missing store is treated as empty. Read-only; no private keys.
.PARAMETER RequiredThumbprints
DE: NinjaOne Text certDisallowedRequiredThumbprints; Standard leer; bis 50 Einträge, komma- oder
    semikolongetrennt, je 40 Hexzeichen (Leerzeichen und unsichtbare Markierungen werden entfernt).
EN: NinjaOne text certDisallowedRequiredThumbprints; default empty; up to 50 entries, comma- or
    semicolon-separated, 40 hex characters each (spaces and invisible marks are removed).
.PARAMETER MaxRecords
DE: NinjaOne Integer certDisallowedMaxRecords; 1..100; Standard 25.
EN: NinjaOne Integer certDisallowedMaxRecords; 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\readDisallowedCertificates.ps1
DE: Listet bis zu 25 nicht vertrauenswürdige Zertifikate.
EN: Lists up to 25 untrusted certificates.
.EXAMPLE
.\readDisallowedCertificates.ps1 -RequiredThumbprints '0123456789ABCDEF0123456789ABCDEF01234567' -CustomField disallowedCertificates
DE: Exit 2, wenn das genannte Zertifikat nicht gesperrt ist; JSON in disallowedCertificates.
EN: Exit 2 if the given certificate is not blocked; JSON to disallowedCertificates.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = OK, 1 = Eingabe-, Abfrage- oder
    Schreibfehler, 2 = mindestens ein Pflicht-Thumbprint fehlt in Disallowed.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = OK, 1 = input, query or write error,
    2 = at least one required thumbprint is missing from Disallowed.
#>
[CmdletBinding()]
param(
    [string]$RequiredThumbprints = $env:certDisallowedRequiredThumbprints,
    [string]$MaxRecords = $env:certDisallowedMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $RequiredThumbprints = ([string]$RequiredThumbprints).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequiredThumbprints -ieq 'null') { $RequiredThumbprints = '' }
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '25' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if ($MaxRecords -notmatch '^\d{1,3}$' -or -not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'certDisallowedMaxRecords: 1..100 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $required = @()
    if ($RequiredThumbprints) {
        if ($RequiredThumbprints.Length -gt 3000) { throw 'certDisallowedRequiredThumbprints zu lang / too long.' }
        $required = @(($RequiredThumbprints -split '[,;]') | ForEach-Object { ($_ -replace '[\s\u200E\u200F]', '').ToUpperInvariant() })
        if ($required.Count -gt 50 -or @($required | Where-Object { $_ -notmatch '^[0-9A-F]{40}$' }).Count -gt 0) {
            throw 'certDisallowedRequiredThumbprints: bis 50 x 40 Hexzeichen / up to 50 x 40 hex characters.'
        }
        $required = @($required | Sort-Object -Unique)
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $storeFound = $true
    try { $certificates = @(Get-ChildItem -Path 'Cert:\LocalMachine\Disallowed' -ErrorAction Stop | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] } | Sort-Object Thumbprint) }
    catch [System.Management.Automation.ItemNotFoundException] { $certificates = @(); $storeFound = $false }
    $present = @($certificates | ForEach-Object { $_.Thumbprint.ToUpperInvariant() })
    $missing = @($required | Where-Object { $present -notcontains $_ })
    $records = @($certificates | ForEach-Object {
        $subject = [string]$_.Subject
        if ($subject.Length -gt 200) { $subject = $subject.Substring(0, 200) }
        [pscustomobject][ordered]@{ Thumbprint = $_.Thumbprint; Subject = $subject; NotAfterUtc = $_.NotAfter.ToUniversalTime().ToString('o') }
    })
    $selected = @($records | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Store = 'LocalMachine\Disallowed'; StoreFound = $storeFound
            TotalCertificates = $records.Count; ReportedRecords = $selected.Count; Truncated = $selected.Count -lt $records.Count
            RequiredCount = $required.Count; MissingRequired = $missing; Certificates = $selected
        })
        if ($report.Length -le 4000) { break }
        if ($selected.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $selected = @($selected | Select-Object -First ($selected.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($missing.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
