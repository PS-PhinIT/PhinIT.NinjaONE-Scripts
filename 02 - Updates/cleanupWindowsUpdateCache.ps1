#Requires -Version 5.1

<#
.SYNOPSIS
DE: Downloadcache prüfen; optional alte Dateien gezielt bereinigen.
EN: Audit the download cache; optionally clean up selected old files.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. Änderungen nur mit AllowCleanup=true und ShouldProcess.
EN: Windows SYSTEM, 64-bit. Changes require AllowCleanup=true and ShouldProcess.
DE: Nur Dateien unter SoftwareDistribution\Download; keine Ordner/Reparsepunkte löschen.
EN: Only files under SoftwareDistribution\Download; never delete folders/reparse points.
DE: Keine laufende Updateinstallation unterbrechen. Dienstzustände werden wiederhergestellt.
EN: Do not run during update installation. Service running states are restored.
DE: MultiLine-CustomField speichert Klartext-JSON; maximal 4000 Zeichen.
EN: MultiLine CustomField stores plain-text JSON; maximum 4000 characters.
.PARAMETER AllowCleanup
DE: String mit Boolean-Wert true/false; NinjaOne updateCacheAllowCleanup; Standard false; explizite Zustimmung erforderlich.
EN: String containing Boolean true/false; NinjaOne updateCacheAllowCleanup; default false; explicit opt-in required.
.PARAMETER MinimumAgeDays
DE: String; NinjaOne updateCacheMinimumAgeDays; Standard 30; ganze Zahl 7-3650.
EN: String; NinjaOne updateCacheMinimumAgeDays; default 30; integer 7-3650.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\cleanupWindowsUpdateCache.ps1 -MinimumAgeDays 30
DE: Nur Inventur: zählt Cachedateien älter als 30 Tage, löscht nichts.
EN: Audit only: counts cache files older than 30 days, deletes nothing.
.EXAMPLE
.\cleanupWindowsUpdateCache.ps1 -AllowCleanup true -MinimumAgeDays 60 -WhatIf
DE: Simuliert die Bereinigung von Dateien älter als 60 Tage; keine Dienste/Dateien werden geändert.
EN: Simulates cleanup of files older than 60 days; no services/files are changed.
.EXAMPLE
.\cleanupWindowsUpdateCache.ps1 -AllowCleanup true -MinimumAgeDays 60 -CustomField updateCacheReport
DE: Löscht Dateien älter als 60 Tage (ohne Rückfrage, ConfirmImpact Medium) und schreibt das JSON in updateCacheReport.
EN: Deletes files older than 60 days (no prompt, ConfirmImpact Medium) and writes the JSON to updateCacheReport.
.NOTES
DE: Exit 0 Erfolg/Inventur/WhatIf, Exit 1 Fehler. AllowCleanup=true bleibt erforderlich.
EN: Exit 0 success/audit/WhatIf, exit 1 error. AllowCleanup=true remains required.
DE: ConfirmImpact Medium vermeidet bei Standard-ConfirmPreference High unbeaufsichtigte Rückfragen.
EN: ConfirmImpact Medium avoids unattended prompts with the default ConfirmPreference High.
DE: -WhatIf simuliert Änderungen; -Confirm erzwingt Rückfragen und ist nicht für unbeaufsichtigte NinjaOne-Läufe geeignet.
EN: -WhatIf simulates changes; -Confirm requests prompts and is unsuitable for unattended NinjaOne runs.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$AllowCleanup = $env:updateCacheAllowCleanup,
    [string]$MinimumAgeDays = $env:updateCacheMinimumAgeDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $AllowCleanup = if ([string]::IsNullOrWhiteSpace($AllowCleanup) -or $AllowCleanup.Trim() -eq 'null') { '' } else { $AllowCleanup.Trim() }
    $MinimumAgeDays = if ([string]::IsNullOrWhiteSpace($MinimumAgeDays) -or $MinimumAgeDays.Trim() -eq 'null') { '' } else { $MinimumAgeDays.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ($CustomField -and ($CustomField.Length -gt 128 -or $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]*$')) { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($AllowCleanup) -or $AllowCleanup.Trim() -eq 'null') { $AllowCleanup = 'false' }
    $allow = $false
    if (-not [bool]::TryParse($AllowCleanup.Trim(), [ref]$allow)) { throw 'AllowCleanup: true/false erforderlich / required.' }
    if ([string]::IsNullOrWhiteSpace($MinimumAgeDays) -or $MinimumAgeDays.Trim() -eq 'null') { $MinimumAgeDays = '30' }
    $days = 0
    if (-not [int]::TryParse($MinimumAgeDays.Trim(), [ref]$days) -or $days -lt 7 -or $days -gt 3650) { throw 'MinimumAgeDays: 7-3650 erforderlich / required.' }
    $windows = [Environment]::GetFolderPath('Windows')
    if (-not [IO.Path]::IsPathRooted($windows)) { throw 'Ungültiger Windows-Pfad / Invalid Windows path.' }
    $cache = Join-Path $windows 'SoftwareDistribution\Download'
    # DE: Alle Pfadkomponenten und Unterordner ohne Reparsepunkte. EN: Reject reparse-point path components and skip subtrees.
    foreach ($path in @($windows, (Join-Path $windows 'SoftwareDistribution'), $cache)) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Reparsepunkt im Cachepfad / Reparse point in cache path.'
        }
    }
    function Get-SafeCacheFile {
        param([string]$Directory)
        foreach ($item in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) { Get-SafeCacheFile -Directory $item.FullName } else { $item }
        }
    }
    $cutoff = [DateTime]::UtcNow.AddDays(-$days)
    $files = @()
    if (Test-Path -LiteralPath $cache -PathType Container) { $files = @(Get-SafeCacheFile -Directory $cache | Where-Object { $_.LastWriteTimeUtc -lt $cutoff }) }
    $bytes = ($files | Measure-Object Length -Sum).Sum
    $deleted = 0
    $states = @()
    if ($allow -and $files.Count -gt 0 -and $PSCmdlet.ShouldProcess($cache, 'Alte Cachedateien löschen / Delete old cache files')) {
        try {
            foreach ($name in @('BITS', 'wuauserv')) {
                $service = Get-Service -Name $name
                if ($service.Status -notin @('Running', 'Stopped')) { throw "Instabiler Dienststatus / Unstable service state: $name" }
                $states += [pscustomobject]@{ Name = $name; Running = $service.Status -eq 'Running' }
            }
            foreach ($state in $states) {
                if ($state.Running) {
                    Stop-Service -Name $state.Name -ErrorAction Stop
                    (Get-Service -Name $state.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                }
            }
            foreach ($file in $files) {
                # DE: Pfad kurz vor Löschung erneut prüfen. EN: Recheck ancestors immediately before deletion.
                $parent = $file.Directory
                while ($null -ne $parent) {
                    if ((Get-Item -LiteralPath $parent.FullName -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparsepunkt erkannt / Reparse point detected.' }
                    if ($parent.FullName -eq $cache) { break }
                    $parent = $parent.Parent
                }
                if ($null -eq $parent) { throw 'Datei außerhalb Cache / File outside cache.' }
                $current = Get-Item -LiteralPath $file.FullName -Force
                if ($current.PSIsContainer -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsichere Cachedatei / Unsafe cache file.' }
                if ($current.LastWriteTimeUtc -lt $cutoff) {
                    Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
                    $deleted++
                }
            }
        } finally {
            $restoreErrors = @()
            foreach ($state in $states) {
                try {
                    $service = Get-Service -Name $state.Name
                    if ($state.Running -and $service.Status -ne 'Running') {
                        Start-Service -Name $state.Name -ErrorAction Stop
                        (Get-Service -Name $state.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                    } elseif (-not $state.Running -and $service.Status -ne 'Stopped') {
                        Stop-Service -Name $state.Name -ErrorAction Stop
                        (Get-Service -Name $state.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                    }
                } catch { $restoreErrors += $_.Exception.Message }
            }
            if ($restoreErrors.Count) { throw "Dienstwiederherstellung fehlgeschlagen / Service restoration failed: $($restoreErrors -join '; ')" }
        }
    }
    $json = [pscustomobject]@{ Cache = $cache; MinimumAgeDays = $days; EligibleFiles = $files.Count; EligibleBytes = [long]$bytes; CleanupAllowed = $allow; WhatIf = [bool]$WhatIfPreference; DeletedFiles = $deleted } | ConvertTo-Json
    Write-Output $json
    $field = if ($null -eq $CustomField) { '' } else { $CustomField.Trim() }
    if ($field -and $field -ne 'null') {
        if ($field.Length -gt 128 -or $field -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
        if ($json.Length -gt 4000) { throw 'JSON überschreitet 4000 Zeichen / JSON exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $field -Value $json -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "Ninja-Property-Set Exitcode / exit code: $global:LASTEXITCODE" }
    }
    exit 0
} catch {
    Write-Error ("Cacheprüfung fehlgeschlagen / Cache audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}