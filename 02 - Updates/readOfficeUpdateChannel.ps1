#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest Updatekanal und Updatestatus von Microsoft 365 Apps (Klick-und-Los).
    EN: Reads the update channel and update state of Microsoft 365 Apps (Click-to-Run).
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration (VersionToReport,
        CDNBaseUrl, UpdateChannel, UpdateChannelChanged, UpdatesEnabled, UpdateUrl, Platform,
        ProductReleaseIds) und die Richtlinie HKLM\SOFTWARE\Policies\Microsoft\office\16.0\
        common\officeupdate (enableautomaticupdates, updatebranch, updatetargetversion,
        updatepath, updatedeadline, hideenabledisableupdates). Die Kanal-GUID in CDNBaseUrl
        bzw. UpdateChannel wird einem Namen zugeordnet (Current, CurrentPreview,
        MonthlyEnterprise, SemiAnnual, SemiAnnualPreview, BetaChannel, PerpetualVL2019/2021/2024);
        unbekannte URLs erscheinen als Custom. CurrentChannel stammt aus CDNBaseUrl (installierte
        Bits), TargetChannel aus UpdateChannel bzw. updatebranch (wirkt beim nächsten Update).
        Ohne Klick-und-Los-Installation: Installed=false, Exit 0. Exit 0 = OK, 1 = Eingabe-,
        Abfrage- oder Schreibfehler, 2 = Updates deaktiviert (UpdatesEnabled=False oder
        enableautomaticupdates=0) oder CurrentChannel weicht von ExpectedChannel ab.
    EN: Reads HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration (VersionToReport,
        CDNBaseUrl, UpdateChannel, UpdateChannelChanged, UpdatesEnabled, UpdateUrl, Platform,
        ProductReleaseIds) and the policy HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\
        officeupdate (enableautomaticupdates, updatebranch, updatetargetversion, updatepath,
        updatedeadline, hideenabledisableupdates). The channel GUID in CDNBaseUrl or
        UpdateChannel is mapped to a name (Current, CurrentPreview, MonthlyEnterprise,
        SemiAnnual, SemiAnnualPreview, BetaChannel, PerpetualVL2019/2021/2024); unknown URLs
        appear as Custom. CurrentChannel comes from CDNBaseUrl (installed bits), TargetChannel
        from UpdateChannel or updatebranch (applies at the next update). Without a Click-to-Run
        installation: Installed=false, exit 0. Exit 0 = OK, 1 = input, query or write error,
        2 = updates disabled (UpdatesEnabled=False or enableautomaticupdates=0) or CurrentChannel
        differs from ExpectedChannel.
.PARAMETER ExpectedChannel
    DE: NinjaOne Dropdown/Text updateOfficeExpectedChannel: Current, CurrentPreview, MonthlyEnterprise, SemiAnnual, SemiAnnualPreview, BetaChannel, PerpetualVL2019, PerpetualVL2021, PerpetualVL2024; Standard leer (kein Vergleich).
    EN: NinjaOne drop-down/text updateOfficeExpectedChannel: Current, CurrentPreview, MonthlyEnterprise, SemiAnnual, SemiAnnualPreview, BetaChannel, PerpetualVL2019, PerpetualVL2021, PerpetualVL2024; default empty (no comparison).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\readOfficeUpdateChannel.ps1
    DE: Zeigt Version und Kanal; Warnung, wenn Office-Updates deaktiviert sind.
    EN: Shows version and channel; warns if Office updates are disabled.
.EXAMPLE
    .\readOfficeUpdateChannel.ps1 -ExpectedChannel MonthlyEnterprise -CustomField officeChannel
    DE: Erwartet den Monatlichen Unternehmenskanal; JSON ins Feld officeChannel.
    EN: Expects Monthly Enterprise Channel; JSON to the field officeChannel.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend; kein Kanalwechsel. MSI-Office
        und Cloud-Richtlinien (config.office.com) werden nicht ausgewertet.
        Exit 0 = OK/nicht installiert, 1 = Fehler, 2 = Updates deaktiviert/Kanalabweichung.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only; no channel change. MSI Office and
        cloud policies (config.office.com) are not evaluated.
        Exit 0 = OK/not installed, 1 = error, 2 = updates disabled/channel mismatch.
#>
[CmdletBinding()]
param(
    [string]$ExpectedChannel = $env:updateOfficeExpectedChannel,
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
        if ($value -is [string] -and $value.Length -gt 300) { $value = $value.Substring(0, 300) }
        $table[$name] = $value
    }
    $table
}
try {
    if ([string]::IsNullOrWhiteSpace($ExpectedChannel) -or $ExpectedChannel.Trim() -eq 'null') { $ExpectedChannel = '' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $CustomField = $CustomField.Trim()
    $channels = [ordered]@{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'; '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'; '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'; '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'PerpetualVL2019'; '5030841d-c919-4594-8d2d-84ae4f96e58e' = 'PerpetualVL2021'
        '7983bac0-e531-40cf-be00-fd24fe66619c' = 'PerpetualVL2024'
    }
    if ($ExpectedChannel) {
        $match = @($channels.Values) | Where-Object { $_ -eq $ExpectedChannel.Trim() } | Select-Object -First 1
        if (-not $match) { throw ('updateOfficeExpectedChannel: ' + (@($channels.Values) -join ', ') + ' erforderlich / required.') }
        $ExpectedChannel = $match
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $branchNames = @{ Current = 'Current'; FirstReleaseCurrent = 'CurrentPreview'; MonthlyEnterprise = 'MonthlyEnterprise'
        Deferred = 'SemiAnnual'; FirstReleaseDeferred = 'SemiAnnualPreview'; InsiderFast = 'BetaChannel' }
    $resolveChannel = {
        param($Url)
        if ([string]::IsNullOrWhiteSpace([string]$Url)) { return $null }
        if ([string]$Url -match '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})') {
            $name = $channels[$Matches[1].ToLowerInvariant()]
            if ($name) { return $name }
        }
        return 'Custom'
    }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $installed = [bool](Test-Path -LiteralPath $configPath)
    $config = $null; $policy = $null; $current = $null; $target = $null
    $findings = [System.Collections.Generic.List[string]]::new()
    if ($installed) {
        $config = Get-RegistryValueTable -Path $configPath -Names @('VersionToReport', 'Platform', 'CDNBaseUrl', 'UpdateChannel', 'UpdateChannelChanged',
            'UpdatesEnabled', 'UpdateUrl', 'ProductReleaseIds')
        $policy = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate' -Names @('enableautomaticupdates',
            'updatebranch', 'updatetargetversion', 'updatepath', 'updatedeadline', 'hideenabledisableupdates')
        $current = & $resolveChannel $config.CDNBaseUrl
        $target = & $resolveChannel $config.UpdateChannel
        if (-not $target -and $policy.updatebranch) {
            $target = $branchNames[([string]$policy.updatebranch).Trim()]
            if (-not $target) { $target = 'Custom' }
        }
        if ([string]$config.UpdatesEnabled -eq 'False') { $findings.Add('UpdatesEnabled=False') }
        if ([string]$policy.enableautomaticupdates -eq '0') { $findings.Add('Policy enableautomaticupdates=0') }
        if ($ExpectedChannel -and $current -ne $ExpectedChannel) { $findings.Add("CurrentChannel '$current' != erwartet/expected $ExpectedChannel") }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Installed = $installed; Version = $(if ($config) { $config.VersionToReport })
        CurrentChannel = $current; TargetChannel = $target; ChannelChangePending = [bool]($target -and $current -and $target -ne $current)
        ExpectedChannel = $ExpectedChannel; Configuration = $config; Policy = $policy; Findings = @($findings)
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
