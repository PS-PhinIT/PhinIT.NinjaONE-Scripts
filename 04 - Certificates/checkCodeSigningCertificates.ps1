#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft Codesignatur-Zertifikate (EKU 1.3.6.1.5.5.7.3.3) in LocalMachine\My und TrustedPublisher auf Ablauf.
EN: Checks code-signing certificates (EKU 1.3.6.1.5.5.7.3.3) in LocalMachine\My and TrustedPublisher for expiry.
.DESCRIPTION
DE: Liest Cert:\LocalMachine\My und Cert:\LocalMachine\TrustedPublisher per Get-ChildItem und
    wertet nur Zertifikate aus, deren Enhanced-Key-Usage-Erweiterung Code Signing enthält
    (Zertifikate ohne EKU-Erweiterung werden nicht gezählt). Status: OK, ExpiringSoon, Expired.
    Fehlende Speicher stehen in MissingStores. Nur lesend; keine privaten Schlüssel.
EN: Reads Cert:\LocalMachine\My and Cert:\LocalMachine\TrustedPublisher via Get-ChildItem and
    evaluates only certificates whose enhanced key usage extension contains Code Signing
    (certificates without an EKU extension are not counted). Status: OK, ExpiringSoon, Expired.
    Missing stores are listed in MissingStores. Read-only; no private keys.
DE: Bericht: Befunde zuerst, MaxRecords, 4000-Zeichen-Kürzung (Truncated/TotalCodeSigning).
EN: Report: findings first, MaxRecords, 4000-char shrinking (Truncated/TotalCodeSigning).
.PARAMETER WarningDays
DE: NinjaOne Integer certCodeSigningWarningDays; 0..3650; Standard 30.
EN: NinjaOne Integer certCodeSigningWarningDays; 0..3650; default 30.
.PARAMETER MaxRecords
DE: NinjaOne Integer certCodeSigningMaxRecords; 1..100; Standard 25.
EN: NinjaOne Integer certCodeSigningMaxRecords; 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkCodeSigningCertificates.ps1
DE: Warnt bei Codesignatur-Zertifikaten, die abgelaufen sind oder in 30 Tagen ablaufen.
EN: Warns about code-signing certificates that are expired or expire within 30 days.
.EXAMPLE
.\checkCodeSigningCertificates.ps1 -WarningDays 60 -MaxRecords 10 -CustomField codeSigningReport
DE: 60 Tage Vorlauf, höchstens 10 Einträge; JSON in codeSigningReport.
EN: 60 days lead time, at most 10 records; JSON to codeSigningReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = OK, 1 = Eingabe-, Abfrage- oder
    Schreibfehler, 2 = mindestens ein Codesignatur-Zertifikat abgelaufen oder läuft innerhalb WarningDays ab.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = OK, 1 = input, query or write error,
    2 = at least one code-signing certificate expired or expiring within WarningDays.
#>
[CmdletBinding()]
param(
    [string]$WarningDays = $env:certCodeSigningWarningDays,
    [string]$MaxRecords = $env:certCodeSigningMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $WarningDays = ([string]$WarningDays).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $WarningDays -or $WarningDays -ieq 'null') { $WarningDays = '30' }
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '25' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $days = 0
    $limit = 0
    if ($WarningDays -notmatch '^\d{1,4}$' -or -not [int]::TryParse($WarningDays, [ref]$days) -or $days -gt 3650) { throw 'certCodeSigningWarningDays: 0..3650 erforderlich / required.' }
    if ($MaxRecords -notmatch '^\d{1,3}$' -or -not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'certCodeSigningMaxRecords: 1..100 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $now = [DateTime]::UtcNow
    $missingStores = New-Object System.Collections.Generic.List[string]
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($storeName in @('My', 'TrustedPublisher')) {
        try { $items = @(Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction Stop | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }) }
        catch [System.Management.Automation.ItemNotFoundException] { $missingStores.Add($storeName); continue }
        foreach ($certificate in ($items | Sort-Object Thumbprint)) {
            $codeSigning = $false
            foreach ($extension in $certificate.Extensions) {
                if ($extension.Oid.Value -ne '2.5.29.37') { continue }
                $eku = New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension -ArgumentList $extension, $extension.Critical
                foreach ($usage in $eku.EnhancedKeyUsages) { if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { $codeSigning = $true } }
            }
            if (-not $codeSigning) { continue }
            $expiry = $certificate.NotAfter.ToUniversalTime()
            $status = 'OK'
            if ($expiry -le $now) { $status = 'Expired' } elseif ($expiry -le $now.AddDays($days)) { $status = 'ExpiringSoon' }
            $records.Add([pscustomobject][ordered]@{
                Store = $storeName; Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject
                Issuer = $certificate.Issuer; NotAfterUtc = $expiry.ToString('o')
                DaysRemaining = [int][Math]::Floor(($expiry - $now).TotalDays); Status = $status
            })
        }
    }
    $findingCount = @($records | Where-Object { $_.Status -ne 'OK' }).Count
    $ordered = @(@($records | Where-Object { $_.Status -ne 'OK' } | Sort-Object DaysRemaining) + @($records | Where-Object { $_.Status -eq 'OK' } | Sort-Object DaysRemaining))
    $selected = @($ordered | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; WarningDays = $days; MissingStores = @($missingStores)
            TotalCodeSigning = $ordered.Count; FindingCount = $findingCount; ReportedRecords = $selected.Count
            Truncated = $selected.Count -lt $ordered.Count; Certificates = $selected
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
    if ($findingCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
