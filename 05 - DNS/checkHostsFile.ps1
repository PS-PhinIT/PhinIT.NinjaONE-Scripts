#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft aktive Einträge der hosts-Datei gegen eine optionale Positivliste.
    EN: Checks active hosts file entries against an optional allowlist.
.DESCRIPTION
    DE: Liest %SystemRoot%\System32\drivers\etc\hosts (maximal 20000 Zeilen), ignoriert
        Kommentare und meldet aktive Einträge (Adresse, Hostname, Zeile), SHA256-Hash,
        Größe und letzte Änderung (UTC). localhost auf 127.0.0.1/::1 ist immer erlaubt.
        Zeilen ohne gültige IP-Adresse oder Hostnamen gelten als fehlerhaft. Unerwartete
        Einträge werden zuerst gelistet; Liste begrenzt mit Truncated-/Total-Angaben,
        maximal 4000 Zeichen. Eine fehlende Datei ist kein Fehler. Nur lesend.
    EN: Reads %SystemRoot%\System32\drivers\etc\hosts (at most 20000 lines), ignores
        comments and reports active entries (address, host name, line), SHA256 hash,
        size and last write time (UTC). localhost on 127.0.0.1/::1 is always allowed.
        Lines without a valid IP address or host name count as malformed. Unexpected
        entries are listed first; bounded list with truncated/total indicators, at most
        4000 characters. A missing file is not an error. Read-only.
.PARAMETER AllowedHostNames
    DE: NinjaOne Text dnsHostsAllowList: kommagetrennte erlaubte Hostnamen (max. 100, ohne Wildcards); leer = keine Positivliste.
    EN: NinjaOne Text dnsHostsAllowList: comma-separated allowed host names (max. 100, no wildcards); empty = no allowlist.
.PARAMETER WarnOnAnyEntry
    DE: NinjaOne Checkbox/Text dnsHostsWarnOnAnyEntry: true/false/1/0; Standard true. Nur ohne Positivliste wirksam.
    EN: NinjaOne checkbox/text dnsHostsWarnOnAnyEntry: true/false/1/0; default true. Only used without allowlist.
.PARAMETER MaxRecords
    DE: NinjaOne Integer dnsHostsMaxRecords, 1..100; Standard 25.
    EN: NinjaOne Integer dnsHostsMaxRecords, 1..100; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkHostsFile.ps1
    DE: Warnt bei jedem aktiven Eintrag außer localhost.
    EN: Warns on any active entry except localhost.
.EXAMPLE
    .\checkHostsFile.ps1 -AllowedHostNames 'intranet.contoso.com,printer01' -CustomField hostsFileReport
    DE: Warnt nur bei nicht erlaubten Einträgen; JSON in hostsFileReport.
    EN: Warns only on entries not on the allowlist; JSON to hostsFileReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = keine unerwarteten Einträge oder nur Bericht, 1 = Eingabe-, Lese- oder
        Schreibfehler, 2 = unerwartete oder fehlerhafte aktive Einträge (mit Positivliste
        bzw. ohne Positivliste bei dnsHostsWarnOnAnyEntry=true). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = no unexpected entries or report only, 1 = input, read or write error,
        2 = unexpected or malformed active entries (with allowlist, or without allowlist
        when dnsHostsWarnOnAnyEntry=true). Read-only.
#>
[CmdletBinding()]
param(
    [string]$AllowedHostNames = $env:dnsHostsAllowList,
    [string]$WarnOnAnyEntry = $env:dnsHostsWarnOnAnyEntry,
    [string]$MaxRecords = $env:dnsHostsMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $AllowedHostNames = ([string]$AllowedHostNames).Trim()
    $WarnOnAnyEntry = ([string]$WarnOnAnyEntry).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($AllowedHostNames -ieq 'null') { $AllowedHostNames = '' }
    if ($WarnOnAnyEntry -ieq 'null') { $WarnOnAnyEntry = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $WarnOnAnyEntry) { $WarnOnAnyEntry = 'true' }
    if (-not $MaxRecords) { $MaxRecords = '25' }
    if ($WarnOnAnyEntry -notin @('true', 'false', '1', '0')) { throw 'dnsHostsWarnOnAnyEntry: true/false/1/0.' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) {
        throw 'dnsHostsMaxRecords muss 1..100 sein / must be 1..100.'
    }
    $allowed = @()
    if ($AllowedHostNames) {
        $allowed = @($AllowedHostNames.Split(',') | ForEach-Object { $_.Trim().TrimEnd('.').ToLowerInvariant() })
        if ($allowed.Count -gt 100) { throw 'dnsHostsAllowList: maximal 100 / at most 100.' }
        foreach ($name in $allowed) {
            if ($name.Length -gt 253 -or $name -notmatch '^[a-z0-9_](?:[a-z0-9_.-]*[a-z0-9_])?$') {
                throw 'Ungültiger Hostname in dnsHostsAllowList / Invalid host name in dnsHostsAllowList.'
            }
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { throw 'SystemRoot fehlt / is not set.' }
    $path = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'drivers', 'etc', 'hosts')
    $checkActive = ($allowed.Count -gt 0) -or ($WarnOnAnyEntry -in @('true', '1'))
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $hash = ''; $lastWrite = ''; $size = 0; $linesTruncated = $false
    $entries = New-Object System.Collections.Generic.List[object]
    $malformed = 0
    if ($exists) {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $size = [long]$item.Length
        $lastWrite = $item.LastWriteTimeUtc.ToString('o')
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        $lines = @(Get-Content -LiteralPath $path -TotalCount 20001 -ErrorAction Stop)
        if ($lines.Count -gt 20000) { $linesTruncated = $true; $lines = @($lines | Select-Object -First 20000) }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $content = ([string]$lines[$i] -replace '#.*$', '').Trim()
            if (-not $content) { continue }
            $tokens = @($content -split '\s+')
            $address = $null
            $validAddress = [System.Net.IPAddress]::TryParse($tokens[0], [ref]$address)
            if (-not $validAddress -or $tokens.Count -lt 2) {
                $malformed++
                $entries.Add([pscustomobject]@{ Line = $i + 1; Address = ($tokens[0] -replace '[\x00-\x1F\x7F]', ''); HostName = ''; Malformed = $true; Unexpected = $checkActive })
                continue
            }
            foreach ($token in @($tokens | Select-Object -Skip 1)) {
                $hostName = ($token -replace '[\x00-\x1F\x7F]', '').TrimEnd('.').ToLowerInvariant()
                if ($hostName.Length -gt 253) { $hostName = $hostName.Substring(0, 253) }
                $isLocal = ($hostName -eq 'localhost') -and ($address.ToString() -in @('127.0.0.1', '::1'))
                $unexpected = $checkActive -and -not $isLocal -and ($allowed -notcontains $hostName)
                $entries.Add([pscustomobject]@{ Line = $i + 1; Address = $address.ToString(); HostName = $hostName; Malformed = $false; Unexpected = $unexpected })
            }
        }
    }
    $unexpectedCount = @($entries | Where-Object { $_.Unexpected }).Count
    $sorted = @(@($entries | Where-Object { $_.Unexpected }) + @($entries | Where-Object { -not $_.Unexpected }))
    $records = @($sorted | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $sorted.Count
        $report = [ordered]@{
            Path = $path; Exists = $exists; SizeBytes = $size; LastWriteTimeUtc = $lastWrite; Sha256 = $hash
            AllowListUsed = ($allowed.Count -gt 0); CheckActive = $checkActive; LinesTruncated = $linesTruncated
            TotalActiveEntries = $entries.Count; UnexpectedEntries = $unexpectedCount; MalformedLines = $malformed
            ReportedRecords = $records.Count; Truncated = $truncated; Entries = $records
        } | ConvertTo-Json -Depth 4
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($unexpectedCount -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
