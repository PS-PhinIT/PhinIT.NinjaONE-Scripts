#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft PTR-Einträge der lokalen IPv4-Adressen gegen Hostname/FQDN.
    EN: Checks PTR records of local IPv4 addresses against host name/FQDN.
.DESCRIPTION
    DE: Ermittelt bevorzugte IPv4-Adressen verbundener Adapter (Get-NetAdapter Status
        Up, Get-NetIPAddress; ohne Loopback und APIPA 169.254/16, maximal 20), fragt je
        Adresse den PTR-Eintrag per Resolve-DnsName -Type PTR -DnsOnly -NoHostsFile
        -QuickTimeout ab und vergleicht ohne Groß-/Kleinschreibung mit dem erwarteten
        Namen (Hostname + primäres Suffix aus HKLM\SYSTEM\CurrentControlSet\Services\
        Tcpip\Parameters, ohne Suffix nur das erste Label). Nur lesend.
    EN: Collects preferred IPv4 addresses of connected adapters (Get-NetAdapter status
        Up, Get-NetIPAddress; excluding loopback and APIPA 169.254/16, at most 20),
        queries each PTR record via Resolve-DnsName -Type PTR -DnsOnly -NoHostsFile
        -QuickTimeout and compares case-insensitively with the expected name (host
        name + primary suffix from HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\
        Parameters; without suffix only the first label). Read-only.
.PARAMETER ExpectedName
    DE: NinjaOne Text dnsReverseExpectedName: erwarteter PTR-Name; leer = Hostname + primäres Suffix.
    EN: NinjaOne Text dnsReverseExpectedName: expected PTR name; empty = host name + primary suffix.
.PARAMETER Server
    DE: NinjaOne Text dnsReverseServer: optionale DNS-Server-IP; leer = konfigurierte Server.
    EN: NinjaOne Text dnsReverseServer: optional DNS server IP; empty = configured servers.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkReverseDnsRecord.ps1
    DE: Prüft PTR-Einträge aller lokalen IPv4-Adressen gegen den eigenen FQDN.
    EN: Checks PTR records of all local IPv4 addresses against the own FQDN.
.EXAMPLE
    .\checkReverseDnsRecord.ps1 -ExpectedName srv01.corp.contoso.com -Server 10.0.0.10 -CustomField dnsReverseReport
    DE: Erwartet srv01.corp.contoso.com, Abfrage bei 10.0.0.10; JSON in dnsReverseReport.
    EN: Expects srv01.corp.contoso.com, query at 10.0.0.10; JSON to dnsReverseReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = alle PTR-Einträge passen, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = PTR fehlt (Missing), passt nicht (Mismatch) oder keine IPv4-Adresse. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = all PTR records match, 1 = input, query or write error,
        2 = PTR missing (Missing), mismatching (Mismatch) or no IPv4 address. Read-only.
#>
[CmdletBinding()]
param(
    [string]$ExpectedName = $env:dnsReverseExpectedName,
    [string]$Server = $env:dnsReverseServer,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $ExpectedName = ([string]$ExpectedName).Trim().TrimEnd('.').ToLowerInvariant()
    $Server = ([string]$Server).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($ExpectedName -ieq 'null') { $ExpectedName = '' }
    if ($Server -ieq 'null') { $Server = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($Server) {
        $parsed = $null
        if ($Server.Contains('%') -or -not [System.Net.IPAddress]::TryParse($Server, [ref]$parsed)) {
            throw 'dnsReverseServer muss eine IP-Adresse sein / must be an IP address.'
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    $source = 'Explicit'
    if (-not $ExpectedName) {
        $source = 'HostnameAndPrimarySuffix'
        $tcpip = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction Stop
        $hostLabel = ([string]$tcpip.Hostname).Trim()
        if (-not $hostLabel) { $hostLabel = ([string]$env:COMPUTERNAME).Trim() }
        $suffix = ([string]$tcpip.Domain).Trim().TrimEnd('.')
        $ExpectedName = $hostLabel.ToLowerInvariant()
        if ($suffix) { $ExpectedName = ('{0}.{1}' -f $hostLabel, $suffix).ToLowerInvariant() }
    }
    if ($ExpectedName.Length -gt 253 -or $ExpectedName -notmatch '^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$') {
        throw 'Ungültiger erwarteter Name / Invalid expected name.'
    }
    foreach ($label in $ExpectedName.Split('.')) {
        if ($label -notmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') { throw 'Ungültiges DNS-Label / Invalid DNS label.' }
    }
    $labelOnly = -not $ExpectedName.Contains('.')
    foreach ($command in @('Resolve-DnsName', 'Get-NetAdapter', 'Get-NetIPAddress')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $upIndexes = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [int]$_.InterfaceIndex })
    $addresses = @(Get-NetIPAddress -ErrorAction Stop |
        Where-Object { $upIndexes -contains [int]$_.InterfaceIndex -and [string]$_.AddressState -eq 'Preferred' } |
        ForEach-Object { $ip = $null; if ([System.Net.IPAddress]::TryParse(([string]$_.IPAddress), [ref]$ip) -and $ip.AddressFamily -eq 'InterNetwork') { $ip.ToString() } } |
        Where-Object { $_ -notmatch '^(127\.|169\.254\.)' } |
        Sort-Object -Unique)
    $totalAddresses = $addresses.Count
    $results = @(foreach ($address in @($addresses | Select-Object -First 20)) {
        $arguments = @{ Name = $address; Type = 'PTR'; DnsOnly = $true; NoHostsFile = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
        if ($Server) { $arguments.Server = $Server }
        $names = @(); $message = ''
        try {
            $names = @(Resolve-DnsName @arguments | Where-Object { [string]$_.Type -eq 'PTR' } |
                ForEach-Object { ([string]$_.NameHost).TrimEnd('.').ToLowerInvariant() } | Select-Object -Unique -First 5)
        }
        catch {
            $message = [string]$_.Exception.Message
            if ($message.Length -gt 120) { $message = $message.Substring(0, 120) }
        }
        $status = 'Missing'
        if ($names.Count -gt 0) {
            $status = 'Mismatch'
            foreach ($name in $names) {
                if ($name -eq $ExpectedName -or ($labelOnly -and $name.Split('.')[0] -eq $ExpectedName)) { $status = 'OK' }
            }
        }
        [pscustomobject]@{ Address = $address; Status = $status; PtrNames = $names; Error = $message }
    })
    $problems = @($results | Where-Object { $_.Status -ne 'OK' }).Count
    $records = @(@($results | Where-Object { $_.Status -ne 'OK' }) + @($results | Where-Object { $_.Status -eq 'OK' }))
    do {
        $report = [ordered]@{
            ExpectedName = $ExpectedName; ExpectedNameSource = $source; Server = $Server
            TotalAddresses = $totalAddresses; CheckedAddresses = $results.Count; Problems = $problems
            ReportedRecords = $records.Count; Truncated = ($records.Count -lt $totalAddresses); Results = $records
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($results.Count -eq 0 -or $problems -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
