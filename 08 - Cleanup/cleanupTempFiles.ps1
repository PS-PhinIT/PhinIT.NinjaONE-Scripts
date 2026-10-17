#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft temporäre Dateien (Windows\Temp, optional Benutzer-Temp) und löscht optional alte Dateien.
    EN: Audits temporary files (Windows\Temp, optionally user temp folders) and optionally deletes old files.
.DESCRIPTION
    DE: Wurzeln: $env:windir\Temp und optional AppData\Local\Temp jedes Benutzerprofils. Profile stammen aus
        HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList (nur SIDs S-1-5-21-* und S-1-12-1-*,
        ProfileImagePath); fehlt der Schlüssel, werden die Unterordner von C:\Users (übergeordneter Ordner von
        $env:PUBLIC) genutzt. Spezialprofile (Public, Default, Default User, All Users, defaultuser*) und
        Reparsepunkte werden übersprungen.
        Es werden nur DATEIEN gelöscht, deren LastWriteTime UND CreationTime älter als MinimumAgeDays sind.
        Reparsepunkte (Junctions/Symlinks) werden nie verfolgt oder gelöscht; enthält ein Wurzelpfad einen
        Reparsepunkt, wird die Wurzel übersprungen. Vor jeder Löschung werden Datei und übergeordnete Ordner bis
        zur Wurzel erneut geprüft. Gesperrte Dateien werden übersprungen und als Skipped gezählt.
        Optional (RemoveEmptyFolders) werden danach LEERE Unterordner unterhalb der Temp-Wurzeln entfernt, deren
        CreationTime älter als MinimumAgeDays ist (nie die Wurzel selbst, nie rekursiv).
        Die Arbeit ist durch TimeBudgetSeconds begrenzt (Aufzählung und Löschung).
        Ohne Allow=true wird nur inventarisiert; jede Löschung je Wurzel läuft über ShouldProcess (-WhatIf).
        Bericht als JSON (je Wurzel: Kandidaten/Bytes, gelöschte Dateien/Bytes, übersprungene Dateien; max. 10 Wurzeln
        im Detail, sortiert nach Größe), optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Roots: $env:windir\Temp and optionally AppData\Local\Temp of every user profile. Profiles come from
        HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList (only SIDs S-1-5-21-* and S-1-12-1-*,
        ProfileImagePath); if the key is missing, the subfolders of C:\Users (parent of $env:PUBLIC) are used.
        Special profiles (Public, Default, Default User, All Users, defaultuser*) and reparse points are skipped.
        Only FILES whose LastWriteTime AND CreationTime are older than MinimumAgeDays are deleted.
        Reparse points (junctions/symlinks) are never followed or deleted; if a root path contains a reparse
        point, the root is skipped. Before each deletion the file and its parent folders up to the root are
        checked again. Locked files are skipped and counted as Skipped.
        Optionally (RemoveEmptyFolders) EMPTY subfolders below the temp roots whose CreationTime is older than
        MinimumAgeDays are removed afterwards (never the root itself, never recursively).
        Work is bounded by TimeBudgetSeconds (enumeration and deletion).
        Without Allow=true the script only audits; every deletion per root goes through ShouldProcess (-WhatIf).
        JSON report (per root: candidates/bytes, deleted files/bytes, skipped files; max. 10 roots in detail,
        sorted by size), optionally written to a MultiLine field (max. 4000 characters, otherwise exit 1).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupTempAllow; true/false; Standard false. Nur true löscht Dateien.
    EN: NinjaOne checkbox/text cleanupTempAllow; true/false; default false. Only true deletes files.
.PARAMETER MinimumAgeDays
    DE: NinjaOne Text cleanupTempMinimumAgeDays; ganze Zahl 1-3650; Standard 7.
    EN: NinjaOne text cleanupTempMinimumAgeDays; integer 1-3650; default 7.
.PARAMETER IncludeUserProfiles
    DE: NinjaOne Checkbox/Text cleanupTempIncludeUserProfiles; true/false; Standard true (Benutzer-Temp einbeziehen).
    EN: NinjaOne checkbox/text cleanupTempIncludeUserProfiles; true/false; default true (include user temp folders).
.PARAMETER RemoveEmptyFolders
    DE: NinjaOne Checkbox/Text cleanupTempRemoveEmptyFolders; true/false; Standard true (leere alte Unterordner entfernen).
    EN: NinjaOne checkbox/text cleanupTempRemoveEmptyFolders; true/false; default true (remove empty old subfolders).
.PARAMETER TimeBudgetSeconds
    DE: NinjaOne Text cleanupTempTimeBudgetSeconds; ganze Zahl 10-3600; Standard 300.
    EN: NinjaOne text cleanupTempTimeBudgetSeconds; integer 10-3600; default 300.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupTempFiles.ps1
    DE: Nur Inventur: zählt Dateien älter als 7 Tage, löscht nichts (Exit 2, falls Kandidaten gefunden).
    EN: Audit only: counts files older than 7 days, deletes nothing (exit 2 if candidates were found).
.EXAMPLE
    .\cleanupTempFiles.ps1 -Allow true -MinimumAgeDays 14 -WhatIf
    DE: Simuliert die Bereinigung von Dateien älter als 14 Tage; nichts wird gelöscht.
    EN: Simulates the cleanup of files older than 14 days; nothing is deleted.
.EXAMPLE
    .\cleanupTempFiles.ps1 -Allow true -IncludeUserProfiles false -CustomField tempCleanupReport
    DE: Löscht alte Dateien nur in Windows\Temp und schreibt das JSON in tempCleanupReport.
    EN: Deletes old files only in Windows\Temp and writes the JSON to tempCleanupReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts zu tun, Bereinigung erfolgreich oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat Kandidaten (Dateien oder leere Ordner) gefunden oder die Aufzählung wegen
                 des Zeitbudgets nicht abgeschlossen; oder die Bereinigung lief, aber Dateien/Ordner wurden
                 übersprungen (gesperrt/Fehler) bzw. das Zeitbudget war erschöpft.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing to do, cleanup successful or -WhatIf.
        Exit 1 = input, query or write error.
        Exit 2 = audit (Allow=false) found candidates (files or empty folders) or did not finish enumeration
                 within the time budget; or cleanup ran but files/folders were skipped (locked/error) or the time
                 budget was exhausted.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupTempAllow,
    [string]$MinimumAgeDays = $env:cleanupTempMinimumAgeDays,
    [string]$IncludeUserProfiles = $env:cleanupTempIncludeUserProfiles,
    [string]$RemoveEmptyFolders = $env:cleanupTempRemoveEmptyFolders,
    [string]$TimeBudgetSeconds = $env:cleanupTempTimeBudgetSeconds,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-Boolean {
    param([string]$Value, [string]$Name)
    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw ('{0}: true/false erforderlich / true/false required.' -f $Name) }
    return $parsed
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $parsed = 0
    if ($Value -notmatch '^\d{1,9}$' -or -not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw ('{0}: ganze Zahl {1}-{2} erforderlich / integer {1}-{2} required.' -f $Name, $Minimum, $Maximum)
    }
    return $parsed
}
function Test-IsReparsePoint {
    param([IO.FileSystemInfo]$Item)
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Get-SafeRoot {
    param([string]$Base, [string[]]$Segment)
    # DE: Jede Pfadkomponente muss existieren und darf kein Reparsepunkt sein. EN: Every component must exist and must not be a reparse point.
    $path = $Base
    $components = @($Base)
    foreach ($part in $Segment) { $path = Join-Path $path $part; $components += $path }
    foreach ($component in $components) {
        $info = [IO.DirectoryInfo]::new($component)
        if (-not $info.Exists) { return [pscustomobject]@{ Path = $path; Status = 'NotFound' } }
        if (Test-IsReparsePoint $info) { return [pscustomobject]@{ Path = $path; Status = 'ReparsePointInPath' } }
    }
    return [pscustomobject]@{ Path = $path; Status = 'OK' }
}
function Test-SafeAncestry {
    param([IO.FileSystemInfo]$Item, [string]$Root)
    $rootPath = $Root.TrimEnd('\', '/')
    $parent = if ($Item -is [IO.FileInfo]) { $Item.Directory } else { $Item.Parent }
    while ($null -ne $parent) {
        $parent.Refresh()
        if (-not $parent.Exists -or (Test-IsReparsePoint $parent)) { return $false }
        if ([string]::Equals($parent.FullName.TrimEnd('\', '/'), $rootPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        $parent = $parent.Parent
    }
    return $false
}
function Get-ProfilePath {
    $listPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $paths = @()
    if (Test-Path -LiteralPath $listPath) {
        foreach ($key in @(Get-ChildItem -LiteralPath $listPath -ErrorAction Stop)) {
            if ([string]$key.PSChildName -notmatch '^S-1-(5-21|12-1)-\d+(-\d+)*$') { continue }
            $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $path = [Environment]::ExpandEnvironmentVariables([string]$values.ProfileImagePath)
            if ($path -and [IO.Path]::IsPathRooted($path)) { $paths += $path.TrimEnd('\', '/') }
        }
    }
    else {
        $usersRoot = if ($env:PUBLIC) { Split-Path -Path $env:PUBLIC -Parent } else { Join-Path $env:SystemDrive 'Users' }
        if ($usersRoot -and (Test-Path -LiteralPath $usersRoot -PathType Container)) {
            foreach ($folder in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction Stop)) {
                if (-not (Test-IsReparsePoint $folder)) { $paths += $folder.FullName }
            }
        }
    }
    @($paths | Where-Object { (Split-Path -Path $_ -Leaf) -notmatch '^(Public|Default|Default User|All Users|defaultuser\d+)$' } | Sort-Object -Unique)
}
function Get-TempContent {
    param([string]$Root, [datetime]$Cutoff, [Diagnostics.Stopwatch]$Watch, [int]$Budget)
    $files = New-Object System.Collections.Generic.List[object]
    $folders = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    $complete = $true
    $inaccessible = 0
    while ($stack.Count -gt 0) {
        if ($Watch.Elapsed.TotalSeconds -ge $Budget) { $complete = $false; break }
        $current = $stack.Pop()
        try { $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop) }
        catch { $inaccessible++; continue }
        foreach ($child in $children) {
            # DE: Reparsepunkte nie verfolgen. EN: Never follow reparse points.
            if (Test-IsReparsePoint $child) { continue }
            if ($child.PSIsContainer) { $folders.Add($child); $stack.Push($child.FullName) }
            elseif ($child.LastWriteTimeUtc -lt $Cutoff -and $child.CreationTimeUtc -lt $Cutoff) { $files.Add($child) }
        }
    }
    [pscustomobject]@{ Files = $files.ToArray(); Folders = $folders.ToArray(); Complete = $complete; Inaccessible = $inaccessible }
}
function Test-EmptyOldFolder {
    param([IO.DirectoryInfo]$Folder, [datetime]$Cutoff, [string]$Root)
    $Folder.Refresh()
    if (-not $Folder.Exists -or (Test-IsReparsePoint $Folder) -or $Folder.CreationTimeUtc -ge $Cutoff) { return $false }
    if (-not (Test-SafeAncestry -Item $Folder -Root $Root)) { return $false }
    $enumerator = [IO.Directory]::EnumerateFileSystemEntries($Folder.FullName).GetEnumerator()
    try { return -not $enumerator.MoveNext() } finally { $enumerator.Dispose() }
}
function Export-Report {
    param([System.Collections.IDictionary]$Data, [string]$Field)
    $json = ConvertTo-Json -Depth 5 -InputObject $Data
    if ($json.Length -gt 4000) { $json = ConvertTo-Json -Depth 5 -Compress -InputObject $Data }
    Write-Output $json
    if ($Field) {
        if ($json.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $json | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}
try {
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupTempAllow'
    $days = ConvertTo-BoundedInt -Value (Resolve-Setting $MinimumAgeDays '7') -Name 'cleanupTempMinimumAgeDays' -Minimum 1 -Maximum 3650
    $includeUsers = ConvertTo-Boolean -Value (Resolve-Setting $IncludeUserProfiles 'true') -Name 'cleanupTempIncludeUserProfiles'
    $removeFolders = ConvertTo-Boolean -Value (Resolve-Setting $RemoveEmptyFolders 'true') -Name 'cleanupTempRemoveEmptyFolders'
    $budget = ConvertTo-BoundedInt -Value (Resolve-Setting $TimeBudgetSeconds '300') -Name 'cleanupTempTimeBudgetSeconds' -Minimum 10 -Maximum 3600
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    if ([string]::IsNullOrWhiteSpace($env:windir) -or -not [IO.Path]::IsPathRooted($env:windir)) { throw 'Ungültiges windir / Invalid windir.' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$days)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $rootSpecs = @([pscustomobject]@{ Type = 'System'; Base = $env:windir; Segment = @('Temp') })
    if ($includeUsers) {
        foreach ($profilePath in @(Get-ProfilePath)) { $rootSpecs += [pscustomobject]@{ Type = 'User'; Base = $profilePath; Segment = @('AppData', 'Local', 'Temp') } }
    }
    $budgetExceeded = $false
    $records = @()
    foreach ($spec in $rootSpecs) {
        $root = Get-SafeRoot -Base $spec.Base -Segment $spec.Segment
        $record = [ordered]@{
            Path = $root.Path; Type = $spec.Type; Status = $root.Status; EligibleFiles = 0; EligibleBytes = [long]0
            DeletedFiles = 0; DeletedBytes = [long]0; Skipped = 0; EmptyFolders = 0; EmptyFoldersRemoved = 0; Inaccessible = 0
        }
        $records += $record
        if ($root.Status -ne 'OK') { continue }
        if ($watch.Elapsed.TotalSeconds -ge $budget) { $budgetExceeded = $true; $record.Status = 'TimeBudgetExceeded'; continue }
        $content = Get-TempContent -Root $root.Path -Cutoff $cutoff -Watch $watch -Budget $budget
        if (-not $content.Complete) { $budgetExceeded = $true; $record.Status = 'Incomplete' }
        $record.Inaccessible = $content.Inaccessible
        $record.EligibleFiles = @($content.Files).Count
        $record.EligibleBytes = [long](@($content.Files) | Measure-Object -Property Length -Sum).Sum
        $orderedFolders = @($content.Folders | Sort-Object -Property @{ Expression = { $_.FullName.Length } } -Descending)
        if (-not $allowed) {
            if ($removeFolders) { $record.EmptyFolders = @($orderedFolders | Where-Object { Test-EmptyOldFolder -Folder $_ -Cutoff $cutoff -Root $root.Path }).Count }
            continue
        }
        if ($record.EligibleFiles -gt 0 -and $PSCmdlet.ShouldProcess($root.Path, ('{0} alte Dateien löschen / Delete {0} old files' -f $record.EligibleFiles))) {
            foreach ($file in $content.Files) {
                if ($watch.Elapsed.TotalSeconds -ge $budget) { $budgetExceeded = $true; break }
                # DE: Unmittelbar vor dem Löschen erneut prüfen. EN: Recheck immediately before deletion.
                $info = [IO.FileInfo]::new($file.FullName)
                if (-not $info.Exists) { continue }
                if ((Test-IsReparsePoint $info) -or $info.LastWriteTimeUtc -ge $cutoff -or $info.CreationTimeUtc -ge $cutoff -or -not (Test-SafeAncestry -Item $info -Root $root.Path)) {
                    $record.Skipped++
                    continue
                }
                $length = $info.Length
                try {
                    Remove-Item -LiteralPath $info.FullName -Force -ErrorAction Stop
                    $record.DeletedFiles++
                    $record.DeletedBytes += $length
                }
                catch { $record.Skipped++ }
            }
        }
        if ($removeFolders -and $orderedFolders.Count -gt 0 -and $PSCmdlet.ShouldProcess($root.Path, 'Leere alte Unterordner entfernen / Remove empty old subfolders')) {
            foreach ($folder in $orderedFolders) {
                if ($watch.Elapsed.TotalSeconds -ge $budget) { $budgetExceeded = $true; break }
                $folderInfo = [IO.DirectoryInfo]::new($folder.FullName)
                if (-not (Test-EmptyOldFolder -Folder $folderInfo -Cutoff $cutoff -Root $root.Path)) { continue }
                $record.EmptyFolders++
                # DE: Nicht rekursiv; schlägt fehl, falls nicht leer. EN: Non-recursive; fails if not empty.
                try { [IO.Directory]::Delete($folderInfo.FullName, $false); $record.EmptyFoldersRemoved++ }
                catch { $record.Skipped++ }
            }
        }
    }
    $records = @($records | ForEach-Object { [pscustomobject]$_ })
    $totalEligible = [int]($records | Measure-Object -Property EligibleFiles -Sum).Sum
    $totalEligibleBytes = [long]($records | Measure-Object -Property EligibleBytes -Sum).Sum
    $totalDeleted = [int]($records | Measure-Object -Property DeletedFiles -Sum).Sum
    $totalDeletedBytes = [long]($records | Measure-Object -Property DeletedBytes -Sum).Sum
    $totalSkipped = [int]($records | Measure-Object -Property Skipped -Sum).Sum
    $totalFolders = [int]($records | Measure-Object -Property EmptyFolders -Sum).Sum
    $totalFoldersRemoved = [int]($records | Measure-Object -Property EmptyFoldersRemoved -Sum).Sum
    $maxRecords = 10
    $shown = @($records | Sort-Object -Property @{ Expression = { $_.EligibleBytes } } -Descending | Select-Object -First $maxRecords)
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; MinimumAgeDays = $days
        IncludeUserProfiles = $includeUsers; RemoveEmptyFolders = $removeFolders; TimeBudgetSeconds = $budget
        TimeBudgetExceeded = $budgetExceeded; ElapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        RootCount = $records.Count; EligibleFiles = $totalEligible; EligibleBytes = $totalEligibleBytes
        DeletedFiles = $totalDeleted; DeletedBytes = $totalDeletedBytes; Skipped = $totalSkipped
        EmptyFolders = $totalFolders; EmptyFoldersRemoved = $totalFoldersRemoved
        RootsOmitted = [Math]::Max(0, $records.Count - $maxRecords); Roots = $shown
    })
    if (-not $allowed) {
        if ($totalEligible -gt 0 -or $totalFolders -gt 0 -or $budgetExceeded) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    if ($totalSkipped -gt 0 -or $budgetExceeded) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
