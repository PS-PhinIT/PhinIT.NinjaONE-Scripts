#Requires -Version 5.1
<#
.SYNOPSIS
DE: Abgelaufene, bald ablaufende und noch nicht gültige Zertifikate prüfen.
EN: Check expired, soon-expiring and not-yet-valid certificates.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. StoreName: My (Standard), Root, CA, TrustedPublisher, TrustedPeople.
EN: Windows SYSTEM, 64-bit. StoreName: My (default), Root, CA, TrustedPublisher, TrustedPeople.
DE: Nur LocalMachine, schreibgeschützt; keine privaten Schlüssel/Vertrauenskettensuche.
EN: LocalMachine only, read-only; no private keys/trust chain lookup.
DE: WarningDays: 0-3650 (Standard 30). MultiLine-CustomField: Klartext-JSON, max. 4000 Zeichen.
EN: WarningDays: 0-3650 (default 30). MultiLine CustomField: plain-text JSON, max. 4000 characters.
.PARAMETER StoreName
DE: String; NinjaOne certificateExpiryStoreName; Standard My; My, Root, CA, TrustedPublisher oder TrustedPeople, nur LocalMachine.
EN: String; NinjaOne certificateExpiryStoreName; default My; My, Root, CA, TrustedPublisher or TrustedPeople, LocalMachine only.
.PARAMETER WarningDays
DE: String; NinjaOne certificateExpiryWarningDays; Standard 30; ganze Zahl 0-3650.
EN: String; NinjaOne certificateExpiryWarningDays; default 30; integer 0-3650.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$StoreName = $env:certificateExpiryStoreName,
    [string]$WarningDays = $env:certificateExpiryWarningDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$store = $null
try {
    $StoreName = if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { '' } else { $StoreName.Trim() }
    $WarningDays = if ([string]::IsNullOrWhiteSpace($WarningDays) -or $WarningDays.Trim() -eq 'null') { '' } else { $WarningDays.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($StoreName) -or $StoreName.Trim() -eq 'null') { $StoreName = 'My' }
    $StoreName = $StoreName.Trim()
    if ($StoreName -notin @('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople')) { throw 'Ungültiger StoreName / Invalid StoreName.' }
    if ([string]::IsNullOrWhiteSpace($WarningDays) -or $WarningDays.Trim() -eq 'null') { $WarningDays = '30' }
    $days = 0
    if (-not [int]::TryParse($WarningDays.Trim(), [ref]$days) -or $days -lt 0 -or $days -gt 3650) { throw 'WarningDays: 0-3650 erforderlich / required.' }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
    $now = [DateTime]::UtcNow
    $limit = $now.AddDays($days)
    $total = $store.Certificates.Count
    $findings = @(foreach ($certificate in ($store.Certificates | Sort-Object Thumbprint)) {
        $expiry = $certificate.NotAfter.ToUniversalTime()
        $start = $certificate.NotBefore.ToUniversalTime()
        $reasons = @()
        if ($expiry -le $now) { $reasons += 'Expired' } elseif ($expiry -le $limit) { $reasons += 'ExpiringSoon' }
        if ($start -gt $now) { $reasons += 'NotYetValid' }
        if ($reasons.Count) {
            [pscustomobject]@{ Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject; NotBeforeUtc = $start.ToString('o'); NotAfterUtc = $expiry.ToString('o'); Reasons = $reasons }
        }
    })
    $store.Close()
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Store = "LocalMachine\$StoreName"; CheckedAtUtc = $now.ToString('o'); WarningDays = $days; CheckedCertificates = $total; FindingCount = $findings.Count; Findings = $findings } | ConvertTo-Json -Depth 6
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
    Write-Error ("Zertifikatsprüfung fehlgeschlagen / Certificate audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
} finally {
    if ($store) { $store.Dispose() }
}