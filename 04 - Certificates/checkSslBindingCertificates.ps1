#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft Zertifikate der HTTP.sys-SSL-Bindungen (netsh http show sslcert).
EN: Checks certificates of HTTP.sys SSL bindings (netsh http show sslcert).
.DESCRIPTION
DE: Ruft netsh http show sslcert auf, erkennt Bindungen (IP:Port, Hostname:Port, Central
    Certificate Store), deren Zertifikat-Hash (40 Hexzeichen) und Speichernamen und sucht das
    Zertifikat in Cert:\LocalMachine\<Speicher>. Ohne erkannten Speichernamen werden My und
    WebHosting durchsucht. Nur lesend; keine privaten Schlüssel; keine Änderung an Bindungen.
EN: Runs netsh http show sslcert, detects bindings (IP:port, hostname:port, Central Certificate
    Store), their certificate hash (40 hex characters) and store name and resolves the certificate
    in Cert:\LocalMachine\<store>. Without a detected store name, My and WebHosting are searched.
    Read-only; no private keys; bindings are never changed.
DE: Sprachhinweis: netsh-Beschriftungen sind lokalisiert. Bindungen werden über Werte im Format
    Host:Port, der Hash über das 40-Hex-Muster erkannt; nur der Speichername hängt von der
    Beschriftung ab (Englisch "Store Name", Deutsch "Speichername"), sonst Fallback My/WebHosting.
EN: Locale caveat: netsh labels are localized. Bindings are detected by host:port values and the
    hash by the 40-hex pattern; only the store name depends on the label (English "Store Name",
    German "Speichername"), otherwise fallback My/WebHosting.
DE: Bericht begrenzt (MaxRecords, Befunde zuerst) und auf 4000 Zeichen gekürzt (Truncated/TotalBindings).
EN: Report bounded (MaxRecords, findings first) and shrunk to 4000 characters (Truncated/TotalBindings).
.PARAMETER WarningDays
DE: NinjaOne Integer certSslBindingWarningDays; 0..3650; Standard 30.
EN: NinjaOne Integer certSslBindingWarningDays; 0..3650; default 30.
.PARAMETER MaxRecords
DE: NinjaOne Integer certSslBindingMaxRecords; 1..100; Standard 25.
EN: NinjaOne Integer certSslBindingMaxRecords; 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkSslBindingCertificates.ps1
DE: Prüft alle HTTP.sys-Bindungen mit 30 Tagen Vorlauf.
EN: Checks all HTTP.sys bindings with 30 days lead time.
.EXAMPLE
.\checkSslBindingCertificates.ps1 -WarningDays 45 -MaxRecords 10 -CustomField sslBindingReport
DE: 45 Tage Vorlauf, höchstens 10 Einträge; JSON in sslBindingReport.
EN: 45 days lead time, at most 10 records; JSON to sslBindingReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = OK (auch ohne Bindungen), 1 = Eingabe-,
    netsh-, Abfrage- oder Schreibfehler, 2 = Bindung ohne Hash, Zertifikat fehlt im Speicher,
    abgelaufen oder läuft innerhalb WarningDays ab. Central-Certificate-Store-Bindungen: NotApplicable.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = OK (also without bindings), 1 = input,
    netsh, query or write error, 2 = binding without hash, certificate missing from store,
    expired or expiring within WarningDays. Central Certificate Store bindings: NotApplicable.
#>
[CmdletBinding()]
param(
    [string]$WarningDays = $env:certSslBindingWarningDays,
    [string]$MaxRecords = $env:certSslBindingMaxRecords,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $WarningDays = ([string]$WarningDays).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $WarningDays -or $WarningDays -ieq 'null') { $WarningDays = '30' }
    if (-not $MaxRecords -or $MaxRecords -ieq 'null') { $MaxRecords = '25' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $days = 0
    $limit = 0
    if ($WarningDays -notmatch '^\d{1,4}$' -or -not [int]::TryParse($WarningDays, [ref]$days) -or $days -gt 3650) { throw 'certSslBindingWarningDays: 0..3650 erforderlich / required.' }
    if ($MaxRecords -notmatch '^\d{1,3}$' -or -not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'certSslBindingMaxRecords: 1..100 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    # DE: stderr unter EAP Stop wäre terminierend. EN: stderr would be terminating under EAP Stop.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $lines = @(netsh http show sslcert 2>&1 | ForEach-Object { [string]$_ })
        $netshExit = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($netshExit -ne 0) { throw "netsh Exitcode / exit code $netshExit." }

    $bindings = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^\s*(?<label>\S.*?)\s+:\s*(?<value>.*?)\s*$')
        if (-not $m.Success) { continue }
        $label = $m.Groups['label'].Value
        $value = $m.Groups['value'].Value
        if ($label -match '(?i)port' -and $value -match '^(?:\[[0-9A-Fa-f:.%]+\]|[^\s:\[\]]+):\d{1,5}$') {
            $kind = 'Other'
            if ($label -match '(?i)^ip') { $kind = 'IP' } elseif ($label -match '(?i)^host') { $kind = 'Hostname' }
            $current = @{ Endpoint = $value; Kind = $kind; Hash = $null; Store = $null }
            $bindings.Add($current)
            continue
        }
        if ($label -match '(?i)central|ccs' -and $value -match '^\d{1,5}$') {
            $current = @{ Endpoint = $value; Kind = 'CentralCertificateStore'; Hash = $null; Store = $null }
            $bindings.Add($current)
            continue
        }
        if ($null -eq $current) { continue }
        if (-not $current.Hash -and $value -match '^[0-9A-Fa-f]{40}$') { $current.Hash = $value.ToUpperInvariant(); continue }
        if (-not $current.Store -and $label -match '(?i)store\s*name|speichername' -and $label -notmatch '(?i)ctl' -and $value -match '^[A-Za-z][A-Za-z0-9 _-]{0,63}$') { $current.Store = $value }
    }

    $storeCache = @{}
    $now = [DateTime]::UtcNow
    $records = @(foreach ($binding in $bindings) {
        $status = 'OK'
        $certificate = $null
        $usedStore = $binding.Store
        if ($binding.Kind -eq 'CentralCertificateStore') {
            $status = 'NotApplicable'
        } elseif (-not $binding.Hash) {
            $status = 'NoHash'
        } else {
            $candidates = @('My', 'WebHosting')
            if ($binding.Store) { $candidates = @($binding.Store) }
            foreach ($storeName in $candidates) {
                $key = $storeName.ToUpperInvariant()
                if (-not $storeCache.ContainsKey($key)) {
                    try { $storeCache[$key] = @(Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction Stop | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }) }
                    catch [System.Management.Automation.ItemNotFoundException] { $storeCache[$key] = @() }
                }
                $hit = @($storeCache[$key] | Where-Object { $_.Thumbprint -eq $binding.Hash } | Select-Object -First 1)
                if ($hit.Count -gt 0) { $certificate = $hit[0]; $usedStore = $storeName; break }
            }
            if ($null -eq $certificate) { $status = 'CertificateMissing' }
        }
        $notAfter = $null
        $remaining = $null
        if ($null -ne $certificate) {
            $expiry = $certificate.NotAfter.ToUniversalTime()
            $notAfter = $expiry.ToString('o')
            $remaining = [int][Math]::Floor(($expiry - $now).TotalDays)
            if ($expiry -le $now) { $status = 'Expired' } elseif ($expiry -le $now.AddDays($days)) { $status = 'ExpiringSoon' }
        }
        [pscustomobject][ordered]@{
            Endpoint = $binding.Endpoint; Kind = $binding.Kind; Thumbprint = $binding.Hash; Store = $usedStore
            Subject = $(if ($certificate) { $certificate.Subject } else { $null })
            NotAfterUtc = $notAfter; DaysRemaining = $remaining; Status = $status
            Finding = $status -notin @('OK', 'NotApplicable')
        }
    })
    $findingCount = @($records | Where-Object { $_.Finding }).Count
    $all = @(@($records | Where-Object { $_.Finding }) + @($records | Where-Object { -not $_.Finding }))
    $selected = @($all | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; WarningDays = $days; TotalBindings = $all.Count; FindingCount = $findingCount
            ReportedRecords = $selected.Count; Truncated = $selected.Count -lt $all.Count; Bindings = $selected
        })
        if ($report.Length -le 4000) { break }
        if ($selected.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $selected = @($selected | Select-Object -First ($selected.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findingCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
