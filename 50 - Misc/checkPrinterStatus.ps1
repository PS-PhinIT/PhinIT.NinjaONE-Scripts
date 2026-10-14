#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Druckwarteschlangendienst, Druckerfehler und hängende Druckaufträge.
    EN: Checks the print spooler service, printer errors and stuck print jobs.
.DESCRIPTION
    DE: Liest per CIM Win32_Service (Spooler), Win32_Printer (PrinterStatus, WorkOffline,
        DetectedErrorState) und Win32_PrintJob (nur Druckername, Alter, Status; keine
        Dokumentnamen oder Besitzer). Fehler = DetectedErrorState 4 (kein Papier),
        6 (kein Toner), 7 (Klappe offen), 8 (Stau), 10 (Service), 11 (Ablage voll).
        Offline = WorkOffline, PrinterStatus 7 oder DetectedErrorState 9. Hängend =
        Auftrag älter als StuckJobMinutes. Ist der Spooler deaktiviert (StartMode
        Disabled, z. B. Härtung auf Servern), wird dies gemeldet und Exit 0 geliefert.
        Viele Treiber melden nur Unknown/Other; Ergebnis ist eine Momentaufnahme.
        JSON, max. 4000 Zeichen (Liste wird gekürzt). Nur lesend, keine Aufträge gelöscht.
    EN: Reads via CIM Win32_Service (Spooler), Win32_Printer (PrinterStatus, WorkOffline,
        DetectedErrorState) and Win32_PrintJob (printer name, age, status only; no
        document names or owners). Error = DetectedErrorState 4 (no paper), 6 (no toner),
        7 (door open), 8 (jammed), 10 (service requested), 11 (output bin full).
        Offline = WorkOffline, PrinterStatus 7 or DetectedErrorState 9. Stuck = job
        older than StuckJobMinutes. If the spooler is disabled (StartMode Disabled, e.g.
        server hardening), this is reported with exit 0. Many drivers only report
        Unknown/Other; results are a snapshot. JSON, max. 4000 characters (list is
        shortened). Read-only, no jobs are deleted.
.PARAMETER StuckJobMinutes
    DE: NinjaOne Integer printerStuckJobMinutes, 1..10080; Standard 30.
    EN: NinjaOne Integer printerStuckJobMinutes, 1..10080; default 30.
.PARAMETER WarnOffline
    DE: NinjaOne Checkbox/Text printerWarnOffline, true/false; Standard false. true = Offline-Drucker lösen Exit 2 aus.
    EN: NinjaOne Checkbox/Text printerWarnOffline, true/false; default false. true = offline printers cause exit 2.
.PARAMETER MaxRecords
    DE: NinjaOne Integer printerMaxRecords, 1..100; Standard 25.
    EN: NinjaOne Integer printerMaxRecords, 1..100; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\checkPrinterStatus.ps1
    DE: Warnt bei gestopptem Spooler, Druckerfehlern oder Aufträgen älter als 30 Minuten.
    EN: Warns on stopped spooler, printer errors or jobs older than 30 minutes.
.EXAMPLE
    .\checkPrinterStatus.ps1 -StuckJobMinutes 60 -WarnOffline true -CustomField printerReport
    DE: 60 Minuten, Offline-Drucker warnen; JSON in printerReport.
    EN: 60 minutes, warn on offline printers; JSON to printerReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK oder Spooler bewusst deaktiviert, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = Spooler fehlt/gestoppt, Drucker im Fehlerzustand, hängende Aufträge
        oder (bei WarnOffline=true) Offline-Drucker.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK or spooler intentionally disabled, 1 = input/query/write error,
        2 = spooler missing/stopped, printer in error state, stuck jobs
        or (with WarnOffline=true) offline printers.
#>
[CmdletBinding()]
param(
    [string]$StuckJobMinutes = $env:printerStuckJobMinutes,
    [string]$WarnOffline = $env:printerWarnOffline,
    [string]$MaxRecords = $env:printerMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-CleanSetting {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInteger {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
        $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0}: {1}..{2} erforderlich / required.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
try {
    $minutes = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $StuckJobMinutes '30') 'printerStuckJobMinutes' 1 10080
    $limit = ConvertTo-BoundedInteger (ConvertTo-CleanSetting $MaxRecords '25') 'printerMaxRecords' 1 100
    $WarnOffline = (ConvertTo-CleanSetting $WarnOffline 'false').ToLowerInvariant()
    if ($WarnOffline -notin @('true', 'false')) { throw 'printerWarnOffline: true/false erforderlich / required.' }
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $statusNames = @{ 1 = 'Other'; 2 = 'Unknown'; 3 = 'Idle'; 4 = 'Printing'; 5 = 'Warmup'; 6 = 'StoppedPrinting'; 7 = 'Offline' }
    $errorNames = @{ 0 = 'Unknown'; 1 = 'Other'; 2 = 'NoError'; 3 = 'LowPaper'; 4 = 'NoPaper'; 5 = 'LowToner'; 6 = 'NoToner'
        7 = 'DoorOpen'; 8 = 'Jammed'; 9 = 'Offline'; 10 = 'ServiceRequested'; 11 = 'OutputBinFull' }
    $spooler = @(Get-CimInstance -ClassName Win32_Service -Filter "Name = 'Spooler'")
    $spoolerState = 'NotInstalled'
    $spoolerStartMode = ''
    if ($spooler.Count -gt 0) { $spoolerState = [string]$spooler[0].State; $spoolerStartMode = [string]$spooler[0].StartMode }
    $spoolerDisabled = $spoolerStartMode -eq 'Disabled'
    $printers = @()
    $jobs = @()
    if ($spoolerState -eq 'Running') {
        $printers = @(Get-CimInstance -ClassName Win32_Printer | Sort-Object Name)
        $jobs = @(Get-CimInstance -ClassName Win32_PrintJob)
    }
    $cutoff = (Get-Date).AddMinutes(-$minutes)
    $records = @(foreach ($printer in $printers) {
        $name = [string]$printer.Name
        $printerJobs = @($jobs | Where-Object { ([string]$_.Name -replace ',\s*\d+$', '') -eq $name })
        $stuck = @($printerJobs | Where-Object { $null -ne $_.TimeSubmitted -and $_.TimeSubmitted -lt $cutoff }).Count
        $errorCode = [int]$printer.DetectedErrorState
        $statusCode = [int]$printer.PrinterStatus
        $state = 'OK'
        if ($errorCode -in @(4, 6, 7, 8, 10, 11)) { $state = 'Error' }
        elseif ([bool]$printer.WorkOffline -or $statusCode -eq 7 -or $errorCode -eq 9) { $state = 'Offline' }
        $statusText = $statusNames[$statusCode]
        if (-not $statusText) { $statusText = [string]$statusCode }
        $errorText = $errorNames[$errorCode]
        if (-not $errorText) { $errorText = [string]$errorCode }
        [pscustomobject]@{
            Name = $name; Network = [bool]$printer.Network; WorkOffline = [bool]$printer.WorkOffline; PrinterStatus = $statusText
            ErrorState = $errorText; State = $state; QueuedJobs = $printerJobs.Count; StuckJobs = $stuck
        }
    })
    $errorPrinters = @($records | Where-Object { $_.State -eq 'Error' }).Count
    $offlinePrinters = @($records | Where-Object { $_.State -eq 'Offline' }).Count
    $stuckJobs = @($jobs | Where-Object { $null -ne $_.TimeSubmitted -and $_.TimeSubmitted -lt $cutoff }).Count
    $ordered = @(@($records | Where-Object { $_.State -ne 'OK' -or $_.StuckJobs -gt 0 }) + @($records | Where-Object { $_.State -eq 'OK' -and $_.StuckJobs -eq 0 }))
    $shown = $limit
    do {
        $list = @($ordered | Select-Object -First $shown)
        $report = [ordered]@{
            SpoolerState = $spoolerState; SpoolerStartMode = $spoolerStartMode; SpoolerDisabled = $spoolerDisabled
            StuckJobMinutes = $minutes; TotalPrinters = $records.Count; ErrorPrinters = $errorPrinters; OfflinePrinters = $offlinePrinters
            TotalJobs = $jobs.Count; StuckJobs = $stuckJobs; ReportedPrinters = $list.Count; Truncated = ($list.Count -lt $ordered.Count)
            Printers = $list
        } | ConvertTo-Json -Depth 4 -Compress
        if ($report.Length -le 4000) { break }
        if ($shown -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $shown--
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($spoolerDisabled -and $spoolerState -ne 'Running') { exit 0 }
    if ($spoolerState -ne 'Running' -or $errorPrinters -gt 0 -or $stuckJobs -gt 0) { exit 2 }
    if ($WarnOffline -eq 'true' -and $offlinePrinters -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
