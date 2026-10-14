#Requires -Version 5.1

<#
.SYNOPSIS
DE: ICMP-Erreichbarkeit von 1..10 Zielen pruefen. EN: Check ICMP reachability of 1..10 targets.
.DESCRIPTION
DE: Sendet je Ziel nacheinander N ICMP-Echos (System.Net.NetworkInformation.Ping) und meldet
Verlust in %, mittlere und maximale Antwortzeit. Kein Scan, keine Aenderungen am System.
EN: Sends N sequential ICMP echoes per target (System.Net.NetworkInformation.Ping) and reports
loss in %, average and maximum round-trip time. Not a scan, no system changes.
DE: Ziele nur DNS-Name oder IP (keine URL/Zugangsdaten), durch Komma/Semikolon/Leerzeichen getrennt.
EN: Targets are DNS names or IPs only (no URL/credentials), separated by comma/semicolon/space.
DE: Laufzeitbudget: Ziele x Echos x Timeout darf 120000 ms nicht ueberschreiten (sonst Exit 1).
EN: Runtime budget: targets x echoes x timeout must not exceed 120000 ms (otherwise exit 1).
DE: Firewalls blockieren ICMP haeufig; Verlust bedeutet nicht zwingend, dass der Dienst ausfaellt.
EN: Firewalls often block ICMP; loss does not necessarily mean the service is down.
DE: Optionales MultiLine-Feld (resultCustomField), maximal 4000 Zeichen; -WhatIf pingt, schreibt aber nicht.
EN: Optional MultiLine field (resultCustomField), max. 4000 characters; -WhatIf pings but skips the write.
.PARAMETER Targets
DE: NinjaOne networkPingTargets (Text); erforderlich; 1..10 DNS-Namen/IPs.
EN: NinjaOne networkPingTargets (text); required; 1..10 DNS names/IPs.
.PARAMETER EchoCount
DE: NinjaOne networkPingCount (Integer); Bereich 1..10; Standard 4.
EN: NinjaOne networkPingCount (integer); range 1..10; default 4.
.PARAMETER TimeoutMs
DE: NinjaOne networkPingTimeoutMs (Integer); Timeout je Echo 100..5000 ms; Standard 1000.
EN: NinjaOne networkPingTimeoutMs (integer); timeout per echo 100..5000 ms; default 1000.
.PARAMETER MaxLossPercent
DE: NinjaOne networkMaxLossPercent (Integer); Bereich 0..100; Standard 25. Verlust darueber = Exit 2.
EN: NinjaOne networkMaxLossPercent (integer); range 0..100; default 25. Loss above it = exit 2.
.PARAMETER MaxLatencyMs
DE: NinjaOne networkMaxLatencyMs (Integer); Bereich 1..10000; Standard 200. Mittelwert darueber = Exit 2.
EN: NinjaOne networkMaxLatencyMs (integer); range 1..10000; default 200. Average above it = exit 2.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\testPingTargets.ps1 -Targets '192.168.1.1,fileserver.contoso.local'
DE: Je 4 Echos an Gateway und Dateiserver; Exit 2 bei >25 % Verlust oder >200 ms Mittelwert.
EN: 4 echoes each to gateway and file server; exit 2 on >25% loss or >200 ms average.
.EXAMPLE
.\testPingTargets.ps1 -Targets 8.8.8.8 -EchoCount 10 -TimeoutMs 500 -MaxLossPercent 0 -MaxLatencyMs 50 -CustomField pingStatus
DE: Strenge Pruefung; JSON-Bericht in pingStatus. EN: Strict check; JSON report to pingStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = alle Ziele innerhalb der Grenzwerte, 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = mindestens ein Ziel ueber Verlust- oder Latenzgrenzwert (inkl. DNS-Fehler = 100 % Verlust).
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = all targets within thresholds, 1 = input/query/write error,
2 = at least one target above loss or latency threshold (DNS failure counts as 100% loss).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Targets = $env:networkPingTargets,
    [string]$EchoCount = $env:networkPingCount,
    [string]$TimeoutMs = $env:networkPingTimeoutMs,
    [string]$MaxLossPercent = $env:networkMaxLossPercent,
    [string]$MaxLatencyMs = $env:networkMaxLatencyMs,
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
    $Targets = ConvertTo-NetworkSetting $Targets
    $EchoCount = ConvertTo-NetworkSetting $EchoCount
    $TimeoutMs = ConvertTo-NetworkSetting $TimeoutMs
    $MaxLossPercent = ConvertTo-NetworkSetting $MaxLossPercent
    $MaxLatencyMs = ConvertTo-NetworkSetting $MaxLatencyMs
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $EchoCount) { $EchoCount = '4' }
    if (-not $TimeoutMs) { $TimeoutMs = '1000' }
    if (-not $MaxLossPercent) { $MaxLossPercent = '25' }
    if (-not $MaxLatencyMs) { $MaxLatencyMs = '200' }
    $count = 0; $timeout = 0; $maxLoss = 0; $maxLatency = 0
    if (-not [int]::TryParse($EchoCount, [ref]$count) -or $count -lt 1 -or $count -gt 10) { throw 'networkPingCount must be 1..10 / muss 1..10 sein.' }
    if (-not [int]::TryParse($TimeoutMs, [ref]$timeout) -or $timeout -lt 100 -or $timeout -gt 5000) { throw 'networkPingTimeoutMs must be 100..5000 / muss 100..5000 sein.' }
    if (-not [int]::TryParse($MaxLossPercent, [ref]$maxLoss) -or $maxLoss -lt 0 -or $maxLoss -gt 100) { throw 'networkMaxLossPercent must be 0..100 / muss 0..100 sein.' }
    if (-not [int]::TryParse($MaxLatencyMs, [ref]$maxLatency) -or $maxLatency -lt 1 -or $maxLatency -gt 10000) { throw 'networkMaxLatencyMs must be 1..10000 / muss 1..10000 sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not $Targets) { throw 'networkPingTargets required / erforderlich.' }
    $hosts = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($Targets -split '[,;\s]+')) {
        if (-not $item) { continue }
        if (-not (Test-NetworkHostName $item)) { throw 'Each target must be one DNS name or IP / Jedes Ziel muss ein DNS-Name oder eine IP sein.' }
        if (-not ($hosts | Where-Object { $_ -ieq $item })) { $hosts.Add($item) }
    }
    if ($hosts.Count -lt 1 -or $hosts.Count -gt 10) { throw 'networkPingTargets must contain 1..10 targets / 1..10 Ziele erforderlich.' }
    if ($hosts.Count * $count * $timeout -gt 120000) { throw 'Runtime budget exceeded (targets x echoes x timeout > 120000 ms) / Laufzeitbudget ueberschritten.' }
    $buffer = New-Object byte[] 32
    $alert = $false
    $records = @(foreach ($target in $hosts) {
        $received = 0
        $times = New-Object System.Collections.Generic.List[long]
        $lastFailure = $null
        $pinger = New-Object System.Net.NetworkInformation.Ping
        try {
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $reply = $pinger.Send($target, $timeout, $buffer)
                } catch {
                    # DE: DNS-/Ping-Ausnahme zaehlt als Totalverlust. EN: DNS/ping exception counts as total loss.
                    $lastFailure = 'DNS or ping failure / DNS- oder Ping-Fehler'
                    break
                }
                if ([string]$reply.Status -eq 'Success') {
                    $received++
                    $times.Add([long]$reply.RoundtripTime)
                } else {
                    $lastFailure = [string]$reply.Status
                }
            }
        } finally {
            $pinger.Dispose()
        }
        $loss = [math]::Round(100 * ($count - $received) / $count, 1)
        $avg = $null; $max = $null
        if ($times.Count -gt 0) {
            $stats = $times | Measure-Object -Average -Maximum
            $avg = [math]::Round($stats.Average, 1)
            $max = [long]$stats.Maximum
        }
        $targetAlert = ($loss -gt $maxLoss) -or ($null -ne $avg -and $avg -gt $maxLatency)
        if ($targetAlert) { $alert = $true }
        [pscustomobject]@{
            target = $target; sent = $count; received = $received; lossPercent = $loss
            avgMs = $avg; maxMs = $max; lastFailure = $lastFailure; alert = $targetAlert
        }
    })
    $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
        test = 'ICMP echo / ICMP-Echo'; echoCount = $count; timeoutMs = $timeout
        maxLossPercent = $maxLoss; maxLatencyMs = $maxLatency
        alertTargets = @($records | Where-Object { $_.alert }).Count; targets = $records
    })
    $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-NetworkReport -Content $report -Field $CustomField
    if ($alert) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
