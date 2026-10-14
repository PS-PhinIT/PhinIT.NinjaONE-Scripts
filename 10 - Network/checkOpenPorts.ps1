#Requires -Version 5.1

<#
.SYNOPSIS
DE: Lokale TCP-Listener und UDP-Endpunkte. EN: Local TCP listeners and UDP endpoints.
.DESCRIPTION
DE: Kein Portscanner: Gebundene Ports beweisen keine externe Erreichbarkeit.
EN: Not a port scanner: bound ports do not establish external reachability.
DE: SYSTEM und 64-Bit-PowerShell verwenden; UDP hat keinen TCP-Listen-Zustand.
EN: Use SYSTEM and 64-bit PowerShell; UDP has no TCP listening state.
DE: Explizite Parameter vor NinjaOne-Variablen localPort, includeUdp, maxRecords,
resultFormat, resultCustomField. Leere Werte: alle Ports, UDP true, 10 Datensaetze, Json.
EN: Explicit parameters override those variables. Blank defaults: all ports, UDP true, 10 records, Json.
DE/EN: includeUdp = true/false/1/0. Optional CustomField: NinjaOne MultiLine,
Json/PlainText, maximal/maximum 4000 Zeichen/characters (sonst Fehler / otherwise failure).
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (nicht verwendet/not used).
.PARAMETER LocalPort
DE/EN: NinjaOne localPort; leer/null = alle Ports/all ports; Bereich/range 1..65535.
.PARAMETER IncludeUdp
DE/EN: NinjaOne includeUdp; leer/null = true; Werte/values true, false, 1, 0.
.PARAMETER MaxRecords
DE/EN: NinjaOne maxRecords; leer/null = 10; Bereich/range 1..100.
.PARAMETER ResultFormat
DE/EN: NinjaOne resultFormat; leer/null = Json; Werte/values Json, PlainText.
.PARAMETER CustomField
DE/EN: -WhatIf liest weiter / still reads; unterdrueckt Feldschreiben / skips field write.
DE/EN: NinjaOne resultCustomField; leer/null = kein Feld/no field.
NinjaOne MultiLine; Name/name [A-Za-z][A-Za-z0-9_]{0,99}; maximal/maximum 4000 Zeichen/characters.
.EXAMPLE
.\checkOpenPorts.ps1 -LocalPort 3389
DE: Zeigt TCP-Listener und UDP-Endpunkte auf Port 3389. EN: Shows TCP listeners and UDP endpoints on port 3389.
.EXAMPLE
.\checkOpenPorts.ps1 -IncludeUdp false -MaxRecords 50 -CustomField openPorts
DE: Nur TCP-Listener (max. 50) als JSON in openPorts. EN: TCP listeners only (max. 50) as JSON to openPorts.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LocalPort = $env:localPort,
    [string]$IncludeUdp = $env:includeUdp,
    [string]$MaxRecords = $env:maxRecords,
    [string]$ResultFormat = $env:resultFormat,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([object]$Report, [string]$Format, [string]$Field)
    if ($Format -eq 'Json') {
        $content = ConvertTo-Json -InputObject $Report -Depth 6 -Compress
    } else {
        $summary = $Report | Select-Object * -ExcludeProperty records | Format-List | Out-String -Width 200
        $rows = $Report.records | Format-List | Out-String -Width 200
        $content = ($summary + $rows).Trim()
    }
    # DE: Steuerzeichen entfernen. EN: Remove terminal control characters.
    $content = $content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters; reduce maxRecords. / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows required / erforderlich.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $LocalPort = ([string]$LocalPort).Trim()
    $IncludeUdp = ([string]$IncludeUdp).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($LocalPort -ieq 'null') { $LocalPort = '' }
    if ($IncludeUdp -ieq 'null') { $IncludeUdp = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $IncludeUdp) { $IncludeUdp = 'true' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    $port = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($LocalPort -and (-not [int]::TryParse($LocalPort, [ref]$port) -or $port -lt 1 -or $port -gt 65535)) { throw 'localPort must be 1..65535 / muss 1..65535 sein.' }
    if ($IncludeUdp -notin @('true', 'false', '1', '0')) { throw 'includeUdp must be true/false/1/0 / muss true/false/1/0 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    # DE: Nur lokale Tabellen lesen. EN: Read only local endpoint tables.
    $endpoints = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ protocol = 'TCP'; localAddress = $_.LocalAddress; localPort = $_.LocalPort; processId = $_.OwningProcess }
    })
    if ($IncludeUdp -in @('true', '1')) {
        $endpoints += @(Get-NetUDPEndpoint -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ protocol = 'UDP'; localAddress = $_.LocalAddress; localPort = $_.LocalPort; processId = $_.OwningProcess }
        })
    }
    $endpoints = @($endpoints | Where-Object { -not $LocalPort -or $_.localPort -eq $port } | Sort-Object protocol, localPort, localAddress)
    $records = @($endpoints | Select-Object -First $limit)
    $report = [pscustomobject]@{
        inventory = 'Local bound ports / Lokal gebundene Ports'
        scope = 'Not a scan or reachability test / Kein Scan oder Erreichbarkeitstest'
        total = $endpoints.Count; returned = $records.Count
        truncated = ($endpoints.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    Write-Error 'Local port inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / Lokales Portinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}