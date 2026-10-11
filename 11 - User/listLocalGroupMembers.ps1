#Requires -Version 5.1
<#
.SYNOPSIS
DE: Direkte Mitglieder einer lokalen Gruppe lesen. EN: Read direct members of one local group.
.DESCRIPTION
DE: Keine rekursive Domaenenaufloesung, keine effektiven Rechte/Anmeldesitzungen.
EN: No recursive domain expansion, effective privilege or logged-on session inference.
DE: SYSTEM und 64-Bit-PowerShell; integrierte LocalAccounts-Cmdlets
(Windows 10/Server 2016+) erforderlich. Keine lokale SAM auf Domaenencontrollern.
EN: Use SYSTEM and 64-bit PowerShell; built-in LocalAccounts cmdlets required
(Windows 10/Server 2016+). Domain controllers have no local SAM.
DE: Parameter vor NinjaOne-Variablen localGroup, maxRecords, resultFormat,
resultCustomField. Leere Gruppe: SID S-1-5-32-544 (Administratoren, sprachunabhaengig).
EN: Parameters override those variables. Blank group: SID S-1-5-32-544
(Administrators, language independent). Exact local name or SID; no wildcards.
DE: Nicht aufloesbare Mitglieder/fehlende Gruppe sind Fehler, kein leeres Erfolgsergebnis.
EN: Unresolvable members/missing group are errors, not successful empty results.
DE/EN: Leer/blanks: maxRecords 10, resultFormat Json (oder/or PlainText), kein Feld/no field.
DE/EN: Optional CustomField: NinjaOne MultiLine, maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (nicht verwendet/not used).
#>
[CmdletBinding()]
param(
    [string]$Group = $env:localGroup,
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
    $Group = ([string]$Group).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($Group -ieq 'null') { $Group = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $Group) { $Group = 'S-1-5-32-544' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($Group.Length -gt 256 -or $Group -match '[\x00-\x1F\x7F*?\[\]]') { throw 'Invalid exact local group name / Ungueltiger exakter lokaler Gruppenname.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) -or -not (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue)) { throw 'LocalAccounts cmdlets unavailable / nicht verfuegbar.' }
    if ($Group -match '^S-\d-') {
        $sid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Group
        $selected = @(Get-LocalGroup -SID $sid -ErrorAction Stop)
    } else {
        # DE: Exakter Vergleich statt Wildcards. EN: Exact comparison instead of wildcard matching.
        $selected = @(Get-LocalGroup -ErrorAction Stop | Where-Object { $_.Name -eq $Group })
    }
    if ($selected.Count -ne 1) { throw 'Exactly one local group required / Genau eine lokale Gruppe erforderlich.' }
    $members = @(Get-LocalGroupMember -Group $selected[0] -ErrorAction Stop | Sort-Object Name)
    $records = @($members | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; objectClass = $_.ObjectClass; principalSource = [string]$_.PrincipalSource }
    })
    $report = [pscustomobject]@{
        inventory = 'Direct local group members / Direkte lokale Gruppenmitglieder'
        group = $selected[0].Name; scope = 'Direct only / Nur direkte Mitglieder'
        total = $members.Count; returned = $records.Count
        truncated = ($members.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    Write-Error 'Group membership inventory or field write failed; check local SAM support, group/member resolution, parameters, permissions and NinjaOne field configuration. / Gruppenmitgliedschaftsinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}
