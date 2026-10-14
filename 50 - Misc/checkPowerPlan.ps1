#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest den aktiven Energiesparplan und vergleicht ihn optional mit einem Sollwert.
    EN: Reads the active power plan and optionally compares it with an expected plan.
.DESCRIPTION
    DE: Primär per CIM root/cimv2/power Win32_PowerPlan (IsActive = TRUE, GUID aus
        InstanceID). Falls nicht verfügbar: powercfg /getactivescheme; die GUID wird
        sprachunabhängig per Regex gelesen, der Name in Klammern ist lokalisiert.
        ExpectedPlan ist eine GUID oder ein bekannter Name: Balanced
        (381b4222-f694-41f0-9685-ff5bb260df2e), HighPerformance
        (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c), PowerSaver
        (a1841308-3541-4fab-bc81-f71556f20b4a), Ultimate
        (e9a42b02-d5df-448d-aa00-03f14749eb61). Kopierte/eigene Pläne haben eigene
        GUIDs und müssen per GUID angegeben werden. Nur lesend, keine Planänderung.
    EN: Primarily via CIM root/cimv2/power Win32_PowerPlan (IsActive = TRUE, GUID from
        InstanceID). If unavailable: powercfg /getactivescheme; the GUID is parsed
        locale-independently via regex, the name in parentheses is localized.
        ExpectedPlan is a GUID or a known name: Balanced
        (381b4222-f694-41f0-9685-ff5bb260df2e), HighPerformance
        (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c), PowerSaver
        (a1841308-3541-4fab-bc81-f71556f20b4a), Ultimate
        (e9a42b02-d5df-448d-aa00-03f14749eb61). Duplicated/custom plans have their own
        GUIDs and must be given by GUID. Read-only, the plan is never changed.
.PARAMETER ExpectedPlan
    DE: NinjaOne Text powerExpectedPlan: GUID oder Balanced/HighPerformance/PowerSaver/Ultimate; leer = nur melden.
    EN: NinjaOne Text powerExpectedPlan: GUID or Balanced/HighPerformance/PowerSaver/Ultimate; empty = report only.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\checkPowerPlan.ps1
    DE: Meldet den aktiven Energiesparplan (Exit 0).
    EN: Reports the active power plan (exit 0).
.EXAMPLE
    .\checkPowerPlan.ps1 -ExpectedPlan HighPerformance -CustomField powerPlanReport
    DE: Exit 2, wenn nicht "Höchstleistung" aktiv ist; JSON in powerPlanReport.
    EN: Exit 2 if "High performance" is not active; JSON to powerPlanReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = gelesen und (falls gesetzt) passend, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = aktiver Plan weicht von ExpectedPlan ab.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = read and (if set) matching, 1 = input/query/write error,
        2 = active plan differs from ExpectedPlan.
#>
[CmdletBinding()]
param(
    [string]$ExpectedPlan = $env:powerExpectedPlan,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $ExpectedPlan = ([string]$ExpectedPlan).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($ExpectedPlan -ieq 'null') { $ExpectedPlan = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $known = [ordered]@{
        Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'; HighPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        PowerSaver = 'a1841308-3541-4fab-bc81-f71556f20b4a'; Ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    }
    $guidPattern = '[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}'
    $expectedGuid = ''
    if ($ExpectedPlan) {
        $match = @($known.Keys | Where-Object { $_ -ieq $ExpectedPlan })
        if ($match.Count -eq 1) { $expectedGuid = $known[$match[0]] }
        elseif ($ExpectedPlan -match "^\{?($guidPattern)\}?$") { $expectedGuid = $Matches[1].ToLowerInvariant() }
        else { throw 'powerExpectedPlan: GUID oder Balanced/HighPerformance/PowerSaver/Ultimate / GUID or known name required.' }
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $activeGuid = ''
    $activeName = ''
    $source = 'CIM'
    try {
        $plan = @(Get-CimInstance -Namespace 'root/cimv2/power' -ClassName Win32_PowerPlan -Filter 'IsActive = TRUE' -ErrorAction Stop) | Select-Object -First 1
        if ($null -ne $plan -and [string]$plan.InstanceID -match $guidPattern) {
            $activeGuid = $Matches[0].ToLowerInvariant()
            $activeName = [string]$plan.ElementName
        }
    }
    catch { $activeGuid = '' }
    if (-not $activeGuid) {
        $source = 'powercfg'
        # DE: stderr unter PS 5.1 nicht als Abbruch werten; Exitcode selbst prüfen.
        # EN: Do not treat stderr as terminating under PS 5.1; check the exit code instead.
        $global:LASTEXITCODE = 0
        $ErrorActionPreference = 'Continue'
        try {
            $lines = @(powercfg /getactivescheme 2>&1)
            $code = $global:LASTEXITCODE
        }
        finally { $ErrorActionPreference = 'Stop' }
        $text = ($lines | ForEach-Object { "$_" }) -join ' '
        if ($code -ne 0 -or $text -notmatch "($guidPattern)") { throw ('powercfg fehlgeschlagen / failed (exit {0}).' -f $code) }
        $activeGuid = $Matches[1].ToLowerInvariant()
        if ($text -match '\(([^)]{1,100})\)\s*$') { $activeName = $Matches[1] }
    }
    $knownName = @($known.Keys | Where-Object { $known[$_] -eq $activeGuid }) | Select-Object -First 1
    $mismatch = [bool]($expectedGuid -and $expectedGuid -ne $activeGuid)
    $report = [ordered]@{
        Source = $source; ActivePlanGuid = $activeGuid; ActivePlanName = ($activeName -replace '[\x00-\x1F\x7F]', '')
        KnownPlan = [string]$knownName; ExpectedPlan = $ExpectedPlan; ExpectedPlanGuid = $expectedGuid; Mismatch = $mismatch
    } | ConvertTo-Json -Depth 3 -Compress
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($mismatch) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
