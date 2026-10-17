#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Analysiert den Komponentenspeicher (WinSxS) mit DISM und bereinigt ihn optional.
    EN: Analyses the component store (WinSxS) with DISM and optionally cleans it up.
.DESCRIPTION
    DE: Inventur: "dism /Online /Cleanup-Image /AnalyzeComponentStore /English". Ausgewertet werden die englischen
        Zeilen "Component Store Cleanup Recommended : Yes/No", "Actual Size of Component Store",
        "Number of Reclaimable Packages" und "Date of Last Cleanup". Ist die Ausgabe nicht auswertbar, wird
        CleanupRecommended als null gemeldet; der Erfolg der Analyse wird sprachunabhängig über den DISM-Exitcode
        bestimmt (ungleich 0 = Exit 1).
        Mit Allow=true und CleanupRecommended ungleich false (also Yes oder unbekannt) wird
        "dism /Online /Cleanup-Image /StartComponentCleanup" (optional mit /ResetBase) über ShouldProcess (-WhatIf)
        ausgeführt. DISM-Exitcode 0 und 3010 gelten als Erfolg (3010 = RebootRequired).
        ACHTUNG /ResetBase: Alle ersetzten Komponenten werden endgültig entfernt; bereits installierte Updates
        können danach NICHT mehr deinstalliert werden (dauerhaft).
        Die Bereinigung kann je nach System viele Minuten dauern. Bericht als JSON, optional in ein MultiLine-Feld.
    EN: Audit: "dism /Online /Cleanup-Image /AnalyzeComponentStore /English". The English lines
        "Component Store Cleanup Recommended : Yes/No", "Actual Size of Component Store",
        "Number of Reclaimable Packages" and "Date of Last Cleanup" are parsed. If the output cannot be parsed,
        CleanupRecommended is reported as null; analysis success is determined locale-independently from the
        DISM exit code (non-zero = exit 1).
        With Allow=true and CleanupRecommended not false (i.e. Yes or unknown),
        "dism /Online /Cleanup-Image /StartComponentCleanup" (optionally with /ResetBase) runs through
        ShouldProcess (-WhatIf). DISM exit codes 0 and 3010 are success (3010 = RebootRequired).
        WARNING /ResetBase: all superseded components are removed permanently; installed updates can NO LONGER be
        uninstalled afterwards (permanent).
        The cleanup may take many minutes. JSON report, optionally written to a MultiLine field.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupComponentStoreAllow; true/false; Standard false. Nur true bereinigt.
    EN: NinjaOne checkbox/text cleanupComponentStoreAllow; true/false; default false. Only true cleans up.
.PARAMETER ResetBase
    DE: NinjaOne Checkbox/Text cleanupComponentStoreResetBase; true/false; Standard false. true ergänzt /ResetBase
        (installierte Updates werden dauerhaft und sind nicht mehr deinstallierbar).
    EN: NinjaOne checkbox/text cleanupComponentStoreResetBase; true/false; default false. true adds /ResetBase
        (installed updates become permanent and can no longer be uninstalled).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\cleanupComponentStore.ps1
    DE: Nur Analyse; Exit 2, wenn DISM eine Bereinigung empfiehlt.
    EN: Analysis only; exit 2 if DISM recommends a cleanup.
.EXAMPLE
    .\cleanupComponentStore.ps1 -Allow true -WhatIf
    DE: Analysiert und simuliert die Bereinigung; StartComponentCleanup wird nicht ausgeführt.
    EN: Analyses and simulates the cleanup; StartComponentCleanup is not run.
.EXAMPLE
    .\cleanupComponentStore.ps1 -Allow true -ResetBase true -CustomField componentStoreReport
    DE: Bereinigt mit /ResetBase (Updates danach nicht mehr deinstallierbar) und schreibt das JSON.
    EN: Cleans up with /ResetBase (updates can no longer be uninstalled) and writes the JSON.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = keine Bereinigung empfohlen/unbekannt (Inventur), Bereinigung erfolgreich (auch 3010) oder -WhatIf.
        Exit 1 = Eingabe-, DISM- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) und DISM empfiehlt eine Bereinigung.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = no cleanup recommended/unknown (audit), cleanup successful (including 3010) or -WhatIf.
        Exit 1 = input, DISM or write error.
        Exit 2 = audit (Allow=false) and DISM recommends a cleanup.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupComponentStoreAllow,
    [string]$ResetBase = $env:cleanupComponentStoreResetBase,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-Boolean {
    param([string]$Value, [string]$Name)
    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw ('{0}: true/false erforderlich / true/false required.' -f $Name) }
    return $parsed
}
function Invoke-Dism {
    param([string[]]$Arguments)
    # DE: stderr nicht als Abbruchfehler behandeln. EN: Do not treat stderr as terminating error.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    $output = @(dism @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = [int]$global:LASTEXITCODE
    $lines = @($output | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\[[=\s\d.%]*\]$' })
    [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}
function Get-DismValue {
    param([string[]]$Lines, [string]$Pattern)
    foreach ($line in $Lines) { if ($line -match $Pattern) { return $Matches[1].Trim() } }
    return $null
}
function Export-Report {
    param([System.Collections.IDictionary]$Data, [string]$Field)
    $json = ConvertTo-Json -Depth 5 -InputObject $Data
    if ($json.Length -gt 4000) { $json = ConvertTo-Json -Depth 5 -Compress -InputObject $Data }
    Write-Output $json
    if ($Field) {
        if ($json.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $json | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}
try {
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupComponentStoreAllow'
    $useResetBase = ConvertTo-Boolean -Value (Resolve-Setting $ResetBase 'false') -Name 'cleanupComponentStoreResetBase'
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $analysis = Invoke-Dism -Arguments @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore', '/English')
    if ($analysis.ExitCode -ne 0) { throw ('DISM AnalyzeComponentStore Exitcode / exit code {0} (0x{0:X8})' -f $analysis.ExitCode) }
    $recommendedText = Get-DismValue -Lines $analysis.Lines -Pattern '^Component Store Cleanup Recommended\s*:\s*(Yes|No)\b'
    $recommended = $null
    if ($recommendedText) { $recommended = $recommendedText -eq 'Yes' }
    $reclaimable = $null
    $reclaimableText = Get-DismValue -Lines $analysis.Lines -Pattern '^Number of Reclaimable Packages\s*:\s*(\d+)'
    if ($reclaimableText) { $reclaimable = [int]$reclaimableText }

    $cleanupRan = $false
    $cleanupCode = $null
    $rebootRequired = $false
    $cleanupLines = @()
    if ($allowed -and $recommended -ne $false) {
        $arguments = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($useResetBase) { $arguments += '/ResetBase' }
        $arguments += '/English'
        $action = if ($useResetBase) { 'StartComponentCleanup /ResetBase ausführen (Updates dauerhaft) / run StartComponentCleanup /ResetBase (updates permanent)' } else { 'StartComponentCleanup ausführen / run StartComponentCleanup' }
        if ($PSCmdlet.ShouldProcess('Component Store (WinSxS)', $action)) {
            $cleanup = Invoke-Dism -Arguments $arguments
            $cleanupRan = $true
            $cleanupCode = $cleanup.ExitCode
            $cleanupLines = @($cleanup.Lines | Select-Object -Last 5 | ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 200) } else { $_ } })
            if ($cleanupCode -notin @(0, 3010)) { throw ('DISM StartComponentCleanup Exitcode / exit code {0} (0x{0:X8}): {1}' -f $cleanupCode, ($cleanupLines -join ' | ')) }
            $rebootRequired = $cleanupCode -eq 3010
        }
    }
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; ResetBase = $useResetBase
        CleanupRecommended = $recommended; RecommendationParsed = ($null -ne $recommended)
        ActualSize = (Get-DismValue -Lines $analysis.Lines -Pattern '^Actual Size of Component Store\s*:\s*(.+)$')
        ReclaimablePackages = $reclaimable
        LastCleanup = (Get-DismValue -Lines $analysis.Lines -Pattern '^Date of Last Cleanup\s*:\s*(.+)$')
        CleanupRan = $cleanupRan; CleanupExitCode = $cleanupCode; RebootRequired = $rebootRequired; CleanupOutput = $cleanupLines
    })
    if (-not $allowed -and $recommended -eq $true) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
