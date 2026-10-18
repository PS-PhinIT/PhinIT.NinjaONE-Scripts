#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Installiert KeePass Password Safe 2 unbeaufsichtigt (Silent) über winget oder eine lokale/UNC-Installationsdatei.
    EN: Installs KeePass Password Safe 2 silently via winget or a local/UNC installer file.
.DESCRIPTION
    DE: Ohne installAllow=true wird nur geprüft, ob KeePass Password Safe 2 maschinenweit installiert ist (Uninstall-Registry
        64/32 Bit, DisplayName-Muster '^KeePass Password Safe 2\.'); es wird nichts installiert. Mit installAllow=true:
        - Quelle Winget (Standard): winget install --id DominikReichl.KeePass --exact --source winget --silent
          --accept-package-agreements --accept-source-agreements --disable-interactivity --scope machine.
          winget.exe wird für SYSTEM unter "$env:ProgramFiles\WindowsApps" (App Installer x64) gesucht.
          winget prüft den SHA256-Hash des Herstellerinstallers gegen das Manifest.
        - Quelle File: installerPath (lokaler Pfad oder UNC, .msi oder .exe) wird in ein neues, nur für
          SYSTEM/Administratoren beschreibbares Arbeitsverzeichnis kopiert, optional per installerSha256
          geprüft und von dort ausgeführt. MSI: msiexec /i "<Datei>" /qn /norestart /l*v "<Log>";
          EXE: /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS. installerArguments ersetzt diese Standardschalter.
        Ist KeePass Password Safe 2 bereits installiert, wird ohne installUpgrade=true nichts ausgeführt (idempotent).
        Nach der Installation wird die Erkennung erneut ausgeführt; fehlt das Produkt, endet das Skript mit 1.
        Erfolgscodes: 0, 3010/1641 bzw. winget 0x8A150109/0x8A15010B (Neustart erforderlich, RebootRequired=true;
        es wird KEIN Neustart ausgelöst), winget 0x8A15002B/0x8A150061 (kein Update/bereits installiert).
        Hinweis: Inno Setup (EXE) bzw. MSI; Plugins nach %ProgramFiles%\KeePass Password Safe 2\Plugins kopieren.
    EN: Without installAllow=true the script only checks whether KeePass Password Safe 2 is installed machine-wide (Uninstall
        registry 64/32-bit, DisplayName pattern '^KeePass Password Safe 2\.'); nothing is installed. With installAllow=true:
        - Source Winget (default): winget install --id DominikReichl.KeePass --exact --source winget --silent
          --accept-package-agreements --accept-source-agreements --disable-interactivity --scope machine.
          winget.exe is located for SYSTEM under "$env:ProgramFiles\WindowsApps" (App Installer x64).
          winget verifies the vendor installer's SHA256 hash against the manifest.
        - Source File: installerPath (local or UNC path, .msi or .exe) is copied into a new work directory that
          only SYSTEM/Administrators can write, optionally verified with installerSha256 and executed from there.
          MSI: msiexec /i "<file>" /qn /norestart /l*v "<log>"; EXE: /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS.
          installerArguments replaces these default switches.
        If KeePass Password Safe 2 is already installed, nothing runs unless installUpgrade=true (idempotent).
        Detection runs again after the installation; if the product is missing, the script exits with 1.
        Success codes: 0, 3010/1641 or winget 0x8A150109/0x8A15010B (reboot required, RebootRequired=true; NO
        reboot is initiated), winget 0x8A15002B/0x8A150061 (no update/already installed).
        Note: Inno Setup (EXE) or MSI; copy plugins to %ProgramFiles%\KeePass Password Safe 2\Plugins.
.PARAMETER AllowInstall
    DE: NinjaOne Checkbox/Text installAllow; true/false; Standard false (nur Prüfung). Ausdrückliche Zustimmung zur Installation.
    EN: NinjaOne checkbox/text installAllow; true/false; default false (check only). Explicit consent to install.
.PARAMETER Source
    DE: NinjaOne Dropdown/Text installSource; Winget oder File; Standard Winget.
    EN: NinjaOne drop-down/text installSource; Winget or File; default Winget.
.PARAMETER InstallerPath
    DE: NinjaOne Text installerPath; nur bei Source=File, Pflicht; vollständiger lokaler Pfad (C:\...) oder UNC-Pfad (\\server\share\...) zu einer .msi- oder .exe-Datei; keine Platzhalter; max. 260 Zeichen.
    EN: NinjaOne text installerPath; Source=File only, required; full local path (C:\...) or UNC path (\\server\share\...) to an .msi or .exe file; no wildcards; max. 260 characters.
.PARAMETER InstallerSha256
    DE: NinjaOne Text installerSha256; optional, nur bei Source=File; erwarteter SHA256-Hash (64 Hex-Zeichen). Dringend empfohlen; der berechnete Hash steht immer im Bericht.
    EN: NinjaOne text installerSha256; optional, Source=File only; expected SHA256 hash (64 hex characters). Strongly recommended; the computed hash is always reported.
.PARAMETER InstallerArguments
    DE: NinjaOne Text installerArguments; optional, nur bei Source=File; ersetzt die Standard-Silent-Schalter (MSI: Zusatzparameter nach /qn /norestart /l*v); max. 1000 Zeichen, keine Steuerzeichen.
    EN: NinjaOne text installerArguments; optional, Source=File only; replaces the default silent switches (MSI: extra properties after /qn /norestart /l*v); max. 1000 characters, no control characters.
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
    .\installKeePass.ps1
    DE: Nur Prüfung: Exit 0, wenn KeePass Password Safe 2 installiert ist, sonst Exit 2. Keine Änderung.
    EN: Check only: exit 0 if KeePass Password Safe 2 is installed, otherwise exit 2. No change.
.EXAMPLE
    .\installKeePass.ps1 -AllowInstall true -WhatIf
    DE: Simuliert die winget-Installation; nichts wird ausgeführt.
    EN: Simulates the winget installation; nothing is executed.
.EXAMPLE
    .\installKeePass.ps1 -AllowInstall true -Source File -InstallerPath '\\fileserver\software\KeePass-2.msi' -InstallerSha256 '<SHA256>' -CustomField installReport
    DE: Installiert aus einer Netzwerkfreigabe mit Hashprüfung und schreibt das JSON in installReport.
    EN: Installs from a network share with hash verification and writes the JSON to installReport.
.NOTES
    DE: Windows PowerShell 5.1, NinjaOne als SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen.
        Silent-Schalter weiterer Programme: Installations-Scripte/SilentSwitches.md.
        Exit 0 = installiert (bereits vorhanden, erfolgreich installiert/aktualisiert oder -WhatIf),
        1 = Eingabe-, Erkennungs-, Installations-, Zeitüberschreitungs- oder Schreibfehler,
        2 = nur Prüfung (installAllow=false) und KeePass Password Safe 2 ist nicht installiert.
    EN: Windows PowerShell 5.1, NinjaOne as SYSTEM, 64-bit. Parameters override NinjaOne variables.
        Silent switches of further programs: Installations-Scripte/SilentSwitches.md.
        Exit 0 = installed (already present, installed/updated successfully or -WhatIf),
        1 = input, detection, installation, timeout or write error,
        2 = check only (installAllow=false) and KeePass Password Safe 2 is not installed.
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
    Name          = 'KeePass Password Safe 2'
    LogName       = 'installKeePass'
    WingetId      = 'DominikReichl.KeePass'
    WingetScope   = 'machine'
    DetectPattern = '^KeePass Password Safe 2\.'
    MsiArguments  = ''
    ExeArguments  = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS'
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
    param([string]$FilePath, [string]$Arguments, [int]$Minutes)
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
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

$workDirectory = $null
try {
    $AllowInstall = Resolve-Setting $AllowInstall 'false'
    $Source = Resolve-Setting $Source 'Winget'
    $InstallerPath = Resolve-Setting $InstallerPath ''
    $InstallerSha256 = Resolve-Setting $InstallerSha256 ''
    $InstallerArguments = Resolve-Setting $InstallerArguments ''
    $Upgrade = Resolve-Setting $Upgrade 'false'
    $TimeoutMinutes = Resolve-Setting $TimeoutMinutes '30'
    $CustomField = Resolve-Setting $CustomField ''

    $allow = ConvertTo-Switch $AllowInstall 'installAllow'
    $upgradeRequested = ConvertTo-Switch $Upgrade 'installUpgrade'
    if ($Source -notin @('Winget', 'File')) { throw 'installSource: Winget oder/or File.' }
    $Source = if ($Source -eq 'Winget') { 'Winget' } else { 'File' }
    $minutes = 0
    if (-not [int]::TryParse($TimeoutMinutes, [ref]$minutes) -or $minutes -lt 1 -or $minutes -gt 240) { throw 'installTimeoutMinutes: 1-240.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($InstallerSha256 -and $InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'installerSha256: 64 Hex-Zeichen / hex characters.' }
    if ($InstallerArguments -and ($InstallerArguments.Length -gt 1000 -or $InstallerArguments -match '[\x00-\x1f]')) { throw 'installerArguments: max. 1000 Zeichen, keine Steuerzeichen / characters, no control characters.' }
    $extension = ''
    if ($Source -eq 'File') {
        if (-not $InstallerPath) { throw 'installerPath ist bei installSource=File erforderlich / is required for installSource=File.' }
        if ($InstallerPath.Length -gt 260 -or $InstallerPath -match '[\x00-\x1f*?"<>|]' -or $InstallerPath -match '(^|\\)\.\.(\\|$)' -or
            $InstallerPath -notmatch '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)[^\\]') {
            throw 'installerPath: vollständiger lokaler oder UNC-Pfad ohne Platzhalter / full local or UNC path without wildcards.'
        }
        $extension = [IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()
        if ($extension -notin @('.msi', '.exe')) { throw 'installerPath: nur .msi oder .exe / only .msi or .exe.' }
        if ($extension -eq '.exe' -and -not $InstallerArguments -and -not $Tool.ExeArguments) { throw 'Keine EXE-Silent-Schalter bekannt; installerArguments angeben / No EXE silent switches known; specify installerArguments.' }
    } elseif ($InstallerPath -or $InstallerSha256 -or $InstallerArguments) {
        throw 'installerPath/installerSha256/installerArguments nur bei installSource=File / only with installSource=File.'
    }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $before = @(Get-InstalledProduct -Pattern $Tool.DetectPattern)
    $after = $before
    $action = 'None'
    $exitCode = $null
    $rebootRequired = $false
    $logPath = $null
    $computedHash = $null
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
            if (-not $wingetPath) { throw 'winget.exe nicht gefunden; installSource=File nutzen / winget.exe not found; use installSource=File.' }
            $verb = if ($mode -eq 'Upgrade') { 'upgrade' } else { 'install' }
            $arguments = @($verb, '--id', $Tool.WingetId, '--exact', '--source', 'winget', '--silent',
                '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--log', ('"{0}"' -f $logPath))
            if ($Tool.WingetScope) { $arguments += @('--scope', $Tool.WingetScope) }
            $commandLine = $arguments -join ' '
            # DE: 0x8A15002B kein Update, 0x8A150061 bereits installiert, 0x8A150109/0x8A15010B Neustart. EN: no update, already installed, reboot.
            $successCodes = @(0, -1978335189, -1978335135, -1978334967, -1978334965)
            $rebootCodes = @(-1978334967, -1978334965)
            if ($PSCmdlet.ShouldProcess($Tool.Name, ('winget {0} {1}' -f $verb, $Tool.WingetId))) {
                $exitCode = Invoke-InstallerProcess -FilePath $wingetPath -Arguments $commandLine -Minutes $minutes
            } else { $action = 'WhatIf' }
        } else {
            if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw ('installerPath nicht gefunden / not found: {0}' -f $InstallerPath) }
            if ($PSCmdlet.ShouldProcess($Tool.Name, ('Installieren aus / Install from {0}' -f $InstallerPath))) {
                $workDirectory = Initialize-SecureWorkDirectory
                $localInstaller = Join-Path $workDirectory ('installer{0}' -f $extension)
                Copy-Item -LiteralPath $InstallerPath -Destination $localInstaller -Force -ErrorAction Stop
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
            if ($successCodes -notcontains $exitCode) {
                throw ('Installer-Exitcode / installer exit code {0} (0x{1:X8}); Log: {2}' -f $exitCode, $exitCode, $logPath)
            }
            $rebootRequired = $rebootCodes -contains $exitCode
            $after = @(Get-InstalledProduct -Pattern $Tool.DetectPattern)
            if ($after.Count -eq 0) { throw ('{0} nach der Installation nicht erkannt / not detected after installation; Log: {1}' -f $Tool.Name, $logPath) }
            $action = if ($mode -eq 'Upgrade') { 'Upgraded' } else { 'Installed' }
        }
    }

    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Tool = $Tool.Name; WingetId = $Tool.WingetId; Mode = $mode; Source = $Source
        Allowed = $allow; WhatIf = [bool]$WhatIfPreference; Action = $action
        InstalledBefore = @($before | Select-Object -First 5); InstalledAfter = @($after | Select-Object -First 5)
        ExitCode = $exitCode; RebootRequired = $rebootRequired; LogPath = $logPath; WingetPath = $wingetPath
        InstallerSha256 = $computedHash
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
