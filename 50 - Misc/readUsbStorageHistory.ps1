#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet bekannte USB-Massenspeicher (USBSTOR) und die USBSTOR-Sperrrichtlinie.
    EN: Reports known USB mass storage devices (USBSTOR) and the USBSTOR block policy.
.DESCRIPTION
    DE: Liest HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR (Typ, Hersteller, Produkt,
        Revision aus dem Klassenschlüssel; FriendlyName je Instanz) und
        HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR Wert Start (4 = gesperrt,
        3 = erlaubt). Seriennummern (Instanzname ohne "&n"-Suffix) werden nur bei
        IncludeSerial=true ausgegeben; SerialGenerated=true bedeutet, dass Windows die
        Kennung erzeugt hat (zweites Zeichen "&"). Keine Zeitstempel (nicht zuverlässig
        lesbar). Höchstens 500 Geräte werden ausgewertet. JSON, max. 4000 Zeichen
        (Liste wird gekürzt). Nur lesend, keine Richtlinienänderung.
    EN: Reads HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR (type, vendor, product,
        revision from the class key; FriendlyName per instance) and
        HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR value Start (4 = blocked,
        3 = allowed). Serial numbers (instance name without "&n" suffix) are only
        output with IncludeSerial=true; SerialGenerated=true means Windows generated
        the identifier (second character "&"). No timestamps (not reliably readable).
        At most 500 devices are evaluated. JSON, max. 4000 characters (list is
        shortened). Read-only, no policy changes.
.PARAMETER IncludeSerial
    DE: NinjaOne Checkbox/Text usbIncludeSerial, true/false; Standard false.
    EN: NinjaOne Checkbox/Text usbIncludeSerial, true/false; default false.
.PARAMETER RequireBlocked
    DE: NinjaOne Checkbox/Text usbRequireBlocked, true/false; Standard false. true = Exit 2, wenn Start nicht 4 ist.
    EN: NinjaOne Checkbox/Text usbRequireBlocked, true/false; default false. true = exit 2 if Start is not 4.
.PARAMETER MaxRecords
    DE: NinjaOne Integer usbMaxRecords, 1..100; Standard 25.
    EN: NinjaOne Integer usbMaxRecords, 1..100; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readUsbStorageHistory.ps1
    DE: Listet bis zu 25 bekannte USB-Speicher ohne Seriennummern (informativ, Exit 0).
    EN: Lists up to 25 known USB storage devices without serials (informational, exit 0).
.EXAMPLE
    .\readUsbStorageHistory.ps1 -RequireBlocked true -IncludeSerial true -CustomField usbStorageReport
    DE: Mit Seriennummern; Exit 2, wenn USB-Speicher nicht gesperrt ist; JSON in usbStorageReport.
    EN: With serials; exit 2 if USB storage is not blocked; JSON to usbStorageReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Bericht erstellt, 1 = Eingabe-/Abfrage-/Schreibfehler,
        2 = nur bei RequireBlocked=true: USBSTOR Start ist nicht 4.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = report created, 1 = input/query/write error,
        2 = only with RequireBlocked=true: USBSTOR Start is not 4.
#>
[CmdletBinding()]
param(
    [string]$IncludeSerial = $env:usbIncludeSerial,
    [string]$RequireBlocked = $env:usbRequireBlocked,
    [string]$MaxRecords = $env:usbMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-CleanSetting {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
try {
    $IncludeSerial = (ConvertTo-CleanSetting $IncludeSerial 'false').ToLowerInvariant()
    $RequireBlocked = (ConvertTo-CleanSetting $RequireBlocked 'false').ToLowerInvariant()
    if ($IncludeSerial -notin @('true', 'false')) { throw 'usbIncludeSerial: true/false erforderlich / required.' }
    if ($RequireBlocked -notin @('true', 'false')) { throw 'usbRequireBlocked: true/false erforderlich / required.' }
    $MaxRecords = ConvertTo-CleanSetting $MaxRecords '25'
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'usbMaxRecords: 1..100 erforderlich / required.'
    }
    $CustomField = ConvertTo-CleanSetting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $cap = 500
    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'
    $devices = New-Object System.Collections.Generic.List[object]
    $capReached = $false
    if (Test-Path -LiteralPath $enumPath) {
        foreach ($class in @(Get-ChildItem -LiteralPath $enumPath -ErrorAction Stop | Sort-Object PSChildName)) {
            $className = [string]$class.PSChildName
            $type = ($className -split '&')[0]
            $vendor = ''; $product = ''; $revision = ''
            if ($className -match '(?i)Ven_([^&]*)') { $vendor = $Matches[1] }
            if ($className -match '(?i)Prod_([^&]*)') { $product = $Matches[1] }
            if ($className -match '(?i)Rev_([^&]*)') { $revision = $Matches[1] }
            foreach ($instance in @(Get-ChildItem -LiteralPath $class.PSPath -ErrorAction Stop | Sort-Object PSChildName)) {
                if ($devices.Count -ge $cap) { $capReached = $true; break }
                $values = Get-ItemProperty -LiteralPath $instance.PSPath -ErrorAction Stop
                $friendly = ([string]$values.FriendlyName) -replace '[\x00-\x1F\x7F]', ''
                $instanceName = [string]$instance.PSChildName
                $record = [ordered]@{ Type = $type; Vendor = $vendor; Product = $product; Revision = $revision; FriendlyName = $friendly.Trim() }
                $record.SerialGenerated = ($instanceName.Length -gt 1 -and $instanceName[1] -eq '&')
                if ($IncludeSerial -eq 'true') { $record.Serial = $instanceName -replace '&\d+$', '' }
                $devices.Add([pscustomobject]$record)
            }
            if ($capReached) { break }
        }
    }
    $policyPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
    $startValue = $null
    if (Test-Path -LiteralPath $policyPath) { $startValue = (Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop).Start }
    $policy = 'NotPresent'
    if ($null -ne $startValue) { $policy = 'Start=' + [string]$startValue }
    $blocked = ($null -ne $startValue -and [int]$startValue -eq 4)
    $all = $devices.ToArray()
    $shown = $limit
    do {
        $records = @($all | Select-Object -First $shown)
        $report = [ordered]@{
            UsbStorageBlocked = $blocked; UsbStorPolicy = $policy; RequireBlocked = ($RequireBlocked -eq 'true')
            SerialsIncluded = ($IncludeSerial -eq 'true'); TotalDevices = $all.Count; DeviceCapReached = $capReached
            ReportedDevices = $records.Count; Truncated = ($records.Count -lt $all.Count -or $capReached); Devices = $records
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
    if ($RequireBlocked -eq 'true' -and -not $blocked) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
