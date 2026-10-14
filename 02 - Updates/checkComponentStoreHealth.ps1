#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft den Komponentenspeicher (WinSxS) schnell und schreibgeschützt mit DISM /CheckHealth.
    EN: Checks the component store (WinSxS) quickly and read-only with DISM /CheckHealth.
.DESCRIPTION
    DE: Führt "dism /Online /Cleanup-Image /CheckHealth /English" aus. CheckHealth liest nur
        den bereits protokollierten Zustand (keine Reparatur, kein ScanHealth, kein Download)
        und dauert typischerweise Sekunden. Ausgewertet werden der Exitcode und die per /English
        erzwungene englische Ausgabe: "No component store corruption detected" = Healthy,
        "The component store is repairable" = Repairable, "cannot be repaired" bzw. Exitcode
        14098 (ERROR_SXS_COMPONENT_STORE_CORRUPT) = Corrupt. Kein Registry-Heuristikwert.
        Exit 0 = Healthy, 1 = Eingabe- oder Schreibfehler, DISM-Fehler (z. B. 740 keine
        Administratorrechte, laufende Wartungsvorgänge) oder nicht erkannter Status,
        2 = Komponentenspeicher reparierbar oder beschädigt.
    EN: Runs "dism /Online /Cleanup-Image /CheckHealth /English". CheckHealth only reads the
        already logged state (no repair, no ScanHealth, no download) and typically takes
        seconds. The exit code and the English output forced by /English are evaluated:
        "No component store corruption detected" = Healthy, "The component store is repairable"
        = Repairable, "cannot be repaired" or exit code 14098 (ERROR_SXS_COMPONENT_STORE_CORRUPT)
        = Corrupt. No registry heuristic is used. Exit 0 = Healthy, 1 = input or write error,
        DISM error (e.g. 740 not elevated, servicing operation in progress) or unrecognised
        status, 2 = component store repairable or corrupt.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\checkComponentStoreHealth.ps1
    DE: Warnt (Exit 2), wenn DISM einen reparierbaren oder beschädigten Speicher meldet.
    EN: Warns (exit 2) if DISM reports a repairable or corrupt store.
.EXAMPLE
    .\checkComponentStoreHealth.ps1 -CustomField componentStoreHealth
    DE: Schreibt den JSON-Bericht ins MultiLine-Feld componentStoreHealth.
    EN: Writes the JSON report to the MultiLine field componentStoreHealth.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend; Reparatur separat mit
        /RestoreHealth. Sprachhinweis: /English erzwingt englische Meldungen; fehlt die
        Unterstützung, endet ein nicht erkannter Text mit Exit 1 statt falschem OK.
        Exit 0 = OK, 1 = Fehler, 2 = reparierbar/beschädigt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only; repair separately with
        /RestoreHealth. Locale caveat: /English forces English messages; if unsupported, an
        unrecognised text ends with exit 1 instead of a false OK.
        Exit 0 = OK, 1 = error, 2 = repairable/corrupt.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    # DE: stderr nicht als Abbruchfehler behandeln. EN: Do not treat stderr as terminating error.
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = 0
        $output = @(dism /Online /Cleanup-Image /CheckHealth /English 2>&1 | ForEach-Object { [string]$_ })
        $code = [int]$LASTEXITCODE
    }
    finally { $ErrorActionPreference = 'Stop' }
    $lines = @($output | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\[[=\s\d.%]*\]$' })
    $text = $lines -join "`n"
    $status = 'Unknown'
    if ($code -eq 14098 -or $text -match 'cannot be repaired|component store has been corrupted') { $status = 'Corrupt' }
    elseif ($text -match 'component store is repairable') { $status = 'Repairable' }
    elseif ($code -eq 0 -and $text -match 'No component store corruption detected') { $status = 'Healthy' }
    $imageVersion = $null
    $versionLine = $lines | Where-Object { $_ -match '^Image Version:\s*(\S+)' } | Select-Object -First 1
    if ($versionLine -and $versionLine -match '^Image Version:\s*(\S+)') { $imageVersion = $Matches[1] }
    $messages = @($lines | Select-Object -Last 10 | ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 200) } else { $_ } })
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Status = $status; DismExitCode = $code; DismExitCodeHex = ('0x{0:X8}' -f $code)
        ImageVersion = $imageVersion; Messages = $messages
    })
    Write-Output $report
    if ($status -eq 'Unknown') {
        throw ("DISM-Status nicht erkannt / DISM status not recognised (exit code {0})." -f $code)
    }
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($status -ne 'Healthy') { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
