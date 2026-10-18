#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft alte Windows-Fehlerberichte (WER) und optional Absturzabbilder; löscht sie optional.
    EN: Audits old Windows Error Reporting (WER) files and optionally crash dumps; optionally deletes them.
.DESCRIPTION
    DE: Wurzeln: $env:ProgramData\Microsoft\Windows\WER\ReportArchive, ReportQueue und Temp (rekursiv, alle Dateien).
        Optional (IncludeCrashDumps): $env:windir\Minidump\*.dmp, $env:windir\MEMORY.DMP und
        $env:windir\LiveKernelReports\*.dmp (rekursiv).
        Es werden nur DATEIEN gelöscht, deren LastWriteTime UND CreationTime älter als MinimumAgeDays sind.
        Reparsepunkte werden nie verfolgt oder gelöscht; enthält ein Wurzelpfad einen Reparsepunkt, wird die
        Wurzel übersprungen. Vor jeder Löschung werden Datei und Ordnerkette bis zur Wurzel erneut geprüft.
        Gesperrte Dateien werden übersprungen (Skipped). Nach der Löschung werden unterhalb der drei WER-Wurzeln
        LEERE Berichtsordner entfernt, deren CreationTime älter als MinimumAgeDays ist (nie die Wurzel selbst,
        nicht rekursiv; nicht bei den Dump-Ordnern).
        Ohne Allow=true wird nur inventarisiert; jede Löschung je Wurzel läuft über ShouldProcess (-WhatIf).
        Bericht als JSON, optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Roots: $env:ProgramData\Microsoft\Windows\WER\ReportArchive, ReportQueue and Temp (recursive, all files).
        Optionally (IncludeCrashDumps): $env:windir\Minidump\*.dmp, $env:windir\MEMORY.DMP and
        $env:windir\LiveKernelReports\*.dmp (recursive).
        Only FILES whose LastWriteTime AND CreationTime are older than MinimumAgeDays are deleted.
        Reparse points are never followed or deleted; if a root path contains a reparse point, the root is
        skipped. Before each deletion the file and its folder chain up to the root are checked again. Locked
        files are skipped (Skipped). After deletion, EMPTY report folders below the three WER roots whose
        CreationTime is older than MinimumAgeDays are removed (never the root itself, not recursive; not for the
        dump folders).
        Without Allow=true the script only audits; every deletion per root goes through ShouldProcess (-WhatIf).
        JSON report, optionally written to a MultiLine field (max. 4000 characters, otherwise exit 1).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupWerAllow; true/false; Standard false. Nur true löscht Dateien.
    EN: NinjaOne checkbox/text cleanupWerAllow; true/false; default false. Only true deletes files.
.PARAMETER MinimumAgeDays
    DE: NinjaOne Text cleanupWerMinimumAgeDays; ganze Zahl 1-3650; Standard 14.
    EN: NinjaOne text cleanupWerMinimumAgeDays; integer 1-3650; default 14.
.PARAMETER IncludeCrashDumps
    DE: NinjaOne Checkbox/Text cleanupWerIncludeCrashDumps; true/false; Standard false. Absturzabbilder werden
        ggf. für die Fehleranalyse benötigt.
    EN: NinjaOne checkbox/text cleanupWerIncludeCrashDumps; true/false; default false. Crash dumps may be needed
        for troubleshooting.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupWindowsErrorReports.ps1
    DE: Nur Inventur der WER-Dateien älter als 14 Tage (Exit 2 bei Kandidaten).
    EN: Audit only of WER files older than 14 days (exit 2 if candidates exist).
.EXAMPLE
    .\cleanupWindowsErrorReports.ps1 -Allow true -IncludeCrashDumps true -WhatIf
    DE: Simuliert die Bereinigung inklusive Absturzabbildern; nichts wird gelöscht.
    EN: Simulates the cleanup including crash dumps; nothing is deleted.
.EXAMPLE
    .\cleanupWindowsErrorReports.ps1 -Allow true -MinimumAgeDays 30 -CustomField werCleanupReport
    DE: Löscht WER-Dateien älter als 30 Tage und schreibt das JSON in werCleanupReport.
    EN: Deletes WER files older than 30 days and writes the JSON to werCleanupReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts zu tun, Bereinigung erfolgreich oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat Kandidaten gefunden; oder die Bereinigung lief, aber Dateien/Ordner
                 wurden übersprungen (gesperrt/Fehler).
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing to do, cleanup successful or -WhatIf.
        Exit 1 = input, query or write error.
        Exit 2 = audit (Allow=false) found candidates; or cleanup ran but files/folders were skipped
                 (locked/error).
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupWerAllow,
    [string]$MinimumAgeDays = $env:cleanupWerMinimumAgeDays,
    [string]$IncludeCrashDumps = $env:cleanupWerIncludeCrashDumps,
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
function Get-CandidateContent {
    param([string]$Root, [datetime]$Cutoff, [string]$Pattern, [bool]$Recurse)
    $files = New-Object System.Collections.Generic.List[object]
    $folders = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    $inaccessible = 0
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try { $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop) }
        catch { $inaccessible++; continue }
        foreach ($child in $children) {
            if (Test-IsReparsePoint $child) { continue }
            if ($child.PSIsContainer) {
                if ($Recurse) { $folders.Add($child); $stack.Push($child.FullName) }
            }
            elseif ($child.Name -like $Pattern -and $child.LastWriteTimeUtc -lt $Cutoff -and $child.CreationTimeUtc -lt $Cutoff) { $files.Add($child) }
        }
    }
    [pscustomobject]@{ Files = $files.ToArray(); Folders = $folders.ToArray(); Inaccessible = $inaccessible }
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
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupWerAllow'
    $days = ConvertTo-BoundedInt -Value (Resolve-Setting $MinimumAgeDays '14') -Name 'cleanupWerMinimumAgeDays' -Minimum 1 -Maximum 3650
    $includeDumps = ConvertTo-Boolean -Value (Resolve-Setting $IncludeCrashDumps 'false') -Name 'cleanupWerIncludeCrashDumps'
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    if ([string]::IsNullOrWhiteSpace($env:ProgramData) -or -not [IO.Path]::IsPathRooted($env:ProgramData)) { throw 'Ungültiges ProgramData / Invalid ProgramData.' }
    if ($includeDumps -and ([string]::IsNullOrWhiteSpace($env:windir) -or -not [IO.Path]::IsPathRooted($env:windir))) { throw 'Ungültiges windir / Invalid windir.' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$days)
    $specs = @(foreach ($name in @('ReportArchive', 'ReportQueue', 'Temp')) {
        [pscustomobject]@{ Name = "WER\$name"; Base = $env:ProgramData; Segment = @('Microsoft', 'Windows', 'WER', $name); Pattern = '*'; Recurse = $true; Folders = $true }
    })
    if ($includeDumps) {
        $specs += [pscustomobject]@{ Name = 'Minidump'; Base = $env:windir; Segment = @('Minidump'); Pattern = '*.dmp'; Recurse = $false; Folders = $false }
        $specs += [pscustomobject]@{ Name = 'MEMORY.DMP'; Base = $env:windir; Segment = @(); Pattern = 'MEMORY.DMP'; Recurse = $false; Folders = $false }
        $specs += [pscustomobject]@{ Name = 'LiveKernelReports'; Base = $env:windir; Segment = @('LiveKernelReports'); Pattern = '*.dmp'; Recurse = $true; Folders = $false }
    }
    $records = @()
    foreach ($spec in $specs) {
        $root = Get-SafeRoot -Base $spec.Base -Segment $spec.Segment
        $record = [ordered]@{
            Name = $spec.Name; Path = $root.Path; Status = $root.Status; EligibleFiles = 0; EligibleBytes = [long]0
            DeletedFiles = 0; DeletedBytes = [long]0; Skipped = 0; EmptyFoldersRemoved = 0
        }
        $records += $record
        if ($root.Status -ne 'OK') { continue }
        $content = Get-CandidateContent -Root $root.Path -Cutoff $cutoff -Pattern $spec.Pattern -Recurse $spec.Recurse
        $record.EligibleFiles = @($content.Files).Count
        $record.EligibleBytes = [long](@($content.Files) | Measure-Object -Property Length -Sum).Sum
        if (-not $allowed) { continue }
        if ($record.EligibleFiles -gt 0 -and $PSCmdlet.ShouldProcess($root.Path, ('{0} alte Dateien löschen / Delete {0} old files' -f $record.EligibleFiles))) {
            foreach ($file in $content.Files) {
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
            if ($spec.Folders) {
                foreach ($folder in @($content.Folders | Sort-Object -Property @{ Expression = { $_.FullName.Length } } -Descending)) {
                    $folderInfo = [IO.DirectoryInfo]::new($folder.FullName)
                    if (-not (Test-EmptyOldFolder -Folder $folderInfo -Cutoff $cutoff -Root $root.Path)) { continue }
                    try { [IO.Directory]::Delete($folderInfo.FullName, $false); $record.EmptyFoldersRemoved++ }
                    catch { $record.Skipped++ }
                }
            }
        }
    }
    $records = @($records | ForEach-Object { [pscustomobject]$_ })
    $totalEligible = [int]($records | Measure-Object -Property EligibleFiles -Sum).Sum
    $totalSkipped = [int]($records | Measure-Object -Property Skipped -Sum).Sum
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; MinimumAgeDays = $days
        IncludeCrashDumps = $includeDumps; EligibleFiles = $totalEligible
        EligibleBytes = [long]($records | Measure-Object -Property EligibleBytes -Sum).Sum
        DeletedFiles = [int]($records | Measure-Object -Property DeletedFiles -Sum).Sum
        DeletedBytes = [long]($records | Measure-Object -Property DeletedBytes -Sum).Sum
        Skipped = $totalSkipped; EmptyFoldersRemoved = [int]($records | Measure-Object -Property EmptyFoldersRemoved -Sum).Sum
        Roots = $records
    })
    if (-not $allowed) {
        if ($totalEligible -gt 0) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    if ($totalSkipped -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
