#Requires -Version 5.1
<#
.SYNOPSIS
DE: Selbst ausgestellte Zertifikate als Kandidaten für selbst signierte Zertifikate melden.
EN: Report self-issued certificates as candidates for self-signed certificates.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit; StoreName=My, LocalMachine schreibgeschützt.
EN: Windows SYSTEM, 64-bit; StoreName=My, LocalMachine read-only.
DE: Vergleicht rohe Aussteller-/Betreffnamen; kein kryptografischer Signaturnachweis.
EN: Compares raw issuer/subject names; not a cryptographic proof of self-signature.
DE: CA-Schlüsselwechsel kann ebenfalls selbst ausgestellte Zertifikate erzeugen; manuell prüfen.
EN: CA key rollover can also create self-issued certificates; review manually.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen. Kandidaten: Exit 2.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters. Candidates: exit 2.
.PARAMETER StoreName
DE: String; NinjaOne selfSignedCertificateStoreName; Standard My; My, Root, CA, TrustedPublisher oder TrustedPeople, nur LocalMachine.
EN: String; NinjaOne selfSignedCertificateStoreName; default My; My, Root, CA, TrustedPublisher or TrustedPeople, LocalMachine only.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$StoreName = $env:selfSignedCertificateStoreName,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$store = $null
try {
    $StoreName = if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { '' } else { $StoreName.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { $StoreName = 'My' }
    $StoreName = $StoreName.Trim()
    if ($StoreName -notin @('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople')) { throw 'Ungültiger StoreName / Invalid StoreName.' }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
    $total = $store.Certificates.Count
    $candidates = @(foreach ($certificate in ($store.Certificates | Sort-Object Thumbprint)) {
        $subjectBytes = [Convert]::ToBase64String($certificate.SubjectName.RawData)
        $issuerBytes = [Convert]::ToBase64String($certificate.IssuerName.RawData)
        if ($subjectBytes -ceq $issuerBytes) {
            [pscustomobject]@{ Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject; NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o'); Finding = 'SelfIssuedCandidate'; SignatureVerified = $false }
        }
    })
    $store.Close()
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Store = "LocalMachine\$StoreName"; CheckedCertificates = $total; CandidateCount = $candidates.Count; Candidates = $candidates } | ConvertTo-Json -Depth 5
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
    if ($candidates.Count) { exit 2 }
    exit 0
} catch {
    Write-Error ("Kandidatenprüfung fehlgeschlagen / Candidate audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
} finally {
    if ($store) { $store.Dispose() }
}
