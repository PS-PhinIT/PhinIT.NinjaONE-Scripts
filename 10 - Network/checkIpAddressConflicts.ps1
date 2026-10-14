#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Erkennt IP-Adresskonflikte, APIPA-Adressen und ungültige Adresszustände.
    EN: Detects IP address conflicts, APIPA addresses and invalid address states.
.DESCRIPTION
    DE: Prüft auf verbundenen Adaptern (Get-NetAdapter, Status Up) per
        Get-NetIPAddress: APIPA-Adressen 169.254.x.x (DHCP fehlgeschlagen) sowie
        AddressState Duplicate, Invalid oder Tentative (Tentative kann kurz nach dem
        Verbindungsaufbau normal sein). Zusätzlich werden System-Ereignisse 4199
        (Tcpip, IP-Adresskonflikt) der letzten N Tage begrenzt gelesen; keine Treffer
        sind kein Fehler. Exit 2 bei mindestens einem Befund. Keine Änderungen;
        JSON-Bericht max. 4000 Zeichen, Befundliste wird bei Bedarf gekürzt.
    EN: Checks connected adapters (Get-NetAdapter, status Up) via Get-NetIPAddress:
        APIPA addresses 169.254.x.x (DHCP failed) plus AddressState Duplicate, Invalid
        or Tentative (Tentative can be normal right after link-up). Additionally reads
        a bounded set of System events 4199 (Tcpip, IP address conflict) from the last
        N days; no matches are not an error. Exit 2 on at least one finding. No changes;
        JSON report max. 4000 characters, the finding list is shortened if needed.
.PARAMETER Days
    DE: NinjaOne Integer networkConflictDays, 1..90; Standard 7.
    EN: NinjaOne Integer networkConflictDays, 1..90; default 7.
.PARAMETER MaxEvents
    DE: NinjaOne Integer networkConflictMaxEvents, 1..500; Standard 50.
    EN: NinjaOne Integer networkConflictMaxEvents, 1..500; default 50.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\checkIpAddressConflicts.ps1
    DE: Prüft Adressen und Ereignis 4199 der letzten 7 Tage.
    EN: Checks addresses and event 4199 from the last 7 days.
.EXAMPLE
    .\checkIpAddressConflicts.ps1 -Days 30 -MaxEvents 100 -CustomField ipConflicts
    DE: 30 Tage, max. 100 Ereignisse; JSON ins Feld ipConflicts.
    EN: 30 days, max. 100 events; JSON to the field ipConflicts.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = APIPA, Adresszustand
        Duplicate/Invalid/Tentative oder Konfliktereignis 4199. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = APIPA, address state
        Duplicate/Invalid/Tentative or conflict event 4199. Read-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Days = $env:networkConflictDays,
    [string]$MaxEvents = $env:networkConflictMaxEvents,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputText {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function Publish-NetworkReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Report, [string]$Field)
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($Report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $Report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    $Days = Get-InputText $Days '7'
    $MaxEvents = Get-InputText $MaxEvents '50'
    $CustomField = Get-InputText $CustomField ''
    $dayCount = 0
    $eventLimit = 0
    if (-not [int]::TryParse($Days, [ref]$dayCount) -or $dayCount -lt 1 -or $dayCount -gt 90) { throw 'networkConflictDays: 1..90 erforderlich / required.' }
    if (-not [int]::TryParse($MaxEvents, [ref]$eventLimit) -or $eventLimit -lt 1 -or $eventLimit -gt 500) { throw 'networkConflictMaxEvents: 1..500 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    $connected = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [int]$_.InterfaceIndex })
    $addresses = @(Get-NetIPAddress -ErrorAction Stop | Where-Object { [int]$_.InterfaceIndex -in $connected })
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($address in ($addresses | Sort-Object InterfaceIndex, IPAddress)) {
        $ip = [string]$address.IPAddress
        $state = [string]$address.AddressState
        $kind = @()
        if ([string]$address.AddressFamily -eq 'IPv4' -and $ip -like '169.254.*') { $kind += 'APIPA' }
        if ($state -in @('Duplicate', 'Invalid', 'Tentative')) { $kind += ('AddressState' + $state) }
        if ($kind.Count -gt 0) {
            $findings.Add([pscustomobject]@{
                Type = ($kind -join ','); InterfaceAlias = [string]$address.InterfaceAlias
                IPAddress = $ip; AddressState = $state; PrefixOrigin = [string]$address.PrefixOrigin
            })
        }
    }

    # DE: Ereignis 4199 begrenzt lesen; "keine Ereignisse" ist kein Fehler.
    # EN: Read event 4199 bounded; "no events" is not an error.
    $filter = @{ LogName = 'System'; Id = 4199; StartTime = (Get-Date).AddDays(-$dayCount) }
    $eventErrors = $null
    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $eventLimit -ErrorAction SilentlyContinue -ErrorVariable eventErrors |
        Where-Object { [string]$_.ProviderName -match '^(Microsoft-Windows-)?Tcpip$' })
    $realErrors = @($eventErrors | Where-Object {
        $_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and $_.CategoryInfo.Category -ne 'ObjectNotFound'
    })
    if ($realErrors.Count -gt 0) { throw $realErrors[0] }
    foreach ($conflictEvent in ($events | Sort-Object TimeCreated -Descending)) {
        $message = ([string]$conflictEvent.Message) -replace '[\x00-\x1F\x7F]+', ' '
        if ($message.Length -gt 200) { $message = $message.Substring(0, 200) }
        $findings.Add([pscustomobject]@{
            Type = 'ConflictEvent4199'; TimeCreated = ([datetime]$conflictEvent.TimeCreated).ToString('s'); Message = $message.Trim()
        })
    }

    $records = @($findings | Select-Object -First 50)
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            Days = $dayCount; ConnectedAdapters = $connected.Count; CheckedAddresses = $addresses.Count
            ConflictEvents = $events.Count; TotalFindings = $findings.Count; ReportedRecords = $records.Count
            Truncated = ($records.Count -lt $findings.Count); Findings = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
