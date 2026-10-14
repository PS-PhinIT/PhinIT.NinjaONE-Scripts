#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die DNS-SRV-Einträge der Domänencontroller (LDAP/Kerberos).
    EN: Checks the domain controller DNS SRV records (LDAP/Kerberos).
.DESCRIPTION
    DE: Für Domänenmitglieder (Win32_ComputerSystem PartOfDomain, Domain) werden
        _ldap._tcp.dc._msdcs.<Domäne> und _kerberos._tcp.<Domäne> per Resolve-DnsName
        -Type SRV -DnsOnly -NoHostsFile -QuickTimeout aufgelöst (konfigurierte oder
        explizite DNS-Server). Ziel, Port, Priorität und Gewicht werden gemeldet
        (max. 10 je Abfrage, 4000 Zeichen). Arbeitsgruppenrechner: Status
        NotDomainJoined, Exit 0. Nur lesend.
    EN: For domain members (Win32_ComputerSystem PartOfDomain, Domain) resolves
        _ldap._tcp.dc._msdcs.<domain> and _kerberos._tcp.<domain> via Resolve-DnsName
        -Type SRV -DnsOnly -NoHostsFile -QuickTimeout (configured or explicit DNS
        server). Reports target, port, priority and weight (max. 10 per query, 4000
        characters). Workgroup computers: status NotDomainJoined, exit 0. Read-only.
.PARAMETER Server
    DE: NinjaOne Text dnsSrvServer: optionale DNS-Server-IP; leer = konfigurierte Server.
    EN: NinjaOne Text dnsSrvServer: optional DNS server IP; empty = configured servers.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkDomainSrvRecords.ps1
    DE: Prüft die DC-SRV-Einträge der eigenen Domäne über die konfigurierten DNS-Server.
    EN: Checks the DC SRV records of the own domain via the configured DNS servers.
.EXAMPLE
    .\checkDomainSrvRecords.ps1 -Server 10.0.0.10 -CustomField dnsSrvReport
    DE: Abfrage direkt bei 10.0.0.10; JSON in dnsSrvReport.
    EN: Query directly at 10.0.0.10; JSON to dnsSrvReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = beide Abfragen liefern SRV-Einträge oder NotDomainJoined, 1 = Eingabe-,
        Abfrage- oder Schreibfehler, 2 = mindestens eine Abfrage ohne SRV-Eintrag
        bzw. fehlgeschlagen. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = both queries return SRV records or NotDomainJoined, 1 = input, query
        or write error, 2 = at least one query without SRV records or failed. Read-only.
#>
[CmdletBinding()]
param(
    [string]$Server = $env:dnsSrvServer,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $Server = ([string]$Server).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($Server -ieq 'null') { $Server = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($Server) {
        $parsed = $null
        if ($Server.Contains('%') -or -not [System.Net.IPAddress]::TryParse($Server, [ref]$parsed)) {
            throw 'dnsSrvServer muss eine IP-Adresse sein / must be an IP address.'
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { throw 'Resolve-DnsName fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
    $domain = ([string]$system.Domain).Trim().TrimEnd('.')
    $status = 'NotDomainJoined'
    $queries = @()
    if ($system.PartOfDomain -eq $true) {
        if ($domain.Length -gt 200 -or $domain -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') {
            throw 'Ungültiger Domänenname / Invalid domain name.'
        }
        foreach ($label in $domain.Split('.')) {
            if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { throw 'Ungültiges Domänen-Label / Invalid domain label.' }
        }
        $queries = @(foreach ($name in @("_ldap._tcp.dc._msdcs.$domain", "_kerberos._tcp.$domain")) {
            $arguments = @{ Name = $name; Type = 'SRV'; DnsOnly = $true; NoHostsFile = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
            if ($Server) { $arguments.Server = $Server }
            $records = @(); $message = ''
            try {
                $records = @(Resolve-DnsName @arguments | Where-Object { [string]$_.Type -eq 'SRV' } |
                    Select-Object @{ Name = 'Target'; Expression = { ([string]$_.NameTarget).TrimEnd('.') } }, Port, Priority, Weight)
            }
            catch {
                $message = [string]$_.Exception.Message
                if ($message.Length -gt 150) { $message = $message.Substring(0, 150) }
            }
            [pscustomobject]@{
                Query = $name; TotalRecords = $records.Count; Truncated = ($records.Count -gt 10)
                Records = @($records | Select-Object -First 10); Error = $message
            }
        })
        $status = 'OK'
        if (@($queries | Where-Object { $_.TotalRecords -eq 0 }).Count -gt 0) { $status = 'MissingRecords' }
    }
    $report = [ordered]@{ Status = $status; PartOfDomain = [bool]$system.PartOfDomain; Domain = $domain; Server = $Server; Queries = $queries } |
        ConvertTo-Json -Depth 5
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($status -eq 'MissingRecords') { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
