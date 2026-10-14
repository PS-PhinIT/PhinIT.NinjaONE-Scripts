#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft das TLS-Zertifikat genau eines entfernten Endpunkts (Host:Port).
EN: Checks the TLS certificate of exactly one remote endpoint (host:port).
.DESCRIPTION
DE: Verbindet per TCP (zeitlich begrenzt), führt nur den TLS-Handshake (SslStream, SNI = Host)
    aus und sendet keine Anwendungsdaten. Ein Validierungs-Callback erfasst Zertifikat,
    SslPolicyErrors und Kettenstatus. Gemeldet werden Betreff, Aussteller, Gültigkeit, Resttage,
    SAN (max. 20, Text laut Windows lokalisiert), Protokoll und Validierungsfehler. Kein Scan.
EN: Connects via TCP (time bounded), performs only the TLS handshake (SslStream, SNI = host)
    and never sends application data. A validation callback captures certificate,
    SslPolicyErrors and chain status. Reports subject, issuer, validity, remaining days,
    SAN (max. 20, text localized by Windows), protocol and validation errors. Not a scanner.
DE: Host nur DNS-Name oder vollständige IP, keine URL/Zugangsdaten. Timeout gilt für Verbindung und
    Handshake-Lesevorgänge. Protokolle TLS 1.0-1.2 (Windows PowerShell 5.1); reine TLS-1.3-Server
    können scheitern. Sperrprüfung ist deaktiviert. Ausführung als SYSTEM (Proxy wird nicht genutzt).
EN: Host is a DNS name or full IP only, no URL/credentials. Timeout covers connect and handshake
    reads. Protocols TLS 1.0-1.2 (Windows PowerShell 5.1); TLS 1.3-only servers may fail.
    Revocation checking is disabled. Runs as SYSTEM (no proxy is used).
.PARAMETER TargetHost
DE: NinjaOne Text certTlsTargetHost; erforderlich; DNS-Name (max. 253 Zeichen) oder IPv4/IPv6.
EN: NinjaOne text certTlsTargetHost; required; DNS name (max. 253 characters) or IPv4/IPv6.
.PARAMETER TargetPort
DE: NinjaOne Integer certTlsTargetPort; 1..65535; Standard 443.
EN: NinjaOne Integer certTlsTargetPort; 1..65535; default 443.
.PARAMETER TimeoutMs
DE: NinjaOne Integer certTlsTimeoutMs; 1000..30000; Standard 10000.
EN: NinjaOne Integer certTlsTimeoutMs; 1000..30000; default 10000.
.PARAMETER WarningDays
DE: NinjaOne Integer certTlsWarningDays; 0..3650; Standard 30.
EN: NinjaOne Integer certTlsWarningDays; 0..3650; default 30.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkRemoteTlsCertificate.ps1 -TargetHost intranet.contoso.local
DE: Prüft das Zertifikat auf Port 443 mit 30 Tagen Vorlauf.
EN: Checks the certificate on port 443 with 30 days lead time.
.EXAMPLE
.\checkRemoteTlsCertificate.ps1 -TargetHost 10.0.0.5 -TargetPort 8443 -TimeoutMs 5000 -WarningDays 14 -CustomField tlsEndpointReport
DE: Port 8443, 5 s Timeout, 14 Tage Vorlauf; JSON in tlsEndpointReport.
EN: Port 8443, 5 s timeout, 14 days lead time; JSON to tlsEndpointReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = gültig, 1 = Eingabe- oder Schreibfehler,
    2 = nicht erreichbar, Handshake fehlgeschlagen, abgelaufen/noch nicht gültig, läuft innerhalb
    WarningDays ab oder Validierungsfehler (Name, Kette, nicht verfügbar).
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = valid, 1 = input or write error,
    2 = unreachable, handshake failed, expired/not yet valid, expiring within WarningDays or
    validation errors (name, chain, not available).
#>
[CmdletBinding()]
param(
    [string]$TargetHost = $env:certTlsTargetHost,
    [string]$TargetPort = $env:certTlsTargetPort,
    [string]$TimeoutMs = $env:certTlsTimeoutMs,
    [string]$WarningDays = $env:certTlsWarningDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $TargetHost = ([string]$TargetHost).Trim()
    $TargetPort = ([string]$TargetPort).Trim()
    $TimeoutMs = ([string]$TimeoutMs).Trim()
    $WarningDays = ([string]$WarningDays).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($TargetHost -ieq 'null') { $TargetHost = '' }
    if (-not $TargetPort -or $TargetPort -ieq 'null') { $TargetPort = '443' }
    if (-not $TimeoutMs -or $TimeoutMs -ieq 'null') { $TimeoutMs = '10000' }
    if (-not $WarningDays -or $WarningDays -ieq 'null') { $WarningDays = '30' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $port = 0
    $timeout = 0
    $days = 0
    $address = $null
    # DE: Nur vollständige IPv4-Punktnotation oder IPv6. EN: Only full dotted IPv4 or IPv6.
    $isIp = ($TargetHost -match '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$' -or $TargetHost -match ':') -and
        [System.Net.IPAddress]::TryParse($TargetHost, [ref]$address)
    $isDns = $TargetHost.Length -le 253 -and $TargetHost -notmatch '^[\d.]+$' -and $TargetHost -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$' -and [Uri]::CheckHostName($TargetHost) -eq 'Dns'
    if (-not $TargetHost -or (-not $isIp -and -not $isDns)) { throw 'certTlsTargetHost: ein DNS-Name oder eine IP erforderlich / single DNS name or IP required.' }
    if ($TargetPort -notmatch '^\d{1,5}$' -or -not [int]::TryParse($TargetPort, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'certTlsTargetPort: 1..65535 erforderlich / required.' }
    if ($TimeoutMs -notmatch '^\d{4,5}$' -or -not [int]::TryParse($TimeoutMs, [ref]$timeout) -or $timeout -lt 1000 -or $timeout -gt 30000) { throw 'certTlsTimeoutMs: 1000..30000 erforderlich / required.' }
    if ($WarningDays -notmatch '^\d{1,4}$' -or -not [int]::TryParse($WarningDays, [ref]$days) -or $days -gt 3650) { throw 'certTlsWarningDays: 0..3650 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $captured = @{ Certificate = $null; PolicyErrors = $null; ChainStatus = @() }
    # DE: Callback erfasst nur und akzeptiert; danach wird ohne Nutzdaten geschlossen.
    # EN: Callback only captures and accepts; the connection is closed without payload afterwards.
    $callback = [System.Net.Security.RemoteCertificateValidationCallback] {
        if ($null -ne $args[1]) { $captured.Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $args[1] }
        $captured.PolicyErrors = [string]$args[3]
        if ($null -ne $args[2]) { $captured.ChainStatus = @($args[2].ChainStatus | ForEach-Object { [string]$_.Status } | Sort-Object -Unique | Select-Object -First 10) }
        $true
    }
    $client = $null
    $ssl = $null
    $waitHandle = $null
    $stage = 'Connect'
    $outcome = 'ConnectFailed'
    $protocol = $null
    $errorText = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($isIp) {
            $client = New-Object System.Net.Sockets.TcpClient -ArgumentList $address.AddressFamily
            $pending = $client.BeginConnect($address, $port, $null, $null)
        } else {
            if ([System.Net.Sockets.Socket]::OSSupportsIPv6) {
                $client = New-Object System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetworkV6)
                $client.Client.DualMode = $true
            } else {
                $client = New-Object System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetwork)
            }
            $pending = $client.BeginConnect($TargetHost, $port, $null, $null)
        }
        $waitHandle = $pending.AsyncWaitHandle
        if (-not $waitHandle.WaitOne($timeout, $false)) {
            $outcome = 'ConnectTimeout'
        } else {
            $client.EndConnect($pending)
            $stage = 'Handshake'
            $remainingMs = [int][Math]::Max(500, $timeout - $timer.ElapsedMilliseconds)
            $client.ReceiveTimeout = $remainingMs
            $client.SendTimeout = $remainingMs
            $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false, $callback)
            $protocols = [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls11 -bor [System.Security.Authentication.SslProtocols]::Tls
            $ssl.AuthenticateAsClient($TargetHost, $null, $protocols, $false)
            $outcome = 'HandshakeCompleted'
            $protocol = [string]$ssl.SslProtocol
        }
    } catch {
        $outcome = "${stage}Failed"
        $errorText = [string]$_.Exception.GetBaseException().Message
        if ($errorText.Length -gt 300) { $errorText = $errorText.Substring(0, 300) }
    } finally {
        if ($null -ne $ssl) { $ssl.Dispose() }
        if ($null -ne $client) { $client.Close() }
        if ($null -ne $waitHandle) { $waitHandle.Close() }
        $timer.Stop()
    }

    $findings = New-Object System.Collections.Generic.List[string]
    if ($outcome -ne 'HandshakeCompleted') { $findings.Add($outcome) }
    $certificate = $captured.Certificate
    $details = $null
    $san = @()
    if ($null -ne $certificate) {
        $now = [DateTime]::UtcNow
        $notAfter = $certificate.NotAfter.ToUniversalTime()
        $notBefore = $certificate.NotBefore.ToUniversalTime()
        if ($notAfter -le $now) { $findings.Add('Expired') } elseif ($notAfter -le $now.AddDays($days)) { $findings.Add('ExpiringSoon') }
        if ($notBefore -gt $now) { $findings.Add('NotYetValid') }
        $sanExtension = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | Select-Object -First 1)
        if ($sanExtension.Count -gt 0) { $san = @(($sanExtension[0].Format($false) -split ',\s*') | Where-Object { $_ } | Select-Object -First 20) }
        $details = [ordered]@{
            Subject = $certificate.Subject; Issuer = $certificate.Issuer; Thumbprint = $certificate.Thumbprint
            NotBeforeUtc = $notBefore.ToString('o'); NotAfterUtc = $notAfter.ToString('o')
            DaysRemaining = [int][Math]::Floor(($notAfter - $now).TotalDays)
        }
    } elseif ($outcome -eq 'HandshakeCompleted') { $findings.Add('NoCertificate') }
    if ($captured.PolicyErrors -and $captured.PolicyErrors -ne 'None') { $findings.Add("PolicyErrors: $($captured.PolicyErrors)") }
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Host = $TargetHost; Port = $port; TimeoutMs = $timeout
            ElapsedMs = $timer.ElapsedMilliseconds; Outcome = $outcome; Protocol = $protocol; Error = $errorText
            WarningDays = $days; Certificate = $details; SubjectAlternativeNames = $san
            PolicyErrors = $captured.PolicyErrors; ChainStatus = @($captured.ChainStatus); Findings = @($findings)
        })
        if ($report.Length -le 4000) { break }
        if ($san.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $san = @($san | Select-Object -First ($san.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
