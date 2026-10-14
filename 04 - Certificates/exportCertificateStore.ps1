#Requires -Version 5.1

<#
.SYNOPSIS
DE: Zertifikatsmetadaten oder genau ein ÖFFENTLICHES DER-Zertifikat als Base64-JSON exportieren.
EN: Export certificate metadata or exactly one PUBLIC DER certificate as Base64 JSON.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. Kein Dateiexport, keine PFX/privaten Schlüssel; Ausgabe nur in stdout/Feld.
EN: Windows SYSTEM, 64-bit. No disk export, no PFX/private keys; output only to stdout/field.
DE: StoreName (Standard: My); Thumbprint leer liefert nur Metadaten, sonst exakt 40 Hexzeichen.
EN: StoreName (default: My); empty Thumbprint returns metadata only, otherwise exactly 40 hex characters.
DE: MultiLine-CustomField: Klartext-JSON; über 4000 Zeichen Fehler nach Konsolenausgabe.
EN: MultiLine CustomField: plain-text JSON; over 4000 characters fails after console output.
DE: Exit 0 = Erfolg, 1 = Eingabe-, Abfrage- oder Schreibfehler.
EN: Exit 0 = success, 1 = input, query or write error.
.PARAMETER StoreName
DE: String; NinjaOne certificateExportStoreName; Standard My; My, Root, CA, TrustedPublisher oder TrustedPeople, nur LocalMachine.
EN: String; NinjaOne certificateExportStoreName; default My; My, Root, CA, TrustedPublisher or TrustedPeople, LocalMachine only.
.PARAMETER Thumbprint
DE: String; NinjaOne certificateExportThumbprint; Standard leer (Metadaten); sonst exakt 40 Hexzeichen für öffentlichen DER-Export als Base64.
EN: String; NinjaOne certificateExportThumbprint; default empty (metadata); otherwise exactly 40 hex characters for public DER export as Base64.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\exportCertificateStore.ps1 -StoreName My
DE: Gibt nur Metadaten aller Zertifikate in LocalMachine\My aus.
EN: Outputs metadata only for all certificates in LocalMachine\My.
.EXAMPLE
.\exportCertificateStore.ps1 -StoreName Root -Thumbprint 'CABD2A79A1076A31F21D253635CB039D4329A5E8' -CustomField certificateExport
DE: Exportiert genau dieses öffentliche Stammzertifikat (ISRG Root X1) als Base64-DER; JSON in certificateExport.
EN: Exports exactly this public root certificate (ISRG Root X1) as Base64 DER; JSON to certificateExport.
#>
[CmdletBinding()]
param(
    [string]$StoreName = $env:certificateExportStoreName,
    [string]$Thumbprint = $env:certificateExportThumbprint,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$store = $null
try {
    $StoreName = if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { '' } else { $StoreName.Trim() }
    $Thumbprint = if ([string]::IsNullOrWhiteSpace($Thumbprint) -or $Thumbprint.Trim() -eq 'null') { '' } else { $Thumbprint.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ($CustomField -and ($CustomField.Length -gt 128 -or $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]*$')) { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { $StoreName = 'My' }
    $StoreName = $StoreName.Trim()
    if ($StoreName -notin @('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople')) { throw 'Ungültiger StoreName / Invalid StoreName.' }
    $fingerprint = if ($null -eq $Thumbprint) { '' } else { $Thumbprint.Trim() }
    if ($fingerprint -eq 'null') { $fingerprint = '' }
    if ($fingerprint -and $fingerprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Thumbprint muss 40 Hexzeichen enthalten / Thumbprint must contain 40 hex characters.' }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
    $certificates = @($store.Certificates | Where-Object { -not $fingerprint -or $_.Thumbprint -eq $fingerprint } | Sort-Object Thumbprint)
    if ($fingerprint -and $certificates.Count -ne 1) { throw 'Zertifikat nicht eindeutig gefunden / Certificate not uniquely found.' }
    $items = @(foreach ($certificate in $certificates) {
        $item = [ordered]@{ Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject; Issuer = $certificate.Issuer; NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o') }
        if ($fingerprint) {
            # DE: Cert exportiert ausschließlich das öffentliche Zertifikat. EN: Cert exports only the public certificate.
            $item['PublicDerBase64'] = [Convert]::ToBase64String($certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        }
        [pscustomobject]$item
    })
    $store.Close()
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Store = "LocalMachine\$StoreName"; PublicOnly = $true; MetadataOnly = -not [bool]$fingerprint; Count = $items.Count; Certificates = $items } | ConvertTo-Json -Depth 5
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
    Write-Error ("Öffentlicher Export fehlgeschlagen / Public export failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
} finally {
    if ($store) { $store.Dispose() }
}