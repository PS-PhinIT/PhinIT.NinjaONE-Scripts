#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet begrenzte Status-Metadaten geplanter Aufgaben.
    EN: Reports bounded scheduled task state metadata.
.DESCRIPTION
    DE: Keine Aktionen, Argumente, Benutzer oder Geheimnisse; keine Änderungen.
        TaskPath wird exakt verglichen, ohne Wildcard-Auswertung.
        Gesamtzahl und Kürzung werden angegeben; maximal 4000 Zeichen.
    EN: No actions, arguments, users or secrets; no changes.
        TaskPath is matched exactly without wildcard interpretation.
        Includes total and truncation indicators; at most 4000 characters.
.PARAMETER TaskPath
    DE: Exakter Aufgabenordner; scheduledTaskPath, Standard \.
    EN: Exact task folder; scheduledTaskPath, default \.
.PARAMETER MaxRecords
    DE: 1..100; scheduledTaskMaxRecords, Standard 25.
    EN: 1..100; scheduledTaskMaxRecords, default 25.
.PARAMETER CustomField
    DE: Optionales MultiLine-Geräteattribut; resultCustomField.
    EN: Optional MultiLine device custom field; resultCustomField.
.EXAMPLE
    .\readScheduledTaskState.ps1
    DE: Status der Aufgaben im Stammordner \ (max. 25).
    EN: State of tasks in the root folder \ (max. 25).
.EXAMPLE
    .\readScheduledTaskState.ps1 -TaskPath '\Microsoft\Windows\WindowsUpdate\' -MaxRecords 50 -CustomField scheduledTaskState
    DE: Aufgaben im Ordner WindowsUpdate; JSON in scheduledTaskState.
    EN: Tasks in the WindowsUpdate folder; JSON to scheduledTaskState.
.NOTES
    DE: SYSTEM, 64-Bit-PowerShell. Explizite Parameter vor Umgebungsvariablen.
        Leere Werte verwenden Standards. Exit 0 = Erfolg, 1 = Fehler,
        2 = gekürzt, keine Treffer oder deaktivierte/unbekannte Aufgaben.
    EN: SYSTEM, 64-bit PowerShell. Explicit parameters override environment.
        Empty values use defaults. Exit 0 = success, 1 = error,
        2 = truncated, no matches or disabled/unknown tasks.
#>
[CmdletBinding()]
param(
    [string]$TaskPath = $env:scheduledTaskPath,
    [string]$MaxRecords = $env:scheduledTaskMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $TaskPath = $TaskPath.Trim()
    $MaxRecords = $MaxRecords.Trim()
    $CustomField = $CustomField.Trim()
    if ($TaskPath -eq 'null') { $TaskPath = '' }
    if ($MaxRecords -eq 'null') { $MaxRecords = '' }
    if ($CustomField -eq 'null') { $CustomField = '' }
    if (-not $TaskPath) { $TaskPath = '\' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'MaxRecords muss 1..100 sein / MaxRecords must be 1..100.'
    }
    if ($TaskPath.Length -gt 260 -or $TaskPath -notmatch '^\\(?:[^\\/:*?"<>|\x00-\x1F]+\\)*$') {
        throw 'TaskPath muss mit \ beginnen/enden / TaskPath must start/end with \.'
    }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw 'Get-ScheduledTask fehlt / is unavailable.'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $tasks = @(Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.TaskPath -eq $TaskPath } |
        Select-Object TaskPath, TaskName, @{ Name = 'State'; Expression = { [string]$_.State } } |
        Sort-Object TaskName)
    $disabled = @($tasks | Where-Object { $_.State -eq 'Disabled' }).Count
    $unknown = @($tasks | Where-Object { $_.State -notin @('Disabled', 'Queued', 'Ready', 'Running') }).Count
    $records = @($tasks | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $tasks.Count
        $report = [ordered]@{
            TaskPath = $TaskPath; TotalMatchingTasks = $tasks.Count
            DisabledTasks = $disabled; UnknownStateTasks = $unknown
            ReportedRecords = $records.Count; Truncated = $truncated; Tasks = $records
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($truncated -or $tasks.Count -eq 0 -or $disabled -gt 0 -or $unknown -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
