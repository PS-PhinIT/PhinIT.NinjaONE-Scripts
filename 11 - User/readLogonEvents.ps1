#Requires -Version 5.1

<#
.SYNOPSIS
DE: Interaktive Anmeldungen (Security 4624) je Benutzer zusammenfassen. EN: Summarize interactive logons (Security 4624) per user.
.DESCRIPTION
DE: Liest Security-Ereignis 4624 der letzten N Tage (begrenzt durch MaxEvents, neueste zuerst) und
filtert im Skript nach LogonType (Standard 2 = interaktiv, 10 = RemoteInteractive, 11 = CachedInteractive).
Ausgeschlossen: Computerkonten ($), System-SIDs (S-1-5-7/18/19/20), DWM-/UMFD-Konten (S-1-5-90-*, S-1-5-96-*).
Ausgabe je Benutzer: Anzahl, letzte Anmeldung, LogonTypes. Keine SIDs, IPs oder Prozessdaten.
EN: Reads Security event 4624 within the last N days (bounded by MaxEvents, newest first) and filters
by LogonType in the script (default 2 = interactive, 10 = RemoteInteractive, 11 = CachedInteractive).
Excluded: machine accounts ($), system SIDs (S-1-5-7/18/19/20), DWM/UMFD accounts (S-1-5-90-*, S-1-5-96-*).
Output per user: count, last logon, logon types. No SIDs, IPs or process data.
DE: MaxEvents zaehlt alle 4624-Ereignisse (auch Typ 3); bei eventLimitReached ist der Zeitraum unvollstaendig.
Erfordert SYSTEM/Administrator und aktivierte Anmeldeueberwachung.
EN: MaxEvents counts all 4624 events (including type 3); with eventLimitReached the window is incomplete.
Requires SYSTEM/administrator and enabled logon auditing.
.PARAMETER LogonTypes
DE: NinjaOne userLogonTypes (Text), kommagetrennt aus 2,3,4,5,7,8,9,10,11,12,13; Standard 2,10,11.
EN: NinjaOne userLogonTypes (text), comma-separated from 2,3,4,5,7,8,9,10,11,12,13; default 2,10,11.
.PARAMETER Days
DE: NinjaOne userLogonEventDays (Integer), 1..90; Standard 7.
EN: NinjaOne userLogonEventDays (integer), 1..90; default 7.
.PARAMETER MaxEvents
DE: NinjaOne userLogonMaxEvents (Integer), 100..50000; Standard 5000.
EN: NinjaOne userLogonMaxEvents (integer), 100..50000; default 5000.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\readLogonEvents.ps1
DE: Interaktive/RDP/Cache-Anmeldungen der letzten 7 Tage je Benutzer. EN: Interactive/RDP/cached logons of the last 7 days per user.
.EXAMPLE
.\readLogonEvents.ps1 -LogonTypes '10' -Days 30 -MaxEvents 20000 -CustomField rdpLogons
DE: Nur RDP-Anmeldungen, 30 Tage; JSON in rdpLogons. EN: RDP logons only, 30 days; JSON to rdpLogons.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = Erfolg (auch ohne Ereignisse), 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = nicht verwendet.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = success (also without events), 1 = input/query/write error, 2 = not used.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LogonTypes = $env:userLogonTypes,
    [string]$Days = $env:userLogonEventDays,
    [string]$MaxEvents = $env:userLogonMaxEvents,
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
    $LogonTypes = Get-InputValue $LogonTypes '2,10,11'
    $types = @()
    foreach ($part in $LogonTypes.Split(',')) {
        $number = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -notin @(2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13)) {
            throw 'userLogonTypes: comma-separated 2,3,4,5,7,8,9,10,11,12,13 / kommagetrennt erforderlich.'
        }
        if ($types -notcontains $number) { $types += $number }
    }
    $dayCount = ConvertTo-BoundedInt -Value (Get-InputValue $Days '7') -Name 'userLogonEventDays' -Minimum 1 -Maximum 90
    $eventLimit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxEvents '5000') -Name 'userLogonMaxEvents' -Minimum 100 -Maximum 50000
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $filter = @{ LogName = 'Security'; Id = 4624; StartTime = (Get-Date).AddDays(-$dayCount) }
    $events = @(Get-BoundedEvent -Filter $filter -Maximum $eventLimit)
    $users = @{}
    $matched = 0
    $parseErrors = 0
    foreach ($logEvent in $events) {
        try {
            $data = @{}
            foreach ($node in ([xml]$logEvent.ToXml()).Event.EventData.Data) { $data[[string]$node.Name] = [string]$node.InnerText }
        } catch { $parseErrors++; continue }
        $type = 0
        if (-not [int]::TryParse($data['LogonType'], [ref]$type) -or $types -notcontains $type) { continue }
        $name = $data['TargetUserName']
        $sid = $data['TargetUserSid']
        # DE: Maschinen-, System-, DWM- und UMFD-Konten ausschliessen. EN: Exclude machine, system, DWM and UMFD accounts.
        if (-not $name -or $name.EndsWith('$') -or $name -match '^(DWM|UMFD)-\d+$') { continue }
        if ($sid -match '^S-1-5-(7|18|19|20)$' -or $sid -match '^S-1-5-(90|96)-') { continue }
        $matched++
        $key = $name
        if ($data['TargetDomainName']) { $key = '{0}\{1}' -f $data['TargetDomainName'], $name }
        $time = ([DateTime]$logEvent.TimeCreated).ToUniversalTime()
        if (-not $users.ContainsKey($key)) { $users[$key] = @{ user = $key; logons = 0; last = $time; types = @() } }
        $entry = $users[$key]
        $entry.logons++
        if ($time -gt $entry.last) { $entry.last = $time }
        if ($entry.types -notcontains $type) { $entry.types += $type }
    }
    $records = @($users.Values | Sort-Object { $_.last } -Descending | ForEach-Object {
        [pscustomobject]@{ user = $_.user; logonCount = $_.logons; lastLogonUtc = $_.last.ToString('o'); logonTypes = @($_.types | Sort-Object) }
    })
    $report = [ordered]@{
        inventory = 'Logon events 4624 / Anmeldeereignisse 4624'; logonTypes = @($types | Sort-Object); days = $dayCount
        eventsRead = $events.Count; eventLimitReached = ($events.Count -ge $eventLimit)
        matchingEvents = $matched; parseErrors = $parseErrors
        total = $records.Count; returned = 0; truncated = $false; records = $records
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
