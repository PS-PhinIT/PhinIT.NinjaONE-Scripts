#Requires -Version 5.1

<#
.SYNOPSIS
DE: .NET-Framework-Registry und moderne .NET-Laufzeitordner inventarisieren.
EN: Inventory .NET Framework registry and modern .NET runtime directories.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. IncludeModern=true prüft standardmäßige x64/x86-Installationsordner.
EN: Windows SYSTEM, 64-bit. IncludeModern=true checks standard x64/x86 installation directories.
DE: Keine dotnet.exe-Ausführung; benutzerdefinierte/portable Installationen werden nicht erkannt.
EN: No dotnet.exe execution; custom/portable installations are not detected.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters.
DE: Exit 0 = Erfolg, 1 = Eingabe-, Abfrage- oder Schreibfehler.
EN: Exit 0 = success, 1 = input, query or write error.
.PARAMETER IncludeModern
DE: String mit Boolean-Wert true/false; NinjaOne dotNetInventoryIncludeModern; Standard true.
EN: String containing Boolean true/false; NinjaOne dotNetInventoryIncludeModern; default true.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\readDotNetInventory.ps1 -IncludeModern false
DE: Nur .NET-Framework-Versionen aus der Registry.
EN: Only .NET Framework versions from the registry.
.EXAMPLE
.\readDotNetInventory.ps1 -IncludeModern true -CustomField dotNetInventory
DE: Framework und moderne .NET-Laufzeiten; JSON in dotNetInventory schreiben.
EN: Framework and modern .NET runtimes; write JSON to dotNetInventory.
#>
[CmdletBinding()]
param(
    [string]$IncludeModern = $env:dotNetInventoryIncludeModern,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $IncludeModern = if ([string]::IsNullOrWhiteSpace($IncludeModern) -or $IncludeModern.Trim() -eq 'null') { '' } else { $IncludeModern.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($IncludeModern) -or $IncludeModern.Trim() -eq 'null') { $IncludeModern = 'true' }
    $modern = $false
    if (-not [bool]::TryParse($IncludeModern.Trim(), [ref]$modern)) { throw 'IncludeModern: true/false erforderlich / required.' }
    $framework = @()
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $base = $null
        $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            foreach ($subkey in @('v4\Full', 'v4\Client', 'v3.5')) {
                $key = $base.OpenSubKey("SOFTWARE\Microsoft\NET Framework Setup\NDP\$subkey")
                if ($null -ne $key) {
                    try {
                        $framework += [pscustomobject]@{ Profile = $subkey; View = [string]$view; Version = [string]$key.GetValue('Version'); Release = $key.GetValue('Release'); Install = $key.GetValue('Install') }
                    } finally { $key.Dispose(); $key = $null }
                }
            }
        } finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
    }
    $runtimes = @()
    if ($modern) {
        foreach ($folder in @([Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86'))) {
            if ([string]::IsNullOrWhiteSpace($folder)) { continue }
            $shared = Join-Path $folder 'dotnet\shared'
            if (Test-Path -LiteralPath $shared -PathType Container) {
                foreach ($family in @(Get-ChildItem -LiteralPath $shared -Directory -ErrorAction Stop)) {
                    foreach ($version in @(Get-ChildItem -LiteralPath $family.FullName -Directory -ErrorAction Stop)) {
                        $runtimes += [pscustomobject]@{ Family = $family.Name; Version = $version.Name; Location = $version.FullName }
                    }
                }
            }
        }
    }
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Framework = $framework; ModernRuntimeDirectories = $runtimes } | ConvertTo-Json -Depth 5
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
    Write-Error (".NET-Inventur fehlgeschlagen / .NET inventory failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
