#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Misst die Größe temporärer Ordner (System- und optional Benutzer-Temp), ohne zu löschen.
    EN: Measures the size of temporary folders (system and optionally user temp) without deleting.
.DESCRIPTION
    DE: Summiert Dateigrößen in %SystemRoot%\Temp und optional in
        %SystemDrive%\Users\*\AppData\Local\Temp. Reparse Points (Junctions, Symlinks,
        Cloud-Platzhalter) werden weder verfolgt noch gezählt. Nicht lesbare oder
        während der Messung gelöschte Ordner werden gezählt (InaccessibleFolders).
        Ein gemeinsames Zeitbudget begrenzt die Laufzeit; bei Überschreitung ist die
        Summe eine Untergrenze (Incomplete=true). Strikt lesend: es wird nichts
        gelöscht. JSON, max. 4000 Zeichen (Ordnerliste nach Größe, wird gekürzt).
    EN: Sums file sizes in %SystemRoot%\Temp and optionally in
        %SystemDrive%\Users\*\AppData\Local\Temp. Reparse points (junctions, symlinks,
        cloud placeholders) are neither followed nor counted. Unreadable folders or
        folders deleted during the scan are counted (InaccessibleFolders). A shared
        time budget bounds the runtime; when exceeded, the total is a lower bound
        (Incomplete=true). Strictly read-only: nothing is deleted. JSON, max. 4000
        characters (folder list by size, shortened).
.PARAMETER ThresholdMB
    DE: NinjaOne Integer tempThresholdMB, 1..1048576; Standard 1024 (Gesamtsumme).
    EN: NinjaOne Integer tempThresholdMB, 1..1048576; default 1024 (grand total).
.PARAMETER IncludeUserTemp
    DE: NinjaOne Checkbox/Text tempIncludeUserProfiles, true/false; Standard false.
    EN: NinjaOne Checkbox/Text tempIncludeUserProfiles, true/false; default false.
.PARAMETER TimeBudgetSeconds
    DE: NinjaOne Integer tempTimeBudgetSeconds, 5..600; Standard 60.
    EN: NinjaOne Integer tempTimeBudgetSeconds, 5..600; default 60.
.PARAMETER MaxRecords
    DE: NinjaOne Integer tempMaxRecords, 1..100; Standard 20 (Ordner im Bericht).
    EN: NinjaOne Integer tempMaxRecords, 1..100; default 20 (folders in report).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\checkTempFolderSize.ps1
    DE: Warnt, wenn %SystemRoot%\Temp größer als 1024 MB ist.
    EN: Warns if %SystemRoot%\Temp is larger than 1024 MB.
.EXAMPLE
    .\checkTempFolderSize.ps1 -ThresholdMB 5120 -IncludeUserTemp true -TimeBudgetSeconds 120 -CustomField tempSizeReport
    DE: Inklusive Benutzer-Temp, Grenzwert 5 GB, 120 s Budget; JSON in tempSizeReport.
    EN: Including user temp, 5 GB threshold, 120 s budget; JSON to tempSizeReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Summe <= Grenzwert und vollständig gemessen, 1 = Eingabe-/Abfrage-/
        Schreibfehler, 2 = Summe > ThresholdMB oder Zeitbudget erschöpft (nicht schlüssig).
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = total <= threshold and fully measured, 1 = input/query/write error,
        2 = total > ThresholdMB or time budget exhausted (inconclusive).
#>
[CmdletBinding()]
param(
    [string]$ThresholdMB = $env:tempThresholdMB,
    [string]$IncludeUserTemp = $env:tempIncludeUserProfiles,
    [string]$TimeBudgetSeconds = $env:tempTimeBudgetSeconds,
    [string]$MaxRecords = $env:tempMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-CleanSetting {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInteger {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
        $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0}: {1}..{2} erforderlich / required.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Measure-FolderTree {
    param([string]$Path, [datetime]$Deadline)
    $result = [pscustomobject]@{ Path = $Path; Bytes = [int64]0; Files = 0; SkippedReparsePoints = 0; InaccessibleFolders = 0; Incomplete = $false }
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        if ((Get-Date) -gt $Deadline) { $result.Incomplete = $true; break }
        $current = $stack.Pop()
        try { $items = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop) }
        catch { $result.InaccessibleFolders++; continue }
        foreach ($item in $items) {
            # DE: Reparse Points nie verfolgen. EN: Never follow reparse points.
            if (([int]$item.Attributes) -band [int][IO.FileAttributes]::ReparsePoint) { $result.SkippedReparsePoints++; continue }
            if ($item.PSIsContainer) { $stack.Push([string]$item.FullName) }
            else { $result.Bytes += [int64]$item.Length; $result.Files++ }
        }
    }
    return $result
}
try {
    $threshold = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $ThresholdMB '1024') 'tempThresholdMB' 1 1048576
    $budget = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $TimeBudgetSeconds '60') 'tempTimeBudgetSeconds' 5 600
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '20') 'tempMaxRecords' 1 100
    $IncludeUserTemp = (ConvertTo-CleanSetting $IncludeUserTemp 'false').ToLowerInvariant()
    if ($IncludeUserTemp -notin @('true', 'false')) { throw 'tempIncludeUserProfiles: true/false erforderlich / required.' }
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { throw 'SystemRoot fehlt / is missing.' }
    $deadline = (Get-Date).AddSeconds($budget)
    $targets = New-Object System.Collections.Generic.List[string]
    $systemTemp = $env:SystemRoot.TrimEnd('\') + '\Temp'
    if (Test-Path -LiteralPath $systemTemp -PathType Container) { $targets.Add($systemTemp) }
    if ($IncludeUserTemp -eq 'true') {
        if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { throw 'SystemDrive fehlt / is missing.' }
        $usersRoot = $env:SystemDrive.TrimEnd('\') + '\Users'
        if (Test-Path -LiteralPath $usersRoot -PathType Container) {
            foreach ($profileDir in @(Get-ChildItem -LiteralPath $usersRoot -Force -ErrorAction Stop | Where-Object { $_.PSIsContainer })) {
                if (([int]$profileDir.Attributes) -band [int][IO.FileAttributes]::ReparsePoint) { continue }
                $userTemp = ([string]$profileDir.FullName).TrimEnd('\') + '\AppData\Local\Temp'
                if (Test-Path -LiteralPath $userTemp -PathType Container) { $targets.Add($userTemp) }
            }
        }
    }
    $results = @(foreach ($target in $targets) { Measure-FolderTree -Path $target -Deadline $deadline })
    $totalBytes = [int64]0
    foreach ($entry in $results) { $totalBytes += $entry.Bytes }
    $totalMB = [Math]::Round($totalBytes / 1MB, 1)
    $incomplete = @($results | Where-Object { $_.Incomplete }).Count -gt 0
    $folders = @($results | Sort-Object Bytes -Descending | ForEach-Object {
        [pscustomobject]@{ Path = $_.Path; SizeMB = [Math]::Round($_.Bytes / 1MB, 1); Files = $_.Files; Incomplete = $_.Incomplete }
    })
    $shown = $limit
    do {
        $records = @($folders | Select-Object -First $shown)
        $report = [ordered]@{
            ThresholdMB = $threshold; TotalMB = $totalMB; OverThreshold = ($totalMB -gt $threshold); Incomplete = $incomplete
            TimeBudgetSeconds = $budget; UserTempIncluded = ($IncludeUserTemp -eq 'true'); FoldersMeasured = $folders.Count
            SkippedReparsePoints = [int](($results | Measure-Object SkippedReparsePoints -Sum).Sum)
            InaccessibleFolders = [int](($results | Measure-Object InaccessibleFolders -Sum).Sum)
            ReportedFolders = $records.Count; Truncated = ($records.Count -lt $folders.Count); Folders = $records
        } | ConvertTo-Json -Depth 4 -Compress
        if ($report.Length -le 4000) { break }
        if ($shown -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $shown--
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($totalMB -gt $threshold -or $incomplete) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
