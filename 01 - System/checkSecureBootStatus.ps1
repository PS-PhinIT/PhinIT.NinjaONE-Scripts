#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob Secure Boot aktiviert ist.
    EN: Checks whether Secure Boot is enabled.
.DESCRIPTION
    DE: Ruft Confirm-SecureBootUEFI auf (nur lesend) und meldet Enabled, Disabled
        oder NotSupported (Legacy-BIOS bzw. Plattform ohne Secure-Boot-Unterstützung).
        Zusätzlich wird der Firmwaretyp aus HKLM:\SYSTEM\CurrentControlSet\Control\
        PEFirmwareType gemeldet (BIOS/UEFI/Unknown). Ausgabe als JSON, optional in
        ein MultiLine-Feld (max. 4000 Zeichen). Exit 0 = Enabled (oder NotSupported
        mit AllowUnsupported=true), 1 = Eingabe-, Abfrage- (z. B. fehlende Rechte,
        Cmdlet fehlt) oder Schreibfehler, 2 = Disabled oder NotSupported. Nur lesend.
    EN: Calls Confirm-SecureBootUEFI (read-only) and reports Enabled, Disabled or
        NotSupported (legacy BIOS or platform without Secure Boot support).
        Also reports the firmware type from HKLM:\SYSTEM\CurrentControlSet\Control\
        PEFirmwareType (BIOS/UEFI/Unknown). Outputs JSON, optionally to a MultiLine
        field (max. 4000 characters). Exit 0 = Enabled (or NotSupported with
        AllowUnsupported=true), 1 = input, query (e.g. access denied, cmdlet
        missing) or write error, 2 = Disabled or NotSupported. Read-only.
.PARAMETER AllowUnsupported
    DE: NinjaOne Checkbox/Text systemSecureBootAllowUnsupported, true/false/1/0; Standard false.
        true = NotSupported führt zu Exit 0 statt 2.
    EN: NinjaOne checkbox/text systemSecureBootAllowUnsupported, true/false/1/0; default false.
        true = NotSupported results in exit 0 instead of 2.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\checkSecureBootStatus.ps1
    DE: Warnt (Exit 2), wenn Secure Boot nicht aktiviert oder nicht unterstützt ist.
    EN: Warns (exit 2) if Secure Boot is not enabled or not supported.
.EXAMPLE
    .\checkSecureBootStatus.ps1 -AllowUnsupported true -CustomField secureBootStatus
    DE: Legacy-Systeme nicht als Warnung werten; JSON ins Feld secureBootStatus.
    EN: Do not flag legacy systems; JSON to the field secureBootStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM (Administratorrechte nötig), 64-Bit.
        Parameter überschreiben Variablen. Exit 0 = OK, 1 = Fehler,
        2 = Secure Boot aus/nicht unterstützt. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM (administrator rights required), 64-bit.
        Parameters override variables. Exit 0 = OK, 1 = error,
        2 = Secure Boot off/not supported. Read-only.
#>
[CmdletBinding()]
param(
    [string]$AllowUnsupported = $env:systemSecureBootAllowUnsupported,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $AllowUnsupported = ([string]$AllowUnsupported).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $AllowUnsupported -or $AllowUnsupported -ieq 'null') { $AllowUnsupported = 'false' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($AllowUnsupported -notin @('true', 'false', '1', '0')) {
        throw 'systemSecureBootAllowUnsupported: true/false/1/0 erforderlich / required.'
    }
    $allow = $AllowUnsupported -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    if (-not (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
        throw 'Confirm-SecureBootUEFI fehlt / is unavailable.'
    }
    $firmwareType = 'Unknown'
    try {
        $peType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop).PEFirmwareType
        if ([int]$peType -eq 1) { $firmwareType = 'BIOS' }
        elseif ([int]$peType -eq 2) { $firmwareType = 'UEFI' }
    }
    catch { $firmwareType = 'Unknown' }
    $state = $null
    try {
        if ([bool](Confirm-SecureBootUEFI -ErrorAction Stop)) { $state = 'Enabled' } else { $state = 'Disabled' }
    }
    catch {
        # DE: Legacy-BIOS meldet PlatformNotSupportedException; andere Fehler (z. B. Zugriff) bleiben Fehler.
        # EN: Legacy BIOS raises PlatformNotSupportedException; other errors (e.g. access) remain errors.
        if ($_.Exception -is [System.PlatformNotSupportedException] -or [string]$_.FullyQualifiedErrorId -like 'NotSupported*') {
            $state = 'NotSupported'
        }
        else { throw }
    }
    $warning = ($state -eq 'Disabled' -or ($state -eq 'NotSupported' -and -not $allow))
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        SecureBoot = $state
        FirmwareType = $firmwareType
        AllowUnsupported = $allow
        Compliant = -not $warning
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
