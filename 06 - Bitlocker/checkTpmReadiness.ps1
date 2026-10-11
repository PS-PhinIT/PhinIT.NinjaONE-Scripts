#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft TPM-Bereitschaft und optional TPM 2.0 fuer BitLocker.
EN: Checks TPM readiness and optionally TPM 2.0 for BitLocker.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell; niemals TPM loeschen oder initialisieren.
EN: SYSTEM, 64-bit Windows PowerShell; never clears or initializes the TPM.
DE: RequireTpm20 / bitlockerRequireTpm20: true/false, Standard false.
EN: RequireTpm20 / bitlockerRequireTpm20: true/false, default false.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang; Besitz-Geheimnisse werden nicht gelesen.
EN: Explicit parameters take precedence; ownership secrets are not read.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER RequireTpm20
DE: TPM 2.0 verlangen; bitlockerRequireTpm20; Standard false.
EN: Require TPM 2.0; bitlockerRequireTpm20; default false.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
#>
[CmdletBinding()]
param([string]$RequireTpm20 = 'false', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Binden vor Validierung. EN: Bind before validation.
    if (-not $PSBoundParameters.ContainsKey('RequireTpm20')) {
        $RequireTpm20 = ([string]$env:bitlockerRequireTpm20).Trim()
        if ($RequireTpm20 -ieq 'null') { $RequireTpm20 = '' }
        if (-not $RequireTpm20) { $RequireTpm20 = 'false' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $require20 = $false
    if (-not [bool]::TryParse($RequireTpm20, [ref]$require20)) { throw 'RequireTpm20 muss true/false sein / must be true/false.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-Tpm -ErrorAction Stop
    $tpm = Get-Tpm -ErrorAction Stop
    $spec = ''
    if ($tpm.TpmPresent) {
        $hardware = @(Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop)
        if ($hardware.Count -ne 1) { throw 'TPM-Metadaten fehlen / TPM metadata unavailable.' }
        $spec = [string]$hardware[0].SpecVersion
    }
    $is20 = $spec -match '(^|,\s*)2\.0($|,)'
    $warning = -not $tpm.TpmPresent -or -not $tpm.TpmReady -or $tpm.LockedOut -or ($require20 -and -not $is20)
    $result = [pscustomobject]@{
        TpmPresent = $tpm.TpmPresent; TpmReady = $tpm.TpmReady; TpmEnabled = $tpm.TpmEnabled
        TpmActivated = $tpm.TpmActivated; LockedOut = $tpm.LockedOut
        RestartPending = $tpm.RestartPending; SpecVersion = $spec; RequireTpm20 = $require20
    }
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    $text = ConvertTo-Json -InputObject $result -Depth 4 -Compress
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
    Write-Error ("TPM-Pruefung fehlgeschlagen / TPM audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
