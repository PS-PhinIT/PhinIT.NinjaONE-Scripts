#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft Verschluesselungsgrad und Verfahren aller BitLocker-Volumes.
EN: Audits encryption progress and methods on all BitLocker volumes.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell; keine Aenderungen, keine Geheimnisse.
EN: SYSTEM, 64-bit Windows PowerShell; no changes or secret collection.
DE: MinimumEncryptionPercent / bitlockerMinimumEncryptionPercent, Standard 100, Bereich 0..100.
EN: MinimumEncryptionPercent / bitlockerMinimumEncryptionPercent, default 100, range 0..100.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang. Auch unverschluesselte Datenvolumes erzeugen Warnungen.
EN: Explicit parameters take precedence. Unencrypted data volumes also produce warnings.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
DE: Exit 2 = Volume unter MinimumEncryptionPercent, Verfahren None oder Status Decryption/Paused.
EN: Exit 2 = volume below MinimumEncryptionPercent, method None or status Decryption/Paused.
.PARAMETER MinimumEncryptionPercent
DE: Minimum 0..100; bitlockerMinimumEncryptionPercent; Standard 100.
EN: Minimum 0..100; bitlockerMinimumEncryptionPercent; default 100.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
.EXAMPLE
.\auditVolumeEncryption.ps1
DE: Verlangt 100 % Verschluesselung auf allen Volumes.
EN: Requires 100% encryption on all volumes.
.EXAMPLE
.\auditVolumeEncryption.ps1 -MinimumEncryptionPercent 90 -CustomField bitlockerEncryption
DE: Akzeptiert ab 90 % (z.B. laufende Verschluesselung); JSON in bitlockerEncryption.
EN: Accepts 90% or more (e.g. encryption in progress); JSON to bitlockerEncryption.
#>
[CmdletBinding()]
param([string]$MinimumEncryptionPercent = '100', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Erst binden, dann pruefen. EN: Validate after environment binding.
    if (-not $PSBoundParameters.ContainsKey('MinimumEncryptionPercent')) {
        $MinimumEncryptionPercent = ([string]$env:bitlockerMinimumEncryptionPercent).Trim()
        if ($MinimumEncryptionPercent -ieq 'null') { $MinimumEncryptionPercent = '' }
        if (-not $MinimumEncryptionPercent) { $MinimumEncryptionPercent = '100' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $minimum = 0
    if (-not [int]::TryParse($MinimumEncryptionPercent, [ref]$minimum) -or $minimum -lt 0 -or $minimum -gt 100) { throw 'MinimumEncryptionPercent muss 0..100 sein / must be 0..100.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-BitLockerVolume -ErrorAction Stop
    $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
    if (-not $volumes.Count) { throw 'Keine Volumes / No volumes returned.' }
    $rows = @($volumes | ForEach-Object {
        $compliant = ($null -ne $_.EncryptionPercentage -and $_.EncryptionPercentage -ge $minimum -and
            [string]$_.EncryptionMethod -ne 'None' -and [string]$_.VolumeStatus -notmatch 'Decryption|Paused')
        [pscustomobject]@{
            MountPoint = $_.MountPoint; EncryptionMethod = [string]$_.EncryptionMethod
            VolumeStatus = [string]$_.VolumeStatus; EncryptionPercentage = $_.EncryptionPercentage
            MinimumEncryptionPercent = $minimum; Compliant = $compliant
        }
    })
    $warning = @($rows | Where-Object { -not $_.Compliant }).Count -gt 0
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
    Write-Error ("Verschluesselungspruefung fehlgeschlagen / Encryption audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
