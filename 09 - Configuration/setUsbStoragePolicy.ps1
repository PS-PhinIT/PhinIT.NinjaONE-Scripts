#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Sperre von USB-Massenspeichern (USBSTOR) und optional den Schreibschutz und setzt sie optional.
    EN: Audits the USB mass storage block (USBSTOR) and optionally the write protection and optionally sets them.
.DESCRIPTION
    DE: Liest HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR Start (4 = gesperrt/deaktiviert, 3 = erlaubt/manuell).
        Fehlt der Schlüssel USBSTOR, endet das Skript mit Exit 1. Optional (configUsbStorageDenyWriteOnly) wird die
        Richtlinie HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}
        Deny_Write verwaltet: true = DWORD 1 (Wechseldatenträger nur lesbar), false = Wert entfernen, leer = nicht verwaltet.
        Ohne Opt-in (configUsbStorageAllow=true) wird nichts geändert. Mit Opt-in werden nur abweichende Werte innerhalb
        von ShouldProcess geschrieben bzw. entfernt (fehlender Richtlinienschlüssel wird angelegt) und erneut gelesen.
        Bereits eingebundene USB-Laufwerke bleiben bis zum erneuten Anstecken oder Neustart zugänglich.
        Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
    EN: Reads HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR Start (4 = blocked/disabled, 3 = allowed/manual).
        If the USBSTOR key is missing the script exits 1. Optionally (configUsbStorageDenyWriteOnly) the policy
        HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}
        Deny_Write is managed: true = DWORD 1 (removable disks read-only), false = remove the value, empty = not managed.
        Without opt-in (configUsbStorageAllow=true) nothing is changed. With opt-in only differing values are written
        or removed inside ShouldProcess (a missing policy key is created) and read back.
        Already mounted USB drives stay accessible until they are replugged or the device restarts.
        Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
.PARAMETER Blocked
    DE: NinjaOne Checkbox/Text configUsbStorageBlocked; erforderlich; true = USB-Massenspeicher sperren (Start=4), false = erlauben (Start=3).
    EN: NinjaOne checkbox/text configUsbStorageBlocked; required; true = block USB mass storage (Start=4), false = allow (Start=3).
.PARAMETER DenyWriteOnly
    DE: NinjaOne Text configUsbStorageDenyWriteOnly; true = Schreibzugriff verweigern (Deny_Write=1), false = Wert entfernen; Standard leer (nicht verwaltet).
    EN: NinjaOne text configUsbStorageDenyWriteOnly; true = deny write access (Deny_Write=1), false = remove the value; default empty (not managed).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configUsbStorageAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configUsbStorageAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setUsbStoragePolicy.ps1 -Blocked true
    DE: Nur Prüfung: Exit 2, wenn USB-Massenspeicher nicht gesperrt sind.
    EN: Audit only: exit 2 if USB mass storage is not blocked.
.EXAMPLE
    .\setUsbStoragePolicy.ps1 -Blocked true -Allow true -WhatIf
    DE: Simuliert die Sperre; nichts wird geändert (Exit 0).
    EN: Simulates the block; nothing is changed (exit 0).
.EXAMPLE
    .\setUsbStoragePolicy.ps1 -Blocked false -DenyWriteOnly true -Allow true -CustomField usbReport
    DE: Erlaubt USB-Massenspeicher nur lesend und schreibt das JSON in usbReport.
    EN: Allows USB mass storage read-only and writes the JSON to usbReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Gruppenrichtlinien/MDM können die Werte überschreiben. Andere Gerätesteuerungen (Defender Device Control) werden nicht ausgewertet.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler bzw. USBSTOR fehlt; 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Group Policy/MDM may overwrite the values. Other device controls (Defender Device Control) are not evaluated.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error or USBSTOR missing; 2 = drift without opt-in or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Blocked = $env:configUsbStorageBlocked,
    [string]$DenyWriteOnly = $env:configUsbStorageDenyWriteOnly,
    [string]$Allow = $env:configUsbStorageAllow,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-BooleanSetting {
    param([string]$Value, [string]$Name)
    $result = $false
    if (-not [bool]::TryParse($Value, [ref]$result)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $result
}
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($null -ne $item -and $item.PSObject.Properties[$Name]) { return $item.$Name }
    return $null
}
function Write-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop
}
try {
    $Blocked = Resolve-Setting $Blocked ''
    $DenyWriteOnly = Resolve-Setting $DenyWriteOnly ''
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $Blocked) { throw 'configUsbStorageBlocked erforderlich (true/false) / required (true/false).' }
    $desiredBlocked = ConvertTo-BooleanSetting $Blocked 'configUsbStorageBlocked'
    $manageDenyWrite = [bool]$DenyWriteOnly
    $desiredDenyWrite = $false
    if ($manageDenyWrite) { $desiredDenyWrite = ConvertTo-BooleanSetting $DenyWriteOnly 'configUsbStorageDenyWriteOnly' }
    $allowed = ConvertTo-BooleanSetting $Allow 'configUsbStorageAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $usbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
    if (-not (Test-Path -LiteralPath $usbPath)) { throw 'USBSTOR-Dienstschlüssel fehlt / USBSTOR service key missing.' }
    $desiredStart = 3
    if ($desiredBlocked) { $desiredStart = 4 }
    $readState = {
        $start = Get-RegistryValue -Path $usbPath -Name 'Start'
        $denyWrite = Get-RegistryValue -Path $policyPath -Name 'Deny_Write'
        $diffs = @()
        if (-not ($start -is [int] -and $start -eq $desiredStart)) { $diffs += ('USBSTOR Start: {0} -> {1}' -f $start, $desiredStart) }
        if ($manageDenyWrite -and $desiredDenyWrite -and -not ($denyWrite -is [int] -and $denyWrite -eq 1)) { $diffs += ('Deny_Write: {0} -> 1' -f $denyWrite) }
        if ($manageDenyWrite -and -not $desiredDenyWrite -and $null -ne $denyWrite) { $diffs += ('Deny_Write: {0} -> (removed)' -f $denyWrite) }
        [pscustomobject]@{
            Current = [ordered]@{ Blocked = ($start -is [int] -and $start -eq 4); UsbStorStart = $start; DenyWrite = $denyWrite }
            Differences = @($diffs)
        }
    }
    $state = & $readState
    $initialDifferences = @($state.Differences)
    $attempted = $false
    $changed = $false
    if ($allowed -and $state.Differences.Count -gt 0) {
        if (@($state.Differences | Where-Object { $_ -like 'USBSTOR Start:*' }).Count -and
            $PSCmdlet.ShouldProcess("$usbPath\Start", ('USB-Massenspeicher Start={0} setzen / Set USB mass storage Start={0}' -f $desiredStart))) {
            $attempted = $true
            Write-RegistryValue -Path $usbPath -Name 'Start' -Value ([int]$desiredStart) -Type 'DWord'
            $changed = $true
        }
        if (@($state.Differences | Where-Object { $_ -like 'Deny_Write:*' }).Count) {
            if ($desiredDenyWrite) {
                if ($PSCmdlet.ShouldProcess("$policyPath\Deny_Write", 'Schreibzugriff verweigern / Deny write access')) {
                    $attempted = $true
                    Write-RegistryValue -Path $policyPath -Name 'Deny_Write' -Value ([int]1) -Type 'DWord'
                    $changed = $true
                }
            }
            elseif ($PSCmdlet.ShouldProcess("$policyPath\Deny_Write", 'Schreibschutz-Richtlinie entfernen / Remove write protection policy')) {
                $attempted = $true
                Remove-ItemProperty -LiteralPath $policyPath -Name 'Deny_Write' -ErrorAction Stop
                $changed = $true
            }
        }
        if ($attempted) { $state = & $readState }
    }
    $compliant = $state.Differences.Count -eq 0
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $desired = [ordered]@{ Blocked = $desiredBlocked; UsbStorStart = $desiredStart; DenyWrite = $null }
    if ($manageDenyWrite) { $desired.DenyWrite = $desiredDenyWrite }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'UsbStorage'; Current = $state.Current; Desired = $desired
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($initialDifferences); RemainingDifferences = @($state.Differences)
        Notes = @('Eingebundene Laufwerke bleiben bis Neuanstecken/Neustart zugänglich / Mounted drives stay accessible until replug/restart')
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit $exitCode
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
