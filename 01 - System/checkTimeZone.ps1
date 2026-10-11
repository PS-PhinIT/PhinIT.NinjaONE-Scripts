#Requires -Version 5.1
<#
.SYNOPSIS
    DE: Liest die Zeitzone und prüft optional eine erwartete Windows-Zeitzonen-ID.
    EN: Reads the time zone and optionally checks an expected Windows time zone ID.
.PARAMETER ExpectedTimeZone
    DE: NinjaOne Text expectedTimeZone, optional; z.B. W. Europe Standard Time.
    EN: NinjaOne Text expectedTimeZone, optional; e.g. W. Europe Standard Time.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField, optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField, optional MultiLine device field.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit; keine Änderung. Parameter vor Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = Abweichung.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit; no changes. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = mismatch.
#>
[CmdletBinding()]
param(
    [string]$ExpectedTimeZone = $env:expectedTimeZone,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $ExpectedTimeZone = $ExpectedTimeZone.Trim()
    if ($ExpectedTimeZone -eq 'null') { $ExpectedTimeZone = '' }
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    # DE: Erwartete IDs gegen die installierten Zeitzonen prüfen.
    # EN: Validate expected IDs against installed time zones.
    if ($ExpectedTimeZone) {
        $available = @(Get-TimeZone -ListAvailable)
        if ($ExpectedTimeZone -notin $available.Id) { throw 'Unbekannte Zeitzonen-ID / Unknown time zone ID.' }
    }
    $zone = Get-TimeZone
    if (-not $zone.Id) { throw 'Zeitzone fehlt / Time zone unavailable.' }
    $mismatch = [bool]($ExpectedTimeZone -and $zone.Id -ne $ExpectedTimeZone)
    $report = [ordered]@{
        Id = $zone.Id
        BaseUtcOffsetMinutes = $zone.BaseUtcOffset.TotalMinutes
        SupportsDaylightSavingTime = $zone.SupportsDaylightSavingTime
        ExpectedId = $ExpectedTimeZone
        Mismatch = $mismatch
    } | ConvertTo-Json
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($mismatch) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
