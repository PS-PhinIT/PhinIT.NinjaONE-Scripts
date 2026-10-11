#Requires -Version 5.1
<#
.SYNOPSIS
    DE: Meldet begrenzte DNS-Cache-Metadaten, ohne Cache zu leeren.
    EN: Reports bounded DNS cache metadata without clearing the cache.
.DESCRIPTION
    DE: Keine Namen, Adressen oder Daten; nur Typ, Status und TTL.
        Gesamtzahl und Kürzung werden angegeben; maximal 4000 Zeichen.
    EN: No names, addresses or data; only type, status and TTL.
        Includes total and truncation indicators; at most 4000 characters.
.PARAMETER MaxRecords
    DE: 1 bis 100; dnsCacheMaxRecords, Standard 25.
    EN: 1 through 100; dnsCacheMaxRecords, default 25.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen.
        Leere Werte verwenden Standards. Exit 0 = Erfolg, 1 = Fehler, 2 = gekürzt.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment.
        Empty values use defaults. Exit 0 = success, 1 = error, 2 = truncated.
#>
[CmdletBinding()]
param(
    [string]$MaxRecords = $env:dnsCacheMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    $MaxRecords = $MaxRecords.Trim()
    if ($MaxRecords -eq 'null') { $MaxRecords = '' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'MaxRecords muss 1..100 sein / MaxRecords must be 1..100.'
    }
    if (-not (Get-Command Get-DnsClientCache -ErrorAction SilentlyContinue)) {
        throw 'Get-DnsClientCache fehlt / is unavailable.'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    # DE: Private Cache-Namen und Antworten niemals in den Bericht übernehmen.
    # EN: Never copy private cached names or answers into the report.
    $cache = @(Get-DnsClientCache -ErrorAction Stop | Select-Object Type, Status, TimeToLive)
    $records = @($cache | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $cache.Count
        $report = [ordered]@{
            TotalRecords = $cache.Count; ReportedRecords = $records.Count
            Truncated = $truncated; Records = $records
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
    if ($truncated) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
