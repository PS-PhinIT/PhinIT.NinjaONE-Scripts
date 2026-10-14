#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Pre-Boot-Authentifizierung (TPM/TPM+PIN) des Betriebssystemvolumes.
    EN: Checks pre-boot authentication (TPM/TPM+PIN) of the operating system volume.
.DESCRIPTION
    DE: Liest die Schlüsselschutz-Typen und -IDs des OS-Volumes ($env:SystemDrive) per
        Get-BitLockerVolume. Niemals Recovery-Kennwörter oder Schlüssel. TPM-basiert sind alle
        Typen, die mit Tpm beginnen (Tpm, TpmPin, TpmStartupKey, TpmPinStartupKey, TpmNetworkKey).
        PIN-Schutz = TpmPin oder TpmPinStartupKey. Mit RequirePin=true genügt reines Tpm nicht.
    EN: Reads key protector types and IDs of the OS volume ($env:SystemDrive) via
        Get-BitLockerVolume. Never recovery passwords or keys. TPM-based are all types starting
        with Tpm (Tpm, TpmPin, TpmStartupKey, TpmPinStartupKey, TpmNetworkKey). PIN protection =
        TpmPin or TpmPinStartupKey. With RequirePin=true, TPM-only is not sufficient.
.PARAMETER RequirePin
    DE: NinjaOne Checkbox bitlockerRequirePin; true/false/1/0; Standard false.
    EN: NinjaOne Checkbox bitlockerRequirePin; true/false/1/0; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkPreBootAuthentication.ps1
    DE: Verlangt mindestens einen TPM-basierten Protector auf dem OS-Volume.
    EN: Requires at least one TPM-based protector on the OS volume.
.EXAMPLE
    .\checkPreBootAuthentication.ps1 -RequirePin true -CustomField bitlockerPreBoot
    DE: Verlangt TPM+PIN; JSON ins Feld bitlockerPreBoot.
    EN: Requires TPM+PIN; JSON to field bitlockerPreBoot.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = Anforderung erfüllt, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = kein TPM-basierter
        Protector auf dem OS-Volume oder (RequirePin=true) kein TpmPin/TpmPinStartupKey.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = requirement met, 1 = input/query/write error, 2 = no TPM-based protector on the
        OS volume or (RequirePin=true) no TpmPin/TpmPinStartupKey.
#>
[CmdletBinding()]
param(
    [string]$RequirePin = $env:bitlockerRequirePin,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $RequirePin = ([string]$RequirePin).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequirePin -ieq 'null') { $RequirePin = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequirePin) { $RequirePin = 'false' }
    if ($RequirePin -notin @('true', 'false', '1', '0')) { throw 'bitlockerRequirePin: true/false erforderlich / required.' }
    $pinRequired = $RequirePin -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $osDrive = ([string]$env:SystemDrive).Trim()
    if ($osDrive -notmatch '^[A-Za-z]:$') { throw 'SystemDrive unbekannt / unknown.' }
    $volume = @(Get-BitLockerVolume -MountPoint $osDrive) | Select-Object -First 1
    if ($null -eq $volume) { throw 'OS-Volume nicht gefunden / OS volume not found.' }
    # DE: Nur Typ und ID projizieren, niemals RecoveryPassword/KeyFileName.
    # EN: Project type and ID only, never RecoveryPassword/KeyFileName.
    $protectors = @($volume.KeyProtector | Where-Object { $null -ne $_ } | ForEach-Object {
        [pscustomobject]@{ Id = [string]$_.KeyProtectorId; Type = [string]$_.KeyProtectorType }
    })
    $types = @($protectors | ForEach-Object { $_.Type } | Sort-Object -Unique)
    $hasTpm = @($types | Where-Object { $_ -like 'Tpm*' }).Count -gt 0
    $hasPin = @($types | Where-Object { $_ -in @('TpmPin', 'TpmPinStartupKey') }).Count -gt 0
    $issues = @()
    if (-not $hasTpm) { $issues += 'NoTpmBasedProtector' }
    if ($pinRequired -and -not $hasPin) {
        if ($types -contains 'Tpm') { $issues += 'TpmOnlyWherePinRequired' } else { $issues += 'PinProtectorMissing' }
    }
    $report = ConvertTo-Json -InputObject ([ordered]@{
        MountPoint = [string]$volume.MountPoint; VolumeStatus = [string]$volume.VolumeStatus
        ProtectionStatus = [string]$volume.ProtectionStatus; RequirePin = $pinRequired
        ProtectorTypes = $types; HasTpmProtector = $hasTpm; HasPinProtector = $hasPin
        Compliant = ($issues.Count -eq 0); Issues = $issues; Protectors = $protectors
    }) -Depth 4 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($issues.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
