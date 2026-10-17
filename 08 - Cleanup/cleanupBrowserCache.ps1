#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Browser-Cacheordner (Chrome, Edge, Firefox) aller Benutzerprofile und leert sie optional.
    EN: Audits browser cache folders (Chrome, Edge, Firefox) of all user profiles and optionally clears them.
.DESCRIPTION
    DE: Es werden ausschließlich CACHE-Ordner gelöscht, nie Profile, Cookies, Verlauf, Kennwörter oder Einstellungen:
        Chrome  AppData\Local\Google\Chrome\User Data\<Profil>\Cache\Cache_Data, Code Cache, GPUCache
        Edge    AppData\Local\Microsoft\Edge\User Data\<Profil>\Cache\Cache_Data, Code Cache, GPUCache
        Firefox AppData\Local\Mozilla\Firefox\Profiles\<Profil>\cache2
        <Profil> = "Default" und "Profile *" (Chrome/Edge) bzw. jeder Profilordner (Firefox).
        Benutzerprofile stammen aus der ProfileList (SIDs S-1-5-21-*/S-1-12-1-*) bzw. C:\Users; Spezialprofile und
        Reparsepunkte werden übersprungen. Pfade mit Reparsepunkten werden übersprungen; innerhalb der
        Cacheordner werden Reparsepunkte nie verfolgt (nur der Link wird entfernt).
        SkipRunning=true (Standard): läuft der Browser (chrome.exe, msedge.exe, firefox.exe) für den Benutzer
        (Besitzer per Win32_Process GetOwner/GetOwnerSid), wird dieser Browser für diesen Benutzer übersprungen;
        ist der Besitzer eines Browserprozesses nicht ermittelbar, wird der Browser für ALLE Benutzer übersprungen.
        Gesperrte Dateien werden übersprungen (Failed). Ohne Allow=true wird nur inventarisiert; jede Löschung je
        Benutzer und Browser läuft über ShouldProcess (-WhatIf). Bericht als JSON (max. 20 Einträge), optional in
        ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Only CACHE folders are deleted, never profiles, cookies, history, passwords or settings:
        Chrome  AppData\Local\Google\Chrome\User Data\<profile>\Cache\Cache_Data, Code Cache, GPUCache
        Edge    AppData\Local\Microsoft\Edge\User Data\<profile>\Cache\Cache_Data, Code Cache, GPUCache
        Firefox AppData\Local\Mozilla\Firefox\Profiles\<profile>\cache2
        <profile> = "Default" and "Profile *" (Chrome/Edge) or every profile folder (Firefox).
        User profiles come from the ProfileList (SIDs S-1-5-21-*/S-1-12-1-*) or C:\Users; special profiles and
        reparse points are skipped. Paths containing reparse points are skipped; inside cache folders reparse
        points are never followed (only the link is removed).
        SkipRunning=true (default): if the browser (chrome.exe, msedge.exe, firefox.exe) runs for the user (owner
        via Win32_Process GetOwner/GetOwnerSid), that browser is skipped for that user; if the owner of a browser
        process cannot be determined, the browser is skipped for ALL users.
        Locked files are skipped (Failed). Without Allow=true the script only audits; every deletion per user and
        browser goes through ShouldProcess (-WhatIf). JSON report (max. 20 entries), optionally written to a
        MultiLine field (max. 4000 characters, otherwise exit 1).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupBrowserCacheAllow; true/false; Standard false. Nur true löscht Cacheordner.
    EN: NinjaOne checkbox/text cleanupBrowserCacheAllow; true/false; default false. Only true deletes cache folders.
.PARAMETER Browsers
    DE: NinjaOne Text cleanupBrowserCacheBrowsers; kommagetrennt aus Chrome, Edge, Firefox; Standard alle drei.
    EN: NinjaOne text cleanupBrowserCacheBrowsers; comma-separated from Chrome, Edge, Firefox; default all three.
.PARAMETER SkipRunning
    DE: NinjaOne Checkbox/Text cleanupBrowserCacheSkipRunning; true/false; Standard true (laufende Browser auslassen).
    EN: NinjaOne checkbox/text cleanupBrowserCacheSkipRunning; true/false; default true (skip running browsers).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupBrowserCache.ps1
    DE: Nur Inventur der Browser-Caches (Exit 2, falls Cachedateien vorhanden sind).
    EN: Audit only of browser caches (exit 2 if cache files exist).
.EXAMPLE
    .\cleanupBrowserCache.ps1 -Allow true -Browsers 'Chrome,Edge' -WhatIf
    DE: Simuliert das Leeren der Chrome- und Edge-Caches; nichts wird gelöscht.
    EN: Simulates clearing the Chrome and Edge caches; nothing is deleted.
.EXAMPLE
    .\cleanupBrowserCache.ps1 -Allow true -CustomField browserCacheReport
    DE: Leert die Caches nicht laufender Browser und schreibt das JSON in browserCacheReport.
    EN: Clears the caches of browsers that are not running and writes the JSON to browserCacheReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts zu tun, Bereinigung erfolgreich oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat Cachedateien (nicht laufender Browser) gefunden; oder die Bereinigung
                 lief, aber Dateien/Ordner konnten nicht gelöscht werden oder Browser mit Cacheinhalt wurden wegen
                 laufender Prozesse übersprungen.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing to do, cleanup successful or -WhatIf.
        Exit 1 = input, query or write error.
        Exit 2 = audit (Allow=false) found cache files (of browsers not running); or cleanup ran but files/folders
                 could not be deleted or browsers with cache content were skipped because they were running.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupBrowserCacheAllow,
    [string]$Browsers = $env:cleanupBrowserCacheBrowsers,
    [string]$SkipRunning = $env:cleanupBrowserCacheSkipRunning,
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
function Get-UserProfile {
    $listPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $found = @()
    if (Test-Path -LiteralPath $listPath) {
        foreach ($key in @(Get-ChildItem -LiteralPath $listPath -ErrorAction Stop)) {
            $sid = [string]$key.PSChildName
            if ($sid -notmatch '^S-1-(5-21|12-1)-\d+(-\d+)*$') { continue }
            $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $path = [Environment]::ExpandEnvironmentVariables([string]$values.ProfileImagePath)
            if ($path -and [IO.Path]::IsPathRooted($path)) { $found += [pscustomobject]@{ Path = $path.TrimEnd('\', '/'); Sid = $sid } }
        }
    }
    else {
        $usersRoot = if ($env:PUBLIC) { Split-Path -Path $env:PUBLIC -Parent } else { Join-Path $env:SystemDrive 'Users' }
        if ($usersRoot -and (Test-Path -LiteralPath $usersRoot -PathType Container)) {
            foreach ($folder in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction Stop)) {
                if (-not (Test-IsReparsePoint $folder)) { $found += [pscustomobject]@{ Path = $folder.FullName; Sid = $null } }
            }
        }
    }
    @($found | Where-Object { (Split-Path -Path $_.Path -Leaf) -notmatch '^(Public|Default|Default User|All Users|defaultuser\d+)$' } | Sort-Object -Property Path -Unique)
}
function Get-RunningOwner {
    param([string]$ProcessName)
    $state = [pscustomobject]@{ Count = 0; Users = @(); Sids = @(); Unknown = $false }
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter ("Name='{0}'" -f $ProcessName) -ErrorAction Stop)
    $state.Count = $processes.Count
    foreach ($process in $processes) {
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
            if ([int]$owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace([string]$owner.User)) { throw 'Besitzer unbekannt / Owner unknown.' }
            $state.Users += [string]$owner.User
            $ownerSid = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue
            if ($null -ne $ownerSid -and [int]$ownerSid.ReturnValue -eq 0 -and $ownerSid.Sid) { $state.Sids += [string]$ownerSid.Sid }
        }
        catch { $state.Unknown = $true }
    }
    return $state
}
function Get-CacheStatistic {
    param([IO.DirectoryInfo]$Folder)
    $files = 0
    $bytes = [long]0
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Folder)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try { $children = @($current.GetFileSystemInfos()) } catch { continue }
        foreach ($child in $children) {
            if (Test-IsReparsePoint $child) { continue }
            if ($child -is [IO.DirectoryInfo]) { $stack.Push($child) } else { $files++; $bytes += $child.Length }
        }
    }
    [pscustomobject]@{ Files = $files; Bytes = $bytes }
}
function Invoke-SafeTreeDelete {
    param([IO.DirectoryInfo]$Folder)
    $stats = [pscustomobject]@{ Files = 0; Bytes = [long]0; Failed = 0 }
    $folders = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Folder)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $folders.Add($current)
        try { $children = @($current.GetFileSystemInfos()) } catch { $stats.Failed++; continue }
        foreach ($child in $children) {
            try {
                # DE: Reparsepunkte nur als Link entfernen. EN: Remove reparse points as links only.
                if (Test-IsReparsePoint $child) {
                    if ($child -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($child.FullName, $false) } else { [IO.File]::Delete($child.FullName) }
                }
                elseif ($child -is [IO.DirectoryInfo]) { $stack.Push($child) }
                else {
                    $length = $child.Length
                    Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop
                    $stats.Files++
                    $stats.Bytes += $length
                }
            }
            catch { $stats.Failed++ }
        }
    }
    for ($index = $folders.Count - 1; $index -ge 0; $index--) {
        $path = $folders[$index].FullName
        if (-not [IO.Directory]::Exists($path)) { continue }
        $enumerator = [IO.Directory]::EnumerateFileSystemEntries($path).GetEnumerator()
        try { $hasContent = $enumerator.MoveNext() } finally { $enumerator.Dispose() }
        # DE: Nicht leere Ordner enthalten bereits gezählte gesperrte Dateien. EN: Non-empty folders contain already counted locked files.
        if ($hasContent) { continue }
        try { [IO.Directory]::Delete($path, $false) } catch { $stats.Failed++ }
    }
    return $stats
}
function Get-BrowserCacheFolder {
    param([string]$ProfilePath, [string]$Browser)
    $definitions = @{
        Chrome = @{ Base = @('AppData', 'Local', 'Google', 'Chrome', 'User Data'); Caches = @(@('Cache', 'Cache_Data'), @('Code Cache'), @('GPUCache')); Firefox = $false }
        Edge = @{ Base = @('AppData', 'Local', 'Microsoft', 'Edge', 'User Data'); Caches = @(@('Cache', 'Cache_Data'), @('Code Cache'), @('GPUCache')); Firefox = $false }
        Firefox = @{ Base = @('AppData', 'Local', 'Mozilla', 'Firefox', 'Profiles'); Caches = @(, @('cache2')); Firefox = $true }
    }
    $definition = $definitions[$Browser]
    $base = Get-SafeRoot -Base $ProfilePath -Segment $definition.Base
    if ($base.Status -ne 'OK') { return }
    foreach ($browserProfile in @(Get-ChildItem -LiteralPath $base.Path -Directory -Force -ErrorAction SilentlyContinue)) {
        if (Test-IsReparsePoint $browserProfile) { continue }
        if (-not $definition.Firefox -and $browserProfile.Name -ne 'Default' -and $browserProfile.Name -notlike 'Profile *') { continue }
        foreach ($segments in $definition.Caches) {
            $cache = Get-SafeRoot -Base $browserProfile.FullName -Segment $segments
            if ($cache.Status -eq 'OK') { [IO.DirectoryInfo]::new($cache.Path) }
        }
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
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupBrowserCacheAllow'
    $skip = ConvertTo-Boolean -Value (Resolve-Setting $SkipRunning 'true') -Name 'cleanupBrowserCacheSkipRunning'
    $browserText = Resolve-Setting $Browsers 'Chrome,Edge,Firefox'
    $known = @('Chrome', 'Edge', 'Firefox')
    $selected = @()
    foreach ($entry in $browserText.Split(',')) {
        $name = $entry.Trim()
        $match = @($known | Where-Object { $_ -eq $name })
        if ($match.Count -ne 1) { throw 'cleanupBrowserCacheBrowsers: nur Chrome, Edge, Firefox / only Chrome, Edge, Firefox.' }
        if ($selected -notcontains $match[0]) { $selected += $match[0] }
    }
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $processNames = @{ Chrome = 'chrome.exe'; Edge = 'msedge.exe'; Firefox = 'firefox.exe' }
    $running = @{}
    if ($skip) { foreach ($browser in $selected) { $running[$browser] = Get-RunningOwner -ProcessName $processNames[$browser] } }
    $records = @()
    foreach ($userProfile in @(Get-UserProfile)) {
        $leaf = Split-Path -Path $userProfile.Path -Leaf
        foreach ($browser in $selected) {
            $caches = @(Get-BrowserCacheFolder -ProfilePath $userProfile.Path -Browser $browser)
            if ($caches.Count -eq 0) { continue }
            $files = 0
            $bytes = [long]0
            foreach ($cache in $caches) { $statistic = Get-CacheStatistic -Folder $cache; $files += $statistic.Files; $bytes += $statistic.Bytes }
            $record = [ordered]@{ User = $leaf; Browser = $browser; Status = 'Eligible'; CacheFolders = $caches.Count; Files = $files; Bytes = $bytes; DeletedFiles = 0; DeletedBytes = [long]0; Failed = 0 }
            $records += $record
            if ($files -eq 0) { $record.Status = 'Empty' }
            if ($skip) {
                $state = $running[$browser]
                $isRunning = $state.Unknown -or ($userProfile.Sid -and $state.Sids -contains $userProfile.Sid) -or $state.Users -contains $leaf -or $state.Users -contains ($leaf -split '\.')[0]
                if ($isRunning) { $record.Status = 'SkippedRunning'; continue }
            }
            if (-not $allowed -or $files -eq 0) { continue }
            if (-not $PSCmdlet.ShouldProcess(('{0} ({1})' -f $browser, $userProfile.Path), 'Browser-Cache leeren / Clear browser cache')) { continue }
            foreach ($cache in $caches) {
                $result = Invoke-SafeTreeDelete -Folder $cache
                $record.DeletedFiles += $result.Files
                $record.DeletedBytes += $result.Bytes
                $record.Failed += $result.Failed
            }
            $record.Status = if ($record.Failed -gt 0) { 'Partial' } else { 'Cleaned' }
        }
    }
    $records = @($records | ForEach-Object { [pscustomobject]$_ })
    $eligible = @($records | Where-Object { $_.Status -ne 'SkippedRunning' -and $_.Files -gt 0 })
    $skippedRunning = @($records | Where-Object { $_.Status -eq 'SkippedRunning' -and $_.Files -gt 0 })
    $totalFailed = [int]($records | Measure-Object -Property Failed -Sum).Sum
    $maxRecords = 20
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; Browsers = $selected; SkipRunning = $skip
        RunningBrowsers = @($running.Keys | Where-Object { $running[$_].Count -gt 0 } | Sort-Object)
        EligibleFiles = [int]($eligible | Measure-Object -Property Files -Sum).Sum
        EligibleBytes = [long]($eligible | Measure-Object -Property Bytes -Sum).Sum
        SkippedRunning = $skippedRunning.Count
        DeletedFiles = [int]($records | Measure-Object -Property DeletedFiles -Sum).Sum
        DeletedBytes = [long]($records | Measure-Object -Property DeletedBytes -Sum).Sum
        Failed = $totalFailed; EntriesOmitted = [Math]::Max(0, $records.Count - $maxRecords)
        Entries = @($records | Sort-Object -Property Bytes -Descending | Select-Object -First $maxRecords)
    })
    if (-not $allowed) {
        if ($eligible.Count -gt 0) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    if ($totalFailed -gt 0 -or $skippedRunning.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
