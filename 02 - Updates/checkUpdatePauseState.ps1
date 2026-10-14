#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob Windows Updates lokal, per Gruppenrichtlinie oder MDM pausiert sind.
    EN: Checks whether Windows updates are paused locally, by Group Policy or by MDM.
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings (PauseUpdatesStart-/ExpiryTime,
        PauseFeatureUpdatesStart-/EndTime, PauseQualityUpdatesStart-/EndTime; Pause über die
        Einstellungen-App), HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate und
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update (PauseQualityUpdates,
        PauseFeatureUpdates, Pause*UpdatesStartTime). Eine lokale Pause ist aktiv, solange das
        Ende in der Zukunft liegt. Eine Richtlinienpause gilt 35 Tage ab Startdatum; ist
        Pause*Updates=1 ohne Startdatum gesetzt, gilt sie als aktiv (Ende unbekannt), ein
        expliziter Wert 0 deaktiviert sie. Datumswerte werden kulturunabhängig (ISO 8601) gelesen.
        Exit 0 = keine aktive Pause, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = mindestens
        eine aktive Pause (Qualitäts-, Funktions- oder alle Updates).
    EN: Reads HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings (PauseUpdatesStart-/ExpiryTime,
        PauseFeatureUpdatesStart-/EndTime, PauseQualityUpdatesStart-/EndTime; pause from the
        Settings app), HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate and
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update (PauseQualityUpdates,
        PauseFeatureUpdates, Pause*UpdatesStartTime). A local pause is active while its end lies
        in the future. A policy pause lasts 35 days from its start date; Pause*Updates=1 without
        a start date counts as active (end unknown), an explicit value 0 disables it. Dates are
        parsed culture-independently (ISO 8601). Exit 0 = no active pause, 1 = input, query or
        write error, 2 = at least one active pause (quality, feature or all updates).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\checkUpdatePauseState.ps1
    DE: Warnt (Exit 2), wenn Updates pausiert sind.
    EN: Warns (exit 2) if updates are paused.
.EXAMPLE
    .\checkUpdatePauseState.ps1 -CustomField updatePauseState
    DE: Schreibt den JSON-Bericht ins MultiLine-Feld updatePauseState.
    EN: Writes the JSON report to the MultiLine field updatePauseState.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend; hebt keine Pause auf.
        Exit 0 = OK, 1 = Fehler, 2 = pausiert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only; does not resume updates.
        Exit 0 = OK, 1 = error, 2 = paused.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryValueTable {
    param([string]$Path, [string[]]$Names)
    $table = [ordered]@{}
    $item = $null
    if (Test-Path -LiteralPath $Path) { $item = Get-ItemProperty -LiteralPath $Path }
    foreach ($name in $Names) {
        $value = $null
        if ($null -ne $item -and $item.PSObject.Properties[$name]) { $value = $item.$name }
        $table[$name] = $value
    }
    $table
}
function ConvertTo-UtcDate {
    param($Value)
    $parsed = [DateTime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if ($null -ne $Value -and [DateTime]::TryParse(([string]$Value).Trim(), [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    return $null
}
try {
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $nowUtc = [DateTime]::UtcNow
    $ux = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Names @('PauseUpdatesStartTime', 'PauseUpdatesExpiryTime',
        'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime')
    $policyNames = @('PauseQualityUpdates', 'PauseQualityUpdatesStartTime', 'PauseFeatureUpdates', 'PauseFeatureUpdatesStartTime')
    $gpo = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Names $policyNames
    $mdm = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -Names $policyNames
    $active = [System.Collections.Generic.List[object]]::new()
    foreach ($pair in @(@('All', 'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime'), @('Feature', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime'),
            @('Quality', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime'))) {
        $end = ConvertTo-UtcDate $ux[$pair[2]]
        if ($null -ne $end -and $end -gt $nowUtc) {
            $start = ConvertTo-UtcDate $ux[$pair[1]]
            $active.Add([pscustomobject]@{ Source = 'Settings'; Kind = $pair[0]; StartUtc = $(if ($start) { $start.ToString('o') }); ExpiryUtc = $end.ToString('o') })
        }
    }
    foreach ($source in @(@('GroupPolicy', $gpo), @('MDM', $mdm))) {
        foreach ($kind in @('Quality', 'Feature')) {
            $flag = [string]$source[1]["Pause$($kind)Updates"]
            $startRaw = $source[1]["Pause$($kind)UpdatesStartTime"]
            if ($flag -eq '0') { continue }
            $start = ConvertTo-UtcDate $startRaw
            if ($null -ne $start) {
                $end = $start.AddDays(35)
                if ($end -gt $nowUtc) {
                    $active.Add([pscustomobject]@{ Source = $source[0]; Kind = $kind; StartUtc = $start.ToString('o'); ExpiryUtc = $end.ToString('o') })
                }
            }
            elseif ($flag -eq '1') {
                $active.Add([pscustomobject]@{ Source = $source[0]; Kind = $kind; StartUtc = $null; ExpiryUtc = $null })
            }
        }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Paused = $active.Count -gt 0; ActivePauses = @($active)
        SettingsApp = $ux; GroupPolicy = $gpo; MdmPolicy = $mdm
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($active.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
