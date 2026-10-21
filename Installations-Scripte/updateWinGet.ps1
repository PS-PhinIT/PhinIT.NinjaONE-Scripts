#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Aktualisiert die lokale WinGet-Installation (App Installer) oder installiert sie, falls sie fehlt.
    EN: Updates the local WinGet installation (App Installer) or installs it if it is missing.
.DESCRIPTION
    DE: Sucht winget.exe wie die Installationsskripte für SYSTEM unter "$env:ProgramFiles\WindowsApps"
        (Microsoft.DesktopAppInstaller, Architektur des Betriebssystems x64/arm64), liest die Version per
        winget --version und vergleicht sie mit dem neuesten stabilen Release von github.com/microsoft/winget-cli
        (GitHub-API releases/latest, keine Vorabversionen). Ohne installAllow=true wird nur geprüft; es wird nichts
        geändert. Mit installAllow=true und fehlender, nicht lauffähiger oder veralteter Installation:
        - Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle, die Lizenzdatei (*_License1.xml) und
          DesktopAppInstaller_Dependencies.zip (VCLibs, Windows App Runtime) dieses Releases werden per HTTPS in ein
          neues, nur für SYSTEM/Administratoren beschreibbares Arbeitsverzeichnis geladen.
        - SHA256 von Paket und Abhängigkeiten wird gegen die veröffentlichten Hashdateien (*.txt) geprüft, die
          Authenticode-Signatur jedes Pakets muss gültig sein und von "Microsoft Corporation" stammen.
        - Add-AppxProvisionedPackage -Online stellt App Installer samt Abhängigkeiten maschinenweit bereit
          (Provisionierung); vorhandene Benutzer erhalten die neue Version in der Regel bei der nächsten Anmeldung.
        Danach wird winget erneut gesucht; liegt die Version unter der Release-Version, endet das Skript mit 1.
        Eine aktuelle Installation bleibt unverändert (idempotent). Es wird kein Neustart ausgelöst.
        Voraussetzungen: Windows 10 1809 oder neuer, Windows 11 oder Windows Server 2022 oder neuer; Zugriff auf
        api.github.com und github.com (anonym max. 60 API-Abfragen pro Stunde je öffentlicher IP).
    EN: Locates winget.exe for SYSTEM like the install scripts under "$env:ProgramFiles\WindowsApps"
        (Microsoft.DesktopAppInstaller, operating system architecture x64/arm64), reads its version via
        winget --version and compares it with the latest stable release of github.com/microsoft/winget-cli
        (GitHub API releases/latest, no pre-releases). Without installAllow=true the script only checks; nothing is
        changed. With installAllow=true and a missing, unusable or outdated installation:
        - Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle, the licence file (*_License1.xml) and
          DesktopAppInstaller_Dependencies.zip (VCLibs, Windows App Runtime) of that release are downloaded via HTTPS
          into a new work directory that only SYSTEM/Administrators can write.
        - The SHA256 of package and dependencies is verified against the published hash files (*.txt); every
          package needs a valid Authenticode signature from "Microsoft Corporation".
        - Add-AppxProvisionedPackage -Online provisions App Installer and its dependencies machine-wide; existing
          users usually receive the new version at their next sign-in.
        winget is located again afterwards; if its version is below the release version, the script exits with 1.
        An up-to-date installation is left unchanged (idempotent). No reboot is initiated.
        Requirements: Windows 10 1809 or later, Windows 11 or Windows Server 2022 or later; access to api.github.com
        and github.com (anonymous limit of 60 API requests per hour per public IP).
.PARAMETER AllowInstall
    DE: NinjaOne Checkbox/Text installAllow; true/false; Standard false (nur Prüfung). Ausdrückliche Zustimmung zur Installation/Aktualisierung.
    EN: NinjaOne checkbox/text installAllow; true/false; default false (check only). Explicit consent to install/update.
.PARAMETER TimeoutMinutes
    DE: NinjaOne Integer/Text installTimeoutMinutes; 1-240; Standard 30. Maximale Dauer je Download bzw. winget-Aufruf; bei Zeitüberschreitung Exit 1.
    EN: NinjaOne integer/text installTimeoutMinutes; 1-240; default 30. Maximum duration per download or winget call; on timeout exit 1.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes für den JSON-Bericht; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field for the JSON report; default empty.
.EXAMPLE
    .\updateWinGet.ps1
    DE: Nur Prüfung: Exit 0, wenn winget aktuell ist, sonst Exit 2. Keine Änderung.
    EN: Check only: exit 0 if winget is up to date, otherwise exit 2. No change.
.EXAMPLE
    .\updateWinGet.ps1 -AllowInstall true -WhatIf
    DE: Zeigt, ob WinGet installiert oder aktualisiert würde; nichts wird geladen oder installiert.
    EN: Shows whether WinGet would be installed or updated; nothing is downloaded or installed.
.EXAMPLE
    .\updateWinGet.ps1 -AllowInstall true -CustomField wingetReport
    DE: Installiert bzw. aktualisiert WinGet und schreibt das JSON in wingetReport.
    EN: Installs or updates WinGet and writes the JSON to wingetReport.
.NOTES
    DE: Windows PowerShell 5.1, NinjaOne als SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen.
        Exit 0 = WinGet aktuell (bereits aktuell, erfolgreich installiert/aktualisiert oder -WhatIf),
        1 = Eingabe-, Abfrage-, Download-, Prüf-, Installations-, Zeitüberschreitungs- oder Schreibfehler,
        2 = nur Prüfung (installAllow=false) und WinGet fehlt, ist nicht lauffähig oder veraltet.
    EN: Windows PowerShell 5.1, NinjaOne as SYSTEM, 64-bit. Parameters override NinjaOne variables.
        Exit 0 = WinGet up to date (already current, installed/updated successfully or -WhatIf),
        1 = input, query, download, verification, installation, timeout or write error,
        2 = check only (installAllow=false) and WinGet is missing, unusable or outdated.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$AllowInstall = $env:installAllow,
    [string]$TimeoutMinutes = $env:installTimeoutMinutes,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'

# DE: Offizielle Release-Quelle. EN: Official release source.
$Release = [ordered]@{
    ApiUrl           = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    DownloadRoot     = 'https://github.com/microsoft/winget-cli/releases/download/'
    Bundle           = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    BundleHash       = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt'
    Dependencies     = 'DesktopAppInstaller_Dependencies.zip'
    DependenciesHash = 'DesktopAppInstaller_Dependencies.txt'
    LicensePattern   = '^[A-Za-z0-9]+_License1\.xml$'
    Signer           = 'Microsoft Corporation'
}

function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-Switch {
    param([string]$Value, [string]$Name)
    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $parsed
}
function Get-OsArchitecture {
    $name = $null
    try { $name = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture } catch { $name = $null }
    if (-not $name) { $name = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
    switch -Regex ([string]$name) {
        '^(X64|AMD64)$' { return 'x64' }
        '^ARM64$' { return 'arm64' }
    }
    return $null
}
function Find-Winget {
    param([string]$Architecture)
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { return $null }
    $appsRoot = '{0}\WindowsApps' -f $env:ProgramFiles.TrimEnd('\')
    if (Test-Path -LiteralPath $appsRoot -PathType Container) {
        $pattern = '^Microsoft\.DesktopAppInstaller_(\d+(?:\.\d+){{1,3}})_{0}__8wekyb3d8bbwe$' -f [regex]::Escape($Architecture)
        $packages = @(Get-ChildItem -LiteralPath $appsRoot -Filter ('Microsoft.DesktopAppInstaller_*_{0}__8wekyb3d8bbwe' -f $Architecture) -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
            $match = [regex]::Match([string]$_.Name, $pattern, 'IgnoreCase')
            $version = $null
            if ($match.Success -and [version]::TryParse($match.Groups[1].Value, [ref]$version)) {
                [pscustomobject]@{ Version = $version; Path = ('{0}\{1}\winget.exe' -f $appsRoot, $_.Name) }
            }
        } | Sort-Object Version -Descending)
        foreach ($package in $packages) {
            if (Test-Path -LiteralPath $package.Path -PathType Leaf) { return $package.Path }
        }
    }
    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return [string]$command.Source }
    return $null
}
function Invoke-ProcessWithTimeout {
    param([string]$FilePath, [string]$Arguments, [int]$Minutes, [string]$OutputPath)
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $OutputPath
    # DE: Handle cachen, damit ExitCode verfügbar bleibt. EN: Cache the handle so ExitCode stays available.
    $null = $process.Handle
    if (-not $process.WaitForExit($Minutes * 60000)) {
        throw ('Zeitüberschreitung nach {0} Minuten / Timeout after {0} minutes: {1}' -f $Minutes, $FilePath)
    }
    return [int]$process.ExitCode
}
function Get-WingetVersion {
    param([string]$Path, [int]$Minutes)
    if (-not $Path) { return $null }
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) ('updateWinGet-{0}-version.txt' -f [guid]::NewGuid().ToString('N'))
    try {
        $null = Invoke-ProcessWithTimeout -FilePath $Path -Arguments '--version' -Minutes $Minutes -OutputPath $outputPath
        $text = @(Get-Content -LiteralPath $outputPath -ErrorAction SilentlyContinue) -join ' '
    } finally {
        Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    }
    $match = [regex]::Match([string]$text, '\bv?(\d+\.\d+\.\d+(?:\.\d+)?)')
    $version = $null
    if ($match.Success -and [version]::TryParse($match.Groups[1].Value, [ref]$version)) { return $version }
    return $null
}
function Get-LatestRelease {
    param([int]$Minutes)
    $response = Invoke-RestMethod -Uri $Release.ApiUrl -UseBasicParsing -TimeoutSec ($Minutes * 60) -Headers @{ Accept = 'application/vnd.github+json' } -ErrorAction Stop
    $tag = [string]$response.tag_name
    $match = [regex]::Match($tag, '^v(\d+\.\d+\.\d+(?:\.\d+)?)$')
    if (-not $match.Success) { throw ('Unerwartetes Release-Tag / Unexpected release tag: {0}' -f $tag) }
    # DE: Nur Dateien dieses Releases aus dem offiziellen Repository übernehmen. EN: Only accept files of this release from the official repository.
    $assets = @{}
    foreach ($asset in @($response.assets)) {
        $name = [string]$asset.name
        $url = [string]$asset.browser_download_url
        if ($name -and $url -ceq ('{0}{1}/{2}' -f $Release.DownloadRoot, $tag, $name)) { $assets[$name] = $url }
    }
    foreach ($required in @($Release.Bundle, $Release.BundleHash, $Release.Dependencies, $Release.DependenciesHash)) {
        if (-not $assets.ContainsKey($required)) { throw ('Release-Datei fehlt / Release file missing: {0} ({1})' -f $required, $tag) }
    }
    $license = @($assets.Keys | Where-Object { $_ -match $Release.LicensePattern } | Sort-Object) | Select-Object -First 1
    if (-not $license) { throw ('Lizenzdatei fehlt / Licence file missing ({0})' -f $tag) }
    [pscustomobject]@{
        Tag = $tag; Version = [version]$match.Groups[1].Value
        BundleUrl = $assets[$Release.Bundle]; BundleHashUrl = $assets[$Release.BundleHash]
        DependenciesUrl = $assets[$Release.Dependencies]; DependenciesHashUrl = $assets[$Release.DependenciesHash]
        LicenseName = $license; LicenseUrl = $assets[$license]
    }
}
function Initialize-SecureWorkDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('PhinIT-Install-{0}' -f [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop
    # DE: Nur SYSTEM und Administratoren dürfen schreiben (kein DLL-Planting). EN: Only SYSTEM and Administrators may write (no DLL planting).
    $global:LASTEXITCODE = 0
    $null = icacls $path '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
    if ($global:LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        throw ('icacls Exitcode / exit code {0}' -f $global:LASTEXITCODE)
    }
    return $path
}
function Save-ReleaseFile {
    param([string]$Uri, [string]$Destination, [int]$Minutes)
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec ($Minutes * 60) -ErrorAction Stop
}
function Get-PublishedHash {
    param([string]$Path)
    $text = ([string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)).Trim()
    if ($text -notmatch '^[A-Fa-f0-9]{64}$') { throw ('Ungültige Hashdatei / Invalid hash file: {0}' -f (Split-Path $Path -Leaf)) }
    return $text.ToUpperInvariant()
}
function Assert-FileHash {
    param([string]$Path, [string]$Expected)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    if ($hash -ne $Expected) { throw ('SHA256 stimmt nicht überein / SHA256 mismatch: {0} ({1})' -f (Split-Path $Path -Leaf), $hash) }
    return $hash
}
function Assert-PackageSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ([string]$signature.Status -ne 'Valid' -or $subject -notmatch ('^CN="?{0}"?(,|$)' -f [regex]::Escape($Release.Signer))) {
        throw ('Signatur ungültig / Invalid signature: {0} {1} {2}' -f (Split-Path $Path -Leaf), $signature.Status, $subject)
    }
    return $subject
}

$workDirectory = $null
try {
    $AllowInstall = Resolve-Setting $AllowInstall 'false'
    $TimeoutMinutes = Resolve-Setting $TimeoutMinutes '30'
    $CustomField = Resolve-Setting $CustomField ''

    $allow = ConvertTo-Switch $AllowInstall 'installAllow'
    $minutes = 0
    if (-not [int]::TryParse($TimeoutMinutes, [ref]$minutes) -or $minutes -lt 1 -or $minutes -gt 240) { throw 'installTimeoutMinutes: 1-240.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    $architecture = Get-OsArchitecture
    if (-not $architecture) { throw 'Nur x64 oder arm64 unterstützt / Only x64 or arm64 supported.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # DE: Fortschrittsanzeige bremst Downloads in PowerShell 5.1. EN: The progress bar slows downloads in PowerShell 5.1.
    $ProgressPreference = 'SilentlyContinue'

    $wingetPath = Find-Winget -Architecture $architecture
    $versionBefore = Get-WingetVersion -Path $wingetPath -Minutes $minutes
    $versionAfter = $versionBefore
    $wingetPathAfter = $wingetPath
    $state = if (-not $wingetPath) { 'NotInstalled' } elseif (-not $versionBefore) { 'Unusable' } else { 'Installed' }
    $latest = Get-LatestRelease -Minutes $minutes
    $current = $state -eq 'Installed' -and $versionBefore -ge $latest.Version
    $mode = if (-not $allow) { 'Audit' } elseif ($state -eq 'Installed') { 'Update' } else { 'Install' }
    $action = 'None'
    $bundleHash = $null
    $signer = $null

    if ($current) {
        $action = 'UpToDate'
    } elseif (-not $allow) {
        $action = if ($state -eq 'Installed') { 'UpdateAvailable' } else { $state }
    } elseif ($PSCmdlet.ShouldProcess('WinGet (App Installer)', ('Bereitstellen / Provision {0}' -f $latest.Tag))) {
        $workDirectory = Initialize-SecureWorkDirectory
        $bundlePath = Join-Path $workDirectory $Release.Bundle
        $bundleHashPath = Join-Path $workDirectory $Release.BundleHash
        $dependenciesPath = Join-Path $workDirectory $Release.Dependencies
        $dependenciesHashPath = Join-Path $workDirectory $Release.DependenciesHash
        $licensePath = Join-Path $workDirectory $latest.LicenseName
        $dependenciesFolder = Join-Path $workDirectory 'Dependencies'

        Save-ReleaseFile -Uri $latest.BundleHashUrl -Destination $bundleHashPath -Minutes $minutes
        Save-ReleaseFile -Uri $latest.DependenciesHashUrl -Destination $dependenciesHashPath -Minutes $minutes
        Save-ReleaseFile -Uri $latest.LicenseUrl -Destination $licensePath -Minutes $minutes
        Save-ReleaseFile -Uri $latest.DependenciesUrl -Destination $dependenciesPath -Minutes $minutes
        Save-ReleaseFile -Uri $latest.BundleUrl -Destination $bundlePath -Minutes $minutes

        $null = Assert-FileHash -Path $dependenciesPath -Expected (Get-PublishedHash $dependenciesHashPath)
        $bundleHash = Assert-FileHash -Path $bundlePath -Expected (Get-PublishedHash $bundleHashPath)
        $signer = Assert-PackageSignature -Path $bundlePath

        Expand-Archive -LiteralPath $dependenciesPath -DestinationPath $dependenciesFolder -Force -ErrorAction Stop
        $dependencyPackages = @(Get-ChildItem -LiteralPath (Join-Path $dependenciesFolder $architecture) -Filter '*.appx' -ErrorAction Stop |
            Where-Object { -not $_.PSIsContainer } | ForEach-Object { [string]$_.FullName } | Sort-Object)
        if ($dependencyPackages.Count -eq 0) { throw ('Keine Abhängigkeiten für / No dependencies for {0}' -f $architecture) }
        foreach ($package in $dependencyPackages) { $null = Assert-PackageSignature -Path $package }

        $null = Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -DependencyPackagePath $dependencyPackages -LicensePath $licensePath -ErrorAction Stop

        $wingetPathAfter = Find-Winget -Architecture $architecture
        $versionAfter = Get-WingetVersion -Path $wingetPathAfter -Minutes $minutes
        if (-not $versionAfter -or $versionAfter -lt $latest.Version) {
            throw ('WinGet nach der Bereitstellung nicht aktuell / not current after provisioning: {0} < {1} ({2})' -f $(if ($versionAfter) { $versionAfter } else { 'n/a' }), $latest.Version, $(if ($wingetPathAfter) { $wingetPathAfter } else { 'winget.exe nicht gefunden / not found' }))
        }
        $action = if ($mode -eq 'Update') { 'Updated' } else { 'Installed' }
    } else {
        $action = 'WhatIf'
    }

    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Tool = 'WinGet (App Installer)'; Mode = $mode; Allowed = $allow
        WhatIf = [bool]$WhatIfPreference; Action = $action; State = $state; Architecture = $architecture
        VersionBefore = $(if ($versionBefore) { $versionBefore.ToString() } else { $null })
        VersionAfter = $(if ($versionAfter) { $versionAfter.ToString() } else { $null })
        LatestVersion = $latest.Version.ToString(); ReleaseTag = $latest.Tag
        WingetPath = $wingetPathAfter; DownloadUrl = $latest.BundleUrl; InstallerSha256 = $bundleHash; InstallerSigner = $signer
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($action -in @('NotInstalled', 'Unusable', 'UpdateAvailable')) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
finally {
    if ($workDirectory -and (Test-Path -LiteralPath $workDirectory)) { Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue }
}
