#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Antwort und Latenz jedes DNS-Servers mit einem Testnamen.
    EN: Tests response and latency of each DNS server with a test name.
.DESCRIPTION
    DE: Fragt jeden konfigurierten IPv4/IPv6-DNS-Server verbundener Adapter
        (Get-NetAdapter Status Up, Get-DnsClientServerAddress) oder eine explizite
        Serverliste einzeln mit Resolve-DnsName -Server -DnsOnly -NoHostsFile
        -QuickTimeout nach dem A-Eintrag des Testnamens ab und misst die Latenz.
        Windows-Platzhalter fec0:0:0:ffff::1..3 werden ignoriert; maximal 10 Server.
        Nur lesend, keine Konfigurationsänderung, maximal 4000 Zeichen.
    EN: Queries each configured IPv4/IPv6 DNS server of connected adapters
        (Get-NetAdapter status Up, Get-DnsClientServerAddress) or an explicit
        server list individually with Resolve-DnsName -Server -DnsOnly -NoHostsFile
        -QuickTimeout for the A record of the test name and measures latency.
        Windows placeholders fec0:0:0:ffff::1..3 are ignored; at most 10 servers.
        Read-only, no configuration change, at most 4000 characters.
.PARAMETER TestName
    DE: NinjaOne Text dnsTestName: DNS-Name ohne Wildcards; Standard www.microsoft.com.
    EN: NinjaOne Text dnsTestName: DNS name without wildcards; default www.microsoft.com.
.PARAMETER Servers
    DE: NinjaOne Text dnsTestServers: kommagetrennte IP-Adressen (1..10); leer = konfigurierte Server.
    EN: NinjaOne Text dnsTestServers: comma-separated IP addresses (1..10); empty = configured servers.
.PARAMETER LatencyThresholdMs
    DE: NinjaOne Integer dnsLatencyThresholdMs, 1..10000 ms; Standard 500.
    EN: NinjaOne Integer dnsLatencyThresholdMs, 1..10000 ms; default 500.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\testDnsServerResponse.ps1
    DE: Prüft alle konfigurierten DNS-Server mit www.microsoft.com (Grenzwert 500 ms).
    EN: Tests all configured DNS servers with www.microsoft.com (threshold 500 ms).
.EXAMPLE
    .\testDnsServerResponse.ps1 -TestName contoso.com -Servers '10.0.0.10,10.0.0.11' -LatencyThresholdMs 200 -CustomField dnsServerHealth
    DE: Prüft zwei explizite Server mit 200 ms Grenzwert; JSON in dnsServerHealth.
    EN: Tests two explicit servers with a 200 ms threshold; JSON to dnsServerHealth.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = alle Server antworten innerhalb des Grenzwerts, 1 = Eingabe-, Abfrage-
        oder Schreibfehler, 2 = mindestens ein Server ohne Antwort/A-Eintrag, langsamer
        als der Grenzwert oder kein DNS-Server konfiguriert. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = all servers answer within the threshold, 1 = input, query or write
        error, 2 = at least one server without answer/A record, slower than the
        threshold, or no DNS server configured. Read-only.
#>
[CmdletBinding()]
param(
    [string]$TestName = $env:dnsTestName,
    [string]$Servers = $env:dnsTestServers,
    [string]$LatencyThresholdMs = $env:dnsLatencyThresholdMs,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $TestName = ([string]$TestName).Trim()
    $Servers = ([string]$Servers).Trim()
    $LatencyThresholdMs = ([string]$LatencyThresholdMs).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($TestName -ieq 'null') { $TestName = '' }
    if ($Servers -ieq 'null') { $Servers = '' }
    if ($LatencyThresholdMs -ieq 'null') { $LatencyThresholdMs = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $TestName) { $TestName = 'www.microsoft.com' }
    if (-not $LatencyThresholdMs) { $LatencyThresholdMs = '500' }
    $threshold = 0
    if (-not [int]::TryParse($LatencyThresholdMs, [ref]$threshold) -or $threshold -lt 1 -or $threshold -gt 10000) {
        throw 'dnsLatencyThresholdMs muss 1..10000 sein / must be 1..10000.'
    }
    # DE: Keine Wildcards, URLs oder Optionszeichen; DNS-Labels einzeln prüfen.
    # EN: Reject wildcards, URLs and option characters; validate individual DNS labels.
    if ($TestName.Length -gt 253 -or $TestName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.?$') {
        throw 'Ungültiger dnsTestName / Invalid dnsTestName.'
    }
    foreach ($label in $TestName.TrimEnd('.').Split('.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { throw 'Ungültiges DNS-Label / Invalid DNS label.' }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    $serverList = New-Object System.Collections.Generic.List[string]
    if ($Servers) {
        foreach ($entry in $Servers.Split(',')) {
            $candidate = $entry.Trim()
            $address = $null
            if (-not $candidate -or $candidate.Contains('%') -or -not [System.Net.IPAddress]::TryParse($candidate, [ref]$address)) {
                throw 'dnsTestServers: nur IP-Adressen / only IP addresses.'
            }
            if (-not $serverList.Contains($address.ToString())) { $serverList.Add($address.ToString()) }
        }
        if ($serverList.Count -gt 10) { throw 'dnsTestServers: maximal 10 / at most 10.' }
    }
    $requiredCommands = @('Resolve-DnsName')
    if (-not $Servers) { $requiredCommands += @('Get-NetAdapter', 'Get-DnsClientServerAddress') }
    foreach ($command in $requiredCommands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $source = 'Explicit'
    $serversTruncated = $false
    if (-not $Servers) {
        $source = 'Configured'
        $upIndexes = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [int]$_.InterfaceIndex })
        $entries = @(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $upIndexes -contains [int]$_.InterfaceIndex })
        foreach ($entry in $entries) {
            foreach ($value in @($entry.ServerAddresses)) {
                $address = $null
                if (-not [System.Net.IPAddress]::TryParse([string]$value, [ref]$address)) { continue }
                $text = $address.ToString()
                # DE: Windows-Standardplatzhalter ohne echten Server überspringen.
                # EN: Skip Windows default placeholders that are not real servers.
                if ($text -match '^fec0:0:0:ffff::[123]$' -or $serverList.Contains($text)) { continue }
                if ($serverList.Count -ge 10) { $serversTruncated = $true; continue }
                $serverList.Add($text)
            }
        }
    }
    $results = @(foreach ($server in $serverList) {
        $status = 'OK'
        $answers = 0
        $message = ''
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $answers = @(Resolve-DnsName -Name $TestName -Type A -Server $server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                Where-Object { [string]$_.Type -eq 'A' }).Count
            if ($answers -eq 0) { $status = 'NoAnswer' }
        }
        catch {
            $status = 'Failed'
            $message = [string]$_.Exception.Message
            if ($message.Length -gt 150) { $message = $message.Substring(0, 150) }
        }
        $watch.Stop()
        $latency = [int]$watch.ElapsedMilliseconds
        if ($status -eq 'OK' -and $latency -gt $threshold) { $status = 'Slow' }
        [pscustomobject]@{ Server = $server; Status = $status; LatencyMs = $latency; Answers = $answers; Error = $message }
    })
    $failed = @($results | Where-Object { $_.Status -in @('Failed', 'NoAnswer') }).Count
    $slow = @($results | Where-Object { $_.Status -eq 'Slow' }).Count
    $report = [ordered]@{
        TestName = $TestName; Source = $source; LatencyThresholdMs = $threshold
        TotalServers = $results.Count; ServersTruncated = $serversTruncated
        FailedServers = $failed; SlowServers = $slow; Results = $results
    } | ConvertTo-Json -Depth 4
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($results.Count -eq 0 -or $failed -gt 0 -or $slow -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
