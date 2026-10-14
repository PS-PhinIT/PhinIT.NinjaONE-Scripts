#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prueft lokale Kennwort- und Sperrrichtlinie sprachunabhaengig per secedit-Export.
    EN: Checks local password and lockout policy locale-independently via secedit export.
.DESCRIPTION
    DE: Exportiert mit "secedit /export /cfg <Temp-Datei> /areas SECURITYPOLICY /quiet" und liest die
        sprachunabhaengigen INI-Schluessel des Abschnitts [System Access]: MinimumPasswordLength,
        PasswordComplexity, PasswordHistorySize, MaximumPasswordAge, MinimumPasswordAge, LockoutBadCount,
        LockoutDuration, ResetLockoutCount, ClearTextPassword. "net accounts" wird bewusst nicht genutzt
        (lokalisierte Ausgabe). Die Temp-Datei (keine Hashes/Kennwoerter) wird im finally geloescht.
        Auf Domaenenmitgliedern gilt die Domaenenrichtlinie fuer Domaenenkonten; geprueft wird die lokale
        (SAM-)Richtlinie. MaximumPasswordAge -1 = laeuft nie ab. ClearTextPassword=1 (umkehrbare
        Verschluesselung) ist immer ein Befund.
    EN: Exports with "secedit /export /cfg <temp file> /areas SECURITYPOLICY /quiet" and reads the
        language-independent INI keys of section [System Access]: MinimumPasswordLength,
        PasswordComplexity, PasswordHistorySize, MaximumPasswordAge, MinimumPasswordAge, LockoutBadCount,
        LockoutDuration, ResetLockoutCount, ClearTextPassword. "net accounts" is intentionally not used
        (localized output). The temp file (no hashes/passwords) is deleted in finally.
        On domain members the domain policy applies to domain accounts; this checks the local (SAM)
        policy. MaximumPasswordAge -1 = never expires. ClearTextPassword=1 (reversible encryption)
        is always a finding.
.PARAMETER MinLength
    DE: NinjaOne Integer securityPasswordMinLength, 0..128; Standard 12.
    EN: NinjaOne Integer securityPasswordMinLength, 0..128; default 12.
.PARAMETER RequireComplexity
    DE: NinjaOne Checkbox/Text securityPasswordRequireComplexity, true/false/1/0; Standard true.
    EN: NinjaOne checkbox/text securityPasswordRequireComplexity, true/false/1/0; default true.
.PARAMETER MinHistory
    DE: NinjaOne Integer securityPasswordMinHistory, 0..24; Standard 0 (keine Pruefung).
    EN: NinjaOne Integer securityPasswordMinHistory, 0..24; default 0 (not checked).
.PARAMETER MaxAgeDays
    DE: NinjaOne Integer securityPasswordMaxAgeDays, 0..999; Standard 0 (keine Pruefung). Sonst muss
        MaximumPasswordAge 1..MaxAgeDays sein.
    EN: NinjaOne Integer securityPasswordMaxAgeDays, 0..999; default 0 (not checked). Otherwise
        MaximumPasswordAge must be 1..MaxAgeDays.
.PARAMETER MaxLockoutThreshold
    DE: NinjaOne Integer securityLockoutMaxThreshold, 0..999; Standard 10. LockoutBadCount muss 1..Wert sein;
        0 = keine Pruefung.
    EN: NinjaOne Integer securityLockoutMaxThreshold, 0..999; default 10. LockoutBadCount must be 1..value;
        0 = not checked.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkPasswordPolicy.ps1
    DE: Mindestlaenge 12, Komplexitaet und Sperrschwelle 1..10 verlangen.
    EN: Require minimum length 12, complexity and lockout threshold 1..10.
.EXAMPLE
    .\checkPasswordPolicy.ps1 -MinLength 14 -MinHistory 24 -MaxAgeDays 365 -CustomField passwordPolicy
    DE: Strengere Vorgaben; JSON ins Feld passwordPolicy.
    EN: Stricter requirements; JSON to the field passwordPolicy.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend (Temp-Datei wird geloescht). Parameter vor Variablen.
        Exit 0 = OK, 1 = Eingabe-/secedit-/Schreibfehler, 2 = mindestens eine Vorgabe verletzt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only (temp file is deleted). Parameters override variables.
        Exit 0 = OK, 1 = input/secedit/write error, 2 = at least one requirement violated.
#>
[CmdletBinding()]
param(
    [string]$MinLength = $env:securityPasswordMinLength,
    [string]$RequireComplexity = $env:securityPasswordRequireComplexity,
    [string]$MinHistory = $env:securityPasswordMinHistory,
    [string]$MaxAgeDays = $env:securityPasswordMaxAgeDays,
    [string]$MaxLockoutThreshold = $env:securityLockoutMaxThreshold,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-IntSetting {
    param([string]$Value, [int]$Default, [int]$Minimum, [int]$Maximum, [string]$Name)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    $number = 0
    if (-not [int]::TryParse($text, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0}: {1}..{2} erforderlich / required.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
$tempFile = $null
try {
    $minLen = Get-IntSetting $MinLength 12 0 128 'securityPasswordMinLength'
    $minHist = Get-IntSetting $MinHistory 0 0 24 'securityPasswordMinHistory'
    $maxAge = Get-IntSetting $MaxAgeDays 0 0 999 'securityPasswordMaxAgeDays'
    $maxLockout = Get-IntSetting $MaxLockoutThreshold 10 0 999 'securityLockoutMaxThreshold'
    $text = ([string]$RequireComplexity).Trim()
    if (-not $text -or $text -ieq 'null') { $text = 'true' }
    if ($text -in @('true', '1')) { $complexity = $true }
    elseif ($text -in @('false', '0')) { $complexity = $false }
    else { throw 'securityPasswordRequireComplexity: true/false erforderlich / required.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }

    $tempFile = Join-Path ([IO.Path]::GetTempPath()) ('ninjaSecPol_{0}.inf' -f [guid]::NewGuid().ToString('N'))
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $null = secedit /export /cfg $tempFile /areas SECURITYPOLICY /quiet 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "secedit Exitcode / exit code $code" }
    $values = @{}
    $section = ''
    foreach ($line in @(Get-Content -LiteralPath $tempFile)) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
        if ($section -eq 'System Access' -and $line -match '^\s*([A-Za-z]+)\s*=\s*(-?\d+)\s*$') { $values[$Matches[1]] = [long]$Matches[2] }
    }
    if (-not $values.ContainsKey('MinimumPasswordLength')) { throw 'Abschnitt [System Access] fehlt / Section [System Access] missing.' }
    $findings = New-Object System.Collections.Generic.List[string]
    if ($values['MinimumPasswordLength'] -lt $minLen) { $findings.Add("MinimumPasswordLength<$minLen") }
    if ($complexity -and $values['PasswordComplexity'] -ne 1) { $findings.Add('PasswordComplexityDisabled') }
    if ($minHist -gt 0 -and $values['PasswordHistorySize'] -lt $minHist) { $findings.Add("PasswordHistorySize<$minHist") }
    if ($maxAge -gt 0 -and ($values['MaximumPasswordAge'] -lt 1 -or $values['MaximumPasswordAge'] -gt $maxAge)) { $findings.Add("MaximumPasswordAge>$maxAge") }
    if ($maxLockout -gt 0 -and ($values['LockoutBadCount'] -lt 1 -or $values['LockoutBadCount'] -gt $maxLockout)) { $findings.Add("LockoutBadCount not 1..$maxLockout") }
    if ($values['ClearTextPassword'] -eq 1) { $findings.Add('ReversibleEncryptionEnabled') }
    $policy = [ordered]@{}
    foreach ($key in @('MinimumPasswordLength', 'PasswordComplexity', 'PasswordHistorySize', 'MaximumPasswordAge', 'MinimumPasswordAge', 'LockoutBadCount', 'LockoutDuration', 'ResetLockoutCount', 'ClearTextPassword')) {
        $policy[$key] = $values[$key]
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Policy = $policy
        Requirements = [ordered]@{ MinLength = $minLen; RequireComplexity = $complexity; MinHistory = $minHist; MaxAgeDays = $maxAge; MaxLockoutThreshold = $maxLockout }
        Findings = @($findings)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
finally {
    if ($tempFile -and (Test-Path -LiteralPath $tempFile)) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
}
