#Requires -Version 5.1

<#
.SYNOPSIS
DE: Profilnutzungszeiten lesen, keine autoritativen Anmeldungen. EN: Read profile use times, not authoritative logons.
.DESCRIPTION
DE: Der historische Dateiname ist irrefuehrend: Win32_UserProfile.LastUseTime ist
Profilnutzung, NICHT letzte Anmeldung. Fehlend/veraltet moeglich; Dienste, geladene
Profile und Windows-Wartung beeinflussen Werte. Kein AD-/Security-Event-Log-Nachweis.
EN: The legacy filename is misleading: Win32_UserProfile.LastUseTime measures
profile use, NOT last logon. It may be missing/stale; services, loaded profiles and
Windows servicing influence it. It is not AD or Security event log evidence.
DE: SYSTEM und 64-Bit-PowerShell; keine Loeschung oder Kontenaenderung.
EN: Use SYSTEM and 64-bit PowerShell; no deletion or account changes.
DE: Parameter vor NinjaOne-Variablen staleProfileDays, maxRecords, resultFormat,
resultCustomField. Leer: 90 Tage, 10, Json, kein Feld. Systemprofile ausgeschlossen.
EN: Parameters override those variables. Blanks: 90 days, 10, Json, no field. Special profiles excluded.
DE: Alarm nur fuer bekannte alte Nutzung ungeladener Profile; unbekannt separat.
EN: Alerts only for known old use of unloaded profiles; unknown times counted separately.
DE/EN: Optional CustomField: NinjaOne MultiLine, Json/PlainText, maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = alte Profilnutzung/stale profile use.
.PARAMETER StaleDays
DE/EN: NinjaOne staleProfileDays; leer/null = 90; Bereich/range 1..3650 Tage/days.
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
    [string]$StaleDays = $env:staleProfileDays,
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
    $StaleDays = ([string]$StaleDays).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($StaleDays -ieq 'null') { $StaleDays = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $StaleDays) { $StaleDays = '90' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    $days = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if (-not [int]::TryParse($StaleDays, [ref]$days) -or $days -lt 1 -or $days -gt 3650) { throw 'staleProfileDays must be 1..3650 / muss 1..3650 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $now = [DateTime]::UtcNow
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special } | ForEach-Object {
        $lastUse = $null
        $age = $null
        # DE: CIM liefert DateTime, keine heuristische Logon-Ableitung. EN: CIM returns DateTime, not a logon inference.
        if ($null -ne $_.LastUseTime) {
            if ($_.LastUseTime -isnot [DateTime]) { throw 'Unexpected CIM timestamp type / Unerwarteter CIM-Zeittyp.' }
            $lastUse = $_.LastUseTime.ToUniversalTime()
            if ($lastUse -le $now) { $age = [math]::Floor(($now - $lastUse).TotalDays) }
        }
        [pscustomobject]@{
            profileFolder = [IO.Path]::GetFileName(([string]$_.LocalPath).TrimEnd('\'))
            lastProfileUseUtc = $(if ($null -ne $lastUse) { $lastUse.ToString('o') } else { $null })
            ageDays = $age; loaded = $_.Loaded
            stale = ($null -ne $age -and $age -ge $days -and -not $_.Loaded)
        }
    } | Sort-Object @{ Expression = 'stale'; Descending = $true }, profileFolder)
    $stale = @($profiles | Where-Object { $_.stale })
    $unknown = @($profiles | Where-Object { $null -eq $_.ageDays })
    $records = @($profiles | Select-Object -First $limit)
    $report = [pscustomobject]@{
        inventory = 'Profile use times / Profilnutzungszeiten'
        caveat = 'LastUseTime is NOT authoritative last logon / KEINE autoritative letzte Anmeldung'
        thresholdDays = $days; staleTotal = $stale.Count; unknownOrFutureTotal = $unknown.Count
        total = $profiles.Count; returned = $records.Count
        truncated = ($profiles.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    if ($stale.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Error 'Profile-use inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / Profilnutzungsinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}