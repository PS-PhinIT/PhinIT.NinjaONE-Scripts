#Requires -Version 5.1

<#
.SYNOPSIS
DE: Meldet die SCHANNEL-Protokollkonfiguration (SSL 2.0 bis TLS 1.3, Server/Client).
EN: Reports the SCHANNEL protocol configuration (SSL 2.0 to TLS 1.3, server/client).
.DESCRIPTION
DE: Liest HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\<Protokoll>\
    Server|Client mit den Werten Enabled und DisabledByDefault. Configuration: Explicit (Enabled
    gesetzt) oder NotConfigured (Betriebssystem-Standard). EffectiveState: Enabled (Enabled <> 0
    und DisabledByDefault <> 1), EnabledButDisabledByDefault, Disabled (Enabled = 0) oder OSDefault.
    Nur lesend; der OS-Standard hängt von der Windows-Version ab und wird nicht geraten.
EN: Reads HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\<protocol>\
    Server|Client with the values Enabled and DisabledByDefault. Configuration: Explicit (Enabled
    set) or NotConfigured (OS default). EffectiveState: Enabled (Enabled <> 0 and
    DisabledByDefault <> 1), EnabledButDisabledByDefault, Disabled (Enabled = 0) or OSDefault.
    Read-only; the OS default depends on the Windows version and is not guessed.
.PARAMETER StrictMode
DE: NinjaOne Checkbox/Text certSchannelStrictMode; true/false; Standard false. true = Warnung,
    solange SSL 2.0/3.0 und TLS 1.0/1.1 nicht ausdrücklich deaktiviert sind (Enabled = 0).
EN: NinjaOne checkbox/text certSchannelStrictMode; true/false; default false. true = warning
    unless SSL 2.0/3.0 and TLS 1.0/1.1 are explicitly disabled (Enabled = 0).
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkSchannelProtocols.ps1
DE: Warnt nur bei ausdrücklich aktivierten Altprotokollen oder deaktiviertem TLS 1.2.
EN: Warns only about explicitly enabled legacy protocols or disabled TLS 1.2.
.EXAMPLE
.\checkSchannelProtocols.ps1 -StrictMode true -CustomField schannelReport
DE: Zusätzlich Warnung, wenn Altprotokolle nicht ausdrücklich deaktiviert sind; JSON in schannelReport.
EN: Additionally warns if legacy protocols are not explicitly disabled; JSON to schannelReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Änderungen wirken erst nach Neustart; das Skript
    meldet nur die Registry. Exit 0 = OK, 1 = Eingabe-, Registry- oder Schreibfehler,
    2 = SSL 2.0/3.0 oder TLS 1.0/1.1 ausdrücklich aktiviert (Enabled <> 0), TLS 1.2 ausdrücklich
    deaktiviert (Enabled = 0 oder DisabledByDefault = 1) oder (StrictMode) Altprotokoll nicht ausdrücklich deaktiviert.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Changes apply only after a reboot; the script
    reports the registry only. Exit 0 = OK, 1 = input, registry or write error,
    2 = SSL 2.0/3.0 or TLS 1.0/1.1 explicitly enabled (Enabled <> 0), TLS 1.2 explicitly
    disabled (Enabled = 0 or DisabledByDefault = 1) or (StrictMode) legacy protocol not explicitly disabled.
#>
[CmdletBinding()]
param(
    [string]$StrictMode = $env:certSchannelStrictMode,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryKeyValue {
    param([string]$Path)
    try { Get-ItemProperty -Path $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { $null }
}
try {
    $StrictMode = ([string]$StrictMode).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $StrictMode -or $StrictMode -ieq 'null') { $StrictMode = 'false' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($StrictMode -notin @('true', 'false')) { throw 'certSchannelStrictMode: true/false erforderlich / required.' }
    $strict = $StrictMode -ieq 'true'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }

    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $legacy = @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')
    $findings = New-Object System.Collections.Generic.List[string]
    $records = @(foreach ($protocol in @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1', 'TLS 1.2', 'TLS 1.3')) {
        foreach ($role in @('Server', 'Client')) {
            $values = Get-RegistryKeyValue -Path "$base\$protocol\$role"
            $enabled = $null
            $disabledByDefault = $null
            if ($null -ne $values -and $values.PSObject.Properties['Enabled']) { $enabled = [long]$values.Enabled }
            if ($null -ne $values -and $values.PSObject.Properties['DisabledByDefault']) { $disabledByDefault = [long]$values.DisabledByDefault }
            $configuration = 'NotConfigured'
            $state = 'OSDefault'
            if ($null -ne $enabled) {
                $configuration = 'Explicit'
                if ($enabled -eq 0) { $state = 'Disabled' }
                elseif ($disabledByDefault -eq 1) { $state = 'EnabledButDisabledByDefault' }
                else { $state = 'Enabled' }
            }
            if ($legacy -contains $protocol) {
                if ($null -ne $enabled -and $enabled -ne 0) { $findings.Add("$protocol $role ExplicitlyEnabled") }
                elseif ($strict -and $enabled -ne 0) { $findings.Add("$protocol $role NotExplicitlyDisabled") }
            } elseif ($protocol -eq 'TLS 1.2') {
                if ($enabled -eq 0 -and $null -ne $enabled) { $findings.Add("$protocol $role ExplicitlyDisabled") }
                elseif ($disabledByDefault -eq 1) { $findings.Add("$protocol $role DisabledByDefault") }
            }
            [pscustomobject][ordered]@{
                Protocol = $protocol; Role = $role; Enabled = $enabled; DisabledByDefault = $disabledByDefault
                Configuration = $configuration; EffectiveState = $state
            }
        }
    })
    $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; StrictMode = $strict; Protocols = $records; Findings = @($findings)
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
