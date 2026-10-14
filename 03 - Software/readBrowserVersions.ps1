#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest die Dateiversionen von Chrome, Edge, Firefox und Brave; optional Mindestversionen je Browser.
    EN: Reads file versions of Chrome, Edge, Firefox and Brave; optional minimum versions per browser.
.DESCRIPTION
    DE: Prüft bekannte maschinenweite Installationspfade unter Program Files und Program Files (x86) sowie
        die Registry "App Paths" (64- und 32-Bit). Nur lokale absolute Pfade, die auf die erwartete EXE enden,
        werden ausgewertet. Die Dateiversion stammt aus den Versionsressourcen (keine Ausführung des Browsers).
        Benutzerinstallationen unter AppData werden nicht erfasst. Ohne Mindestversionen rein informativ.
        Exit 0 = OK/Inventar, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = mindestens eine Installation eines Browsers liegt unter der für ihn gesetzten Mindestversion.
        Nicht installierte Browser sind kein Befund.
    EN: Checks known machine-wide install paths under Program Files and Program Files (x86) plus the registry
        "App Paths" (64- and 32-bit). Only local absolute paths ending with the expected EXE are evaluated.
        The file version comes from the version resource (the browser is never started).
        Per-user installs under AppData are not covered. Informational without minimum versions.
        Exit 0 = OK/inventory, 1 = input, query or write error,
        2 = at least one installation of a browser is below the minimum version configured for it.
        Browsers that are not installed are not a finding.
.PARAMETER MinChrome
    DE: NinjaOne Text softwareBrowserMinChrome; optional; 1-4 numerische Komponenten (z. B. 120.0.6099.71); Standard leer.
    EN: NinjaOne Text softwareBrowserMinChrome; optional; 1-4 numeric components (e.g. 120.0.6099.71); default empty.
.PARAMETER MinEdge
    DE: NinjaOne Text softwareBrowserMinEdge; optional; Format wie MinChrome; Standard leer.
    EN: NinjaOne Text softwareBrowserMinEdge; optional; same format as MinChrome; default empty.
.PARAMETER MinFirefox
    DE: NinjaOne Text softwareBrowserMinFirefox; optional; Format wie MinChrome; Standard leer.
    EN: NinjaOne Text softwareBrowserMinFirefox; optional; same format as MinChrome; default empty.
.PARAMETER MinBrave
    DE: NinjaOne Text softwareBrowserMinBrave; optional; Format wie MinChrome (Dateiversion, z. B. 120.1.61.104); Standard leer.
    EN: NinjaOne Text softwareBrowserMinBrave; optional; same format as MinChrome (file version, e.g. 120.1.61.104); default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readBrowserVersions.ps1
    DE: Nur Inventar der installierten Browser-Versionen.
    EN: Inventory of installed browser versions only.
.EXAMPLE
    .\readBrowserVersions.ps1 -MinChrome 120.0.6099.71 -MinEdge 120.0 -CustomField browserVersions
    DE: Exit 2, wenn Chrome oder Edge älter sind; JSON in browserVersions.
    EN: Exit 2 if Chrome or Edge are older; JSON to browserVersions.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = Browser unter Mindestversion.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = browser below minimum version.
#>
[CmdletBinding()]
param(
    [string]$MinChrome = $env:softwareBrowserMinChrome,
    [string]$MinEdge = $env:softwareBrowserMinEdge,
    [string]$MinFirefox = $env:softwareBrowserMinFirefox,
    [string]$MinBrave = $env:softwareBrowserMinBrave,
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
    $minimumInput = [ordered]@{
        Chrome = Resolve-Setting $MinChrome ''; Edge = Resolve-Setting $MinEdge ''
        Firefox = Resolve-Setting $MinFirefox ''; Brave = Resolve-Setting $MinBrave ''
    }
    $CustomField = Resolve-Setting $CustomField ''
    $minimum = @{}
    foreach ($browser in $minimumInput.Keys) {
        $value = $minimumInput[$browser]
        if (-not $value) { continue }
        if ($value -notmatch '^\d{1,9}(\.\d{1,9}){0,3}$') { throw "softwareBrowserMin${browser}: z. B. / e.g. 120.0.6099.71" }
        $minimum[$browser] = ConvertTo-NormalizedVersion $value
        if ($null -eq $minimum[$browser]) { throw "softwareBrowserMin${browser} ungültig / invalid." }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $definitions = @(
        @{ Browser = 'Chrome'; Exe = 'chrome.exe'; Relative = 'Google\Chrome\Application\chrome.exe' },
        @{ Browser = 'Edge'; Exe = 'msedge.exe'; Relative = 'Microsoft\Edge\Application\msedge.exe' },
        @{ Browser = 'Firefox'; Exe = 'firefox.exe'; Relative = 'Mozilla Firefox\firefox.exe' },
        @{ Browser = 'Brave'; Exe = 'brave.exe'; Relative = 'BraveSoftware\Brave-Browser\Application\brave.exe' }
    )
    $programRoots = @(@($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    $appPathRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')
    $warning = $false
    $browsers = @(foreach ($definition in $definitions) {
        $candidates = New-Object System.Collections.Generic.List[object]
        foreach ($root in $programRoots) { $candidates.Add(@{ Path = ('{0}\{1}' -f $root, $definition.Relative); Source = 'ProgramFiles' }) }
        foreach ($appRoot in $appPathRoots) {
            $keyPath = '{0}\{1}' -f $appRoot, $definition.Exe
            if (-not (Test-Path -LiteralPath $keyPath)) { continue }
            try { $props = Get-ItemProperty -LiteralPath $keyPath -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            $registered = [Environment]::ExpandEnvironmentVariables(([string]$props.'(default)').Trim().Trim('"'))
            # DE: Nur lokale absolute Pfade auf die erwartete EXE. EN: Only local absolute paths to the expected EXE.
            if ($registered -match ('^[A-Za-z]:\\[^"*?<>|]*\\' + [regex]::Escape($definition.Exe) + '$')) {
                $candidates.Add(@{ Path = $registered; Source = 'AppPaths' })
            }
        }
        $seen = @{}
        $installs = @(foreach ($candidate in $candidates) {
            $id = $candidate.Path.ToLowerInvariant()
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            if (-not (Test-Path -LiteralPath $candidate.Path -PathType Leaf)) { continue }
            $info = (Get-Item -LiteralPath $candidate.Path -ErrorAction Stop).VersionInfo
            $version = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
            $belowMinimum = $false
            if ($minimum.ContainsKey($definition.Browser)) { $belowMinimum = ([version]$version) -lt $minimum[$definition.Browser] }
            if ($belowMinimum) { $warning = $true }
            [pscustomobject]@{ Path = $candidate.Path; Source = $candidate.Source; FileVersion = $version; BelowMinimum = $belowMinimum }
        })
        [pscustomobject]@{
            Browser = $definition.Browser
            Installed = $installs.Count -gt 0
            MinimumVersion = if ($minimum.ContainsKey($definition.Browser)) { $minimum[$definition.Browser].ToString() } else { $null }
            Installations = $installs
        }
    })
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ Computer = $env:COMPUTERNAME; Browsers = $browsers })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
