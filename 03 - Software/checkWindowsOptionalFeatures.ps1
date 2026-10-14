#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, dass unsichere optionale Windows-Features deaktiviert und geforderte Features aktiviert sind.
    EN: Checks that insecure Windows optional features are disabled and required features are enabled.
.DESCRIPTION
    DE: Liest alle Features einmal per Get-WindowsOptionalFeature -Online (DISM-API) und vergleicht exakte
        Feature-Namen (Groß-/Kleinschreibung egal). Unbekannte Namen werden als NotPresent gemeldet; NotPresent
        gilt für MustBeDisabled als konform, für MustBeEnabled als Verstoß. Konform für "deaktiviert" sind
        Disabled, DisabledWithPayloadRemoved und NotPresent; DisablePending (Neustart ausstehend) ist ein Verstoß.
        Für "aktiviert" ist nur Enabled konform. Keine Änderungen. Bericht max. 4000 Zeichen für das Feld.
        Exit 0 = konform, 1 = Eingabe-, Abfrage- oder Schreibfehler, 2 = mindestens ein Verstoß.
    EN: Reads all features once via Get-WindowsOptionalFeature -Online (DISM API) and compares exact feature
        names (case-insensitive). Unknown names are reported as NotPresent; NotPresent is compliant for
        MustBeDisabled and a violation for MustBeEnabled. Compliant "disabled" states are Disabled,
        DisabledWithPayloadRemoved and NotPresent; DisablePending (reboot pending) is a violation.
        Only Enabled is compliant for "enabled". No changes. Report max. 4000 characters for the field.
        Exit 0 = compliant, 1 = input, query or write error, 2 = at least one violation.
.PARAMETER MustBeDisabled
    DE: NinjaOne Text softwareFeaturesMustBeDisabled; 1-50 kommagetrennte Feature-Namen, Muster ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$;
        Standard SMB1Protocol,MicrosoftWindowsPowerShellV2Root,TelnetClient,TFTP.
    EN: NinjaOne Text softwareFeaturesMustBeDisabled; 1-50 comma-separated feature names, pattern ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$;
        default SMB1Protocol,MicrosoftWindowsPowerShellV2Root,TelnetClient,TFTP.
.PARAMETER MustBeEnabled
    DE: NinjaOne Text softwareFeaturesMustBeEnabled; optional, 0-50 Namen im selben Format; Standard leer.
    EN: NinjaOne Text softwareFeaturesMustBeEnabled; optional, 0-50 names in the same format; default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\checkWindowsOptionalFeatures.ps1
    DE: Exit 2, wenn SMB1, PowerShell 2.0, Telnet-Client oder TFTP aktiviert sind.
    EN: Exit 2 if SMB1, PowerShell 2.0, Telnet client or TFTP are enabled.
.EXAMPLE
    .\checkWindowsOptionalFeatures.ps1 -MustBeDisabled 'SMB1Protocol' -MustBeEnabled 'NetFx4-AdvSrvs' -CustomField featureCompliance
    DE: SMB1 muss aus, .NET 4 muss an sein; JSON in featureCompliance.
    EN: SMB1 must be off, .NET 4 must be on; JSON to featureCompliance.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit, DISM-Modul (Client und Server). Parameter überschreiben Variablen. Nur lesend.
        Exit 0 = OK, 1 = Fehler, 2 = Feature-Verstoß.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit, DISM module (client and server). Parameters override variables. Read-only.
        Exit 0 = OK, 1 = error, 2 = feature violation.
#>
[CmdletBinding()]
param(
    [string]$MustBeDisabled = $env:softwareFeaturesMustBeDisabled,
    [string]$MustBeEnabled = $env:softwareFeaturesMustBeEnabled,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-FeatureList {
    param([string]$Text, [string]$Variable)
    if (-not $Text) { return @() }
    $items = @($Text.Split(',') | ForEach-Object { $_.Trim() })
    if ($items.Count -gt 50 -or @($items | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' }).Count -gt 0) {
        throw "Ungültige Feature-Liste / Invalid feature list: $Variable"
    }
    return @($items | Sort-Object -Unique)
}
try {
    $MustBeDisabled = Resolve-Setting $MustBeDisabled 'SMB1Protocol,MicrosoftWindowsPowerShellV2Root,TelnetClient,TFTP'
    $MustBeEnabled = Resolve-Setting $MustBeEnabled ''
    $CustomField = Resolve-Setting $CustomField ''
    $disabledList = @(ConvertTo-FeatureList $MustBeDisabled 'softwareFeaturesMustBeDisabled')
    $enabledList = @(ConvertTo-FeatureList $MustBeEnabled 'softwareFeaturesMustBeEnabled')
    $overlap = @($disabledList | Where-Object { $enabledList -contains $_ })
    if ($overlap.Count -gt 0) { throw ('Feature in beiden Listen / Feature in both lists: {0}' -f ($overlap -join ', ')) }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) { throw 'Get-WindowsOptionalFeature fehlt / unavailable.' }

    $states = @{}
    foreach ($feature in @(Get-WindowsOptionalFeature -Online)) { $states[[string]$feature.FeatureName] = [string]$feature.State }
    if ($states.Count -eq 0) { throw 'Keine Features gelesen / No features returned.' }
    $violations = 0
    $results = @(
        foreach ($name in $disabledList) {
            $state = if ($states.ContainsKey($name)) { $states[$name] } else { 'NotPresent' }
            $compliant = @('Disabled', 'DisabledWithPayloadRemoved', 'NotPresent') -contains $state
            if (-not $compliant) { $violations++ }
            [pscustomobject]@{ Feature = $name; Required = 'Disabled'; State = $state; Compliant = $compliant }
        }
        foreach ($name in $enabledList) {
            $state = if ($states.ContainsKey($name)) { $states[$name] } else { 'NotPresent' }
            $compliant = $state -eq 'Enabled'
            if (-not $compliant) { $violations++ }
            [pscustomobject]@{ Feature = $name; Required = 'Enabled'; State = $state; Compliant = $compliant }
        }
    )
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; FeaturesOnSystem = $states.Count; Violations = $violations; Results = $results
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($violations -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
