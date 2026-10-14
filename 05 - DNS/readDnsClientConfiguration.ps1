#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest globale und adapterbezogene DNS-Client-Konfiguration.
    EN: Reads global and per-interface DNS client configuration.
.DESCRIPTION
    DE: Keine Änderungen. Berichtet DNS-Suffixe, Registrierung und Server,
        nicht MAC-Adressen, Benutzer oder allgemeine IP-Konfiguration.
        Über 4000 Zeichen wird mit Fehler abgebrochen.
    EN: No changes. Reports DNS suffixes, registration and servers,
        not MAC addresses, users or general IP configuration.
        Reports over 4000 characters fail explicitly.
.PARAMETER InterfaceIndex
    DE: Optionaler positiver Adapterindex; dnsInterfaceIndex. Leer = alle.
    EN: Optional positive interface index; dnsInterfaceIndex. Empty = all.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.EXAMPLE
    .\readDnsClientConfiguration.ps1
    DE: Liest die DNS-Client-Konfiguration aller Adapter.
    EN: Reads the DNS client configuration of all interfaces.
.EXAMPLE
    .\readDnsClientConfiguration.ps1 -InterfaceIndex 12 -CustomField dnsClientConfiguration
    DE: Nur Adapter mit Index 12; JSON in dnsClientConfiguration schreiben.
    EN: Only interface index 12; write JSON to dnsClientConfiguration.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen.
        Exit 0 = Erfolg, 1 = Fehler, 2 = keine Adapter.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment.
        Exit 0 = success, 1 = error, 2 = no interfaces.
#>
[CmdletBinding()]
param(
    [string]$InterfaceIndex = $env:dnsInterfaceIndex,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $InterfaceIndex = $InterfaceIndex.Trim()
    $CustomField = $CustomField.Trim()
    if ($InterfaceIndex -eq 'null') { $InterfaceIndex = '' }
    if ($CustomField -eq 'null') { $CustomField = '' }
    $index = 0
    if ($InterfaceIndex -and (-not [int]::TryParse($InterfaceIndex, [ref]$index) -or $index -lt 1)) {
        throw 'Ungültiger InterfaceIndex / Invalid InterfaceIndex.'
    }
    foreach ($command in @('Get-DnsClient', 'Get-DnsClientGlobalSetting', 'Get-DnsClientServerAddress')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $arguments = @{ ErrorAction = 'Stop' }
    if ($InterfaceIndex) { $arguments.InterfaceIndex = $index }
    $clients = @(Get-DnsClient @arguments)
    $interfaces = @(
        foreach ($client in $clients) {
            $servers = @(Get-DnsClientServerAddress -InterfaceIndex $client.InterfaceIndex -ErrorAction Stop |
                Select-Object AddressFamily, ServerAddresses)
            [pscustomobject]@{
                InterfaceIndex = $client.InterfaceIndex
                InterfaceAlias = $client.InterfaceAlias
                ConnectionSpecificSuffix = $client.ConnectionSpecificSuffix
                RegisterThisConnectionsAddress = $client.RegisterThisConnectionsAddress
                UseSuffixWhenRegistering = $client.UseSuffixWhenRegistering
                Servers = $servers
            }
        }
    )
    $settings = Get-DnsClientGlobalSetting -ErrorAction Stop |
        Select-Object SuffixSearchList, UseDevolution, DevolutionLevel
    $report = [ordered]@{
        GlobalSettings = $settings; TotalInterfaces = $interfaces.Count; Interfaces = $interfaces
    } | ConvertTo-Json -Depth 6
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($interfaces.Count -eq 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
