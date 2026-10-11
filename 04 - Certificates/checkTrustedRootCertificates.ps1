#Requires -Version 5.1
<#
.SYNOPSIS
DE: Maschinenvertrauensanker auf Gültigkeit und optional gegen eine Freigabeliste prüfen.
EN: Audit machine trust anchors for validity and optionally against an allow list.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit; LocalMachine\Root schreibgeschützt. Keine Zertifikate entfernen.
EN: Windows SYSTEM, 64-bit; LocalMachine\Root read-only. Never removes certificates.
DE: AllowedThumbprints leer: nur Gültigkeit; sonst vollständige semikolongetrennte Freigabeliste.
EN: Empty AllowedThumbprints: validity only; otherwise a complete semicolon-separated allow list.
DE: Freigabeliste wird vom Betreiber gepflegt, nicht als Microsoft-Vertrauensliste interpretiert.
EN: Allow list is operator maintained, not interpreted as Microsoft's trust list.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen. Befunde: Exit 2.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters. Findings: exit 2.
.PARAMETER AllowedThumbprints
DE: String; NinjaOne trustedRootAllowedThumbprints; Standard leer (nur Gültigkeit); 1-1000 semikolongetrennte Fingerabdrücke mit je 40 Hexzeichen, insgesamt maximal 41000 Zeichen.
EN: String; NinjaOne trustedRootAllowedThumbprints; default empty (validity only); 1-1000 semicolon-separated thumbprints of 40 hex characters each, maximum 41000 total characters.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$AllowedThumbprints = $env:trustedRootAllowedThumbprints,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$store = $null
try {
    $AllowedThumbprints = if ([string]::IsNullOrWhiteSpace($AllowedThumbprints) -or $AllowedThumbprints.Trim() -eq 'null') { '' } else { $AllowedThumbprints.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    $list = if ($null -eq $AllowedThumbprints) { '' } else { $AllowedThumbprints.Trim() }
    if ($list -eq 'null') { $list = '' }
    if ($list.Length -gt 41000) { throw 'Freigabeliste zu lang / Allow list too long.' }
    $allowed = @()
    if ($list) {
        $allowed = @($list.Split(';') | ForEach-Object { $_.Trim().ToUpperInvariant() })
        if ($allowed.Count -gt 1000 -or @($allowed | Where-Object { $_ -notmatch '^[A-F0-9]{40}$' }).Count) { throw 'Ungültige Thumbprint-Freigabeliste / Invalid thumbprint allow list.' }
        $allowed = @($allowed | Sort-Object -Unique)
    }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
    $now = [DateTime]::UtcNow
    $total = $store.Certificates.Count
    $findings = @(foreach ($certificate in ($store.Certificates | Sort-Object Thumbprint)) {
        $reasons = @()
        if ($certificate.NotAfter.ToUniversalTime() -le $now) { $reasons += 'Expired' }
        if ($certificate.NotBefore.ToUniversalTime() -gt $now) { $reasons += 'NotYetValid' }
        if ($allowed.Count -and $allowed -notcontains $certificate.Thumbprint) { $reasons += 'NotOnOperatorAllowList' }
        if ($reasons.Count) {
            [pscustomobject]@{ Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject; NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o'); Reasons = $reasons }
        }
    })
    $store.Close()
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Store = 'LocalMachine\Root'; AllowListEnabled = $allowed.Count -gt 0; AllowListCount = $allowed.Count; CheckedCertificates = $total; FindingCount = $findings.Count; Findings = $findings } | ConvertTo-Json -Depth 6
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
    if ($findings.Count) { exit 2 }
    exit 0
} catch {
    Write-Error ("Vertrauensankerprüfung fehlgeschlagen / Trust anchor audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
} finally {
    if ($store) { $store.Dispose() }
}
