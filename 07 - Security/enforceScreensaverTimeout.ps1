#Requires -Version 5.1

<#
.SYNOPSIS
DE: Legacy-Dateiname: prueft optional die COMPUTER-Richtlinie fuer Inaktivitaetssperre.
EN: Legacy filename: audits/optionally sets the MACHINE inactivity lock policy.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell. KEINE HKCU-/Bildschirmschoner-Aenderung.
EN: SYSTEM, 64-bit Windows PowerShell. NO HKCU or screensaver changes.
DE: Windows 8 / Server 2012 oder neuer: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System,
    InactivityTimeoutSecs (DWORD), "Interaktive Anmeldung: Inaktivitaetsgrenze des Computers".
EN: Windows 8 / Server 2012 or newer: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System,
    InactivityTimeoutSecs (DWORD), "Interactive logon: Machine inactivity limit".
DE: TimeoutSeconds / securityInactivityTimeoutSeconds: 1..599940, Standard 900.
EN: TimeoutSeconds / securityInactivityTimeoutSeconds: 1..599940, default 900.
DE: ApplyMachinePolicy / securityApplyMachineInactivityPolicy: true/false, Standard false.
EN: ApplyMachinePolicy / securityApplyMachineInactivityPolicy: true/false, default false.
DE: Nur nach ausdruecklicher Aktivierung mit ShouldProcess; fuer unbeaufsichtigt -Confirm:$false.
EN: Changes only after explicit opt-in with ShouldProcess; use -Confirm:$false for unattended runs.
DE: GPO/MDM kann Wert ueberschreiben. Registry-Ruecklesen ist kein Beweis einer laufenden Sitzungssperre.
EN: GPO/MDM may overwrite the value. Registry readback does not prove runtime session locking.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang. Exit 2 bei fehlendem/falschem Wert oder WhatIf.
EN: Explicit parameters take precedence. Exit 2 for missing/mismatched value or WhatIf.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER TimeoutSeconds
DE: Inaktivitaetsgrenze 1..599940; securityInactivityTimeoutSeconds; Standard 900.
EN: Inactivity limit 1..599940; securityInactivityTimeoutSeconds; default 900.
.PARAMETER ApplyMachinePolicy
DE: Maschinenrichtlinie setzen; securityApplyMachineInactivityPolicy; Standard false.
EN: Set machine policy; securityApplyMachineInactivityPolicy; default false.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$TimeoutSeconds = '900', [string]$ApplyMachinePolicy = 'false', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Keine Aenderung durch leere Umgebungswerte. EN: Empty environment values never enable changes.
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        $TimeoutSeconds = ([string]$env:securityInactivityTimeoutSeconds).Trim()
        if ($TimeoutSeconds -ieq 'null') { $TimeoutSeconds = '' }
        if (-not $TimeoutSeconds) { $TimeoutSeconds = '900' }
    }
    if (-not $PSBoundParameters.ContainsKey('ApplyMachinePolicy')) {
        $ApplyMachinePolicy = ([string]$env:securityApplyMachineInactivityPolicy).Trim()
        if ($ApplyMachinePolicy -ieq 'null') { $ApplyMachinePolicy = '' }
        if (-not $ApplyMachinePolicy) { $ApplyMachinePolicy = 'false' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $seconds = 0
    $apply = $false
    if (-not [int]::TryParse($TimeoutSeconds, [ref]$seconds) -or $seconds -lt 1 -or $seconds -gt 599940) { throw 'TimeoutSeconds muss 1..599940 sein / must be 1..599940.' }
    if (-not [bool]::TryParse($ApplyMachinePolicy, [ref]$apply)) { throw 'ApplyMachinePolicy muss true/false sein / must be true/false.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 9200) { throw 'Windows 8 / Server 2012 oder neuer erforderlich / or newer required.' }
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $current = $null
    $kind = ''
    if (Test-Path -LiteralPath $path -ErrorAction Stop) {
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($key.GetValueNames() -contains 'InactivityTimeoutSecs') {
            $current = $key.GetValue('InactivityTimeoutSecs')
            $kind = [string]$key.GetValueKind('InactivityTimeoutSecs')
        }
    }
    $changed = $false
    $skipped = $false
    if ($apply -and ($current -ne $seconds -or $kind -ne 'DWord')) {
        if ($PSCmdlet.ShouldProcess($path, "Computer-Inaktivitaetsgrenze setzen / Set machine inactivity limit to $seconds seconds")) {
            if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) {
                $null = New-Item -Path $path -ErrorAction Stop
            }
            $null = New-ItemProperty -LiteralPath $path -Name InactivityTimeoutSecs -Value $seconds -PropertyType DWord -Force -ErrorAction Stop
            $key = Get-Item -LiteralPath $path -ErrorAction Stop
            $current = $key.GetValue('InactivityTimeoutSecs')
            $kind = [string]$key.GetValueKind('InactivityTimeoutSecs')
            if ($current -ne $seconds -or $kind -ne 'DWord') { throw 'Registry-Verifikation fehlgeschlagen / Registry verification failed.' }
            $changed = $true
        } else { $skipped = $true }
    }
    $compliant = $null -ne $current -and $current -eq $seconds -and $kind -eq 'DWord'
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{
        Scope = 'Machine_HKLM'; DesiredSeconds = $seconds; ConfiguredSeconds = $current
        RegistryType = $kind; Compliant = $compliant; Changed = $changed; Skipped = $skipped
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
    if (-not $compliant -or $skipped) { exit 2 }
    exit 0
} catch {
    Write-Error ("Inaktivitaetsrichtlinie fehlgeschlagen / Inactivity policy failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}