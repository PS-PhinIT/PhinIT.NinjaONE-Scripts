#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Vergleicht DNS-Suffixsuchliste und primäres DNS-Suffix mit Sollwerten.
    EN: Compares the DNS suffix search list and primary DNS suffix with expected values.
.DESCRIPTION
    DE: Liest SuffixSearchList (Get-DnsClientGlobalSetting) und das primäre DNS-Suffix
        (HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters, Werte Domain und
        NV Domain = nach Neustart wirksam) und vergleicht ohne Groß-/Kleinschreibung
        und ohne abschließenden Punkt. Reihenfolge optional. Eine leere Suchliste
        bedeutet unter Windows: primäres und verbindungsspezifische Suffixe (Devolution).
        Ohne Sollwerte nur Bericht. Nur lesend, maximal 4000 Zeichen.
    EN: Reads SuffixSearchList (Get-DnsClientGlobalSetting) and the primary DNS suffix
        (HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters, values Domain and
        NV Domain = effective after reboot) and compares case-insensitively without a
        trailing dot. Order is optional. An empty search list means primary plus
        connection-specific suffixes (devolution) on Windows. Without expected values
        report only. Read-only, at most 4000 characters.
.PARAMETER ExpectedSuffixes
    DE: NinjaOne Text dnsExpectedSuffixSearchList: kommagetrennte DNS-Suffixe (max. 50); leer = nicht vergleichen.
    EN: NinjaOne Text dnsExpectedSuffixSearchList: comma-separated DNS suffixes (max. 50); empty = do not compare.
.PARAMETER OrderMatters
    DE: NinjaOne Checkbox/Text dnsSuffixOrderMatters: true/false/1/0; Standard false.
    EN: NinjaOne checkbox/text dnsSuffixOrderMatters: true/false/1/0; default false.
.PARAMETER ExpectedPrimarySuffix
    DE: NinjaOne Text dnsExpectedPrimarySuffix: erwartetes primäres DNS-Suffix; leer = nicht vergleichen.
    EN: NinjaOne Text dnsExpectedPrimarySuffix: expected primary DNS suffix; empty = do not compare.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field.
.EXAMPLE
    .\checkDnsSuffixSearchList.ps1 -ExpectedSuffixes 'corp.contoso.com,contoso.com'
    DE: Warnt, wenn die Suchliste nicht genau diese Suffixe enthält (Reihenfolge egal).
    EN: Warns if the search list does not contain exactly these suffixes (any order).
.EXAMPLE
    .\checkDnsSuffixSearchList.ps1 -ExpectedSuffixes 'corp.contoso.com,contoso.com' -OrderMatters true -ExpectedPrimarySuffix corp.contoso.com -CustomField dnsSuffixReport
    DE: Prüft Reihenfolge und primäres Suffix; JSON in dnsSuffixReport.
    EN: Checks order and primary suffix; JSON to dnsSuffixReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = übereinstimmend oder nur Bericht, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = Suchliste (Inhalt/Reihenfolge) oder primäres Suffix weicht ab.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = matching or report only, 1 = input, query or write error,
        2 = search list (content/order) or primary suffix differs.
#>
[CmdletBinding()]
param(
    [string]$ExpectedSuffixes = $env:dnsExpectedSuffixSearchList,
    [string]$OrderMatters = $env:dnsSuffixOrderMatters,
    [string]$ExpectedPrimarySuffix = $env:dnsExpectedPrimarySuffix,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Test-DnsSuffix {
    param([string]$Name)
    if ($Name.Length -gt 253 -or $Name -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') { return $false }
    foreach ($label in $Name.Split('.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { return $false }
    }
    return $true
}
try {
    $ExpectedSuffixes = ([string]$ExpectedSuffixes).Trim()
    $OrderMatters = ([string]$OrderMatters).Trim()
    $ExpectedPrimarySuffix = ([string]$ExpectedPrimarySuffix).Trim().TrimEnd('.').ToLowerInvariant()
    $CustomField = ([string]$CustomField).Trim()
    if ($ExpectedSuffixes -ieq 'null') { $ExpectedSuffixes = '' }
    if ($OrderMatters -ieq 'null') { $OrderMatters = '' }
    if ($ExpectedPrimarySuffix -ieq 'null') { $ExpectedPrimarySuffix = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $OrderMatters) { $OrderMatters = 'false' }
    if ($OrderMatters -notin @('true', 'false', '1', '0')) { throw 'dnsSuffixOrderMatters: true/false/1/0.' }
    $ordered = $OrderMatters -in @('true', '1')
    $expected = @()
    if ($ExpectedSuffixes) {
        $expected = @($ExpectedSuffixes.Split(',') | ForEach-Object { $_.Trim().TrimEnd('.').ToLowerInvariant() })
        if ($expected.Count -gt 50) { throw 'dnsExpectedSuffixSearchList: maximal 50 / at most 50.' }
        foreach ($suffix in $expected) {
            if (-not (Test-DnsSuffix -Name $suffix)) { throw 'Ungültiges Suffix / Invalid suffix in dnsExpectedSuffixSearchList.' }
        }
    }
    if ($ExpectedPrimarySuffix -and -not (Test-DnsSuffix -Name $ExpectedPrimarySuffix)) {
        throw 'Ungültiger dnsExpectedPrimarySuffix / Invalid dnsExpectedPrimarySuffix.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger resultCustomField / Invalid resultCustomField.'
    }
    if (-not (Get-Command Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue)) { throw 'Get-DnsClientGlobalSetting fehlt / is unavailable.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }
    $actual = @(@((Get-DnsClientGlobalSetting -ErrorAction Stop).SuffixSearchList) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { ([string]$_).Trim().TrimEnd('.').ToLowerInvariant() })
    $tcpip = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction Stop
    $primary = ([string]$tcpip.Domain).Trim().TrimEnd('.').ToLowerInvariant()
    $pendingPrimary = ([string]$tcpip.'NV Domain').Trim().TrimEnd('.').ToLowerInvariant()
    $listCompared = [bool]$ExpectedSuffixes
    $missing = @($expected | Where-Object { $actual -notcontains $_ } | Select-Object -Unique)
    $unexpected = @()
    $orderOk = $true
    if ($listCompared) {
        $unexpected = @($actual | Where-Object { $expected -notcontains $_ } | Select-Object -Unique)
        if ($ordered) { $orderOk = (($actual -join ',') -eq ($expected -join ',')) }
    }
    $listOk = (-not $listCompared) -or ($missing.Count -eq 0 -and $unexpected.Count -eq 0 -and $orderOk)
    $primaryOk = (-not $ExpectedPrimarySuffix) -or ($primary -eq $ExpectedPrimarySuffix)
    $report = [ordered]@{
        SuffixSearchList = $actual; PrimaryDnsSuffix = $primary; PendingPrimaryDnsSuffix = $pendingPrimary
        ListCompared = $listCompared; OrderMatters = $ordered; ExpectedSuffixSearchList = $expected
        MissingSuffixes = $missing; UnexpectedSuffixes = $unexpected; OrderMatches = $orderOk; ListMatches = $listOk
        ExpectedPrimarySuffix = $ExpectedPrimarySuffix; PrimarySuffixMatches = $primaryOk
    } | ConvertTo-Json -Depth 4
    if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if (-not $listOk -or -not $primaryOk) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
