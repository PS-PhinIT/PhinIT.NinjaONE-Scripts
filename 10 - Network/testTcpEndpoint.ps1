#Requires -Version 5.1

<#
.SYNOPSIS
DE: Einen konfigurierten TCP-Endpunkt testen. EN: Test one configured TCP endpoint.
.DESCRIPTION
DE: Genau ein Host/Port, kein Scan. Verbindet und schliesst ohne Nutzdaten.
EN: Exactly one host/port, not a scan. Connects and closes without application data.
DE: SYSTEM, 64-Bit-PowerShell; SYSTEM-Netzwerkzugriff kann vom Benutzer abweichen.
EN: Use SYSTEM, 64-bit PowerShell; SYSTEM networking can differ from user networking.
DE: Parameter vor NinjaOne-Variablen targetHost, targetPort, connectionTimeoutMs,
resultFormat und resultCustomField. Host/Port erforderlich, Timeout leer = 5000 ms.
EN: Parameters override those variables. Host/port required; blank timeout = 5000 ms.
DE: Host nur DNS-Name/IP, keine URL/Zugangsdaten; Timeout 100..30000 ms.
EN: Host is DNS name/IP only, no URL/credentials; timeout 100..30000 ms.
DE/EN: Optional CustomField: NinjaOne MultiLine, resultFormat Json (default)/PlainText,
maximal/maximum 4000 Zeichen/characters; sonst Fehler / otherwise failure.
DE: DNS/Verbindung werden gemeinsam zeitlich begrenzt; keine TLS/Anwendungspruefung.
EN: DNS/connection share the timeout; no TLS/application health validation.
DE/EN: Exit 0 = verbunden/connected, 1 = Fehler/error, 2 = nicht erreichbar/unreachable.
.PARAMETER TargetHost
DE/EN: NinjaOne targetHost; erforderlich/required; leer/null = Fehler/error.
Ein DNS-Name oder IP / One DNS name or IP; DNS maximal/maximum 253 Zeichen/characters.
.PARAMETER TargetPort
DE/EN: NinjaOne targetPort; erforderlich/required; leer/null = Fehler/error; Bereich/range 1..65535.
.PARAMETER ConnectionTimeoutMs
DE/EN: NinjaOne connectionTimeoutMs; leer/null = 5000; Bereich/range 100..30000 ms.
.PARAMETER ResultFormat
DE/EN: NinjaOne resultFormat; leer/null = Json; Werte/values Json, PlainText.
.PARAMETER CustomField
DE/EN: -WhatIf testet weiterhin TCP / still tests TCP; kein Feldschreiben / skips field write.
DE/EN: NinjaOne resultCustomField; leer/null = kein Feld/no field.
NinjaOne MultiLine; Name/name [A-Za-z][A-Za-z0-9_]{0,99}; maximal/maximum 4000 Zeichen/characters.
.EXAMPLE
.\testTcpEndpoint.ps1 -TargetHost fileserver.contoso.local -TargetPort 445
DE: Testet SMB auf fileserver.contoso.local; Exit 2, wenn nicht erreichbar. EN: Tests SMB on fileserver.contoso.local; exit 2 if unreachable.
.EXAMPLE
.\testTcpEndpoint.ps1 -TargetHost 192.168.10.5 -TargetPort 443 -ConnectionTimeoutMs 2000 -CustomField tcpEndpointTest
DE: HTTPS-Port mit 2 s Timeout; JSON in tcpEndpointTest. EN: HTTPS port with 2 s timeout; JSON to tcpEndpointTest.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TargetHost = $env:targetHost,
    [string]$TargetPort = $env:targetPort,
    [string]$ConnectionTimeoutMs = $env:connectionTimeoutMs,
    [string]$ResultFormat = $env:resultFormat,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([object]$Report, [string]$Format, [string]$Field)
    if ($Format -eq 'Json') {
        $content = ConvertTo-Json -InputObject $Report -Depth 6 -Compress
    } else {
        $content = ($Report | Format-List | Out-String -Width 200).Trim()
    }
    # DE: Steuerzeichen entfernen. EN: Remove terminal control characters.
    $content = $content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows required / erforderlich.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $TargetHost = ([string]$TargetHost).Trim()
    $TargetPort = ([string]$TargetPort).Trim()
    $ConnectionTimeoutMs = ([string]$ConnectionTimeoutMs).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($TargetHost -ieq 'null') { $TargetHost = '' }
    if ($TargetPort -ieq 'null') { $TargetPort = '' }
    if ($ConnectionTimeoutMs -ieq 'null') { $ConnectionTimeoutMs = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $ConnectionTimeoutMs) { $ConnectionTimeoutMs = '5000' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $port = 0
    $timeout = 0
    $address = $null
    # DE: Nur vollständige IPv4-Punktnotation oder IPv6; Kurzformen wie "1234" oder "10.1" ablehnen.
    # EN: Only full dotted IPv4 or IPv6; reject shorthand such as "1234" or "10.1".
    $isIp = ($TargetHost -match '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$' -or $TargetHost -match ':') -and
        [System.Net.IPAddress]::TryParse($TargetHost, [ref]$address)
    $isDns = $TargetHost.Length -le 253 -and $TargetHost -notmatch '^[\d.]+$' -and $TargetHost -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$' -and [Uri]::CheckHostName($TargetHost) -eq 'Dns'
    if (-not $TargetHost -or (-not $isIp -and -not $isDns)) { throw 'targetHost must be a single DNS name or IP / Ein DNS-Name oder eine IP erforderlich.' }
    if (-not [int]::TryParse($TargetPort, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'targetPort must be 1..65535 / muss 1..65535 sein.' }
    if (-not [int]::TryParse($ConnectionTimeoutMs, [ref]$timeout) -or $timeout -lt 100 -or $timeout -gt 30000) { throw 'connectionTimeoutMs must be 100..30000 / muss 100..30000 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $client = $null
    $pending = $null
    $waitHandle = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $connected = $false
    $outcome = 'Unreachable / Nicht erreichbar'
    try {
        # DE: DNS braucht beide Familien, auch auf .NET Framework. EN: DNS needs both families, including .NET Framework.
        if ($isIp) {
            $client = New-Object System.Net.Sockets.TcpClient -ArgumentList $address.AddressFamily
        } elseif ([System.Net.Sockets.Socket]::OSSupportsIPv6) {
            $client = New-Object System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            $client.Client.DualMode = $true
        } else {
            $client = New-Object System.Net.Sockets.TcpClient -ArgumentList ([System.Net.Sockets.AddressFamily]::InterNetwork)
        }
        if ($isIp) {
            $pending = $client.BeginConnect($address, $port, $null, $null)
        } else {
            $pending = $client.BeginConnect($TargetHost, $port, $null, $null)
        }
        $waitHandle = $pending.AsyncWaitHandle
        $remainingMs = [math]::Max(0, $timeout - $timer.ElapsedMilliseconds)
        if ($waitHandle.WaitOne([int]$remainingMs, $false)) {
            $client.EndConnect($pending)
            $connected = $client.Connected
            if ($connected) { $outcome = 'Connected / Verbunden' }
        } else {
            $outcome = 'Timeout / Zeitlimit'
        }
    } catch [System.Net.Sockets.SocketException] {
        $outcome = 'DNS or connection failure / DNS- oder Verbindungsfehler'
    } finally {
        if ($null -ne $client) { $client.Close() }
        if ($null -ne $waitHandle) { $waitHandle.Close() }
        $timer.Stop()
    }
    $report = [pscustomobject]@{
        test = 'Single TCP endpoint / Einzelner TCP-Endpunkt'
        host = $TargetHost; port = $port; timeoutMs = $timeout
        elapsedMs = $timer.ElapsedMilliseconds; connected = $connected; outcome = $outcome
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    if (-not $connected) { exit 2 }
    exit 0
} catch {
    Write-Error 'TCP test or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / TCP-Test oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}
