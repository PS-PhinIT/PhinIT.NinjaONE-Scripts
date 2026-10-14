#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Richtlinien für automatische Updates und Windows-Update-for-Business-Rückstellungen.
    EN: Checks automatic update policies and Windows Update for Business deferrals.
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU (NoAutoUpdate, AUOptions,
        ScheduledInstallDay/-Time, NoAutoRebootWithLoggedOnUsers), WindowsUpdate (DeferQuality-/
        DeferFeatureUpdates[PeriodInDays], BranchReadinessLevel, DisableWindowsUpdateAccess,
        SetDisableUXWUAccess, ExcludeWUDriversInQualityUpdate) sowie MDM-Werte unter
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update (AllowAutoUpdate,
        Defer*PeriodInDays, BranchReadinessLevel). Nicht gesetzte Werte erscheinen als null.
        Exit 0 = automatische Updates nicht deaktiviert, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = NoAutoUpdate=1, AUOptions=1 oder MDM AllowAutoUpdate=5, oder die
        wirksame Qualitätsupdate-Rückstellung überschreitet MaxQualityDeferralDays.
    EN: Reads HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU (NoAutoUpdate, AUOptions,
        ScheduledInstallDay/-Time, NoAutoRebootWithLoggedOnUsers), WindowsUpdate (DeferQuality-/
        DeferFeatureUpdates[PeriodInDays], BranchReadinessLevel, DisableWindowsUpdateAccess,
        SetDisableUXWUAccess, ExcludeWUDriversInQualityUpdate) and MDM values under
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update (AllowAutoUpdate,
        Defer*PeriodInDays, BranchReadinessLevel). Unset values appear as null.
        Exit 0 = automatic updates not disabled, 1 = input, query or write error,
        2 = NoAutoUpdate=1, AUOptions=1 or MDM AllowAutoUpdate=5, or the effective quality
        update deferral exceeds MaxQualityDeferralDays.
.PARAMETER MaxQualityDeferralDays
    DE: NinjaOne Integer updatePolicyMaxQualityDeferralDays, 0..30; Standard leer (keine Prüfung).
    EN: NinjaOne Integer updatePolicyMaxQualityDeferralDays, 0..30; default empty (not checked).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\checkWindowsUpdatePolicy.ps1
    DE: Warnt (Exit 2), wenn automatische Updates per Richtlinie deaktiviert sind.
    EN: Warns (exit 2) if automatic updates are disabled by policy.
.EXAMPLE
    .\checkWindowsUpdatePolicy.ps1 -MaxQualityDeferralDays 7 -CustomField updatePolicy
    DE: Zusätzlich Warnung bei mehr als 7 Tagen Rückstellung; JSON ins Feld updatePolicy.
    EN: Additionally warns on more than 7 days deferral; JSON to the field updatePolicy.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Nur lokale Registry; Cloud-
        Richtlinien (z. B. Intune-Updateringe, Autopatch) wirken nur über PolicyManager-Werte.
        Exit 0 = OK, 1 = Fehler, 2 = deaktiviert/zu lange Rückstellung.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Local registry only; cloud policies
        (e.g. Intune update rings, Autopatch) are visible only via PolicyManager values.
        Exit 0 = OK, 1 = error, 2 = disabled/deferral too long.
#>
[CmdletBinding()]
param(
    [string]$MaxQualityDeferralDays = $env:updatePolicyMaxQualityDeferralDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryValueTable {
    param([string]$Path, [string[]]$Names)
    $table = [ordered]@{}
    $item = $null
    if (Test-Path -LiteralPath $Path) { $item = Get-ItemProperty -LiteralPath $Path }
    foreach ($name in $Names) {
        $value = $null
        if ($null -ne $item -and $item.PSObject.Properties[$name]) { $value = $item.$name }
        $table[$name] = $value
    }
    $table
}
try {
    if ([string]::IsNullOrWhiteSpace($MaxQualityDeferralDays) -or $MaxQualityDeferralDays.Trim() -eq 'null') { $MaxQualityDeferralDays = '' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    $maxDeferral = $null
    if ($MaxQualityDeferralDays) {
        $parsed = 0
        if (-not [int]::TryParse($MaxQualityDeferralDays.Trim(), [ref]$parsed) -or $parsed -lt 0 -or $parsed -gt 30) {
            throw 'updatePolicyMaxQualityDeferralDays: 0..30 erforderlich / required.'
        }
        $maxDeferral = $parsed
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au = Get-RegistryValueTable -Path "$base\AU" -Names @('NoAutoUpdate', 'AUOptions', 'ScheduledInstallDay', 'ScheduledInstallTime',
        'NoAutoRebootWithLoggedOnUsers', 'AlwaysAutoRebootAtScheduledTime')
    $wufb = Get-RegistryValueTable -Path $base -Names @('DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays', 'DeferFeatureUpdates',
        'DeferFeatureUpdatesPeriodInDays', 'BranchReadinessLevel', 'DisableWindowsUpdateAccess', 'SetDisableUXWUAccess', 'ExcludeWUDriversInQualityUpdate')
    $mdm = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -Names @('AllowAutoUpdate',
        'DeferQualityUpdatesPeriodInDays', 'DeferFeatureUpdatesPeriodInDays', 'BranchReadinessLevel')
    $auOptionNames = @{ 1 = 'Disabled'; 2 = 'NotifyDownload'; 3 = 'AutoDownloadNotifyInstall'; 4 = 'AutoDownloadScheduleInstall'
        5 = 'LocalAdminChooses'; 7 = 'AutoDownloadNotifyInstallNotifyRestart' }
    $dayNames = @('EveryDay', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
    $branchNames = @{ 2 = 'InsiderFast/Dev'; 4 = 'InsiderSlow/Beta'; 8 = 'ReleasePreview'; 16 = 'GeneralAvailability'; 32 = 'GeneralAvailability' }
    $findings = [System.Collections.Generic.List[string]]::new()
    $anyConfigured = @(@($au.Values) + @($mdm.AllowAutoUpdate) | Where-Object { $null -ne $_ }).Count -gt 0
    $state = 'NotConfigured'
    if ($anyConfigured) { $state = 'Enabled' }
    if ([string]$au.NoAutoUpdate -eq '1') { $findings.Add('NoAutoUpdate=1'); $state = 'Disabled' }
    if ([string]$au.AUOptions -eq '1') { $findings.Add('AUOptions=1'); $state = 'Disabled' }
    if ([string]$mdm.AllowAutoUpdate -eq '5') { $findings.Add('MDM AllowAutoUpdate=5'); $state = 'Disabled' }
    $qualityDeferral = 0
    if ([string]$wufb.DeferQualityUpdates -eq '1' -and $null -ne $wufb.DeferQualityUpdatesPeriodInDays) { $qualityDeferral = [int]$wufb.DeferQualityUpdatesPeriodInDays }
    elseif ($null -ne $mdm.DeferQualityUpdatesPeriodInDays) { $qualityDeferral = [int]$mdm.DeferQualityUpdatesPeriodInDays }
    if ($null -ne $maxDeferral -and $qualityDeferral -gt $maxDeferral) { $findings.Add("QualityDeferralDays $qualityDeferral > $maxDeferral") }
    $day = $null
    if ($null -ne $au.ScheduledInstallDay -and [int]$au.ScheduledInstallDay -ge 0 -and [int]$au.ScheduledInstallDay -le 7) { $day = $dayNames[[int]$au.ScheduledInstallDay] }
    $branch = $wufb.BranchReadinessLevel
    if ($null -eq $branch) { $branch = $mdm.BranchReadinessLevel }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; AutomaticUpdates = $state
        AUOptionsName = $(if ($null -ne $au.AUOptions) { $auOptionNames[[int]$au.AUOptions] })
        ScheduledInstallDayName = $day; EffectiveQualityDeferralDays = $qualityDeferral
        BranchReadiness = $(if ($null -ne $branch) { $branchNames[[int]$branch] })
        MaxQualityDeferralDays = $maxDeferral; AUPolicy = $au; WUfBPolicy = $wufb; MdmPolicy = $mdm; Findings = @($findings)
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
