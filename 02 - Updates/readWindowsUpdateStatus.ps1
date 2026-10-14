#Requires -Version 5.1

<#
.SYNOPSIS
DE: Lokalen Updateverlauf und Neustartstatus lesen, ohne Updatesuche.
EN: Read local update history and reboot status without searching for updates.
.DESCRIPTION
DE: Als Windows SYSTEM in 64-Bit-PowerShell ausführen. historyCount: 1-200.
EN: Run as Windows SYSTEM in 64-bit PowerShell. historyCount: 1-200.
DE: CustomField benötigt ein beschreibbares MultiLine-Feld; JSON als Klartext.
EN: CustomField requires a writable MultiLine field; JSON is plain text.
DE: Exit 0 = OK, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = Neustart ausstehend oder Verlaufseintrag mit ResultCode 3/4/5 (mit Fehlern/fehlgeschlagen/abgebrochen).
EN: Exit 0 = OK, 1 = input, query or write error, 2 = reboot pending or history entry with ResultCode 3/4/5 (succeeded with errors/failed/aborted).
.PARAMETER HistoryCount
DE: String; NinjaOne updateStatusHistoryCount; Standard 20; ganze Zahl 1-200.
EN: String; NinjaOne updateStatusHistoryCount; default 20; integer 1-200.
.PARAMETER CustomField
DE: String; NinjaOne resultCustomField; Standard leer; MultiLine-Feldname, 1-128 Zeichen, Buchstabe zuerst, danach Buchstaben/Ziffern/Unterstrich.
EN: String; NinjaOne resultCustomField; default empty; MultiLine field name, 1-128 characters, letter first, then letters/digits/underscore.
.EXAMPLE
.\readWindowsUpdateStatus.ps1 -HistoryCount 10
DE: Zeigt die letzten 10 Verlaufseinträge und den Neustartstatus.
EN: Shows the last 10 history entries and the reboot status.
.EXAMPLE
.\readWindowsUpdateStatus.ps1 -HistoryCount 50 -CustomField updateStatusReport
DE: Liest 50 Einträge und schreibt das JSON in updateStatusReport (max. 4000 Zeichen).
EN: Reads 50 entries and writes the JSON to updateStatusReport (max. 4000 characters).
#>
[CmdletBinding()]
param(
    [string]$HistoryCount = $env:updateStatusHistoryCount,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
try {
    $HistoryCount = if ([string]::IsNullOrWhiteSpace($HistoryCount) -or $HistoryCount.Trim() -eq 'null') { '' } else { $HistoryCount.Trim() }
    $CustomField = if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { '' } else { $CustomField.Trim() }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) {
        throw 'Windows/64-Bit erforderlich / Windows/64-bit required.'
    }
    if ([string]::IsNullOrWhiteSpace($HistoryCount) -or $HistoryCount.Trim() -eq 'null') { $HistoryCount = '20' }
    $count = 0
    if (-not [int]::TryParse($HistoryCount.Trim(), [ref]$count) -or $count -lt 1 -or $count -gt 200) {
        throw 'HistoryCount muss 1-200 sein / HistoryCount must be 1-200.'
    }
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $total = $searcher.GetTotalHistoryCount()
    $entries = @()
    if ($total -gt 0) {
        $entries = @($searcher.QueryHistory(0, [Math]::Min($count, $total)) | ForEach-Object {
            [pscustomobject]@{ Date = $_.Date.ToUniversalTime().ToString('o'); Title = $_.Title; ResultCode = [int]$_.ResultCode; HResult = $_.HResult }
        })
    }
    $reboot = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
    $warning = $reboot -or @($entries | Where-Object { $_.ResultCode -in 3, 4, 5 }).Count -gt 0
    $report = [pscustomobject]@{ Computer = $env:COMPUTERNAME; RebootRequired = $reboot; TotalHistory = $total; ReturnedHistory = $entries.Count; History = $entries }
    $json = $report | ConvertTo-Json -Depth 6
    Write-Output $json
    # DE: Keine Kürzung; Schreibfehler sind Fehler. EN: No truncation; write failures are errors.
    $field = if ($null -eq $CustomField) { '' } else { $CustomField.Trim() }
    if ($field -and $field -ne 'null') {
        if ($field.Length -gt 128 -or $field -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
        if ($json.Length -gt 4000) { throw 'JSON überschreitet 4000 Zeichen / JSON exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $field -Value $json -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw "Ninja-Property-Set Exitcode / exit code: $global:LASTEXITCODE" }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Updatebericht fehlgeschlagen / Update report failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}