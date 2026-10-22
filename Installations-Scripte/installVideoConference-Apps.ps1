# NinjaOne RMM - Global Video Conference & Collaboration Software Installer
# ======================================================================================
# NINJAONE CONFIGURATION:
# Architecture: Windows PowerShell
# Run As: SYSTEM
#
# PARAMETERS / CHOICE FIELD CONFIGURATION:
# In the Script Settings in NinjaOne, create a parameter variable named: app
# Configure it as a "Choice" or "Text" field with the following allowed values:
# "all", "teams", "zoom", "webex", "skype", "slack", "discord", "gotomeeting", "bluejeans", "teamviewer", "anydesk"
# ======================================================================================

# Fallback value if no parameter is passed from NinjaOne
if (!($env:app) -and ($args.Count -gt 0)) {
    $env:app = $args[0]
}
if (!($env:app)) {
    $env:app = "all"
}

$LogFile = "$env:ProgramData\NinjaOne\Logs\VideoConference_Installation.log"
$LogDir = Split-Path $LogFile
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

"--- Start der Installation (Auswahl: $($env:app)): $(Get-Date) ---" | Out-File -FilePath $LogFile -Append

# WinGet-Pfad auflösen (SYSTEM-Kontext Fix für RMM)
$WinGetPath = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (!$WinGetPath) { $WinGetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path }
if (!$WinGetPath -or !(Test-Path $WinGetPath)) { 
    "FEHLER: winget.exe fehlt auf diesem System oder ist im System-Kontext nicht initialisiert." | Out-File -FilePath $LogFile -Append
    Exit 1 
}

# Erweiterte Paket-Matrix für alle gängigen Lösungen (x64 / nativer Fokus)
$AllPackages = @(
    @{ Key = "teams";        Id = "Microsoft.Teams";        Arch = "x64"; MatchName = "Microsoft Teams";            RegArch = "x64" },
    @{ Key = "zoom";         Id = "Zoom.Zoom";              Arch = "x64"; MatchName = "Zoom";                       RegArch = "x64" },
    @{ Key = "webex";        Id = "Cisco.WebexTeams";       Arch = "x64"; MatchName = "Webex";                      RegArch = "x64" },
    @{ Key = "skype";        Id = "Microsoft.Skype";        Arch = "x86"; MatchName = "Skype";                      RegArch = "x86" },
    @{ Key = "slack";        Id = "SlackTechnologies.Slack";Arch = "x64"; MatchName = "Slack";                     RegArch = "x64" },
    @{ Key = "discord";      Id = "Discord.Discord";        Arch = "x86"; MatchName = "Discord";                    RegArch = "x86" },
    @{ Key = "gotomeeting";  Id = "LogMeIn.GoToMeeting";    Arch = "x64"; MatchName = "GoToMeeting";                RegArch = "x64" },
    @{ Key = "bluejeans";    Id = "BlueJeans.BlueJeans";    Arch = "x64"; MatchName = "BlueJeans";                  RegArch = "x64" },
    @{ Key = "teamviewer";   Id = "TeamViewer.TeamViewer";  Arch = "x64"; MatchName = "TeamViewer";                 RegArch = "x64" },
    @{ Key = "anydesk";      Id = "AnyDeskSoftware.AnyDesk";Arch = "x86"; MatchName = "AnyDesk";                    RegArch = "x86" }
)

# Filtern der Pakete basierend auf dem Parameter
$packagesToInstall = if ($env:app -eq "all") {
    $AllPackages
} else {
    $AllPackages | Where-Object { $_.Key -eq $env:app.ToLower() }
}

if ($packagesToInstall.Count -eq 0) {
    "FEHLER: Ungueltiger Parameter '$($env:app)' an das Skript uebergeben." | Out-File -FilePath $LogFile -Append
    Exit 1
}

# Installierte Windows-Software einlesen (Smart-Check)
$InstalledApps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* , HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                 Select-Object DisplayName

foreach ($pkg in $packagesToInstall) {
    $currentName = "$($pkg.Id) ($($pkg.Arch))"
    
    # Vorab-Prüfung in der Registry (Verhindert unnötige WinGet-Aufrufe)
    $AlreadyInstalled = $InstalledApps | Where-Object { $_.DisplayName -match $pkg.MatchName }

    if ($AlreadyInstalled) {
        "Uebersprungen (Bereits aktuell/installiert): $currentName" | Out-File -FilePath $LogFile -Append
        continue
    }

    # Unbeaufsichtigte Installation via WinGet-Pfad ausführen
    $argumentList = @("install", "--id", $pkg.Id, "--architecture", $pkg.Arch, "--silent", "--accept-source-agreements", "--accept-package-agreements")
    $process = Start-Process -FilePath $WinGetPath -ArgumentList $argumentList -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        "Erfolg: $currentName installiert. (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    } else {
        "Fehler bei: $currentName (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    }
}

"--- Ende der Installation: $(Get-Date) ---" | Out-File -FilePath $LogFile -Append
Exit 0