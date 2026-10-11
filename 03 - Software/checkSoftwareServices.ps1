#Requires -Version 5.1
<#
.SYNOPSIS
DE: Erwartete Anwendungsdienste auf Vorhandensein und Laufstatus prüfen.
EN: Check expected application services for presence and running state.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit. ServiceNames: exakte semikolongetrennte Dienstnamen, standardmäßig Spooler.
EN: Windows SYSTEM, 64-bit. ServiceNames: exact semicolon-separated service names, default Spooler.
DE: RequireRunning=false prüft nur Vorhandensein. Keine Dienständerung. Abweichung: Exit 2.
EN: RequireRunning=false checks presence only. No service changes. Mismatch: exit 2.
DE: MultiLine-CustomField: Klartext-JSON, maximal 4000 Zeichen; keine Anmeldekonten/Startbefehle.
EN: MultiLine CustomField: plain-text JSON, maximum 4000 characters; no logon accounts/start commands.
.PARAMETER ServiceNames
DE: String; NinjaOne softwareServicesNames; Standard Spooler; 1-30 semikolongetrennte Namen, je 1-128 Zeichen, insgesamt maximal 2000; Muster ^[A-Za-z0-9][A-Za-z0-9_. $-]{0,127}$.
EN: String; NinjaOne softwareServicesNames; default Spooler; 1-30 semicolon-separated names, each 1-128 characters, maximum 2000 total; pattern ^[A-Za-z0-9][A-Za-z0-9_. $-]{0,127}$.
.PARAMETER RequireRunning
DE: String mit Boolean-Wert true/false; NinjaOne softwareServicesRequireRunning; Standard true.
EN: String containing Boolean true/false; NinjaOne softwareServicesRequireRunning; default true.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
#>
[CmdletBinding()]
param(
    [string]$ServiceNames = $env:softwareServicesNames,
    [string]$RequireRunning = $env:softwareServicesRequireRunning,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $ServiceNames = if ([string]::IsNullOrWhiteSpace($ServiceNames) -or $ServiceNames.Trim() -eq 'null') { '' } else { $ServiceNames.Trim() }
    $RequireRunning = if ([string]::IsNullOrWhiteSpace($RequireRunning) -or $RequireRunning.Trim() -eq 'null') { '' } else { $RequireRunning.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($ServiceNames) -or $ServiceNames.Trim() -eq 'null') { $ServiceNames = 'Spooler' }
    if ($ServiceNames.Length -gt 2000) { throw 'Zu viele Dienstnamen / Too many service names.' }
    $names = @($ServiceNames.Split(';') | ForEach-Object { $_.Trim() })
    if ($names.Count -gt 30 -or @($names | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9_. $-]{0,127}$' }).Count) { throw 'Ungültige Dienstnamen / Invalid service names.' }
    $names = @($names | Sort-Object -Unique)
    if ([string]::IsNullOrWhiteSpace($RequireRunning) -or $RequireRunning.Trim() -eq 'null') { $RequireRunning = 'true' }
    $running = $false
    if (-not [bool]::TryParse($RequireRunning.Trim(), [ref]$running)) { throw 'RequireRunning: true/false erforderlich / required.' }
    $all = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
    $warning = $false
    $items = @(foreach ($name in $names) {
        $service = $all | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -eq $service) {
            $warning = $true
            [pscustomobject]@{ Name = $name; Present = $false; State = $null; StartMode = $null }
        } else {
            if ($running -and $service.State -ne 'Running') { $warning = $true }
            [pscustomobject]@{ Name = $name; Present = $true; State = $service.State; StartMode = $service.StartMode }
        }
    })
    $json = [pscustomobject]@{ Computer = $env:COMPUTERNAME; RequireRunning = $running; Warning = $warning; Services = $items } | ConvertTo-Json -Depth 5
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
    Write-Error ("Anwendungsdienstprüfung fehlgeschlagen / Application service audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
