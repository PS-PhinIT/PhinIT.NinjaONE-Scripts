#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft Legacy-Authentifizierung: LM/NTLM-Stufe, LM-Hashes, WDigest und Anonymous-Einschraenkungen.
EN: Audits legacy authentication: LM/NTLM level, LM hashes, WDigest and anonymous restrictions.
.DESCRIPTION
DE: Liest ohne Aenderungen (fehlender Wert = State NotConfigured, wirksamer Windows-Standard in Klammern):
    HKLM:\SYSTEM\CurrentControlSet\Control\Lsa LmCompatibilityLevel (3 = nur NTLMv2 senden),
    NoLMHash (1 = keine LM-Hashes), RestrictAnonymous (0), RestrictAnonymousSAM (1);
    ...\Lsa\MSV1_0 RestrictSendingNTLMTraffic (0 = alles erlauben), NtlmMinClientSec und
    NtlmMinServerSec (536870912 = 128-Bit verlangt);
    ...\Control\SecurityProviders\WDigest UseLogonCredential (0 = kein Klartext-Cache,
    Standard ab Windows 8.1/Server 2012 R2).
    Werte 0..5 LmCompatibilityLevel: 0 LM+NTLM, 1 LM+NTLM mit NTLMv2-Sitzung, 2 nur NTLM,
    3 nur NTLMv2, 4 NTLMv2 und LM ablehnen, 5 NTLMv2 und LM/NTLM ablehnen.
EN: Reads without changes (absent value = State NotConfigured, effective Windows default in brackets):
    HKLM:\SYSTEM\CurrentControlSet\Control\Lsa LmCompatibilityLevel (3 = send NTLMv2 only),
    NoLMHash (1 = no LM hashes), RestrictAnonymous (0), RestrictAnonymousSAM (1);
    ...\Lsa\MSV1_0 RestrictSendingNTLMTraffic (0 = allow all), NtlmMinClientSec and
    NtlmMinServerSec (536870912 = require 128-bit);
    ...\Control\SecurityProviders\WDigest UseLogonCredential (0 = no cleartext caching,
    default since Windows 8.1/Server 2012 R2).
    LmCompatibilityLevel 0..5: 0 LM+NTLM, 1 LM+NTLM with NTLMv2 session, 2 NTLM only,
    3 NTLMv2 only, 4 NTLMv2 and refuse LM, 5 NTLMv2 and refuse LM/NTLM.
DE: Exit 2 = wirksames LmCompatibilityLevel < MinimumLevel (auch Standard 3 bei Minimum 5),
    NoLMHash ungleich 1, WDigest UseLogonCredential = 1 oder ungueltiger Wert dieser drei.
    Stufe 5 kann aeltere Geraete/Anwendungen brechen; vor dem Erzwingen NTLM-Audit nutzen.
EN: Exit 2 = effective LmCompatibilityLevel < MinimumLevel (including default 3 with minimum 5),
    NoLMHash not 1, WDigest UseLogonCredential = 1 or invalid value of these three.
    Level 5 can break legacy devices/applications; use NTLM auditing before enforcing.
.PARAMETER MinimumLevel
DE: NinjaOne Integer securityLmCompatibilityMinimum: 0..5; Standard 5.
EN: NinjaOne integer securityLmCompatibilityMinimum: 0..5; default 5.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkLegacyAuthentication.ps1
DE: Verlangt LmCompatibilityLevel 5, keine LM-Hashes und keinen WDigest-Klartext.
EN: Requires LmCompatibilityLevel 5, no LM hashes and no WDigest cleartext.
.EXAMPLE
.\checkLegacyAuthentication.ps1 -MinimumLevel 3 -CustomField legacyAuthStatus
DE: Akzeptiert ab Stufe 3; JSON in das MultiLine-Feld legacyAuthStatus.
EN: Accepts level 3 and above; JSON to the MultiLine field legacyAuthStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = unsichere Legacy-Authentifizierung.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = OK, 1 = input/query/write error, 2 = insecure legacy authentication.
#>
[CmdletBinding()]
param(
    [string]$MinimumLevel = $env:securityLmCompatibilityMinimum,
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
    $MinimumLevel = ([string]$MinimumLevel).Trim()
    if ($MinimumLevel -ieq 'null' -or -not $MinimumLevel) { $MinimumLevel = '5' }
    $minimum = 0
    if (-not [int]::TryParse($MinimumLevel, [ref]$minimum) -or $minimum -lt 0 -or $minimum -gt 5) { throw 'MinimumLevel muss 0..5 sein / must be 0..5.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }

    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $msv = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
    $levels = @{
        0 = 'SendLmAndNtlm'; 1 = 'SendLmAndNtlmUseNtlmv2SessionIfNegotiated'; 2 = 'SendNtlmOnly'
        3 = 'SendNtlmv2Only'; 4 = 'SendNtlmv2OnlyRefuseLm'; 5 = 'SendNtlmv2OnlyRefuseLmAndNtlm'
    }
    $lmLevel = Get-RegistrySetting -Path $lsa -Name 'LmCompatibilityLevel' -DefaultValue 3 -Map $levels
    $noLmHash = Get-RegistrySetting -Path $lsa -Name 'NoLMHash' -DefaultValue 1 -Map @{ 0 = 'LmHashStored'; 1 = 'LmHashNotStored' }
    $wdigest = Get-RegistrySetting -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -DefaultValue 0 -Map @{ 0 = 'NoCleartextCaching'; 1 = 'CleartextCaching' }
    $settings = @(
        $lmLevel, $noLmHash, $wdigest,
        (Get-RegistrySetting -Path $msv -Name 'RestrictSendingNTLMTraffic' -DefaultValue 0 -Map @{ 0 = 'AllowAll'; 1 = 'AuditAll'; 2 = 'DenyAll' }),
        (Get-RegistrySetting -Path $msv -Name 'NtlmMinClientSec' -DefaultValue 536870912),
        (Get-RegistrySetting -Path $msv -Name 'NtlmMinServerSec' -DefaultValue 536870912),
        (Get-RegistrySetting -Path $lsa -Name 'RestrictAnonymous' -DefaultValue 0 -Map @{ 0 = 'NoRestriction'; 1 = 'NoSamAndShareEnumeration'; 2 = 'NoAccessWithoutExplicitPermission' }),
        (Get-RegistrySetting -Path $lsa -Name 'RestrictAnonymousSAM' -DefaultValue 1 -Map @{ 0 = 'SamEnumerationAllowed'; 1 = 'SamEnumerationRestricted' })
    )

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($setting in @($lmLevel, $noLmHash, $wdigest)) { if ($setting.State -eq 'Invalid') { $findings.Add($setting.Name + 'Invalid') } }
    if ($null -ne $lmLevel.EffectiveValue -and $lmLevel.EffectiveValue -lt $minimum) { $findings.Add('LmCompatibilityLevelBelowMinimum') }
    if ($null -ne $noLmHash.EffectiveValue -and $noLmHash.EffectiveValue -ne 1) { $findings.Add('LmHashStorageAllowed') }
    if ($wdigest.EffectiveValue -eq 1) { $findings.Add('WDigestCleartextEnabled') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status; MinimumLmCompatibilityLevel = $minimum; Settings = $settings; Findings = @($findings)
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
