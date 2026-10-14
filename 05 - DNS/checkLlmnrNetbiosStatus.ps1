#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Härtungsprüfung für LLMNR, NetBIOS über TCP/IP und mDNS.
    EN: Hardening check for LLMNR, NetBIOS over TCP/IP and mDNS.
.DESCRIPTION
    DE: Liest die LLMNR-Richtlinie EnableMulticast (HKLM\SOFTWARE\Policies\Microsoft\
        Windows NT\DNSClient; 0 = deaktiviert, fehlend/1 = aktiv), NetBIOS über TCP/IP je
        IP-aktiviertem Adapter (Win32_NetworkAdapterConfiguration IPEnabled,
        TcpipNetbiosOptions 0 = Standard/DHCP, 1 = aktiv, 2 = deaktiviert; Standard gilt
        als aktiv) und mDNS (HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters
        EnableMDNS; 0 = deaktiviert, fehlend = aktiv). Maximal 50 Adapter, 4000 Zeichen.
        Nur lesend, keine Änderungen.
    EN: Reads the LLMNR policy EnableMulticast (HKLM\SOFTWARE\Policies\Microsoft\
        Windows NT\DNSClient; 0 = disabled, missing/1 = enabled), NetBIOS over TCP/IP per
        IP-enabled adapter (Win32_NetworkAdapterConfiguration IPEnabled,
        TcpipNetbiosOptions 0 = default/DHCP, 1 = enabled, 2 = disabled; default counts as
        enabled) and mDNS (HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters
        EnableMDNS; 0 = disabled, missing = enabled). At most 50 adapters, 4000
        characters. Read-only, no changes.
.PARAMETER RequireMdnsDisabled
    DE: NinjaOne Checkbox/Text dnsRequireMdnsDisabled: true/false/1/0; Standard false (mDNS nur melden).
    EN: NinjaOne checkbox/text dnsRequireMdnsDisabled: true/false/1/0; default false (report mDNS only).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkLlmnrNetbiosStatus.ps1
    DE: Warnt (Exit 2), wenn LLMNR oder NetBIOS auf einem Adapter aktiv ist.
    EN: Warns (exit 2) if LLMNR or NetBIOS is enabled on any adapter.
.EXAMPLE
    .\checkLlmnrNetbiosStatus.ps1 -RequireMdnsDisabled true -CustomField dnsLegacyResolution
    DE: Zusätzlich mDNS als Befund werten; JSON in dnsLegacyResolution.
    EN: Additionally treat mDNS as a finding; JSON to dnsLegacyResolution.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = gehärtet, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = LLMNR aktiv,
        NetBIOS auf mindestens einem Adapter aktiv/Standard oder (bei
        dnsRequireMdnsDisabled=true) mDNS aktiv. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = hardened, 1 = input, query or write error, 2 = LLMNR enabled, NetBIOS
        enabled/default on at least one adapter or (with dnsRequireMdnsDisabled=true)
        mDNS enabled. Read-only.
#>
[CmdletBinding()]
param(
    [string]$RequireMdnsDisabled = $env:dnsRequireMdnsDisabled,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-RegistryDword {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $value = (Get-ItemProperty -LiteralPath $Path -ErrorAction Stop).$Name
    if ($null -eq $value) { return $null }
    return [int]$value
}
try {
    $RequireMdnsDisabled = ([string]$RequireMdnsDisabled).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($RequireMdnsDisabled -ieq 'null') { $RequireMdnsDisabled = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RequireMdnsDisabled) { $RequireMdnsDisabled = 'false' }
    if ($RequireMdnsDisabled -notin @('true', 'false', '1', '0')) { throw 'dnsRequireMdnsDisabled: true/false/1/0.' }
    $mdnsRequired = $RequireMdnsDisabled -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $llmnrValue = Get-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast'
    $llmnrEnabled = $llmnrValue -ne 0
    $mdnsValue = Get-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableMDNS'
    $mdnsEnabled = $mdnsValue -ne 0
    $configs = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop | Sort-Object Index)
    $adapters = @(foreach ($config in $configs) {
        $option = $null
        if ($null -ne $config.TcpipNetbiosOptions) { $option = [int]$config.TcpipNetbiosOptions }
        $state = 'Unknown'
        if ($option -eq 0) { $state = 'DefaultDhcp' }
        elseif ($option -eq 1) { $state = 'Enabled' }
        elseif ($option -eq 2) { $state = 'Disabled' }
        $description = [string]$config.Description
        if ($description.Length -gt 80) { $description = $description.Substring(0, 80) }
        [pscustomobject]@{ Index = $config.Index; InterfaceIndex = $config.InterfaceIndex; Description = $description; TcpipNetbiosOptions = $option; NetbiosState = $state }
    })
    $netbiosAdapters = @($adapters | Where-Object { $_.NetbiosState -ne 'Disabled' }).Count
    $records = @($adapters | Select-Object -First 50)
    do {
        $report = [ordered]@{
            LlmnrPolicyEnableMulticast = $llmnrValue; LlmnrEnabled = $llmnrEnabled
            MdnsEnableMDNS = $mdnsValue; MdnsEnabled = $mdnsEnabled; MdnsDisabledRequired = $mdnsRequired
            TotalAdapters = $configs.Count; NetbiosEnabledAdapters = $netbiosAdapters
            ReportedAdapters = $records.Count; Truncated = ($records.Count -lt $configs.Count); Adapters = $records
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($llmnrEnabled -or $netbiosAdapters -gt 0 -or ($mdnsRequired -and $mdnsEnabled)) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
