#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Ermittelt je Volume, ob BitLocker nur den belegten Speicher oder den ganzen Datenträger verschlüsselt hat.
    EN: Determines per volume whether BitLocker encrypted used space only or the full disk.
.DESCRIPTION
    DE: Ruft für jedes Win32_EncryptableVolume (root/cimv2/Security/MicrosoftVolumeEncryption)
        GetConversionStatus per Invoke-CimMethod auf. Laut Microsoft-Dokumentation steht Bit
        0x00000001 in EncryptionFlags für den Data-only-Modus (Used Space Only), sonst Full.
        Modus: NotEncrypted (ConversionStatus 0), UsedSpaceOnly (Bit gesetzt), FullDisk (Bit nicht
        gesetzt), Unknown (Methode fehlgeschlagen, z. B. gesperrtes Volume 0x80310000, oder Flags
        fehlen). Microsoft beschreibt das Bit primär für den Start einer Verschlüsselung; die Anzeige
        für bereits verschlüsselte Volumes entspricht manage-bde "Used Space Only Encrypted", ist aber
        nicht ausdrücklich garantiert. RequireFullDisk gilt nur für OS- und feste Datenvolumes
        (VolumeType 0/1); Wechseldatenträger werden nur gemeldet. Keine Änderungen.
    EN: Calls GetConversionStatus via Invoke-CimMethod for every Win32_EncryptableVolume
        (root/cimv2/Security/MicrosoftVolumeEncryption). Per Microsoft documentation, bit
        0x00000001 in EncryptionFlags means data-only mode (used space only), otherwise full.
        Mode: NotEncrypted (ConversionStatus 0), UsedSpaceOnly (bit set), FullDisk (bit not set),
        Unknown (method failed, e.g. locked volume 0x80310000, or flags missing). Microsoft documents
        the bit primarily for starting encryption; for already encrypted volumes it matches
        manage-bde "Used Space Only Encrypted" but is not explicitly guaranteed. RequireFullDisk
        only applies to OS and fixed data volumes (VolumeType 0/1); removable volumes are only
        reported. No changes.
.PARAMETER RequireFullDisk
    DE: NinjaOne Checkbox bitlockerRequireFullDiskEncryption; true/false/1/0; Standard false.
    EN: NinjaOne Checkbox bitlockerRequireFullDiskEncryption; true/false/1/0; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkUsedSpaceOnlyEncryption.ps1
    DE: Meldet den Verschlüsselungsmodus aller Volumes (Exit 0).
    EN: Reports the encryption mode of all volumes (exit 0).
.EXAMPLE
    .\checkUsedSpaceOnlyEncryption.ps1 -RequireFullDisk true -CustomField bitlockerEncryptionMode
    DE: Exit 2 bei UsedSpaceOnly oder Unknown auf OS-/festen Volumes; JSON ins Feld bitlockerEncryptionMode.
    EN: Exit 2 for UsedSpaceOnly or Unknown on OS/fixed volumes; JSON to field bitlockerEncryptionMode.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = OK oder RequireFullDisk=false, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = RequireFullDisk=true und ein verschlüsseltes OS-/festes Volume ist UsedSpaceOnly oder Unknown.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = OK or RequireFullDisk=false, 1 = input/query/write error,
        2 = RequireFullDisk=true and an encrypted OS/fixed volume is UsedSpaceOnly or Unknown.
#>
[CmdletBinding()]
param(
    [string]$RequireFullDisk = $env:bitlockerRequireFullDiskEncryption,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $RequireFullDisk = ([string]$RequireFullDisk).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequireFullDisk -ieq 'null') { $RequireFullDisk = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequireFullDisk) { $RequireFullDisk = 'false' }
    if ($RequireFullDisk -notin @('true', 'false', '1', '0')) { throw 'bitlockerRequireFullDiskEncryption: true/false.' }
    $fullRequired = $RequireFullDisk -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $volumes = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume)
    if ($volumes.Count -eq 0) { throw 'Keine verschlüsselbaren Volumes / No encryptable volumes.' }
    $typeNames = @{ 0 = 'OperatingSystem'; 1 = 'FixedData'; 2 = 'Removable' }
    $conversionNames = @{ 0 = 'FullyDecrypted'; 1 = 'FullyEncrypted'; 2 = 'EncryptionInProgress'; 3 = 'DecryptionInProgress'; 4 = 'EncryptionPaused'; 5 = 'DecryptionPaused' }
    $records = @(foreach ($volume in ($volumes | Select-Object -First 26)) {
        $typeName = 'Unknown'
        if ($null -ne $volume.VolumeType -and $typeNames.ContainsKey([int]$volume.VolumeType)) { $typeName = $typeNames[[int]$volume.VolumeType] }
        $mode = 'Unknown'; $conversion = 'Unknown'; $flags = $null; $returnCode = $null
        try {
            $result = Invoke-CimMethod -InputObject $volume -MethodName GetConversionStatus -Arguments @{ PrecisionFactor = [uint32]0 }
            $returnCode = [uint32]$result.ReturnValue
            if ($returnCode -eq 0) {
                $status = [int]$result.ConversionStatus
                if ($conversionNames.ContainsKey($status)) { $conversion = $conversionNames[$status] }
                if ($status -eq 0) { $mode = 'NotEncrypted' }
                elseif ($null -ne $result.EncryptionFlags) {
                    $flags = [uint32]$result.EncryptionFlags
                    if ($flags -band 1) { $mode = 'UsedSpaceOnly' } else { $mode = 'FullDisk' }
                }
            }
        } catch { $mode = 'Unknown' }
        $volumeId = [string]$volume.DriveLetter
        if (-not $volumeId) { $volumeId = [string]$volume.DeviceID }
        [pscustomobject]@{
            Volume = $volumeId; VolumeType = $typeName; ConversionStatus = $conversion
            EncryptionFlags = $flags; ReturnValue = $returnCode; Mode = $mode
        }
    })
    $violations = @($records | Where-Object { $_.VolumeType -in @('OperatingSystem', 'FixedData') -and $_.Mode -in @('UsedSpaceOnly', 'Unknown') })
    $report = ConvertTo-Json -InputObject ([ordered]@{
        RequireFullDisk = $fullRequired; TotalVolumes = $volumes.Count; ReportedVolumes = $records.Count
        UsedSpaceOnlyVolumes = @($records | Where-Object { $_.Mode -eq 'UsedSpaceOnly' }).Count
        UnknownVolumes = @($records | Where-Object { $_.Mode -eq 'Unknown' }).Count; Volumes = $records
    }) -Depth 4 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($fullRequired -and $violations.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
