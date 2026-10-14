#Requires -Version 5.1

<#
.SYNOPSIS
DE: Findet Zertifikate mit schwacher Signatur (MD2/MD4/MD5/SHA1) oder zu kurzen Schlüsseln.
EN: Finds certificates with weak signatures (MD2/MD4/MD5/SHA1) or short keys.
.DESCRIPTION
DE: Liest LocalMachine\My und optional weitere LocalMachine-Speicher per Get-ChildItem. Befunde:
    Signaturalgorithmus MD2/MD4/MD5/SHA1, RSA-Schlüssel < 2048 Bit, ECC-Schlüssel < 256 Bit.
    Bei selbst ausgestellten Zertifikaten in Root/AuthRoot wird die Signatur nicht bewertet
    (Vertrauensanker-Signaturen werden nicht geprüft). Nur öffentliche Schlüssel; nur lesend.
EN: Reads LocalMachine\My and optional additional LocalMachine stores via Get-ChildItem. Findings:
    signature algorithm MD2/MD4/MD5/SHA1, RSA keys < 2048 bits, ECC keys < 256 bits. For
    self-issued certificates in Root/AuthRoot the signature is not rated (trust anchor
    signatures are not verified). Public keys only; read-only.
DE: Fehlende Speicher stehen in MissingStores. Bericht: nur Befunde, MaxRecords, 4000-Zeichen-Kürzung.
EN: Missing stores are listed in MissingStores. Report: findings only, MaxRecords, 4000-char shrinking.
.PARAMETER AdditionalStores
DE: NinjaOne Text certWeakAdditionalStores; Standard leer; kommagetrennt aus Root, CA, AuthRoot,
    TrustedPublisher, TrustedPeople, WebHosting, Remote Desktop.
EN: NinjaOne text certWeakAdditionalStores; default empty; comma-separated from Root, CA, AuthRoot,
    TrustedPublisher, TrustedPeople, WebHosting, Remote Desktop.
.PARAMETER MaxRecords
DE: NinjaOne Integer certWeakMaxRecords; 1..100; Standard 25.
EN: NinjaOne Integer certWeakMaxRecords; 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkWeakCertificates.ps1
DE: Prüft nur LocalMachine\My.
EN: Checks LocalMachine\My only.
.EXAMPLE
.\checkWeakCertificates.ps1 -AdditionalStores 'WebHosting,Remote Desktop' -MaxRecords 10 -CustomField weakCertificateReport
DE: Zusätzlich WebHosting und Remote Desktop; JSON in weakCertificateReport.
EN: Additionally WebHosting and Remote Desktop; JSON to weakCertificateReport.
.NOTES
DE: Windows PowerShell 5.1 (.NET 4.6.1+), SYSTEM, 64-Bit. Exit 0 = keine schwachen Zertifikate,
    1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = mindestens ein schwaches Zertifikat.
EN: Windows PowerShell 5.1 (.NET 4.6.1+), SYSTEM, 64-bit. Exit 0 = no weak certificates,
    1 = input, query or write error, 2 = at least one weak certificate.
#>
[CmdletBinding()]
param(
    [string]$AdditionalStores = $env:certWeakAdditionalStores,
    [string]$MaxRecords = $env:certWeakMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $AdditionalStores = ([string]$AdditionalStores).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($AdditionalStores -ieq 'null') { $AdditionalStores = '' }
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '25' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if ($MaxRecords -notmatch '^\d{1,3}$' -or -not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'certWeakMaxRecords: 1..100 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $allowedStores = @('Root', 'CA', 'AuthRoot', 'TrustedPublisher', 'TrustedPeople', 'WebHosting', 'Remote Desktop')
    $stores = New-Object System.Collections.Generic.List[string]
    $stores.Add('My')
    if ($AdditionalStores) {
        if ($AdditionalStores.Length -gt 200) { throw 'certWeakAdditionalStores zu lang / too long.' }
        foreach ($entry in $AdditionalStores.Split(',')) {
            $name = @($allowedStores | Where-Object { $_ -ieq $entry.Trim() } | Select-Object -First 1)
            if ($name.Count -eq 0) { throw "certWeakAdditionalStores: ungültiger Speicher / invalid store '$($entry.Trim())'." }
            if (-not $stores.Contains($name[0])) { $stores.Add($name[0]) }
        }
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $weakSignatures = @{
        '1.2.840.113549.1.1.2' = 'MD2RSA'; '1.2.840.113549.1.1.3' = 'MD4RSA'; '1.2.840.113549.1.1.4' = 'MD5RSA'
        '1.2.840.113549.1.1.5' = 'SHA1RSA'; '1.3.14.3.2.29' = 'SHA1RSA'; '1.2.840.10045.4.1' = 'SHA1ECDSA'
        '1.2.840.10040.4.3' = 'SHA1DSA'; '1.3.14.3.2.27' = 'SHA1DSA'
    }
    # DE: KeySize per Reflection, da manche Schlüsselklassen nur den Setter überschreiben.
    # EN: KeySize via reflection because some key classes only override the setter.
    $keySizeProperty = [System.Security.Cryptography.AsymmetricAlgorithm].GetProperty('KeySize')
    $missingStores = New-Object System.Collections.Generic.List[string]
    $checked = 0
    $weak = New-Object System.Collections.Generic.List[object]
    foreach ($storeName in $stores) {
        try { $items = @(Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction Stop | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }) }
        catch [System.Management.Automation.ItemNotFoundException] { $missingStores.Add($storeName); continue }
        foreach ($certificate in ($items | Sort-Object Thumbprint)) {
            $checked++
            $reasons = @()
            $selfIssued = [Convert]::ToBase64String($certificate.SubjectName.RawData) -ceq [Convert]::ToBase64String($certificate.IssuerName.RawData)
            $signatureOid = [string]$certificate.SignatureAlgorithm.Value
            if ($weakSignatures.ContainsKey($signatureOid) -and -not ($selfIssued -and $storeName -in @('Root', 'AuthRoot'))) {
                $reasons += "WeakSignature:$($weakSignatures[$signatureOid])"
            }
            $keyOid = [string]$certificate.PublicKey.Oid.Value
            $keyAlgorithm = 'Other'
            $bits = $null
            $key = $null
            try {
                if ($keyOid -in @('1.2.840.113549.1.1.1', '1.2.840.113549.1.1.10')) {
                    $keyAlgorithm = 'RSA'
                    $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
                } elseif ($keyOid -eq '1.2.840.10045.2.1') {
                    $keyAlgorithm = 'ECC'
                    $key = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPublicKey($certificate)
                }
                if ($null -ne $key) { $bits = [int]$keySizeProperty.GetValue($key, $null) }
            } catch {
                $bits = $null
            } finally {
                if ($null -ne $key) { $key.Dispose() }
            }
            if ($keyAlgorithm -eq 'RSA' -and $null -ne $bits -and $bits -lt 2048) { $reasons += "WeakRsaKey:$bits" }
            if ($keyAlgorithm -eq 'ECC' -and $null -ne $bits -and $bits -lt 256) { $reasons += "WeakEccKey:$bits" }
            if ($reasons.Count -gt 0) {
                $weak.Add([pscustomobject][ordered]@{
                    Store = $storeName; Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject
                    NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o'); SignatureAlgorithm = $signatureOid
                    KeyAlgorithm = $keyAlgorithm; KeySize = $bits; Findings = $reasons
                })
            }
        }
    }
    $selected = @($weak | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Stores = @($stores); MissingStores = @($missingStores)
            CheckedCertificates = $checked; WeakCount = $weak.Count; ReportedRecords = $selected.Count
            Truncated = $selected.Count -lt $weak.Count; WeakCertificates = $selected
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
    if ($weak.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
