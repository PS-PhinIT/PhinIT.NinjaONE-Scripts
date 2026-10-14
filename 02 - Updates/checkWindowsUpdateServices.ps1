#Requires -Version 5.1

<#
.SYNOPSIS
DE: Startkonfiguration der Updatedienste schreibgeschützt prüfen.
EN: Audit update service startup configuration without changing it.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. IncludeOptional=true ergänzt UsoSvc und WaaSMedicSvc.
EN: Windows SYSTEM, 64-bit. IncludeOptional=true includes UsoSvc and WaaSMedicSvc.
DE: Warnung bei fehlenden Pflichtdiensten/deaktivierten Diensten; gestoppt kann normal sein.
EN: Warn on missing required/disabled services; stopped can be normal.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters.
DE: Exit 0 = OK, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = Pflichtdienst (wuauserv/BITS/CryptSvc) fehlt oder ein geprüfter Dienst ist deaktiviert.
EN: Exit 0 = OK, 1 = input, query or write error, 2 = required service (wuauserv/BITS/CryptSvc) missing or a checked service is disabled.
.PARAMETER IncludeOptional
DE: String mit Boolean-Wert true/false; NinjaOne updateServicesIncludeOptional; Standard true.
EN: String containing Boolean true/false; NinjaOne updateServicesIncludeOptional; default true.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\checkWindowsUpdateServices.ps1 -IncludeOptional false
DE: Prüft nur wuauserv, BITS und CryptSvc.
EN: Checks only wuauserv, BITS and CryptSvc.
.EXAMPLE
.\checkWindowsUpdateServices.ps1 -IncludeOptional true -CustomField updateServicesReport
DE: Prüft zusätzlich UsoSvc/WaaSMedicSvc und schreibt das JSON in updateServicesReport.
EN: Also checks UsoSvc/WaaSMedicSvc and writes the JSON to updateServicesReport.
#>
[CmdletBinding()]
param(
    [string]$IncludeOptional = $env:updateServicesIncludeOptional,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $IncludeOptional = if ([string]::IsNullOrWhiteSpace($IncludeOptional) -or $IncludeOptional.Trim() -eq 'null') { '' } else { $IncludeOptional.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($IncludeOptional) -or $IncludeOptional.Trim() -eq 'null') { $IncludeOptional = 'true' }
    $optional = $false
    if (-not [bool]::TryParse($IncludeOptional.Trim(), [ref]$optional)) { throw 'IncludeOptional: true/false erforderlich / required.' }
    $names = @('wuauserv', 'BITS', 'CryptSvc')
    if ($optional) { $names += @('UsoSvc', 'WaaSMedicSvc') }
    $all = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
    $warning = $false
    $items = @(foreach ($name in $names) {
        $service = $all | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -eq $service) {
            if ($name -in @('wuauserv', 'BITS', 'CryptSvc')) { $warning = $true }
            [pscustomobject]@{ Name = $name; Present = $false; State = $null; StartMode = $null }
        } else {
            if ($service.StartMode -eq 'Disabled') { $warning = $true }
            [pscustomobject]@{ Name = $name; Present = $true; State = $service.State; StartMode = $service.StartMode }
        }
    })
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; Warning = $warning; Services = $items } | ConvertTo-Json -Depth 5
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
    Write-Error ("Updatedienstprüfung fehlgeschlagen / Update service audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
