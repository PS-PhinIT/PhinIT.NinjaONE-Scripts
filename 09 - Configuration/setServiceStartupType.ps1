#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Starttyp und Zustand eines Windows-Dienstes und setzt sie optional (geschützte Dienste ausgenommen).
    EN: Audits the startup type and state of a Windows service and optionally sets them (protected services excluded).
.DESCRIPTION
    DE: Liest den Dienst mit Get-CimInstance Win32_Service (StartMode Auto/Manual/Disabled, State) und den verzögerten
        Start aus HKLM:\SYSTEM\CurrentControlSet\Services\<Name> DelayedAutostart. StartupType (Automatic,
        AutomaticDelayedStart, Manual, Disabled) wird mit Set-Service -StartupType gesetzt; für Automatic und
        AutomaticDelayedStart wird zusätzlich DelayedAutostart als DWORD 0 bzw. 1 geschrieben (wirksam beim nächsten
        Systemstart). Action Start/Stop/Restart nutzt Start-/Stop-/Restart-Service (ohne -Force, abhängige Dienste werden
        nicht mitgestoppt) und wartet bis zu 60 Sekunden auf den Zielzustand. Restart wird bei jeder Ausführung mit
        Opt-in durchgeführt und gilt im Prüfmodus als ausstehend (Exit 2). Geschützte Dienste dürfen nie deaktiviert,
        gestoppt oder neu gestartet werden (Exit 1, auch ohne Opt-in): RpcSs, RpcEptMapper, DcomLaunch, LSM, SamSs,
        Schedule, EventLog, Winmgmt, PlugPlay, Power, ProfSvc, BFE, mpssvc, WinDefend, CryptSvc, Dhcp, Dnscache, NlaSvc,
        nsi, LanmanWorkstation, gpsvc sowie alle Dienste mit Präfix NinjaRMMAgent. Ohne Opt-in (configServiceAllow=true)
        wird nichts geändert. Jede Änderung läuft über ShouldProcess und wird danach erneut gelesen.
        Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
    EN: Reads the service with Get-CimInstance Win32_Service (StartMode Auto/Manual/Disabled, State) and the delayed
        start from HKLM:\SYSTEM\CurrentControlSet\Services\<name> DelayedAutostart. StartupType (Automatic,
        AutomaticDelayedStart, Manual, Disabled) is set with Set-Service -StartupType; for Automatic and
        AutomaticDelayedStart DelayedAutostart is also written as DWORD 0 or 1 (effective at the next boot). Action
        Start/Stop/Restart uses Start-/Stop-/Restart-Service (without -Force, dependent services are not stopped) and
        waits up to 60 seconds for the target state. Restart is performed on every run with opt-in and counts as
        pending in audit mode (exit 2). Protected services may never be disabled, stopped or restarted (exit 1, even
        without opt-in): RpcSs, RpcEptMapper, DcomLaunch, LSM, SamSs, Schedule, EventLog, Winmgmt, PlugPlay, Power,
        ProfSvc, BFE, mpssvc, WinDefend, CryptSvc, Dhcp, Dnscache, NlaSvc, nsi, LanmanWorkstation, gpsvc and every
        service with the prefix NinjaRMMAgent. Without opt-in (configServiceAllow=true) nothing is changed. Every change
        runs inside ShouldProcess and is read back. Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
.PARAMETER ServiceName
    DE: NinjaOne Text configServiceName; erforderlich; interner Dienstname (1-80 Zeichen A-Z, 0-9, _ . -); muss existieren.
    EN: NinjaOne text configServiceName; required; internal service name (1-80 characters A-Z, 0-9, _ . -); must exist.
.PARAMETER StartupType
    DE: NinjaOne Dropdown/Text configServiceStartupType: Automatic, AutomaticDelayedStart, Manual, Disabled; Standard leer (nicht verwaltet).
    EN: NinjaOne drop-down/text configServiceStartupType: Automatic, AutomaticDelayedStart, Manual, Disabled; default empty (not managed).
.PARAMETER Action
    DE: NinjaOne Dropdown/Text configServiceAction: None, Start, Stop, Restart; Standard None.
    EN: NinjaOne drop-down/text configServiceAction: None, Start, Stop, Restart; default None.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configServiceAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configServiceAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setServiceStartupType.ps1 -ServiceName Spooler -StartupType Disabled -Action Stop
    DE: Nur Prüfung: Exit 2, wenn die Druckwarteschlange nicht deaktiviert und gestoppt ist.
    EN: Audit only: exit 2 if the print spooler is not disabled and stopped.
.EXAMPLE
    .\setServiceStartupType.ps1 -ServiceName Spooler -StartupType Disabled -Action Stop -Allow true -WhatIf
    DE: Simuliert Deaktivieren und Stoppen; nichts wird geändert (Exit 0).
    EN: Simulates disabling and stopping; nothing is changed (exit 0).
.EXAMPLE
    .\setServiceStartupType.ps1 -ServiceName wuauserv -StartupType AutomaticDelayedStart -Action Start -Allow true -CustomField serviceReport
    DE: Setzt verzögerten automatischen Start, startet den Dienst und schreibt das JSON in serviceReport.
    EN: Sets delayed automatic start, starts the service and writes the JSON to serviceReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        StartupType oder Action (nicht None) ist erforderlich. Disabled mit Start/Restart ist widersprüchlich (Exit 1).
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabefehler, geschützter Dienst,
        Dienst fehlt, Änderungs-, Zeitüberschreitungs- oder Verifikationsfehler; 2 = Abweichung ohne Opt-in (Drift, inkl.
        ausstehendem Restart) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        StartupType or Action (not None) is required. Disabled with Start/Restart is contradictory (exit 1).
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input error, protected service,
        service missing, change, timeout or verification error; 2 = drift without opt-in (including pending restart)
        or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ServiceName = $env:configServiceName,
    [string]$StartupType = $env:configServiceStartupType,
    [string]$Action = $env:configServiceAction,
    [string]$Allow = $env:configServiceAllow,
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
function Wait-ServiceStatus {
    param([string]$Name, [string]$Status)
    (Get-Service -Name $Name -ErrorAction Stop).WaitForStatus($Status, [TimeSpan]::FromSeconds(60))
}
try {
    $ServiceName = Resolve-Setting $ServiceName ''
    $StartupType = Resolve-Setting $StartupType ''
    $Action = Resolve-Setting $Action 'None'
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if ($ServiceName -notmatch '^[A-Za-z0-9_.\-]{1,80}$') { throw 'configServiceName: 1-80 Zeichen A-Z, 0-9, _ . - erforderlich / required.' }
    if ($StartupType) {
        $match = @('Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled') | Where-Object { $_ -eq $StartupType } | Select-Object -First 1
        if (-not $match) { throw 'configServiceStartupType: Automatic, AutomaticDelayedStart, Manual oder/or Disabled.' }
        $StartupType = $match
    }
    $actionMatch = @('None', 'Start', 'Stop', 'Restart') | Where-Object { $_ -eq $Action } | Select-Object -First 1
    if (-not $actionMatch) { throw 'configServiceAction: None, Start, Stop oder/or Restart.' }
    $Action = $actionMatch
    $allowed = ConvertTo-BooleanSetting $Allow 'configServiceAllow'
    if (-not $StartupType -and $Action -eq 'None') { throw 'configServiceStartupType oder/or configServiceAction erforderlich / required.' }
    if ($StartupType -eq 'Disabled' -and $Action -in @('Start', 'Restart')) { throw 'Disabled mit Start/Restart ist widersprüchlich / Disabled with Start/Restart is contradictory.' }
    $protectedServices = @('RpcSs', 'RpcEptMapper', 'DcomLaunch', 'LSM', 'SamSs', 'Schedule', 'EventLog', 'Winmgmt', 'PlugPlay', 'Power',
        'ProfSvc', 'BFE', 'mpssvc', 'WinDefend', 'CryptSvc', 'Dhcp', 'Dnscache', 'NlaSvc', 'nsi', 'LanmanWorkstation', 'gpsvc')
    $isProtected = ($protectedServices -contains $ServiceName) -or ($ServiceName -like 'NinjaRMMAgent*')
    if ($isProtected -and ($StartupType -eq 'Disabled' -or $Action -in @('Stop', 'Restart'))) {
        throw ('Geschützter Dienst darf nicht deaktiviert/gestoppt werden / Protected service must not be disabled/stopped: {0}' -f $ServiceName)
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $restartDone = $false
    $readState = {
        $services = @(Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $ServiceName) -ErrorAction Stop)
        if ($services.Count -eq 0) { throw ('Dienst nicht gefunden / Service not found: {0}' -f $ServiceName) }
        $service = $services[0]
        $mode = [string]$service.StartMode
        $delayed = Get-RegistryValue -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $service.Name) -Name 'DelayedAutostart'
        $type = $mode
        if ($mode -eq 'Auto') {
            $type = 'Automatic'
            if ($delayed -is [int] -and $delayed -eq 1) { $type = 'AutomaticDelayedStart' }
        }
        elseif ($mode -in @('Manual', 'Disabled')) { $type = $mode }
        $state = [string]$service.State
        $diffs = @()
        if ($StartupType -and $type -ne $StartupType) { $diffs += ('StartupType: {0} -> {1}' -f $type, $StartupType) }
        if ($Action -eq 'Start' -and $state -ne 'Running') { $diffs += ('State: {0} -> Running' -f $state) }
        if ($Action -eq 'Stop' -and $state -ne 'Stopped') { $diffs += ('State: {0} -> Stopped' -f $state) }
        if ($Action -eq 'Restart' -and -not ($restartDone -and $state -eq 'Running')) { $diffs += ('Restart: {0} -> Running' -f $state) }
        [pscustomobject]@{
            Name = [string]$service.Name; DisplayName = [string]$service.DisplayName
            Current = [ordered]@{ StartupType = $type; State = $state }; Differences = @($diffs)
        }
    }
    $info = & $readState
    $ServiceName = $info.Name
    $initialDifferences = @($info.Differences)
    $attempted = $false
    $changed = $false
    if ($allowed -and $info.Differences.Count -gt 0) {
        if (@($info.Differences | Where-Object { $_ -like 'StartupType:*' }).Count -and
            $PSCmdlet.ShouldProcess($ServiceName, ('Starttyp setzen auf {0} / Set startup type to {0}' -f $StartupType))) {
            $attempted = $true
            $baseType = $StartupType
            if ($StartupType -eq 'AutomaticDelayedStart') { $baseType = 'Automatic' }
            Set-Service -Name $ServiceName -StartupType $baseType -ErrorAction Stop
            if ($baseType -eq 'Automatic') {
                $delayedValue = 0
                if ($StartupType -eq 'AutomaticDelayedStart') { $delayedValue = 1 }
                Write-RegistryValue -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $ServiceName) -Name 'DelayedAutostart' -Value ([int]$delayedValue) -Type 'DWord'
            }
            $changed = $true
        }
        if ($Action -eq 'Start' -and @($info.Differences | Where-Object { $_ -like 'State:*' }).Count -and
            $PSCmdlet.ShouldProcess($ServiceName, 'Dienst starten / Start service')) {
            $attempted = $true
            Start-Service -Name $ServiceName -ErrorAction Stop
            Wait-ServiceStatus -Name $ServiceName -Status 'Running'
            $changed = $true
        }
        if ($Action -eq 'Stop' -and @($info.Differences | Where-Object { $_ -like 'State:*' }).Count -and
            $PSCmdlet.ShouldProcess($ServiceName, 'Dienst stoppen / Stop service')) {
            $attempted = $true
            Stop-Service -Name $ServiceName -ErrorAction Stop
            Wait-ServiceStatus -Name $ServiceName -Status 'Stopped'
            $changed = $true
        }
        if ($Action -eq 'Restart' -and $PSCmdlet.ShouldProcess($ServiceName, 'Dienst neu starten / Restart service')) {
            $attempted = $true
            Restart-Service -Name $ServiceName -ErrorAction Stop
            Wait-ServiceStatus -Name $ServiceName -Status 'Running'
            $restartDone = $true
            $changed = $true
        }
        if ($attempted) { $info = & $readState }
    }
    $compliant = $info.Differences.Count -eq 0
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'Service'; ServiceName = $ServiceName; DisplayName = $info.DisplayName; Protected = $isProtected
        Current = $info.Current; Desired = [ordered]@{ StartupType = $(if ($StartupType) { $StartupType } else { $null }); Action = $Action }
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($initialDifferences); RemainingDifferences = @($info.Differences)
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
