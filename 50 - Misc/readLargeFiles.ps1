#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet die größten Dateien unter einem lokalen Pfad (nur Bericht, kein Löschen).
    EN: Reports the largest files under a local path (report only, no deletion).
.DESCRIPTION
    DE: Durchsucht RootPath (absoluter Pfad auf einem festen lokalen Laufwerk,
        Win32_LogicalDisk DriveType 3; kein UNC, keine "."/".."-Segmente) und meldet die
        Top-N-Dateien nach Größe (Pfad, MB, Änderungsdatum UTC). Reparse Points
        (Junctions, Symlinks, Cloud-/Dedup-Platzhalter) werden weder verfolgt noch
        gezählt. Zeitbudget und maximale Dateianzahl begrenzen die Laufzeit; wird eine
        Grenze erreicht, ist das Ergebnis unvollständig (Truncated=true, Exit 2).
        Nicht lesbare Ordner werden gezählt. Pfade können Benutzernamen enthalten.
        JSON, max. 4000 Zeichen (Liste wird gekürzt). Strikt lesend.
    EN: Scans RootPath (absolute path on a fixed local drive, Win32_LogicalDisk
        DriveType 3; no UNC, no "."/".." segments) and reports the top N files by size
        (path, MB, last write UTC). Reparse points (junctions, symlinks, cloud/dedup
        placeholders) are neither followed nor counted. Time budget and maximum file
        count bound the runtime; when a limit is hit the result is incomplete
        (Truncated=true, exit 2). Unreadable folders are counted. Paths may contain
        user names. JSON, max. 4000 characters (list is shortened). Strictly read-only.
.PARAMETER RootPath
    DE: NinjaOne Text largeFilesRootPath, absoluter lokaler Pfad; Standard C:\.
    EN: NinjaOne Text largeFilesRootPath, absolute local path; default C:\.
.PARAMETER Top
    DE: NinjaOne Integer largeFilesTop, 1..100; Standard 20.
    EN: NinjaOne Integer largeFilesTop, 1..100; default 20.
.PARAMETER TimeBudgetSeconds
    DE: NinjaOne Integer largeFilesTimeBudgetSeconds, 5..900; Standard 120.
    EN: NinjaOne Integer largeFilesTimeBudgetSeconds, 5..900; default 120.
.PARAMETER MaxFiles
    DE: NinjaOne Integer largeFilesMaxFiles, 1000..5000000; Standard 500000.
    EN: NinjaOne Integer largeFilesMaxFiles, 1000..5000000; default 500000.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readLargeFiles.ps1
    DE: Top 20 der größten Dateien unter C:\ (max. 120 s, 500000 Dateien).
    EN: Top 20 largest files under C:\ (max. 120 s, 500000 files).
.EXAMPLE
    .\readLargeFiles.ps1 -RootPath 'D:\Data' -Top 10 -TimeBudgetSeconds 300 -CustomField largeFilesReport
    DE: Top 10 unter D:\Data mit 300 s Budget; JSON in largeFilesReport.
    EN: Top 10 under D:\Data with a 300 s budget; JSON to largeFilesReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = vollständig durchsucht (informativ), 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = durch Zeitbudget oder MaxFiles gekürzt (Ergebnis unvollständig).
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = fully scanned (informational), 1 = input/query/write error,
        2 = truncated by time budget or MaxFiles (incomplete result).
#>
[CmdletBinding()]
param(
    [string]$RootPath = $env:largeFilesRootPath,
    [string]$Top = $env:largeFilesTop,
    [string]$TimeBudgetSeconds = $env:largeFilesTimeBudgetSeconds,
    [string]$MaxFiles = $env:largeFilesMaxFiles,
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
try {
    $RootPath = ConvertTo-CleanSetting $RootPath 'C:\'
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $Top '20') 'largeFilesTop' 1 100
    $budget = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $TimeBudgetSeconds '120') 'largeFilesTimeBudgetSeconds' 5 900
    $fileLimit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxFiles '500000') 'largeFilesMaxFiles' 1000 5000000
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($RootPath.Length -gt 240 -or $RootPath -notmatch '^[A-Za-z]:\\(?:[^\\/:*?"<>|\x00-\x1F]+(?:\\|$))*$' -or $RootPath -match '(?:^|\\)\.{1,2}(?:\\|$)') {
        throw 'largeFilesRootPath: absoluter lokaler Pfad erforderlich (z. B. C:\) / absolute local path required (e.g. C:\).'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $drive = $RootPath.Substring(0, 2).ToUpperInvariant()
    $disk = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID = '{0}'" -f $drive) -ErrorAction Stop) | Select-Object -First 1
    if ($null -eq $disk -or [int]$disk.DriveType -ne 3) { throw 'Kein festes lokales Laufwerk / Not a fixed local drive.' }
    $root = Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop
    if ($root.PSProvider.Name -ne 'FileSystem' -or -not $root.PSIsContainer) { throw 'Kein Ordner / Not a folder.' }
    $reparse = [int][IO.FileAttributes]::ReparsePoint
    if (([int]$root.Attributes) -band $reparse) { throw 'Stammpfad ist ein Reparse Point / Root is a reparse point.' }
    $deadline = (Get-Date).AddSeconds($budget)
    $topFiles = New-Object System.Collections.Generic.List[object]
    $minBytes = [int64]-1
    $scanned = 0; $skipped = 0; $inaccessible = 0; $stopReason = ''
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push([string]$root.FullName)
    while ($stack.Count -gt 0 -and -not $stopReason) {
        if ((Get-Date) -gt $deadline) { $stopReason = 'TimeBudget'; break }
        $current = $stack.Pop()
        try { $items = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop) }
        catch { $inaccessible++; continue }
        foreach ($item in $items) {
            # DE: Reparse Points nie verfolgen. EN: Never follow reparse points.
            if (([int]$item.Attributes) -band $reparse) { $skipped++; continue }
            if ($item.PSIsContainer) { $stack.Push([string]$item.FullName); continue }
            $scanned++
            $bytes = [int64]$item.Length
            if ($topFiles.Count -lt $limit -or $bytes -gt $minBytes) {
                $topFiles.Add([pscustomobject]@{ Path = [string]$item.FullName; Bytes = $bytes; LastWriteUtc = $item.LastWriteTimeUtc })
                if ($topFiles.Count -gt $limit) {
                    $smallest = $topFiles | Sort-Object Bytes | Select-Object -First 1
                    [void]$topFiles.Remove($smallest)
                }
                $minBytes = ($topFiles | Measure-Object Bytes -Minimum).Minimum
            }
            if ($scanned -ge $fileLimit) { $stopReason = 'MaxFiles'; break }
        }
    }
    $truncated = [bool]$stopReason
    $ranked = @($topFiles | Sort-Object Bytes -Descending | ForEach-Object {
        $time = ''
        if ($_.LastWriteUtc -is [datetime]) { $time = $_.LastWriteUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        [pscustomobject]@{ Path = ($_.Path -replace '[\x00-\x1F\x7F]', ''); SizeMB = [Math]::Round($_.Bytes / 1MB, 1); LastWriteUtc = $time }
    })
    $shown = $ranked.Count
    do {
        $records = @($ranked | Select-Object -First $shown)
        $report = [ordered]@{
            RootPath = $RootPath; Top = $limit; FilesScanned = $scanned; SkippedReparsePoints = $skipped; InaccessibleFolders = $inaccessible
            TimeBudgetSeconds = $budget; MaxFiles = $fileLimit; Truncated = $truncated; StopReason = $stopReason
            ReportedFiles = $records.Count; ListShortened = ($records.Count -lt $ranked.Count); Files = $records
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
    if ($truncated) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
