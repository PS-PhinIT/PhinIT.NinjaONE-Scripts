#Requires -Version 5.1

<#
.SYNOPSIS
DE: Traceroute zu einem Ziel per ICMP und TTL. EN: Trace route to one target via ICMP and TTL.
.DESCRIPTION
DE: Eigene Implementierung mit System.Net.NetworkInformation.Ping und TTL 1..maxHops (je Hop ein Echo).
Meldet je Hop Adresse, Status und gemessene Zeit; kein Reverse-DNS, keine Aenderungen.
EN: Own implementation using System.Net.NetworkInformation.Ping with TTL 1..maxHops (one echo per hop).
Reports address, status and measured time per hop; no reverse DNS, no system changes.
DE: Ziel nur DNS-Name oder IP (keine URL). Router ohne ICMP-Antwort erscheinen als TimedOut.
EN: Target is a DNS name or IP only (no URL). Routers that do not answer ICMP appear as TimedOut.
DE: Abbruch bei Erreichen des Ziels oder bei Unreachable-Status. Maximale Laufzeit maxHops x Timeout.
EN: Stops when the target is reached or on an unreachable status. Max runtime maxHops x timeout.
DE: Optionales MultiLine-Feld (resultCustomField), maximal 4000 Zeichen; -WhatIf misst, schreibt aber nicht.
EN: Optional MultiLine field (resultCustomField), max. 4000 characters; -WhatIf traces but skips the write.
.PARAMETER Target
DE: NinjaOne networkTraceTarget (Text); erforderlich; ein DNS-Name oder eine IP.
EN: NinjaOne networkTraceTarget (text); required; one DNS name or IP.
.PARAMETER MaxHops
DE: NinjaOne networkTraceMaxHops (Integer); Bereich 1..30; Standard 20.
EN: NinjaOne networkTraceMaxHops (integer); range 1..30; default 20.
.PARAMETER TimeoutMs
DE: NinjaOne networkTraceTimeoutMs (Integer); Timeout je Hop 100..5000 ms; Standard 1000.
EN: NinjaOne networkTraceTimeoutMs (integer); timeout per hop 100..5000 ms; default 1000.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\testTraceRoute.ps1 -Target 8.8.8.8
DE: Bis zu 20 Hops mit 1 s Timeout; Exit 2, wenn das Ziel nicht erreicht wird.
EN: Up to 20 hops with 1 s timeout; exit 2 if the target is not reached.
.EXAMPLE
.\testTraceRoute.ps1 -Target vpn.contoso.com -MaxHops 30 -TimeoutMs 500 -CustomField traceRoute
DE: Bis zu 30 Hops; JSON-Bericht in traceRoute. EN: Up to 30 hops; JSON report to traceRoute.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = Ziel erreicht, 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = Ziel nicht erreicht (Timeout, Unreachable, DNS-Fehler oder maxHops ausgeschoepft).
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = target reached, 1 = input/query/write error,
2 = target not reached (timeout, unreachable, DNS failure or maxHops exhausted).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Target = $env:networkTraceTarget,
    [string]$MaxHops = $env:networkTraceMaxHops,
    [string]$TimeoutMs = $env:networkTraceTimeoutMs,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-NetworkSetting {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -ieq 'null') { return '' }
    return $text
}
function Test-NetworkHostName {
    param([string]$Name)
    $address = $null
    # DE: Nur vollstaendige IPv4-Punktnotation, IPv6 oder DNS-Name. EN: Only full dotted IPv4, IPv6 or DNS name.
    $isIp = ($Name -match '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$' -or $Name -match ':') -and
        [System.Net.IPAddress]::TryParse($Name, [ref]$address)
    $isDns = $Name.Length -le 253 -and $Name -notmatch '^[\d.]+$' -and $Name -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$' -and [Uri]::CheckHostName($Name) -eq 'Dns'
    return ($isIp -or $isDns)
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
    $Target = ConvertTo-NetworkSetting $Target
    $MaxHops = ConvertTo-NetworkSetting $MaxHops
    $TimeoutMs = ConvertTo-NetworkSetting $TimeoutMs
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $MaxHops) { $MaxHops = '20' }
    if (-not $TimeoutMs) { $TimeoutMs = '1000' }
    $hopLimit = 0; $timeout = 0
    if (-not $Target -or -not (Test-NetworkHostName $Target)) { throw 'networkTraceTarget must be one DNS name or IP / Ein DNS-Name oder eine IP erforderlich.' }
    if (-not [int]::TryParse($MaxHops, [ref]$hopLimit) -or $hopLimit -lt 1 -or $hopLimit -gt 30) { throw 'networkTraceMaxHops must be 1..30 / muss 1..30 sein.' }
    if (-not [int]::TryParse($TimeoutMs, [ref]$timeout) -or $timeout -lt 100 -or $timeout -gt 5000) { throw 'networkTraceTimeoutMs must be 100..5000 / muss 100..5000 sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $buffer = New-Object byte[] 32
    $hops = New-Object System.Collections.Generic.List[object]
    $reached = $false
    $stopReason = 'MaxHopsExhausted / maxHops ausgeschoepft'
    $pinger = New-Object System.Net.NetworkInformation.Ping
    try {
        for ($ttl = 1; $ttl -le $hopLimit; $ttl++) {
            $options = New-Object System.Net.NetworkInformation.PingOptions -ArgumentList $ttl, $true
            # DE: RoundtripTime ist bei TtlExpired 0; daher selbst messen. EN: RoundtripTime is 0 for TtlExpired; measure ourselves.
            $timer = [Diagnostics.Stopwatch]::StartNew()
            try {
                $reply = $pinger.Send($Target, $timeout, $buffer, $options)
            } catch {
                $stopReason = 'DNS or ping failure / DNS- oder Ping-Fehler'
                break
            }
            $timer.Stop()
            $status = [string]$reply.Status
            $answered = $status -in @('Success', 'TtlExpired', 'TimeExceeded')
            $address = $null
            $elapsed = $null
            if ($answered -and $null -ne $reply.Address) { $address = [string]$reply.Address }
            if ($answered) { $elapsed = [long]$timer.ElapsedMilliseconds }
            $hops.Add([pscustomobject]@{ hop = $ttl; address = $address; status = $status; ms = $elapsed })
            if ($status -eq 'Success') {
                $reached = $true
                $stopReason = 'Reached / Erreicht'
                break
            }
            if ($status -notin @('TtlExpired', 'TimeExceeded', 'TimedOut')) {
                $stopReason = 'Unreachable / Nicht erreichbar: ' + $status
                break
            }
        }
    } finally {
        $pinger.Dispose()
    }
    $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
        test = 'ICMP trace route / ICMP-Routenverfolgung'; target = $Target
        maxHops = $hopLimit; timeoutMs = $timeout; reached = $reached
        hopCount = $hops.Count; result = $stopReason; hops = $hops.ToArray()
    })
    $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-NetworkReport -Content $report -Field $CustomField
    if (-not $reached) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
