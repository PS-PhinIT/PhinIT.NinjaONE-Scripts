#Requires -Version 5.1
<#
.SYNOPSIS
DE: Öffentliche Zertifikatsmetadaten und EKU-OIDs inventarisieren.
EN: Inventory public certificate metadata and EKU OIDs.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. StoreName=My; SubjectContains ist ein literaler Filter.
EN: Windows SYSTEM, 64-bit. StoreName=My; SubjectContains is a literal filter.
DE: LocalMachine schreibgeschützt; keine Schlüssel-/Vertrauenskettendaten.
EN: LocalMachine read-only; no key/trust-chain data.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters.
.PARAMETER StoreName
DE: String; NinjaOne certificateInventoryStoreName; Standard My; My, Root, CA, TrustedPublisher oder TrustedPeople, nur LocalMachine.
EN: String; NinjaOne certificateInventoryStoreName; default My; My, Root, CA, TrustedPublisher or TrustedPeople, LocalMachine only.
.PARAMETER SubjectContains
DE: String; NinjaOne certificateInventorySubjectContains; Standard leer; literaler Teiltext, maximal 200 Zeichen, keine Steuerzeichen.
EN: String; NinjaOne certificateInventorySubjectContains; default empty; literal substring, maximum 200 characters, no control characters.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$StoreName = $env:certificateInventoryStoreName,
    [string]$SubjectContains = $env:certificateInventorySubjectContains,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$store = $null
try {
    $StoreName = if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { '' } else { $StoreName.Trim() }
    $SubjectContains = if ([string]::IsNullOrWhiteSpace($SubjectContains) -or $SubjectContains.Trim() -eq 'null') { '' } else { $SubjectContains.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { $StoreName = 'My' }
    $StoreName = $StoreName.Trim()
    if ($StoreName -notin @('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople')) { throw 'Ungültiger StoreName / Invalid StoreName.' }
    $filter = if ($null -eq $SubjectContains) { '' } else { $SubjectContains.Trim() }
    if ($filter -eq 'null') { $filter = '' }
    if ($filter.Length -gt 200 -or $filter -match '[\x00-\x1f]') { throw 'Ungültiger Betrefffilter / Invalid subject filter.' }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
    $total = $store.Certificates.Count
    $items = @(foreach ($certificate in ($store.Certificates | Sort-Object Thumbprint)) {
        if ($filter -and $certificate.Subject.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $eku = @()
        foreach ($extension in $certificate.Extensions) {
            if ($extension.Oid.Value -eq '2.5.29.37') {
                $decoded = New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($extension, $extension.Critical)
                $eku += @($decoded.EnhancedKeyUsages | ForEach-Object { $_.Value })
            }
        }
        [pscustomobject]@{
            Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject; Issuer = $certificate.Issuer
            NotBeforeUtc = $certificate.NotBefore.ToUniversalTime().ToString('o'); NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o')
            SignatureAlgorithmOid = $certificate.SignatureAlgorithm.Value; EnhancedKeyUsageOids = $eku
        }
    })
    $store.Close()
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Store = "LocalMachine\$StoreName"; SubjectContains = $filter; TotalCertificates = $total; ReturnedCertificates = $items.Count; Certificates = $items } | ConvertTo-Json -Depth 5
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
    exit 0
} catch {
    Write-Error ("Zertifikatsinventur fehlgeschlagen / Certificate inventory failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
} finally {
    if ($store) { $store.Dispose() }
}
