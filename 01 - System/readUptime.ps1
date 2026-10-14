#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest die Windows-Laufzeit und meldet eine konfigurierte Überschreitung.
    EN: Reads Windows uptime and reports a configured threshold violation.
.DESCRIPTION
    DE: Nur Diagnose; startet das Gerät niemals neu. Explizite Parameter haben
        Vorrang vor NinjaOne-Skriptvariablen (Umgebungsvariablen).
    EN: Diagnostics only; never reboots the device. Explicit parameters take
        precedence over NinjaOne script variables (environment variables).
.PARAMETER MaximumUptimeHours
    DE: Ganze Stunden, 1 bis 87600; Standard 720. Variable: maximumUptimeHours.
    EN: Whole hours, 1 to 87600; default 720. Variable: maximumUptimeHours.
.PARAMETER CustomField
    DE: Optionales Geräteattribut vom Typ Integer. Variable: uptimeCustomField.
    EN: Optional device custom field of type Integer. Variable: uptimeCustomField.
.EXAMPLE
    .\readUptime.ps1 -MaximumUptimeHours 168
    DE: Warnt (Exit 2), wenn das Gerät seit mindestens 7 Tagen (168 h) läuft.
    EN: Warns (exit 2) if the device has been up for at least 7 days (168 h).
.EXAMPLE
    .\readUptime.ps1 -MaximumUptimeHours 720 -CustomField uptimeHours
    DE: Standardgrenzwert 720 h; Laufzeit in Stunden in das Integer-Feld uptimeHours schreiben.
    EN: Default threshold 720 h; write uptime in hours to the Integer field uptimeHours.
.NOTES
    DE: Als SYSTEM ausführen. Exit 0 = OK, 1 = Fehler, 2 = Grenzwert erreicht.
    EN: Run as SYSTEM. Exit 0 = OK, 1 = error, 2 = threshold reached.
#>
[CmdletBinding()]
param(
    [string]$MaximumUptimeHours = $env:maximumUptimeHours,
    [string]$CustomField = $env:uptimeCustomField
)

$ErrorActionPreference = 'Stop'
try {
    # DE: NinjaOne verwendet teils "null" für leere Variablen.
    # EN: NinjaOne sometimes uses "null" for empty variables.
    if ([string]::IsNullOrWhiteSpace($MaximumUptimeHours) -or $MaximumUptimeHours.Trim() -eq 'null') {
        $MaximumUptimeHours = '720'
    }
    $limit = 0
    if (-not [int]::TryParse($MaximumUptimeHours, [ref]$limit) -or $limit -lt 1 -or $limit -gt 87600) {
        throw 'maximumUptimeHours: 1..87600 erforderlich / required.'
    }
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }

    # DE: CIM liefert den letzten Start als DateTime; UTC vermeidet Sommerzeitfehler.
    # EN: CIM returns the last boot as DateTime; UTC avoids daylight-saving errors.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not $os.LastBootUpTime) { throw 'Startzeit fehlt / Boot time missing.' }
    $elapsed = [DateTime]::UtcNow - $os.LastBootUpTime.ToUniversalTime()
    if ($elapsed.TotalHours -lt 0) { throw 'Startzeit liegt in der Zukunft / Boot time is in the future.' }
    $hours = [int][Math]::Floor($elapsed.TotalHours)
    Write-Output ("Laufzeit / Uptime: {0} h; Limit: {1} h" -f $hours, $limit)

    # DE: Das optionale Feld muss existieren und für Skripte schreibbar sein.
    # EN: The optional field must exist and allow script write access.
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $hours | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom Field konnte nicht geschrieben werden / Custom field write failed.' }
    }
    if ($elapsed.TotalHours -ge $limit) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}