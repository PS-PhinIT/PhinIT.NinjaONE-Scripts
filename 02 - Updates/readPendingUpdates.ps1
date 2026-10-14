#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Listet ausstehende Softwareupdates (nur Suche, kein Download/keine Installation).
    EN: Lists pending software updates (search only, no download/no installation).
.DESCRIPTION
    DE: Sucht über Microsoft.Update.Session mit dem Kriterium
        "IsInstalled=0 and IsHidden=0 and Type='Software'" nach nicht installierten, nicht
        ausgeblendeten Updates der vom Gerät konfigurierten Quelle (WSUS/Windows Update).
        Es wird nichts heruntergeladen oder installiert. Ausgegeben werden Titel, KB,
        MSRC-Schweregrad und Klassifizierung, begrenzt auf MaxRecords und 4000 Zeichen
        (TotalPending/Truncated). Sicherheits-/kritische Updates werden sprachunabhängig über
        MsrcSeverity bzw. die Klassifizierungs-GUIDs (Security Updates 0fa1201d-...,
        Critical Updates e6cf1350-...) erkannt. Exit 0 = kein Befund gemäß WarnOn,
        1 = Eingabe-, Such- oder Schreibfehler, 2 = WarnOn=SecurityCritical und mindestens
        ein Sicherheits-/kritisches Update bzw. WarnOn=Any und mindestens ein Update ausstehend.
    EN: Searches via Microsoft.Update.Session with the criteria
        "IsInstalled=0 and IsHidden=0 and Type='Software'" for not installed, not hidden
        updates from the source configured on the device (WSUS/Windows Update). Nothing is
        downloaded or installed. Outputs title, KB, MSRC severity and classification, bounded
        by MaxRecords and 4000 characters (TotalPending/Truncated). Security/critical updates
        are detected locale-independently via MsrcSeverity or the classification GUIDs
        (Security Updates 0fa1201d-..., Critical Updates e6cf1350-...). Exit 0 = no finding
        according to WarnOn, 1 = input, search or write error, 2 = WarnOn=SecurityCritical and
        at least one security/critical update, or WarnOn=Any and at least one update pending.
.PARAMETER WarnOn
    DE: NinjaOne Dropdown/Text updatePendingWarnOn: SecurityCritical, Any oder None; Standard SecurityCritical.
    EN: NinjaOne drop-down/text updatePendingWarnOn: SecurityCritical, Any or None; default SecurityCritical.
.PARAMETER OnlineSearch
    DE: NinjaOne Checkbox/Text updatePendingOnlineSearch, true/false; Standard true. false nutzt nur zwischengespeicherte Metadaten (schneller, ggf. veraltet).
    EN: NinjaOne checkbox/text updatePendingOnlineSearch, true/false; default true. false uses cached metadata only (faster, possibly stale).
.PARAMETER MaxRecords
    DE: NinjaOne Integer updatePendingMaxRecords, 1..100; Standard 25.
    EN: NinjaOne Integer updatePendingMaxRecords, 1..100; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\readPendingUpdates.ps1
    DE: Warnt (Exit 2) bei ausstehenden Sicherheits-/kritischen Updates.
    EN: Warns (exit 2) on pending security/critical updates.
.EXAMPLE
    .\readPendingUpdates.ps1 -WarnOn Any -OnlineSearch false -MaxRecords 10 -CustomField pendingUpdates
    DE: Offline-Suche, Warnung bei jedem Update, max. 10 Einträge ins Feld pendingUpdates.
    EN: Offline search, warn on any update, max. 10 records to the field pendingUpdates.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Die COM-Suche ist synchron und
        kann nicht per Timeout abgebrochen werden; Online-Suchen dauern typisch 1-10 Minuten,
        bei langsamen WSUS-Servern länger. NinjaOne-Timeout auf mindestens 15 Minuten setzen.
        Exit 0 = OK, 1 = Fehler, 2 = ausstehende Updates gemäß WarnOn.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. The COM search is synchronous and
        cannot be cancelled by a timeout; online searches typically take 1-10 minutes, longer
        with slow WSUS servers. Set the NinjaOne timeout to at least 15 minutes.
        Exit 0 = OK, 1 = error, 2 = pending updates according to WarnOn.
#>
[CmdletBinding()]
param(
    [string]$WarnOn = $env:updatePendingWarnOn,
    [string]$OnlineSearch = $env:updatePendingOnlineSearch,
    [string]$MaxRecords = $env:updatePendingMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($WarnOn) -or $WarnOn.Trim() -eq 'null') { $WarnOn = 'SecurityCritical' }
    if ([string]::IsNullOrWhiteSpace($OnlineSearch) -or $OnlineSearch.Trim() -eq 'null') { $OnlineSearch = 'true' }
    if ([string]::IsNullOrWhiteSpace($MaxRecords) -or $MaxRecords.Trim() -eq 'null') { $MaxRecords = '25' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    $mode = @('SecurityCritical', 'Any', 'None') | Where-Object { $_ -eq $WarnOn.Trim() } | Select-Object -First 1
    if (-not $mode) { throw 'updatePendingWarnOn: SecurityCritical, Any, None erforderlich / required.' }
    $online = $false
    if (-not [bool]::TryParse($OnlineSearch.Trim(), [ref]$online)) { throw 'updatePendingOnlineSearch: true/false erforderlich / required.' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords.Trim(), [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'updatePendingMaxRecords: 1..100 erforderlich / required.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    $securityIds = @('0fa1201d-4330-4fa8-8ae9-b877473b6441', 'e6cf1350-c01b-414d-a61f-263d14d133b4')
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $online
    # DE: Nur Suche; keine Download-/Installationsobjekte. EN: Search only; no downloader/installer objects.
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $resultCode = [int]$result.ResultCode
    if ($resultCode -notin @(2, 3)) { throw "Suche fehlgeschlagen / Search failed, ResultCode $resultCode." }
    $all = @(foreach ($update in @($result.Updates)) {
        $categories = @($update.Categories)
        $classes = @($categories | Where-Object { [string]$_.Type -eq 'UpdateClassification' } | ForEach-Object { [string]$_.Name })
        if ($classes.Count -eq 0) { $classes = @($categories | Select-Object -First 3 | ForEach-Object { [string]$_.Name }) }
        $severity = [string]$update.MsrcSeverity
        $isSecurity = [bool]$severity -or @($categories | Where-Object { $securityIds -contains ([string]$_.CategoryID).ToLowerInvariant() }).Count -gt 0
        $title = [string]$update.Title
        if ($title.Length -gt 150) { $title = $title.Substring(0, 150) }
        [pscustomobject]@{
            Title = $title
            KB = (@($update.KBArticleIDs) | ForEach-Object { 'KB' + $_ }) -join ','
            Severity = $severity
            Classification = ($classes -join ', ')
            SecurityOrCritical = $isSecurity
            Downloaded = [bool]$update.IsDownloaded
        }
    })
    $all = @($all | Sort-Object @{ Expression = { -not $_.SecurityOrCritical } }, Title)
    $securityCount = @($all | Where-Object { $_.SecurityOrCritical }).Count
    $records = @($all | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $all.Count
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; OnlineSearch = $online; WarnOn = $mode; SearchResultCode = $resultCode
            TotalPending = $all.Count; SecurityOrCriticalCount = $securityCount
            ReportedRecords = $records.Count; Truncated = $truncated; Updates = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if (($mode -eq 'SecurityCritical' -and $securityCount -gt 0) -or ($mode -eq 'Any' -and $all.Count -gt 0)) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
