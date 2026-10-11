#Requires -Version 5.1
<#
.SYNOPSIS
DE: Installierte Windows-Hotfixes inventarisieren (keine vollständige Updateinventur).
EN: Inventory installed Windows hotfixes (not a complete update inventory).
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. RecentDays=0 zeigt alle, 1-3650 filtert nach Installationsdatum.
EN: Windows SYSTEM, 64-bit. RecentDays=0 shows all; 1-3650 filters by installation date.
DE: Unbekannte Installationsdaten bleiben sichtbar. MultiLine-CustomField: Klartext-JSON, max. 4000 Zeichen.
EN: Unknown installation dates remain visible. MultiLine CustomField: plain-text JSON, max. 4000 characters.
.PARAMETER RecentDays
DE: String; NinjaOne hotfixInventoryRecentDays; Standard 0; ganze Zahl 0-3650, 0 ohne Datumsfilter.
EN: String; NinjaOne hotfixInventoryRecentDays; default 0; integer 0-3650, 0 disables date filtering.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$RecentDays = $env:hotfixInventoryRecentDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $RecentDays = if ([string]::IsNullOrWhiteSpace($RecentDays) -or $RecentDays.Trim() -eq 'null') { '' } else { $RecentDays.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($RecentDays) -or $RecentDays.Trim() -eq 'null') { $RecentDays = '0' }
    $days = 0
    if (-not [int]::TryParse($RecentDays.Trim(), [ref]$days) -or $days -lt 0 -or $days -gt 3650) { throw 'RecentDays: 0-3650 erforderlich / required.' }
    $cutoff = [DateTime]::Now.AddDays(-$days)
    $all = @(Get-HotFix -ErrorAction Stop)
    $items = @(foreach ($hotfix in ($all | Sort-Object HotFixID)) {
        $installed = $null
        if ($hotfix.InstalledOn) { $installed = [datetime]$hotfix.InstalledOn }
        if ($days -eq 0 -or $null -eq $installed -or $installed -ge $cutoff) {
            [pscustomobject]@{ HotFixId = $hotfix.HotFixID; Description = $hotfix.Description; InstalledOn = if ($installed) { $installed.ToString('yyyy-MM-dd') } else { $null } }
        }
    })
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; RecentDays = $days; TotalHotfixes = $all.Count; ReturnedHotfixes = $items.Count; Hotfixes = $items } | ConvertTo-Json -Depth 5
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
    Write-Error ("Hotfixinventur fehlgeschlagen / Hotfix inventory failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
