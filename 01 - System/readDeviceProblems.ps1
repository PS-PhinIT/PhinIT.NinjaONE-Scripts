#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Listet Geräte mit Problemcode im Geräte-Manager (ConfigManagerErrorCode).
    EN: Lists devices with a Device Manager problem code (ConfigManagerErrorCode).
.DESCRIPTION
    DE: Liest Win32_PnPEntity per CIM mit ConfigManagerErrorCode ungleich 0 und meldet
        Name, Klasse, Code, Klartext (z. B. 10 = Start nicht möglich, 22 = deaktiviert,
        28 = Treiber fehlt, 43 = Fehler gemeldet) und Geräte-ID (gekürzt). Codes aus
        IgnoreCodes werden nur gezählt. Liste auf MaxRecords begrenzt und gekürzt,
        bis der Bericht 4000 Zeichen nicht überschreitet (Truncated, TotalProblems).
        Ausgabe als JSON, optional in ein MultiLine-Feld. Exit 0 = keine (nicht
        ignorierten) Problemgeräte, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = mindestens ein Problemgerät. Nur lesend.
    EN: Reads Win32_PnPEntity via CIM with ConfigManagerErrorCode not 0 and reports
        name, class, code, text (e.g. 10 = cannot start, 22 = disabled, 28 = no
        driver, 43 = reported problems) and device ID (shortened). Codes listed in
        IgnoreCodes are only counted. The list is bounded by MaxRecords and shrinks
        until the report fits 4000 characters (Truncated, TotalProblems).
        Outputs JSON, optionally to a MultiLine field. Exit 0 = no (non-ignored)
        problem devices, 1 = input, query or write error, 2 = at least one problem
        device. Read-only.
.PARAMETER MaxRecords
    DE: NinjaOne Integer systemDeviceMaxRecords, 1..100; Standard 25.
    EN: NinjaOne Integer systemDeviceMaxRecords, 1..100; default 25.
.PARAMETER IgnoreCodes
    DE: NinjaOne Text systemDeviceIgnoreCodes: kommagetrennte Codes 1..99 (z. B. 22,45); Standard leer.
    EN: NinjaOne text systemDeviceIgnoreCodes: comma-separated codes 1..99 (e.g. 22,45); default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readDeviceProblems.ps1
    DE: Alle Geräte mit Problemcode (max. 25) melden.
    EN: Report all devices with a problem code (max. 25).
.EXAMPLE
    .\readDeviceProblems.ps1 -IgnoreCodes '22,45' -MaxRecords 10 -CustomField deviceProblems
    DE: Deaktivierte und nicht verbundene Geräte ignorieren; JSON ins Feld deviceProblems.
    EN: Ignore disabled and disconnected devices; JSON to the field deviceProblems.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = Problemgeräte gefunden. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = problem devices found. Read-only.
#>
[CmdletBinding()]
param(
    [string]$MaxRecords = $env:systemDeviceMaxRecords,
    [string]$IgnoreCodes = $env:systemDeviceIgnoreCodes,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MaxRecords = ([string]$MaxRecords).Trim()
    $IgnoreCodes = ([string]$IgnoreCodes).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '25' }
    if ($IgnoreCodes -ieq 'null') { $IgnoreCodes = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'systemDeviceMaxRecords: 1..100 erforderlich / required.'
    }
    $ignored = @()
    if ($IgnoreCodes) {
        if ($IgnoreCodes -notmatch '^\d{1,2}(\s*,\s*\d{1,2})*$') { throw 'systemDeviceIgnoreCodes: z. B./e.g. 22,45.' }
        $ignored = @($IgnoreCodes -split '\s*,\s*' | ForEach-Object { [int]$_ })
        if (@($ignored | Where-Object { $_ -lt 1 -or $_ -gt 99 }).Count -gt 0) { throw 'systemDeviceIgnoreCodes: 1..99.' }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $codeMap = @{ 1 = 'Not configured correctly'; 3 = 'Driver corrupted or low resources'; 10 = 'Cannot start'
        12 = 'Insufficient free resources'; 14 = 'Restart required'; 18 = 'Reinstall drivers'
        19 = 'Registry configuration incomplete or damaged'; 21 = 'Being removed'; 22 = 'Disabled'
        24 = 'Not present, not working or missing drivers'; 28 = 'Drivers not installed'; 29 = 'Disabled by firmware'
        31 = 'Driver could not be loaded'; 32 = 'Driver service disabled'; 33 = 'Cannot determine resources'
        34 = 'Manual configuration required'; 35 = 'Firmware lacks information'; 36 = 'IRQ translation failed'
        37 = 'Driver initialization failed'; 38 = 'Previous driver instance still loaded'; 39 = 'Driver corrupted or missing'
        40 = 'Driver service registry key invalid'; 41 = 'Driver loaded but hardware not found'; 42 = 'Duplicate device'
        43 = 'Device reported problems'; 44 = 'Shut down by application or service'; 45 = 'Not connected'
        46 = 'Unavailable during shutdown'; 47 = 'Prepared for safe removal'; 48 = 'Driver blocked'
        49 = 'Registry size limit exceeded'; 50 = 'Cannot apply properties'; 51 = 'Waiting on another device'
        52 = 'Driver signature cannot be verified'; 53 = 'Reserved by kernel debugger'; 54 = 'Failed and is being reset' }
    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $null -ne $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0 })
    $relevant = @($devices | Where-Object { $ignored -notcontains [int]$_.ConfigManagerErrorCode } |
        Sort-Object { [int]$_.ConfigManagerErrorCode }, { [string]$_.Name })
    $ignoredCount = $devices.Count - $relevant.Count
    $records = @(foreach ($device in ($relevant | Select-Object -First $limit)) {
        $code = [int]$device.ConfigManagerErrorCode
        $name = (([string]$device.Name) -replace '[\x00-\x1F\x7F]', '').Trim()
        $id = (([string]$device.PNPDeviceID) -replace '[\x00-\x1F\x7F]', '')
        [pscustomobject]@{
            Name = $name.Substring(0, [Math]::Min(100, $name.Length))
            Class = (([string]$device.PNPClass) -replace '[^A-Za-z0-9_\-]', '')
            Code = $code
            Problem = $(if ($codeMap.ContainsKey($code)) { $codeMap[$code] } else { 'Other' })
            DeviceId = $id.Substring(0, [Math]::Min(120, $id.Length))
        }
    })
    do {
        $truncated = $records.Count -lt $relevant.Count
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            TotalProblems = $relevant.Count; IgnoredCodes = $ignored; IgnoredDevices = $ignoredCount
            Reported = $records.Count; Truncated = $truncated; Devices = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($relevant.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
