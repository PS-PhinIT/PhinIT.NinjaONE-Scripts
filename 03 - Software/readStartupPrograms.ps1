#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert Autostart-Einträge (Win32_StartupCommand und HKLM Run/RunOnce), optional mit Allowlist.
    EN: Inventories startup entries (Win32_StartupCommand and HKLM Run/RunOnce), optionally against an allowlist.
.DESCRIPTION
    DE: Kombiniert Win32_StartupCommand (CIM; Startordner, HKLM/HKU Run) mit den Registry-Schlüsseln
        HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run und RunOnce (64- und 32-Bit/WOW6432Node).
        Doppelte Einträge (gleicher Ort und Name) werden zusammengefasst. Standardmäßig wird nur der
        Programmpfad ohne Argumente ausgegeben, da Argumente Geheimnisse enthalten können; vollständige
        Befehle nur mit IncludeCommands=true (max. 300 Zeichen). AllowedNames vergleicht exakte Eintragsnamen
        (Groß-/Kleinschreibung egal). Liste begrenzt (MaxRecords, 4000 Zeichen), unbekannte Einträge zuerst;
        Kürzung allein ist kein Befund. Exit 0 = OK/Inventar, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = Allowlist gesetzt und mindestens ein nicht erlaubter Eintrag gefunden.
    EN: Combines Win32_StartupCommand (CIM; startup folders, HKLM/HKU Run) with the registry keys
        HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run and RunOnce (64- and 32-bit/WOW6432Node).
        Duplicates (same location and name) are merged. By default only the executable path without
        arguments is reported because arguments may contain secrets; full commands only with
        IncludeCommands=true (max. 300 characters). AllowedNames matches exact entry names (case-insensitive).
        Bounded list (MaxRecords, 4000 characters), unknown entries first; truncation alone is not a finding.
        Exit 0 = OK/inventory, 1 = input, query or write error,
        2 = allowlist set and at least one entry not on it.
.PARAMETER AllowedNames
    DE: NinjaOne Text softwareStartupAllowedNames; Standard leer (nur Inventar); 1-100 kommagetrennte exakte
        Namen, je 1-200 Zeichen, gesamt max. 4000; keine Steuerzeichen, * oder ?.
    EN: NinjaOne Text softwareStartupAllowedNames; default empty (inventory only); 1-100 comma-separated exact
        names, each 1-200 characters, max. 4000 total; no control characters, * or ?.
.PARAMETER MaxRecords
    DE: NinjaOne Integer softwareStartupMaxRecords; 1..200; Standard 50.
    EN: NinjaOne Integer softwareStartupMaxRecords; 1..200; default 50.
.PARAMETER IncludeCommands
    DE: NinjaOne Checkbox/Text softwareStartupIncludeCommands; true/false; Standard false.
    EN: NinjaOne checkbox/text softwareStartupIncludeCommands; true/false; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readStartupPrograms.ps1
    DE: Listet bis zu 50 Autostart-Einträge ohne Argumente.
    EN: Lists up to 50 startup entries without arguments.
.EXAMPLE
    .\readStartupPrograms.ps1 -AllowedNames 'SecurityHealth,OneDrive,NinjaRMMAgent' -CustomField startupReport
    DE: Exit 2 bei Einträgen außerhalb der Allowlist; JSON in startupReport.
    EN: Exit 2 for entries outside the allowlist; JSON to startupReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend.
        Win32_StartupCommand sieht HKU-Einträge nur für geladene Profile.
        Exit 0 = OK, 1 = Fehler, 2 = unbekannte Einträge.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
        Win32_StartupCommand only sees HKU entries of loaded profiles.
        Exit 0 = OK, 1 = error, 2 = unknown entries.
#>
[CmdletBinding()]
param(
    [string]$AllowedNames = $env:softwareStartupAllowedNames,
    [string]$MaxRecords = $env:softwareStartupMaxRecords,
    [string]$IncludeCommands = $env:softwareStartupIncludeCommands,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function Get-ExecutablePath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $text = $Command.Trim()
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -gt 1) { return $text.Substring(1, $end - 1) }
        return $text.Trim('"')
    }
    $match = [regex]::Match($text, '^(.+?\.(?:exe|com|cmd|bat|lnk|vbs|js|ps1|dll))(?=[\s,]|$)', 'IgnoreCase')
    if ($match.Success) { return $match.Groups[1].Value }
    return ($text -split '\s+', 2)[0]
}
function Get-ShortText {
    param([string]$Text, [int]$Length)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Length) { return $Text }
    return $Text.Substring(0, $Length)
}
try {
    $AllowedNames = Resolve-Setting $AllowedNames ''
    $MaxRecords = Resolve-Setting $MaxRecords '50'
    $IncludeCommands = Resolve-Setting $IncludeCommands 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'softwareStartupMaxRecords: 1..200.' }
    $withCommands = $false
    if (-not [bool]::TryParse($IncludeCommands, [ref]$withCommands)) { throw 'softwareStartupIncludeCommands: true/false.' }
    $allowed = @()
    if ($AllowedNames) {
        if ($AllowedNames.Length -gt 4000) { throw 'softwareStartupAllowedNames zu lang / too long.' }
        $allowed = @($AllowedNames.Split(',') | ForEach-Object { $_.Trim() })
        if ($allowed.Count -gt 100 -or @($allowed | Where-Object { -not $_ -or $_.Length -gt 200 -or $_ -match '[\x00-\x1f*?]' }).Count -gt 0) {
            throw 'Ungültige Allowlist / Invalid allowlist.'
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $raw = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-CimInstance -ClassName Win32_StartupCommand)) {
        $raw.Add([pscustomobject]@{ Source = 'CIM'; Name = [string]$item.Name; Location = [string]$item.Location; User = [string]$item.User; Command = [string]$item.Command })
    }
    $runKeys = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    $skip = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider', '(default)')
    foreach ($runKey in $runKeys) {
        $path = 'HKLM:\' + $runKey
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try { $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { continue }
        foreach ($property in @($props.PSObject.Properties | Where-Object { $skip -notcontains $_.Name })) {
            $raw.Add([pscustomobject]@{ Source = 'Registry'; Name = [string]$property.Name; Location = 'HKLM\' + $runKey; User = 'Machine'; Command = [string]$property.Value })
        }
    }
    $seen = @{}
    $entries = @(foreach ($entry in $raw) {
        $id = ('{0}|{1}' -f $entry.Location, $entry.Name).ToLowerInvariant()
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $record = [ordered]@{
            Name = Get-ShortText $entry.Name 200; Source = $entry.Source; Location = Get-ShortText $entry.Location 200
            User = Get-ShortText $entry.User 100; Executable = Get-ShortText (Get-ExecutablePath $entry.Command) 260
            Unknown = ($allowed.Count -gt 0 -and $allowed -notcontains $entry.Name)
        }
        if ($withCommands) { $record.Command = Get-ShortText $entry.Command 300 }
        [pscustomobject]$record
    })
    $entries = @($entries | Sort-Object @{ Expression = { -not $_.Unknown } }, Location, Name)
    $unknownCount = @($entries | Where-Object { $_.Unknown }).Count
    $records = @($entries | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; AllowlistActive = $allowed.Count -gt 0; TotalEntries = $entries.Count
            UnknownEntries = $unknownCount; ReportedRecords = $records.Count; Truncated = $records.Count -lt $entries.Count
            Entries = $records
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
    if ($unknownCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
