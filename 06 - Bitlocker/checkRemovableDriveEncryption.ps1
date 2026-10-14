#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft angeschlossene Wechseldatenträger auf BitLocker-Verschlüsselung (BitLocker To Go).
    EN: Checks attached removable drives for BitLocker encryption (BitLocker To Go).
.DESCRIPTION
    DE: Wechseldatenträger werden über Win32_EncryptableVolume (VolumeType 2, Namespace
        root/cimv2/Security/MicrosoftVolumeEncryption) und Win32_LogicalDisk (DriveType 2) erkannt.
        Status: Encrypted (ConversionStatus 1), Locked (gesperrt, ConversionStatus nicht lesbar,
        gilt als verschlüsselt), EncryptionInProgress (2/4), NotEncrypted (0/3/5),
        NotEncryptable (nur Win32_LogicalDisk mit Medium), Laufwerke ohne Medium werden ignoriert.
        Richtlinie RDVDenyWriteAccess wird aus HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE
        (Fallback HKLM\SOFTWARE\Policies\Microsoft\FVE) gelesen. Keine Schlüssel, keine Änderungen.
    EN: Removable drives are detected via Win32_EncryptableVolume (VolumeType 2, namespace
        root/cimv2/Security/MicrosoftVolumeEncryption) and Win32_LogicalDisk (DriveType 2).
        Status: Encrypted (ConversionStatus 1), Locked (locked, ConversionStatus unreadable,
        treated as encrypted), EncryptionInProgress (2/4), NotEncrypted (0/3/5), NotEncryptable
        (only Win32_LogicalDisk with media); drives without media are ignored. Policy
        RDVDenyWriteAccess is read from HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE
        (fallback HKLM\SOFTWARE\Policies\Microsoft\FVE). No keys, no changes.
.PARAMETER RequireEncrypted
    DE: NinjaOne Dropdown/Text bitlockerRequireRemovableEncryption; auto, true oder false;
        Standard auto = Verschlüsselung verlangt, wenn RDVDenyWriteAccess = 1.
    EN: NinjaOne Dropdown/Text bitlockerRequireRemovableEncryption; auto, true or false;
        default auto = encryption required when RDVDenyWriteAccess = 1.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkRemovableDriveEncryption.ps1
    DE: Warnt bei unverschlüsselten Wechseldatenträgern, wenn die Richtlinie Schreibschutz erzwingt.
    EN: Warns about unencrypted removable drives when policy enforces write denial.
.EXAMPLE
    .\checkRemovableDriveEncryption.ps1 -RequireEncrypted true -CustomField removableEncryption
    DE: Verlangt immer Verschlüsselung; JSON ins Feld removableEncryption.
    EN: Always requires encryption; JSON to field removableEncryption.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = OK oder keine Anforderung, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = Verschlüsselung
        verlangt und mindestens ein angeschlossener Wechseldatenträger ist nicht (vollständig) verschlüsselt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = OK or no requirement, 1 = input/query/write error, 2 = encryption required and at
        least one attached removable drive is not (fully) encrypted.
#>
[CmdletBinding()]
param(
    [string]$RequireEncrypted = $env:bitlockerRequireRemovableEncryption,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $RequireEncrypted = ([string]$RequireEncrypted).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequireEncrypted -ieq 'null') { $RequireEncrypted = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequireEncrypted) { $RequireEncrypted = 'auto' }
    if ($RequireEncrypted -notin @('auto', 'true', 'false')) { throw 'bitlockerRequireRemovableEncryption: auto/true/false.' }
    $RequireEncrypted = $RequireEncrypted.ToLowerInvariant()
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $denyWrite = $null
    $denyCrossOrg = $null
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\FVE', 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE')) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-ItemProperty -LiteralPath $path
        if ($null -eq $item) { continue }
        if ($null -ne $item.RDVDenyWriteAccess) { $denyWrite = [int]$item.RDVDenyWriteAccess }
        if ($null -ne $item.RDVDenyCrossOrg) { $denyCrossOrg = [int]$item.RDVDenyCrossOrg }
    }
    $required = ($RequireEncrypted -eq 'true') -or ($RequireEncrypted -eq 'auto' -and $denyWrite -eq 1)
    $encryptable = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume |
        Where-Object { [int]$_.VolumeType -eq 2 })
    $logical = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 2')
    $statusNames = @{ 0 = 'NotEncrypted'; 1 = 'Encrypted'; 2 = 'EncryptionInProgress'; 3 = 'NotEncrypted'; 4 = 'EncryptionInProgress'; 5 = 'NotEncrypted' }
    $seen = @()
    $records = @(foreach ($volume in $encryptable) {
        $letter = ([string]$volume.DriveLetter).ToUpperInvariant()
        if ($letter) { $seen += $letter }
        if ($null -eq $volume.ConversionStatus) { $status = 'Locked' }
        else {
            $status = $statusNames[[int]$volume.ConversionStatus]
            if (-not $status) { $status = 'Unknown' }
        }
        [pscustomobject]@{ Drive = $letter; Source = 'Win32_EncryptableVolume'; Status = $status; ProtectionStatus = $volume.ProtectionStatus }
    })
    $records += @(foreach ($disk in $logical) {
        $letter = ([string]$disk.DeviceID).ToUpperInvariant()
        if ($seen -contains $letter -or $null -eq $disk.Size -or $disk.Size -le 0) { continue }
        [pscustomobject]@{ Drive = $letter; Source = 'Win32_LogicalDisk'; Status = 'NotEncryptable'; ProtectionStatus = $null }
    })
    $unencrypted = @($records | Where-Object { $_.Status -notin @('Encrypted', 'Locked') })
    $report = ConvertTo-Json -InputObject ([ordered]@{
        RDVDenyWriteAccess = $denyWrite; RDVDenyCrossOrg = $denyCrossOrg; RequireEncrypted = $RequireEncrypted
        EncryptionRequired = $required; RemovableDrives = $records.Count; UnencryptedDrives = $unencrypted.Count
        Drives = @($records | Select-Object -First 26)
    }) -Depth 4 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($required -and $unencrypted.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
