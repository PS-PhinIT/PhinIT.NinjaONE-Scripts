#Requires -Version 5.1

<#
.SYNOPSIS
DE: Liest und dekodiert die Computer-Richtlinie für Zertifikat-Autoregistrierung (AEPolicy).
EN: Reads and decodes the computer certificate autoenrollment policy (AEPolicy).
.DESCRIPTION
DE: Liest HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment (AEPolicy,
    OfflineExpirationPercent, OfflineExpirationStoreNames) und dekodiert AEPolicy nach MS-CAESO:
    0x1 = Registrierung/Vorlagenprüfung ("Zertifikate aktualisieren, die Vorlagen verwenden"),
    0x2 = Speicherverwaltung (abgelaufene erneuern, gesperrte entfernen), 0x4 = ausstehende
    Anforderungen abrufen, 0x8000 = deaktiviert. GPO "Aktiviert" mit beiden Optionen = 7.
    Enabled = Wert vorhanden, 0x8000 nicht gesetzt und 0x1 gesetzt. Nur lesend.
EN: Reads HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment (AEPolicy,
    OfflineExpirationPercent, OfflineExpirationStoreNames) and decodes AEPolicy per MS-CAESO:
    0x1 = enrollment/template check ("Update certificates that use certificate templates"),
    0x2 = store management (renew expired, remove revoked), 0x4 = fetch pending requests,
    0x8000 = disabled. GPO "Enabled" with both options = 7.
    Enabled = value present, 0x8000 not set and 0x1 set. Read-only.
.PARAMETER RequireEnabled
DE: NinjaOne Checkbox/Text certAutoEnrollRequireEnabled; true/false; Standard false. true = nicht aktiv ergibt Exit 2.
EN: NinjaOne checkbox/text certAutoEnrollRequireEnabled; true/false; default false. true = not active yields exit 2.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkAutoEnrollmentPolicy.ps1
DE: Meldet den dekodierten Richtlinienstatus (immer Exit 0, außer bei Fehlern).
EN: Reports the decoded policy state (always exit 0 unless an error occurs).
.EXAMPLE
.\checkAutoEnrollmentPolicy.ps1 -RequireEnabled true -CustomField autoEnrollmentReport
DE: Exit 2, wenn Autoregistrierung nicht aktiv ist; JSON in autoEnrollmentReport.
EN: Exit 2 if autoenrollment is not active; JSON to autoEnrollmentReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur Computerrichtlinie (keine Benutzerrichtlinie).
    Exit 0 = OK, 1 = Eingabe-, Registry- oder Schreibfehler, 2 = RequireEnabled=true und
    Richtlinie fehlt, ist deaktiviert (0x8000), ohne 0x1 oder hat einen ungültigen Typ.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Computer policy only (no user policy).
    Exit 0 = OK, 1 = input, registry or write error, 2 = RequireEnabled=true and the policy
    is missing, disabled (0x8000), lacks 0x1 or has an invalid type.
#>
[CmdletBinding()]
param(
    [string]$RequireEnabled = $env:certAutoEnrollRequireEnabled,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryKeyValue {
    param([string]$Path)
    try { Get-ItemProperty -Path $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { $null }
}
try {
    $RequireEnabled = ([string]$RequireEnabled).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $RequireEnabled -or $RequireEnabled -ieq 'null') { $RequireEnabled = 'false' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($RequireEnabled -notin @('true', 'false')) { throw 'certAutoEnrollRequireEnabled: true/false erforderlich / required.' }
    $require = $RequireEnabled -ieq 'true'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment'
    $values = Get-RegistryKeyValue -Path $path
    $raw = $null
    $percent = $null
    $storeNames = $null
    if ($null -ne $values) {
        if ($values.PSObject.Properties['AEPolicy']) { $raw = $values.AEPolicy }
        if ($values.PSObject.Properties['OfflineExpirationPercent']) { $percent = $values.OfflineExpirationPercent }
        if ($values.PSObject.Properties['OfflineExpirationStoreNames']) { $storeNames = @($values.OfflineExpirationStoreNames | ForEach-Object { [string]$_ } | Select-Object -First 10) }
    }
    $state = 'NotConfigured'
    $decoded = $null
    $enabled = $false
    if ($null -ne $raw) {
        if ($raw -is [int] -or $raw -is [long] -or $raw -is [uint32]) {
            $value = [long]$raw -band 0xFFFFFFFFL
            $disabled = ($value -band 0x8000) -ne 0
            $enabled = -not $disabled -and ($value -band 0x1) -ne 0
            if ($disabled) { $state = 'Disabled' } elseif ($enabled) { $state = 'Enabled' } else { $state = 'ConfiguredWithoutEnrollment' }
            $decoded = [ordered]@{
                Value = $value; Hex = ('0x{0:X8}' -f $value)
                EnrollAndUpdateTemplates = ($value -band 0x1) -ne 0
                RenewExpiredRemoveRevoked = ($value -band 0x2) -ne 0
                RetrievePending = ($value -band 0x4) -ne 0
                DisableAll = $disabled
                UnknownBits = ('0x{0:X8}' -f ($value -band (-bnot 0x8007L) -band 0xFFFFFFFFL))
            }
        } else {
            $state = 'InvalidType'
        }
    }
    $findings = @()
    if ($require -and -not $enabled) { $findings += "NotEnabled:$state" }
    $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; PolicyPath = $path; State = $state; Enabled = $enabled
        AEPolicy = $decoded; OfflineExpirationPercent = $percent; OfflineExpirationStoreNames = $storeNames
        RequireEnabled = $require; Findings = $findings
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
