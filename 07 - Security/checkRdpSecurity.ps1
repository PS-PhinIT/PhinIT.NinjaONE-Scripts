#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prueft die RDP-Sicherheitskonfiguration (NLA, SecurityLayer, Verschluesselung, Port) nur lesend.
    EN: Checks the RDP security configuration (NLA, security layer, encryption, port) read-only.
.DESCRIPTION
    DE: Liest fDenyTSConnections (HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server) sowie
        UserAuthentication, SecurityLayer, MinEncryptionLevel und PortNumber
        (HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp). Richtlinienwerte unter
        HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services haben Vorrang (Source = Policy).
        UserAuthentication 1 = NLA; SecurityLayer 0 = RDP, 1 = Negotiate, 2 = TLS;
        MinEncryptionLevel 1 = Low, 2 = ClientCompatible, 3 = High, 4 = FIPS. Fehlender NLA-Wert gilt als
        nicht bestaetigt. Firewallregeln und Remote Desktop Gateway werden nicht bewertet.
    EN: Reads fDenyTSConnections (HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server) and
        UserAuthentication, SecurityLayer, MinEncryptionLevel and PortNumber
        (HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp). Policy values under
        HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services take precedence (Source = Policy).
        UserAuthentication 1 = NLA; SecurityLayer 0 = RDP, 1 = Negotiate, 2 = TLS;
        MinEncryptionLevel 1 = Low, 2 = ClientCompatible, 3 = High, 4 = FIPS. A missing NLA value counts as
        not confirmed. Firewall rules and Remote Desktop Gateway are not evaluated.
.PARAMETER AllowRdp
    DE: NinjaOne Checkbox/Text securityRdpAllow, true/false/1/0; Standard true. false = aktiviertes RDP ist Befund.
    EN: NinjaOne checkbox/text securityRdpAllow, true/false/1/0; default true. false = enabled RDP is a finding.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkRdpSecurity.ps1
    DE: Exit 2, wenn RDP aktiv ist und NLA fehlt oder SecurityLayer 0 (RDP) ist.
    EN: Exit 2 if RDP is enabled and NLA is missing or SecurityLayer is 0 (RDP).
.EXAMPLE
    .\checkRdpSecurity.ps1 -AllowRdp false -CustomField rdpSecurity
    DE: Jedes aktivierte RDP ist ein Befund; JSON ins Feld rdpSecurity.
    EN: Any enabled RDP is a finding; JSON to the field rdpSecurity.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter vor Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = RDP aktiv ohne NLA, mit SecurityLayer 0
        oder RDP aktiv bei AllowRdp=false.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = RDP enabled without NLA, with SecurityLayer 0
        or RDP enabled while AllowRdp=false.
#>
[CmdletBinding()]
param(
    [string]$AllowRdp = $env:securityRdpAllow,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-RegistryEntry {
    param([string]$Path)
    $map = @{}
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $map }
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { $map[$property.Name] = $property.Value }
    }
    return $map
}
try {
    $text = ([string]$AllowRdp).Trim()
    if (-not $text -or $text -ieq 'null') { $text = 'true' }
    if ($text -in @('true', '1')) { $allow = $true }
    elseif ($text -in @('false', '0')) { $allow = $false }
    else { throw 'securityRdpAllow: true/false erforderlich / required.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }

    $server = Get-RegistryEntry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $winStation = Get-RegistryEntry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $policy = Get-RegistryEntry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    if ($server.Count -eq 0 -and $winStation.Count -eq 0) { throw 'Terminal-Server-Registry nicht lesbar / Terminal Server registry unavailable.' }
    $settings = [ordered]@{}
    foreach ($name in @('fDenyTSConnections', 'UserAuthentication', 'SecurityLayer', 'MinEncryptionLevel')) {
        $local = $winStation
        if ($name -eq 'fDenyTSConnections') { $local = $server }
        $value = $null; $from = 'NotSet'
        if ($policy.ContainsKey($name)) { $value = [int]$policy[$name]; $from = 'Policy' }
        elseif ($local.ContainsKey($name)) { $value = [int]$local[$name]; $from = 'Local' }
        $settings[$name] = [pscustomobject]@{ Value = $value; Source = $from }
    }
    $port = $null
    if ($winStation.ContainsKey('PortNumber')) { $port = [int]$winStation['PortNumber'] }
    $enabled = $settings['fDenyTSConnections'].Value -eq 0
    $nla = $settings['UserAuthentication'].Value -eq 1
    $layer = $settings['SecurityLayer'].Value
    $layerName = $null
    if ($null -ne $layer) { $layerName = @{ 0 = 'RDP'; 1 = 'Negotiate'; 2 = 'TLS' }[$layer]; if (-not $layerName) { $layerName = 'Unknown' } }
    $encryption = $settings['MinEncryptionLevel'].Value
    $encryptionName = $null
    if ($null -ne $encryption) { $encryptionName = @{ 1 = 'Low'; 2 = 'ClientCompatible'; 3 = 'High'; 4 = 'FIPS' }[$encryption]; if (-not $encryptionName) { $encryptionName = 'Unknown' } }
    $findings = New-Object System.Collections.Generic.List[string]
    if ($enabled) {
        if (-not $allow) { $findings.Add('RdpEnabledButNotAllowed') }
        if (-not $nla) { $findings.Add('NlaNotEnforced') }
        if ($layer -eq 0) { $findings.Add('SecurityLayerRdp') }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        RdpEnabled = $enabled; AllowRdp = $allow; NlaRequired = $nla
        SecurityLayer = $layer; SecurityLayerName = $layerName
        MinEncryptionLevel = $encryption; MinEncryptionLevelName = $encryptionName
        PortNumber = $port; Settings = $settings; Findings = @($findings)
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
