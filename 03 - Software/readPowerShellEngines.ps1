#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet installierte PowerShell-Engines (2.0, 5.1, 7.x) und warnt, wenn PowerShell 2.0 aktiviert ist.
    EN: Reports installed PowerShell engines (2.0, 5.1, 7.x) and warns if PowerShell 2.0 is enabled.
.DESCRIPTION
    DE: PowerShell 2.0: optionale Features MicrosoftWindowsPowerShellV2Root/MicrosoftWindowsPowerShellV2
        (Get-WindowsOptionalFeature -Online) und HKLM\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine.
        Sind die Feature-Zustände abfragbar, entscheiden sie (Enabled/EnablePending = aktiviert); sonst wird die
        Registry (PowerShellVersion 2.x) herangezogen. Fehlen die Features (z. B. Windows 11 24H2), gilt 2.0 als
        nicht vorhanden. PowerShell 5.1: HKLM\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine.
        PowerShell 7.x: HKLM\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions (64/32) und pwsh.exe unter
        Program Files\PowerShell\* (Dateiversion, keine Ausführung). Nichts wird geändert.
        Exit 0 = PowerShell 2.0 nicht aktiviert, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = PowerShell 2.0 aktiviert.
    EN: PowerShell 2.0: optional features MicrosoftWindowsPowerShellV2Root/MicrosoftWindowsPowerShellV2
        (Get-WindowsOptionalFeature -Online) and HKLM\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine.
        If feature states are queryable they decide (Enabled/EnablePending = enabled); otherwise the registry
        (PowerShellVersion 2.x) is used. If the features are absent (e.g. Windows 11 24H2), 2.0 counts as not
        present. PowerShell 5.1: HKLM\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine.
        PowerShell 7.x: HKLM\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions (64/32) and pwsh.exe under
        Program Files\PowerShell\* (file version, never executed). Nothing is changed.
        Exit 0 = PowerShell 2.0 not enabled, 1 = input, query or write error, 2 = PowerShell 2.0 enabled.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readPowerShellEngines.ps1
    DE: Gibt die Engine-Übersicht aus; Exit 2, wenn PowerShell 2.0 aktiviert ist.
    EN: Outputs the engine overview; exit 2 if PowerShell 2.0 is enabled.
.EXAMPLE
    .\readPowerShellEngines.ps1 -CustomField powerShellEngines
    DE: Wie oben, zusätzlich JSON in powerShellEngines.
    EN: As above, plus JSON to powerShellEngines.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = PowerShell 2.0 aktiviert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = PowerShell 2.0 enabled.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $props = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
    $value = $props.$Name
    if ($null -eq $value) { return $null }
    return [string]$value
}
try {
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $v2Registry = Get-RegistryValue 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\PowerShellEngine' 'PowerShellVersion'
    $v2RegistryPresent = ($null -ne $v2Registry -and $v2Registry -match '^2\.')
    $featureStates = [ordered]@{}
    $featureQueryOk = [bool](Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)
    foreach ($name in @('MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2')) {
        if (-not $featureQueryOk) { $featureStates[$name] = 'Unknown'; continue }
        try {
            $feature = @(Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop) | Select-Object -First 1
            $featureStates[$name] = if ($feature -and $feature.State) { [string]$feature.State } else { 'NotPresent' }
        } catch {
            $featureStates[$name] = 'Unknown'
            $featureQueryOk = $false
        }
    }
    $v2Enabled = if (@($featureStates.Values | Where-Object { $_ -in @('Enabled', 'EnablePending') }).Count -gt 0) { $true }
        elseif ($featureQueryOk) { $false }
        else { $v2RegistryPresent }

    $v5Version = Get-RegistryValue 'HKLM:\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine' 'PowerShellVersion'
    $core = [ordered]@{}
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\PowerShellCore\InstalledVersions')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            $location = ([string]$props.InstallLocation).Trim().TrimEnd('\')
            if (-not $location) { continue }
            $core[$location.ToLowerInvariant()] = [ordered]@{ Location = $location; SemanticVersion = [string]$props.SemanticVersion; FileVersion = $null; Source = 'Registry' }
        }
    }
    $programRoots = @(@($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    foreach ($programRoot in $programRoots) {
        $base = '{0}\PowerShell' -f $programRoot
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        foreach ($folder in @(Get-ChildItem -LiteralPath $base -ErrorAction Stop | Where-Object { $_.PSIsContainer })) {
            $location = '{0}\{1}' -f $base, $folder.Name
            $exe = '{0}\pwsh.exe' -f $location
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
            $info = (Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo
            $fileVersion = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
            $id = $location.ToLowerInvariant()
            if ($core.Contains($id)) { $core[$id].FileVersion = $fileVersion; $core[$id].Source = 'Registry+File' }
            else { $core[$id] = [ordered]@{ Location = $location; SemanticVersion = $null; FileVersion = $fileVersion; Source = 'File' } }
        }
    }
    $coreRecords = @($core.Values | ForEach-Object { [pscustomobject]$_ } | Select-Object -First 20)
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME
        PowerShell2 = [ordered]@{ Enabled = $v2Enabled; FeatureStates = $featureStates; RegistryVersion = $v2Registry }
        WindowsPowerShell = [ordered]@{ RegistryVersion = $v5Version; CurrentHostVersion = $PSVersionTable.PSVersion.ToString() }
        PowerShell7 = [ordered]@{ Count = $core.Count; Installations = $coreRecords }
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($v2Enabled) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
