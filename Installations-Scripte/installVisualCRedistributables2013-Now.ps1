# NinjaOne RMM optimiertes Installationsskript (VC++ Runtimes 2013 bis heute - x64 & x86)
$LogFile = "$env:ProgramData\NinjaOne\Logs\VCRedist_Installation.log"
$LogDir = Split-Path $LogFile

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

"--- Start der Installation (VC++ x64 & x86): $(Get-Date) ---" | Out-File -FilePath $LogFile -Append

# Absoluten Pfad zur winget.exe im WindowsApps-Verzeichnis auflösen (SYSTEM-Kontext Fix)
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

# Paket-Matrix für VC++ 2013 und das kumulative Paket (2015-heute)
$packages = @(
    # Visual C++ 2013 Runtimes
    @{ Id = "Microsoft.VCRedist.2013.x64"; Arch = "x64" },
    @{ Id = "Microsoft.VCRedist.2013.x86"; Arch = "x86" },

    # Visual C++ 2015 bis heute (Kumulatives Paket für 2015, 2017, 2019, 2022, 2026)
    @{ Id = "Microsoft.VCRedist.2015+.x64"; Arch = "x64" },
    @{ Id = "Microsoft.VCRedist.2015+.x86"; Arch = "x86" }
)

# Abarbeitung der VC++ Pakete
foreach ($pkg in $packages) {
    $currentName = "$($pkg.Id) ($($pkg.Arch))"
    
    # Argumente sauber als String-Array trennen, damit die Architektur zwingend übergeben wird
    $argumentList = @(
        "install",
        "--id", $pkg.Id,
        "--architecture", $pkg.Arch,
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )
    
    # Ausführung via Start-Process im Hintergrund
    $process = Start-Process -FilePath $WinGetPath -ArgumentList $argumentList -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        "Erfolg: $currentName wurde erfolgreich installiert/aktualisiert. (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    } else {
        "Fehler bei: $currentName (Exit Code: $($process.ExitCode))" | Out-File -FilePath $LogFile -Append
    }
}

"--- Ende der Installation: $(Get-Date) ---" | Out-File -FilePath $LogFile -Append

# Letzten Exit-Code der Schleife an NinjaOne übergeben
Exit $LASTEXITCODE
