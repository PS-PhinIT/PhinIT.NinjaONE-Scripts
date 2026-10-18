#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Papierkörbe aller Benutzer auf lokalen Festplatten und leert optional alte Elemente.
    EN: Audits the recycle bins of all users on local fixed drives and optionally removes old items.
.DESCRIPTION
    DE: Laufwerke: Get-CimInstance Win32_LogicalDisk mit DriveType=3 (lokale Festplatten). Je Laufwerk werden die
        SID-Unterordner von <Laufwerk>\$Recycle.Bin gelesen. Ein Element besteht aus der Metadatendatei $I<id> und
        dem Inhalt $R<id> (Datei oder Ordner). Ist die LastWriteTime der $I-Datei älter als MinimumAgeDays
        (0 = alle Elemente), werden $R und danach $I gelöscht. $R-Ordner werden rekursiv gelöscht, Reparsepunkte
        darin werden dabei NIE verfolgt: nur der Link selbst wird entfernt, das Ziel bleibt unberührt.
        Enthält der Pfad Laufwerk\$Recycle.Bin\<SID> einen Reparsepunkt, wird er übersprungen.
        Ohne Allow=true wird nur inventarisiert; jede Löschung je Laufwerk läuft über ShouldProcess (-WhatIf).
        Bericht als JSON (je Laufwerk), optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Drives: Get-CimInstance Win32_LogicalDisk with DriveType=3 (local fixed disks). For each drive the SID
        subfolders of <drive>\$Recycle.Bin are read. An item consists of the metadata file $I<id> and the
        content $R<id> (file or folder). If the LastWriteTime of the $I file is older than MinimumAgeDays
        (0 = all items), $R and then $I are deleted. $R folders are deleted recursively; reparse points inside are
        NEVER followed: only the link itself is removed, its target is left untouched.
        If the path drive\$Recycle.Bin\<SID> contains a reparse point, it is skipped.
        Without Allow=true the script only audits; every deletion per drive goes through ShouldProcess (-WhatIf).
        JSON report (per drive), optionally written to a MultiLine field (max. 4000 characters, otherwise exit 1).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupRecycleBinAllow; true/false; Standard false. Nur true löscht Elemente.
    EN: NinjaOne checkbox/text cleanupRecycleBinAllow; true/false; default false. Only true deletes items.
.PARAMETER MinimumAgeDays
    DE: NinjaOne Text cleanupRecycleBinMinimumAgeDays; ganze Zahl 0-3650; Standard 30; 0 = alle Elemente.
    EN: NinjaOne text cleanupRecycleBinMinimumAgeDays; integer 0-3650; default 30; 0 = all items.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupRecycleBin.ps1
    DE: Nur Inventur der Papierkorbelemente älter als 30 Tage (Exit 2 bei Kandidaten).
    EN: Audit only of recycle bin items older than 30 days (exit 2 if candidates exist).
.EXAMPLE
    .\cleanupRecycleBin.ps1 -Allow true -MinimumAgeDays 0 -WhatIf
    DE: Simuliert das vollständige Leeren aller Papierkörbe; nichts wird gelöscht.
    EN: Simulates emptying all recycle bins completely; nothing is deleted.
.EXAMPLE
    .\cleanupRecycleBin.ps1 -Allow true -CustomField recycleBinReport
    DE: Löscht Elemente älter als 30 Tage und schreibt das JSON in recycleBinReport.
    EN: Deletes items older than 30 days and writes the JSON to recycleBinReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts zu tun, Bereinigung erfolgreich oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat alte Elemente gefunden; oder die Bereinigung lief, aber mindestens ein
                 Element konnte nicht (vollständig) gelöscht werden.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing to do, cleanup successful or -WhatIf.
        Exit 1 = input, query or write error.
        Exit 2 = audit (Allow=false) found old items; or cleanup ran but at least one item could not be
                 (completely) deleted.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupRecycleBinAllow,
    [string]$MinimumAgeDays = $env:cleanupRecycleBinMinimumAgeDays,
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
function Test-SafeChain {
    param([string]$Path, [string]$Anchor)
    # DE: Pfad bis zum Anker frisch prüfen (keine Reparsepunkte). EN: Freshly verify the path up to the anchor (no reparse points).
    $anchorPath = $Anchor.TrimEnd('\', '/')
    $current = [IO.DirectoryInfo]::new($Path)
    while ($null -ne $current) {
        if ([string]::Equals($current.FullName.TrimEnd('\', '/'), $anchorPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (-not $current.Exists -or (Test-IsReparsePoint $current)) { return $false }
        $current = $current.Parent
    }
    return $false
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
function Get-ItemSize {
    param([IO.FileSystemInfo]$Item)
    if ($Item -is [IO.FileInfo]) { return [long]$Item.Length }
    if (Test-IsReparsePoint $Item) { return [long]0 }
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Item)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($child in @($current.GetFileSystemInfos())) {
            if (Test-IsReparsePoint $child) { continue }
            if ($child -is [IO.DirectoryInfo]) { $stack.Push($child) } else { $total += $child.Length }
        }
    }
    return $total
}
function Invoke-SafeTreeDelete {
    param([IO.FileSystemInfo]$Item, [string]$Anchor)
    # DE: Reparsepunkte nur als Link entfernen, nie verfolgen. EN: Remove reparse points as links only, never follow them.
    if (Test-IsReparsePoint $Item) {
        if ($Item -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($Item.FullName, $false) } else { [IO.File]::Delete($Item.FullName) }
        return
    }
    if ($Item -is [IO.FileInfo]) { Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction Stop; return }
    $folders = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Item)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if (-not (Test-SafeChain -Path $current.FullName -Anchor $Anchor)) { throw 'Unsicherer Papierkorbpfad / Unsafe recycle bin path.' }
        $folders.Add($current)
        foreach ($child in @($current.GetFileSystemInfos())) {
            if (Test-IsReparsePoint $child) {
                if ($child -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($child.FullName, $false) } else { [IO.File]::Delete($child.FullName) }
            }
            elseif ($child -is [IO.DirectoryInfo]) { $stack.Push($child) }
            else {
                if (-not (Test-SafeChain -Path $current.FullName -Anchor $Anchor)) { throw 'Unsicherer Papierkorbpfad / Unsafe recycle bin path.' }
                Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop
            }
        }
    }
    for ($index = $folders.Count - 1; $index -ge 0; $index--) {
        $folder = $folders[$index]
        $folder.Refresh()
        if ($folder.Attributes -band [IO.FileAttributes]::ReadOnly) { $folder.Attributes = $folder.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
        [IO.Directory]::Delete($folder.FullName, $false)
    }
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
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupRecycleBinAllow'
    $days = ConvertTo-BoundedInt -Value (Resolve-Setting $MinimumAgeDays '30') -Name 'cleanupRecycleBinMinimumAgeDays' -Minimum 0 -Maximum 3650
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $cutoff = [DateTime]::UtcNow.AddDays(-$days)
    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)
    $records = @()
    foreach ($disk in $disks) {
        $device = ([string]$disk.DeviceID).TrimEnd('\', '/')
        if (-not $device) { continue }
        $bin = Get-SafeRoot -Base ($device + [IO.Path]::DirectorySeparatorChar) -Segment @('$Recycle.Bin')
        $record = [ordered]@{
            Drive = [string]$disk.DeviceID; Status = $bin.Status; UserBins = 0; EligibleItems = 0; EligibleBytes = [long]0
            DeletedItems = 0; DeletedBytes = [long]0; Failed = 0; SkippedReparsePoints = 0
        }
        $records += $record
        if ($bin.Status -ne 'OK') { continue }
        $candidates = @()
        foreach ($userBin in @(Get-ChildItem -LiteralPath $bin.Path -Directory -Force -ErrorAction Stop)) {
            if ($userBin.Name -notmatch '^S-1-[\d-]+$') { continue }
            if (Test-IsReparsePoint $userBin) { $record.SkippedReparsePoints++; continue }
            $record.UserBins++
            foreach ($meta in @(Get-ChildItem -LiteralPath $userBin.FullName -File -Force -Filter '$I*' -ErrorAction Stop)) {
                if (-not $meta.Name.StartsWith('$I', [StringComparison]::OrdinalIgnoreCase) -or (Test-IsReparsePoint $meta)) { continue }
                if ($days -gt 0 -and $meta.LastWriteTimeUtc -ge $cutoff) { continue }
                $contentPath = Join-Path $userBin.FullName ('$R' + $meta.Name.Substring(2))
                $content = $null
                if ([IO.Directory]::Exists($contentPath)) { $content = [IO.DirectoryInfo]::new($contentPath) }
                elseif ([IO.File]::Exists($contentPath)) { $content = [IO.FileInfo]::new($contentPath) }
                $size = [long]0
                if ($null -ne $content) { $size = Get-ItemSize -Item $content }
                $candidates += [pscustomobject]@{ Meta = $meta; Content = $content; Size = $size; Bin = $userBin.FullName }
            }
        }
        $record.EligibleItems = $candidates.Count
        $record.EligibleBytes = [long]($candidates | Measure-Object -Property Size -Sum).Sum
        if (-not $allowed -or $candidates.Count -eq 0) { continue }
        if (-not $PSCmdlet.ShouldProcess($bin.Path, ('{0} Papierkorbelemente löschen / Delete {0} recycle bin items' -f $candidates.Count))) { continue }
        foreach ($candidate in $candidates) {
            try {
                # DE: Benutzerordner unmittelbar vorher erneut prüfen. EN: Recheck the user bin immediately before deletion.
                $binInfo = [IO.DirectoryInfo]::new($candidate.Bin)
                if (-not $binInfo.Exists -or (Test-IsReparsePoint $binInfo)) { throw 'Unsicherer Papierkorbpfad / Unsafe recycle bin path.' }
                if ($null -ne $candidate.Content) {
                    $candidate.Content.Refresh()
                    if ($candidate.Content.Exists) { Invoke-SafeTreeDelete -Item $candidate.Content -Anchor $bin.Path }
                }
                $candidate.Meta.Refresh()
                if ($candidate.Meta.Exists) { Remove-Item -LiteralPath $candidate.Meta.FullName -Force -ErrorAction Stop }
                $record.DeletedItems++
                $record.DeletedBytes += $candidate.Size
            }
            catch { $record.Failed++ }
        }
    }
    $records = @($records | ForEach-Object { [pscustomobject]$_ })
    $totalEligible = [int]($records | Measure-Object -Property EligibleItems -Sum).Sum
    $totalFailed = [int]($records | Measure-Object -Property Failed -Sum).Sum
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; MinimumAgeDays = $days
        EligibleItems = $totalEligible; EligibleBytes = [long]($records | Measure-Object -Property EligibleBytes -Sum).Sum
        DeletedItems = [int]($records | Measure-Object -Property DeletedItems -Sum).Sum
        DeletedBytes = [long]($records | Measure-Object -Property DeletedBytes -Sum).Sum
        Failed = $totalFailed; Drives = @($records | Select-Object -First 26)
    })
    if (-not $allowed) {
        if ($totalEligible -gt 0) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    if ($totalFailed -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
