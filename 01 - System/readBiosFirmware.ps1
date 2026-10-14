#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet BIOS-/Firmware-Hersteller, Version, Datum, Seriennummer und Firmwaretyp.
    EN: Reports BIOS/firmware vendor, version, date, serial number and firmware type.
.DESCRIPTION
    DE: Liest Win32_BIOS per CIM (Hersteller, SMBIOS-BIOS-Version, Version,
        Veröffentlichungsdatum, Seriennummer, SMBIOS-Version) und den Firmwaretyp
        aus HKLM:\SYSTEM\CurrentControlSet\Control\PEFirmwareType (1 = Legacy BIOS,
        2 = UEFI; fehlt der Wert: Unknown). Optional Warnung, wenn das BIOS-Datum
        älter als MaxAgeDays ist (0 = deaktiviert); ist das Datum dann unbekannt,
        wird ebenfalls gewarnt. Ausgabe als JSON, optional in ein MultiLine-Feld
        (max. 4000 Zeichen). Exit 0 = OK, 1 = Eingabe-, Abfrage- oder Schreibfehler,
        2 = BIOS älter als MaxAgeDays oder Datum unbekannt (nur bei MaxAgeDays > 0).
        Nur lesend. Die Seriennummer ist kein Geheimnis, aber Inventardaten:
        Feld-Leserechte in NinjaOne entsprechend setzen.
    EN: Reads Win32_BIOS via CIM (vendor, SMBIOS BIOS version, version, release
        date, serial number, SMBIOS version) and the firmware type from
        HKLM:\SYSTEM\CurrentControlSet\Control\PEFirmwareType (1 = legacy BIOS,
        2 = UEFI; missing value: Unknown). Optional warning if the BIOS date is
        older than MaxAgeDays (0 = disabled); an unknown date then also warns.
        Outputs JSON, optionally to a MultiLine field (max. 4000 characters).
        Exit 0 = OK, 1 = input, query or write error, 2 = BIOS older than
        MaxAgeDays or date unknown (only if MaxAgeDays > 0). Read-only. The
        serial number is not a secret but inventory data: restrict field read
        permissions in NinjaOne accordingly.
.PARAMETER MaxAgeDays
    DE: NinjaOne Integer systemBiosMaxAgeDays, 0..36500; Standard 0 = keine Altersprüfung.
    EN: NinjaOne Integer systemBiosMaxAgeDays, 0..36500; default 0 = no age check.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\readBiosFirmware.ps1
    DE: BIOS-/Firmwaredaten als JSON, ohne Altersprüfung.
    EN: BIOS/firmware data as JSON without age check.
.EXAMPLE
    .\readBiosFirmware.ps1 -MaxAgeDays 1095 -CustomField biosFirmware
    DE: Warnung bei BIOS älter als 3 Jahre; JSON ins Feld biosFirmware.
    EN: Warning if the BIOS is older than 3 years; JSON to the field biosFirmware.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. PEFirmwareType ab Windows 8/Server 2012.
        Parameter überschreiben Variablen. Exit 0 = OK, 1 = Fehler, 2 = BIOS zu alt/Datum unbekannt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. PEFirmwareType since Windows 8/Server 2012.
        Parameters override variables. Exit 0 = OK, 1 = error, 2 = BIOS too old/date unknown.
#>
[CmdletBinding()]
param(
    [string]$MaxAgeDays = $env:systemBiosMaxAgeDays,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $MaxAgeDays = ([string]$MaxAgeDays).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $MaxAgeDays -or $MaxAgeDays -ieq 'null') { $MaxAgeDays = '0' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $maxAge = 0
    if (-not [int]::TryParse($MaxAgeDays, [ref]$maxAge) -or $maxAge -lt 0 -or $maxAge -gt 36500) {
        throw 'systemBiosMaxAgeDays: 0..36500 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $bios = @(Get-CimInstance -ClassName Win32_BIOS)
    if ($bios.Count -eq 0) { throw 'Keine BIOS-Daten / No BIOS data.' }
    $bios = $bios[0]
    $firmwareType = 'Unknown'
    try {
        $peType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop).PEFirmwareType
        if ([int]$peType -eq 1) { $firmwareType = 'BIOS' }
        elseif ([int]$peType -eq 2) { $firmwareType = 'UEFI' }
    }
    catch { $firmwareType = 'Unknown' }
    $clean = {
        param($Value, [int]$Max)
        $text = (([string]$Value) -replace '[\x00-\x1F\x7F]', '').Trim()
        $text.Substring(0, [Math]::Min($Max, $text.Length))
    }
    $releaseDate = $null
    $ageDays = $null
    if ($bios.ReleaseDate -is [datetime]) {
        $releaseDate = $bios.ReleaseDate.ToString('yyyy-MM-dd')
        $ageDays = [int][Math]::Floor(((Get-Date).Date - $bios.ReleaseDate.Date).TotalDays)
    }
    $outdated = ($maxAge -gt 0 -and ($null -eq $ageDays -or $ageDays -gt $maxAge))
    $smbios = $null
    if ($null -ne $bios.SMBIOSMajorVersion) { $smbios = '{0}.{1}' -f $bios.SMBIOSMajorVersion, $bios.SMBIOSMinorVersion }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Manufacturer = (& $clean $bios.Manufacturer 100)
        BiosVersion = (& $clean $bios.SMBIOSBIOSVersion 100)
        Version = (& $clean $bios.Version 100)
        ReleaseDate = $releaseDate
        AgeDays = $ageDays
        SerialNumber = (& $clean $bios.SerialNumber 64)
        SmbiosVersion = $smbios
        FirmwareType = $firmwareType
        MaxAgeDays = $maxAge
        Outdated = $outdated
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($outdated) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
