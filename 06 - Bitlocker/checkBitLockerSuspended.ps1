#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Erkennt verschlüsselte Volumes mit angehaltenem (suspendiertem) BitLocker-Schutz.
    EN: Detects encrypted volumes whose BitLocker protection is suspended.
.DESCRIPTION
    DE: Liest alle Volumes per Get-BitLockerVolume. Ein Volume gilt als angehalten, wenn
        VolumeStatus FullyEncrypted und ProtectionStatus Off ist (Schlüssel liegt im Klartext
        auf dem Datenträger). Für angehaltene Volumes wird die verbleibende Anzahl Neustarts bis
        zur automatischen Wiederaufnahme per Win32_EncryptableVolume.GetSuspendCount
        (Invoke-CimMethod, root/cimv2/Security/MicrosoftVolumeEncryption) gelesen. Laut
        Microsoft gilt GetSuspendCount nur für das OS-Volume (Windows 8+); sonst bleibt der Wert
        null mit Quelle Unavailable. 0 bedeutet: Wiederaufnahme nur manuell. Keine Änderungen.
    EN: Reads all volumes via Get-BitLockerVolume. A volume counts as suspended when
        VolumeStatus is FullyEncrypted and ProtectionStatus is Off (clear key on disk). For
        suspended volumes the remaining reboot count until automatic resume is read via
        Win32_EncryptableVolume.GetSuspendCount (Invoke-CimMethod,
        root/cimv2/Security/MicrosoftVolumeEncryption). Per Microsoft, GetSuspendCount only
        applies to the OS volume (Windows 8+); otherwise the value stays null with source
        Unavailable. 0 means resume only manually. No changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkBitLockerSuspended.ps1
    DE: Meldet angehaltene Volumes inkl. verbleibender Neustarts.
    EN: Reports suspended volumes including remaining reboots.
.EXAMPLE
    .\checkBitLockerSuspended.ps1 -CustomField bitlockerSuspended
    DE: Wie oben; JSON zusätzlich ins Feld bitlockerSuspended.
    EN: As above; JSON additionally to field bitlockerSuspended.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = kein Volume angehalten, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = mindestens ein verschlüsseltes Volume mit ProtectionStatus Off.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = no volume suspended, 1 = input/query/write error,
        2 = at least one encrypted volume with ProtectionStatus Off.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $volumes = @(Get-BitLockerVolume)
    if ($volumes.Count -eq 0) { throw 'Keine Volumes / No volumes returned.' }
    $suspendedVolumes = @($volumes | Where-Object { [string]$_.VolumeStatus -eq 'FullyEncrypted' -and [string]$_.ProtectionStatus -eq 'Off' })
    $cimVolumes = @()
    if ($suspendedVolumes.Count -gt 0) {
        $cimVolumes = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume)
    }
    $records = @(foreach ($volume in $volumes) {
        $mount = [string]$volume.MountPoint
        $suspended = [string]$volume.VolumeStatus -eq 'FullyEncrypted' -and [string]$volume.ProtectionStatus -eq 'Off'
        $count = $null
        $source = 'NotApplicable'
        if ($suspended) {
            $source = 'Unavailable'
            $letter = $mount.TrimEnd('\')
            $cim = @($cimVolumes | Where-Object { ([string]$_.DriveLetter -ieq $letter) -or ([string]$_.DeviceID -ieq $mount) }) | Select-Object -First 1
            if ($cim) {
                # DE: ERROR_NOT_SUPPORTED für Datenvolumes ist kein Skriptfehler. EN: ERROR_NOT_SUPPORTED for data volumes is not a script error.
                try {
                    $result = Invoke-CimMethod -InputObject $cim -MethodName GetSuspendCount
                    if ($null -ne $result -and [uint32]$result.ReturnValue -eq 0) {
                        $count = [int]$result.SuspendCount
                        $source = 'GetSuspendCount'
                    }
                } catch { $source = 'Unavailable' }
            }
        }
        [pscustomobject]@{
            MountPoint = $mount; VolumeType = [string]$volume.VolumeType
            VolumeStatus = [string]$volume.VolumeStatus; ProtectionStatus = [string]$volume.ProtectionStatus
            Suspended = $suspended; RemainingRebootCount = $count; RebootCountSource = $source
        }
    })
    $report = ConvertTo-Json -InputObject ([ordered]@{
        SuspendedVolumes = $suspendedVolumes.Count; Volumes = $records
    }) -Depth 4 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($suspendedVolumes.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
