#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Größe des Übermittlungsoptimierungs-Caches (Delivery Optimization) und leert ihn optional.
    EN: Audits the size of the Delivery Optimization cache and optionally clears it.
.DESCRIPTION
    DE: Größe: Get-DeliveryOptimizationPerfSnap (CacheSizeBytes), sonst Ordnergröße des Cache-Ordners aus
        Get-DOConfig (WorkingDirectory) bzw. des Standardpfads
        $env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache
        (ohne Reparsepunkte). Mit Allow=true und Cachegröße >= MinimumCacheMB (0 = immer) wird
        Delete-DeliveryOptimizationCache -Force über ShouldProcess (-WhatIf) aufgerufen; fehlt das Cmdlet, endet
        das Skript mit Exit 1. Danach wird die Größe erneut gemessen.
        Ohne Allow=true wird nur inventarisiert. Bericht als JSON, optional in ein MultiLine-Feld (max. 4000 Zeichen).
    EN: Size: Get-DeliveryOptimizationPerfSnap (CacheSizeBytes), otherwise the folder size of the cache folder
        from Get-DOConfig (WorkingDirectory) or the default path
        $env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache
        (without reparse points). With Allow=true and cache size >= MinimumCacheMB (0 = always),
        Delete-DeliveryOptimizationCache -Force is called through ShouldProcess (-WhatIf); if the cmdlet is
        missing, the script ends with exit 1. Afterwards the size is measured again.
        Without Allow=true the script only audits. JSON report, optionally written to a MultiLine field
        (max. 4000 characters).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupDoAllow; true/false; Standard false. Nur true leert den Cache.
    EN: NinjaOne checkbox/text cleanupDoAllow; true/false; default false. Only true clears the cache.
.PARAMETER MinimumCacheMB
    DE: NinjaOne Text cleanupDoMinimumCacheMB; ganze Zahl 0-1048576; Standard 0 (= mit Allow immer leeren).
        Nur leeren bzw. melden, wenn der Cache mindestens so groß ist.
    EN: NinjaOne text cleanupDoMinimumCacheMB; integer 0-1048576; default 0 (= always clear when allowed).
        Only clear or report when the cache is at least this large.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupDeliveryOptimizationCache.ps1 -MinimumCacheMB 1024
    DE: Nur Inventur; Exit 2, wenn der Cache mindestens 1024 MB groß ist.
    EN: Audit only; exit 2 if the cache is at least 1024 MB.
.EXAMPLE
    .\cleanupDeliveryOptimizationCache.ps1 -Allow true -WhatIf
    DE: Simuliert das Leeren des Caches; nichts wird gelöscht.
    EN: Simulates clearing the cache; nothing is deleted.
.EXAMPLE
    .\cleanupDeliveryOptimizationCache.ps1 -Allow true -MinimumCacheMB 2048 -CustomField doCacheReport
    DE: Leert den Cache ab 2048 MB und schreibt das JSON in doCacheReport.
    EN: Clears the cache from 2048 MB and writes the JSON to doCacheReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts zu tun (Cache leer oder unter Schwellwert), Cache geleert oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage-, Lösch- oder Schreibfehler (auch: Delete-DeliveryOptimizationCache fehlt).
        Exit 2 = Inventur (Allow=false): Cache > 0 Byte und >= MinimumCacheMB.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing to do (cache empty or below threshold), cache cleared or -WhatIf.
        Exit 1 = input, query, delete or write error (also: Delete-DeliveryOptimizationCache missing).
        Exit 2 = audit (Allow=false): cache > 0 bytes and >= MinimumCacheMB.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupDoAllow,
    [string]$MinimumCacheMB = $env:cleanupDoMinimumCacheMB,
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
function Get-FolderSize {
    param([string]$Path)
    $info = [IO.DirectoryInfo]::new($Path)
    if (-not $info.Exists -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($child.PSIsContainer) { $stack.Push($child.FullName) } else { $total += $child.Length }
        }
    }
    return $total
}
function Get-CacheSize {
    param([System.Collections.Generic.List[string]]$Errors)
    if (Get-Command -Name Get-DeliveryOptimizationPerfSnap -ErrorAction SilentlyContinue) {
        try {
            $snap = Get-DeliveryOptimizationPerfSnap -ErrorAction Stop | Select-Object -First 1
            if ($null -ne $snap -and $null -ne $snap.CacheSizeBytes) {
                return [pscustomobject]@{ Bytes = [long]$snap.CacheSizeBytes; Source = 'Get-DeliveryOptimizationPerfSnap'; Path = $null }
            }
        }
        catch { $Errors.Add('PerfSnap: ' + $_.Exception.Message) }
    }
    $path = $null
    if (Get-Command -Name Get-DOConfig -ErrorAction SilentlyContinue) {
        try {
            $directory = [string](Get-DOConfig -ErrorAction Stop | Select-Object -First 1).WorkingDirectory
            if ($directory -and [IO.Path]::IsPathRooted($directory)) {
                $path = $directory.TrimEnd('\', '/')
                if ((Split-Path -Path $path -Leaf) -ne 'Cache' -and (Test-Path -LiteralPath (Join-Path $path 'Cache') -PathType Container)) { $path = Join-Path $path 'Cache' }
            }
        }
        catch { $Errors.Add('DOConfig: ' + $_.Exception.Message) }
    }
    if (-not $path) {
        if ([string]::IsNullOrWhiteSpace($env:windir) -or -not [IO.Path]::IsPathRooted($env:windir)) { throw 'Ungültiges windir / Invalid windir.' }
        $path = Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    }
    $bytes = Get-FolderSize -Path $path
    if ($null -eq $bytes) { return [pscustomobject]@{ Bytes = [long]0; Source = 'FolderNotFound'; Path = $path } }
    return [pscustomobject]@{ Bytes = [long]$bytes; Source = 'Folder'; Path = $path }
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
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupDoAllow'
    $thresholdMB = ConvertTo-BoundedInt -Value (Resolve-Setting $MinimumCacheMB '0') -Name 'cleanupDoMinimumCacheMB' -Minimum 0 -Maximum 1048576
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $errors = New-Object System.Collections.Generic.List[string]
    $before = Get-CacheSize -Errors $errors
    $thresholdBytes = [long]$thresholdMB * 1MB
    $due = $thresholdMB -eq 0 -or $before.Bytes -ge $thresholdBytes
    $cleaned = $false
    $after = $null
    if ($allowed -and $due) {
        if (-not (Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
            throw 'Delete-DeliveryOptimizationCache fehlt / unavailable.'
        }
        if ($PSCmdlet.ShouldProcess('Delivery Optimization Cache', 'Cache leeren / Clear cache')) {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null
            $cleaned = $true
            $after = Get-CacheSize -Errors $errors
        }
    }
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; MinimumCacheMB = $thresholdMB
        Source = $before.Source; CachePath = $before.Path; CacheBytes = $before.Bytes; CacheMB = [Math]::Round($before.Bytes / 1MB, 2)
        CleanupDue = $due; Cleaned = $cleaned
        CacheBytesAfter = $(if ($null -ne $after) { $after.Bytes } else { $null })
        FreedBytes = $(if ($null -ne $after) { [Math]::Max([long]0, $before.Bytes - $after.Bytes) } else { $null })
        Errors = @($errors | Select-Object -First 5)
    })
    if (-not $allowed -and $due -and $before.Bytes -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
