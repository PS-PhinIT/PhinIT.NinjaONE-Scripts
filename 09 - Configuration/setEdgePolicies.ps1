#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft ausgewählte Microsoft-Edge-Computerrichtlinien und setzt oder entfernt sie optional.
    EN: Audits selected Microsoft Edge machine policies and optionally sets or removes them.
.DESCRIPTION
    DE: Verwaltet Werte unter HKLM:\SOFTWARE\Policies\Microsoft\Edge über eine Einstellungstabelle im Code:
        HideFirstRunExperience, StartupBoostEnabled, BackgroundModeEnabled, ShowRecommendationsEnabled,
        PasswordManagerEnabled (true/false = DWORD 1/0) und HomepageLocation (REG_SZ, nur https-URL, max. 2048 Zeichen).
        Jede Einstellung ist optional: leer = nicht verwaltet, 'remove' = Wert entfernen. Mindestens eine Einstellung ist
        erforderlich (sonst Exit 1). Ohne Opt-in (configEdgeAllow=true) wird nichts geändert. Mit Opt-in werden nur
        abweichende Werte innerhalb von ShouldProcess geschrieben bzw. entfernt (fehlender Schlüssel wird angelegt) und
        erneut gelesen. Edge übernimmt Richtlinien beim nächsten Richtlinienabruf bzw. Neustart des Browsers; einige
        Richtlinien (z. B. HomepageLocation) wirken nur auf Domänen-, Entra- oder MDM-verwalteten Geräten.
        Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
    EN: Manages values under HKLM:\SOFTWARE\Policies\Microsoft\Edge through a settings table in code:
        HideFirstRunExperience, StartupBoostEnabled, BackgroundModeEnabled, ShowRecommendationsEnabled,
        PasswordManagerEnabled (true/false = DWORD 1/0) and HomepageLocation (REG_SZ, https URL only, max. 2048 characters).
        Every setting is optional: empty = not managed, 'remove' = delete the value. At least one setting is required
        (otherwise exit 1). Without opt-in (configEdgeAllow=true) nothing is changed. With opt-in only differing values are
        written or removed inside ShouldProcess (a missing key is created) and read back. Edge applies policies at the
        next policy refresh or browser restart; some policies (e.g. HomepageLocation) only apply on domain-joined,
        Entra-joined or MDM-managed devices. Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
.PARAMETER HideFirstRunExperience
    DE: NinjaOne Text configEdgeHideFirstRunExperience; true/false/remove; Standard leer (nicht verwaltet).
    EN: NinjaOne text configEdgeHideFirstRunExperience; true/false/remove; default empty (not managed).
.PARAMETER StartupBoostEnabled
    DE: NinjaOne Text configEdgeStartupBoostEnabled; true/false/remove; Standard leer (nicht verwaltet).
    EN: NinjaOne text configEdgeStartupBoostEnabled; true/false/remove; default empty (not managed).
.PARAMETER BackgroundModeEnabled
    DE: NinjaOne Text configEdgeBackgroundModeEnabled; true/false/remove; Standard leer (nicht verwaltet).
    EN: NinjaOne text configEdgeBackgroundModeEnabled; true/false/remove; default empty (not managed).
.PARAMETER ShowRecommendationsEnabled
    DE: NinjaOne Text configEdgeShowRecommendationsEnabled; true/false/remove; Standard leer (nicht verwaltet).
    EN: NinjaOne text configEdgeShowRecommendationsEnabled; true/false/remove; default empty (not managed).
.PARAMETER HomepageLocation
    DE: NinjaOne Text configEdgeHomepageLocation; https-URL (max. 2048 Zeichen) oder remove; Standard leer (nicht verwaltet).
    EN: NinjaOne text configEdgeHomepageLocation; https URL (max. 2048 characters) or remove; default empty (not managed).
.PARAMETER PasswordManagerEnabled
    DE: NinjaOne Text configEdgePasswordManagerEnabled; true/false/remove; Standard leer (nicht verwaltet). Kein Geheimnis, nur ein Schalter.
    EN: NinjaOne text configEdgePasswordManagerEnabled; true/false/remove; default empty (not managed). Not a secret, only a switch.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configEdgeAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configEdgeAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setEdgePolicies.ps1 -HideFirstRunExperience true -StartupBoostEnabled false
    DE: Nur Prüfung: Exit 2, wenn eine der beiden Richtlinien abweicht.
    EN: Audit only: exit 2 if one of the two policies differs.
.EXAMPLE
    .\setEdgePolicies.ps1 -HomepageLocation 'https://intranet.contoso.com' -Allow true -WhatIf
    DE: Simuliert das Setzen der Startseite; nichts wird geändert (Exit 0).
    EN: Simulates setting the home page; nothing is changed (exit 0).
.EXAMPLE
    .\setEdgePolicies.ps1 -BackgroundModeEnabled remove -PasswordManagerEnabled false -Allow true -CustomField edgeReport
    DE: Entfernt BackgroundModeEnabled, deaktiviert den Kennwort-Manager und schreibt das JSON in edgeReport.
    EN: Removes BackgroundModeEnabled, disables the password manager and writes the JSON to edgeReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Weitere Richtlinien lassen sich durch eine Zeile in der Einstellungstabelle ergänzen. Domänen-GPO/MDM können Werte überschreiben.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler bzw. keine Einstellung angegeben; 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Further policies can be added with one line in the settings table. Domain GPO/MDM may overwrite values.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error or no setting specified; 2 = drift without opt-in or change declined via -Confirm.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'PasswordManagerEnabled', Justification = 'true/false/remove switch text, not a secret.')]
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$HideFirstRunExperience = $env:configEdgeHideFirstRunExperience,
    [string]$StartupBoostEnabled = $env:configEdgeStartupBoostEnabled,
    [string]$BackgroundModeEnabled = $env:configEdgeBackgroundModeEnabled,
    [string]$ShowRecommendationsEnabled = $env:configEdgeShowRecommendationsEnabled,
    [string]$HomepageLocation = $env:configEdgeHomepageLocation,
    [string]$PasswordManagerEnabled = $env:configEdgePasswordManagerEnabled,
    [string]$Allow = $env:configEdgeAllow,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-BooleanSetting {
    param([string]$Value, [string]$Name)
    $result = $false
    if (-not [bool]::TryParse($Value, [ref]$result)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $result
}
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($null -ne $item -and $item.PSObject.Properties[$Name]) { return $item.$Name }
    return $null
}
function Format-ShortValue {
    param($Value)
    if ($Value -is [string] -and $Value.Length -gt 200) { return $Value.Substring(0, 200) + '...' }
    return $Value
}
function Write-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop
}
try {
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    # DE: Einstellungstabelle - neue Richtlinien hier ergänzen. EN: Settings table - add new policies here.
    $definitions = @(
        [pscustomobject]@{ Variable = 'configEdgeHideFirstRunExperience'; Policy = 'HideFirstRunExperience'; Kind = 'Boolean'; Input = $HideFirstRunExperience }
        [pscustomobject]@{ Variable = 'configEdgeStartupBoostEnabled'; Policy = 'StartupBoostEnabled'; Kind = 'Boolean'; Input = $StartupBoostEnabled }
        [pscustomobject]@{ Variable = 'configEdgeBackgroundModeEnabled'; Policy = 'BackgroundModeEnabled'; Kind = 'Boolean'; Input = $BackgroundModeEnabled }
        [pscustomobject]@{ Variable = 'configEdgeShowRecommendationsEnabled'; Policy = 'ShowRecommendationsEnabled'; Kind = 'Boolean'; Input = $ShowRecommendationsEnabled }
        [pscustomobject]@{ Variable = 'configEdgeHomepageLocation'; Policy = 'HomepageLocation'; Kind = 'HttpsUrl'; Input = $HomepageLocation }
        [pscustomobject]@{ Variable = 'configEdgePasswordManagerEnabled'; Policy = 'PasswordManagerEnabled'; Kind = 'Boolean'; Input = $PasswordManagerEnabled }
    )
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $allowed = ConvertTo-BooleanSetting $Allow 'configEdgeAllow'
    $managed = @()
    foreach ($definition in $definitions) {
        $text = Resolve-Setting $definition.Input ''
        if (-not $text) { continue }
        $operation = 'Set'
        $data = $null
        $type = 'DWord'
        if ($text -eq 'remove') { $operation = 'Remove'; $type = $null }
        elseif ($definition.Kind -eq 'Boolean') {
            $flag = ConvertTo-BooleanSetting $text $definition.Variable
            $data = 0
            if ($flag) { $data = 1 }
        }
        else {
            $uri = $null
            if ($text.Length -gt 2048 -or $text -match '[\s\x00-\x1f\x7f]' -or -not [Uri]::TryCreate($text, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -ne 'https' -or -not $uri.Host) {
                throw ('{0}: https-URL (max. 2048 Zeichen) oder remove erforderlich / https URL (max. 2048 characters) or remove required.' -f $definition.Variable)
            }
            $data = $text
            $type = 'String'
        }
        $managed += [pscustomobject]@{ Policy = $definition.Policy; Operation = $operation; Data = $data; Type = $type }
    }
    if ($managed.Count -eq 0) { throw 'Mindestens eine Edge-Einstellung erforderlich / At least one Edge setting required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $readState = {
        $current = [ordered]@{}
        $diffs = @()
        foreach ($setting in $managed) {
            $raw = Get-RegistryValue -Path $policyPath -Name $setting.Policy
            $display = Format-ShortValue $raw
            $current[$setting.Policy] = $display
            $ok = $false
            if ($setting.Operation -eq 'Remove') { $ok = $null -eq $raw }
            elseif ($setting.Type -eq 'DWord') { $ok = $raw -is [int] -and $raw -eq $setting.Data }
            else { $ok = $raw -is [string] -and $raw -ceq $setting.Data }
            if (-not $ok) {
                $target = '(removed)'
                if ($setting.Operation -eq 'Set') { $target = Format-ShortValue $setting.Data }
                $diffs += ('{0}: {1} -> {2}' -f $setting.Policy, $display, $target)
            }
        }
        [pscustomobject]@{ Current = $current; Differences = @($diffs) }
    }
    $state = & $readState
    $initialDifferences = @($state.Differences)
    $attempted = $false
    $changed = $false
    if ($allowed -and $state.Differences.Count -gt 0) {
        foreach ($setting in $managed) {
            if (-not @($state.Differences | Where-Object { $_ -like ($setting.Policy + ':*') }).Count) { continue }
            if ($setting.Operation -eq 'Remove') {
                if ($PSCmdlet.ShouldProcess("$policyPath\$($setting.Policy)", 'Edge-Richtlinie entfernen / Remove Edge policy')) {
                    $attempted = $true
                    Remove-ItemProperty -LiteralPath $policyPath -Name $setting.Policy -ErrorAction Stop
                    $changed = $true
                }
            }
            elseif ($PSCmdlet.ShouldProcess("$policyPath\$($setting.Policy)", ('Edge-Richtlinie setzen ({0}) / Set Edge policy ({0})' -f $setting.Type))) {
                $attempted = $true
                $value = $setting.Data
                if ($setting.Type -eq 'DWord') { $value = [int]$setting.Data }
                Write-RegistryValue -Path $policyPath -Name $setting.Policy -Value $value -Type $setting.Type
                $changed = $true
            }
        }
        if ($attempted) { $state = & $readState }
    }
    $compliant = $state.Differences.Count -eq 0
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $desired = [ordered]@{}
    foreach ($setting in $managed) {
        $desired[$setting.Policy] = '(remove)'
        if ($setting.Operation -eq 'Set') { $desired[$setting.Policy] = Format-ShortValue $setting.Data }
    }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'EdgePolicies'; Current = $state.Current; Desired = $desired
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($initialDifferences); RemainingDifferences = @($state.Differences)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit $exitCode
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
