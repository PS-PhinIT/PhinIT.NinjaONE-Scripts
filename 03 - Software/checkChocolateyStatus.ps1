#Requires -Version 5.1
<#
.SYNOPSIS
DE: Chocolatey-Standardinstallation anhand geschützter Dateien schreibgeschützt prüfen.
EN: Audit the standard Chocolatey installation using protected files without changing it.
.DESCRIPTION
DE: Originalimplementierung; Windows SYSTEM, 64-Bit. Keine choco.exe-Ausführung oder Downloads.
EN: Original implementation; Windows SYSTEM, 64-bit. No choco.exe execution or downloads.
DE: Nur KnownFolder CommonApplicationData\chocolatey; ChocolateyInstall/PATH werden nicht verwendet.
EN: Only KnownFolder CommonApplicationData\chocolatey; ChocolateyInstall/PATH are not used.
DE: Reparsepunkte oder Schreibrechte für nicht privilegierte Konten verhindern Metadatenprüfung.
EN: Reparse points or write permissions for nonprivileged accounts prevent metadata inspection.
DE: Datei-/Versionsmetadaten sind kein Integritätsnachweis; portable/abweichende Installationen fehlen.
EN: File/version metadata is not proof of integrity; portable/nonstandard installations are omitted.
DE: Keine Paketinstallation, Aktualisierung oder Paketskriptausführung; keine Paketinventur.
EN: No package installation, upgrade or package script execution; no package inventory.
.PARAMETER RequireInstalled
DE: String mit Boolean-Wert true/false; NinjaOne chocolateyStatusRequireInstalled; Standard false. true meldet fehlende Standardinstallation mit Exit 2.
EN: String containing Boolean true/false; NinjaOne chocolateyStatusRequireInstalled; default false. true reports a missing standard installation with exit 2.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich. Klartext-JSON, maximal 4000 Zeichen, keine Kürzung.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore. Plain-text JSON, maximum 4000 characters, no truncation.
#>
[CmdletBinding()]
param(
    [string]$RequireInstalled = $env:chocolateyStatusRequireInstalled,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $RequireInstalled = if ([string]::IsNullOrWhiteSpace($RequireInstalled) -or $RequireInstalled.Trim() -eq 'null') { '' } else { $RequireInstalled.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if (-not $RequireInstalled) { $RequireInstalled = 'false' }
    $required = $false
    if (-not [bool]::TryParse($RequireInstalled, [ref]$required)) { throw 'RequireInstalled: true/false erforderlich / required.' }
    $programData = [Environment]::GetFolderPath('CommonApplicationData')
    if (-not [IO.Path]::IsPathRooted($programData)) { throw 'Ungültiger ProgramData-Pfad / Invalid ProgramData path.' }
    $root = Join-Path $programData 'chocolatey'
    $bin = Join-Path $root 'bin'
    $executable = Join-Path $bin 'choco.exe'
    $issues = @()
    $trustedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    # DE: Nur SYSTEM, Administratoren und TrustedInstaller dürfen Besitzer/Schreiber sein.
    # EN: Only SYSTEM, Administrators and TrustedInstaller may own/write inspected paths.
    $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    $paths = @($programData, $root, $bin, $executable)
    $found = $false
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { break }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $issues += "ReparsePoint: $path"
            break
        }
        if (($path -eq $executable -and $item.PSIsContainer) -or ($path -ne $executable -and -not $item.PSIsContainer)) {
            $issues += "UnexpectedPathType: $path"
            break
        }
        $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($trustedSids -notcontains $owner) { $issues += "UntrustedOwner: $path" }
        $pathWriteMask = $writeMask
        if ($path -eq $programData) {
            # DE: ProgramData darf neue Unterordner erlauben, aber nicht geschützte Kinder ersetzen.
            # EN: ProgramData may allow new subfolders, but must not allow replacing protected children.
            $pathWriteMask = [Security.AccessControl.FileSystemRights]::Delete -bor
                [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
                [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
                [Security.AccessControl.FileSystemRights]::TakeOwnership
        }
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            # DE: InheritOnly gilt nicht für diesen Pfad. EN: InheritOnly does not apply to this path.
            if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                ($rule.FileSystemRights -band $pathWriteMask) -and
                $trustedSids -notcontains $rule.IdentityReference.Value) {
                $issues += "NonPrivilegedWritePermission: $path"
                break
            }
        }
        if ($issues.Count) { break }
        if ($path -eq $executable) { $found = $true }
    }
    $metadata = $null
    if ($found -and -not $issues.Count) {
        # DE: Liest Versionsressourcen ohne Prozessstart. EN: Reads version resources without launching a process.
        $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
        $file = Get-Item -LiteralPath $executable -Force -ErrorAction Stop
        $metadata = [pscustomobject]@{
            Path = $executable; FileVersion = $version.FileVersion; ProductVersion = $version.ProductVersion
            Length = $file.Length; LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
        }
    }
    $warning = $issues.Count -gt 0 -or ($required -and -not $found)
    $json = [pscustomobject]@{
        Computer = $env:COMPUTERNAME; StandardLocation = $root; RequireInstalled = $required
        ProtectedStandardExecutableFound = $found; ExecutionTested = $false; PackageInventoryCollected = $false
        Warning = $warning; SafetyFindings = $issues; ExecutableMetadata = $metadata
    } | ConvertTo-Json -Depth 5
    Write-Output $json
    if ($CustomField) {
        if ($CustomField.Length -gt 128 -or $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
        if ($json.Length -gt 4000) { throw 'JSON überschreitet 4000 Zeichen / JSON exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $json -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "Ninja-Property-Set Exitcode / exit code: $global:LASTEXITCODE" }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Chocolatey-Prüfung fehlgeschlagen / Chocolatey audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
