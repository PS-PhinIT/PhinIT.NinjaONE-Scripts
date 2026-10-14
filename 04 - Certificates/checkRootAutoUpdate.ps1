#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prüft automatische Aktualisierung von Stamm- und nicht vertrauenswürdigen Zertifikaten.
EN: Checks automatic updates of root and untrusted (disallowed) certificates.
.DESCRIPTION
DE: Liest die Richtlinie HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot
    (DisableRootAutoUpdate, EnableDisallowedCertAutoUpdate), den lokalen Wert
    HKLM\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\DisableRootAutoUpdate sowie unter
    ...\AuthRoot\AutoUpdate die FILETIME-Binärwerte LastSyncTime, DisallowedCertLastSyncTime und
    PinRulesLastSyncTime (sicher dekodiert; fehlend/ungültig = null) und RootDirUrl (max. 200 Zeichen).
EN: Reads the policy HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot
    (DisableRootAutoUpdate, EnableDisallowedCertAutoUpdate), the local value
    HKLM\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\DisableRootAutoUpdate and under
    ...\AuthRoot\AutoUpdate the FILETIME binary values LastSyncTime, DisallowedCertLastSyncTime and
    PinRulesLastSyncTime (safely decoded; missing/invalid = null) and RootDirUrl (max. 200 characters).
DE: Nur lesend; löst keine Synchronisierung aus (kein certutil, kein Download).
EN: Read-only; does not trigger a sync (no certutil, no download).
.PARAMETER MaxSyncAgeDays
DE: NinjaOne Integer certRootMaxSyncAgeDays; 1..3650; Standard 30.
EN: NinjaOne Integer certRootMaxSyncAgeDays; 1..3650; default 30.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField; Standard leer; MultiLine-Feldname ^[A-Za-z][A-Za-z0-9_]{0,99}$.
EN: NinjaOne text resultCustomField; default empty; MultiLine field name ^[A-Za-z][A-Za-z0-9_]{0,99}$.
.EXAMPLE
.\checkRootAutoUpdate.ps1
DE: Warnt, wenn Auto-Update deaktiviert ist oder die letzte Synchronisierung älter als 30 Tage ist.
EN: Warns if auto update is disabled or the last sync is older than 30 days.
.EXAMPLE
.\checkRootAutoUpdate.ps1 -MaxSyncAgeDays 14 -CustomField rootAutoUpdateReport
DE: Grenzwert 14 Tage; JSON in rootAutoUpdateReport.
EN: Threshold 14 days; JSON to rootAutoUpdateReport.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Exit 0 = OK, 1 = Eingabe-, Registry- oder
    Schreibfehler, 2 = Stamm-Auto-Update deaktiviert (Richtlinie oder lokal = 1),
    EnableDisallowedCertAutoUpdate = 0, oder (bei aktivem Update) LastSyncTime bzw.
    DisallowedCertLastSyncTime fehlt oder ist älter als MaxSyncAgeDays.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Exit 0 = OK, 1 = input, registry or write
    error, 2 = root auto update disabled (policy or local = 1), EnableDisallowedCertAutoUpdate
    = 0, or (with update active) LastSyncTime or DisallowedCertLastSyncTime missing or older
    than MaxSyncAgeDays.
#>
[CmdletBinding()]
param(
    [string]$MaxSyncAgeDays = $env:certRootMaxSyncAgeDays,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryKeyValue {
    param([string]$Path)
    try { Get-ItemProperty -Path $Path -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { $null }
}
function Get-NamedValue {
    param([object]$Values, [string]$Name)
    if ($null -ne $Values -and $Values.PSObject.Properties[$Name]) { return , $Values.PSObject.Properties[$Name].Value }
    return $null
}
function ConvertFrom-FileTimeValue {
    param([object]$Value)
    $ticks = $null
    if ($Value -is [byte[]] -and $Value.Length -ge 8) { $ticks = [BitConverter]::ToInt64($Value, 0) }
    elseif ($Value -is [long] -or $Value -is [int]) { $ticks = [long]$Value }
    if ($null -eq $ticks -or $ticks -le 0 -or $ticks -gt [DateTime]::MaxValue.ToFileTimeUtc()) { return $null }
    return [DateTime]::FromFileTimeUtc($ticks)
}
try {
    $MaxSyncAgeDays = ([string]$MaxSyncAgeDays).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if (-not $MaxSyncAgeDays -or $MaxSyncAgeDays -ieq 'null') { $MaxSyncAgeDays = '30' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    $maxAge = 0
    if ($MaxSyncAgeDays -notmatch '^\d{1,4}$' -or -not [int]::TryParse($MaxSyncAgeDays, [ref]$maxAge) -or $maxAge -lt 1 -or $maxAge -gt 3650) { throw 'certRootMaxSyncAgeDays: 1..3650 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $policy = Get-RegistryKeyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot'
    $local = Get-RegistryKeyValue -Path 'HKLM:\SOFTWARE\Microsoft\SystemCertificates\AuthRoot'
    $auto = Get-RegistryKeyValue -Path 'HKLM:\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate'
    $policyDisableRoot = Get-NamedValue -Values $policy -Name 'DisableRootAutoUpdate'
    $policyDisallowed = Get-NamedValue -Values $policy -Name 'EnableDisallowedCertAutoUpdate'
    $localDisableRoot = Get-NamedValue -Values $local -Name 'DisableRootAutoUpdate'
    $rootUrl = Get-NamedValue -Values $auto -Name 'RootDirUrl'
    if ($null -ne $rootUrl) { $rootUrl = [string]$rootUrl; if ($rootUrl.Length -gt 200) { $rootUrl = $rootUrl.Substring(0, 200) } }
    $now = [DateTime]::UtcNow
    $rootDisabled = ("$policyDisableRoot" -eq '1') -or ("$localDisableRoot" -eq '1')
    $disallowedDisabled = "$policyDisallowed" -eq '0'
    $findings = New-Object System.Collections.Generic.List[string]
    if ($rootDisabled) { $findings.Add('RootAutoUpdateDisabled') }
    if ($disallowedDisabled) { $findings.Add('DisallowedAutoUpdateDisabled') }
    $syncs = [ordered]@{}
    foreach ($item in @(
            @{ Name = 'LastSyncTime'; Label = 'Root'; Checked = -not $rootDisabled },
            @{ Name = 'DisallowedCertLastSyncTime'; Label = 'Disallowed'; Checked = -not $disallowedDisabled },
            @{ Name = 'PinRulesLastSyncTime'; Label = 'PinRules'; Checked = $false })) {
        $time = ConvertFrom-FileTimeValue -Value (Get-NamedValue -Values $auto -Name $item.Name)
        $age = $null
        if ($null -ne $time) { $age = [Math]::Round(($now - $time).TotalDays, 1) }
        $syncs[$item.Name] = [ordered]@{ Utc = $(if ($null -ne $time) { $time.ToString('o') } else { $null }); AgeDays = $age }
        if ($item.Checked) {
            if ($null -eq $time) { $findings.Add("$($item.Label)SyncMissing") }
            elseif ($age -gt $maxAge) { $findings.Add("$($item.Label)SyncStale") }
        }
    }
    $report = ConvertTo-Json -Depth 4 -Compress -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; MaxSyncAgeDays = $maxAge
        PolicyDisableRootAutoUpdate = $policyDisableRoot; LocalDisableRootAutoUpdate = $localDisableRoot
        PolicyEnableDisallowedCertAutoUpdate = $policyDisallowed; RootAutoUpdateDisabled = $rootDisabled
        DisallowedAutoUpdateDisabled = $disallowedDisabled; RootDirUrl = $rootUrl; LastSync = $syncs
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
