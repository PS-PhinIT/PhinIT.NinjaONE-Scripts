#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Windows-Zeitzone und setzt sie optional auf eine vorgegebene Zeitzonen-ID.
    EN: Audits the Windows time zone and optionally sets it to a given time zone ID.
.DESCRIPTION
    DE: Liest die aktuelle Zeitzone mit Get-TimeZone und vergleicht sie mit TimeZoneId. Die ID wird gegen
        Get-TimeZone -ListAvailable geprüft (z. B. 'W. Europe Standard Time') und in die offizielle Schreibweise
        übernommen. Ohne Opt-in (configTimeZoneAllow=true) wird nichts geändert. Mit Opt-in wird innerhalb von
        ShouldProcess Set-TimeZone -Id ausgeführt und erneut gelesen. Optional (configTimeZoneResyncTime=true) wird nach
        einer erfolgreichen Änderung 'w32tm /resync /nowait' ausgeführt; ein Fehler dabei ist nur eine Warnung (Exit 2).
        Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, Warnings.
    EN: Reads the current time zone with Get-TimeZone and compares it with TimeZoneId. The ID is validated against
        Get-TimeZone -ListAvailable (e.g. 'W. Europe Standard Time') and normalised to its official spelling.
        Without opt-in (configTimeZoneAllow=true) nothing is changed. With opt-in Set-TimeZone -Id runs inside
        ShouldProcess and the zone is read back. Optionally (configTimeZoneResyncTime=true) 'w32tm /resync /nowait'
        runs after a successful change; a failure there is only a warning (exit 2).
        Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, Warnings.
.PARAMETER TimeZoneId
    DE: NinjaOne Text configTimeZoneId; erforderlich; Windows-Zeitzonen-ID (max. 128 Zeichen, keine Steuerzeichen/Wildcards).
    EN: NinjaOne text configTimeZoneId; required; Windows time zone ID (max. 128 characters, no control characters/wildcards).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configTimeZoneAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configTimeZoneAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER ResyncTime
    DE: NinjaOne Checkbox/Text configTimeZoneResyncTime; true/false; Standard false. Nach einer Änderung w32tm /resync /nowait ausführen.
    EN: NinjaOne checkbox/text configTimeZoneResyncTime; true/false; default false. Run w32tm /resync /nowait after a change.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setTimeZone.ps1 -TimeZoneId 'W. Europe Standard Time'
    DE: Nur Prüfung: Exit 2, wenn eine andere Zeitzone eingestellt ist.
    EN: Audit only: exit 2 if a different time zone is set.
.EXAMPLE
    .\setTimeZone.ps1 -TimeZoneId 'W. Europe Standard Time' -Allow true -WhatIf
    DE: Simuliert die Änderung; nichts wird geändert (Exit 0).
    EN: Simulates the change; nothing is changed (exit 0).
.EXAMPLE
    .\setTimeZone.ps1 -TimeZoneId 'GMT Standard Time' -Allow true -ResyncTime true -CustomField timeZoneReport
    DE: Setzt die Zeitzone, synchronisiert die Zeit neu und schreibt das JSON in timeZoneReport.
    EN: Sets the time zone, resynchronises the time and writes the JSON to timeZoneReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Gruppenrichtlinien oder die automatische Zeitzonenerkennung können die Zeitzone später wieder ändern.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Abfrage-, Änderungs-
        oder Verifikationsfehler; 2 = Abweichung ohne Opt-in (Drift), Änderung per -Confirm abgelehnt oder w32tm-Resync fehlgeschlagen.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Group Policy or automatic time zone detection may change the zone again later.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, query, change or
        verification error; 2 = drift without opt-in, change declined via -Confirm or w32tm resync failed.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$TimeZoneId = $env:configTimeZoneId,
    [string]$Allow = $env:configTimeZoneAllow,
    [string]$ResyncTime = $env:configTimeZoneResyncTime,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-BooleanSetting {
    param([string]$Value, [string]$Name)
    $result = $false
    if (-not [bool]::TryParse($Value, [ref]$result)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $result
}
try {
    $TimeZoneId = Resolve-Setting $TimeZoneId ''
    $Allow = Resolve-Setting $Allow 'false'
    $ResyncTime = Resolve-Setting $ResyncTime 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $TimeZoneId -or $TimeZoneId.Length -gt 128 -or $TimeZoneId -match '[\x00-\x1f\x7f*?]') {
        throw 'configTimeZoneId erforderlich (max. 128 Zeichen, keine Steuerzeichen/Wildcards) / required (max. 128 characters, no control characters/wildcards).'
    }
    $allowed = ConvertTo-BooleanSetting $Allow 'configTimeZoneAllow'
    $resync = ConvertTo-BooleanSetting $ResyncTime 'configTimeZoneResyncTime'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $available = @(Get-TimeZone -ListAvailable -ErrorAction Stop | ForEach-Object { [string]$_.Id })
    $desired = $available | Where-Object { $_ -eq $TimeZoneId } | Select-Object -First 1
    if (-not $desired) { throw ('Unbekannte Zeitzonen-ID / Unknown time zone ID: {0}' -f $TimeZoneId) }
    $current = [string](Get-TimeZone -ErrorAction Stop).Id
    $differences = @()
    if ($current -ne $desired) { $differences += ('TimeZoneId: {0} -> {1}' -f $current, $desired) }
    $attempted = $false
    $changed = $false
    $warnings = @()
    if ($allowed -and $current -ne $desired) {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, ('Zeitzone setzen auf {0} / Set time zone to {0}' -f $desired))) {
            $attempted = $true
            Set-TimeZone -Id $desired -ErrorAction Stop
            $changed = $true
            $current = [string](Get-TimeZone -ErrorAction Stop).Id
        }
    }
    $compliant = $current -eq $desired
    if ($changed -and $compliant -and $resync) {
        if ($PSCmdlet.ShouldProcess('w32time', 'Zeit neu synchronisieren / Resynchronise time')) {
            try {
                $global:LASTEXITCODE = 0
                $null = w32tm /resync /nowait
                if ($global:LASTEXITCODE -ne 0) { $warnings += ('w32tm /resync Exitcode / exit code {0}' -f $global:LASTEXITCODE) }
            }
            catch { $warnings += ('w32tm /resync fehlgeschlagen / failed: {0}' -f $_.Exception.Message) }
        }
    }
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }
    elseif ($warnings.Count -gt 0) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'TimeZone'; Current = $current; Desired = $desired
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        ResyncTime = $resync; VerificationFailed = $verificationFailed; Differences = @($differences); Warnings = @($warnings)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit $exitCode
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
