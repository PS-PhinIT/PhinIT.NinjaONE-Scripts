#Requires -Version 5.1

<#
.SYNOPSIS
DE: Lokale Benutzerprofile auflisten. EN: List local user profiles.
.DESCRIPTION
DE: Win32_UserProfile-Metadaten, keine Dateisuche, keine Loeschung/Aenderung.
EN: Win32_UserProfile metadata, no file traversal or deletion/modification.
DE: Nur Profilordnername statt vollem Pfad; keine SID, keine Dateiinhalte.
EN: Reports profile folder leaf instead of full path; no SID or file contents.
DE: SYSTEM und 64-Bit-PowerShell verwenden. Profile sind nicht Benutzerkonten.
EN: Use SYSTEM and 64-bit PowerShell. Profiles are not user accounts.
DE: Parameter vor NinjaOne-Variablen includeSpecialProfiles, maxRecords,
resultFormat, resultCustomField. Leer: false, 10, Json, kein Feld.
EN: Parameters override those variables. Blanks: false, 10, Json, no field.
DE/EN: includeSpecialProfiles = true/false/1/0; resultFormat = Json/PlainText.
DE/EN: Optional CustomField: NinjaOne MultiLine; maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (nicht verwendet/not used).
.PARAMETER IncludeSpecial
DE/EN: NinjaOne includeSpecialProfiles; leer/null = false; Werte/values true, false, 1, 0.
.PARAMETER MaxRecords
DE/EN: NinjaOne maxRecords; leer/null = 10; Bereich/range 1..100.
.PARAMETER ResultFormat
DE/EN: NinjaOne resultFormat; leer/null = Json; Werte/values Json, PlainText.
.PARAMETER CustomField
DE/EN: -WhatIf liest weiter / still reads; unterdrueckt Feldschreiben / skips field write.
DE/EN: NinjaOne resultCustomField; leer/null = kein Feld/no field.
NinjaOne MultiLine; Name/name [A-Za-z][A-Za-z0-9_]{0,99}; maximal/maximum 4000 Zeichen/characters.
.EXAMPLE
.\listUsersProfiles.ps1 -MaxRecords 25
DE: Bis zu 25 Benutzerprofile ohne Systemprofile. EN: Up to 25 user profiles without special profiles.
.EXAMPLE
.\listUsersProfiles.ps1 -IncludeSpecial true -MaxRecords 50 -CustomField userProfiles
DE: Inklusive Systemprofile; JSON in userProfiles. EN: Including special profiles; JSON to userProfiles.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$IncludeSpecial = $env:includeSpecialProfiles,
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
    $IncludeSpecial = ([string]$IncludeSpecial).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($IncludeSpecial -ieq 'null') { $IncludeSpecial = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $IncludeSpecial) { $IncludeSpecial = 'false' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($IncludeSpecial -notin @('true', 'false', '1', '0')) { throw 'includeSpecialProfiles must be true/false/1/0 / muss true/false/1/0 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object {
        -not $_.Special -or $IncludeSpecial -in @('true', '1')
    } | Sort-Object LocalPath)
    $records = @($profiles | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{
            profileFolder = [IO.Path]::GetFileName(([string]$_.LocalPath).TrimEnd('\'))
            loaded = $_.Loaded; special = $_.Special; status = $_.Status
            healthStatus = $_.HealthStatus
        }
    })
    $report = [pscustomobject]@{
        inventory = 'Local profiles / Lokale Profile'; includesSpecial = ($IncludeSpecial -in @('true', '1'))
        total = $profiles.Count; returned = $records.Count
        truncated = ($profiles.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    Write-Error 'Profile inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / Profilinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}