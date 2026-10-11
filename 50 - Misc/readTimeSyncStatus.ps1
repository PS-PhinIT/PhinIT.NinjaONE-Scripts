#Requires -Version 5.1
<#
.SYNOPSIS
    DE: Liest den Windows-Zeitsynchronisationsstatus mit w32tm /query /status.
    EN: Reads Windows time synchronization status using w32tm /query /status.
.DESCRIPTION
    DE: Keine Synchronisation, Dienstaktion oder Konfigurationsänderung.
        Lokalisierte w32tm-Ausgabe wird unverändert als Text gemeldet.
        Exit 0 bestätigt die Abfrage, nicht die Genauigkeit der Uhrzeit.
        Über 4000 Zeichen wird mit Fehler abgebrochen.
    EN: No synchronization, service action or configuration changes.
        Localized w32tm output is reported verbatim as text.
        Exit 0 confirms the query, not clock accuracy.
        Reports over 4000 characters fail explicitly.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen.
        Exit 0 = Abfrage erfolgreich, 1 = Fehler, 2 = leere Ausgabe.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment.
        Exit 0 = successful query, 1 = error, 2 = empty output.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $CustomField = $CustomField.Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { throw 'SystemRoot fehlt / is missing.' }
    $executable = Join-Path $env:SystemRoot 'System32\w32tm.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'w32tm.exe fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    # DE: Feste, ausschließlich lesende Argumente; keine Benutzereingabe.
    # EN: Fixed, read-only arguments; no user-supplied command arguments.
    $global:LASTEXITCODE = 0
    $lines = @(& $executable /query /status 2>&1)
    $queryExitCode = $global:LASTEXITCODE
    $text = ($lines | ForEach-Object { "$_" }) -join [Environment]::NewLine
    if ($queryExitCode -ne 0) {
        throw ("w32tm-Abfrage fehlgeschlagen / w32tm query failed (exit {0}): {1}" -f $queryExitCode, $text.Substring(0, [Math]::Min(1000, $text.Length)))
    }
    $report = "w32tm /query /status; ExitCode: $queryExitCode`r`n$text"
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
