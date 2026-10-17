#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft den aktiven Energiesparplan und optionale Bildschirm-/Standby-Zeitlimits und setzt sie optional.
    EN: Audits the active power plan and optional monitor/standby timeouts and optionally sets them.
.DESCRIPTION
    DE: Liest den aktiven Plan mit 'powercfg /getactivescheme' und die vorhandenen Pläne mit 'powercfg /list'.
        PowerPlan akzeptiert Balanced (381b4222-f694-41f0-9685-ff5bb260df2e), HighPerformance
        (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c), PowerSaver (a1841308-3541-4fab-bc81-f71556f20b4a),
        UltimatePerformance (e9a42b02-d5df-448d-aa00-03f14749eb61) oder eine GUID. Ist UltimatePerformance nicht
        vorhanden, wird nur mit Opt-in 'powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        878f208b-dd80-47bd-ae62-235365a04fed' ausgeführt (feste Ziel-GUID, damit Wiederholungen keine weiteren Kopien
        anlegen) und dieser Plan aktiviert. Ein nicht vorhandener anderer Plan ist ein Fehler (Exit 1).
        Zeitlimits (Minuten 0-1440, 0 = nie) werden sprachunabhängig über
        'powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE' bzw. 'SUB_SLEEP STANDBYIDLE' gelesen: Es werden die
        LETZTEN ZWEI Hexwerte 0x######## der Ausgabe verwendet, in dieser Reihenfolge Netzbetrieb (AC) und
        Akkubetrieb (DC); die Werte sind Sekunden. Geändert wird mit 'powercfg /setactive <GUID>' und
        'powercfg /change monitor-timeout-ac|monitor-timeout-dc|standby-timeout-ac|standby-timeout-dc <Minuten>'
        (wirkt auf den aktiven Plan, daher wird zuerst der Plan aktiviert). Leere Einstellungen werden nicht verwaltet.
        Ohne Opt-in (configPowerAllow=true) wird nichts geändert. Jede Änderung läuft über ShouldProcess; danach wird
        erneut gelesen und verglichen. Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
    EN: Reads the active plan with 'powercfg /getactivescheme' and the available plans with 'powercfg /list'.
        PowerPlan accepts Balanced (381b4222-f694-41f0-9685-ff5bb260df2e), HighPerformance
        (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c), PowerSaver (a1841308-3541-4fab-bc81-f71556f20b4a),
        UltimatePerformance (e9a42b02-d5df-448d-aa00-03f14749eb61) or a GUID. If UltimatePerformance is not present,
        'powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 878f208b-dd80-47bd-ae62-235365a04fed' is run
        only with opt-in (fixed destination GUID so repeated runs create no further copies) and that plan is
        activated. Any other missing plan is an error (exit 1). Timeouts (minutes 0-1440, 0 = never) are read
        locale-independently via 'powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE' or 'SUB_SLEEP STANDBYIDLE': the
        LAST TWO hex values 0x######## of the output are used, in this order AC (plugged in) and DC (battery); values
        are seconds. Changes use 'powercfg /setactive <GUID>' and 'powercfg /change
        monitor-timeout-ac|monitor-timeout-dc|standby-timeout-ac|standby-timeout-dc <minutes>' (applies to the active
        plan, so the plan is activated first). Empty settings are not managed. Without opt-in (configPowerAllow=true)
        nothing is changed. Every change runs inside ShouldProcess and is read back and compared. Report: Current,
        Desired, Compliant, Changed, Allowed, WhatIf, Differences.
.PARAMETER PowerPlan
    DE: NinjaOne Dropdown/Text configPowerPlan: Balanced, HighPerformance, PowerSaver, UltimatePerformance oder GUID; Standard leer (nicht verwaltet).
    EN: NinjaOne drop-down/text configPowerPlan: Balanced, HighPerformance, PowerSaver, UltimatePerformance or GUID; default empty (not managed).
.PARAMETER MonitorTimeoutAcMinutes
    DE: NinjaOne Text configPowerMonitorTimeoutAcMinutes; Bildschirm aus im Netzbetrieb, 0-1440 Minuten (0 = nie); Standard leer.
    EN: NinjaOne text configPowerMonitorTimeoutAcMinutes; monitor off on AC, 0-1440 minutes (0 = never); default empty.
.PARAMETER MonitorTimeoutDcMinutes
    DE: NinjaOne Text configPowerMonitorTimeoutDcMinutes; Bildschirm aus im Akkubetrieb, 0-1440 Minuten (0 = nie); Standard leer.
    EN: NinjaOne text configPowerMonitorTimeoutDcMinutes; monitor off on battery, 0-1440 minutes (0 = never); default empty.
.PARAMETER StandbyTimeoutAcMinutes
    DE: NinjaOne Text configPowerStandbyTimeoutAcMinutes; Energiesparmodus im Netzbetrieb, 0-1440 Minuten (0 = nie); Standard leer.
    EN: NinjaOne text configPowerStandbyTimeoutAcMinutes; sleep on AC, 0-1440 minutes (0 = never); default empty.
.PARAMETER StandbyTimeoutDcMinutes
    DE: NinjaOne Text configPowerStandbyTimeoutDcMinutes; Energiesparmodus im Akkubetrieb, 0-1440 Minuten (0 = nie); Standard leer.
    EN: NinjaOne text configPowerStandbyTimeoutDcMinutes; sleep on battery, 0-1440 minutes (0 = never); default empty.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configPowerAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configPowerAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setPowerPlan.ps1 -PowerPlan HighPerformance -StandbyTimeoutAcMinutes 0
    DE: Nur Prüfung: Exit 2, wenn ein anderer Plan aktiv ist oder Standby im Netzbetrieb nicht 'nie' ist.
    EN: Audit only: exit 2 if another plan is active or sleep on AC is not 'never'.
.EXAMPLE
    .\setPowerPlan.ps1 -PowerPlan Balanced -MonitorTimeoutAcMinutes 15 -Allow true -WhatIf
    DE: Simuliert Aktivierung und Zeitlimit; nichts wird geändert (Exit 0).
    EN: Simulates activation and timeout; nothing is changed (exit 0).
.EXAMPLE
    .\setPowerPlan.ps1 -PowerPlan UltimatePerformance -Allow true -CustomField powerPlanReport
    DE: Legt bei Bedarf den Plan Höchstleistung an, aktiviert ihn und schreibt das JSON in powerPlanReport.
    EN: Creates the Ultimate Performance plan if needed, activates it and writes the JSON to powerPlanReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Mindestens eine Einstellung ist erforderlich. Gruppenrichtlinien für Energieeinstellungen können Werte überschreiben.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, powercfg- oder
        Verifikationsfehler (z. B. Plan fehlt); 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        At least one setting is required. Group Policy power settings may override values.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, powercfg or verification
        error (e.g. plan missing); 2 = drift without opt-in or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$PowerPlan = $env:configPowerPlan,
    [string]$MonitorTimeoutAcMinutes = $env:configPowerMonitorTimeoutAcMinutes,
    [string]$MonitorTimeoutDcMinutes = $env:configPowerMonitorTimeoutDcMinutes,
    [string]$StandbyTimeoutAcMinutes = $env:configPowerStandbyTimeoutAcMinutes,
    [string]$StandbyTimeoutDcMinutes = $env:configPowerStandbyTimeoutDcMinutes,
    [string]$Allow = $env:configPowerAllow,
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
function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $global:LASTEXITCODE = 0
    $output = @(powercfg @Arguments | ForEach-Object { [string]$_ })
    if ($global:LASTEXITCODE -ne 0) { throw ('powercfg {0}: Exitcode / exit code {1}' -f ($Arguments -join ' '), $global:LASTEXITCODE) }
    return $output
}
try {
    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $planGuids = [ordered]@{
        Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'; HighPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        PowerSaver = 'a1841308-3541-4fab-bc81-f71556f20b4a'; UltimatePerformance = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    }
    $ultimateCopyGuid = '878f208b-dd80-47bd-ae62-235365a04fed'
    $PowerPlan = Resolve-Setting $PowerPlan ''
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $allowed = ConvertTo-BooleanSetting $Allow 'configPowerAllow'
    $planName = ''
    $planGuid = ''
    if ($PowerPlan) {
        $planName = @($planGuids.Keys) | Where-Object { $_ -eq $PowerPlan } | Select-Object -First 1
        if ($planName) { $planGuid = $planGuids[$planName] }
        elseif ($PowerPlan -match ('^\{?(' + $guidPattern + ')\}?$')) { $planGuid = $Matches[1].ToLowerInvariant(); $planName = 'Custom' }
        else { throw 'configPowerPlan: Balanced, HighPerformance, PowerSaver, UltimatePerformance oder/or GUID.' }
    }
    $timeouts = @(
        [pscustomobject]@{ Name = 'MonitorTimeoutAcMinutes'; Variable = 'configPowerMonitorTimeoutAcMinutes'; Input = $MonitorTimeoutAcMinutes; Group = 'SUB_VIDEO'; Setting = 'VIDEOIDLE'; Index = 0; Change = 'monitor-timeout-ac'; Minutes = $null }
        [pscustomobject]@{ Name = 'MonitorTimeoutDcMinutes'; Variable = 'configPowerMonitorTimeoutDcMinutes'; Input = $MonitorTimeoutDcMinutes; Group = 'SUB_VIDEO'; Setting = 'VIDEOIDLE'; Index = 1; Change = 'monitor-timeout-dc'; Minutes = $null }
        [pscustomobject]@{ Name = 'StandbyTimeoutAcMinutes'; Variable = 'configPowerStandbyTimeoutAcMinutes'; Input = $StandbyTimeoutAcMinutes; Group = 'SUB_SLEEP'; Setting = 'STANDBYIDLE'; Index = 0; Change = 'standby-timeout-ac'; Minutes = $null }
        [pscustomobject]@{ Name = 'StandbyTimeoutDcMinutes'; Variable = 'configPowerStandbyTimeoutDcMinutes'; Input = $StandbyTimeoutDcMinutes; Group = 'SUB_SLEEP'; Setting = 'STANDBYIDLE'; Index = 1; Change = 'standby-timeout-dc'; Minutes = $null }
    )
    foreach ($timeout in $timeouts) {
        $text = Resolve-Setting $timeout.Input ''
        if (-not $text) { continue }
        $minutes = 0
        if ($text -notmatch '^\d{1,4}$' -or -not [int]::TryParse($text, [ref]$minutes) -or $minutes -gt 1440) {
            throw ('{0}: 0-1440 erforderlich / required.' -f $timeout.Variable)
        }
        $timeout.Minutes = $minutes
    }
    $managedTimeouts = @($timeouts | Where-Object { $null -ne $_.Minutes })
    if (-not $planGuid -and $managedTimeouts.Count -eq 0) { throw 'Mindestens eine Einstellung erforderlich / At least one setting required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $readState = {
        $activeText = (Invoke-PowerCfg -Arguments @('/getactivescheme')) -join "`n"
        if ($activeText -notmatch $guidPattern) { throw 'Aktiver Plan nicht lesbar / Active plan unreadable.' }
        $active = $Matches[0].ToLowerInvariant()
        $listText = (Invoke-PowerCfg -Arguments @('/list')) -join "`n"
        $schemes = @([regex]::Matches($listText, $guidPattern) | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
        $values = [ordered]@{}
        foreach ($group in @($managedTimeouts | Select-Object -ExpandProperty Setting -Unique)) {
            $sub = @($managedTimeouts | Where-Object { $_.Setting -eq $group })[0].Group
            $queryText = (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', $sub, $group)) -join "`n"
            # DE: Letzte zwei Hexwerte = AC, DC (sprachunabhängig). EN: Last two hex values = AC, DC (locale-independent).
            $hex = @([regex]::Matches($queryText, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
            if ($hex.Count -lt 2) { throw ('powercfg /query {0}: AC/DC-Werte nicht lesbar / AC/DC values unreadable.' -f $group) }
            $values[$group] = @([Convert]::ToInt64($hex[$hex.Count - 2].Substring(2), 16), [Convert]::ToInt64($hex[$hex.Count - 1].Substring(2), 16))
        }
        $activeName = 'Custom'
        foreach ($key in $planGuids.Keys) { if ($planGuids[$key] -eq $active) { $activeName = $key } }
        if ($active -eq $ultimateCopyGuid) { $activeName = 'UltimatePerformance' }
        $current = [ordered]@{ PowerPlan = $activeName; PowerPlanGuid = $active }
        $diffs = @()
        $targetGuid = $planGuid
        $needsDuplicate = $false
        if ($planGuid) {
            if ($planName -eq 'UltimatePerformance' -and $schemes -notcontains $planGuid) {
                $targetGuid = $ultimateCopyGuid
                if ($schemes -notcontains $ultimateCopyGuid) { $needsDuplicate = $true }
            }
            elseif ($schemes -notcontains $planGuid) { throw ('Energiesparplan nicht vorhanden / Power plan not present: {0}' -f $planGuid) }
            if ($active -ne $targetGuid -and -not ($planName -eq 'UltimatePerformance' -and $active -eq $ultimateCopyGuid)) {
                $diffs += ('PowerPlan: {0} -> {1} ({2})' -f $active, $targetGuid, $planName)
            }
        }
        foreach ($timeout in $managedTimeouts) {
            $seconds = $values[$timeout.Setting][$timeout.Index]
            $current[$timeout.Name] = [Math]::Round($seconds / 60, 2)
            if ($seconds -ne ([long]$timeout.Minutes * 60)) { $diffs += ('{0}: {1} -> {2}' -f $timeout.Name, $current[$timeout.Name], $timeout.Minutes) }
        }
        [pscustomobject]@{ Current = $current; Schemes = $schemes; Active = $active; TargetGuid = $targetGuid; NeedsDuplicate = $needsDuplicate; Differences = @($diffs) }
    }

    $state = & $readState
    $initialDifferences = @($state.Differences)
    $attempted = $false
    $changed = $false
    if ($allowed -and $state.Differences.Count -gt 0) {
        $planReady = $true
        if ($planGuid -and $state.Differences[0] -like 'PowerPlan:*') {
            if ($state.NeedsDuplicate) {
                $planReady = $false
                if ($PSCmdlet.ShouldProcess($ultimateCopyGuid, 'Energiesparplan Ultimative Leistung anlegen / Create Ultimate Performance power plan')) {
                    $attempted = $true
                    $null = Invoke-PowerCfg -Arguments @('/duplicatescheme', $planGuids['UltimatePerformance'], $ultimateCopyGuid)
                    $changed = $true
                    $planReady = $true
                }
            }
            if ($planReady -and $PSCmdlet.ShouldProcess($state.TargetGuid, ('Energiesparplan aktivieren ({0}) / Activate power plan ({0})' -f $planName))) {
                $attempted = $true
                $null = Invoke-PowerCfg -Arguments @('/setactive', $state.TargetGuid)
                $changed = $true
                # DE: Zeitlimits gelten für den aktiven Plan, daher neu lesen. EN: Timeouts apply to the active plan, so re-read.
                $state = & $readState
            }
        }
        foreach ($timeout in $managedTimeouts) {
            if (-not @($state.Differences | Where-Object { $_ -like ($timeout.Name + ':*') }).Count) { continue }
            if ($PSCmdlet.ShouldProcess($timeout.Change, ('Zeitlimit auf {0} Minuten setzen / Set timeout to {0} minutes' -f $timeout.Minutes))) {
                $attempted = $true
                $null = Invoke-PowerCfg -Arguments @('/change', $timeout.Change, [string]$timeout.Minutes)
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

    $desired = [ordered]@{ PowerPlan = $null; PowerPlanGuid = $null }
    if ($planGuid) { $desired.PowerPlan = $planName; $desired.PowerPlanGuid = $state.TargetGuid }
    foreach ($timeout in $managedTimeouts) { $desired[$timeout.Name] = $timeout.Minutes }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'PowerPlan'; Current = $state.Current; Desired = $desired
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($initialDifferences); RemainingDifferences = @($state.Differences)
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
