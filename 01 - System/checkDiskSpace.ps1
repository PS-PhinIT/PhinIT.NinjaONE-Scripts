#Requires -Version 5.1
<#
.SYNOPSIS
    DE: Prüft freien Speicher lokaler Festplatten, ohne Daten zu löschen.
    EN: Checks free space on local disks without deleting data.
.PARAMETER MinimumFreePercent
    DE: NinjaOne Integer minimumFreePercent, 1..99; Standard 15.
    EN: NinjaOne Integer minimumFreePercent, 1..99; default 15.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
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
    $records = @(foreach ($disk in $disks) {
        if ($null -eq $disk.Size -or $disk.Size -le 0 -or $null -eq $disk.FreeSpace) {
            throw "Ungültige Laufwerksdaten / Invalid disk data: $($disk.DeviceID)"
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
    $report = ConvertTo-Json -InputObject ([ordered]@{ MinimumFreePercent = $limit; Disks = $records }) -Depth 4
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
