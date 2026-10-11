#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft Chocolatey-Dateimetadaten am bekannten ProgramData-Installationsort.
EN: Audits Chocolatey file metadata at the known ProgramData installation location.
.DESCRIPTION
DE: SYSTEM, 64-Bit Windows PowerShell. Originalimplementierung; keine Fremdskripte.
EN: SYSTEM, 64-bit Windows PowerShell. Original implementation; no third-party script code.
DE: Nur ProgramData\chocolatey\bin\choco.exe pruefen. ChocolateyInstall und PATH werden ignoriert.
EN: Checks only ProgramData\chocolatey\bin\choco.exe. Ignores ChocolateyInstall and PATH.
DE: Kein Ausfuehren von choco.exe; keine Installation/Updates/Downloads/Paketinventarisierung.
EN: Never executes choco.exe; no installation/upgrades/downloads/package inventory.
DE: Reparse-Points werden abgelehnt. Dateiversion und Signatur sind Metadaten, kein
    Funktions-, ACL-Vertrauens- oder Paketgesundheitsnachweis. Alternative Installationen fehlen hier.
EN: Rejects reparse points. File version and signature are metadata, not proof of
    functionality, ACL trust, or package health. Alternative installations are not detected.
DE: NinjaOne-Text null gilt nach Trim als leer; explizite Parameter haben Vorrang.
EN: NinjaOne literal null is empty after Trim; explicit parameters take precedence.
DE/EN: Exit 0 = Metadaten OK/metadata OK, 1 = Fehler/error, 2 = fehlt/Version unbekannt/zu alt/missing/unknown/old.
.PARAMETER MinimumVersion
DE: Optionale numerische Mindestversion (2..4 Teile); securityChocolateyMinimumVersion; Standard leer.
EN: Optional numeric minimum version (2..4 components); securityChocolateyMinimumVersion; default empty.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer; maximal 4000 Zeichen.
EN: Optional MultiLine JSON field; resultCustomField; default empty; maximum 4000 characters.
#>
[CmdletBinding()]
param([string]$MinimumVersion = '', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    if (-not $PSBoundParameters.ContainsKey('MinimumVersion')) { $MinimumVersion = $env:securityChocolateyMinimumVersion }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $MinimumVersion = ([string]$MinimumVersion).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($MinimumVersion -ieq 'null') { $MinimumVersion = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $minimum = $null
    if ($MinimumVersion) {
        if ($MinimumVersion -notmatch '^\d+\.\d+(?:\.\d+){0,2}$' -or -not [version]::TryParse($MinimumVersion, [ref]$minimum)) {
            throw 'Ungueltige MinimumVersion / Invalid MinimumVersion.'
        }
    }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    # DE: OS-bekannter Ort statt Benutzer-/Ninja-Pfad. EN: OS-known location, never a user/Ninja path.
    $programData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if (-not $programData -or -not [IO.Path]::IsPathRooted($programData)) { throw 'ProgramData fehlt / ProgramData unavailable.' }
    $directory = Join-Path $programData 'chocolatey'
    $bin = Join-Path $directory 'bin'
    $path = Join-Path $bin 'choco.exe'
    $present = $true
    foreach ($candidate in @($programData, $directory, $bin, $path)) {
        if (-not (Test-Path -LiteralPath $candidate -ErrorAction Stop)) { $present = $false; break }
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse-Point nicht erlaubt / Reparse point not allowed.' }
        if ($candidate -ne $path -and -not $item.PSIsContainer) { throw 'Installationspfad ist kein Ordner / Installation path is not a directory.' }
    }
    $fileVersion = ''
    $signatureStatus = 'NotChecked'
    $detected = $null
    if ($present) {
        if ($item.PSIsContainer) { throw 'choco.exe ist kein regulaeres Programm / choco.exe is not a regular file.' }
        $fileVersion = [string]$item.VersionInfo.FileVersion
        # DE: Numerische Dateiversion; keine CLI-Ausfuehrung. EN: Numeric file version; no CLI execution.
        if ($fileVersion -match '^\s*(\d+\.\d+(?:\.\d+){0,2})(?:\s|$)') {
            $null = [version]::TryParse($Matches[1], [ref]$detected)
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $signatureStatus = [string]$signature.Status
    }
    $warning = -not $present -or $null -eq $detected -or ($null -ne $minimum -and $detected -lt $minimum)
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{
        Scope = 'KnownProgramDataLocation_MetadataOnly'; Path = $path; Present = $present
        FileVersion = $fileVersion; MinimumVersion = $MinimumVersion; SignatureStatus = $signatureStatus
        Executed = $false; PackageHealthVerified = $false
    }) -Depth 4 -Compress
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    if ($text.Length -gt 4000) { throw 'Ergebnis groesser als 4000 Zeichen / Result exceeds 4000 characters.' }
    Write-Output $text
    if ($CustomField) {
        $null = Get-Command Ninja-Property-Set -ErrorAction Stop
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $text -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'CustomField konnte nicht geschrieben werden / Field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Chocolatey-Pruefung fehlgeschlagen / Chocolatey audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
