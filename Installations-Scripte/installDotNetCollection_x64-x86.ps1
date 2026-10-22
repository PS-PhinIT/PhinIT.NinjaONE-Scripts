# NinjaOne RMM optimiertes Installationsskript (x64 + x86 - Final Fixed)
$LogFile = "$env:ProgramData\NinjaOne\Logs\DotNet_Installation.log"
$LogDir = Split-Path $LogFile

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

"--- Start der Installation (x64 & x86): $(Get-Date) ---" | Out-File -FilePath $LogFile -Append

# Absoluten Pfad zur winget.exe im WindowsApps-Verzeichnis auflösen
$WinGetPath = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | 
              Select-Object -First 1 -ExpandProperty FullName

if (!$WinGetPath) {
    $WinGetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | 
                  Select-Object -First 1 -ExpandProperty Path
}

if (!$WinGetPath -or !(Test-Path $WinGetPath)) {
    "FEHLER: winget.exe konnte im SYSTEM-Kontext nicht gefunden werden." | Out-File -FilePath $LogFile -Append
    Exit 1
}

# Paket-Matrix für x64 und x86 Runtimes (.NET 8, 9, 10)
$packages = @(
    # .NET 8 Runtimes
    @{ Id = "Microsoft.DotNet.DesktopRuntime.8"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.DesktopRuntime.8"; Arch = "x86" },
    @{ Id = "Microsoft.DotNet.AspNetCore.8"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.AspNetCore.8"; Arch = "x86" },

    # .NET 9 Runtimes
    @{ Id = "Microsoft.DotNet.DesktopRuntime.9"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.DesktopRuntime.9"; Arch = "x86" },
    @{ Id = "Microsoft.DotNet.AspNetCore.9"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.AspNetCore.9"; Arch = "x86" },

    # .NET 10 Runtimes
    @{ Id = "Microsoft.DotNet.DesktopRuntime.10"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.DesktopRuntime.10"; Arch = "x86" },
    @{ Id = "Microsoft.DotNet.AspNetCore.10"; Arch = "x64" },
    @{ Id = "Microsoft.DotNet.AspNetCore.10"; Arch = "x86" }
)

# Versuche das klassische .NET 4.8 über die Windows-Features bereitzustellen (RMM-sicherer als WinGet)
try {
    Enable-WindowsOptionalFeature -Online -FeatureName "NetFx4-AdvXMP" -NoRestart -ErrorAction SilentlyContinue | Out-Null
    ".NET Framework 4.8 Features wurden per Windows-DISM aktiviert/geprüft." | Out-File -FilePath $LogFile -Append
} catch {
    "Hinweis: Aktivierung von NetFx4 über DISM nicht erfolgreich oder bereits aktiv." | Out-File -FilePath $LogFile -Append
}

# Abarbeitung der Core-Pakete
foreach ($pkg in $packages) {
    $currentName = "$($pkg.Id) ($($pkg.Arch))"
    
    # Argumente sauber als String-Array trennen, damit Start-Process die Architektur korrekt übergibt
    $argumentList = @(
        "install",
        "--id", $pkg.Id,
        "--architecture", $pkg.Arch,
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )
    
    # Ausführung via Start-Process (vollständig silent, Logs werden umgeleitet)
    $process = Start-Process -FilePath $WinGetPath -ArgumentList $argumentList -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        "Erfolg: $currentName wurde erfolgreich installiert/aktualisiert. (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    } else {
        "Fehler bei: $currentName (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    }
}

"--- Ende der Installation: $(Get-Date) ---" | Out-File -FilePath $LogFile -Append

# Gibt den letzten Exit-Code an NinjaOne zurück
Exit $LASTEXITCODE