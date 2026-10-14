#Requires -Version 5.1

<#
.SYNOPSIS
DE: RDP-/Sitzungsverlauf aus dem LocalSessionManager-Protokoll lesen. EN: Read RDP/session history from the LocalSessionManager log.
.DESCRIPTION
DE: Liest Microsoft-Windows-TerminalServices-LocalSessionManager/Operational, Ereignisse 21
(Anmeldung), 23 (Abmeldung), 24 (Trennung) und 25 (Wiederverbindung) der letzten N Tage,
begrenzt durch MaxEvents. Benutzer, Sitzungs-ID und Quelladresse werden aus dem Ereignis-XML
gelesen (Address "LOCAL" = Konsole). Zusaetzlich Zaehler je Aktion. Nur lesend, informativ.
EN: Reads Microsoft-Windows-TerminalServices-LocalSessionManager/Operational events 21 (logon),
23 (logoff), 24 (disconnect) and 25 (reconnect) within the last N days, bounded by MaxEvents.
User, session ID and source address are parsed from the event XML (address "LOCAL" = console).
Also counts per action. Read-only, informational.
DE: Enthaelt personenbezogene Daten (Benutzer, Quell-IP); Feldleserechte in NinjaOne einschraenken.
EN: Contains personal data (user, source IP); restrict field read permissions in NinjaOne.
.PARAMETER Days
DE: NinjaOne userRdpHistoryDays (Integer), 1..90; Standard 7.
EN: NinjaOne userRdpHistoryDays (integer), 1..90; default 7.
.PARAMETER MaxEvents
DE: NinjaOne userRdpMaxEvents (Integer), 10..5000; Standard 500. Neueste Ereignisse zuerst.
EN: NinjaOne userRdpMaxEvents (integer), 10..5000; default 500. Newest events first.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\readRdpSessionHistory.ps1
DE: Sitzungsereignisse der letzten 7 Tage (max. 25 Eintraege). EN: Session events of the last 7 days (max 25 entries).
.EXAMPLE
.\readRdpSessionHistory.ps1 -Days 30 -MaxEvents 2000 -MaxRecords 40 -CustomField rdpHistory
DE: 30 Tage, bis 2000 Ereignisse; JSON in rdpHistory. EN: 30 days, up to 2000 events; JSON to rdpHistory.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = Erfolg (auch ohne Ereignisse), 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = nicht verwendet.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = success (also without events), 1 = input/query/write error, 2 = not used.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Days = $env:userRdpHistoryDays,
    [string]$MaxEvents = $env:userRdpMaxEvents,
    [string]$MaxRecords = $env:userMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputValue {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0} must be {1}..{2} / muss {1}..{2} sein.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Get-BoundedEvent {
    param([hashtable]$Filter, [int]$Maximum)
    try { Get-WinEvent -FilterHashtable $Filter -MaxEvents $Maximum -ErrorAction Stop }
    catch {
        # DE: Keine Treffer sind kein Fehler. EN: No matching events is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
}
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([System.Collections.IDictionary]$Report, [int]$Limit, [string]$Field)
    $all = @($Report['records'])
    $count = [Math]::Min($all.Count, $Limit)
    while ($true) {
        $Report['records'] = @($all | Select-Object -First $count)
        $Report['returned'] = $count
        $Report['truncated'] = ($count -lt $all.Count)
        $content = ConvertTo-Json -InputObject $Report -Depth 5
        if ($content.Length -le 4000 -or $count -eq 0) { break }
        $count--
    }
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $dayCount = ConvertTo-BoundedInt -Value (Get-InputValue $Days '7') -Name 'userRdpHistoryDays' -Minimum 1 -Maximum 90
    $eventLimit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxEvents '500') -Name 'userRdpMaxEvents' -Minimum 10 -Maximum 5000
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $actions = @{ 21 = 'Logon'; 23 = 'Logoff'; 24 = 'Disconnect'; 25 = 'Reconnect' }
    $filter = @{
        LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
        Id = @(21, 23, 24, 25); StartTime = (Get-Date).AddDays(-$dayCount)
    }
    $events = @(Get-BoundedEvent -Filter $filter -Maximum $eventLimit)
    $parseErrors = 0
    $records = @(foreach ($logEvent in ($events | Sort-Object TimeCreated -Descending)) {
        try {
            # DE: Felder liegen in UserData/EventXML (Namensraum ueber LocalName). EN: Fields live in UserData/EventXML (namespace via LocalName).
            $data = ([xml]$logEvent.ToXml()).Event.UserData.EventXML
            [pscustomobject]@{
                timeUtc = ([DateTime]$logEvent.TimeCreated).ToUniversalTime().ToString('o'); eventId = [int]$logEvent.Id
                action = $actions[[int]$logEvent.Id]; user = [string]$data.User
                sessionId = [string]$data.SessionID; sourceAddress = [string]$data.Address
            }
        } catch { $parseErrors++ }
    })
    $summary = [ordered]@{}
    foreach ($id in @(21, 23, 24, 25)) { $summary[$actions[$id]] = @($records | Where-Object { $_.eventId -eq $id }).Count }
    $report = [ordered]@{
        inventory = 'RDP/session history / RDP-Sitzungsverlauf'; days = $dayCount
        eventsRead = $events.Count; eventLimitReached = ($events.Count -ge $eventLimit); parseErrors = $parseErrors
        distinctUsers = @($records | Where-Object { $_.user } | Sort-Object user -Unique).Count
        actionCounts = $summary
        total = $records.Count; returned = 0; truncated = $false; records = $records
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
