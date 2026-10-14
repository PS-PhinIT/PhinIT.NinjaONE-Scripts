#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft, ob Credential Guard und optional HVCI (Speicherintegritaet) laufen.
EN: Checks whether Credential Guard and optionally HVCI (memory integrity) are running.
.DESCRIPTION
DE: Liest per CIM root/Microsoft/Windows/DeviceGuard, Klasse Win32_DeviceGuard:
    VirtualizationBasedSecurityStatus (0 aus, 1 aktiviert aber nicht laufend, 2 laufend),
    SecurityServicesConfigured/-Running (1 Credential Guard, 2 HVCI, 3 System Guard Secure Launch,
    4 SMM-Firmwaremessung, 5/6 Kernel-Stack-Schutz/Audit, 7 HVPT), AvailableSecurityProperties
    und den Code-Integrity-Status (0 aus, 1 Audit, 2 erzwungen). Registry-Herkunft:
    Lsa\LsaCfgFlags, Policies\...\DeviceGuard (EnableVirtualizationBasedSecurity, LsaCfgFlags)
    und DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled. Fehlende Werte = State
    NotConfigured; der wirksame Standard ist versionsabhaengig (Windows 11 22H2+ Enterprise/Education
    aktiviert Credential Guard auf geeigneter Hardware automatisch), daher zaehlt nur der
    CIM-Laufzeitstatus.
EN: Reads via CIM root/Microsoft/Windows/DeviceGuard, class Win32_DeviceGuard:
    VirtualizationBasedSecurityStatus (0 off, 1 enabled but not running, 2 running),
    SecurityServicesConfigured/-Running (1 Credential Guard, 2 HVCI, 3 System Guard Secure Launch,
    4 SMM firmware measurement, 5/6 kernel stack protection/audit, 7 HVPT),
    AvailableSecurityProperties and code integrity status (0 off, 1 audit, 2 enforced).
    Registry provenance: Lsa\LsaCfgFlags, Policies\...\DeviceGuard (EnableVirtualizationBasedSecurity,
    LsaCfgFlags) and DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity\Enabled. Absent values =
    State NotConfigured; the effective default depends on the version (Windows 11 22H2+
    Enterprise/Education enables Credential Guard automatically on eligible hardware), so only
    the CIM runtime status counts.
DE: Exit 2 = geforderter Dienst (RequireCredentialGuard/RequireHvci) laeuft nicht.
EN: Exit 2 = a required service (RequireCredentialGuard/RequireHvci) is not running.
.PARAMETER RequireCredentialGuard
DE: NinjaOne Checkbox/Text securityRequireCredentialGuard: true/false; Standard true.
EN: NinjaOne checkbox/text securityRequireCredentialGuard: true/false; default true.
.PARAMETER RequireHvci
DE: NinjaOne Checkbox/Text securityRequireHvci: true/false; Standard false.
EN: NinjaOne checkbox/text securityRequireHvci: true/false; default false.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkCredentialGuard.ps1
DE: Warnt, wenn Credential Guard nicht laeuft.
EN: Warns if Credential Guard is not running.
.EXAMPLE
.\checkCredentialGuard.ps1 -RequireCredentialGuard false -RequireHvci true -CustomField vbsStatus
DE: Verlangt nur HVCI; JSON in das MultiLine-Feld vbsStatus.
EN: Requires HVCI only; JSON to the MultiLine field vbsStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler (z. B. Klasse fehlt), 2 = Dienst laeuft nicht.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = OK, 1 = input/query/write error (e.g. class missing), 2 = service not running.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'RequireCredentialGuard', Justification = 'true/false switch text, not a secret.')]
[CmdletBinding()]
param(
    [string]$RequireCredentialGuard = $env:securityRequireCredentialGuard,
    [string]$RequireHvci = $env:securityRequireHvci,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'

function Get-RegistrySetting {
    param([string]$Path, [string]$Name, $DefaultValue, [hashtable]$Map)
    $raw = $null
    if (Test-Path -LiteralPath $Path) {
        $property = (Get-ItemProperty -LiteralPath $Path).PSObject.Properties[$Name]
        if ($null -ne $property) { $raw = $property.Value }
    }
    $state = 'NotConfigured'
    $value = $null
    $effective = $DefaultValue
    if ($null -ne $raw) {
        $number = 0
        if ([int]::TryParse(([string]$raw).Trim(), [ref]$number)) { $state = 'Configured'; $value = $number; $effective = $number }
        else { $state = 'Invalid'; $effective = $null }
    }
    $meaning = $null
    if ($Map) {
        $meaning = 'Unknown'
        if ($null -ne $effective -and $Map.ContainsKey($effective)) { $meaning = $Map[$effective] }
    }
    [pscustomobject]@{ Name = $Name; State = $state; Value = $value; EffectiveValue = $effective; Meaning = $meaning }
}

function ConvertTo-NameList {
    param($Values, [hashtable]$Map)
    @(foreach ($item in @($Values)) {
        if ($null -eq $item) { continue }
        $number = [int]$item
        if ($Map.ContainsKey($number)) { $Map[$number] } else { 'Unknown(' + $number + ')' }
    })
}

try {
    $RequireCredentialGuard = ([string]$RequireCredentialGuard).Trim()
    if ($RequireCredentialGuard -ieq 'null' -or -not $RequireCredentialGuard) { $RequireCredentialGuard = 'true' }
    $needCg = $false
    if (-not [bool]::TryParse($RequireCredentialGuard, [ref]$needCg)) { throw 'RequireCredentialGuard muss true/false sein / must be true/false.' }
    $RequireHvci = ([string]$RequireHvci).Trim()
    if ($RequireHvci -ieq 'null' -or -not $RequireHvci) { $RequireHvci = 'false' }
    $needHvci = $false
    if (-not [bool]::TryParse($RequireHvci, [ref]$needHvci)) { throw 'RequireHvci muss true/false sein / must be true/false.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }

    $guard = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName 'Win32_DeviceGuard')
    if ($guard.Count -eq 0 -or $null -eq $guard[0]) { throw 'Win32_DeviceGuard liefert keine Daten / returned no data.' }
    $guard = $guard[0]
    $services = @{
        0 = 'None'; 1 = 'CredentialGuard'; 2 = 'HVCI'; 3 = 'SystemGuardSecureLaunch'; 4 = 'SmmFirmwareMeasurement'
        5 = 'KernelModeHardwareEnforcedStackProtection'; 6 = 'KernelModeHardwareEnforcedStackProtectionAudit'; 7 = 'HypervisorEnforcedPagingTranslation'
    }
    $properties = @{
        0 = 'None'; 1 = 'HypervisorSupport'; 2 = 'SecureBoot'; 3 = 'DmaProtection'; 4 = 'SecureMemoryOverwrite'
        5 = 'NxProtections'; 6 = 'SmmMitigations'; 7 = 'MbecOrGmet'; 8 = 'ApicVirtualization'
    }
    $vbsMap = @{ 0 = 'NotEnabled'; 1 = 'EnabledNotRunning'; 2 = 'Running' }
    $ciMap = @{ 0 = 'Off'; 1 = 'Audit'; 2 = 'Enforced' }
    $vbs = 'Unknown'
    if ($null -ne $guard.VirtualizationBasedSecurityStatus -and $vbsMap.ContainsKey([int]$guard.VirtualizationBasedSecurityStatus)) { $vbs = $vbsMap[[int]$guard.VirtualizationBasedSecurityStatus] }
    $ci = 'Unknown'
    if ($null -ne $guard.CodeIntegrityPolicyEnforcementStatus -and $ciMap.ContainsKey([int]$guard.CodeIntegrityPolicyEnforcementStatus)) { $ci = $ciMap[[int]$guard.CodeIntegrityPolicyEnforcementStatus] }
    $running = @(ConvertTo-NameList -Values $guard.SecurityServicesRunning -Map $services)
    $configured = @(ConvertTo-NameList -Values $guard.SecurityServicesConfigured -Map $services)
    $cgRunning = $running -contains 'CredentialGuard'
    $hvciRunning = $running -contains 'HVCI'

    $lsaMap = @{ 0 = 'Disabled'; 1 = 'EnabledWithUefiLock'; 2 = 'EnabledWithoutLock' }
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    $registry = @(
        (Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -DefaultValue $null -Map $lsaMap),
        (Get-RegistrySetting -Path $policyPath -Name 'LsaCfgFlags' -DefaultValue $null -Map $lsaMap),
        (Get-RegistrySetting -Path $policyPath -Name 'EnableVirtualizationBasedSecurity' -DefaultValue $null -Map @{ 0 = 'Disabled'; 1 = 'Enabled' }),
        (Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -DefaultValue $null -Map @{ 0 = 'Disabled'; 1 = 'Enabled' })
    )
    $registry[0] | Add-Member -NotePropertyName Key -NotePropertyValue 'Lsa'
    $registry[1] | Add-Member -NotePropertyName Key -NotePropertyValue 'Policy'
    $registry[2] | Add-Member -NotePropertyName Key -NotePropertyValue 'Policy'
    $registry[3] | Add-Member -NotePropertyName Key -NotePropertyValue 'HvciScenario'

    $findings = New-Object System.Collections.Generic.List[string]
    if ($needCg -and -not $cgRunning) { $findings.Add('CredentialGuardNotRunning') }
    if ($needHvci -and -not $hvciRunning) { $findings.Add('HvciNotRunning') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status; RequireCredentialGuard = $needCg; RequireHvci = $needHvci
        VirtualizationBasedSecurity = $vbs; CredentialGuardRunning = $cgRunning; HvciRunning = $hvciRunning
        ServicesConfigured = $configured; ServicesRunning = $running
        AvailableSecurityProperties = @(ConvertTo-NameList -Values $guard.AvailableSecurityProperties -Map $properties)
        CodeIntegrityPolicy = $ci; Registry = $registry; Findings = @($findings)
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
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
