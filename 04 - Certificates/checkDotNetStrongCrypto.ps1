#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft SchUseStrongCrypto und SystemDefaultTlsVersions für .NET Framework (64- und 32-Bit).
EN: Checks SchUseStrongCrypto and SystemDefaultTlsVersions for .NET Framework (64- and 32-bit).
.DESCRIPTION
DE: Liest HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319 und \v2.0.50727 sowie dieselben
    Schlüssel unter HKLM\SOFTWARE\WOW6432Node (nur auf 64-Bit-Windows). Beide Werte müssen 1 sein,
    damit .NET-Anwendungen starke Kryptografie und die TLS-Standardversionen des Systems nutzen.
    Fehlende Schlüssel/Werte gelten als nicht gesetzt. Nur lesend.
EN: Reads HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319 and \v2.0.50727 and the same keys
    under HKLM\SOFTWARE\WOW6432Node (64-bit Windows only). Both values must be 1 so that .NET
    applications use strong cryptography and the system default TLS versions.
    Missing keys/values count as not set. Read-only.
.PARAMETER IncludeV2
DE: NinjaOne Checkbox/Text certDotNetIncludeV2; true/false; Standard true. false = nur v4.0.30319 prüfen.
EN: NinjaOne checkbox/text certDotNetIncludeV2; true/false; default true. false = check v4.0.30319 only.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkDotNetStrongCrypto.ps1
DE: Prüft v4.0.30319 und v2.0.50727 in beiden Registry-Ansichten.
EN: Checks v4.0.30319 and v2.0.50727 in both registry views.
.EXAMPLE
.\checkDotNetStrongCrypto.ps1 -IncludeV2 false -CustomField dotNetCryptoReport
DE: Nur v4.0.30319; JSON in dotNetCryptoReport.
EN: Only v4.0.30319; JSON to dotNetCryptoReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit (32-Bit-Prozesse würden umgeleitet und brechen ab).
    Exit 0 = alle Werte 1, 1 = Eingabe-, Registry- oder Schreibfehler, 2 = mindestens ein Wert
    fehlt oder ist nicht 1.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit (32-bit processes would be redirected and abort).
    Exit 0 = all values 1, 1 = input, registry or write error, 2 = at least one value is
    missing or not 1.
#>
[CmdletBinding()]
param(
    [string]$IncludeV2 = $env:certDotNetIncludeV2,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryKeyValue {
    param([string]$Path)
    try { Get-ItemProperty -Path $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { $null }
}
try {
    $IncludeV2 = ([string]$IncludeV2).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $IncludeV2 -or $IncludeV2 -ieq 'null') { $IncludeV2 = 'true' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($IncludeV2 -notin @('true', 'false')) { throw 'certDotNetIncludeV2: true/false erforderlich / required.' }
    $withV2 = $IncludeV2 -ieq 'true'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $versions = @('v4.0.30319')
    if ($withV2) { $versions += 'v2.0.50727' }
    $views = @(@{ Name = '64-bit'; Root = 'HKLM:\SOFTWARE\Microsoft\.NETFramework' })
    if ([Environment]::Is64BitOperatingSystem) { $views += @{ Name = '32-bit'; Root = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework' } }
    $records = @(foreach ($version in $versions) {
        foreach ($view in $views) {
            $values = Get-RegistryKeyValue -Path "$($view.Root)\$version"
            $strong = $null
            $systemDefault = $null
            if ($null -ne $values -and $values.PSObject.Properties['SchUseStrongCrypto']) { $strong = $values.SchUseStrongCrypto }
            if ($null -ne $values -and $values.PSObject.Properties['SystemDefaultTlsVersions']) { $systemDefault = $values.SystemDefaultTlsVersions }
            [pscustomobject][ordered]@{
                Framework = $version; View = $view.Name; KeyExists = $null -ne $values
                SchUseStrongCrypto = $strong; SystemDefaultTlsVersions = $systemDefault
                Compliant = ("$strong" -eq '1') -and ("$systemDefault" -eq '1')
            }
        }
    })
    $nonCompliant = @($records | Where-Object { -not $_.Compliant }).Count
    $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; IncludeV2 = $withV2; NonCompliantCount = $nonCompliant; Settings = $records
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($nonCompliant -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
