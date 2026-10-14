#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Ermittelt die Tage seit der letzten erfolgreichen Updateinstallation.
    EN: Determines the days since the last successful update installation.
.DESCRIPTION
    DE: Liest den lokalen Windows-Update-Verlauf (Microsoft.Update.Session, nur QueryHistory,
        keine Suche/kein Download) und wertet Installationen (Operation 1) mit ResultCode 2
        (erfolgreich) oder 3 (erfolgreich mit Fehlern) aus. Zusätzlich wird Get-HotFix
        (InstalledOn) gelesen; das jüngste Datum beider Quellen gilt. Defender-Definitions-
        und Plattformupdates (KB2267602, KB2461484, KB915597, KB4052623) werden standardmäßig
        ignoriert, weil sie täglich installiert werden und fehlende Qualitätsupdates verdecken.
        Es werden höchstens 1000 Verlaufseinträge gelesen. Exit 0 = letzte Installation
        innerhalb MaximumDays, 1 = Eingabe-, Abfrage- oder Schreibfehler (beide Quellen
        fehlgeschlagen), 2 = letzte Installation älter als MaximumDays oder keine gefunden.
    EN: Reads the local Windows Update history (Microsoft.Update.Session, QueryHistory only,
        no search/no download) and evaluates installations (operation 1) with ResultCode 2
        (succeeded) or 3 (succeeded with errors). Get-HotFix (InstalledOn) is read as well;
        the newest date of both sources wins. Defender definition and platform updates
        (KB2267602, KB2461484, KB915597, KB4052623) are ignored by default because they are
        installed daily and would hide missing quality updates. At most 1000 history entries
        are read. Exit 0 = last installation within MaximumDays, 1 = input, query or write
        error (both sources failed), 2 = last installation older than MaximumDays or none found.
.PARAMETER MaximumDays
    DE: NinjaOne Integer updateLastInstallMaxDays, 1..3650; Standard 35.
    EN: NinjaOne Integer updateLastInstallMaxDays, 1..3650; default 35.
.PARAMETER IncludeDefinitionUpdates
    DE: NinjaOne Checkbox/Text updateLastInstallIncludeDefinitions, true/false; Standard false.
    EN: NinjaOne Checkbox/Text updateLastInstallIncludeDefinitions, true/false; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\readLastUpdateInstall.ps1
    DE: Warnt (Exit 2), wenn seit mehr als 35 Tagen kein Update installiert wurde.
    EN: Warns (exit 2) if no update has been installed for more than 35 days.
.EXAMPLE
    .\readLastUpdateInstall.ps1 -MaximumDays 45 -CustomField lastUpdateInstall
    DE: Grenzwert 45 Tage, JSON ins MultiLine-Feld lastUpdateInstall schreiben.
    EN: Threshold 45 days, write the JSON to the MultiLine field lastUpdateInstall.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter überschreiben Variablen.
        Verlauf kann nach Zurücksetzen von SoftwareDistribution leer sein; InstalledOn von
        Get-HotFix ist bei manchen Gebietsschemata unzuverlässig (Zukunftsdaten werden verworfen).
        Exit 0 = OK, 1 = Fehler, 2 = zu alt/keine Installation.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables.
        History can be empty after a SoftwareDistribution reset; Get-HotFix InstalledOn is
        unreliable on some locales (future dates are discarded).
        Exit 0 = OK, 1 = error, 2 = too old/no installation.
#>
[CmdletBinding()]
param(
    [string]$MaximumDays = $env:updateLastInstallMaxDays,
    [string]$IncludeDefinitionUpdates = $env:updateLastInstallIncludeDefinitions,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($MaximumDays) -or $MaximumDays.Trim() -eq 'null') { $MaximumDays = '35' }
    if ([string]::IsNullOrWhiteSpace($IncludeDefinitionUpdates) -or $IncludeDefinitionUpdates.Trim() -eq 'null') { $IncludeDefinitionUpdates = 'false' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    $limit = 0
    if (-not [int]::TryParse($MaximumDays.Trim(), [ref]$limit) -or $limit -lt 1 -or $limit -gt 3650) {
        throw 'updateLastInstallMaxDays: 1..3650 erforderlich / required.'
    }
    $includeDefinitions = $false
    if (-not [bool]::TryParse($IncludeDefinitionUpdates.Trim(), [ref]$includeDefinitions)) {
        throw 'updateLastInstallIncludeDefinitions: true/false erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $nowUtc = [DateTime]::UtcNow
    $definitionPattern = 'KB(2267602|2461484|915597|4052623)\b'
    $wuaDate = $null; $wuaTitle = $null; $wuaError = $null; $scanned = 0
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $total = [int]$searcher.GetTotalHistoryCount()
        if ($total -gt 0) {
            foreach ($entry in @($searcher.QueryHistory(0, [Math]::Min($total, 1000)))) {
                $scanned++
                if ([int]$entry.Operation -ne 1 -or [int]$entry.ResultCode -notin @(2, 3) -or $null -eq $entry.Date) { continue }
                if (-not $includeDefinitions -and [string]$entry.Title -match $definitionPattern) { continue }
                # DE: WUA liefert UTC ohne Kind. EN: WUA returns UTC without kind.
                $date = [DateTime]::SpecifyKind([DateTime]$entry.Date, [DateTimeKind]::Utc)
                if ($date -gt $nowUtc.AddDays(1)) { continue }
                if ($null -eq $wuaDate -or $date -gt $wuaDate) { $wuaDate = $date; $wuaTitle = [string]$entry.Title }
            }
        }
    }
    catch { $wuaError = $_.Exception.Message }
    $hotfixDate = $null; $hotfixId = $null; $hotfixError = $null
    try {
        foreach ($hotfix in @(Get-HotFix)) {
            if ($null -eq $hotfix.InstalledOn) { continue }
            $date = ([DateTime]$hotfix.InstalledOn).ToUniversalTime()
            if ($date -gt $nowUtc.AddDays(1)) { continue }
            if ($null -eq $hotfixDate -or $date -gt $hotfixDate) { $hotfixDate = $date; $hotfixId = [string]$hotfix.HotFixID }
        }
    }
    catch { $hotfixError = $_.Exception.Message }
    if ($wuaError -and $hotfixError) {
        throw "WUA: $wuaError; Get-HotFix: $hotfixError"
    }
    $last = $null; $source = $null; $title = $null
    if ($null -ne $wuaDate -and ($null -eq $hotfixDate -or $wuaDate -ge $hotfixDate)) {
        $last = $wuaDate; $source = 'WindowsUpdateHistory'; $title = $wuaTitle
    }
    elseif ($null -ne $hotfixDate) {
        $last = $hotfixDate; $source = 'Get-HotFix'; $title = $hotfixId
    }
    if ($title -and $title.Length -gt 200) { $title = $title.Substring(0, 200) }
    $days = $null
    if ($null -ne $last) { $days = [Math]::Round(($nowUtc - $last).TotalDays, 1) }
    $warning = ($null -eq $days) -or ($days -gt $limit)
    $toIso = { param($d) if ($null -ne $d) { $d.ToString('o') } }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; MaximumDays = $limit; IncludeDefinitionUpdates = $includeDefinitions
        LastInstallUtc = (& $toIso $last); DaysSinceLastInstall = $days; Source = $source; LastUpdate = $title
        WuaLastInstallUtc = (& $toIso $wuaDate); WuaHistoryEntriesScanned = $scanned; WuaError = $wuaError
        HotFixLastInstallUtc = (& $toIso $hotfixDate); HotFixError = $hotfixError; Warning = $warning
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
