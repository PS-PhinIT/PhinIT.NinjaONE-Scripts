#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft eine explizite Liste benötigter Dienste, ohne Dienste zu starten.
    EN: Checks an explicit list of required services without starting services.
.DESCRIPTION
    DE: Liest das Dienstinventar einmal per Get-Service und meldet für jeden
        angegebenen Namen den Status (Running, Stopped, ... oder Missing) als JSON;
        optional Export in ein MultiLine-Feld (max. 4000 Zeichen). Dienste werden
        nie gestartet. Exit 0 = alle laufen, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = mindestens ein Dienst fehlt oder läuft nicht.
    EN: Reads the service inventory once via Get-Service and reports the status
        (Running, Stopped, ... or Missing) of each given name as JSON; optional
        export to a MultiLine field (max. 4000 characters). Services are never
        started. Exit 0 = all running, 1 = input, query or write error,
        2 = at least one service is missing or not running.
.PARAMETER ServiceNames
    DE: NinjaOne Text requiredServiceNames: kommagetrennte interne Dienstnamen.
        Pflichtwert, z.B. Spooler,W32Time; max. 20 Namen; keine Wildcards.
    EN: NinjaOne Text requiredServiceNames: comma-separated internal service names.
        Required, e.g. Spooler,W32Time; max. 20 names; no wildcards.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField, optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField, optional MultiLine device field.
.EXAMPLE
    .\checkRequiredServices.ps1 -ServiceNames 'Spooler,W32Time'
    DE: Prüft, ob Spooler und W32Time vorhanden sind und laufen.
    EN: Checks whether Spooler and W32Time exist and are running.
.EXAMPLE
    .\checkRequiredServices.ps1 -ServiceNames 'wuauserv,BITS,WinDefend' -CustomField requiredServicesReport
    DE: Prüft drei Dienste und schreibt den JSON-Bericht in requiredServicesReport.
    EN: Checks three services and writes the JSON report to requiredServicesReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter haben Vorrang.
        Exit 0 = alle laufen, 1 = Fehler, 2 = fehlt/gestoppt. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters take precedence.
        Exit 0 = all running, 1 = error, 2 = missing/stopped. Read-only.
#>
[CmdletBinding()]
param(
    [string]$ServiceNames = $env:requiredServiceNames,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($ServiceNames) -or $ServiceNames.Trim() -eq 'null') {
        throw 'requiredServiceNames erforderlich / required.'
    }
    $names = @($ServiceNames.Split(',') | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if ($names.Count -gt 20) { throw 'Maximal 20 Dienste / Maximum 20 services.' }
    foreach ($name in $names) {
        if ($name.Length -gt 256 -or $name -match '[\x00-\x1F\x7F\\/*?\[\]]' -or -not $name) {
            throw 'Ungültiger Dienstname / Invalid service name.'
        }
    }
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    # DE: Gesamtinventar einmal lesen; fehlende Namen sind Befunde, Abfragefehler nicht.
    # EN: Read inventory once; missing names are findings, query failures are not.
    $services = @(Get-Service)
    $warning = $false
    $records = @(foreach ($name in $names) {
        $match = @($services | Where-Object { $_.Name -eq $name })
        $status = 'Missing'
        if ($match.Count -gt 0) { $status = [string]$match[0].Status }
        if ($status -ne 'Running') { $warning = $true }
        [pscustomobject]@{ Name = $name; Status = $status }
    })
    $report = ConvertTo-Json -InputObject $records -Depth 3
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
