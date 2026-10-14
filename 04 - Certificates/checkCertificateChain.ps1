#Requires -Version 5.1

<#
.SYNOPSIS
DE: Baut Zertifikatsketten für Maschinenzertifikate mit privatem Schlüssel und meldet Kettenfehler.
EN: Builds certificate chains for machine certificates with a private key and reports chain errors.
.DESCRIPTION
DE: Liest LocalMachine\My per Get-ChildItem, berücksichtigt nur Zertifikate mit privatem Schlüssel
    (HasPrivateKey; der Schlüssel wird nie gelesen oder exportiert), sortiert nach Thumbprint und
    prüft höchstens MaxCertificates mit X509Chain.Build. Sperrprüfung: NoCheck (Standard), Offline
    (nur Cache) oder Online (Netzwerk, 10 s URL-Timeout). Gesamtzeitbudget 120 s; nicht geprüfte
    Zertifikate erscheinen in NotChecked. Im Modus Offline zählen RevocationStatusUnknown und
    OfflineRevocation nicht als Fehler (werden aber gemeldet), in Online schon.
EN: Reads LocalMachine\My via Get-ChildItem, considers only certificates with a private key
    (HasPrivateKey; the key is never read or exported), sorts by thumbprint and checks at most
    MaxCertificates with X509Chain.Build. Revocation: NoCheck (default), Offline (cache only) or
    Online (network, 10 s URL timeout). Total time budget 120 s; unchecked certificates are counted
    in NotChecked. In Offline mode RevocationStatusUnknown and OfflineRevocation are reported but
    not counted as errors; in Online mode they are.
DE: Bericht: Fehler zuerst, auf 4000 Zeichen gekürzt (Truncated/ReportedRecords).
EN: Report: errors first, shrunk to 4000 characters (Truncated/ReportedRecords).
.PARAMETER RevocationMode
DE: NinjaOne Dropdown/Text certChainRevocationMode; NoCheck, Offline oder Online; Standard NoCheck.
EN: NinjaOne drop-down/text certChainRevocationMode; NoCheck, Offline or Online; default NoCheck.
.PARAMETER MaxCertificates
DE: NinjaOne Integer certChainMaxCertificates; 1..200; Standard 50.
EN: NinjaOne Integer certChainMaxCertificates; 1..200; default 50.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkCertificateChain.ps1
DE: Prüft Ketten ohne Sperrprüfung.
EN: Checks chains without revocation checking.
.EXAMPLE
.\checkCertificateChain.ps1 -RevocationMode Online -MaxCertificates 20 -CustomField certificateChainReport
DE: Online-Sperrprüfung für höchstens 20 Zertifikate; JSON in certificateChainReport.
EN: Online revocation checking for at most 20 certificates; JSON to certificateChainReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Kettenbau kann im Modus Online AIA/CRL/OCSP abrufen
    (reine Prüfung, keine Installation). Exit 0 = keine Kettenfehler, 1 = Eingabe-, Abfrage- oder
    Schreibfehler, 2 = mindestens ein geprüftes Zertifikat mit Kettenfehler (z. B. UntrustedRoot,
    NotTimeValid, PartialChain, Revoked).
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Chain building in Online mode may fetch AIA/CRL/OCSP
    (verification only, no installation). Exit 0 = no chain errors, 1 = input, query or write
    error, 2 = at least one checked certificate with chain errors (e.g. UntrustedRoot,
    NotTimeValid, PartialChain, Revoked).
#>
[CmdletBinding()]
param(
    [string]$RevocationMode = $env:certChainRevocationMode,
    [string]$MaxCertificates = $env:certChainMaxCertificates,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $RevocationMode = ([string]$RevocationMode).Trim()
    $MaxCertificates = ([string]$MaxCertificates).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $RevocationMode -or $RevocationMode -ieq 'null') { $RevocationMode = 'NoCheck' }
    if (-not $MaxCertificates -or $MaxCertificates -ieq 'null') { $MaxCertificates = '50' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $modeName = @('NoCheck', 'Offline', 'Online') | Where-Object { $_ -ieq $RevocationMode } | Select-Object -First 1
    if (-not $modeName) { throw 'certChainRevocationMode: NoCheck, Offline oder/or Online.' }
    $limit = 0
    if ($MaxCertificates -notmatch '^\d{1,3}$' -or -not [int]::TryParse($MaxCertificates, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'certChainMaxCertificates: 1..200 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $mode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]$modeName
    $candidates = @(Get-ChildItem -Path 'Cert:\LocalMachine\My' |
        Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and $_.HasPrivateKey } |
        Sort-Object Thumbprint)
    $ignored = @()
    if ($modeName -eq 'Offline') { $ignored = @('RevocationStatusUnknown', 'OfflineRevocation') }
    $budget = [Diagnostics.Stopwatch]::StartNew()
    $checked = 0
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($certificate in ($candidates | Select-Object -First $limit)) {
        if ($budget.Elapsed.TotalSeconds -ge 120) { break }
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        try {
            $chain.ChainPolicy.RevocationMode = $mode
            $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::ExcludeRoot
            $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(10)
            $null = $chain.Build($certificate)
            $statuses = @($chain.ChainStatus | ForEach-Object { [string]$_.Status } | Sort-Object -Unique)
            $length = $chain.ChainElements.Count
        } finally {
            if ($chain -is [IDisposable]) { $chain.Dispose() } else { $chain.Reset() }
        }
        $checked++
        $errors = @($statuses | Where-Object { $_ -and $_ -ne 'NoError' -and $ignored -notcontains $_ })
        $results.Add([pscustomobject][ordered]@{
            Thumbprint = $certificate.Thumbprint; Subject = $certificate.Subject
            NotAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o'); ChainLength = $length
            Valid = $errors.Count -eq 0; ChainStatus = $statuses
        })
    }
    $budget.Stop()
    $errorCount = @($results | Where-Object { -not $_.Valid }).Count
    $ordered = @(@($results | Where-Object { -not $_.Valid }) + @($results | Where-Object { $_.Valid }))
    $selected = $ordered
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Store = 'LocalMachine\My'; RevocationMode = $modeName
            TotalWithPrivateKey = $candidates.Count; Checked = $checked; NotChecked = $candidates.Count - $checked
            ErrorCount = $errorCount; ReportedRecords = $selected.Count; Truncated = $selected.Count -lt $ordered.Count
            Certificates = $selected
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
    if ($errorCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
