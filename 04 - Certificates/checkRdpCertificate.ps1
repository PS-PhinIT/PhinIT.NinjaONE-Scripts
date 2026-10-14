#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft das Zertifikat des RDP-Listeners RDP-Tcp (Ablauf, selbst signiert).
EN: Checks the certificate of the RDP-Tcp listener (expiry, self-signed).
.DESCRIPTION
DE: Liest SSLCertificateSHA1Hash aus Win32_TSGeneralSetting (CIM root/cimv2/TerminalServices,
    TerminalName='RDP-Tcp') und sucht das Zertifikat in LocalMachine\Remote Desktop, danach in
    LocalMachine\My. Meldet Betreff, Aussteller, Gültigkeit, Resttage und SelfSigned
    (Aussteller-DN = Betreff-DN, Heuristik ohne Signaturprüfung). Nur lesend; keine privaten Schlüssel.
EN: Reads SSLCertificateSHA1Hash from Win32_TSGeneralSetting (CIM root/cimv2/TerminalServices,
    TerminalName='RDP-Tcp') and looks up the certificate in LocalMachine\Remote Desktop, then in
    LocalMachine\My. Reports subject, issuer, validity, remaining days and SelfSigned
    (issuer DN = subject DN, heuristic without signature verification). Read-only; no private keys.
DE: JSON-Bericht (komprimiert) auf stdout; optional in ein MultiLine-Feld (max. 4000 Zeichen).
EN: Compressed JSON report on stdout; optionally to a MultiLine field (max. 4000 characters).
.PARAMETER WarningDays
DE: NinjaOne Integer certRdpWarningDays; 0..3650; Standard 30. Ablauf innerhalb dieser Tage = Warnung.
EN: NinjaOne Integer certRdpWarningDays; 0..3650; default 30. Expiry within these days = warning.
.PARAMETER FailOnSelfSigned
DE: NinjaOne Checkbox/Text certRdpFailOnSelfSigned; true/false; Standard false. true = selbst signiert ergibt Exit 2.
EN: NinjaOne checkbox/text certRdpFailOnSelfSigned; true/false; default false. true = self-signed yields exit 2.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkRdpCertificate.ps1
DE: Prüft das RDP-Zertifikat mit 30 Tagen Vorlauf.
EN: Checks the RDP certificate with 30 days lead time.
.EXAMPLE
.\checkRdpCertificate.ps1 -WarningDays 14 -FailOnSelfSigned true -CustomField rdpCertificateReport
DE: 14 Tage Vorlauf, selbst signierte Zertifikate warnen; JSON in rdpCertificateReport.
EN: 14 days lead time, self-signed certificates warn; JSON to rdpCertificateReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen; leer/null = Standard.
    Exit 0 = OK, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = kein Zertifikat-Hash konfiguriert,
    Zertifikat in Remote Desktop/My nicht gefunden, abgelaufen, noch nicht gültig, läuft innerhalb
    WarningDays ab oder (mit FailOnSelfSigned=true) selbst signiert.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables; empty/null = default.
    Exit 0 = OK, 1 = input, query or write error, 2 = no certificate hash configured, certificate
    not found in Remote Desktop/My, expired, not yet valid, expiring within WarningDays or
    (with FailOnSelfSigned=true) self-signed.
#>
[CmdletBinding()]
param(
    [string]$WarningDays = $env:certRdpWarningDays,
    [string]$FailOnSelfSigned = $env:certRdpFailOnSelfSigned,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $WarningDays = ([string]$WarningDays).Trim()
    $FailOnSelfSigned = ([string]$FailOnSelfSigned).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $WarningDays -or $WarningDays -ieq 'null') { $WarningDays = '30' }
    if (-not $FailOnSelfSigned -or $FailOnSelfSigned -ieq 'null') { $FailOnSelfSigned = 'false' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $days = 0
    if ($WarningDays -notmatch '^\d{1,4}$' -or -not [int]::TryParse($WarningDays, [ref]$days) -or $days -gt 3650) {
        throw 'certRdpWarningDays: 0..3650 erforderlich / required.'
    }
    if ($FailOnSelfSigned -notin @('true', 'false')) { throw 'certRdpFailOnSelfSigned: true/false erforderlich / required.' }
    $failSelfSigned = $FailOnSelfSigned -ieq 'true'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $settings = @(Get-CimInstance -Namespace 'root/cimv2/TerminalServices' -ClassName Win32_TSGeneralSetting -Filter "TerminalName='RDP-Tcp'")
    if ($settings.Count -eq 0) { throw 'RDP-Tcp-Listener nicht gefunden / RDP-Tcp listener not found.' }
    $hash = (([string]$settings[0].SSLCertificateSHA1Hash) -replace '\s', '').ToUpperInvariant()
    $now = [DateTime]::UtcNow
    $findings = New-Object System.Collections.Generic.List[string]
    $certificate = $null
    $foundStore = $null
    if ($hash -notmatch '^[0-9A-F]{40}$' -or $hash -match '^0{40}$') {
        $findings.Add('NoCertificateHash')
    } else {
        foreach ($storeName in @('Remote Desktop', 'My')) {
            # DE: Fehlender Speicher (z. B. ohne RDS) ist kein Fehler. EN: A missing store (e.g. without RDS) is not an error.
            try { $items = @(Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction Stop) }
            catch [System.Management.Automation.ItemNotFoundException] { $items = @() }
            $match = @($items | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and $_.Thumbprint -eq $hash } | Select-Object -First 1)
            if ($match.Count -gt 0) { $certificate = $match[0]; $foundStore = $storeName; break }
        }
        if ($null -eq $certificate) { $findings.Add('CertificateNotFound') }
    }
    $details = $null
    if ($null -ne $certificate) {
        $notAfter = $certificate.NotAfter.ToUniversalTime()
        $notBefore = $certificate.NotBefore.ToUniversalTime()
        $remaining = [int][Math]::Floor(($notAfter - $now).TotalDays)
        $selfSigned = [Convert]::ToBase64String($certificate.SubjectName.RawData) -ceq [Convert]::ToBase64String($certificate.IssuerName.RawData)
        if ($notAfter -le $now) { $findings.Add('Expired') } elseif ($notAfter -le $now.AddDays($days)) { $findings.Add('ExpiringSoon') }
        if ($notBefore -gt $now) { $findings.Add('NotYetValid') }
        if ($selfSigned -and $failSelfSigned) { $findings.Add('SelfSigned') }
        $details = [ordered]@{
            Store = "LocalMachine\$foundStore"; Subject = $certificate.Subject; Issuer = $certificate.Issuer
            NotBeforeUtc = $notBefore.ToString('o'); NotAfterUtc = $notAfter.ToString('o')
            DaysRemaining = $remaining; SelfSigned = $selfSigned
        }
    }
    $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Listener = 'RDP-Tcp'; ConfiguredThumbprint = $hash
        WarningDays = $days; FailOnSelfSigned = $failSelfSigned; Found = $null -ne $certificate
        Certificate = $details; Findings = @($findings)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
