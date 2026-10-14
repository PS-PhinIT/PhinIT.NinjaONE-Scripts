#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob winget.exe (App Installer) für SYSTEM auffindbar ist, ohne etwas zu installieren.
    EN: Checks whether winget.exe (App Installer) can be located for SYSTEM without installing anything.
.DESCRIPTION
    DE: Durchsucht "$env:ProgramFiles\WindowsApps" nach Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe,
        wählt die höchste Paketversion mit vorhandener winget.exe und liest deren Dateiversion aus der
        Versionsressource. winget wird NICHT ausgeführt (kein "winget --version"), es gibt keine Installation,
        kein Bootstrap und keine Downloads. Benutzerkontext-Aliase (AppData\Local\Microsoft\WindowsApps) werden
        nicht geprüft. MinimumVersion wird mit der Paketversion (Ordnername) verglichen.
        Exit 0 = bereit (oder nicht gefunden mit Required=false), 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = winget.exe nicht gefunden und Required=true, oder Paketversion unter MinimumVersion.
    EN: Searches "$env:ProgramFiles\WindowsApps" for Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe,
        selects the highest package version containing winget.exe and reads its file version from the
        version resource. winget is NOT executed (no "winget --version"); no install, no bootstrap, no
        downloads. Per-user aliases (AppData\Local\Microsoft\WindowsApps) are not checked. MinimumVersion is
        compared with the package version (folder name).
        Exit 0 = ready (or not found with Required=false), 1 = input, query or write error,
        2 = winget.exe not found and Required=true, or package version below MinimumVersion.
.PARAMETER Required
    DE: NinjaOne Checkbox/Text softwareWingetRequired; true/false; Standard true.
    EN: NinjaOne checkbox/text softwareWingetRequired; true/false; default true.
.PARAMETER MinimumVersion
    DE: NinjaOne Text softwareWingetMinimumVersion; optional; App-Installer-Paketversion mit 1-4 Komponenten (z. B. 1.21); Standard leer.
    EN: NinjaOne Text softwareWingetMinimumVersion; optional; App Installer package version with 1-4 components (e.g. 1.21); default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\checkWingetStatus.ps1
    DE: Exit 2, wenn winget.exe für SYSTEM nicht gefunden wird.
    EN: Exit 2 if winget.exe cannot be found for SYSTEM.
.EXAMPLE
    .\checkWingetStatus.ps1 -Required false -MinimumVersion 1.21 -CustomField wingetStatus
    DE: Fehlendes winget nur melden; zu alte Paketversion ergibt Exit 2; JSON in wingetStatus.
    EN: Only report missing winget; outdated package version returns exit 2; JSON to wingetStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit (x64-Paket). Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = winget fehlt (Required) oder zu alt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit (x64 package). Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = winget missing (Required) or too old.
#>
[CmdletBinding()]
param(
    [string]$Required = $env:softwareWingetRequired,
    [string]$MinimumVersion = $env:softwareWingetMinimumVersion,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-NormalizedVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text.Trim(), '^[vV]?(\d+(?:\.\d+){0,3})')
    if (-not $match.Success) { return $null }
    $parts = @($match.Groups[1].Value.Split('.'))
    while ($parts.Count -lt 4) { $parts += '0' }
    $parsed = $null
    if ([version]::TryParse(($parts -join '.'), [ref]$parsed)) { return $parsed }
    return $null
}
try {
    $Required = Resolve-Setting $Required 'true'
    $MinimumVersion = Resolve-Setting $MinimumVersion ''
    $CustomField = Resolve-Setting $CustomField ''
    $mustExist = $false
    if (-not [bool]::TryParse($Required, [ref]$mustExist)) { throw 'softwareWingetRequired: true/false.' }
    $minimum = $null
    if ($MinimumVersion) {
        if ($MinimumVersion -notmatch '^\d{1,9}(\.\d{1,9}){0,3}$') { throw 'softwareWingetMinimumVersion: z. B. / e.g. 1.21' }
        $minimum = ConvertTo-NormalizedVersion $MinimumVersion
        if ($null -eq $minimum) { throw 'softwareWingetMinimumVersion ungültig / invalid.' }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { throw 'ProgramFiles nicht gesetzt / not set.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $appsRoot = '{0}\WindowsApps' -f $env:ProgramFiles.TrimEnd('\')
    $packages = @()
    if (Test-Path -LiteralPath $appsRoot -PathType Container) {
        $packages = @(Get-ChildItem -LiteralPath $appsRoot -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -ErrorAction Stop | Where-Object { $_.PSIsContainer } | ForEach-Object {
            $match = [regex]::Match([string]$_.Name, '^Microsoft\.DesktopAppInstaller_(\d+(?:\.\d+){1,3})_x64__8wekyb3d8bbwe$', 'IgnoreCase')
            if ($match.Success) {
                $version = ConvertTo-NormalizedVersion $match.Groups[1].Value
                if ($version) { [pscustomobject]@{ Name = [string]$_.Name; Version = $version; Path = ('{0}\{1}' -f $appsRoot, $_.Name) } }
            }
        } | Sort-Object Version -Descending)
    }
    $selected = $null
    $wingetPath = $null
    foreach ($package in $packages) {
        $candidate = '{0}\winget.exe' -f $package.Path
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $selected = $package; $wingetPath = $candidate; break }
    }
    $fileVersion = $null
    if ($wingetPath) {
        $info = (Get-Item -LiteralPath $wingetPath -ErrorAction Stop).VersionInfo
        $fileVersion = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
    }
    $status = if ($selected) { 'Ready' } elseif ($packages.Count -gt 0) { 'AppInstallerWithoutWinget' } else { 'NotFound' }
    $belowMinimum = ($null -ne $selected -and $null -ne $minimum -and $selected.Version -lt $minimum)
    if ($belowMinimum) { $status = 'BelowMinimum' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Status = $status; Required = $mustExist
        AppInstallerPresent = $packages.Count -gt 0; PackageCount = $packages.Count
        Packages = @($packages | Select-Object -First 10 | ForEach-Object { $_.Name })
        SelectedPackageVersion = if ($selected) { $selected.Version.ToString() } else { $null }
        MinimumVersion = if ($minimum) { $minimum.ToString() } else { $null }
        WingetPath = $wingetPath; WingetFileVersion = $fileVersion
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($belowMinimum -or ($null -eq $selected -and $mustExist)) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
