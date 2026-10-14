#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Microsoft-Defender-ASR-Regeln mit Namen und Modus und prueft optionale Pflichtregeln.
    EN: Reports Microsoft Defender ASR rules with name and mode and checks optional required rules.
.DESCRIPTION
    DE: Liest AttackSurfaceReductionRules_Ids/_Actions aus Get-MpPreference (effektive Konfiguration) und ordnet
        bekannte Regel-GUIDs (Microsoft "ASR rules reference", 19 Regeln) Namen zu. Modi: 0 = Off, 1 = Block,
        2 = Audit, 5 = NotConfigured, 6 = Warn. Ohne RequiredRules nur Bericht (Exit 0). Pflichtregeln
        muessen Block sein; mit AllowAudit=true sind auch Audit und Warn zulaessig. ASR wirkt nur, wenn
        Defender Antivirus aktiv ist (nicht passiv); das prueft checkWindowsDefender.ps1. Keine Aenderungen.
        Der Bericht wird bei Bedarf auf 4000 Zeichen gekuerzt (Verstoesse vollstaendig, Truncated).
    EN: Reads AttackSurfaceReductionRules_Ids/_Actions from Get-MpPreference (effective configuration) and maps
        known rule GUIDs (Microsoft "ASR rules reference", 19 rules) to names. Modes: 0 = Off, 1 = Block,
        2 = Audit, 5 = NotConfigured, 6 = Warn. Without RequiredRules report only (exit 0). Required rules
        must be Block; with AllowAudit=true Audit and Warn are accepted too. ASR only applies when Defender
        Antivirus is active (not passive); see checkWindowsDefender.ps1. No changes.
        The report is shrunk to 4000 characters if needed (violations kept, Truncated).
.PARAMETER RequiredRules
    DE: NinjaOne Text securityAsrRequiredRules: Regel-GUIDs, getrennt durch Komma/Semikolon/Zeilenumbruch,
        max. 25; Standard leer (nur Bericht).
    EN: NinjaOne text securityAsrRequiredRules: rule GUIDs separated by comma/semicolon/newline,
        max. 25; default empty (report only).
.PARAMETER AllowAudit
    DE: NinjaOne Checkbox/Text securityAsrAllowAudit, true/false/1/0; Standard false.
    EN: NinjaOne checkbox/text securityAsrAllowAudit, true/false/1/0; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkDefenderAsrRules.ps1
    DE: Listet alle konfigurierten ASR-Regeln mit Namen und Modus.
    EN: Lists all configured ASR rules with name and mode.
.EXAMPLE
    .\checkDefenderAsrRules.ps1 -RequiredRules '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2,56a863a9-875e-4185-98a7-b882c64b5ce5' -CustomField asrRules
    DE: LSASS-Schutz und Treiber-Missbrauchsregel muessen Block sein; JSON ins Feld asrRules.
    EN: LSASS protection and vulnerable-driver rule must be Block; JSON to the field asrRules.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter vor Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler (z. B. Defender-Modul fehlt),
        2 = Pflichtregel fehlt oder nicht im geforderten Modus.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error (e.g. Defender module missing),
        2 = required rule missing or not in the required mode.
#>
[CmdletBinding()]
param(
    [string]$RequiredRules = $env:securityAsrRequiredRules,
    [string]$AllowAudit = $env:securityAsrAllowAudit,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $known = @{
        '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Block abuse of exploited vulnerable signed drivers'
        '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Block Adobe Reader from creating child processes'
        'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block all Office applications from creating child processes'
        '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Block credential stealing from LSASS'
        'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email client and webmail'
        '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executables unless prevalence, age or trusted list criterion'
        '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
        'd3e037e1-3eb8-44c8-a917-57927947596d' = 'Block JavaScript or VBScript from launching downloaded executable content'
        '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office applications from creating executable content'
        '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office applications from injecting code into other processes'
        '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication application from creating child processes'
        'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Block persistence through WMI event subscription'
        'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'Block process creations originating from PSExec and WMI commands'
        '33ddedf1-c6e0-47cb-833e-de6133960387' = 'Block rebooting machine in Safe Mode'
        'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted and unsigned processes that run from USB'
        'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'Block use of copied or impersonated system tools'
        'a8f5898e-1dc8-49a9-9878-85004b8a61e6' = 'Block Webshell creation for Servers'
        '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
        'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'Use advanced protection against ransomware'
    }
    $modes = @{ 0 = 'Off'; 1 = 'Block'; 2 = 'Audit'; 5 = 'NotConfigured'; 6 = 'Warn' }
    $guidPattern = '^\{?([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\}?$'
    $required = New-Object System.Collections.Generic.List[string]
    foreach ($entry in (([string]$RequiredRules) -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ine 'null' })) {
        if ($entry -notmatch $guidPattern) { throw "securityAsrRequiredRules: ungueltige GUID / invalid GUID '$entry'." }
        $id = $Matches[1].ToLowerInvariant()
        if (-not $required.Contains($id)) { $required.Add($id) }
    }
    if ($required.Count -gt 25) { throw 'securityAsrRequiredRules: max. 25 GUIDs.' }
    $text = ([string]$AllowAudit).Trim()
    if (-not $text -or $text -ieq 'null') { $text = 'false' }
    if ($text -in @('true', '1')) { $auditOk = $true }
    elseif ($text -in @('false', '0')) { $auditOk = $false }
    else { throw 'securityAsrAllowAudit: true/false erforderlich / required.' }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) { throw 'Get-MpPreference fehlt / unavailable.' }

    $preference = Get-MpPreference -ErrorAction Stop
    $ids = @($preference.AttackSurfaceReductionRules_Ids | Where-Object { $null -ne $_ })
    $actions = @($preference.AttackSurfaceReductionRules_Actions | Where-Object { $null -ne $_ })
    if ($ids.Count -ne $actions.Count) { throw 'ASR-Ids/Actions ungleich lang / ASR ids/actions length mismatch.' }
    $configured = @{}
    $rules = @(for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = ([string]$ids[$i]).Trim('{} ').ToLowerInvariant()
        $action = [int]$actions[$i]
        $configured[$id] = $action
        $mode = $modes[$action]; if (-not $mode) { $mode = 'Unknown' }
        $name = $known[$id]; if (-not $name) { $name = 'Unknown' }
        [pscustomobject]@{ Id = $id; Name = $name; Action = $action; Mode = $mode }
    })
    $accepted = @(1)
    if ($auditOk) { $accepted = @(1, 2, 6) }
    $violations = @(foreach ($id in $required) {
        $mode = 'NotConfigured'
        if ($configured.ContainsKey($id)) { if ($configured[$id] -in $accepted) { continue }; $mode = $modes[$configured[$id]]; if (-not $mode) { $mode = 'Unknown' } }
        $name = $known[$id]; if (-not $name) { $name = 'Unknown' }
        [pscustomobject]@{ Id = $id; Name = $name; Mode = $mode }
    })
    $records = @($rules | Sort-Object Name)
    do {
        $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
            AllowAudit = $auditOk; RequiredCount = $required.Count; ViolationCount = $violations.Count
            TotalRules = $rules.Count; ReportedRules = $records.Count; Truncated = $records.Count -lt $rules.Count
            Violations = $violations; Rules = $records
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
    if ($violations.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
