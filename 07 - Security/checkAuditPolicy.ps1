#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prueft die erweiterte Ueberwachungsrichtlinie gegen eine Liste Pflicht-Unterkategorien (GUID-basiert).
    EN: Checks the advanced audit policy against a list of required subcategories (GUID based).
.DESCRIPTION
    DE: Fuehrt "auditpol /get /category:* /r" aus (CSV) und ordnet Zeilen ueber die Spalte
        "Subcategory GUID" zu (unabhaengig von lokalisierten Namen). Die Spalte "Inclusion Setting" ist
        lokalisiert; erkannt werden Englisch und Deutsch (Success/Erfolg, Failure/Fehler, No Auditing/Keine
        Ueberwachung). Unbekannter Text einer Pflicht-Unterkategorie fuehrt zu Exit 1 statt einer falschen
        Bewertung. Standard-Basislinie (angelehnt an Microsoft-Sicherheitsbaselines):
        Credential Validation {0CCE923F-...} = SuccessAndFailure, Logon {0CCE9215-...} = SuccessAndFailure,
        Account Lockout {0CCE9217-...} = Failure, User Account Management {0CCE9235-...} = SuccessAndFailure,
        Security Group Management {0CCE9237-...} = Success, Process Creation {0CCE922B-...} = Success,
        Audit Policy Change {0CCE922F-...} = Success (alle mit Suffix -69AE-11D9-BED3-505054503030).
        Zusaetzliche Einstellungen (z. B. Failure bei Anforderung Success) sind erlaubt. Der Bericht wird
        bei Bedarf auf 4000 Zeichen gekuerzt (Verstoesse zuerst, Truncated/ReportedRecords).
    EN: Runs "auditpol /get /category:* /r" (CSV) and matches rows via the "Subcategory GUID" column
        (independent of localized names). The "Inclusion Setting" column is localized; English and German
        are recognized (Success/Erfolg, Failure/Fehler, No Auditing/Keine Ueberwachung). Unknown text of a
        required subcategory causes exit 1 instead of a wrong verdict. Default baseline (based on Microsoft
        security baselines): Credential Validation {0CCE923F-...} = SuccessAndFailure, Logon {0CCE9215-...} =
        SuccessAndFailure, Account Lockout {0CCE9217-...} = Failure, User Account Management {0CCE9235-...} =
        SuccessAndFailure, Security Group Management {0CCE9237-...} = Success, Process Creation {0CCE922B-...} =
        Success, Audit Policy Change {0CCE922F-...} = Success (all with suffix -69AE-11D9-BED3-505054503030).
        Additional settings (e.g. Failure when Success is required) are allowed. The report is shrunk
        to 4000 characters if needed (violations first, Truncated/ReportedRecords).
.PARAMETER RequiredSubcategories
    DE: NinjaOne Text securityAuditRequiredSubcategories: Eintraege "{GUID}=Success|Failure|SuccessAndFailure",
        getrennt durch Komma, Semikolon oder Zeilenumbruch, max. 60; leer = Standard-Basislinie.
    EN: NinjaOne text securityAuditRequiredSubcategories: entries "{GUID}=Success|Failure|SuccessAndFailure",
        separated by comma, semicolon or newline, max. 60; empty = default baseline.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkAuditPolicy.ps1
    DE: Prueft die Standard-Basislinie.
    EN: Checks the default baseline.
.EXAMPLE
    .\checkAuditPolicy.ps1 -RequiredSubcategories '{0CCE9215-69AE-11D9-BED3-505054503030}=Failure' -CustomField auditPolicy
    DE: Verlangt nur Fehlerueberwachung fuer Anmelden; JSON ins Feld auditPolicy.
    EN: Requires only failure auditing for Logon; JSON to the field auditPolicy.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter vor Variablen. Gruppenrichtlinien mit
        "Ueberwachungsrichtlinien-Unterkategorien erzwingen" deaktiviert koennen abweichen.
        Exit 0 = OK, 1 = Eingabe-/auditpol-/Parse-/Schreibfehler, 2 = Pflicht-Unterkategorie fehlt oder
        Einstellung unzureichend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables. Results may differ
        when "Force audit policy subcategory settings" is disabled.
        Exit 0 = OK, 1 = input/auditpol/parse/write error, 2 = required subcategory missing or
        setting insufficient.
#>
[CmdletBinding()]
param(
    [string]$RequiredSubcategories = $env:securityAuditRequiredSubcategories,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $text = ([string]$RequiredSubcategories).Trim()
    if (-not $text -or $text -ieq 'null') {
        $text = '{0CCE923F-69AE-11D9-BED3-505054503030}=SuccessAndFailure,{0CCE9215-69AE-11D9-BED3-505054503030}=SuccessAndFailure,' +
            '{0CCE9217-69AE-11D9-BED3-505054503030}=Failure,{0CCE9235-69AE-11D9-BED3-505054503030}=SuccessAndFailure,' +
            '{0CCE9237-69AE-11D9-BED3-505054503030}=Success,{0CCE922B-69AE-11D9-BED3-505054503030}=Success,' +
            '{0CCE922F-69AE-11D9-BED3-505054503030}=Success'
    }
    $required = [ordered]@{}
    foreach ($entry in ($text -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if ($entry -notmatch '^\{?([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\}?\s*=\s*(Success|Failure|SuccessAndFailure)$') {
            throw "securityAuditRequiredSubcategories: ungueltiger Eintrag / invalid entry '$entry'."
        }
        $required['{' + $Matches[1].ToUpperInvariant() + '}'] = $Matches[2]
    }
    if ($required.Count -eq 0 -or $required.Count -gt 60) { throw 'securityAuditRequiredSubcategories: 1..60 Eintraege / entries.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $output = @(auditpol /get /category:* /r 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "auditpol Exitcode / exit code $code" }
    $rows = @{}
    foreach ($line in $output) {
        if ($line -notmatch '\{[0-9A-Fa-f-]{36}\}') { continue }
        $fields = @(($line | ConvertFrom-Csv -Header (1..10 | ForEach-Object { "c$_" })).PSObject.Properties | ForEach-Object { [string]$_.Value })
        for ($i = 0; $i -lt $fields.Count - 1; $i++) {
            if ($fields[$i] -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $rows[$fields[$i].ToUpperInvariant()] = [pscustomobject]@{ Name = $fields[$i - 1]; Setting = $fields[$i + 1].Trim() }
                break
            }
        }
    }
    if ($rows.Count -eq 0) { throw 'Keine auditpol-Daten / No auditpol data.' }
    $results = @(foreach ($guid in $required.Keys) {
        $want = $required[$guid]
        $row = $rows[$guid]
        $success = $false; $failure = $false; $status = 'OK'; $setting = $null; $name = $null
        if ($null -eq $row) { $status = 'Missing' }
        else {
            $setting = $row.Setting; $name = $row.Name
            $success = $setting -match 'Success|Erfolg'
            $failure = $setting -match 'Failure|Fehler'
            if (-not $success -and -not $failure -and $setting -notmatch '^(No Auditing|Keine)') {
                throw "Unbekannte Einstellung / Unrecognized setting '$setting' for $guid."
            }
            if (($want -match 'Success' -and -not $success) -or ($want -match 'Failure' -and -not $failure)) { $status = 'Insufficient' }
        }
        [pscustomobject]@{ Guid = $guid; Subcategory = $name; Required = $want; Success = $success; Failure = $failure; Status = $status }
    })
    $violations = @($results | Where-Object { $_.Status -ne 'OK' }).Count
    # DE: Verstoesse zuerst; bei Bedarf bis 4000 Zeichen kuerzen. EN: Violations first; shrink to 4000 characters if needed.
    $records = @(@($results | Where-Object { $_.Status -ne 'OK' }) + @($results | Where-Object { $_.Status -eq 'OK' }))
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            RequiredCount = $results.Count; Violations = $violations; ReportedRecords = $records.Count
            Truncated = $records.Count -lt $results.Count; Subcategories = $records
        })
        if ($report.Length -le 4000 -or $records.Count -eq 0) { break }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($violations -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
