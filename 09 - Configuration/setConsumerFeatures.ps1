#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Richtlinien gegen Windows-Consumer-Funktionen (automatische App-Installationen) und setzt sie optional.
    EN: Audits the policies against Windows consumer experiences (automatic app installs) and optionally sets them.
.DESCRIPTION
    DE: Verwaltet unter HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent die DWORD-Werte
        DisableWindowsConsumerFeatures, DisableConsumerAccountStateContent, DisableSoftLanding und
        DisableCloudOptimizedContent. Disabled=true setzt alle vier auf 1 (Funktionen aus), Disabled=false entfernt die
        vier Werte (Windows-Standard). Ohne Opt-in (configConsumerFeaturesAllow=true) wird nichts geändert. Mit Opt-in
        werden nur abweichende Werte innerhalb von ShouldProcess geschrieben bzw. entfernt (fehlender Schlüssel wird
        angelegt) und erneut gelesen. Hinweis: DisableWindowsConsumerFeatures wird nur von Enterprise/Education (und
        Server) beachtet; EditionID aus HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion wird informativ gemeldet.
        Bereits installierte Apps werden nicht entfernt. Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
    EN: Manages the DWORD values DisableWindowsConsumerFeatures, DisableConsumerAccountStateContent, DisableSoftLanding and
        DisableCloudOptimizedContent under HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent. Disabled=true sets all
        four to 1 (features off), Disabled=false removes the four values (Windows default). Without opt-in
        (configConsumerFeaturesAllow=true) nothing is changed. With opt-in only differing values are written or removed
        inside ShouldProcess (a missing key is created) and read back. Note: DisableWindowsConsumerFeatures is only
        honoured by Enterprise/Education (and Server); EditionID from HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion
        is reported for information. Apps already installed are not removed.
        Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences.
.PARAMETER Disabled
    DE: NinjaOne Checkbox/Text configConsumerFeaturesDisabled; erforderlich; true = Consumer-Funktionen per Richtlinie aus, false = Richtlinienwerte entfernen.
    EN: NinjaOne checkbox/text configConsumerFeaturesDisabled; required; true = consumer features off by policy, false = remove the policy values.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configConsumerFeaturesAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configConsumerFeaturesAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setConsumerFeatures.ps1 -Disabled true
    DE: Nur Prüfung: Exit 2, wenn einer der vier Richtlinienwerte nicht 1 ist.
    EN: Audit only: exit 2 if one of the four policy values is not 1.
.EXAMPLE
    .\setConsumerFeatures.ps1 -Disabled true -Allow true -WhatIf
    DE: Simuliert das Setzen; nichts wird geändert (Exit 0).
    EN: Simulates setting; nothing is changed (exit 0).
.EXAMPLE
    .\setConsumerFeatures.ps1 -Disabled true -Allow true -CustomField consumerReport
    DE: Setzt alle vier Werte und schreibt das JSON in consumerReport.
    EN: Sets all four values and writes the JSON to consumerReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Domänen-Gruppenrichtlinien/MDM können die Werte überschreiben.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler; 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Domain Group Policy/MDM may overwrite the values.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error; 2 = drift without opt-in or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Disabled = $env:configConsumerFeaturesDisabled,
    [string]$Allow = $env:configConsumerFeaturesAllow,
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
function Write-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop
}
try {
    $Disabled = Resolve-Setting $Disabled ''
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $Disabled) { throw 'configConsumerFeaturesDisabled erforderlich (true/false) / required (true/false).' }
    $desiredDisabled = ConvertTo-BooleanSetting $Disabled 'configConsumerFeaturesDisabled'
    $allowed = ConvertTo-BooleanSetting $Allow 'configConsumerFeaturesAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    $valueNames = @('DisableWindowsConsumerFeatures', 'DisableConsumerAccountStateContent', 'DisableSoftLanding', 'DisableCloudOptimizedContent')
    $readState = {
        $current = [ordered]@{}
        $diffs = @()
        foreach ($valueName in $valueNames) {
            $raw = Get-RegistryValue -Path $policyPath -Name $valueName
            $current[$valueName] = $raw
            if ($desiredDisabled -and -not ($raw -is [int] -and $raw -eq 1)) { $diffs += ('{0}: {1} -> 1' -f $valueName, $raw) }
            if (-not $desiredDisabled -and $null -ne $raw) { $diffs += ('{0}: {1} -> (removed)' -f $valueName, $raw) }
        }
        [pscustomobject]@{ Current = $current; Differences = @($diffs) }
    }
    $state = & $readState
    $initialDifferences = @($state.Differences)
    $attempted = $false
    $changed = $false
    if ($allowed -and $state.Differences.Count -gt 0) {
        foreach ($valueName in $valueNames) {
            if (-not @($state.Differences | Where-Object { $_ -like ($valueName + ':*') }).Count) { continue }
            if ($desiredDisabled) {
                if ($PSCmdlet.ShouldProcess("$policyPath\$valueName", 'Richtlinie auf 1 setzen / Set policy to 1')) {
                    $attempted = $true
                    Write-RegistryValue -Path $policyPath -Name $valueName -Value ([int]1) -Type 'DWord'
                    $changed = $true
                }
            }
            elseif ($PSCmdlet.ShouldProcess("$policyPath\$valueName", 'Richtlinienwert entfernen / Remove policy value')) {
                $attempted = $true
                Remove-ItemProperty -LiteralPath $policyPath -Name $valueName -ErrorAction Stop
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

    $edition = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID'
    $notes = @()
    if ($desiredDisabled -and $edition -and [string]$edition -notmatch '^(Enterprise|Education|Server)') {
        $notes += ('DisableWindowsConsumerFeatures wird von {0} ignoriert / is ignored by {0}' -f $edition)
    }
    $desired = [ordered]@{}
    foreach ($valueName in $valueNames) { $desired[$valueName] = $(if ($desiredDisabled) { 1 } else { $null }) }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'ConsumerFeatures'; ConsumerFeaturesDisabled = $desiredDisabled
        Current = $state.Current; Desired = $desired; Compliant = $compliant; Changed = $changed; Allowed = $allowed
        WhatIf = [bool]$WhatIfPreference; VerificationFailed = $verificationFailed; Differences = @($initialDifferences)
        RemainingDifferences = @($state.Differences); EditionId = $edition; Notes = @($notes)
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
