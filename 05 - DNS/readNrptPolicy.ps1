#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert NRPT-Richtlinie und -Regeln des DNS-Clients (begrenzt).
    EN: Inventories the DNS client NRPT policy and rules (bounded).
.DESCRIPTION
    DE: Liest die wirksame Name Resolution Policy Table (Get-DnsClientNrptPolicy) und
        die lokal konfigurierten Regeln (Get-DnsClientNrptRule): Namespace, DNS-Server,
        DirectAccess-/DNSSEC-Kennzeichen. Keine Zertifikate, Kommentare oder Proxys.
        Listen begrenzt mit Total-/Truncated-Angaben, maximal 4000 Zeichen.
        Rein informativ, keine Änderungen.
    EN: Reads the effective Name Resolution Policy Table (Get-DnsClientNrptPolicy) and
        the locally configured rules (Get-DnsClientNrptRule): namespace, DNS servers,
        DirectAccess/DNSSEC flags. No certificates, comments or proxies. Bounded lists
        with total/truncated indicators, at most 4000 characters. Informational only,
        no changes.
.PARAMETER MaxRecords
    DE: NinjaOne Integer dnsNrptMaxRecords, 1..100 je Liste; Standard 25.
    EN: NinjaOne Integer dnsNrptMaxRecords, 1..100 per list; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\readNrptPolicy.ps1
    DE: Meldet bis zu 25 wirksame NRPT-Einträge und 25 Regeln.
    EN: Reports up to 25 effective NRPT entries and 25 rules.
.EXAMPLE
    .\readNrptPolicy.ps1 -MaxRecords 10 -CustomField dnsNrptReport
    DE: Bis zu 10 Einträge je Liste; JSON in dnsNrptReport.
    EN: Up to 10 entries per list; JSON to dnsNrptReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Erfolg (auch ohne NRPT-Einträge), 1 = Eingabe-, Abfrage- oder
        Schreibfehler. Exit 2 wird nicht verwendet (rein informativ). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = success (also without NRPT entries), 1 = input, query or write
        error. Exit 2 is not used (informational only). Read-only.
#>
[CmdletBinding()]
param(
    [string]$MaxRecords = $env:dnsNrptMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'dnsNrptMaxRecords muss 1..100 sein / must be 1..100.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    foreach ($command in @('Get-DnsClientNrptPolicy', 'Get-DnsClientNrptRule')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / is unavailable." }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $policies = @(Get-DnsClientNrptPolicy -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Namespace = (@($_.Namespace) -join ',')
            NameServers = (@($_.NameServers) -join ',')
            DirectAccessDnsServers = (@($_.DirectAccessDnsServers) -join ',')
            DnsSecValidationRequired = [bool]$_.DnsSecValidationRequired
            NameEncoding = [string]$_.NameEncoding
            QueryPolicy = [string]$_.QueryPolicy
        }
    })
    $rules = @(Get-DnsClientNrptRule -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            DisplayName = [string]$_.DisplayName
            Namespace = (@($_.Namespace) -join ',')
            NameServers = (@($_.NameServers) -join ',')
            DirectAccessEnabled = [bool]$_.DirectAccessEnabled
            DnsSecEnabled = [bool]$_.DnsSecEnabled
        }
    })
    $policyRecords = @($policies | Select-Object -First $limit)
    $ruleRecords = @($rules | Select-Object -First $limit)
    do {
        $report = [ordered]@{
            TotalPolicyEntries = $policies.Count; ReportedPolicyEntries = $policyRecords.Count
            PolicyTruncated = ($policyRecords.Count -lt $policies.Count)
            TotalRules = $rules.Count; ReportedRules = $ruleRecords.Count
            RulesTruncated = ($ruleRecords.Count -lt $rules.Count)
            EffectivePolicy = $policyRecords; Rules = $ruleRecords
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($policyRecords.Count -eq 0 -and $ruleRecords.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        if ($ruleRecords.Count -ge $policyRecords.Count) {
            $ruleRecords = @($ruleRecords | Select-Object -First ($ruleRecords.Count - 1))
        }
        else {
            $policyRecords = @($policyRecords | Select-Object -First ($policyRecords.Count - 1))
        }
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
