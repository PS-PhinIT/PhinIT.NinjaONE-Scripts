#Requires -Version 5.1

<#
.SYNOPSIS
DE: Automatische Windows-Anmeldung (AutoAdminLogon) pruefen. EN: Check automatic Windows logon (AutoAdminLogon).
.DESCRIPTION
DE: Liest HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon: AutoAdminLogon, ForceAutoLogon,
DefaultUserName, DefaultDomainName, AutoLogonCount sowie NUR das Vorhandensein (bool) des Werts
DefaultPassword (Klartext) und des LSA-Geheimnisses DefaultPassword (HKLM\SECURITY\Policy\Secrets,
z. B. von Sysinternals Autologon). Kennwortinhalte werden nie gelesen oder ausgegeben.
EN: Reads HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon: AutoAdminLogon, ForceAutoLogon,
DefaultUserName, DefaultDomainName, AutoLogonCount and ONLY the presence (bool) of the plaintext
DefaultPassword value and of the DefaultPassword LSA secret (HKLM\SECURITY\Policy\Secrets, e.g. from
Sysinternals Autologon). Password contents are never read or printed.
DE: Die LSA-Pruefung braucht SYSTEM; ohne Zugriff lautet sie Unknown. Ein leerer DefaultPassword-Wert gilt als vorhanden.
EN: The LSA check requires SYSTEM; without access it reports Unknown. An empty DefaultPassword value counts as present.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkAutoLogon.ps1
DE: Autologon-Status als JSON; Exit 2 bei aktivem Autologon. EN: Autologon state as JSON; exit 2 when autologon is enabled.
.EXAMPLE
.\checkAutoLogon.ps1 -CustomField autoLogonState
DE: Ergebnis zusaetzlich in autoLogonState schreiben. EN: Also write the result to autoLogonState.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen. Nur lesend.
Exit 0 = Autologon aus und kein Klartextkennwort, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = AutoAdminLogon = 1 oder Klartext-DefaultPassword vorhanden.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters. Read-only.
Exit 0 = autologon off and no plaintext password, 1 = input/query/write error, 2 = AutoAdminLogon = 1 or plaintext DefaultPassword present.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
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
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    # DE: RegistryKey statt Get-ItemProperty, damit DefaultPassword nie gelesen wird. EN: RegistryKey instead of Get-ItemProperty so DefaultPassword is never read.
    $key = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
    $names = @($key.GetValueNames())
    $autoAdmin = ([string]$key.GetValue('AutoAdminLogon')).Trim()
    $forceAuto = ([string]$key.GetValue('ForceAutoLogon')).Trim()
    $userName = $null
    if ($names -contains 'DefaultUserName') { $userName = [string]$key.GetValue('DefaultUserName') }
    $domainName = $null
    if ($names -contains 'DefaultDomainName') { $domainName = [string]$key.GetValue('DefaultDomainName') }
    $logonCount = $null
    if ($names -contains 'AutoLogonCount') {
        $parsedCount = 0
        if ([int]::TryParse([string]$key.GetValue('AutoLogonCount'), [ref]$parsedCount)) { $logonCount = $parsedCount }
    }
    $plaintextPresent = $names -contains 'DefaultPassword'
    $lsaSecret = 'Unknown'
    try {
        $secrets = Get-Item -LiteralPath 'HKLM:\SECURITY\Policy\Secrets' -ErrorAction Stop
        $lsaSecret = 'Absent'
        if (@($secrets.GetSubKeyNames()) -contains 'DefaultPassword') { $lsaSecret = 'Present' }
    } catch { $lsaSecret = 'Unknown' }
    $enabled = $autoAdmin -eq '1'
    $report = [ordered]@{
        check = 'Automatic logon / Automatische Anmeldung'
        autoAdminLogonEnabled = $enabled; autoAdminLogonValue = $(if ($names -contains 'AutoAdminLogon') { $autoAdmin } else { $null })
        forceAutoLogon = ($forceAuto -eq '1'); defaultUserName = $userName; defaultDomainName = $domainName
        autoLogonCount = $logonCount; plaintextDefaultPasswordPresent = $plaintextPresent; lsaSecretDefaultPassword = $lsaSecret
        alert = ($enabled -or $plaintextPresent)
    }
    Write-InventoryReport -Report $report -Field $CustomField
    if ($enabled -or $plaintextPresent) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
