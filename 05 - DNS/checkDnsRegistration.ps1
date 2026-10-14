#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob der eigene DNS-Eintrag (A/AAAA) zu den lokalen IP-Adressen passt.
    EN: Checks whether the own DNS record (A/AAAA) matches the local IP addresses.
.DESCRIPTION
    DE: Bildet den FQDN aus DNS-Hostname und primärem Suffix (HKLM\SYSTEM\
        CurrentControlSet\Services\Tcpip\Parameters Hostname/Domain) oder nutzt einen
        expliziten Namen, löst A und AAAA mit Resolve-DnsName -DnsOnly -NoHostsFile
        -QuickTimeout über die konfigurierten (oder einen expliziten) DNS-Server auf und
        vergleicht mit bevorzugten Unicast-Adressen verbundener Adapter (Get-NetAdapter
        Status Up, Get-NetIPAddress; ohne Loopback, APIPA 169.254/16, fe80::/10).
        DNS-Adressen, die lokal nicht vorhanden sind, gelten als veraltet. Ohne primäres
        Suffix und ohne expliziten Namen: Status NotApplicable. Nur lesend.
    EN: Builds the FQDN from DNS host name and primary suffix (HKLM\SYSTEM\
        CurrentControlSet\Services\Tcpip\Parameters Hostname/Domain) or uses an explicit
        name, resolves A and AAAA with Resolve-DnsName -DnsOnly -NoHostsFile -QuickTimeout
        via the configured (or an explicit) DNS server and compares with preferred
        unicast addresses of connected adapters (Get-NetAdapter status Up,
        Get-NetIPAddress; excluding loopback, APIPA 169.254/16, fe80::/10). DNS addresses
        not present locally count as stale. Without primary suffix and explicit name:
        status NotApplicable. Read-only.
.PARAMETER Fqdn
    DE: NinjaOne Text dnsRegistrationFqdn: zu prüfender FQDN; leer = Hostname + primäres Suffix.
    EN: NinjaOne Text dnsRegistrationFqdn: FQDN to check; empty = host name + primary suffix.
.PARAMETER Server
    DE: NinjaOne Text dnsRegistrationServer: optionale DNS-Server-IP; leer = konfigurierte Server.
    EN: NinjaOne Text dnsRegistrationServer: optional DNS server IP; empty = configured servers.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkDnsRegistration.ps1
    DE: Prüft den eigenen FQDN über die konfigurierten DNS-Server.
    EN: Checks the own FQDN via the configured DNS servers.
.EXAMPLE
    .\checkDnsRegistration.ps1 -Fqdn pc01.corp.contoso.com -Server 10.0.0.10 -CustomField dnsRegistrationReport
    DE: Prüft pc01.corp.contoso.com direkt bei 10.0.0.10; JSON in dnsRegistrationReport.
    EN: Checks pc01.corp.contoso.com directly at 10.0.0.10; JSON to dnsRegistrationReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Eintrag passt oder NotApplicable, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = kein Eintrag (NotRegistered), keine Übereinstimmung (NoMatch)
        oder veraltete Adresse im DNS (Stale). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = record matches or NotApplicable, 1 = input, query or write error,
        2 = no record (NotRegistered), no match (NoMatch) or stale address in DNS
        (Stale). Read-only.
#>
[CmdletBinding()]
param(
    [string]$Fqdn = $env:dnsRegistrationFqdn,
    [string]$Server = $env:dnsRegistrationServer,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $Fqdn = ([string]$Fqdn).Trim().TrimEnd('.')
    $Server = ([string]$Server).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($Fqdn -ieq 'null') { $Fqdn = '' }
    if ($Server -ieq 'null') { $Server = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($Server) {
        $parsed = $null
        if ($Server.Contains('%') -or -not [System.Net.IPAddress]::TryParse($Server, [ref]$parsed)) {
            throw 'dnsRegistrationServer muss eine IP-Adresse sein / must be an IP address.'
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    $source = 'Explicit'
    if (-not $Fqdn) {
        $source = 'HostnameAndPrimarySuffix'
        $tcpip = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction Stop
        $hostLabel = ([string]$tcpip.Hostname).Trim()
        if (-not $hostLabel) { $hostLabel = ([string]$env:COMPUTERNAME).Trim() }
        $suffix = ([string]$tcpip.Domain).Trim().TrimEnd('.')
        if ($suffix) { $Fqdn = '{0}.{1}' -f $hostLabel, $suffix }
    }
    if ($Fqdn) {
        if ($Fqdn.Length -gt 253 -or $Fqdn -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') {
            throw 'Ungültiger FQDN / Invalid FQDN.'
        }
        foreach ($label in $Fqdn.Split('.')) {
            if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { throw 'Ungültiges DNS-Label / Invalid DNS label.' }
        }
    }
    foreach ($command in @('Resolve-DnsName', 'Get-NetAdapter', 'Get-NetIPAddress')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $status = 'NotApplicable'
    $dnsAddresses = @(); $localAddresses = @(); $matched = @(); $stale = @(); $queryErrors = @()
    if ($Fqdn) {
        $upIndexes = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [int]$_.InterfaceIndex })
        $localAddresses = @(Get-NetIPAddress -ErrorAction Stop |
            Where-Object { $upIndexes -contains [int]$_.InterfaceIndex -and [string]$_.AddressState -eq 'Preferred' } |
            ForEach-Object { ([string]$_.IPAddress).Split('%')[0] } |
            Where-Object { $_ -notmatch '^(127\.|169\.254\.|::1$|fe[89ab][0-9a-f]:)' } |
            ForEach-Object { $ip = $null; if ([System.Net.IPAddress]::TryParse($_, [ref]$ip)) { $ip.ToString() } } |
            Sort-Object -Unique)
        $resolved = New-Object System.Collections.Generic.List[string]
        foreach ($type in @('A', 'AAAA')) {
            $arguments = @{ Name = $Fqdn; Type = $type; DnsOnly = $true; NoHostsFile = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
            if ($Server) { $arguments.Server = $Server }
            try {
                foreach ($record in @(Resolve-DnsName @arguments | Where-Object { [string]$_.Type -eq $type -and [string]$_.Section -eq 'Answer' })) {
                    $ip = $null
                    if ([System.Net.IPAddress]::TryParse([string]$record.IPAddress, [ref]$ip) -and -not $resolved.Contains($ip.ToString())) { $resolved.Add($ip.ToString()) }
                }
            }
            catch {
                $text = [string]$_.Exception.Message
                if ($text.Length -gt 150) { $text = $text.Substring(0, 150) }
                $queryErrors += ('{0}: {1}' -f $type, $text)
            }
        }
        $dnsAddresses = @($resolved | Sort-Object)
        $matched = @($dnsAddresses | Where-Object { $localAddresses -contains $_ })
        $stale = @($dnsAddresses | Where-Object { $localAddresses -notcontains $_ })
        if ($dnsAddresses.Count -eq 0) { $status = 'NotRegistered' }
        elseif ($matched.Count -eq 0) { $status = 'NoMatch' }
        elseif ($stale.Count -gt 0) { $status = 'Stale' }
        else { $status = 'OK' }
    }
    $report = [ordered]@{
        Fqdn = $Fqdn; FqdnSource = $source; Server = $Server; Status = $status
        DnsAddresses = @($dnsAddresses | Select-Object -First 20); LocalAddresses = @($localAddresses | Select-Object -First 20)
        MatchedAddresses = @($matched | Select-Object -First 20); StaleAddresses = @($stale | Select-Object -First 20)
        TotalDnsAddresses = $dnsAddresses.Count; TotalLocalAddresses = $localAddresses.Count; QueryErrors = $queryErrors
    } | ConvertTo-Json -Depth 4
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($status -in @('NotRegistered', 'NoMatch', 'Stale')) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
