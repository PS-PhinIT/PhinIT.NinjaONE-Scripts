#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft Microsoft Defender und das Alter der Virensignaturen.
EN: Audits Microsoft Defender and antivirus signature age.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell; nur Status, keine Updates/Scans/Aenderungen.
EN: SYSTEM, 64-bit Windows PowerShell; status only, no updates/scans/changes.
DE: MaxSignatureAgeHours / securityDefenderMaxSignatureAgeHours: 1..8760, Standard 48.
EN: MaxSignatureAgeHours / securityDefenderMaxSignatureAgeHours: 1..8760, default 48.
DE: Fehlender Defender-Befehl ist Fehler; passiver Modus/inaktiver Schutz ist Warnung,
    auch wenn ein anderes Produkt absichtlich den Schutz uebernimmt.
EN: Missing Defender command is an error; passive mode/inactive protection is a warning,
    even when another product intentionally provides protection.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang.
EN: Explicit parameters take precedence.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER MaxSignatureAgeHours
DE: Signaturalter 1..8760 Stunden; securityDefenderMaxSignatureAgeHours; Standard 48.
EN: Signature age 1..8760 hours; securityDefenderMaxSignatureAgeHours; default 48.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
#>
[CmdletBinding()]
param([string]$MaxSignatureAgeHours = '48', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Umgebungsparameter erst binden. EN: Bind environment parameters first.
    if (-not $PSBoundParameters.ContainsKey('MaxSignatureAgeHours')) {
        $MaxSignatureAgeHours = ([string]$env:securityDefenderMaxSignatureAgeHours).Trim()
        if ($MaxSignatureAgeHours -ieq 'null') { $MaxSignatureAgeHours = '' }
        if (-not $MaxSignatureAgeHours) { $MaxSignatureAgeHours = '48' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $maximum = 0
    if (-not [int]::TryParse($MaxSignatureAgeHours, [ref]$maximum) -or $maximum -lt 1 -or $maximum -gt 8760) { throw 'MaxSignatureAgeHours muss 1..8760 sein / must be 1..8760.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-MpComputerStatus -ErrorAction Stop
    $status = Get-MpComputerStatus -ErrorAction Stop
    if ($null -eq $status) { throw 'Defender-Status fehlt / Defender status unavailable.' }
    $age = $null
    $updated = $null
    if ($null -ne $status.AntivirusSignatureLastUpdated) {
        $updated = ([datetime]$status.AntivirusSignatureLastUpdated).ToUniversalTime()
        $age = [math]::Round(([datetime]::UtcNow - $updated).TotalHours, 2)
    }
    $mode = [string]$status.AMRunningMode
    $warning = -not $status.AMServiceEnabled -or -not $status.AntivirusEnabled -or
        -not $status.RealTimeProtectionEnabled -or -not $status.BehaviorMonitorEnabled -or
        $null -eq $age -or $age -lt 0 -or $age -gt $maximum -or ($mode -and $mode -ne 'Normal')
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{
        AMServiceEnabled = $status.AMServiceEnabled; AntivirusEnabled = $status.AntivirusEnabled
        RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled; BehaviorMonitorEnabled = $status.BehaviorMonitorEnabled
        AMRunningMode = $mode; SignatureVersion = [string]$status.AntivirusSignatureVersion
        SignatureUpdatedUtc = $(if ($updated) { $updated.ToString('o') } else { $null })
        SignatureAgeHours = $age; MaximumAgeHours = $maximum
    }) -Depth 4 -Compress
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
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
    Write-Error ("Defender-Pruefung fehlgeschlagen / Defender audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}