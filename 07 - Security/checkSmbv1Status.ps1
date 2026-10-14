#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft, ob SMBv1 (Server, Client-Treiber oder optionales Feature) aktiv ist.
EN: Checks whether SMBv1 (server, client driver or optional feature) is enabled.
.DESCRIPTION
DE: Liest EnableSMB1Protocol per Get-SmbServerConfiguration, den Starttyp des
    SMBv1-Clienttreibers (HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10, Wert Start:
    0 Boot, 1 System, 2 Automatisch, 3 Manuell, 4 Deaktiviert) und optional den Zustand des
    optionalen Features SMB1Protocol (Get-WindowsOptionalFeature, falls verfuegbar).
    Fehlt der Schluessel mrxsmb10, ist der SMBv1-Client nicht installiert (State NotInstalled).
    Zusaetzlich wird LanmanServer\Parameters\SMB1 gemeldet: fehlt der Wert, gilt
    NotConfigured = Windows-Standard (Server-SMBv1 aktiv, sofern die Komponente installiert ist).
    Ist das Feature nicht abfragbar (z. B. aeltere Server), erscheint FeatureState Unavailable.
EN: Reads EnableSMB1Protocol via Get-SmbServerConfiguration, the start type of the SMBv1
    client driver (HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10, value Start: 0 boot,
    1 system, 2 automatic, 3 manual, 4 disabled) and optionally the state of the optional
    feature SMB1Protocol (Get-WindowsOptionalFeature, if available). If the mrxsmb10 key is
    absent, the SMBv1 client is not installed (State NotInstalled). LanmanServer\Parameters\SMB1
    is reported too: if absent, NotConfigured = Windows default (server SMBv1 on when the
    component is installed). If the feature cannot be queried (e.g. older servers),
    FeatureState is Unavailable.
DE: Exit 2 = Server-SMBv1 aktiv oder unbekannt, Client-Treiber nicht deaktiviert oder Feature
    Enabled/EnablePending. Aenderungen am Feature wirken erst nach Neustart.
EN: Exit 2 = server SMBv1 enabled or unknown, client driver not disabled or feature
    Enabled/EnablePending. Feature changes take effect only after a reboot.
.PARAMETER IncludeFeature
DE: NinjaOne Checkbox/Text securitySmb1IncludeFeature: true/false; Standard true. false ueberspringt die (langsame) DISM-Featureabfrage.
EN: NinjaOne checkbox/text securitySmb1IncludeFeature: true/false; default true. false skips the (slow) DISM feature query.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkSmbv1Status.ps1
DE: Prueft Server, Client-Treiber und optionales Feature auf SMBv1.
EN: Checks server, client driver and optional feature for SMBv1.
.EXAMPLE
.\checkSmbv1Status.ps1 -IncludeFeature false -CustomField smb1Status
DE: Ohne Featureabfrage; JSON in das MultiLine-Feld smb1Status.
EN: Without feature query; JSON to the MultiLine field smb1Status.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = SMBv1 aus, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = SMBv1 aktiv/unklar.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = SMBv1 off, 1 = input/query/write error, 2 = SMBv1 enabled/unclear.
#>
[CmdletBinding()]
param(
    [string]$IncludeFeature = $env:securitySmb1IncludeFeature,
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

try {
    $IncludeFeature = ([string]$IncludeFeature).Trim()
    if ($IncludeFeature -ieq 'null' -or -not $IncludeFeature) { $IncludeFeature = 'true' }
    $withFeature = $false
    if (-not [bool]::TryParse($IncludeFeature, [ref]$withFeature)) { throw 'IncludeFeature muss true/false sein / must be true/false.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if (-not (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue)) { throw 'Get-SmbServerConfiguration fehlt / unavailable.' }

    $findings = New-Object System.Collections.Generic.List[string]
    $serverSmb1 = (Get-SmbServerConfiguration).EnableSMB1Protocol
    if ($null -eq $serverSmb1) { $findings.Add('ServerSmb1Unknown') }
    elseif ([bool]$serverSmb1) { $findings.Add('ServerSmb1Enabled') }
    $serverRegistry = Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -DefaultValue 1 -Map @{ 0 = 'Disabled'; 1 = 'Enabled' }

    # DE: Fehlender Treiberschluessel = SMBv1-Client entfernt. EN: Missing driver key = SMBv1 client removed.
    $clientPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10'
    $startMap = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }
    $client = Get-RegistrySetting -Path $clientPath -Name 'Start' -DefaultValue $null -Map $startMap
    $clientState = 'NotInstalled'
    if (Test-Path -LiteralPath $clientPath) {
        $clientState = 'Enabled'
        if ($client.EffectiveValue -eq 4) { $clientState = 'Disabled' }
        elseif ($null -eq $client.EffectiveValue) { $clientState = 'Unknown' }
    }
    if ($clientState -eq 'Enabled') { $findings.Add('ClientSmb1Enabled') }
    elseif ($clientState -eq 'Unknown') { $findings.Add('ClientSmb1Unknown') }

    $featureState = 'Skipped'
    $featureNote = $null
    if ($withFeature) {
        if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            try {
                $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol'
                $featureState = 'NotPresent'
                if ($null -ne $feature) { $featureState = [string]@($feature)[0].State }
            }
            catch {
                $featureState = 'Unavailable'
                $featureNote = [string]$_.Exception.Message
                if ($featureNote.Length -gt 300) { $featureNote = $featureNote.Substring(0, 300) }
            }
        }
        else { $featureState = 'Unavailable'; $featureNote = 'Get-WindowsOptionalFeature fehlt / unavailable.' }
    }
    if (@('Enabled', 'EnablePending') -contains $featureState) { $findings.Add('FeatureSmb1Enabled') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status
        Server = [ordered]@{ EnableSMB1Protocol = $serverSmb1; Registry = $serverRegistry }
        Client = [ordered]@{ State = $clientState; DriverStart = $client }
        Feature = [ordered]@{ Name = 'SMB1Protocol'; State = $featureState; Note = $featureNote }
        Findings = @($findings)
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
