#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Listet die Top-N-Prozesse nach CPU-Zeit oder Arbeitsspeicher (informativ).
    EN: Lists the top N processes by CPU time or working set (informational).
.DESCRIPTION
    DE: Liest Get-Process und meldet Name, PID, kumulierte CPU-Zeit (Sekunden),
        Working Set und privaten Speicher (MiB) sowie Handles der Top-N-Prozesse,
        sortiert nach Cpu (kumulierte CPU-Zeit seit Prozessstart, keine
        Momentauslastung) oder Memory (Working Set). Keine Befehlszeilen, Pfade
        oder Benutzer. Die Liste wird gekürzt, bis der Bericht 4000 Zeichen nicht
        überschreitet (Truncated, TotalProcesses). Ausgabe als JSON, optional in ein
        MultiLine-Feld. Exit 0 = Erfolg, 1 = Eingabe-, Abfrage- oder Schreibfehler;
        Exit 2 wird nicht verwendet. Nur lesend.
    EN: Reads Get-Process and reports name, PID, cumulative CPU time (seconds),
        working set and private memory (MiB) and handles of the top N processes,
        sorted by Cpu (cumulative CPU time since process start, not current
        load) or Memory (working set). No command lines, paths or users. The list
        shrinks until the report fits 4000 characters (Truncated,
        TotalProcesses). Outputs JSON, optionally to a MultiLine field.
        Exit 0 = success, 1 = input, query or write error; exit 2 is not used.
        Read-only.
.PARAMETER Top
    DE: NinjaOne Integer systemTopProcessCount, 1..50; Standard 10.
    EN: NinjaOne Integer systemTopProcessCount, 1..50; default 10.
.PARAMETER SortBy
    DE: NinjaOne Dropdown/Text systemTopProcessSortBy, Cpu oder Memory; Standard Cpu.
    EN: NinjaOne dropdown/text systemTopProcessSortBy, Cpu or Memory; default Cpu.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readTopProcesses.ps1
    DE: Top 10 Prozesse nach CPU-Zeit.
    EN: Top 10 processes by CPU time.
.EXAMPLE
    .\readTopProcesses.ps1 -Top 20 -SortBy Memory -CustomField topProcesses
    DE: Top 20 nach Working Set; JSON ins Feld topProcesses.
    EN: Top 20 by working set; JSON to the field topProcesses.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit (sonst fehlen Werte von 64-Bit-Prozessen).
        Parameter überschreiben Variablen. Exit 0 = OK, 1 = Fehler. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit (otherwise 64-bit process values may be missing).
        Parameters override variables. Exit 0 = OK, 1 = error. Read-only.
#>
[CmdletBinding()]
param(
    [string]$Top = $env:systemTopProcessCount,
    [string]$SortBy = $env:systemTopProcessSortBy,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $Top = ([string]$Top).Trim()
    $SortBy = ([string]$SortBy).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $Top -or $Top -ieq 'null') { $Top = '10' }
    if (-not $SortBy -or $SortBy -ieq 'null') { $SortBy = 'Cpu' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $limit = 0
    if (-not [int]::TryParse($Top, [ref]$limit) -or $limit -lt 1 -or $limit -gt 50) {
        throw 'systemTopProcessCount: 1..50 erforderlich / required.'
    }
    if ($SortBy -notin @('Cpu', 'Memory')) { throw 'systemTopProcessSortBy: Cpu oder/or Memory.' }
    if ($SortBy -ieq 'Memory') { $SortBy = 'Memory' } else { $SortBy = 'Cpu' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $all = @(Get-Process -ErrorAction Stop | ForEach-Object {
        $name = (([string]$_.ProcessName) -replace '[\x00-\x1F\x7F]', '')
        $cpu = 0.0
        if ($null -ne $_.CPU) { $cpu = [double]$_.CPU }
        [pscustomobject]@{
            Name = $name.Substring(0, [Math]::Min(64, $name.Length))
            Id = [int]$_.Id
            CpuSeconds = [Math]::Round($cpu, 1)
            WorkingSetMiB = [Math]::Round([double]$_.WorkingSet64 / 1MB, 1)
            PrivateMiB = [Math]::Round([double]$_.PrivateMemorySize64 / 1MB, 1)
            Handles = [int]$_.HandleCount
        }
    })
    if ($all.Count -eq 0) { throw 'Keine Prozesse / No processes.' }
    if ($SortBy -eq 'Cpu') { $key = 'CpuSeconds' } else { $key = 'WorkingSetMiB' }
    $records = @($all | Sort-Object -Property @{ Expression = $key; Descending = $true }, @{ Expression = 'Id'; Descending = $false } |
        Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            SortBy = $SortBy; Requested = $limit; TotalProcesses = $all.Count
            Reported = $records.Count; Truncated = ($records.Count -lt [Math]::Min($limit, $all.Count))
            Processes = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -le 1) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
