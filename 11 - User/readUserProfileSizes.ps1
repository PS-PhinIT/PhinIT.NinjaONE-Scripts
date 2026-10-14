#Requires -Version 5.1

<#
.SYNOPSIS
DE: Groesse der Benutzerprofilordner zeitbegrenzt messen. EN: Measure user profile folder sizes within a time budget.
.DESCRIPTION
DE: Summiert Dateigroessen je Profilordner (Win32_UserProfile.LocalPath, ohne Systemprofile) mit
einem gesamten Zeitbudget. Reparse-Punkte (Junctions, Symlinks, OneDrive-Platzhalter) werden
uebersprungen und gezaehlt, daher koennen Cloud-Dateien fehlen. Ist das Budget erschoepft, werden
Profile als partial (Untergrenze) bzw. notScanned markiert. Nicht lesbare Ordner werden gezaehlt.
EN: Sums file sizes per profile folder (Win32_UserProfile.LocalPath, special profiles excluded)
within a total time budget. Reparse points (junctions, symlinks, OneDrive placeholders) are skipped
and counted, so cloud files may be missing. When the budget is exhausted, profiles are marked
partial (lower bound) or notScanned. Unreadable folders are counted.
DE: Nur lesend; nur Ordnername statt Pfad, keine Dateinamen oder SIDs. Logische Groesse, nicht Platz auf dem Datentraeger.
EN: Read-only; folder name instead of path, no file names or SIDs. Logical size, not size on disk.
.PARAMETER TimeBudgetSeconds
DE: NinjaOne userProfileSizeBudgetSeconds (Integer), 5..900; Standard 60. Gesamtbudget fuer alle Profile.
EN: NinjaOne userProfileSizeBudgetSeconds (integer), 5..900; default 60. Total budget for all profiles.
.PARAMETER ThresholdGB
DE: NinjaOne userProfileSizeThresholdGB (Dezimal, Punkt), 0.01..100000; Standard 20.
EN: NinjaOne userProfileSizeThresholdGB (decimal, dot), 0.01..100000; default 20.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\readUserProfileSizes.ps1
DE: Groessen mit 60 s Budget; Exit 2 ueber 20 GB. EN: Sizes with a 60 s budget; exit 2 above 20 GB.
.EXAMPLE
.\readUserProfileSizes.ps1 -TimeBudgetSeconds 300 -ThresholdGB 7.5 -CustomField profileSizes
DE: 300 s Budget, Grenze 7,5 GB; JSON in profileSizes. EN: 300 s budget, 7.5 GB limit; JSON to profileSizes.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = kein Profil ueber der Grenze, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein Profil (auch partial) ueber ThresholdGB.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no profile above the limit, 1 = input/query/write error, 2 = at least one profile (also partial) above ThresholdGB.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TimeBudgetSeconds = $env:userProfileSizeBudgetSeconds,
    [string]$ThresholdGB = $env:userProfileSizeThresholdGB,
    [string]$MaxRecords = $env:userMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputValue {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0} must be {1}..{2} / muss {1}..{2} sein.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Measure-ProfileFolder {
    param([string]$Path, [System.Diagnostics.Stopwatch]$Clock, [double]$BudgetMs)
    $result = @{ bytes = [long]0; files = [long]0; inaccessible = 0; reparse = 0; partial = $false }
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    $reparseFlag = [int][IO.FileAttributes]::ReparsePoint
    while ($stack.Count -gt 0 -and -not $result.partial) {
        $directory = $stack.Pop()
        try {
            foreach ($item in ([IO.DirectoryInfo]$directory).EnumerateFileSystemInfos()) {
                if ($Clock.Elapsed.TotalMilliseconds -ge $BudgetMs) { $result.partial = $true; break }
                # DE: Reparse-Punkte nie verfolgen (Schleifen/Doppelzaehlung). EN: Never follow reparse points (loops/double counting).
                if (([int]$item.Attributes -band $reparseFlag) -ne 0) { $result.reparse++; continue }
                if ($item -is [IO.DirectoryInfo]) { $stack.Push($item.FullName) }
                else { $result.bytes += $item.Length; $result.files++ }
            }
        } catch { $result.inaccessible++ }
        if ($Clock.Elapsed.TotalMilliseconds -ge $BudgetMs -and $stack.Count -gt 0) { $result.partial = $true }
    }
    return $result
}
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([System.Collections.IDictionary]$Report, [int]$Limit, [string]$Field)
    $all = @($Report['records'])
    $count = [Math]::Min($all.Count, $Limit)
    while ($true) {
        $Report['records'] = @($all | Select-Object -First $count)
        $Report['returned'] = $count
        $Report['truncated'] = ($count -lt $all.Count)
        $content = ConvertTo-Json -InputObject $Report -Depth 5
        if ($content.Length -le 4000 -or $count -eq 0) { break }
        $count--
    }
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $budget = ConvertTo-BoundedInt -Value (Get-InputValue $TimeBudgetSeconds '60') -Name 'userProfileSizeBudgetSeconds' -Minimum 5 -Maximum 900
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $ThresholdGB = Get-InputValue $ThresholdGB '20'
    $thresholdValue = 0.0
    if ($ThresholdGB -notmatch '^\d{1,6}(\.\d{1,3})?$' -or -not [double]::TryParse($ThresholdGB, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$thresholdValue) -or $thresholdValue -lt 0.01 -or $thresholdValue -gt 100000) {
        throw 'userProfileSizeThresholdGB must be 0.01..100000 / muss 0.01..100000 sein.'
    }
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $thresholdBytes = $thresholdValue * 1GB
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and $_.LocalPath } | Sort-Object LocalPath)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $budgetMs = $budget * 1000.0
    $records = @(foreach ($userProfile in $profiles) {
        $path = [string]$userProfile.LocalPath
        $record = [ordered]@{
            profileFolder = (($path.TrimEnd('\', '/') -split '[\\/]')[-1]); loaded = [bool]$userProfile.Loaded
            sizeGB = 0; fileCount = 0; partial = $false; notScanned = $false; missing = $false
            inaccessibleDirectories = 0; skippedReparsePoints = 0; aboveThreshold = $false
        }
        if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) {
            $record.missing = $true
        } elseif ($clock.Elapsed.TotalMilliseconds -ge $budgetMs) {
            $record.notScanned = $true
            $record.partial = $true
        } else {
            $measure = Measure-ProfileFolder -Path $path -Clock $clock -BudgetMs $budgetMs
            $record.sizeGB = [Math]::Round($measure.bytes / 1GB, 2)
            $record.fileCount = $measure.files
            $record.partial = $measure.partial
            $record.inaccessibleDirectories = $measure.inaccessible
            $record.skippedReparsePoints = $measure.reparse
            $record.aboveThreshold = ($measure.bytes -gt $thresholdBytes)
        }
        [pscustomobject]$record
    })
    $clock.Stop()
    $sorted = @($records | Sort-Object @{ Expression = 'sizeGB'; Descending = $true }, profileFolder)
    $above = @($records | Where-Object { $_.aboveThreshold })
    $report = [ordered]@{
        check = 'User profile sizes / Profilgroessen'; thresholdGB = $thresholdValue; timeBudgetSeconds = $budget
        elapsedSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
        budgetExhausted = (@($records | Where-Object { $_.partial }).Count -gt 0)
        aboveThresholdCount = $above.Count
        total = $sorted.Count; returned = 0; truncated = $false; records = $sorted
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($above.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
