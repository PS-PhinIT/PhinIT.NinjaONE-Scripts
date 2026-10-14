#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob Betriebssystem- und feste Datenvolumes vollständig mit BitLocker geschützt sind.
    EN: Checks whether operating system and fixed data volumes are fully protected by BitLocker.
.DESCRIPTION
    DE: Liest alle Volumes per Get-BitLockerVolume. Das OS-Volume und (optional) feste
        Datenvolumes mit Laufwerksbuchstaben müssen VolumeStatus FullyEncrypted,
        ProtectionStatus On und ein erlaubtes Verschlüsselungsverfahren haben.
        Wechseldatenträger (Win32_EncryptableVolume VolumeType 2) werden ausgelassen.
        Datenvolumes ohne Laufwerksbuchstaben (Ordner-Mountpunkte) erscheinen als
        SkippedVolumes. Keine Schlüssel oder Recovery-Kennwörter werden gelesen.
    EN: Reads all volumes via Get-BitLockerVolume. The OS volume and (optionally) fixed
        data volumes with a drive letter must report VolumeStatus FullyEncrypted,
        ProtectionStatus On and an allowed encryption method. Removable volumes
        (Win32_EncryptableVolume VolumeType 2) are skipped. Data volumes without a
        drive letter (folder mount points) are listed as SkippedVolumes. No keys or
        recovery passwords are read.
.PARAMETER AllowedMethods
    DE: NinjaOne Text bitlockerAllowedEncryptionMethods; kommagetrennte Liste aus
        Aes128, Aes256, XtsAes128, XtsAes256, Aes128Diffuser, Aes256Diffuser, Hardware;
        Standard XtsAes128,XtsAes256,Aes128,Aes256.
    EN: NinjaOne Text bitlockerAllowedEncryptionMethods; comma-separated list of
        Aes128, Aes256, XtsAes128, XtsAes256, Aes128Diffuser, Aes256Diffuser, Hardware;
        default XtsAes128,XtsAes256,Aes128,Aes256.
.PARAMETER IncludeFixedData
    DE: NinjaOne Checkbox bitlockerIncludeFixedDataDrives; true/false/1/0; Standard true.
    EN: NinjaOne Checkbox bitlockerIncludeFixedDataDrives; true/false/1/0; default true.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkBitLockerCompliance.ps1
    DE: Prüft OS- und feste Datenvolumes gegen die Standardverfahren.
    EN: Checks OS and fixed data volumes against the default methods.
.EXAMPLE
    .\checkBitLockerCompliance.ps1 -AllowedMethods XtsAes256 -IncludeFixedData false -CustomField bitlockerCompliance
    DE: Nur OS-Volume, nur XTS-AES 256 erlaubt; JSON ins Feld bitlockerCompliance.
    EN: OS volume only, only XTS-AES 256 allowed; JSON to field bitlockerCompliance.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = alle geprüften Volumes konform, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = mindestens ein Volume nicht FullyEncrypted, Schutz nicht On, unerlaubtes Verfahren
        oder kein OS-Volume gefunden.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Exit 0 = all checked volumes compliant, 1 = input/query/write error,
        2 = at least one volume not FullyEncrypted, protection not On, disallowed method
        or no OS volume found.
#>
[CmdletBinding()]
param(
    [string]$AllowedMethods = $env:bitlockerAllowedEncryptionMethods,
    [string]$IncludeFixedData = $env:bitlockerIncludeFixedDataDrives,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $AllowedMethods = ([string]$AllowedMethods).Trim()
    $IncludeFixedData = ([string]$IncludeFixedData).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($AllowedMethods -ieq 'null') { $AllowedMethods = '' }
    if ($IncludeFixedData -ieq 'null') { $IncludeFixedData = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $AllowedMethods) { $AllowedMethods = 'XtsAes128,XtsAes256,Aes128,Aes256' }
    if (-not $IncludeFixedData) { $IncludeFixedData = 'true' }
    if ($IncludeFixedData -notin @('true', 'false', '1', '0')) { throw 'bitlockerIncludeFixedDataDrives: true/false erforderlich / required.' }
    $includeFixed = $IncludeFixedData -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $knownMethods = @('Aes128', 'Aes256', 'XtsAes128', 'XtsAes256', 'Aes128Diffuser', 'Aes256Diffuser', 'Hardware')
    $allowed = @()
    foreach ($item in ($AllowedMethods -split ',')) {
        $name = $item.Trim()
        $match = @($knownMethods | Where-Object { $_ -ieq $name })
        if ($match.Count -ne 1) { throw "bitlockerAllowedEncryptionMethods: unbekanntes Verfahren / unknown method '$name'." }
        if ($allowed -notcontains $match[0]) { $allowed += $match[0] }
    }
    $volumes = @(Get-BitLockerVolume)
    if ($volumes.Count -eq 0) { throw 'Keine Volumes / No volumes returned.' }
    # DE: Wechseldatenträger über CIM erkennen (Get-BitLockerVolume kennt nur OperatingSystem/Data).
    # EN: Detect removable volumes via CIM (Get-BitLockerVolume only knows OperatingSystem/Data).
    $removable = @()
    if ($includeFixed) {
        $removable = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume |
            Where-Object { [int]$_.VolumeType -eq 2 } | ForEach-Object { ([string]$_.DriveLetter).ToUpperInvariant() })
    }
    $skipped = New-Object System.Collections.Generic.List[string]
    $records = @(foreach ($volume in $volumes) {
        $mount = [string]$volume.MountPoint
        $letter = $mount.TrimEnd('\').ToUpperInvariant()
        $type = [string]$volume.VolumeType
        if ($type -ne 'OperatingSystem') {
            if (-not $includeFixed -or $removable -contains $letter) { continue }
            if ($letter -notmatch '^[A-Z]:$') { $skipped.Add($mount); continue }
        }
        $issues = @()
        if ([string]$volume.VolumeStatus -ne 'FullyEncrypted') { $issues += 'NotFullyEncrypted' }
        if ([string]$volume.ProtectionStatus -ne 'On') { $issues += 'ProtectionNotOn' }
        if ($allowed -notcontains [string]$volume.EncryptionMethod) { $issues += 'MethodNotAllowed' }
        [pscustomobject]@{
            MountPoint = $mount; VolumeType = $type
            VolumeStatus = [string]$volume.VolumeStatus; ProtectionStatus = [string]$volume.ProtectionStatus
            EncryptionMethod = [string]$volume.EncryptionMethod; EncryptionPercentage = $volume.EncryptionPercentage
            Compliant = ($issues.Count -eq 0); Issues = $issues
        }
    })
    $osFound = @($records | Where-Object { $_.VolumeType -eq 'OperatingSystem' }).Count -gt 0
    $nonCompliant = @($records | Where-Object { -not $_.Compliant }).Count
    $report = ConvertTo-Json -InputObject ([ordered]@{
        AllowedMethods = $allowed; IncludeFixedDataDrives = $includeFixed
        OperatingSystemVolumeFound = $osFound; NonCompliantVolumes = $nonCompliant
        Volumes = $records; SkippedVolumes = @($skipped)
    }) -Depth 4 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($nonCompliant -gt 0 -or -not $osFound) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
