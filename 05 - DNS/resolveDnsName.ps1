#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Löst einen ausdrücklich konfigurierten DNS-Namen auf.
    EN: Resolves an explicitly configured DNS name.
.DESCRIPTION
    DE: Nur DNS-Abfrage, keine Konfigurationsänderung. Ohne Namen keine Aktion.
        TXT-Daten werden nicht ausgegeben. Überlange Berichte schlagen fehl.
    EN: DNS query only, no configuration changes. No name means no action.
        TXT data is not exposed. Oversized reports fail explicitly.
.PARAMETER HostName
    DE: DNS-Name; NinjaOne-Variable dnsHostName.
    EN: DNS name; NinjaOne variable dnsHostName.
.PARAMETER RecordType
    DE: A, AAAA, CNAME, MX, NS, PTR, SOA oder TXT; dnsRecordType, Standard A.
    EN: A, AAAA, CNAME, MX, NS, PTR, SOA or TXT; dnsRecordType, default A.
.PARAMETER Server
    DE: Optionale DNS-Server-IP; dnsServer.
    EN: Optional DNS server IP; dnsServer.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.EXAMPLE
    .\resolveDnsName.ps1 -HostName www.microsoft.com
    DE: Löst den A-Eintrag über die konfigurierten DNS-Server auf.
    EN: Resolves the A record using the configured DNS servers.
.EXAMPLE
    .\resolveDnsName.ps1 -HostName contoso.com -RecordType MX -Server 1.1.1.1 -CustomField dnsResolveReport
    DE: Fragt MX-Einträge direkt bei 1.1.1.1 ab; JSON in dnsResolveReport schreiben.
    EN: Queries MX records directly at 1.1.1.1; write JSON to dnsResolveReport.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter haben Vorrang vor
        Umgebungsvariablen; leere Werte verwenden dokumentierte Standards.
        Exit 0 = Erfolg/keine Aktion, 1 = Fehler, 2 = Warnung (keine Einträge erhalten).
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment
        variables; empty values use documented defaults.
        Exit 0 = success/no action, 1 = error, 2 = warning (no records returned).
#>
[CmdletBinding()]
param(
    [string]$HostName = $env:dnsHostName,
    [string]$RecordType = $env:dnsRecordType,
    [string]$Server = $env:dnsServer,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $HostName = $HostName.Trim()
    $RecordType = $RecordType.Trim().ToUpperInvariant()
    $Server = $Server.Trim()
    $CustomField = $CustomField.Trim()
    if ($HostName -eq 'null') { $HostName = '' }
    if ($RecordType -eq 'null') { $RecordType = '' }
    if ($Server -eq 'null') { $Server = '' }
    if ($CustomField -eq 'null') { $CustomField = '' }
    if (-not $RecordType) { $RecordType = 'A' }
    if ($RecordType -notin @('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'TXT')) {
        throw 'Ungültiger RecordType / Invalid RecordType.'
    }
    if (-not $HostName) {
        Write-Output 'Keine Aktion: dnsHostName fehlt / No action: dnsHostName is not configured.'
        exit 0
    }
    # DE: Keine Wildcards, URLs oder Optionszeichen; DNS-Labels einzeln prüfen.
    # EN: Reject wildcards, URLs and option characters; validate individual DNS labels.
    if ($HostName.Length -gt 253 -or $HostName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.?$') {
        throw 'Ungültiger DNS-Name / Invalid DNS name.'
    }
    foreach ($label in $HostName.TrimEnd('.').Split('.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
            throw 'Ungültiges DNS-Label / Invalid DNS label.'
        }
    }
    if ($Server) {
        $address = $null
        if (-not [System.Net.IPAddress]::TryParse($Server, [ref]$address)) {
            throw 'dnsServer muss eine IP-Adresse sein / dnsServer must be an IP address.'
        }
    }
    if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
        throw 'Resolve-DnsName fehlt / is unavailable.'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $arguments = @{ Name = $HostName; Type = $RecordType; DnsOnly = $true; NoHostsFile = $true; ErrorAction = 'Stop' }
    if ($Server) { $arguments.Server = $Server }
    $records = @(Resolve-DnsName @arguments | Select-Object Name, Type, TTL, Section, IPAddress, NameHost, NameExchange, Preference)
    $report = [ordered]@{
        HostName = $HostName; RecordType = $RecordType; Server = $Server
        TotalRecords = $records.Count; Records = $records
    } | ConvertTo-Json -Depth 5
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($records.Count -eq 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
