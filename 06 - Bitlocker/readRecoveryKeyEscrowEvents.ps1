#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Wertet BitLocker-Escrow-Ereignisse (Sicherung in Entra ID / AD DS) für das OS-Volume aus.
    EN: Evaluates BitLocker escrow events (backup to Entra ID / AD DS) for the OS volume.
.DESCRIPTION
    DE: Liest das Protokoll Microsoft-Windows-BitLocker/BitLocker Management (Ereignisanzeige:
        BitLocker-API > Management) per Get-WinEvent mit StartTime und MaxEvents. Ereignis-IDs:
        845 = Sicherung in Entra ID erfolgreich, 846 = Entra ID fehlgeschlagen,
        784 = Sicherung in AD DS erfolgreich, 785 = AD DS fehlgeschlagen. Diese IDs sind in der
        Praxis/Community (Intune-Remediations) dokumentiert, aber nicht in einer offiziellen
        Microsoft-Referenz; vor dem Einsatz auf einem Referenzgerät verifizieren. Das Volume wird
        sprachunabhängig aus den XML-Ereignisdaten (VolumeMountPoint/VolumeName bzw. ein Datenfeld
        gleich $env:SystemDrive) ermittelt. Meldungstexte werden nie ausgegeben, keine Schlüssel.
    EN: Reads the log Microsoft-Windows-BitLocker/BitLocker Management (Event Viewer:
        BitLocker-API > Management) via Get-WinEvent with StartTime and MaxEvents. Event IDs:
        845 = Entra ID backup succeeded, 846 = Entra ID backup failed, 784 = AD DS backup succeeded,
        785 = AD DS backup failed. These IDs are documented in practice/community (Intune
        remediations) but not in an official Microsoft reference; verify on a reference device
        first. The volume is resolved locale-independently from the XML event data
        (VolumeMountPoint/VolumeName or any data field equal to $env:SystemDrive). Message texts are
        never output, no keys.
.PARAMETER Days
    DE: NinjaOne Integer bitlockerEscrowDays; 1..365; Standard 30.
    EN: NinjaOne Integer bitlockerEscrowDays; 1..365; default 30.
.PARAMETER MaxEvents
    DE: NinjaOne Integer bitlockerEscrowMaxEvents; 1..1000; Standard 200 (Obergrenze gelesener Ereignisse).
    EN: NinjaOne Integer bitlockerEscrowMaxEvents; 1..1000; default 200 (upper bound of read events).
.PARAMETER Target
    DE: NinjaOne Dropdown/Text bitlockerEscrowTarget; Any, EntraId oder ActiveDirectory; Standard Any.
    EN: NinjaOne Dropdown/Text bitlockerEscrowTarget; Any, EntraId or ActiveDirectory; default Any.
.PARAMETER RequireEvent
    DE: NinjaOne Checkbox bitlockerEscrowRequireEvent; true/false/1/0; Standard true = Exit 2, wenn kein
        Escrow-Ereignis für das OS-Volume im Zeitraum vorliegt.
    EN: NinjaOne Checkbox bitlockerEscrowRequireEvent; true/false/1/0; default true = exit 2 if no
        escrow event exists for the OS volume in the period.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\readRecoveryKeyEscrowEvents.ps1
    DE: Letzte 30 Tage, Entra ID und AD DS; Exit 2 bei letztem Fehlschlag oder ohne Ereignis.
    EN: Last 30 days, Entra ID and AD DS; exit 2 on latest failure or no event.
.EXAMPLE
    .\readRecoveryKeyEscrowEvents.ps1 -Days 90 -Target EntraId -RequireEvent false -CustomField bitlockerEscrow
    DE: Nur Entra ID, 90 Tage, fehlendes Ereignis ist keine Warnung; JSON ins Feld bitlockerEscrow.
    EN: Entra ID only, 90 days, missing event is no warning; JSON to field bitlockerEscrow.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Fehlende Ereignisse sind kein Fehler.
        Exit 0 = letztes OS-Escrow-Ereignis erfolgreich (oder keines und RequireEvent=false),
        1 = Eingabe-/Abfrage-/Schreibfehler, 2 = letztes OS-Escrow-Ereignis ist ein Fehlschlag oder
        (RequireEvent=true) kein OS-Escrow-Ereignis im Zeitraum.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Missing events are not an error.
        Exit 0 = latest OS escrow event succeeded (or none and RequireEvent=false),
        1 = input/query/write error, 2 = latest OS escrow event is a failure or (RequireEvent=true)
        no OS escrow event in the period.
#>
[CmdletBinding()]
param(
    [string]$Days = $env:bitlockerEscrowDays,
    [string]$MaxEvents = $env:bitlockerEscrowMaxEvents,
    [string]$Target = $env:bitlockerEscrowTarget,
    [string]$RequireEvent = $env:bitlockerEscrowRequireEvent,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $Days = ([string]$Days).Trim(); $MaxEvents = ([string]$MaxEvents).Trim(); $Target = ([string]$Target).Trim()
    $RequireEvent = ([string]$RequireEvent).Trim(); $CustomField = ([string]$CustomField).Trim()
    if ($Days -ieq 'null') { $Days = '' }
    if ($MaxEvents -ieq 'null') { $MaxEvents = '' }
    if ($Target -ieq 'null') { $Target = '' }
    if ($RequireEvent -ieq 'null') { $RequireEvent = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $Days) { $Days = '30' }
    if (-not $MaxEvents) { $MaxEvents = '200' }
    if (-not $Target) { $Target = 'Any' }
    if (-not $RequireEvent) { $RequireEvent = 'true' }
    $dayCount = 0; $eventLimit = 0
    if (-not [int]::TryParse($Days, [ref]$dayCount) -or $dayCount -lt 1 -or $dayCount -gt 365) { throw 'bitlockerEscrowDays: 1..365.' }
    if (-not [int]::TryParse($MaxEvents, [ref]$eventLimit) -or $eventLimit -lt 1 -or $eventLimit -gt 1000) { throw 'bitlockerEscrowMaxEvents: 1..1000.' }
    $targetMatch = @(@('Any', 'EntraId', 'ActiveDirectory') | Where-Object { $_ -ieq $Target })
    if ($targetMatch.Count -ne 1) { throw 'bitlockerEscrowTarget: Any, EntraId, ActiveDirectory.' }
    $Target = $targetMatch[0]
    if ($RequireEvent -notin @('true', 'false', '1', '0')) { throw 'bitlockerEscrowRequireEvent: true/false.' }
    $mustExist = $RequireEvent -in @('true', '1')
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $osDrive = ([string]$env:SystemDrive).Trim()
    if ($osDrive -notmatch '^[A-Za-z]:$') { throw 'SystemDrive unbekannt / unknown.' }
    $meaning = @{
        845 = @('EntraId', 'Success'); 846 = @('EntraId', 'Failure')
        784 = @('ActiveDirectory', 'Success'); 785 = @('ActiveDirectory', 'Failure')
    }
    $ids = @($meaning.Keys | Where-Object { $Target -eq 'Any' -or $meaning[$_][0] -eq $Target } | Sort-Object)
    $filter = @{ LogName = 'Microsoft-Windows-BitLocker/BitLocker Management'; Id = $ids; StartTime = (Get-Date).AddDays(-$dayCount) }
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $eventLimit) }
    catch {
        # DE: Keine Treffer ist kein Fehler. EN: No matches is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and $_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
    $records = @(foreach ($entry in ($events | Sort-Object TimeCreated -Descending)) {
        $volume = ''
        $isOs = $false
        try {
            # DE: XML-Datenfelder statt lokalisierter Meldung. EN: XML data fields instead of localized message.
            $data = @(([xml]$entry.ToXml()).Event.EventData.Data | ForEach-Object {
                if ($_ -is [string]) { [pscustomobject]@{ Name = ''; Value = $_ } }
                else { [pscustomobject]@{ Name = [string]$_.Name; Value = [string]$_.InnerText } }
            })
            $named = @($data | Where-Object { $_.Name -in @('VolumeMountPoint', 'VolumeName') -and $_.Value })
            if ($named.Count -gt 0) { $volume = $named[0].Value }
            $isOs = @($data | Where-Object { $_.Value.Trim().TrimEnd('\') -ieq $osDrive }).Count -gt 0
        } catch { $volume = 'Unknown' }
        [pscustomobject]@{
            TimeCreated = ([datetime]$entry.TimeCreated).ToString('o'); Id = [int]$entry.Id
            Target = $meaning[[int]$entry.Id][0]; Result = $meaning[[int]$entry.Id][1]
            Volume = $volume; IsOsVolume = $isOs
        }
    })
    $osRecords = @($records | Where-Object { $_.IsOsVolume })
    $latest = $osRecords | Select-Object -First 1
    $status = 'NoEvent'
    if ($latest) { $status = $latest.Result }
    $listed = @($records | Select-Object -First 20)
    do {
        $report = ConvertTo-Json -InputObject ([ordered]@{
            LogName = $filter.LogName; Days = $dayCount; Target = $Target; OsVolume = $osDrive
            LatestOsStatus = $status; LatestOsEvent = $latest; TotalEvents = $records.Count
            OsVolumeEvents = $osRecords.Count; Truncated = ($listed.Count -lt $records.Count); Events = $listed
        }) -Depth 4 -Compress
        if ($report.Length -le 4000) { break }
        if ($listed.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $listed = @($listed | Select-Object -First ($listed.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($status -eq 'Failure' -or ($status -eq 'NoEvent' -and $mustExist)) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
