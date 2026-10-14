#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft, ob bestimmte Zertifikate (Thumbprint und/oder exakter Betreff) in einem Maschinenspeicher vorhanden und gültig sind.
EN: Checks whether specific certificates (thumbprint and/or exact subject) exist and are valid in a machine store.
.DESCRIPTION
DE: Liest Cert:\LocalMachine\<StoreName> per Get-ChildItem. Jeder Thumbprint wird exakt gesucht;
    der Betreff wird exakt (ohne Groß-/Kleinschreibung, keine Wildcards) mit Subject verglichen.
    Status je Eintrag: Present, Missing, Expired oder NotYetValid. Bei mehreren Treffern für den
    Betreff genügt ein aktuell gültiges Zertifikat. Nur lesend; keine privaten Schlüssel.
EN: Reads Cert:\LocalMachine\<StoreName> via Get-ChildItem. Each thumbprint is matched exactly;
    the subject is compared exactly (case-insensitive, no wildcards) with Subject. Status per
    entry: Present, Missing, Expired or NotYetValid. With several subject matches one currently
    valid certificate is sufficient. Read-only; no private keys.
.PARAMETER StoreName
DE: NinjaOne Dropdown/Text certPresenceStoreName; Standard My; erlaubt My, Root, CA, AuthRoot,
    TrustedPublisher, TrustedPeople, Disallowed, WebHosting, Remote Desktop.
EN: NinjaOne drop-down/text certPresenceStoreName; default My; allowed My, Root, CA, AuthRoot,
    TrustedPublisher, TrustedPeople, Disallowed, WebHosting, Remote Desktop.
.PARAMETER Thumbprints
DE: NinjaOne Text certPresenceThumbprints; Standard leer; bis 50 komma-/semikolongetrennte Werte zu je 40 Hexzeichen.
EN: NinjaOne text certPresenceThumbprints; default empty; up to 50 comma/semicolon-separated values of 40 hex characters.
.PARAMETER Subject
DE: NinjaOne Text certPresenceSubject; Standard leer; exakter Betreff (z. B. CN=web01.contoso.com), max. 512 Zeichen, keine Steuerzeichen.
    Thumbprints oder Subject ist erforderlich.
EN: NinjaOne text certPresenceSubject; default empty; exact subject (e.g. CN=web01.contoso.com), max. 512 characters, no control characters.
    Thumbprints or Subject is required.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkCertificatePresence.ps1 -Thumbprints 'CABD2A79A1076A31F21D253635CB039D4329A5E8' -StoreName Root
DE: Prüft, ob ISRG Root X1 in LocalMachine\Root vorhanden und gültig ist.
EN: Checks that ISRG Root X1 is present and valid in LocalMachine\Root.
.EXAMPLE
.\checkCertificatePresence.ps1 -Subject 'CN=web01.contoso.com' -CustomField certificatePresence
DE: Prüft LocalMachine\My auf ein gültiges Zertifikat mit genau diesem Betreff; JSON in certificatePresence.
EN: Checks LocalMachine\My for a valid certificate with exactly this subject; JSON to certificatePresence.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = alle vorhanden und gültig, 1 = Eingabe-,
    Abfrage- oder Schreibfehler (auch fehlender Speicher), 2 = mindestens ein Eintrag fehlt,
    ist abgelaufen oder noch nicht gültig.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = all present and valid, 1 = input, query
    or write error (including missing store), 2 = at least one entry missing, expired or not
    yet valid.
#>
[CmdletBinding()]
param(
    [string]$StoreName = $env:certPresenceStoreName,
    [string]$Thumbprints = $env:certPresenceThumbprints,
    [string]$Subject = $env:certPresenceSubject,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $StoreName = ([string]$StoreName).Trim()
    $Thumbprints = ([string]$Thumbprints).Trim()
    $Subject = ([string]$Subject).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $StoreName -or $StoreName -ieq 'null') { $StoreName = 'My' }
    if ($Thumbprints -ieq 'null') { $Thumbprints = '' }
    if ($Subject -ieq 'null') { $Subject = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $allowedStores = @('My', 'Root', 'CA', 'AuthRoot', 'TrustedPublisher', 'TrustedPeople', 'Disallowed', 'WebHosting', 'Remote Desktop')
    $store = @($allowedStores | Where-Object { $_ -ieq $StoreName } | Select-Object -First 1)
    if ($store.Count -eq 0) { throw 'certPresenceStoreName: nicht erlaubter Speicher / store not allowed.' }
    $store = $store[0]
    $wanted = @()
    if ($Thumbprints) {
        if ($Thumbprints.Length -gt 3000) { throw 'certPresenceThumbprints zu lang / too long.' }
        $wanted = @(($Thumbprints -split '[,;]') | ForEach-Object { ($_ -replace '[\s\u200E\u200F]', '').ToUpperInvariant() })
        if ($wanted.Count -gt 50 -or @($wanted | Where-Object { $_ -notmatch '^[0-9A-F]{40}$' }).Count -gt 0) { throw 'certPresenceThumbprints: bis 50 x 40 Hexzeichen / up to 50 x 40 hex characters.' }
        $wanted = @($wanted | Sort-Object -Unique)
    }
    if ($Subject -and ($Subject.Length -gt 512 -or $Subject -match '[\x00-\x1F\x7F]')) { throw 'certPresenceSubject: max. 512 Zeichen, keine Steuerzeichen / no control characters.' }
    if ($wanted.Count -eq 0 -and -not $Subject) { throw 'certPresenceThumbprints oder/or certPresenceSubject erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $certificates = @(Get-ChildItem -Path "Cert:\LocalMachine\$store" -ErrorAction Stop | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] })
    $now = [DateTime]::UtcNow
    $checks = New-Object System.Collections.Generic.List[object]
    $targets = @($wanted | ForEach-Object { @{ Type = 'Thumbprint'; Value = $_ } })
    if ($Subject) { $targets += @{ Type = 'Subject'; Value = $Subject } }
    foreach ($target in $targets) {
        if ($target.Type -eq 'Thumbprint') {
            $found = @($certificates | Where-Object { $_.Thumbprint -eq $target.Value })
        } else {
            $found = @($certificates | Where-Object { [string]::Equals([string]$_.Subject, $target.Value, [StringComparison]::OrdinalIgnoreCase) })
        }
        $valid = @($found | Where-Object { $_.NotBefore.ToUniversalTime() -le $now -and $_.NotAfter.ToUniversalTime() -gt $now })
        $status = 'Missing'
        if ($valid.Count -gt 0) { $status = 'Present' }
        elseif (@($found | Where-Object { $_.NotAfter.ToUniversalTime() -le $now }).Count -gt 0) { $status = 'Expired' }
        elseif ($found.Count -gt 0) { $status = 'NotYetValid' }
        $latest = @($found | Sort-Object NotAfter -Descending | Select-Object -First 1)
        $checks.Add([pscustomobject][ordered]@{
            Type = $target.Type; Value = $target.Value; Status = $status; Matches = $found.Count
            MatchedThumbprints = @($found | Select-Object -First 5 | ForEach-Object { $_.Thumbprint })
            LatestNotAfterUtc = $(if ($latest.Count -gt 0) { $latest[0].NotAfter.ToUniversalTime().ToString('o') } else { $null })
        })
    }
    $failed = @($checks | Where-Object { $_.Status -ne 'Present' }).Count
    $ordered = @(@($checks | Where-Object { $_.Status -ne 'Present' }) + @($checks | Where-Object { $_.Status -eq 'Present' }))
    $selected = $ordered
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; Store = "LocalMachine\$store"; StoreCertificates = $certificates.Count
            TotalChecks = $ordered.Count; FailedChecks = $failed; ReportedRecords = $selected.Count
            Truncated = $selected.Count -lt $ordered.Count; Checks = $selected
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
    if ($failed -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
