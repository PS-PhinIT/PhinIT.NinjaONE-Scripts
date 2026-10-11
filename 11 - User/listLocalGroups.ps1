#Requires -Version 5.1
<#
.SYNOPSIS
DE: Lokale Gruppen inventarisieren. EN: Inventory local groups.
.DESCRIPTION
DE: Nur Gruppennamen und Herkunft; keine Beschreibungen, keine Aenderungen.
EN: Only group names and principal source; no descriptions or changes.
DE: SYSTEM und 64-Bit-PowerShell. Benoetigt Get-LocalGroup (Windows 10/Server 2016+);
auf Domaenencontrollern keine lokale SAM. Keine Mitgliedschafts-/Rechteableitung.
EN: Use SYSTEM and 64-bit PowerShell. Requires Get-LocalGroup (Windows 10/Server 2016+);
domain controllers have no local SAM. Does not infer membership or effective rights.
DE: Parameter vor NinjaOne-Variablen maxRecords, resultFormat, resultCustomField.
EN: Parameters override those variables.
DE/EN: Leer/blanks: 10, Json, kein Feld/no field; resultFormat = Json/PlainText.
DE/EN: Optional CustomField: NinjaOne MultiLine, maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (nicht verwendet/not used).
#>
[CmdletBinding()]
param(
    [string]$MaxRecords = $env:maxRecords,
    [string]$ResultFormat = $env:resultFormat,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Write-InventoryReport {
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
    if ($Field) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters; reduce maxRecords. / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
    Write-Output $content
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows required / erforderlich.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue)) { throw 'Get-LocalGroup unavailable / nicht verfuegbar.' }
    $groups = @(Get-LocalGroup -ErrorAction Stop | Sort-Object Name)
    $records = @($groups | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; principalSource = [string]$_.PrincipalSource }
    })
    $report = [pscustomobject]@{
        inventory = 'Local groups / Lokale Gruppen'; total = $groups.Count; returned = $records.Count
        truncated = ($groups.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    Write-Error 'Local group inventory or field write failed; check local SAM support, parameters, permissions and NinjaOne field configuration. / Lokales Gruppeninventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}
