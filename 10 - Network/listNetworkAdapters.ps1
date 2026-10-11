#Requires -Version 5.1

<#
.SYNOPSIS
DE: Netzwerkadapter inventarisieren. EN: Inventory network adapters.
.DESCRIPTION
DE: Schreibgeschuetzte Momentaufnahme ohne MAC-Adressen, IPs oder DNS-Daten.
EN: Read-only snapshot without MAC addresses, IPs or DNS data.
DE: SYSTEM und 64-Bit-PowerShell verwenden. Get-NetAdapter muss verfuegbar sein.
EN: Use SYSTEM and 64-bit PowerShell. Requires built-in Get-NetAdapter.
DE: Parameter vor NinjaOne-Variablen includeHiddenAdapters, maxRecords,
resultFormat und resultCustomField. Leer: false, 10, Json, kein Feld.
EN: Parameters override those variables. Blanks: false, 10, Json, no field.
DE/EN: includeHiddenAdapters = true/false/1/0; resultFormat = Json/PlainText.
DE/EN: Optional CustomField: NinjaOne MultiLine (JSON oder Text / JSON or text),
maximal/maximum 4000 Zeichen/characters, sonst Fehler / otherwise failure.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (nicht verwendet/not used).
.PARAMETER IncludeHidden
DE/EN: NinjaOne includeHiddenAdapters; leer/null = false; Werte/values true, false, 1, 0.
.PARAMETER MaxRecords
DE/EN: NinjaOne maxRecords; leer/null = 10; Bereich/range 1..100.
.PARAMETER ResultFormat
DE/EN: NinjaOne resultFormat; leer/null = Json; Werte/values Json, PlainText.
.PARAMETER CustomField
DE/EN: -WhatIf liest weiter / still reads; unterdrueckt Feldschreiben / skips field write.
DE/EN: NinjaOne resultCustomField; leer/null = kein Feld/no field.
NinjaOne MultiLine; Name/name [A-Za-z][A-Za-z0-9_]{0,99}; maximal/maximum 4000 Zeichen/characters.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$IncludeHidden = $env:includeHiddenAdapters,
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
    $IncludeHidden = ([string]$IncludeHidden).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($IncludeHidden -ieq 'null') { $IncludeHidden = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $IncludeHidden) { $IncludeHidden = 'false' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($IncludeHidden -notin @('true', 'false', '1', '0')) { throw 'includeHiddenAdapters must be true/false/1/0 / muss true/false/1/0 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $adapters = @(Get-NetAdapter -IncludeHidden:($IncludeHidden -in @('true', '1')) -ErrorAction Stop | Sort-Object InterfaceIndex)
    $records = @($adapters | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name; interfaceIndex = $_.InterfaceIndex; status = [string]$_.Status
            linkSpeed = [string]$_.LinkSpeed; hardware = $_.HardwareInterface; virtual = $_.Virtual
        }
    })
    $report = [pscustomobject]@{
        inventory = 'Network adapters / Netzwerkadapter'; includesHidden = ($IncludeHidden -in @('true', '1'))
        total = $adapters.Count; returned = $records.Count
        truncated = ($adapters.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    Write-Error 'Adapter inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / Adapterinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}
