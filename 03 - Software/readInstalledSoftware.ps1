#Requires -Version 5.1
<#
.SYNOPSIS
DE: Maschinenweite Uninstall-Registry inventarisieren, ohne MSI-Reparatur auszulösen.
EN: Inventory machine-wide uninstall registry entries without triggering MSI repair.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit; keine Benutzerprofile/AppX-Pakete. NameContains ist literaler Text.
EN: Windows SYSTEM, 64-bit; no user profiles/AppX packages. NameContains is literal text.
DE: Optionales MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen; keine Kürzung.
EN: Optional MultiLine CustomField: plain-text JSON, maximum 4000 characters; no truncation.
.PARAMETER NameContains
DE: String; NinjaOne softwareInventoryNameContains; Standard leer; literaler Teilname, maximal 200 Zeichen, keine Steuerzeichen.
EN: String; NinjaOne softwareInventoryNameContains; default empty; literal substring, maximum 200 characters, no control characters.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$NameContains = $env:softwareInventoryNameContains,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $NameContains = if ([string]::IsNullOrWhiteSpace($NameContains) -or $NameContains.Trim() -eq 'null') { '' } else { $NameContains.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    $filter = if ($null -eq $NameContains) { '' } else { $NameContains.Trim() }
    if ($filter -eq 'null') { $filter = '' }
    if ($filter.Length -gt 200 -or $filter -match '[\x00-\x1f]') { throw 'Ungültiger Namensfilter / Invalid name filter.' }
    $items = @(foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null
        $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $key) { continue }
            foreach ($name in $key.GetSubKeyNames()) {
                $entry = $key.OpenSubKey($name)
                if ($null -eq $entry) { throw 'Registryeintrag nicht lesbar / Registry entry unreadable.' }
                try {
                    $display = [string]$entry.GetValue('DisplayName')
                    if (-not [string]::IsNullOrWhiteSpace($display) -and (-not $filter -or $display.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                        [pscustomobject]@{ Name = $display; Version = [string]$entry.GetValue('DisplayVersion'); Publisher = [string]$entry.GetValue('Publisher'); RegistryView = [string]$view; Key = $name }
                    }
                } finally { $entry.Dispose() }
            }
        } finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
    })
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Scope = 'Machine uninstall registry only'; NameContains = $filter; Count = $items.Count; Software = @($items | Sort-Object Name, RegistryView, Key) } | ConvertTo-Json -Depth 5
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
    Write-Error ("Softwareinventur fehlgeschlagen / Software inventory failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}