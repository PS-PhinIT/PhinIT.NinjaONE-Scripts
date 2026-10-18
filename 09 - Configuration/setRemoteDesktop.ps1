#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Remotedesktop (RDP), NLA und die RDP-Firewallregeln und setzt sie optional auf den Sollzustand.
    EN: Audits Remote Desktop (RDP), NLA and the RDP firewall rules and optionally sets them to the desired state.
.DESCRIPTION
    DE: Liest HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server fDenyTSConnections (0 = RDP aktiv, fehlend = 1)
        und ...\WinStations\RDP-Tcp UserAuthentication (1 = NLA erforderlich). NLA wird nur verwaltet, wenn RDP
        aktiviert werden soll. Die Firewallregeln der sprachunabhängigen Gruppe '@FirewallAPI.dll,-28752'
        (Remotedesktop) werden mit Get-NetFirewallRule gelesen und bei Bedarf mit Enable-/Disable-NetFirewallRule
        -Group passend zum Sollzustand geschaltet (abschaltbar mit configRdpConfigureFirewall=false); fehlen die Regeln,
        endet das Skript mit Exit 1. Definiert eine Gruppenrichtlinie unter HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\
        Terminal Services (fDenyTSConnections, UserAuthentication) einen abweichenden Wert, wird PolicyOverride gemeldet,
        nichts geändert (die Richtlinie gewinnt) und Exit 2 zurückgegeben. Ohne Opt-in (configRdpAllow=true) wird nichts
        geändert. Mit Opt-in werden nur abweichende Einstellungen innerhalb von ShouldProcess geschrieben (DWORD) und
        danach erneut gelesen. Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, PolicyOverride.
    EN: Reads HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server fDenyTSConnections (0 = RDP enabled, missing = 1)
        and ...\WinStations\RDP-Tcp UserAuthentication (1 = NLA required). NLA is only managed when RDP is to be
        enabled. The firewall rules of the locale-independent group '@FirewallAPI.dll,-28752' (Remote Desktop) are read
        with Get-NetFirewallRule and switched with Enable-/Disable-NetFirewallRule -Group to match the desired state
        (can be turned off with configRdpConfigureFirewall=false); if the rules are missing the script exits 1. If a
        Group Policy under HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services (fDenyTSConnections,
        UserAuthentication) defines a conflicting value, PolicyOverride is reported, nothing is changed (policy wins)
        and exit 2 is returned. Without opt-in (configRdpAllow=true) nothing is changed. With opt-in only differing
        settings are written (DWORD) inside ShouldProcess and read back.
        Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, PolicyOverride.
.PARAMETER Enabled
    DE: NinjaOne Checkbox/Text configRdpEnabled; erforderlich; true = RDP-Verbindungen erlauben, false = verweigern.
    EN: NinjaOne checkbox/text configRdpEnabled; required; true = allow RDP connections, false = deny.
.PARAMETER RequireNla
    DE: NinjaOne Checkbox/Text configRdpRequireNla; true/false; Standard true; nur wirksam, wenn RDP aktiviert wird.
    EN: NinjaOne checkbox/text configRdpRequireNla; true/false; default true; only used when RDP is enabled.
.PARAMETER ConfigureFirewall
    DE: NinjaOne Checkbox/Text configRdpConfigureFirewall; true/false; Standard true; Remotedesktop-Firewallregeln mitschalten.
    EN: NinjaOne checkbox/text configRdpConfigureFirewall; true/false; default true; switch the Remote Desktop firewall rules too.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configRdpAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configRdpAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setRemoteDesktop.ps1 -Enabled true
    DE: Nur Prüfung: Exit 2, wenn RDP, NLA oder die Firewallregeln abweichen.
    EN: Audit only: exit 2 if RDP, NLA or the firewall rules differ.
.EXAMPLE
    .\setRemoteDesktop.ps1 -Enabled true -Allow true -WhatIf
    DE: Simuliert Aktivierung mit NLA und Firewallregeln; nichts wird geändert (Exit 0).
    EN: Simulates enabling with NLA and firewall rules; nothing is changed (exit 0).
.EXAMPLE
    .\setRemoteDesktop.ps1 -Enabled false -Allow true -CustomField rdpReport
    DE: Deaktiviert RDP und die Firewallregeln und schreibt das JSON in rdpReport.
    EN: Disables RDP and the firewall rules and writes the JSON to rdpReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Bestehende Sitzungen bleiben bestehen. Der Dienst TermService und Benutzerrechte werden nicht verändert.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Abfrage-, Schreib-
        oder Verifikationsfehler bzw. keine RDP-Firewallregeln; 2 = Abweichung ohne Opt-in (Drift), PolicyOverride oder
        Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Existing sessions are kept. The TermService service and user rights are not changed.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, query, write or
        verification error or no RDP firewall rules; 2 = drift without opt-in, PolicyOverride or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Enabled = $env:configRdpEnabled,
    [string]$RequireNla = $env:configRdpRequireNla,
    [string]$ConfigureFirewall = $env:configRdpConfigureFirewall,
    [string]$Allow = $env:configRdpAllow,
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
    $Enabled = Resolve-Setting $Enabled ''
    $RequireNla = Resolve-Setting $RequireNla 'true'
    $ConfigureFirewall = Resolve-Setting $ConfigureFirewall 'true'
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $Enabled) { throw 'configRdpEnabled erforderlich (true/false) / required (true/false).' }
    $desiredEnabled = ConvertTo-BooleanSetting $Enabled 'configRdpEnabled'
    $nla = ConvertTo-BooleanSetting $RequireNla 'configRdpRequireNla'
    $manageFirewall = ConvertTo-BooleanSetting $ConfigureFirewall 'configRdpConfigureFirewall'
    $allowed = ConvertTo-BooleanSetting $Allow 'configRdpAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    $firewallGroup = '@FirewallAPI.dll,-28752'
    $desiredDeny = 1
    $desiredNla = $null
    if ($desiredEnabled) {
        $desiredDeny = 0
        $desiredNla = 0
        if ($nla) { $desiredNla = 1 }
    }
    $readState = {
        $deny = Get-RegistryValue -Path $tsPath -Name 'fDenyTSConnections'
        $auth = Get-RegistryValue -Path $rdpTcpPath -Name 'UserAuthentication'
        $diffs = @()
        $current = [ordered]@{ RdpEnabled = ($deny -is [int] -and $deny -eq 0); fDenyTSConnections = $deny; UserAuthentication = $auth }
        if (-not ($deny -is [int] -and $deny -eq $desiredDeny)) { $diffs += ('fDenyTSConnections: {0} -> {1}' -f $deny, $desiredDeny) }
        if ($null -ne $desiredNla -and -not ($auth -is [int] -and $auth -eq $desiredNla)) { $diffs += ('UserAuthentication: {0} -> {1}' -f $auth, $desiredNla) }
        if ($manageFirewall) {
            try { $rules = @(Get-NetFirewallRule -Group $firewallGroup -ErrorAction Stop) }
            catch { throw ('Remotedesktop-Firewallregeln nicht lesbar / Remote Desktop firewall rules unavailable: {0}' -f $_.Exception.Message) }
            if ($rules.Count -eq 0) { throw 'Keine Remotedesktop-Firewallregeln gefunden / No Remote Desktop firewall rules found.' }
            $enabledCount = @($rules | Where-Object { [string]$_.Enabled -eq 'True' }).Count
            $current['FirewallRules'] = $rules.Count
            $current['FirewallRulesEnabled'] = $enabledCount
            if ($desiredEnabled -and $enabledCount -ne $rules.Count) { $diffs += ('FirewallRulesEnabled: {0}/{1} -> {1}/{1}' -f $enabledCount, $rules.Count) }
            if (-not $desiredEnabled -and $enabledCount -ne 0) { $diffs += ('FirewallRulesEnabled: {0}/{1} -> 0/{1}' -f $enabledCount, $rules.Count) }
        }
        [pscustomobject]@{ Current = $current; Differences = @($diffs) }
    }
    $state = & $readState
    $initialDifferences = @($state.Differences)
    $policyDeny = Get-RegistryValue -Path $policyPath -Name 'fDenyTSConnections'
    $policyNla = Get-RegistryValue -Path $policyPath -Name 'UserAuthentication'
    $policyOverride = @()
    if ($null -ne $policyDeny -and [string]$policyDeny -ne [string]$desiredDeny) { $policyOverride += ('Policy fDenyTSConnections={0}' -f $policyDeny) }
    if ($null -ne $desiredNla -and $null -ne $policyNla -and [string]$policyNla -ne [string]$desiredNla) { $policyOverride += ('Policy UserAuthentication={0}' -f $policyNla) }

    $attempted = $false
    $changed = $false
    if ($allowed -and $policyOverride.Count -eq 0 -and $state.Differences.Count -gt 0) {
        if (@($state.Differences | Where-Object { $_ -like 'fDenyTSConnections:*' }).Count -and
            $PSCmdlet.ShouldProcess("$tsPath\fDenyTSConnections", ('RDP-Verbindungen setzen (fDenyTSConnections={0}) / Set RDP connections (fDenyTSConnections={0})' -f $desiredDeny))) {
            $attempted = $true
            Write-RegistryValue -Path $tsPath -Name 'fDenyTSConnections' -Value ([int]$desiredDeny) -Type 'DWord'
            $changed = $true
        }
        if (@($state.Differences | Where-Object { $_ -like 'UserAuthentication:*' }).Count -and
            $PSCmdlet.ShouldProcess("$rdpTcpPath\UserAuthentication", ('NLA setzen (UserAuthentication={0}) / Set NLA (UserAuthentication={0})' -f $desiredNla))) {
            $attempted = $true
            Write-RegistryValue -Path $rdpTcpPath -Name 'UserAuthentication' -Value ([int]$desiredNla) -Type 'DWord'
            $changed = $true
        }
        if (@($state.Differences | Where-Object { $_ -like 'FirewallRulesEnabled:*' }).Count) {
            if ($desiredEnabled) {
                if ($PSCmdlet.ShouldProcess($firewallGroup, 'Remotedesktop-Firewallregeln aktivieren / Enable Remote Desktop firewall rules')) {
                    $attempted = $true
                    Enable-NetFirewallRule -Group $firewallGroup -ErrorAction Stop
                    $changed = $true
                }
            }
            elseif ($PSCmdlet.ShouldProcess($firewallGroup, 'Remotedesktop-Firewallregeln deaktivieren / Disable Remote Desktop firewall rules')) {
                $attempted = $true
                Disable-NetFirewallRule -Group $firewallGroup -ErrorAction Stop
                $changed = $true
            }
        }
        if ($attempted) { $state = & $readState }
    }
    $compliant = $state.Differences.Count -eq 0 -and $policyOverride.Count -eq 0
    $verificationFailed = $attempted -and $state.Differences.Count -gt 0
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif ($policyOverride.Count -gt 0) { $exitCode = 2 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $desired = [ordered]@{ RdpEnabled = $desiredEnabled; fDenyTSConnections = $desiredDeny; UserAuthentication = $desiredNla; FirewallManaged = $manageFirewall }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'RemoteDesktop'; Current = $state.Current; Desired = $desired
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; PolicyOverride = @($policyOverride)
        Differences = @($initialDifferences); RemainingDifferences = @($state.Differences)
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
