#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft BitLocker-Schutz ohne Schluessel auszulesen.
EN: Audits BitLocker protection without reading recovery secrets.
.DESCRIPTION
DE: NinjaOne-Text null (ohne Beachtung der Grossschreibung) gilt als leer. EN: NinjaOne literal null is treated as empty.
DE: Als SYSTEM in 64-Bit Windows PowerShell ausfuehren. Nur Erkennung.
EN: Run as SYSTEM in 64-bit Windows PowerShell. Detection only.
DE: MountPoint / bitlockerMountPoint (leer = alle Volumes); explizite Parameter haben Vorrang.
EN: MountPoint / bitlockerMountPoint (empty = all volumes); explicit parameters take precedence.
DE: CustomField / resultCustomField ist ein optionales NinjaOne MultiLine-Feld (JSON, maximal 4000 Zeichen).
EN: CustomField / resultCustomField is an optional NinjaOne MultiLine field (JSON, maximum 4000 characters).
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER MountPoint
DE: Laufwerk; bitlockerMountPoint; Standard leer = alle. EN: Drive; bitlockerMountPoint; default empty = all.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
#>
[CmdletBinding()]
param([string]$MountPoint = '', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Umgebungswerte nur ohne expliziten Parameter. EN: Environment only if not explicitly bound.
    if (-not $PSBoundParameters.ContainsKey('MountPoint')) { $MountPoint = $env:bitlockerMountPoint }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $MountPoint = ([string]$MountPoint).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($MountPoint -ieq 'null') { $MountPoint = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($MountPoint -and $MountPoint -notmatch '^[A-Za-z]:\\?$') { throw 'MountPoint: Laufwerksbuchstabe erforderlich / Drive letter required.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-BitLockerVolume -ErrorAction Stop
    if ($MountPoint) { $volumes = @(Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop) }
    else { $volumes = @(Get-BitLockerVolume -ErrorAction Stop) }
    if (-not $volumes.Count) { throw 'Keine Volumes / No volumes returned.' }
    $warning = @($volumes | Where-Object { [string]$_.ProtectionStatus -ne 'On' }).Count -gt 0
    $rows = @($volumes | ForEach-Object {
        [pscustomobject]@{
            MountPoint = $_.MountPoint; VolumeType = [string]$_.VolumeType
            VolumeStatus = [string]$_.VolumeStatus; ProtectionStatus = [string]$_.ProtectionStatus
            LockStatus = [string]$_.LockStatus; EncryptionPercentage = $_.EncryptionPercentage
        }
    })
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    $text = ConvertTo-Json -InputObject $rows -Depth 4 -Compress
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
    Write-Error ("BitLocker-Pruefung fehlgeschlagen / Audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}