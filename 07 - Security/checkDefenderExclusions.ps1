#Requires -Version 5.1

<#
.SYNOPSIS
DE: Inventarisiert Microsoft-Defender-Ausschluesse und vergleicht sie mit einer Allowlist.
EN: Inventories Microsoft Defender exclusions and compares them with an allowlist.
.DESCRIPTION
DE: Liest per Get-MpPreference ExclusionPath, ExclusionExtension, ExclusionProcess und
    ExclusionIpAddress. Je Kategorie: State None (keine), Listed (Eintraege) oder Hidden
    (Windows liefert "N/A: Must be an administrator to view exclusions", z. B. bei
    HideExclusionsFromLocalAdmins/Tamper Protection ohne passende Rechte). Kein Wert gesetzt =
    NotConfigured = Windows-Standard ohne Ausschluesse (Defender-eigene automatische
    Server-Rollen-Ausschluesse erscheinen hier nicht). Eintraege werden begrenzt (MaxRecords,
    nicht erlaubte zuerst) und so lange gekuerzt, bis der Bericht <= 4000 Zeichen ist
    (Truncated/TotalExclusions). Allowlist: Komma/Semikolon/Zeilen-getrennt, Vergleich exakt und
    ohne Gross-/Kleinschreibung, fuer alle Kategorien gemeinsam.
EN: Reads ExclusionPath, ExclusionExtension, ExclusionProcess and ExclusionIpAddress via
    Get-MpPreference. Per category: State None, Listed (entries) or Hidden (Windows returns
    "N/A: Must be an administrator to view exclusions", e.g. with HideExclusionsFromLocalAdmins/
    tamper protection without sufficient rights). No value set = NotConfigured = Windows default
    without exclusions (Defender's automatic server role exclusions are not listed here). Entries
    are bounded (MaxRecords, unapproved first) and shrunk until the report is <= 4000 characters
    (Truncated/TotalExclusions). Allowlist: comma/semicolon/newline separated, exact
    case-insensitive match, shared across all categories.
DE: Exit 2 = WarnOnAny=true und mindestens ein Ausschluss; oder Allowlist gesetzt und ein
    Ausschluss nicht darin; oder WarnOnHidden=true und eine Kategorie Hidden.
    Hinweis: Mit WarnOnAny=true (Standard) wirkt die Allowlist nur als Markierung (Allowed);
    fuer Allowlist-Pruefung WarnOnAny=false setzen. WarnOnAny=false ohne Allowlist = nur Inventar.
EN: Exit 2 = WarnOnAny=true and at least one exclusion; or allowlist set and an exclusion not
    on it; or WarnOnHidden=true and a category is Hidden.
    Note: With WarnOnAny=true (default) the allowlist only marks entries (Allowed); set
    WarnOnAny=false for allowlist checking. WarnOnAny=false without allowlist = inventory only.
.PARAMETER Allowlist
DE: NinjaOne Text securityDefenderExclusionAllowlist: erlaubte Eintraege, max. 200, je max. 1024 Zeichen, keine Steuerzeichen; Standard leer.
EN: NinjaOne text securityDefenderExclusionAllowlist: allowed entries, max. 200, each max. 1024 characters, no control characters; default empty.
.PARAMETER WarnOnAny
DE: NinjaOne Checkbox/Text securityDefenderWarnOnAnyExclusion: true/false; Standard true.
EN: NinjaOne checkbox/text securityDefenderWarnOnAnyExclusion: true/false; default true.
.PARAMETER WarnOnHidden
DE: NinjaOne Checkbox/Text securityDefenderWarnOnHiddenExclusions: true/false; Standard true.
EN: NinjaOne checkbox/text securityDefenderWarnOnHiddenExclusions: true/false; default true.
.PARAMETER MaxRecords
DE: NinjaOne Integer securityDefenderExclusionMaxRecords: 1..200; Standard 25.
EN: NinjaOne integer securityDefenderExclusionMaxRecords: 1..200; default 25.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkDefenderExclusions.ps1
DE: Warnt bei jedem Defender-Ausschluss.
EN: Warns on any Defender exclusion.
.EXAMPLE
.\checkDefenderExclusions.ps1 -WarnOnAny false -Allowlist 'C:\App\Data;.ldf;sqlservr.exe' -CustomField defenderExclusions
DE: Warnt nur bei Ausschluessen ausserhalb der Allowlist; JSON in defenderExclusions.
EN: Warns only on exclusions outside the allowlist; JSON to defenderExclusions.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler (z. B. Defender nicht aktiv), 2 = Befund.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = OK, 1 = input/query/write error (e.g. Defender not active), 2 = finding.
#>
[CmdletBinding()]
param(
    [string]$Allowlist = $env:securityDefenderExclusionAllowlist,
    [string]$WarnOnAny = $env:securityDefenderWarnOnAnyExclusion,
    [string]$WarnOnHidden = $env:securityDefenderWarnOnHiddenExclusions,
    [string]$MaxRecords = $env:securityDefenderExclusionMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $Allowlist = ([string]$Allowlist).Trim()
    if ($Allowlist -ieq 'null') { $Allowlist = '' }
    $WarnOnAny = ([string]$WarnOnAny).Trim()
    if ($WarnOnAny -ieq 'null' -or -not $WarnOnAny) { $WarnOnAny = 'true' }
    $anyWarns = $false
    if (-not [bool]::TryParse($WarnOnAny, [ref]$anyWarns)) { throw 'WarnOnAny muss true/false sein / must be true/false.' }
    $WarnOnHidden = ([string]$WarnOnHidden).Trim()
    if ($WarnOnHidden -ieq 'null' -or -not $WarnOnHidden) { $WarnOnHidden = 'true' }
    $hiddenWarns = $false
    if (-not [bool]::TryParse($WarnOnHidden, [ref]$hiddenWarns)) { throw 'WarnOnHidden muss true/false sein / must be true/false.' }
    $MaxRecords = ([string]$MaxRecords).Trim()
    if ($MaxRecords -ieq 'null' -or -not $MaxRecords) { $MaxRecords = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'MaxRecords muss 1..200 sein / must be 1..200.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }

    $allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in ($Allowlist -split '[,;\r\n]+')) {
        $entry = $entry.Trim()
        if (-not $entry) { continue }
        if ($entry.Length -gt 1024 -or $entry -match '[\x00-\x1F]') { throw 'Ungueltiger Allowlist-Eintrag / Invalid allowlist entry.' }
        $null = $allowed.Add($entry)
    }
    if ($allowed.Count -gt 200) { throw 'Allowlist max. 200 Eintraege / entries.' }
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) { throw 'Get-MpPreference fehlt / unavailable.' }

    $preference = Get-MpPreference
    if ($null -eq $preference) { throw 'Defender-Einstellungen fehlen / Defender preferences unavailable.' }
    $categories = New-Object System.Collections.Generic.List[object]
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($name in @('ExclusionPath', 'ExclusionExtension', 'ExclusionProcess', 'ExclusionIpAddress')) {
        $values = @(@($preference.$name) | Where-Object { $null -ne $_ -and ([string]$_).Trim() } | ForEach-Object { ([string]$_).Trim() })
        $state = 'None'
        if (@($values | Where-Object { $_ -match '^N/A\s*:' }).Count -gt 0) { $state = 'Hidden' }
        elseif ($values.Count -gt 0) { $state = 'Listed' }
        $count = $values.Count
        if ($state -eq 'Hidden') { $count = $null }
        $categories.Add([pscustomobject]@{ Category = $name; State = $state; Count = $count })
        if ($state -ne 'Listed') { continue }
        foreach ($value in $values) { $entries.Add([pscustomobject]@{ Category = $name; Value = $value; Allowed = $allowed.Contains($value) }) }
    }
    $unapproved = @($entries | Where-Object { -not $_.Allowed }).Count
    $hidden = @($categories | Where-Object { $_.State -eq 'Hidden' } | ForEach-Object { $_.Category })

    $findings = New-Object System.Collections.Generic.List[string]
    if ($anyWarns -and $entries.Count -gt 0) { $findings.Add('ExclusionsPresent') }
    if ($allowed.Count -gt 0 -and $unapproved -gt 0) { $findings.Add('UnapprovedExclusions') }
    if ($hiddenWarns -and $hidden.Count -gt 0) { $findings.Add('ExclusionsHidden') }
    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }

    $sorted = @($entries | Sort-Object -Property @{ Expression = { $_.Allowed } }, Category, Value)
    $records = @($sorted | Select-Object -First $limit)
    do {
        $truncated = $records.Count -lt $sorted.Count
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Status = $status; WarnOnAny = $anyWarns; WarnOnHidden = $hiddenWarns; AllowlistCount = $allowed.Count
            TotalExclusions = $entries.Count; UnapprovedExclusions = $unapproved; HiddenCategories = $hidden
            Categories = $categories.ToArray(); ReportedEntries = $records.Count; Truncated = $truncated
            Entries = $records; Findings = @($findings)
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu gross / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
