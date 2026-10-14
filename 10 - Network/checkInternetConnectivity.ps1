#Requires -Version 5.1

<#
.SYNOPSIS
DE: Internetverbindung im NCSI-Stil pruefen. EN: Check internet connectivity NCSI-style.
.DESCRIPTION
DE: Loest einen Probe-Host per DNS auf (Resolve-DnsName -DnsOnly) und sendet einen HTTP-GET an eine
konfigurierbare URL (System.Net.HttpWebRequest, ohne Weiterleitungen). Gelesen werden hoechstens
4096 Bytes; der Inhalt wird nur mit dem erwarteten Text verglichen, nie ausgefuehrt oder ausgegeben.
EN: Resolves a probe host via DNS (Resolve-DnsName -DnsOnly) and sends an HTTP GET to a configurable URL
(System.Net.HttpWebRequest, no redirects). At most 4096 bytes are read; the content is only compared
with the expected text, never executed or printed.
DE: Nur http/https-URLs ohne Zugangsdaten. Eine Weiterleitung (3xx) deutet auf ein Captive Portal hin.
Es gilt der .NET-Standardproxy des SYSTEM-Kontexts.
EN: Only http/https URLs without credentials. A redirect (3xx) suggests a captive portal.
The .NET default proxy of the SYSTEM context applies.
DE: Optionales MultiLine-Feld (resultCustomField), maximal 4000 Zeichen; -WhatIf prueft, schreibt aber nicht.
EN: Optional MultiLine field (resultCustomField), max. 4000 characters; -WhatIf probes but skips the write.
.PARAMETER ProbeUrl
DE: NinjaOne networkProbeUrl (Text); Standard http://www.msftconnecttest.com/connecttest.txt; nur http/https, max. 2048 Zeichen.
EN: NinjaOne networkProbeUrl (text); default http://www.msftconnecttest.com/connecttest.txt; http/https only, max. 2048 chars.
.PARAMETER ExpectedContent
DE: NinjaOne networkProbeExpectedContent (Text); Standard "Microsoft Connect Test"; 1..200 Zeichen; exakter Vergleich nach Trim.
EN: NinjaOne networkProbeExpectedContent (text); default "Microsoft Connect Test"; 1..200 chars; exact match after trim.
.PARAMETER DnsProbeHost
DE: NinjaOne networkProbeDnsHost (Text); Standard = Host der URL (bei IP-URL keine DNS-Pruefung); DNS-Name, max. 253 Zeichen.
EN: NinjaOne networkProbeDnsHost (text); default = URL host (no DNS check for IP URLs); DNS name, max. 253 chars.
.PARAMETER TimeoutMs
DE: NinjaOne networkProbeTimeoutMs (Integer); HTTP-Timeout 1000..30000 ms; Standard 5000.
EN: NinjaOne networkProbeTimeoutMs (integer); HTTP timeout 1000..30000 ms; default 5000.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\checkInternetConnectivity.ps1
DE: Microsoft-NCSI-Pruefung; Exit 2 bei DNS-/HTTP-Fehler oder falschem Inhalt.
EN: Microsoft NCSI probe; exit 2 on DNS/HTTP failure or wrong content.
.EXAMPLE
.\checkInternetConnectivity.ps1 -ProbeUrl https://intranet.contoso.local/health.txt -ExpectedContent OK -TimeoutMs 3000 -CustomField internetProbe
DE: Eigene Health-URL; JSON in internetProbe. EN: Own health URL; JSON to internetProbe.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = DNS aufgeloest, HTTP 200 und Inhalt passend, 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = DNS-Fehler, HTTP nicht erreichbar/Timeout, Status ungleich 200 (z. B. Captive Portal) oder Inhalt abweichend.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = DNS resolved, HTTP 200 and content matches, 1 = input/query/write error,
2 = DNS failure, HTTP unreachable/timeout, status other than 200 (e.g. captive portal) or content mismatch.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ProbeUrl = $env:networkProbeUrl,
    [string]$ExpectedContent = $env:networkProbeExpectedContent,
    [string]$DnsProbeHost = $env:networkProbeDnsHost,
    [string]$TimeoutMs = $env:networkProbeTimeoutMs,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-NetworkSetting {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -ieq 'null') { return '' }
    return $text
}
function Write-NetworkReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Content, [string]$Field)
    Write-Output $Content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($Content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $Content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $ProbeUrl = ConvertTo-NetworkSetting $ProbeUrl
    $ExpectedContent = ConvertTo-NetworkSetting $ExpectedContent
    $DnsProbeHost = ConvertTo-NetworkSetting $DnsProbeHost
    $TimeoutMs = ConvertTo-NetworkSetting $TimeoutMs
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $ProbeUrl) { $ProbeUrl = 'http://www.msftconnecttest.com/connecttest.txt' }
    if (-not $ExpectedContent) { $ExpectedContent = 'Microsoft Connect Test' }
    if (-not $TimeoutMs) { $TimeoutMs = '5000' }
    $uri = $null
    $timeout = 0
    if ($ProbeUrl.Length -gt 2048 -or $ProbeUrl -match '[\s\x00-\x1F\x7F]' -or -not [Uri]::TryCreate($ProbeUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo -or [string]$uri.HostNameType -notin @('Dns', 'IPv4', 'IPv6')) {
        throw 'networkProbeUrl must be an http/https URL without credentials / http/https-URL ohne Zugangsdaten erforderlich.'
    }
    if ($ExpectedContent -notmatch '^[^\x00-\x1F\x7F]{1,200}$') { throw 'networkProbeExpectedContent must be 1..200 printable characters / 1..200 druckbare Zeichen.' }
    if (-not $DnsProbeHost -and [string]$uri.HostNameType -eq 'Dns') { $DnsProbeHost = $uri.DnsSafeHost }
    if ($DnsProbeHost -and ($DnsProbeHost.Length -gt 253 -or $DnsProbeHost -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$' -or $DnsProbeHost -match '^[\d.]+$')) { throw 'networkProbeDnsHost must be a DNS name / muss ein DNS-Name sein.' }
    if (-not [int]::TryParse($TimeoutMs, [ref]$timeout) -or $timeout -lt 1000 -or $timeout -gt 30000) { throw 'networkProbeTimeoutMs must be 1000..30000 / muss 1000..30000 sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $dnsResolved = $null
    $dnsAddresses = @()
    if ($DnsProbeHost) {
        if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { throw 'Resolve-DnsName unavailable / nicht verfuegbar.' }
        try {
            $dnsAddresses = @(Resolve-DnsName -Name $DnsProbeHost -DnsOnly -QuickTimeout -ErrorAction Stop |
                Where-Object { $_.IPAddress } | ForEach-Object { [string]$_.IPAddress } | Select-Object -Unique -First 10)
        } catch {
            $dnsAddresses = @()
        }
        $dnsResolved = $dnsAddresses.Count -gt 0
    }
    $statusCode = $null
    $httpFailure = $null
    $bytesRead = 0
    $contentMatches = $false
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $response = $null
    try {
        # DE: .NET Framework 4.x aktiviert TLS 1.2 nicht immer (nur dieser Prozess). EN: .NET Framework 4.x may lack TLS 1.2 (this process only).
        if ($uri.Scheme -eq 'https') { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($uri)
        $request.Method = 'GET'
        $request.Timeout = $timeout
        $request.ReadWriteTimeout = $timeout
        $request.AllowAutoRedirect = $false
        $request.KeepAlive = $false
        $request.UserAgent = 'NinjaOne-ConnectivityProbe/1.0'
        try {
            $response = $request.GetResponse()
        } catch {
            # DE: Auch HTTP-Fehlerstatus liefern eine Antwort. EN: HTTP error statuses still carry a response.
            $inner = $_.Exception
            while ($null -ne $inner -and -not ($inner -is [System.Net.WebException])) { $inner = $inner.InnerException }
            if ($null -eq $inner) { throw }
            $response = $inner.Response
            if ($null -eq $response) { $httpFailure = [string]$inner.Status }
        }
        if ($null -ne $response) {
            $statusCode = [int]$response.StatusCode
            $stream = $response.GetResponseStream()
            $buffer = New-Object byte[] 4096
            while ($bytesRead -lt $buffer.Length) {
                $read = $stream.Read($buffer, $bytesRead, $buffer.Length - $bytesRead)
                if ($read -le 0) { break }
                $bytesRead += $read
            }
            $body = [Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
            $contentMatches = $statusCode -eq 200 -and [string]::Equals($body.Trim(), $ExpectedContent, [StringComparison]::Ordinal)
        }
    } finally {
        if ($null -ne $response) { $response.Close() }
        $timer.Stop()
    }
    $result = 'Connected / Verbunden'
    if ($dnsResolved -eq $false) { $result = 'DNS failure / DNS-Fehler' }
    elseif ($httpFailure) { $result = 'HTTP unreachable / HTTP nicht erreichbar: ' + $httpFailure }
    elseif ($statusCode -ge 300 -and $statusCode -lt 400) { $result = 'Redirect, captive portal suspected / Weiterleitung, Captive Portal vermutet' }
    elseif ($statusCode -ne 200) { $result = 'Unexpected HTTP status / Unerwarteter HTTP-Status' }
    elseif (-not $contentMatches) { $result = 'Content mismatch / Inhalt abweichend' }
    $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
        test = 'Internet connectivity (NCSI-style) / Internetverbindung (NCSI-Stil)'
        probeUrl = $uri.AbsoluteUri; dnsProbeHost = $(if ($DnsProbeHost) { $DnsProbeHost } else { $null })
        dnsResolved = $dnsResolved; dnsAddresses = $dnsAddresses; httpStatus = $statusCode
        bytesRead = $bytesRead; contentMatches = $contentMatches; elapsedMs = $timer.ElapsedMilliseconds
        timeoutMs = $timeout; result = $result
    })
    $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-NetworkReport -Content $report -Field $CustomField
    if ($dnsResolved -eq $false -or -not $contentMatches) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
