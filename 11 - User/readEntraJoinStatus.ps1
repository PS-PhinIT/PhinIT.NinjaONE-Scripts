#Requires -Version 5.1

<#
.SYNOPSIS
DE: Entra-ID-/Domaenen-Beitrittsstatus des Geraets lesen. EN: Read the device Entra ID/domain join state.
.DESCRIPTION
DE: Ruft dsregcmd /status auf und wertet "Schluessel : Wert"-Zeilen aus: AzureAdJoined,
EnterpriseJoined, DomainJoined, DomainName, TenantName, TenantId, DeviceId, DeviceAuthStatus,
KeySignTest, TpmProtected. Nur Geraetestatus: unter SYSTEM sind Benutzerdaten (PRT, WorkplaceJoined)
nicht aussagekraeftig und werden nicht gemeldet. Keine Zertifikate, Thumbprints oder Tokens.
EN: Runs dsregcmd /status and parses "Key : Value" lines: AzureAdJoined, EnterpriseJoined,
DomainJoined, DomainName, TenantName, TenantId, DeviceId, DeviceAuthStatus, KeySignTest,
TpmProtected. Device state only: under SYSTEM user data (PRT, WorkplaceJoined) is not meaningful
and is not reported. No certificates, thumbprints or tokens.
DE: Abgeleiteter joinType: HybridJoined (Entra + Domaene), EntraJoined, DomainJoined, Workgroup.
Schluesselnamen sind englisch; Felder fehlen je nach Windows-Version (dann null).
EN: Derived joinType: HybridJoined (Entra + domain), EntraJoined, DomainJoined, Workgroup.
Key names are English; fields may be missing depending on the Windows version (then null).
.PARAMETER ExpectedJoinType
DE: NinjaOne userExpectedJoinType (Auswahl), leer/EntraJoined/HybridJoined/DomainJoined/Workgroup; Standard leer = kein Vergleich.
EN: NinjaOne userExpectedJoinType (drop-down), blank/EntraJoined/HybridJoined/DomainJoined/Workgroup; default blank = no comparison.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\readEntraJoinStatus.ps1
DE: Beitrittsstatus als JSON, ohne Vergleich. EN: Join state as JSON, no comparison.
.EXAMPLE
.\readEntraJoinStatus.ps1 -ExpectedJoinType HybridJoined -CustomField entraJoinState
DE: Exit 2, wenn nicht Hybrid; JSON in entraJoinState. EN: Exit 2 if not hybrid; JSON to entraJoinState.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen.
Exit 0 = Erfolg/erwarteter Typ, 1 = Eingabe-/dsregcmd-/Schreibfehler, 2 = joinType weicht von ExpectedJoinType ab.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters.
Exit 0 = success/expected type, 1 = input/dsregcmd/write error, 2 = joinType differs from ExpectedJoinType.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExpectedJoinType = $env:userExpectedJoinType,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputValue {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([System.Collections.IDictionary]$Report, [string]$Field)
    $content = ConvertTo-Json -InputObject $Report -Depth 4
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $ExpectedJoinType = Get-InputValue $ExpectedJoinType ''
    if ($ExpectedJoinType -and $ExpectedJoinType -notin @('EntraJoined', 'HybridJoined', 'DomainJoined', 'Workgroup')) {
        throw 'userExpectedJoinType must be EntraJoined/HybridJoined/DomainJoined/Workgroup / ungueltig.'
    }
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command dsregcmd -ErrorAction SilentlyContinue)) { throw 'dsregcmd unavailable / nicht verfuegbar.' }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $lines = @(dsregcmd /status 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw ('dsregcmd exit {0} / dsregcmd-Fehler.' -f $code) }
    $wanted = @('AzureAdJoined', 'EnterpriseJoined', 'DomainJoined', 'DomainName', 'TenantName', 'TenantId', 'DeviceId', 'DeviceAuthStatus', 'KeySignTest', 'TpmProtected')
    $values = @{}
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*?)\s*$') {
            $name = $Matches[1]
            # DE: Nur erlaubte Geraeteschluessel, erste Fundstelle gewinnt. EN: Allowed device keys only, first occurrence wins.
            foreach ($candidate in $wanted) {
                if ($name -ieq $candidate -and -not $values.ContainsKey($candidate)) { $values[$candidate] = $Matches[2] }
            }
        }
    }
    if (-not $values.ContainsKey('AzureAdJoined') -or -not $values.ContainsKey('DomainJoined')) { throw 'Unexpected dsregcmd output / Unerwartete dsregcmd-Ausgabe.' }
    $entra = $values['AzureAdJoined'] -ieq 'YES'
    $domain = $values['DomainJoined'] -ieq 'YES'
    $joinType = 'Workgroup'
    if ($entra -and $domain) { $joinType = 'HybridJoined' }
    elseif ($entra) { $joinType = 'EntraJoined' }
    elseif ($domain) { $joinType = 'DomainJoined' }
    $deviceState = [ordered]@{}
    foreach ($candidate in $wanted) {
        $value = $null
        if ($values.ContainsKey($candidate) -and $values[$candidate]) { $value = $values[$candidate] }
        $deviceState[$candidate] = $value
    }
    $matchesExpectation = $null
    if ($ExpectedJoinType) { $matchesExpectation = ($joinType -eq $ExpectedJoinType) }
    $report = [ordered]@{
        inventory = 'Entra/domain join state / Beitrittsstatus'; scope = 'Device only (SYSTEM) / Nur Geraet'
        joinType = $joinType; expectedJoinType = $ExpectedJoinType; matchesExpectation = $matchesExpectation
        deviceState = $deviceState
    }
    Write-InventoryReport -Report $report -Field $CustomField
    if ($matchesExpectation -eq $false) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
