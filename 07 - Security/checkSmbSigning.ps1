#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft, ob SMB-Signierung fuer Server und/oder Client erzwungen wird.
EN: Checks whether SMB signing is required for the server and/or client.
.DESCRIPTION
DE: Liest per Get-SmbServerConfiguration RequireSecuritySignature, EnableSecuritySignature,
    EncryptData und RejectUnencryptedAccess sowie per Get-SmbClientConfiguration
    RequireSecuritySignature, EnableSecuritySignature und (falls vorhanden) RequireEncryption.
    Zur Herkunft werden die Registry-Werte RequireSecuritySignature unter
    HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters und ...\LanmanWorkstation\Parameters
    gemeldet. Fehlen sie, gilt State NotConfigured: Der OS-Standard ist versionsabhaengig
    (bis Windows 11 23H2 / Server 2022 nicht erzwungen ausser auf Domaenencontrollern;
    Windows 11 24H2 erzwingt Signierung standardmaessig), daher ist die Bewertung immer der
    wirksame Cmdlet-Wert.
EN: Reads RequireSecuritySignature, EnableSecuritySignature, EncryptData and
    RejectUnencryptedAccess via Get-SmbServerConfiguration and RequireSecuritySignature,
    EnableSecuritySignature and (if present) RequireEncryption via Get-SmbClientConfiguration.
    For provenance, the registry values RequireSecuritySignature under
    HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters and ...\LanmanWorkstation\Parameters
    are reported. If absent, State is NotConfigured: the OS default depends on the version
    (not required up to Windows 11 23H2 / Server 2022 except on domain controllers;
    Windows 11 24H2 requires signing by default), so evaluation always uses the effective cmdlet value.
DE: Exit 2 = Signierung auf der geprueften Seite (RequiredSide) nicht erzwungen oder unbekannt,
    bzw. bei RequireEncryption=true Server-EncryptData nicht aktiv.
EN: Exit 2 = signing not required or unknown on the checked side (RequiredSide), or with
    RequireEncryption=true server EncryptData not enabled.
.PARAMETER RequiredSide
DE: NinjaOne Dropdown/Text securitySmbSigningRequiredSide: Both, Server, Client oder None (nur Bericht); Standard Both.
EN: NinjaOne dropdown/text securitySmbSigningRequiredSide: Both, Server, Client or None (report only); default Both.
.PARAMETER RequireEncryption
DE: NinjaOne Checkbox/Text securitySmbRequireEncryption: true/false; Standard false. true warnt, wenn Server-EncryptData aus ist.
EN: NinjaOne checkbox/text securitySmbRequireEncryption: true/false; default false. true warns if server EncryptData is off.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkSmbSigning.ps1
DE: Warnt, wenn Server- oder Client-Signierung nicht erzwungen wird.
EN: Warns if server or client signing is not required.
.EXAMPLE
.\checkSmbSigning.ps1 -RequiredSide Server -RequireEncryption true -CustomField smbSigningStatus
DE: Prueft nur die Serverseite plus Verschluesselung; JSON in smbSigningStatus.
EN: Checks the server side plus encryption only; JSON to smbSigningStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = Signierung/Verschluesselung nicht erzwungen.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = OK, 1 = input/query/write error, 2 = signing/encryption not required.
#>
[CmdletBinding()]
param(
    [string]$RequiredSide = $env:securitySmbSigningRequiredSide,
    [string]$RequireEncryption = $env:securitySmbRequireEncryption,
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
    $RequiredSide = ([string]$RequiredSide).Trim()
    if ($RequiredSide -ieq 'null' -or -not $RequiredSide) { $RequiredSide = 'Both' }
    $side = @('Both', 'Server', 'Client', 'None') | Where-Object { $_ -ieq $RequiredSide }
    if (-not $side) { throw 'RequiredSide muss Both/Server/Client/None sein / must be Both/Server/Client/None.' }
    $RequireEncryption = ([string]$RequireEncryption).Trim()
    if ($RequireEncryption -ieq 'null' -or -not $RequireEncryption) { $RequireEncryption = 'false' }
    $needEncryption = $false
    if (-not [bool]::TryParse($RequireEncryption, [ref]$needEncryption)) { throw 'RequireEncryption muss true/false sein / must be true/false.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    foreach ($command in @('Get-SmbServerConfiguration', 'Get-SmbClientConfiguration')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command fehlt / unavailable." }
    }

    $server = Get-SmbServerConfiguration
    $client = Get-SmbClientConfiguration
    $clientEncryption = $null
    if ($null -ne $client.PSObject.Properties['RequireEncryption']) { $clientEncryption = $client.RequireEncryption }
    $map = @{ 0 = 'NotRequired'; 1 = 'Required' }
    $serverRegistry = Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'RequireSecuritySignature' -DefaultValue $null -Map $map
    $clientRegistry = Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'RequireSecuritySignature' -DefaultValue $null -Map $map

    $findings = New-Object System.Collections.Generic.List[string]
    if (@('Both', 'Server') -contains $side -and $server.RequireSecuritySignature -ne $true) { $findings.Add('ServerSigningNotRequired') }
    if (@('Both', 'Client') -contains $side -and $client.RequireSecuritySignature -ne $true) { $findings.Add('ClientSigningNotRequired') }
    if ($needEncryption -and $server.EncryptData -ne $true) { $findings.Add('ServerEncryptionNotRequired') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status; RequiredSide = $side; RequireEncryption = $needEncryption
        Server = [ordered]@{
            RequireSecuritySignature = $server.RequireSecuritySignature; EnableSecuritySignature = $server.EnableSecuritySignature
            EncryptData = $server.EncryptData; RejectUnencryptedAccess = $server.RejectUnencryptedAccess; Registry = $serverRegistry
        }
        Client = [ordered]@{
            RequireSecuritySignature = $client.RequireSecuritySignature; EnableSecuritySignature = $client.EnableSecuritySignature
            RequireEncryption = $clientEncryption; Registry = $clientRegistry
        }
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
