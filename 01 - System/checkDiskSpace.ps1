#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft freien Speicher lokaler Festplatten, ohne Daten zu löschen.
    EN: Checks free space on local disks without deleting data.
.DESCRIPTION
    DE: Liest alle festen lokalen Laufwerke (Win32_LogicalDisk, DriveType 3) per CIM,
        gibt Größe, freien Speicher und freien Anteil als JSON aus und schreibt den
        Bericht optional in ein MultiLine-Feld (max. 4000 Zeichen). Exit 0 = alle
        Laufwerke über dem Grenzwert, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = mindestens ein Laufwerk unter MinimumFreePercent. Volumes ohne Größenangabe
        (z. B. gesperrt durch BitLocker) erscheinen in UnavailableDrives; nur wenn kein
        Laufwerk auswertbar ist, endet das Skript mit Exit 1.
    EN: Reads all fixed local disks (Win32_LogicalDisk, DriveType 3) via CIM,
        outputs size, free space and free percentage as JSON and optionally writes
        the report to a MultiLine field (max. 4000 characters). Exit 0 = all disks
        above the threshold, 1 = input, query or write error, 2 = at least one
        disk below MinimumFreePercent. Volumes without size data (e.g. BitLocker-locked)
        are listed in UnavailableDrives; the script exits 1 only if no disk is usable.
.PARAMETER MinimumFreePercent
    DE: NinjaOne Integer minimumFreePercent, 1..99; Standard 15.
    EN: NinjaOne Integer minimumFreePercent, 1..99; default 15.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkDiskSpace.ps1 -MinimumFreePercent 10
    DE: Warnt (Exit 2), wenn ein lokales Laufwerk weniger als 10 % frei hat.
    EN: Warns (exit 2) if any local disk has less than 10% free space.
.EXAMPLE
    .\checkDiskSpace.ps1 -MinimumFreePercent 20 -CustomField diskSpaceReport
    DE: Grenzwert 20 % und JSON-Bericht ins MultiLine-Feld diskSpaceReport schreiben.
    EN: Threshold 20% and write the JSON report to the MultiLine field diskSpaceReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Fehler, 2 = wenig Speicher. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = error, 2 = low space. Read-only.
#>
[CmdletBinding()]
param(
    [string]$MinimumFreePercent = $env:minimumFreePercent,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($MinimumFreePercent) -or $MinimumFreePercent.Trim() -eq 'null') {
        $MinimumFreePercent = '15'
    }
    $limit = 0
    if (-not [int]::TryParse($MinimumFreePercent, [ref]$limit) -or $limit -lt 1 -or $limit -gt 99) {
        throw 'minimumFreePercent: 1..99 erforderlich / required.'
    }
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    # DE: Nur feste lokale Laufwerke; Netzwerkfreigaben bleiben unberührt.
    # EN: Fixed local disks only; network shares remain untouched.
    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3')
    if ($disks.Count -eq 0) { throw 'Keine lokalen Laufwerke / No local disks.' }
    $warning = $false
    $unavailable = New-Object System.Collections.Generic.List[string]
    $records = @(foreach ($disk in $disks) {
        # DE: Gesperrte/unformatierte Volumes (z. B. BitLocker) melden statt die ganze Prüfung abzubrechen.
        # EN: Report locked/unformatted volumes (e.g. BitLocker) instead of aborting the whole check.
        if ($null -eq $disk.Size -or $disk.Size -le 0 -or $null -eq $disk.FreeSpace) {
            $unavailable.Add([string]$disk.DeviceID)
            continue
        }
        $percent = 100 * $disk.FreeSpace / $disk.Size
        if ($percent -lt $limit) { $warning = $true }
        [pscustomobject]@{
            Drive = $disk.DeviceID
            SizeGiB = [Math]::Round($disk.Size / 1GB, 2)
            FreeGiB = [Math]::Round($disk.FreeSpace / 1GB, 2)
            FreePercent = [Math]::Round($percent, 2)
            LowSpace = $percent -lt $limit
        }
    })
    if ($records.Count -eq 0) { throw "Keine auswertbaren Laufwerksdaten / No usable disk data: $($unavailable -join ', ')" }
    $report = ConvertTo-Json -InputObject ([ordered]@{ MinimumFreePercent = $limit; Disks = $records; UnavailableDrives = @($unavailable) }) -Depth 4
    Write-Output $report
    # DE: Feld muss existieren und Skript-Schreibrechte haben; kein stilles Abschneiden.
    # EN: Field must exist and allow script writes; never silently truncate.
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
