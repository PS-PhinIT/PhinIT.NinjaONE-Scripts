#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft effektive Windows-Firewallprofile ohne Regeln zu aendern.
EN: Audits effective Windows firewall profiles without changing rules.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell. Alle drei Profile, auch derzeit inaktive, werden geprueft.
EN: SYSTEM, 64-bit Windows PowerShell. Checks all three profiles, including currently inactive ones.
DE: RequireOutboundBlock / securityFirewallRequireOutboundBlock: true/false, Standard false.
EN: RequireOutboundBlock / securityFirewallRequireOutboundBlock: true/false, default false.
DE: Warnung bei deaktiviertem Profil, nicht blockiertem Standard-Inbound oder fehlendem Profil.
EN: Warns on disabled profiles, non-blocking default inbound policy or missing profiles.
DE: Outbound-Allow ist standardmaessig erlaubt. Keine vollstaendige Regel-/Port-Sicherheitsbewertung.
EN: Outbound-Allow is acceptable by default. This is not a full rule/port security assessment.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang; keine Remediation.
EN: Explicit parameters take precedence; no remediation.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = Warnung/warning.
.PARAMETER RequireOutboundBlock
DE: Standard-Outbound-Block verlangen; securityFirewallRequireOutboundBlock; Standard false.
EN: Require default outbound block; securityFirewallRequireOutboundBlock; default false.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
#>
[CmdletBinding()]
param([string]$RequireOutboundBlock = 'false', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Erst Umgebungswerte binden. EN: Bind environment values before validation.
    if (-not $PSBoundParameters.ContainsKey('RequireOutboundBlock')) {
        $RequireOutboundBlock = ([string]$env:securityFirewallRequireOutboundBlock).Trim()
        if ($RequireOutboundBlock -ieq 'null') { $RequireOutboundBlock = '' }
        if (-not $RequireOutboundBlock) { $RequireOutboundBlock = 'false' }
    }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $outbound = $false
    if (-not [bool]::TryParse($RequireOutboundBlock, [ref]$outbound)) { throw 'RequireOutboundBlock muss true/false sein / must be true/false.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $null = Get-Command Get-NetFirewallProfile -ErrorAction Stop
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    $warning = $profiles.Count -ne 3
    foreach ($name in @('Domain', 'Private', 'Public')) {
        if (@($profiles | Where-Object { $_.Name -eq $name }).Count -ne 1) { $warning = $true }
    }
    $rows = @($profiles | ForEach-Object {
        $compliant = [string]$_.Enabled -eq 'True' -and [string]$_.DefaultInboundAction -eq 'Block' -and
            (-not $outbound -or [string]$_.DefaultOutboundAction -eq 'Block')
        [pscustomobject]@{
            Name = [string]$_.Name; Enabled = [string]$_.Enabled
            DefaultInboundAction = [string]$_.DefaultInboundAction; DefaultOutboundAction = [string]$_.DefaultOutboundAction
            Compliant = $compliant
        }
    })
    if (@($rows | Where-Object { -not $_.Compliant }).Count) { $warning = $true }
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{ PolicyStore = 'ActiveStore'; RequireOutboundBlock = $outbound; Profiles = $rows }) -Depth 4 -Compress
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    if ($text.Length -gt 4000) { throw 'Ergebnis groesser als 4000 Zeichen / Result exceeds 4000 characters.' }
    Write-Output $text
    if ($CustomField) {
        $null = Get-Command Ninja-Property-Set -ErrorAction Stop
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $text -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'CustomField konnte nicht geschrieben werden / Field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Firewallpruefung fehlgeschlagen / Firewall audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
