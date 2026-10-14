#Requires -Version 5.1

<#
.SYNOPSIS
DE: PowerShell-Ausführungsrichtlinie schreibgeschützt prüfen.
EN: Audit PowerShell execution policy without changing it.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. ExpectedPolicy leer: nur Inventur; sonst exakter Richtlinienvergleich.
EN: Windows SYSTEM, 64-bit. Empty ExpectedPolicy: inventory only; otherwise exact policy comparison.
DE: Richtlinie gilt für diesen Host/Benutzer (SYSTEM), nicht für alle Hosts; keine Sicherheitsgrenze.
EN: Policy applies to this host/user (SYSTEM), not all hosts; it is not a security boundary.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen. Abweichung: Exit 2.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters. Mismatch: exit 2.
DE: Exit 0 = OK/Inventur, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = effektive Richtlinie weicht von ExpectedPolicy ab.
EN: Exit 0 = OK/inventory, 1 = input, query or write error, 2 = effective policy differs from ExpectedPolicy.
.PARAMETER ExpectedPolicy
DE: String; NinjaOne powerShellPolicyExpected; Standard leer (Inventur); Restricted, AllSigned, RemoteSigned, Unrestricted, Bypass oder Undefined.
EN: String; NinjaOne powerShellPolicyExpected; default empty (inventory); Restricted, AllSigned, RemoteSigned, Unrestricted, Bypass or Undefined.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\checkPowerShellPolicy.ps1
DE: Nur Inventur der Ausführungsrichtlinien.
EN: Execution policy inventory only.
.EXAMPLE
.\checkPowerShellPolicy.ps1 -ExpectedPolicy RemoteSigned -CustomField powerShellPolicyReport
DE: Meldet Exit 2, wenn die effektive Richtlinie nicht RemoteSigned ist; JSON in powerShellPolicyReport.
EN: Returns exit 2 if the effective policy is not RemoteSigned; JSON to powerShellPolicyReport.
#>
[CmdletBinding()]
param(
    [string]$ExpectedPolicy = $env:powerShellPolicyExpected,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $ExpectedPolicy = if ([string]::IsNullOrWhiteSpace($ExpectedPolicy) -or $ExpectedPolicy.Trim() -eq 'null') { '' } else { $ExpectedPolicy.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    $expected = if ($null -eq $ExpectedPolicy) { '' } else { $ExpectedPolicy.Trim() }
    if ($expected -eq 'null') { $expected = '' }
    if ($expected -and $expected -notin @('Restricted', 'AllSigned', 'RemoteSigned', 'Unrestricted', 'Bypass', 'Undefined')) { throw 'Ungültige ExpectedPolicy / Invalid ExpectedPolicy.' }
    $effective = [string](Get-ExecutionPolicy -ErrorAction Stop)
    $policies = @(Get-ExecutionPolicy -List -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ Scope = [string]$_.Scope; ExecutionPolicy = [string]$_.ExecutionPolicy }
    })
    $warning = [bool]($expected -and $effective -ne $expected)
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; HostVersion = $PSVersionTable.PSVersion.ToString(); EffectivePolicy = $effective; ExpectedPolicy = $expected; Warning = $warning; Policies = $policies } | ConvertTo-Json -Depth 5
    Write-Output $json
    $field = if ($null -eq $CustomField) { '' } else { $CustomField.Trim() }
    if ($field -and $field -ne 'null') {
        if ($field.Length -gt 128 -or $field -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
        if ($json.Length -gt 4000) { throw 'JSON überschreitet 4000 Zeichen / JSON exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $field -Value $json -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "Ninja-Property-Set Exitcode / exit code: $global:LASTEXITCODE" }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Richtlinienprüfung fehlgeschlagen / Policy audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}