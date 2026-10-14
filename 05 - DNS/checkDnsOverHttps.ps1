#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet DNS-over-HTTPS-Konfiguration und prüft optional, ob DoH verlangt wird.
    EN: Reports DNS-over-HTTPS configuration and optionally checks that DoH is required.
.DESCRIPTION
    DE: Liest bekannte DoH-Server (Get-DnsClientDohServerAddress, ab Windows 11 /
        Server 2022; fehlt das Cmdlet: Supported=false, kein Fehler), die Richtlinie
        DoHPolicy unter HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient
        (1 = Prohibit, 2 = Allow, 3 = Require) und die DNS-Server verbundener Adapter.
        Mit RequireDoh gilt DoH als erfüllt, wenn DoHPolicy = 3 ist oder jeder
        konfigurierte DNS-Server eine DoH-Vorlage ohne UDP-Fallback hat; DoHPolicy = 1
        ist nie erfüllt. Adapterbezogene DoH-Flags (Windows 11) werden nicht ausgewertet.
        Nur lesend, maximal 4000 Zeichen.
    EN: Reads known DoH servers (Get-DnsClientDohServerAddress, Windows 11 / Server 2022
        and later; if the cmdlet is missing: Supported=false, not an error), the DoHPolicy
        policy under HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient (1 = Prohibit,
        2 = Allow, 3 = Require) and the DNS servers of connected adapters. With RequireDoh,
        DoH is satisfied if DoHPolicy = 3 or every configured DNS server has a DoH template
        without UDP fallback; DoHPolicy = 1 is never satisfied. Per-interface DoH flags
        (Windows 11) are not evaluated. Read-only, at most 4000 characters.
.PARAMETER RequireDoh
    DE: NinjaOne Checkbox/Text dnsRequireDoh: true/false/1/0; Standard false (nur Bericht).
    EN: NinjaOne checkbox/text dnsRequireDoh: true/false/1/0; default false (report only).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkDnsOverHttps.ps1
    DE: Meldet DoH-Unterstützung, -Server und -Richtlinie (Exit 0).
    EN: Reports DoH support, servers and policy (exit 0).
.EXAMPLE
    .\checkDnsOverHttps.ps1 -RequireDoh true -CustomField dnsDohReport
    DE: Warnt (Exit 2), wenn DoH nicht verlangt bzw. nicht für alle Server aktiv ist.
    EN: Warns (exit 2) if DoH is not required or not active for all servers.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Bericht bzw. DoH erfüllt, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = dnsRequireDoh=true und DoH nicht erfüllt (auch NotSupported). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = report or DoH satisfied, 1 = input, query or write error,
        2 = dnsRequireDoh=true and DoH not satisfied (including NotSupported). Read-only.
#>
[CmdletBinding()]
param(
    [string]$RequireDoh = $env:dnsRequireDoh,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $RequireDoh = ([string]$RequireDoh).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequireDoh -ieq 'null') { $RequireDoh = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequireDoh) { $RequireDoh = 'false' }
    if ($RequireDoh -notin @('true', 'false', '1', '0')) { throw 'dnsRequireDoh: true/false/1/0.' }
    $required = $RequireDoh -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    foreach ($command in @('Get-NetAdapter', 'Get-DnsClientServerAddress')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $policyValue = $null
    if (Test-Path -LiteralPath $policyPath) {
        $raw = (Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop).DoHPolicy
        if ($null -ne $raw) { $policyValue = [int]$raw }
    }
    $policyText = 'NotConfigured'
    if ($policyValue -eq 1) { $policyText = 'Prohibit' }
    elseif ($policyValue -eq 2) { $policyText = 'Allow' }
    elseif ($policyValue -eq 3) { $policyText = 'Require' }
    elseif ($null -ne $policyValue) { $policyText = 'Unknown' }
    $supported = [bool](Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
    $dohServers = @()
    if ($supported) {
        $dohServers = @(Get-DnsClientDohServerAddress -ErrorAction Stop | ForEach-Object {
            $ip = $null
            $address = [string]$_.ServerAddress
            if ([System.Net.IPAddress]::TryParse($address, [ref]$ip)) { $address = $ip.ToString() }
            [pscustomobject]@{
                ServerAddress = $address; DohTemplate = [string]$_.DohTemplate
                AllowFallbackToUdp = [bool]$_.AllowFallbackToUdp; AutoUpgrade = [bool]$_.AutoUpgrade
            }
        })
    }
    $upIndexes = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [int]$_.InterfaceIndex })
    $configured = @(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $upIndexes -contains [int]$_.InterfaceIndex } |
        ForEach-Object { @($_.ServerAddresses) } |
        ForEach-Object { $ip = $null; if ([System.Net.IPAddress]::TryParse([string]$_, [ref]$ip)) { $ip.ToString() } } |
        Where-Object { $_ -notmatch '^fec0:0:0:ffff::[123]$' } | Sort-Object -Unique)
    $serverStates = @(foreach ($server in @($configured | Select-Object -First 20)) {
        $match = @($dohServers | Where-Object { $_.ServerAddress -eq $server -and $_.DohTemplate }) | Select-Object -First 1
        $state = 'NoTemplate'
        if ($match) { $state = 'DohWithFallback'; if (-not $match.AllowFallbackToUdp) { $state = 'DohOnly' } }
        [pscustomobject]@{ Server = $server; State = $state }
    })
    $allDohOnly = ($configured.Count -gt 0) -and (@($serverStates | Where-Object { $_.State -ne 'DohOnly' }).Count -eq 0) -and ($configured.Count -le 20)
    $status = 'NotSupported'
    if ($policyValue -eq 1) { $status = 'Prohibited' }
    elseif ($policyValue -eq 3) { $status = 'Required' }
    elseif ($supported -and $allDohOnly) { $status = 'DohOnlyAllServers' }
    elseif ($supported) { $status = 'NotEnforced' }
    $compliant = $status -in @('Required', 'DohOnlyAllServers')
    $report = [ordered]@{
        Supported = $supported; DoHPolicy = $policyValue; DoHPolicyText = $policyText; Status = $status
        RequireDoh = $required; Compliant = $compliant
        TotalDohServers = $dohServers.Count; DohServers = @($dohServers | Select-Object -First 15)
        TotalConfiguredServers = $configured.Count; ConfiguredServers = $serverStates
    } | ConvertTo-Json -Depth 4
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($required -and -not $compliant) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
