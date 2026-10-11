#Requires -Version 5.1
<#
.SYNOPSIS
DE: Effektive Firewallprofile inventarisieren. EN: Inventory effective firewall profiles.
.DESCRIPTION
DE: Liest ActiveStore, aendert keine Regeln. Alle Profile, nicht nur aktive Netzwerke.
EN: Reads ActiveStore without changing rules. All profiles, not just active networks.
DE: SYSTEM und 64-Bit-PowerShell verwenden. Keine Regel-/Anwendungsdetails.
EN: Use SYSTEM and 64-bit PowerShell. No rule/application details.
DE: Explizite Parameter vor NinjaOne-Variablen alertOnDisabledFirewall, maxRecords,
resultFormat, resultCustomField. Leer: true, 10, Json, kein Feld.
EN: Explicit parameters override those variables. Blanks: true, 10, Json, no field.
DE: Alarm bei explizit deaktiviertem Profil, auch wenn aktuell nicht genutzt.
EN: Alerts for explicitly disabled profiles, including currently unused profiles.
DE/EN: alertOnDisabledFirewall = true/false/1/0; resultFormat = Json/PlainText.
DE/EN: Optional CustomField: NinjaOne MultiLine, maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = deaktiviertes Profil/disabled profile.
#>
[CmdletBinding()]
param(
    [string]$AlertOnDisabled = $env:alertOnDisabledFirewall,
    [string]$MaxRecords = $env:maxRecords,
    [string]$ResultFormat = $env:resultFormat,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Write-InventoryReport {
    param([object]$Report, [string]$Format, [string]$Field)
    if ($Format -eq 'Json') {
        $content = ConvertTo-Json -InputObject $Report -Depth 6 -Compress
    } else {
        $summary = $Report | Select-Object * -ExcludeProperty records | Format-List | Out-String -Width 200
        $rows = $Report.records | Format-List | Out-String -Width 200
        $content = ($summary + $rows).Trim()
    }
    # DE: Steuerzeichen entfernen. EN: Remove terminal control characters.
    $content = $content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    if ($Field) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters; reduce maxRecords. / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
    Write-Output $content
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows required / erforderlich.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $AlertOnDisabled = ([string]$AlertOnDisabled).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($AlertOnDisabled -ieq 'null') { $AlertOnDisabled = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $AlertOnDisabled) { $AlertOnDisabled = 'true' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($AlertOnDisabled -notin @('true', 'false', '1', '0')) { throw 'alertOnDisabledFirewall must be true/false/1/0 / muss true/false/1/0 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Sort-Object Name)
    if ($profiles.Count -eq 0) { throw 'No firewall profiles returned / Keine Firewallprofile geliefert.' }
    $disabled = @($profiles | Where-Object { [string]$_.Enabled -eq 'False' })
    $records = @($profiles | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name; enabled = [string]$_.Enabled
            defaultInbound = [string]$_.DefaultInboundAction; defaultOutbound = [string]$_.DefaultOutboundAction
        }
    })
    $report = [pscustomobject]@{
        inventory = 'Firewall profiles / Firewallprofile'; policyStore = 'ActiveStore'
        disabledTotal = $disabled.Count; total = $profiles.Count; returned = $records.Count
        truncated = ($profiles.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    if ($disabled.Count -gt 0 -and $AlertOnDisabled -in @('true', '1')) { exit 2 }
    exit 0
} catch {
    Write-Error 'Firewall inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / Firewallinventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}
