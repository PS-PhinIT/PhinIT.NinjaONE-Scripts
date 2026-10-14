#Requires -Version 5.1

<#
.SYNOPSIS
DE: Legacy-Dateiname: sicheres, explizit aktiviertes AD-DS-Escrow, KEIN Schluesselexport.
EN: Legacy filename: safe, explicitly enabled AD DS escrow, NOT a key export.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell. Standard ist Inventar von Recovery-Protector-IDs.
EN: SYSTEM, 64-bit Windows PowerShell. Default is recovery protector ID inventory.
DE: MountPoint / bitlockerEscrowMountPoint: Laufwerk, Standard SystemDrive.
EN: MountPoint / bitlockerEscrowMountPoint: drive, default SystemDrive.
DE: EnableAdDsEscrow / bitlockerEnableAdDsEscrow: true/false, Standard false; unterstuetzt WhatIf/Confirm.
EN: EnableAdDsEscrow / bitlockerEnableAdDsEscrow: true/false, default false; supports WhatIf/Confirm.
DE: Nur vorhandene RecoveryPassword-Protectoren via Backup-BitLockerKeyProtector in AD DS sichern.
EN: Backs up existing RecoveryPassword protectors to AD DS via Backup-BitLockerKeyProtector only.
DE: Domainmitgliedschaft, erreichbarer DC und passende AD-DS-Rechte/Schema sind erforderlich.
EN: Requires domain membership, reachable DC, and appropriate AD DS permissions/schema.
DE: Keine Kennwoerter auf Konsole/Felder/Datentraeger; keine Protectoren anlegen; kein Entra-Escrow.
EN: No passwords to console/fields/disk; no protector creation; no Entra escrow.
DE: Cmdlet-Erfolg ist KEINE unabhaengige Verifikation des AD-Objekts; separat in AD pruefen.
EN: Cmdlet success is NOT independent AD-object verification; verify separately in AD.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang. Exit 2 bei fehlenden Protectoren/nicht ausgefuehrtem Escrow.
EN: Explicit parameters take precedence. Exit 2 for missing protectors/unperformed escrow.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER MountPoint
DE: Laufwerk; bitlockerEscrowMountPoint; Standard SystemDrive.
EN: Drive; bitlockerEscrowMountPoint; default SystemDrive.
.PARAMETER EnableAdDsEscrow
DE: AD-DS-Sicherung aktivieren; bitlockerEnableAdDsEscrow; Standard false.
EN: Enable AD DS backup; bitlockerEnableAdDsEscrow; default false.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
.EXAMPLE
.\exportRecoveryKeys.ps1 -MountPoint C:
DE: Nur Inventar der RecoveryPassword-Protector-IDs auf C:; keine Aenderung, keine Kennwoerter.
EN: Inventory of RecoveryPassword protector IDs on C: only; no changes, no passwords.
.EXAMPLE
.\exportRecoveryKeys.ps1 -MountPoint C: -EnableAdDsEscrow true -WhatIf
DE: Simuliert das AD-DS-Escrow; nichts wird gesichert (Status Skipped_NotVerified, Exit 2).
EN: Simulates AD DS escrow; nothing is backed up (status Skipped_NotVerified, exit 2).
.EXAMPLE
.\exportRecoveryKeys.ps1 -MountPoint C: -EnableAdDsEscrow true -Confirm:$false -CustomField bitlockerEscrowStatus
DE: Unbeaufsichtigtes AD-DS-Escrow; NinjaOne-Laeufe benoetigen -Confirm:$false, da ConfirmImpact High sonst eine Rueckfrage ausloest.
EN: Unattended AD DS escrow; NinjaOne runs need -Confirm:$false because ConfirmImpact High otherwise triggers a prompt.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$MountPoint = $env:SystemDrive, [string]$EnableAdDsEscrow = 'false', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Explizites false bleibt false. EN: Explicit false overrides environment opt-in.
    if (-not $PSBoundParameters.ContainsKey('MountPoint')) {
        $MountPoint = ([string]$env:bitlockerEscrowMountPoint).Trim()
        if ($MountPoint -ieq 'null') { $MountPoint = '' }
        if (-not $MountPoint) { $MountPoint = ([string]$env:SystemDrive).Trim() }
    }
    if (-not $PSBoundParameters.ContainsKey('EnableAdDsEscrow')) {
        $EnableAdDsEscrow = ([string]$env:bitlockerEnableAdDsEscrow).Trim()
        if ($EnableAdDsEscrow -ieq 'null') { $EnableAdDsEscrow = '' }
        if (-not $EnableAdDsEscrow) { $EnableAdDsEscrow = 'false' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $MountPoint = ([string]$MountPoint).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $enable = $false
    if (-not [bool]::TryParse($EnableAdDsEscrow, [ref]$enable)) { throw 'EnableAdDsEscrow muss true/false sein / must be true/false.' }
    if ($MountPoint -notmatch '^[A-Za-z]:\\?$') { throw 'MountPoint: Laufwerksbuchstabe erforderlich / Drive letter required.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-BitLockerVolume -ErrorAction Stop
    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    $ids = @($volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object { [string]$_.KeyProtectorId })
    foreach ($id in $ids) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($id, [ref]$parsed)) { throw 'Ungueltige Protector-ID / Invalid protector ID.' }
    }
    if ($enable -and $ids.Count) {
        $null = Get-Command Backup-BitLockerKeyProtector -ErrorAction Stop
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if (-not $computer.PartOfDomain) { throw 'AD-DS-Domainmitgliedschaft erforderlich / AD DS domain membership required.' }
    }
    $warning = -not $ids.Count
    $rows = @()
    foreach ($id in $ids) {
        $status = 'InventoryOnly_NotVerified'
        if ($enable) {
            if ($PSCmdlet.ShouldProcess("$MountPoint / $id", 'AD-DS-Escrow / Back up existing protector to AD DS')) {
                # DE: Cmdlet-Ausgaben/Fehler koennen Geheimnisse enthalten: unterdruecken und Fehler ersetzen.
                # EN: Suppress cmdlet output and replace errors to prevent accidental secret disclosure.
                $global:LASTEXITCODE = 0
                try {
                    $null = Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $id -ErrorAction Stop -WarningAction SilentlyContinue -InformationAction SilentlyContinue -Verbose:$false -Debug:$false
                    if ($global:LASTEXITCODE -ne 0) { throw 'Backup failed.' }
                } catch { throw "AD-DS-Escrow fehlgeschlagen / failed for protector ID $id." }
                $status = 'BackupCommandSucceeded_NotIndependentlyVerified'
            } else { $status = 'Skipped_NotVerified'; $warning = $true }
        }
        $rows += [pscustomobject]@{ ProtectorId = $id; Status = $status }
    }
    if ($global:LASTEXITCODE -ne 0) { throw 'Befehlsfehler / Command failed.' }
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{ MountPoint = $MountPoint; EscrowRequested = $enable; Protectors = $rows }) -Depth 4 -Compress
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
    # DE: Keine ungefilterten BitLocker-Fehler ausgeben. EN: Never emit raw BitLocker errors.
    Write-Error 'Escrow/Inventar fehlgeschlagen. Parameter, Domain und Rechte pruefen; keine Schluessel exportiert. / Escrow/inventory failed. Check parameters, domain and permissions; no keys exported.' -ErrorAction Continue
    exit 1
}