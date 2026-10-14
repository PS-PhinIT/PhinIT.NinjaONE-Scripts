#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Vergleicht die A/AAAA-Antworten mehrerer DNS-Server für einen Namen.
    EN: Compares A/AAAA answers of several DNS servers for one name.
.DESCRIPTION
    DE: Löst einen Namen bei 2..5 expliziten DNS-Servern einzeln mit Resolve-DnsName
        -Server -DnsOnly -NoHostsFile -QuickTimeout auf und vergleicht die sortierten
        Adressmengen (Hinweis auf Split-Brain, Hijacking oder veraltete Zonen). CDN- oder
        GeoDNS-Namen können legitim abweichen. Maximal 10 Adressen je Server im Bericht,
        4000 Zeichen. Nur lesend.
    EN: Resolves one name at 2..5 explicit DNS servers individually with Resolve-DnsName
        -Server -DnsOnly -NoHostsFile -QuickTimeout and compares the sorted address sets
        (indicator of split-brain, hijacking or stale zones). CDN or GeoDNS names may
        legitimately differ. At most 10 addresses per server in the report, 4000
        characters. Read-only.
.PARAMETER HostName
    DE: NinjaOne Text dnsCompareHostName: DNS-Name ohne Wildcards; Pflicht.
    EN: NinjaOne Text dnsCompareHostName: DNS name without wildcards; required.
.PARAMETER Servers
    DE: NinjaOne Text dnsCompareServers: 2..5 kommagetrennte, eindeutige IP-Adressen; Pflicht.
    EN: NinjaOne Text dnsCompareServers: 2..5 comma-separated unique IP addresses; required.
.PARAMETER RecordType
    DE: NinjaOne Dropdown/Text dnsCompareRecordType: A, AAAA oder Both; Standard Both.
    EN: NinjaOne drop-down/text dnsCompareRecordType: A, AAAA or Both; default Both.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\compareDnsServerResponses.ps1 -HostName intranet.contoso.com -Servers '10.0.0.10,10.0.0.11'
    DE: Vergleicht A- und AAAA-Antworten beider interner DNS-Server.
    EN: Compares A and AAAA answers of both internal DNS servers.
.EXAMPLE
    .\compareDnsServerResponses.ps1 -HostName www.contoso.com -Servers '10.0.0.10,1.1.1.1,8.8.8.8' -RecordType A -CustomField dnsCompareReport
    DE: Vergleicht nur A-Einträge über drei Server; JSON in dnsCompareReport.
    EN: Compares A records only across three servers; JSON to dnsCompareReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = alle Server liefern dieselbe Adressmenge, 1 = Eingabe- oder
        Schreibfehler (inkl. fehlender Pflichtwerte), 2 = abweichende Antworten oder
        mindestens ein Server antwortet nicht/mit Fehler (z. B. NXDOMAIN). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = all servers return the same address set, 1 = input or write error
        (including missing required values), 2 = differing answers or at least one
        server fails/errors (e.g. NXDOMAIN). Read-only.
#>
[CmdletBinding()]
param(
    [string]$HostName = $env:dnsCompareHostName,
    [string]$Servers = $env:dnsCompareServers,
    [string]$RecordType = $env:dnsCompareRecordType,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $HostName = ([string]$HostName).Trim()
    $Servers = ([string]$Servers).Trim()
    $RecordType = ([string]$RecordType).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($HostName -ieq 'null') { $HostName = '' }
    if ($Servers -ieq 'null') { $Servers = '' }
    if ($RecordType -ieq 'null') { $RecordType = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $RecordType) { $RecordType = 'Both' }
    if ($RecordType -notin @('A', 'AAAA', 'Both')) { throw 'dnsCompareRecordType: A, AAAA, Both.' }
    $types = @('A', 'AAAA')
    if ($RecordType -ne 'Both') { $types = @($RecordType.ToUpperInvariant()) }
    if (-not $HostName) { throw 'dnsCompareHostName fehlt / is required.' }
    if ($HostName.Length -gt 253 -or $HostName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.?$') {
        throw 'Ungültiger dnsCompareHostName / Invalid dnsCompareHostName.'
    }
    foreach ($label in $HostName.TrimEnd('.').Split('.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { throw 'Ungültiges DNS-Label / Invalid DNS label.' }
    }
    $serverList = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Servers.Split(',')) {
        $candidate = $entry.Trim()
        if (-not $candidate) { continue }
        $address = $null
        if ($candidate.Contains('%') -or -not [System.Net.IPAddress]::TryParse($candidate, [ref]$address)) {
            throw 'dnsCompareServers: nur IP-Adressen / only IP addresses.'
        }
        if (-not $serverList.Contains($address.ToString())) { $serverList.Add($address.ToString()) }
    }
    if ($serverList.Count -lt 2 -or $serverList.Count -gt 5) { throw 'dnsCompareServers: 2..5 eindeutige Server / unique servers required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { throw 'Resolve-DnsName fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $results = @(foreach ($server in $serverList) {
        $answers = New-Object System.Collections.Generic.List[string]
        $message = ''
        foreach ($type in $types) {
            try {
                foreach ($record in @(Resolve-DnsName -Name $HostName -Type $type -Server $server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                    Where-Object { [string]$_.Type -eq $type -and [string]$_.Section -eq 'Answer' })) {
                    $ip = $null
                    if ([System.Net.IPAddress]::TryParse([string]$record.IPAddress, [ref]$ip) -and -not $answers.Contains($ip.ToString())) { $answers.Add($ip.ToString()) }
                }
            }
            catch {
                $message = [string]$_.Exception.Message
                if ($message.Length -gt 120) { $message = $message.Substring(0, 120) }
                break
            }
        }
        $sorted = @($answers | Sort-Object)
        $status = 'OK'
        if ($message) { $status = 'Failed' }
        [pscustomobject]@{
            Server = $server; Status = $status; AnswerSet = ($sorted -join ',')
            TotalAnswers = $sorted.Count; Answers = @($sorted | Select-Object -First 10); Error = $message
        }
    })
    $failed = @($results | Where-Object { $_.Status -ne 'OK' }).Count
    $distinctSets = @($results | Where-Object { $_.Status -eq 'OK' } | ForEach-Object { $_.AnswerSet } | Sort-Object -Unique)
    $consistent = ($failed -eq 0) -and ($distinctSets.Count -eq 1)
    $records = @($results | Select-Object Server, Status, TotalAnswers, Answers, Error)
    $report = [ordered]@{
        HostName = $HostName; RecordType = $RecordType; TotalServers = $results.Count; FailedServers = $failed
        DistinctAnswerSets = $distinctSets.Count; Consistent = $consistent; Results = $records
    } | ConvertTo-Json -Depth 4
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if (-not $consistent) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
