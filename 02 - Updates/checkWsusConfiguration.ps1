#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die WSUS-Richtlinienkonfiguration (WUServer, UseWUServer, Zielgruppe).
    EN: Checks the WSUS policy configuration (WUServer, UseWUServer, target group).
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate (WUServer, WUStatusServer,
        UpdateServiceUrlAlternate, TargetGroupEnabled, TargetGroup, DoNotConnectToWindowsUpdate-
        InternetLocations, DisableDualScan, SetPolicyDrivenUpdateSource*) und den Unterschlüssel
        AU (UseWUServer, DetectionFrequency*). Optional werden ExpectedServer und
        ExpectedTargetGroup verglichen (ohne Groß-/Kleinschreibung, abschließendes / ignoriert).
        Exit 0 = Konfiguration lesbar und ohne Abweichung, 1 = Eingabe-, Abfrage- oder
        Schreibfehler, 2 = Abweichung: UseWUServer=1 ohne WUServer, oder bei ExpectedServer
        WSUS nicht aktiv bzw. WUServer/WUStatusServer abweichend, oder bei ExpectedTargetGroup
        Zielgruppe deaktiviert/abweichend.
    EN: Reads HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate (WUServer, WUStatusServer,
        UpdateServiceUrlAlternate, TargetGroupEnabled, TargetGroup, DoNotConnectToWindowsUpdate-
        InternetLocations, DisableDualScan, SetPolicyDrivenUpdateSource*) and the AU subkey
        (UseWUServer, DetectionFrequency*). ExpectedServer and ExpectedTargetGroup are compared
        optionally (case-insensitive, trailing / ignored). Exit 0 = configuration readable
        without mismatch, 1 = input, query or write error, 2 = mismatch: UseWUServer=1 without
        WUServer, or with ExpectedServer WSUS not active or WUServer/WUStatusServer different,
        or with ExpectedTargetGroup target group disabled/different.
.PARAMETER ExpectedServer
    DE: NinjaOne Text updateWsusExpectedServer: erwartete URL http(s)://host[:port]; Standard leer (kein Vergleich).
    EN: NinjaOne text updateWsusExpectedServer: expected URL http(s)://host[:port]; default empty (no comparison).
.PARAMETER ExpectedTargetGroup
    DE: NinjaOne Text updateWsusExpectedTargetGroup: erwartete Zielgruppe(n), max. 256 Zeichen; Standard leer.
    EN: NinjaOne text updateWsusExpectedTargetGroup: expected target group(s), max. 256 characters; default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\checkWsusConfiguration.ps1
    DE: Zeigt die WSUS-Richtlinie ohne Vergleich an.
    EN: Shows the WSUS policy without comparison.
.EXAMPLE
    .\checkWsusConfiguration.ps1 -ExpectedServer 'https://wsus.contoso.local:8531' -ExpectedTargetGroup 'Clients' -CustomField wsusConfig
    DE: Vergleicht Server und Zielgruppe, JSON ins Feld wsusConfig.
    EN: Compares server and target group, JSON to the field wsusConfig.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend; keine Verbindung zum WSUS.
        Exit 0 = OK, 1 = Fehler, 2 = Abweichung.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only; no connection to WSUS.
        Exit 0 = OK, 1 = error, 2 = mismatch.
#>
[CmdletBinding()]
param(
    [string]$ExpectedServer = $env:updateWsusExpectedServer,
    [string]$ExpectedTargetGroup = $env:updateWsusExpectedTargetGroup,
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
    if ([string]::IsNullOrWhiteSpace($ExpectedServer) -or $ExpectedServer.Trim() -eq 'null') { $ExpectedServer = '' }
    if ([string]::IsNullOrWhiteSpace($ExpectedTargetGroup) -or $ExpectedTargetGroup.Trim() -eq 'null') { $ExpectedTargetGroup = '' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $ExpectedServer = $ExpectedServer.Trim().TrimEnd('/')
    $ExpectedTargetGroup = $ExpectedTargetGroup.Trim()
    $CustomField = $CustomField.Trim()
    if ($ExpectedServer -and $ExpectedServer -notmatch '^https?://[A-Za-z0-9][A-Za-z0-9.-]{0,252}(:\d{1,5})?$') {
        throw 'updateWsusExpectedServer: http(s)://host[:port] erforderlich / required.'
    }
    if ($ExpectedTargetGroup -and $ExpectedTargetGroup -notmatch '^[\w .,;()-]{1,256}$') {
        throw 'updateWsusExpectedTargetGroup: ungültige Zeichen / invalid characters.'
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $wu = Get-RegistryValueTable -Path $base -Names @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate', 'TargetGroupEnabled', 'TargetGroup',
        'DoNotConnectToWindowsUpdateInternetLocations', 'DisableDualScan', 'SetPolicyDrivenUpdateSourceForQualityUpdates', 'SetPolicyDrivenUpdateSourceForFeatureUpdates')
    $au = Get-RegistryValueTable -Path "$base\AU" -Names @('UseWUServer', 'DetectionFrequencyEnabled', 'DetectionFrequency')
    $server = ([string]$wu.WUServer).Trim().TrimEnd('/')
    $statusServer = ([string]$wu.WUStatusServer).Trim().TrimEnd('/')
    $wsusEnabled = ([string]$au.UseWUServer -eq '1') -and [bool]$server
    $findings = [System.Collections.Generic.List[string]]::new()
    if ([string]$au.UseWUServer -eq '1' -and -not $server) { $findings.Add('UseWUServer=1 ohne/without WUServer') }
    if ($ExpectedServer) {
        if ([string]$au.UseWUServer -ne '1') { $findings.Add('UseWUServer nicht/not 1') }
        if ($server -ne $ExpectedServer) { $findings.Add('WUServer abweichend/mismatch') }
        if ($statusServer -ne $ExpectedServer) { $findings.Add('WUStatusServer abweichend/mismatch') }
    }
    if ($ExpectedTargetGroup) {
        if ([string]$wu.TargetGroupEnabled -ne '1') { $findings.Add('TargetGroupEnabled nicht/not 1') }
        if (([string]$wu.TargetGroup).Trim() -ne $ExpectedTargetGroup) { $findings.Add('TargetGroup abweichend/mismatch') }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; WsusEnabled = $wsusEnabled; ExpectedServer = $ExpectedServer
        ExpectedTargetGroup = $ExpectedTargetGroup; Policy = $wu; AU = $au; Findings = @($findings)
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
