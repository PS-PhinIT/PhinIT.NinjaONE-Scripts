#Requires -Version 5.1

<#
.SYNOPSIS
DE: Updatedienste prüfen; optional laufende Dienste kontrolliert neu starten.
EN: Audit update services; optionally restart running services in a controlled manner.
.DESCRIPTION
DE: Windows SYSTEM, 64-Bit; AllowRepair=true erforderlich. Kein Cache-/Registry-Reset.
EN: Windows SYSTEM, 64-bit; AllowRepair=true required. No cache/registry reset.
DE: Nicht während Updateinstallation nutzen; Starttypen und ursprüngliche Laufzustände bleiben erhalten.
EN: Do not use during update installation; startup types and original running states are preserved.
DE: Optionales MultiLine-CustomField enthält Klartext-JSON (maximal 4000 Zeichen).
EN: Optional MultiLine CustomField contains plain-text JSON (maximum 4000 characters).
.PARAMETER AllowRepair
DE: String mit Boolean-Wert true/false; NinjaOne updateRepairAllowRestart; Standard false; explizite Zustimmung erforderlich.
EN: String containing Boolean true/false; NinjaOne updateRepairAllowRestart; default false; explicit opt-in required.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\repairWindowsUpdate.ps1
DE: Nur Inventur: zeigt den Zustand von BITS und wuauserv, startet nichts neu.
EN: Audit only: shows the state of BITS and wuauserv, restarts nothing.
.EXAMPLE
.\repairWindowsUpdate.ps1 -AllowRepair true -WhatIf
DE: Simuliert den Neustart laufender Updatedienste ohne Änderung.
EN: Simulates restarting running update services without changes.
.EXAMPLE
.\repairWindowsUpdate.ps1 -AllowRepair true -CustomField updateRepairReport
DE: Startet laufende Dienste neu (ohne Rückfrage, ConfirmImpact Medium) und schreibt das JSON in updateRepairReport.
EN: Restarts running services (no prompt, ConfirmImpact Medium) and writes the JSON to updateRepairReport.
.NOTES
DE: Exit 0 Erfolg/Inventur/WhatIf, Exit 1 Fehler. AllowRepair=true bleibt erforderlich.
EN: Exit 0 success/audit/WhatIf, exit 1 error. AllowRepair=true remains required.
DE: ConfirmImpact Medium vermeidet bei Standard-ConfirmPreference High unbeaufsichtigte Rückfragen.
EN: ConfirmImpact Medium avoids unattended prompts with the default ConfirmPreference High.
DE: -WhatIf simuliert Änderungen; -Confirm erzwingt Rückfragen und ist nicht für unbeaufsichtigte NinjaOne-Läufe geeignet.
EN: -WhatIf simulates changes; -Confirm requests prompts and is unsuitable for unattended NinjaOne runs.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$AllowRepair = $env:updateRepairAllowRestart,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $AllowRepair = if ([string]::IsNullOrWhiteSpace($AllowRepair) -or $AllowRepair.Trim() -eq 'null') { '' } else { $AllowRepair.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ($CustomField -and ($CustomField.Length -gt 128 -or $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]*$')) { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows/64-Bit erforderlich / Windows/64-bit required.' }
    if ([string]::IsNullOrWhiteSpace($AllowRepair) -or $AllowRepair.Trim() -eq 'null') { $AllowRepair = 'false' }
    $allow = $false
    if (-not [bool]::TryParse($AllowRepair.Trim(), [ref]$allow)) { throw 'AllowRepair: true/false erforderlich / required.' }
    $states = @()
    foreach ($name in @('BITS', 'wuauserv')) {
        $service = Get-Service -Name $name
        if ($service.Status -notin @('Running', 'Stopped')) { throw "Instabiler Dienststatus / Unstable service state: $name" }
        $states += [pscustomobject]@{ Name = $name; Running = $service.Status -eq 'Running' }
    }
    $restarted = @()
    if ($allow -and $PSCmdlet.ShouldProcess('BITS, wuauserv', 'Laufende Dienste neu starten / Restart running services')) {
        try {
            foreach ($state in $states) {
                if ($state.Running) {
                    Stop-Service -Name $state.Name -ErrorAction Stop
                    (Get-Service -Name $state.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                }
            }
            foreach ($state in $states) {
                if ($state.Running) {
                    Start-Service -Name $state.Name -ErrorAction Stop
                    (Get-Service -Name $state.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                    $restarted += $state.Name
                }
            }
        } finally {
            $restoreErrors = @()
            foreach ($state in $states) {
                try {
                    $service = Get-Service -Name $state.Name
                    if ($state.Running -and $service.Status -ne 'Running') {
                        Start-Service -Name $state.Name -ErrorAction Stop
                        (Get-Service -Name $state.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                    } elseif (-not $state.Running -and $service.Status -ne 'Stopped') {
                        Stop-Service -Name $state.Name -ErrorAction Stop
                        (Get-Service -Name $state.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                    }
                } catch { $restoreErrors += $_.Exception.Message }
            }
            if ($restoreErrors.Count) { throw "Dienstwiederherstellung fehlgeschlagen / Service restoration failed: $($restoreErrors -join '; ')" }
        }
    }
    $after = @(foreach ($state in $states) {
        [pscustomobject]@{ Name = $state.Name; OriginalRunning = $state.Running; CurrentStatus = [string](Get-Service -Name $state.Name).Status }
    })
    $json = [pscustomobject]@{ RepairAllowed = $allow; WhatIf = [bool]$WhatIfPreference; Restarted = $restarted; Services = $after } | ConvertTo-Json -Depth 5
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
    exit 0
} catch {
    Write-Error ("Dienstprüfung fehlgeschlagen / Service audit failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}