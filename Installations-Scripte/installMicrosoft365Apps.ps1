#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Installiert Microsoft 365 Apps unbeaufsichtigt (Silent) über das Office Deployment Tool, winget oder eine lokale/UNC-Installationsdatei.
    EN: Installs Microsoft 365 Apps silently via the Office Deployment Tool, winget or a local/UNC installer file.
.DESCRIPTION
    DE: Ohne installAllow=true wird nur geprüft, ob Microsoft 365 Apps maschinenweit installiert ist (Uninstall-Registry
        64/32 Bit, DisplayName-Muster '^Microsoft (365|Office 365)\b.* - [a-z]{2}-[a-z]{2}$'); es wird nichts installiert. Mit installAllow=true:
        - Quelle Download (Standard): lädt das Office Deployment Tool (setup.exe) per HTTPS von
          https://officecdn.microsoft.com/pr/wsus/setup.exe in ein neues, nur für SYSTEM/Administratoren beschreibbares
          Arbeitsverzeichnis, prüft die Authenticode-Signatur (gültig, Signierer CN=Microsoft Corporation) und führt
          setup.exe /configure https://aka.ms/fhlwingetconfig aus (Microsoft-Standardkonfiguration wie bei winget:
          Microsoft 365 Apps for enterprise, x64, en-us). Eigene Konfiguration über installerArguments, z. B.
          "/configure \\server\share\config.xml" oder "/configure https://<Rohdaten-URL>/config.xml" (direkter Link
          auf die XML-Datei, keine HTML-Seite). Empfohlen in der XML: Display Level="None" AcceptEULA="TRUE".
          Microsoft ersetzt setup.exe ohne neue Version; daher Signatur- statt fester Hashprüfung (installerSha256 optional).
        - Quelle Winget: winget install --id Microsoft.Office --exact --source winget --silent
          --accept-package-agreements --accept-source-agreements --disable-interactivity --scope machine.
          winget.exe wird für SYSTEM unter "$env:ProgramFiles\WindowsApps" (App Installer x64) gesucht.
          winget prüft den SHA256-Hash gegen das Manifest; bei Microsoft.Office scheitert das häufig mit
          "Installer hash does not match" (0x8A150011), weil setup.exe zwischen Manifest-Updates ersetzt wird.
          Die winget-Ausgabe wird in "<Temp>\installMicrosoft365Apps-<Zeit>-winget.log" protokolliert.
        - Quelle File: installerPath (lokaler Pfad oder UNC, .msi oder .exe) wird in ein neues, nur für
          SYSTEM/Administratoren beschreibbares Arbeitsverzeichnis kopiert, optional per installerSha256
          geprüft und von dort ausgeführt. MSI: msiexec /i "<Datei>" /qn /norestart /l*v "<Log>";
          EXE: /configure https://aka.ms/fhlwingetconfig. installerArguments ersetzt diese Standardschalter.
        Ist Microsoft 365 Apps bereits installiert, wird ohne installUpgrade=true nichts ausgeführt (idempotent).
        Nach der Installation wird die Erkennung erneut ausgeführt; fehlt das Produkt, endet das Skript mit 1.
        Erfolgscodes: 0, 3010/1641 bzw. winget 0x8A150109/0x8A15010B (Neustart erforderlich, RebootRequired=true;
        es wird KEIN Neustart ausgelöst), winget 0x8A15002B/0x8A150061 (kein Update/bereits installiert).
        Hinweis: Das Office Deployment Tool schreibt sein Log nach "%windir%\Temp" (SYSTEM); Pfad per Logging-Element
          der XML änderbar. installTimeoutMinutes 60 empfohlen. Lizenz erforderlich.
    EN: Without installAllow=true the script only checks whether Microsoft 365 Apps is installed machine-wide (Uninstall
        registry 64/32-bit, DisplayName pattern '^Microsoft (365|Office 365)\b.* - [a-z]{2}-[a-z]{2}$'); nothing is installed. With installAllow=true:
        - Source Download (default): downloads the Office Deployment Tool (setup.exe) via HTTPS from
          https://officecdn.microsoft.com/pr/wsus/setup.exe into a new work directory that only SYSTEM/Administrators
          can write, verifies the Authenticode signature (valid, signer CN=Microsoft Corporation) and runs
          setup.exe /configure https://aka.ms/fhlwingetconfig (Microsoft default configuration as used by winget:
          Microsoft 365 Apps for enterprise, x64, en-us). Use installerArguments for your own configuration, e.g.
          "/configure \\server\share\config.xml" or "/configure https://<raw-url>/config.xml" (direct link to the
          XML file, not an HTML page). Recommended in the XML: Display Level="None" AcceptEULA="TRUE".
          Microsoft replaces setup.exe without a new version; hence signature instead of fixed hash verification
          (installerSha256 optional).
        - Source Winget: winget install --id Microsoft.Office --exact --source winget --silent
          --accept-package-agreements --accept-source-agreements --disable-interactivity --scope machine.
          winget.exe is located for SYSTEM under "$env:ProgramFiles\WindowsApps" (App Installer x64).
          winget verifies the SHA256 hash against the manifest; for Microsoft.Office this often fails with
          "Installer hash does not match" (0x8A150011) because setup.exe is replaced between manifest updates.
          The winget output is logged to "<Temp>\installMicrosoft365Apps-<time>-winget.log".
        - Source File: installerPath (local or UNC path, .msi or .exe) is copied into a new work directory that
          only SYSTEM/Administrators can write, optionally verified with installerSha256 and executed from there.
          MSI: msiexec /i "<file>" /qn /norestart /l*v "<log>"; EXE: /configure https://aka.ms/fhlwingetconfig.
          installerArguments replaces these default switches.
        If Microsoft 365 Apps is already installed, nothing runs unless installUpgrade=true (idempotent).
        Detection runs again after the installation; if the product is missing, the script exits with 1.
        Success codes: 0, 3010/1641 or winget 0x8A150109/0x8A15010B (reboot required, RebootRequired=true; NO
        reboot is initiated), winget 0x8A15002B/0x8A150061 (no update/already installed).
        Note: the Office Deployment Tool writes its log to "%windir%\Temp" (SYSTEM); change it with the XML Logging
          element. installTimeoutMinutes 60 recommended. Licence required.
.PARAMETER AllowInstall
    DE: NinjaOne Checkbox/Text installAllow; true/false; Standard false (nur Prüfung). Ausdrückliche Zustimmung zur Installation.
    EN: NinjaOne checkbox/text installAllow; true/false; default false (check only). Explicit consent to install.
.PARAMETER Source
    DE: NinjaOne Dropdown/Text installSource; Download, Winget oder File; Standard Download (Office Deployment Tool von Microsoft).
    EN: NinjaOne drop-down/text installSource; Download, Winget or File; default Download (Office Deployment Tool from Microsoft).
.PARAMETER InstallerPath
    DE: NinjaOne Text installerPath; nur bei Source=File, Pflicht; vollständiger lokaler Pfad (C:\...) oder UNC-Pfad (\\server\share\...) zu einer .msi- oder .exe-Datei; keine Platzhalter; max. 260 Zeichen.
    EN: NinjaOne text installerPath; Source=File only, required; full local path (C:\...) or UNC path (\\server\share\...) to an .msi or .exe file; no wildcards; max. 260 characters.
.PARAMETER InstallerSha256
    DE: NinjaOne Text installerSha256; optional, nur bei Source=File/Download; erwarteter SHA256-Hash (64 Hex-Zeichen). Bei File dringend empfohlen; der berechnete Hash steht immer im Bericht.
    EN: NinjaOne text installerSha256; optional, Source=File/Download only; expected SHA256 hash (64 hex characters). Strongly recommended for File; the computed hash is always reported.
.PARAMETER InstallerArguments
    DE: NinjaOne Text installerArguments; optional, nur bei Source=File/Download; ersetzt die Standardschalter (/configure https://aka.ms/fhlwingetconfig), z. B. "/configure \\server\share\config.xml"; max. 1000 Zeichen, keine Steuerzeichen.
    EN: NinjaOne text installerArguments; optional, Source=File/Download only; replaces the default switches (/configure https://aka.ms/fhlwingetconfig), e.g. "/configure \\server\share\config.xml"; max. 1000 characters, no control characters.
.PARAMETER Upgrade
    DE: NinjaOne Checkbox/Text installUpgrade; true/false; Standard false. true = auch bei vorhandener Installation aktualisieren (winget upgrade bzw. Installer erneut ausführen).
    EN: NinjaOne checkbox/text installUpgrade; true/false; default false. true = update even if already installed (winget upgrade or run the installer again).
.PARAMETER TimeoutMinutes
    DE: NinjaOne Integer/Text installTimeoutMinutes; 1-240; Standard 30. Bei Zeitüberschreitung Exit 1 (Prozess wird nicht beendet).
    EN: NinjaOne integer/text installTimeoutMinutes; 1-240; default 30. On timeout exit 1 (the process is not killed).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes für den JSON-Bericht; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field for the JSON report; default empty.
.EXAMPLE
    .\installMicrosoft365Apps.ps1
    DE: Nur Prüfung: Exit 0, wenn Microsoft 365 Apps installiert ist, sonst Exit 2. Keine Änderung.
    EN: Check only: exit 0 if Microsoft 365 Apps is installed, otherwise exit 2. No change.
.EXAMPLE
    .\installMicrosoft365Apps.ps1 -AllowInstall true -WhatIf
    DE: Simuliert die Installation über das Office Deployment Tool; nichts wird ausgeführt.
    EN: Simulates the installation via the Office Deployment Tool; nothing is executed.
.EXAMPLE
    .\installMicrosoft365Apps.ps1 -AllowInstall true -InstallerArguments '/configure https://raw.githubusercontent.com/<owner>/<repo>/main/office365.xml' -TimeoutMinutes 60
    DE: Lädt das Office Deployment Tool von Microsoft und installiert mit der eigenen XML (Rohdaten-Link).
    EN: Downloads the Office Deployment Tool from Microsoft and installs with your own XML (raw link).
.EXAMPLE
    .\installMicrosoft365Apps.ps1 -AllowInstall true -Source File -InstallerPath '\\fileserver\software\setup.exe' -InstallerSha256 '<SHA256>' -InstallerArguments '/configure \\fileserver\software\Office\config.xml' -CustomField installReport
    DE: Installiert aus einer Netzwerkfreigabe mit Hashprüfung und schreibt das JSON in installReport.
    EN: Installs from a network share with hash verification and writes the JSON to installReport.
.NOTES
    DE: Windows PowerShell 5.1, NinjaOne als SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen.
        Silent-Schalter weiterer Programme: Installations-Scripte/SilentSwitches.md.
        Exit 0 = installiert (bereits vorhanden, erfolgreich installiert/aktualisiert oder -WhatIf),
        1 = Eingabe-, Erkennungs-, Installations-, Zeitüberschreitungs- oder Schreibfehler,
        2 = nur Prüfung (installAllow=false) und Microsoft 365 Apps ist nicht installiert.
    EN: Windows PowerShell 5.1, NinjaOne as SYSTEM, 64-bit. Parameters override NinjaOne variables.
        Silent switches of further programs: Installations-Scripte/SilentSwitches.md.
        Exit 0 = installed (already present, installed/updated successfully or -WhatIf),
        1 = input, detection, installation, timeout or write error,
        2 = check only (installAllow=false) and Microsoft 365 Apps is not installed.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$AllowInstall = $env:installAllow,
    [string]$Source = $env:installSource,
    [string]$InstallerPath = $env:installerPath,
    [string]$InstallerSha256 = $env:installerSha256,
    [string]$InstallerArguments = $env:installerArguments,
    [string]$Upgrade = $env:installUpgrade,
    [string]$TimeoutMinutes = $env:installTimeoutMinutes,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'

# DE: Werkzeugspezifische Einstellungen. EN: Tool-specific settings.
$Tool = [ordered]@{
    Name           = 'Microsoft 365 Apps'
    LogName        = 'installMicrosoft365Apps'
    WingetId       = 'Microsoft.Office'
    WingetScope    = 'machine'
    DetectPattern  = '^Microsoft (365|Office 365)\b.* - [a-z]{2}-[a-z]{2}$'
    MsiArguments   = ''
    ExeArguments   = '/configure https://aka.ms/fhlwingetconfig'
    # DE: Office Deployment Tool direkt von Microsoft (winget-Hash veraltet oft). EN: Office Deployment Tool directly from Microsoft (winget hash is often stale).
    DefaultSource  = 'Download'
    DownloadUrl    = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
    DownloadSigner = 'Microsoft Corporation'
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
function Get-InstalledProduct {
    param([string]$Pattern)
    $roots = [ordered]@{
        Registry64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Registry32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    }
    foreach ($view in $roots.Keys) {
        if (-not (Test-Path -LiteralPath $roots[$view])) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $roots[$view] -ErrorAction Stop)) {
            # DE: Während Installationen entfernte Schlüssel überspringen. EN: Skip keys removed during installs.
            try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            $display = [string]$props.DisplayName
            if ([string]::IsNullOrWhiteSpace($display) -or $display.Trim() -notmatch $Pattern) { continue }
            [pscustomobject]@{ Name = $display.Trim(); Version = [string]$props.DisplayVersion; Publisher = [string]$props.Publisher; RegistryView = $view }
        }
    }
}
function Find-Winget {
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { return $null }
    $appsRoot = '{0}\WindowsApps' -f $env:ProgramFiles.TrimEnd('\')
    if (Test-Path -LiteralPath $appsRoot -PathType Container) {
        $packages = @(Get-ChildItem -LiteralPath $appsRoot -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
            $match = [regex]::Match([string]$_.Name, '^Microsoft\.DesktopAppInstaller_(\d+(?:\.\d+){1,3})_x64__8wekyb3d8bbwe$', 'IgnoreCase')
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
function Invoke-InstallerProcess {
    param([string]$FilePath, [string]$Arguments, [int]$Minutes, [string]$OutputPath)
    $startArguments = @{ FilePath = $FilePath; ArgumentList = $Arguments; PassThru = $true; WindowStyle = 'Hidden' }
    if ($OutputPath) { $startArguments.RedirectStandardOutput = $OutputPath }
    $process = Start-Process @startArguments
    # DE: Handle cachen, damit ExitCode verfügbar bleibt. EN: Cache the handle so ExitCode stays available.
    $null = $process.Handle
    if (-not $process.WaitForExit($Minutes * 60000)) {
        throw ('Zeitüberschreitung nach {0} Minuten / Timeout after {0} minutes: {1}' -f $Minutes, $FilePath)
    }
    return [int]$process.ExitCode
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
function Save-VendorInstaller {
    param([string]$Uri, [string]$Destination, [string]$Signer, [int]$Minutes)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # DE: Fortschrittsanzeige bremst Downloads in PowerShell 5.1. EN: The progress bar slows downloads in PowerShell 5.1.
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec ($Minutes * 60) -ErrorAction Stop
    # DE: Herstellerdatei per Authenticode prüfen (Datei ändert sich, fester Hash wäre veraltet). EN: Verify the vendor file via Authenticode (file changes, a fixed hash would be stale).
    $signature = Get-AuthenticodeSignature -LiteralPath $Destination -ErrorAction Stop
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ([string]$signature.Status -ne 'Valid' -or $subject -notmatch ('^CN="?{0}"?(,|$)' -f [regex]::Escape($Signer))) {
        throw ('Signatur ungültig / Invalid signature: {0} {1}' -f $signature.Status, $subject)
    }
    return $subject
}
function Get-ExistingLog {
    param([string[]]$Path)
    @($Path | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
}
function Get-OutputTail {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    # DE: Fortschrittsbalken und leere Zeilen auslassen. EN: Skip progress bars and empty lines.
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { ([string]$_ -split "`r")[-1].Trim() } |
        Where-Object { $_ -match '^[\p{L}\p{N}]' })
    return (@($lines | Select-Object -Last 3) -join ' | ')
}

$workDirectory = $null
try {
    $AllowInstall = Resolve-Setting $AllowInstall 'false'
    $Source = Resolve-Setting $Source (Resolve-Setting $Tool['DefaultSource'] 'Winget')
    $InstallerPath = Resolve-Setting $InstallerPath ''
    $InstallerSha256 = Resolve-Setting $InstallerSha256 ''
    $InstallerArguments = Resolve-Setting $InstallerArguments ''
    $Upgrade = Resolve-Setting $Upgrade 'false'
    $TimeoutMinutes = Resolve-Setting $TimeoutMinutes '30'
    $CustomField = Resolve-Setting $CustomField ''

    $allow = ConvertTo-Switch $AllowInstall 'installAllow'
    $upgradeRequested = ConvertTo-Switch $Upgrade 'installUpgrade'
    $Source = @('Winget', 'File', 'Download') | Where-Object { $_ -eq $Source } | Select-Object -First 1
    if (-not $Source) { throw 'installSource: Winget, File oder/or Download.' }
    $minutes = 0
    if (-not [int]::TryParse($TimeoutMinutes, [ref]$minutes) -or $minutes -lt 1 -or $minutes -gt 240) { throw 'installTimeoutMinutes: 1-240.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($InstallerSha256 -and $InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'installerSha256: 64 Hex-Zeichen / hex characters.' }
    if ($InstallerArguments -and ($InstallerArguments.Length -gt 1000 -or $InstallerArguments -match '[\x00-\x1f]')) { throw 'installerArguments: max. 1000 Zeichen, keine Steuerzeichen / characters, no control characters.' }
    $extension = ''
    if ($Source -eq 'Download') {
        if (-not $Tool['DownloadUrl'] -or -not $Tool['DownloadSigner']) { throw 'installSource=Download für dieses Tool nicht verfügbar / not available for this tool.' }
        if ($InstallerPath) { throw 'installerPath nur bei installSource=File / only with installSource=File.' }
        $extension = [IO.Path]::GetExtension(([uri]$Tool.DownloadUrl).AbsolutePath).ToLowerInvariant()
        if ($Tool.DownloadUrl -notmatch '^https://' -or $extension -notin @('.msi', '.exe')) { throw 'DownloadUrl: nur HTTPS mit .msi/.exe / HTTPS .msi/.exe only.' }
        if ($extension -eq '.exe' -and -not $InstallerArguments -and -not $Tool.ExeArguments) { throw 'Keine EXE-Silent-Schalter bekannt; installerArguments angeben / No EXE silent switches known; specify installerArguments.' }
    } elseif ($Source -eq 'File') {
        if (-not $InstallerPath) { throw 'installerPath ist bei installSource=File erforderlich / is required for installSource=File.' }
        if ($InstallerPath.Length -gt 260 -or $InstallerPath -match '[\x00-\x1f*?"<>|]' -or $InstallerPath -match '(^|\\)\.\.(\\|$)' -or
            $InstallerPath -notmatch '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)[^\\]') {
            throw 'installerPath: vollständiger lokaler oder UNC-Pfad ohne Platzhalter / full local or UNC path without wildcards.'
        }
        $extension = [IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()
        if ($extension -notin @('.msi', '.exe')) { throw 'installerPath: nur .msi oder .exe / only .msi or .exe.' }
        if ($extension -eq '.exe' -and -not $InstallerArguments -and -not $Tool.ExeArguments) { throw 'Keine EXE-Silent-Schalter bekannt; installerArguments angeben / No EXE silent switches known; specify installerArguments.' }
    } elseif ($InstallerPath -or $InstallerSha256 -or $InstallerArguments) {
        throw 'installerPath/installerSha256/installerArguments nur bei installSource=File/Download / only with installSource=File/Download.'
    }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $before = @(Get-InstalledProduct -Pattern $Tool.DetectPattern)
    $after = $before
    $action = 'None'
    $exitCode = $null
    $rebootRequired = $false
    $logPath = $null
    $outputPath = $null
    $logs = @()
    $computedHash = $null
    $signer = $null
    $wingetPath = $null
    $mode = if (-not $allow) { 'Audit' } elseif ($before.Count -gt 0 -and $upgradeRequested) { 'Upgrade' } else { 'Install' }

    if (-not $allow) {
        $action = if ($before.Count -gt 0) { 'AlreadyInstalled' } else { 'NotInstalled' }
    } elseif ($before.Count -gt 0 -and -not $upgradeRequested) {
        $action = 'AlreadyInstalled'
    } else {
        $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
        $logPath = Join-Path ([IO.Path]::GetTempPath()) ('{0}-{1}.log' -f $Tool.LogName, $stamp)
        $successCodes = @(0, 3010, 1641)
        $rebootCodes = @(3010, 1641)
        if ($Source -eq 'Winget') {
            $wingetPath = Find-Winget
            $outputPath = Join-Path ([IO.Path]::GetTempPath()) ('{0}-{1}-winget.log' -f $Tool.LogName, $stamp)
            if (-not $wingetPath) { throw 'winget.exe nicht gefunden; installSource=File nutzen / winget.exe not found; use installSource=File.' }
            $verb = if ($mode -eq 'Upgrade') { 'upgrade' } else { 'install' }
            $arguments = @($verb, '--id', $Tool.WingetId, '--exact', '--source', 'winget', '--silent',
                '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--log', ('"{0}"' -f $logPath))
            # DE: Installertyp erzwingen (z. B. MSI statt MSIX, das --scope machine ignoriert). EN: Force the installer type (e.g. MSI instead of MSIX, which ignores --scope machine).
            if ($Tool['WingetInstallerType']) { $arguments += @('--installer-type', $Tool.WingetInstallerType) }
            if ($Tool.WingetScope) { $arguments += @('--scope', $Tool.WingetScope) }
            $commandLine = $arguments -join ' '
            # DE: 0x8A15002B kein Update, 0x8A150061 bereits installiert, 0x8A150109/0x8A15010B Neustart. EN: no update, already installed, reboot.
            $successCodes = @(0, -1978335189, -1978335135, -1978334967, -1978334965)
            $rebootCodes = @(-1978334967, -1978334965)
            if ($PSCmdlet.ShouldProcess($Tool.Name, ('winget {0} {1}' -f $verb, $Tool.WingetId))) {
                # DE: winget-Ausgabe protokollieren; --log greift nur, wenn das Manifest einen Log-Schalter hat. EN: Capture winget output; --log only applies if the manifest has a log switch.
                $exitCode = Invoke-InstallerProcess -FilePath $wingetPath -Arguments $commandLine -Minutes $minutes -OutputPath $outputPath
            } else { $action = 'WhatIf' }
        } else {
            if ($Source -eq 'File' -and -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw ('installerPath nicht gefunden / not found: {0}' -f $InstallerPath) }
            $origin = if ($Source -eq 'Download') { $Tool.DownloadUrl } else { $InstallerPath }
            if ($PSCmdlet.ShouldProcess($Tool.Name, ('Installieren aus / Install from {0}' -f $origin))) {
                $workDirectory = Initialize-SecureWorkDirectory
                $localInstaller = Join-Path $workDirectory ('installer{0}' -f $extension)
                if ($Source -eq 'Download') {
                    $signer = Save-VendorInstaller -Uri $Tool.DownloadUrl -Destination $localInstaller -Signer $Tool.DownloadSigner -Minutes $minutes
                } else {
                    Copy-Item -LiteralPath $InstallerPath -Destination $localInstaller -Force -ErrorAction Stop
                }
                $computedHash = (Get-FileHash -LiteralPath $localInstaller -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
                if ($InstallerSha256 -and $computedHash -ne $InstallerSha256.ToUpperInvariant()) {
                    throw ('SHA256 stimmt nicht überein / SHA256 mismatch: {0}' -f $computedHash)
                }
                if ($extension -eq '.msi') {
                    $extra = if ($InstallerArguments) { $InstallerArguments } else { $Tool.MsiArguments }
                    $commandLine = ('/i "{0}" /qn /norestart /l*v "{1}" {2}' -f $localInstaller, $logPath, $extra).Trim()
                    $exitCode = Invoke-InstallerProcess -FilePath 'msiexec.exe' -Arguments $commandLine -Minutes $minutes
                } else {
                    $logPath = $null
                    $commandLine = if ($InstallerArguments) { $InstallerArguments } else { $Tool.ExeArguments }
                    $exitCode = Invoke-InstallerProcess -FilePath $localInstaller -Arguments $commandLine -Minutes $minutes
                }
            } else { $action = 'WhatIf' }
        }
        if ($action -ne 'WhatIf') {
            $logs = @(Get-ExistingLog @($logPath, $outputPath))
            $logHint = if ($logs.Count -gt 0) { 'Log: {0}' -f ($logs -join ', ') } else { 'kein Log / no log' }
            if ($successCodes -notcontains $exitCode) {
                $detail = Get-OutputTail $outputPath
                if ($Source -eq 'Winget' -and $exitCode -eq -1978335215) {
                    # DE: 0x8A150011 Hash passt nicht zum Manifest (Herstellerdatei geändert). EN: Hash does not match the manifest (vendor file changed).
                    $detail = ('{0} Installer-Hash weicht vom winget-Manifest ab / installer hash does not match the winget manifest; installSource=Download oder/or File nutzen / use.' -f $detail).Trim()
                }
                throw ('Installer-Exitcode / installer exit code {0} (0x{1:X8}); {2}{3}' -f $exitCode, $exitCode, $logHint, $(if ($detail) { '; ' + $detail } else { '' }))
            }
            $rebootRequired = $rebootCodes -contains $exitCode
            $after = @(Get-InstalledProduct -Pattern $Tool.DetectPattern)
            if ($after.Count -eq 0) {
                $detail = Get-OutputTail $outputPath
                throw ('{0} nach der Installation nicht erkannt / not detected after installation (Exitcode / exit code {1}); {2}{3}' -f $Tool.Name, $exitCode, $logHint, $(if ($detail) { '; ' + $detail } else { '' }))
            }
            $action = if ($mode -eq 'Upgrade') { 'Upgraded' } else { 'Installed' }
        }
    }

    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Tool = $Tool.Name; WingetId = $Tool.WingetId; Mode = $mode; Source = $Source
        Allowed = $allow; WhatIf = [bool]$WhatIfPreference; Action = $action
        InstalledBefore = @($before | Select-Object -First 5); InstalledAfter = @($after | Select-Object -First 5)
        ExitCode = $exitCode; RebootRequired = $rebootRequired; LogPath = $(if ($logs) { $logs -join ', ' } else { $null }); WingetPath = $wingetPath
        DownloadUrl = $(if ($Source -eq 'Download') { $Tool.DownloadUrl } else { $null }); InstallerSha256 = $computedHash; InstallerSigner = $signer
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($action -eq 'NotInstalled') { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
finally {
    if ($workDirectory -and (Test-Path -LiteralPath $workDirectory)) { Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue }
}
