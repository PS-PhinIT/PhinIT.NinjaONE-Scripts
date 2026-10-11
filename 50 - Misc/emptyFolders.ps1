#Requires -Version 5.1
<#
.SYNOPSIS
    DE: Meldet leere Ordner unter einem ausdrücklich konfigurierten Pfad.
    EN: Reports empty folders under an explicitly configured path.
.DESCRIPTION
    DE: Strikt lesend: kein Löschen, keine Erstellung. Ohne Pfad keine Aktion.
        Leer bedeutet keine direkten Einträge, einschließlich versteckter.
        Reparse Points werden nicht verfolgt. Zugriffsfehler sind Fehler,
        keine leeren Ordner. Ergebnisse sind eine Momentaufnahme.
    EN: Strictly read-only: no deletion or creation. No path means no action.
        Empty means no direct entries, including hidden entries.
        Reparse points are not followed. Access failures are errors,
        not empty folders. Results are a point-in-time snapshot.
.PARAMETER RootPath
    DE: Bestehender absoluter lokaler/UNC-Dateisystempfad; emptyFoldersRootPath.
    EN: Existing absolute local/UNC filesystem path; emptyFoldersRootPath.
.PARAMETER MaxFolders
    DE: Maximal geprüfte Ordner, 1..10000; emptyFoldersMaxFolders, Standard 1000.
    EN: Maximum folders inspected, 1..10000; emptyFoldersMaxFolders, default 1000.
.PARAMETER MaxRecords
    DE: Maximal ausgegebene Pfade, 1..100; emptyFoldersMaxRecords, Standard 25.
    EN: Maximum reported paths, 1..100; emptyFoldersMaxRecords, default 25.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen;
        leere Werte verwenden Standards. Maximal 4000 Zeichen.
        Exit 0 = Erfolg/keine Aktion, 1 = Fehler, 2 = gekürzt/Links übersprungen.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment;
        empty values use defaults. At most 4000 characters.
        Exit 0 = success/no action, 1 = error, 2 = truncated/links skipped.
#>
[CmdletBinding()]
param(
    [string]$RootPath = $env:emptyFoldersRootPath,
    [string]$MaxFolders = $env:emptyFoldersMaxFolders,
    [string]$MaxRecords = $env:emptyFoldersMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $RootPath = $RootPath.Trim()
    $MaxFolders = $MaxFolders.Trim()
    $MaxRecords = $MaxRecords.Trim()
    $CustomField = $CustomField.Trim()
    if ($RootPath -eq 'null') { $RootPath = '' }
    if ($MaxFolders -eq 'null') { $MaxFolders = '' }
    if ($MaxRecords -eq 'null') { $MaxRecords = '' }
    if ($CustomField -eq 'null') { $CustomField = '' }
    if (-not $MaxFolders) { $MaxFolders = '1000' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    $scanLimit = 0
    $recordLimit = 0
    if (-not [int]::TryParse($MaxFolders, [ref]$scanLimit) -or $scanLimit -lt 1 -or $scanLimit -gt 10000) {
        throw 'MaxFolders muss 1..10000 sein / MaxFolders must be 1..10000.'
    }
    if (-not [int]::TryParse($MaxRecords, [ref]$recordLimit) -or $recordLimit -lt 1 -or $recordLimit -gt 100) {
        throw 'MaxRecords muss 1..100 sein / MaxRecords must be 1..100.'
    }
    if (-not $RootPath) {
        Write-Output 'Keine Aktion: emptyFoldersRootPath fehlt / No action: emptyFoldersRootPath is not configured.'
        exit 0
    }
    if ($RootPath -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') {
        throw 'Absoluter Windows-Dateisystempfad erforderlich / Absolute Windows filesystem path required.'
    }
    $root = Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop
    if ($root.PSProvider.Name -ne 'FileSystem' -or -not $root.PSIsContainer) {
        throw 'RootPath muss ein bestehender Ordner sein / RootPath must be an existing folder.'
    }
    # DE: Auch konfigurierte Pfade dürfen nicht über einen Link führen.
    # EN: Even the configured path must not traverse an ancestor link.
    $ancestor = $root
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw 'RootPath enthält einen Reparse Point / RootPath contains a reparse point.'
        }
        $ancestor = $ancestor.Parent
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($root.FullName)
    $scanned = 0
    $emptyCount = 0
    $skippedLinks = 0
    $records = @()
    while ($queue.Count -gt 0 -and $scanned -lt $scanLimit) {
        $path = $queue.Dequeue()
        $folder = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($folder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $skippedLinks++
            continue
        }
        $children = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop)
        $scanned++
        if ($children.Count -eq 0) {
            $emptyCount++
            if ($records.Count -lt $recordLimit) { $records += $path }
        }
        foreach ($child in $children) {
            if ($child.PSIsContainer) {
                if ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $skippedLinks++ }
                else { $queue.Enqueue($child.FullName) }
            }
        }
    }
    do {
        $truncated = $queue.Count -gt 0 -or $records.Count -lt $emptyCount
        $report = [ordered]@{
            RootPath = $root.FullName; ScannedFolders = $scanned
            EmptyFoldersFoundInScan = $emptyCount; ReportedRecords = $records.Count
            ScanComplete = ($queue.Count -eq 0 -and $skippedLinks -eq 0)
            RemainingQueuedFolders = $queue.Count; SkippedReparsePoints = $skippedLinks
            Truncated = $truncated; EmptyFolders = $records
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
    if ($truncated -or $skippedLinks -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}