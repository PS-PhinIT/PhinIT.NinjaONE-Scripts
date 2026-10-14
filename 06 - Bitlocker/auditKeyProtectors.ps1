#Requires -Version 5.1

<#
.SYNOPSIS
DE: Inventarisiert ausschliesslich BitLocker-Schutztypen und IDs.
EN: Inventories only BitLocker protector types and IDs.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell. Keine RecoveryPassword-Werte lesen/ausgeben.
EN: SYSTEM, 64-bit Windows PowerShell. Never read/output RecoveryPassword values.
DE: RequireRecoveryProtector / bitlockerRequireRecoveryProtector: true/false, Standard false.
EN: RequireRecoveryProtector / bitlockerRequireRecoveryProtector: true/false, default false.
DE: Prueft lokale Existenz, NICHT erfolgreichen AD/Entra-Escrow.
EN: Checks local existence, NOT successful AD/Entra escrow.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang; nur Erkennung.
EN: Explicit parameters take precedence; detection only.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
DE: Exit 2 = Volume ohne Protector oder (bei RequireRecoveryProtector=true) ohne RecoveryPassword-Protector.
EN: Exit 2 = volume without protectors or (with RequireRecoveryProtector=true) without a RecoveryPassword protector.
.PARAMETER RequireRecoveryProtector
DE: Recovery-Protector verlangen; bitlockerRequireRecoveryProtector; Standard false.
EN: Require a recovery protector; bitlockerRequireRecoveryProtector; default false.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
.EXAMPLE
.\auditKeyProtectors.ps1
DE: Listet Protector-Typen und IDs aller Volumes; Warnung nur bei Volumes ohne Protector.
EN: Lists protector types and IDs of all volumes; warns only for volumes without protectors.
.EXAMPLE
.\auditKeyProtectors.ps1 -RequireRecoveryProtector true -CustomField bitlockerProtectors
DE: Verlangt einen RecoveryPassword-Protector je Volume; JSON in bitlockerProtectors.
EN: Requires a RecoveryPassword protector per volume; JSON to bitlockerProtectors.
#>
[CmdletBinding()]
param([string]$RequireRecoveryProtector = 'false', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Umgebungswerte sind optional. EN: Environment defaults are optional.
    if (-not $PSBoundParameters.ContainsKey('RequireRecoveryProtector')) {
        $RequireRecoveryProtector = ([string]$env:bitlockerRequireRecoveryProtector).Trim()
        if ($RequireRecoveryProtector -ieq 'null') { $RequireRecoveryProtector = '' }
        if (-not $RequireRecoveryProtector) { $RequireRecoveryProtector = 'false' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $required = $false
    if (-not [bool]::TryParse($RequireRecoveryProtector, [ref]$required)) { throw 'RequireRecoveryProtector muss true/false sein / must be true/false.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-BitLockerVolume -ErrorAction Stop
    $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
    if (-not $volumes.Count) { throw 'Keine Volumes / No volumes returned.' }
    $rows = @($volumes | ForEach-Object {
        # DE: Nur sichere Eigenschaften projizieren. EN: Project safe metadata only.
        $protectors = @($_.KeyProtector | ForEach-Object {
            [pscustomobject]@{ Id = [string]$_.KeyProtectorId; Type = [string]$_.KeyProtectorType }
        })
        $hasRecovery = @($protectors | Where-Object { $_.Type -eq 'RecoveryPassword' }).Count -gt 0
        [pscustomobject]@{ MountPoint = $_.MountPoint; Protectors = $protectors; HasRecoveryProtector = $hasRecovery }
    })
    $warning = @($rows | Where-Object { -not $_.Protectors.Count -or ($required -and -not $_.HasRecoveryProtector) }).Count -gt 0
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    $text = ConvertTo-Json -InputObject $rows -Depth 5 -Compress
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
    Write-Error ("Schutzinventar fehlgeschlagen / Protector inventory failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
