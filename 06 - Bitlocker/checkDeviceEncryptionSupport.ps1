#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Voraussetzungen für die automatische Geräteverschlüsselung (Device Encryption).
    EN: Checks prerequisites for automatic device encryption.
.DESCRIPTION
    DE: Liest per Registry HKLM\SYSTEM\CurrentControlSet\Control\BitLocker\PreventDeviceEncryption
        (1 = automatische Geräteverschlüsselung unterdrückt), HKLM\SYSTEM\CurrentControlSet\Control\
        BitLockerStatus\BootStatus (nur Rohwert, informativ), HKLM\SYSTEM\CurrentControlSet\Control\
        PEFirmwareType (1 = BIOS, 2 = UEFI) und HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State\
        UEFISecureBootEnabled sowie Get-Tpm (TpmPresent/TpmReady). Unterstützt = TPM vorhanden und
        bereit, UEFI, Secure Boot aktiv und PreventDeviceEncryption nicht 1. Das ist eine Näherung:
        Windows prüft je nach Build zusätzlich z. B. Modern Standby/HSTI und DMA-Schutz; das
        msinfo32-Feld "Device Encryption Support" wird nicht ausgewertet. Keine Änderungen.
    EN: Reads via registry HKLM\SYSTEM\CurrentControlSet\Control\BitLocker\PreventDeviceEncryption
        (1 = automatic device encryption suppressed), HKLM\SYSTEM\CurrentControlSet\Control\
        BitLockerStatus\BootStatus (raw value only, informational), HKLM\SYSTEM\CurrentControlSet\
        Control\PEFirmwareType (1 = BIOS, 2 = UEFI) and HKLM\SYSTEM\CurrentControlSet\Control\
        SecureBoot\State\UEFISecureBootEnabled plus Get-Tpm (TpmPresent/TpmReady). Supported = TPM
        present and ready, UEFI, Secure Boot on and PreventDeviceEncryption not 1. This is an
        approximation: depending on the build Windows also checks e.g. Modern Standby/HSTI and DMA
        protection; the msinfo32 field "Device Encryption Support" is not evaluated. No changes.
.PARAMETER RequireSupport
    DE: NinjaOne Checkbox bitlockerRequireDeviceEncryptionSupport; true/false/1/0; Standard false (nur Info).
    EN: NinjaOne Checkbox bitlockerRequireDeviceEncryptionSupport; true/false/1/0; default false (info only).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkDeviceEncryptionSupport.ps1
    DE: Meldet die Bereitschaft rein informativ (Exit 0).
    EN: Reports readiness for information only (exit 0).
.EXAMPLE
    .\checkDeviceEncryptionSupport.ps1 -RequireSupport true -CustomField deviceEncryptionReady
    DE: Exit 2, wenn nicht unterstützt; JSON ins Feld deviceEncryptionReady.
    EN: Exit 2 if not supported; JSON to field deviceEncryptionReady.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = unterstützt oder RequireSupport=false, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = RequireSupport=true und mindestens eine Voraussetzung fehlt (siehe Reasons).
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = supported or RequireSupport=false, 1 = input/query/write error,
        2 = RequireSupport=true and at least one prerequisite is missing (see Reasons).
#>
[CmdletBinding()]
param(
    [string]$RequireSupport = $env:bitlockerRequireDeviceEncryptionSupport,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path
    if ($null -eq $item -or $null -eq $item.PSObject.Properties[$Name]) { return $null }
    return $item.$Name
}
try {
    $RequireSupport = ([string]$RequireSupport).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequireSupport -ieq 'null') { $RequireSupport = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequireSupport) { $RequireSupport = 'false' }
    if ($RequireSupport -notin @('true', 'false', '1', '0')) { throw 'bitlockerRequireDeviceEncryptionSupport: true/false.' }
    $mustSupport = $RequireSupport -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $control = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $prevent = Get-RegistryValue -Path "$control\BitLocker" -Name 'PreventDeviceEncryption'
    $bootStatus = Get-RegistryValue -Path "$control\BitLockerStatus" -Name 'BootStatus'
    $firmware = Get-RegistryValue -Path $control -Name 'PEFirmwareType'
    $secureBoot = Get-RegistryValue -Path "$control\SecureBoot\State" -Name 'UEFISecureBootEnabled'
    $tpm = Get-Tpm
    $firmwareName = 'Unknown'
    if ($firmware -eq 1) { $firmwareName = 'BIOS' } elseif ($firmware -eq 2) { $firmwareName = 'UEFI' }
    $reasons = @()
    if (-not $tpm.TpmPresent) { $reasons += 'TpmNotPresent' } elseif (-not $tpm.TpmReady) { $reasons += 'TpmNotReady' }
    if ($firmwareName -ne 'UEFI') { $reasons += 'FirmwareNotUefi' }
    if ($secureBoot -ne 1) { $reasons += 'SecureBootNotEnabled' }
    if ($prevent -eq 1) { $reasons += 'PreventDeviceEncryptionSet' }
    $report = ConvertTo-Json -InputObject ([ordered]@{
        Supported = ($reasons.Count -eq 0); Reasons = $reasons; RequireSupport = $mustSupport
        TpmPresent = [bool]$tpm.TpmPresent; TpmReady = [bool]$tpm.TpmReady
        FirmwareType = $firmwareName; SecureBootEnabled = ($secureBoot -eq 1)
        PreventDeviceEncryption = $prevent; BitLockerBootStatus = $bootStatus
    }) -Depth 3 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($mustSupport -and $reasons.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
