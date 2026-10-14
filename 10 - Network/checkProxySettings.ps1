#Requires -Version 5.1

<#
.SYNOPSIS
DE: Maschinenweite Proxy-Einstellungen pruefen. EN: Check machine-wide proxy settings.
.DESCRIPTION
DE: Liest den WinHTTP-Proxy sprachunabhaengig aus dem Registry-Wert WinHttpSettings
(HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections; entspricht
"netsh winhttp show proxy"), die Richtlinie ProxySettingsPerUser
(HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings), die maschinenweiten
WinINET-Werte ProxyEnable/ProxyServer/ProxyOverride/AutoConfigURL sowie die Maschinen-Umgebungsvariablen
HTTP_PROXY, HTTPS_PROXY und NO_PROXY. Keine Aenderungen.
EN: Reads the WinHTTP proxy locale-independently from the WinHttpSettings registry value (same data as
"netsh winhttp show proxy"), the ProxySettingsPerUser policy, the machine-wide WinINET values
ProxyEnable/ProxyServer/ProxyOverride/AutoConfigURL and the machine environment variables
HTTP_PROXY, HTTPS_PROXY and NO_PROXY. No system changes.
DE: Zugangsdaten in Proxy-Angaben (user:pass@) werden vor der Ausgabe entfernt. Benutzerbezogene
Proxys (HKCU) sind fuer SYSTEM nicht sichtbar.
EN: Credentials in proxy values (user:pass@) are removed before output. Per-user proxies (HKCU) are
not visible to SYSTEM.
DE: Optionaler Soll-Proxy wird nur mit dem WinHTTP-Proxy verglichen (Gross-/Kleinschreibung egal).
EN: The optional expected proxy is compared with the WinHTTP proxy only (case-insensitive).
DE: Optionales MultiLine-Feld (resultCustomField), maximal 4000 Zeichen; -WhatIf liest, schreibt aber nicht.
EN: Optional MultiLine field (resultCustomField), max. 4000 characters; -WhatIf reads but skips the write.
.PARAMETER ExpectedProxy
DE: NinjaOne networkExpectedProxy (Text); leer/null = kein Vergleich; "direct" = kein WinHTTP-Proxy erwartet,
sonst exakte WinHTTP-Proxyangabe wie "proxy.contoso.local:8080" (max. 255 Zeichen, [A-Za-z0-9.:;=_\-\[\]]).
EN: NinjaOne networkExpectedProxy (text); blank/null = no comparison; "direct" = no WinHTTP proxy expected,
otherwise the exact WinHTTP proxy string such as "proxy.contoso.local:8080" (max. 255 chars, see allowlist).
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\checkProxySettings.ps1
DE: Proxy-Einstellungen als JSON, ohne Vergleich. EN: Proxy settings as JSON, no comparison.
.EXAMPLE
.\checkProxySettings.ps1 -ExpectedProxy proxy.contoso.local:8080 -CustomField proxyStatus
DE: Exit 2, wenn WinHTTP nicht proxy.contoso.local:8080 nutzt; JSON in proxyStatus.
EN: Exit 2 if WinHTTP does not use proxy.contoso.local:8080; JSON to proxyStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = gelesen und ggf. passend, 1 = Eingabe-/Abfrage-/Schreibfehler (inkl. defekter WinHttpSettings),
2 = WinHTTP-Proxy weicht von networkExpectedProxy ab.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = read and matching (if set), 1 = input/query/write error (incl. malformed WinHttpSettings),
2 = WinHTTP proxy differs from networkExpectedProxy.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExpectedProxy = $env:networkExpectedProxy,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-NetworkSetting {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -ieq 'null') { return '' }
    return $text
}
function Hide-ProxyCredential {
    param([string]$Value)
    if (-not $Value) { return $null }
    return (($Value -replace '[^;=\s/@]+@', '') -replace '[\x00-\x1F\x7F]', '')
}
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.PSObject.Properties[$Name]) { return $null }
    return $item.$Name
}
function ConvertFrom-WinHttpSetting {
    param([byte[]]$Data)
    # DE: Aufbau: Version, Zaehler, Flags, Laenge+Proxy, Laenge+Bypass (ASCII). EN: Layout: version, counter, flags, length+proxy, length+bypass (ASCII).
    if ($null -eq $Data -or $Data.Length -eq 0) { return [pscustomobject]@{ accessType = 'Direct'; proxyServer = $null; bypassList = $null; source = 'Default' } }
    if ($Data.Length -lt 12) { throw 'Malformed WinHttpSettings / Fehlerhafte WinHttpSettings.' }
    $flags = [BitConverter]::ToInt32($Data, 8)
    $offset = 12
    $parts = @()
    foreach ($index in 0, 1) {
        $text = ''
        if ($Data.Length -ge $offset + 4) {
            $length = [BitConverter]::ToInt32($Data, $offset)
            $offset += 4
            if ($length -lt 0 -or $length -gt 4096 -or $offset + $length -gt $Data.Length) { throw 'Malformed WinHttpSettings / Fehlerhafte WinHttpSettings.' }
            $text = [Text.Encoding]::ASCII.GetString($Data, $offset, $length)
            $offset += $length
        }
        $parts += $text
    }
    $accessType = 'Direct'
    if (($flags -band 2) -and $parts[0]) { $accessType = 'NamedProxy' }
    return [pscustomobject]@{ accessType = $accessType; proxyServer = (Hide-ProxyCredential $parts[0]); bypassList = (Hide-ProxyCredential $parts[1]); source = 'Registry' }
}
function Write-NetworkReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Content, [string]$Field)
    Write-Output $Content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($Content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $Content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $ExpectedProxy = ConvertTo-NetworkSetting $ExpectedProxy
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if ($ExpectedProxy -and ($ExpectedProxy.Length -gt 255 -or $ExpectedProxy -notmatch '^[A-Za-z0-9.:;=_\-\[\]]+$')) { throw 'Invalid networkExpectedProxy / Ungueltiger networkExpectedProxy.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $settingsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
    $winHttp = ConvertFrom-WinHttpSetting -Data ([byte[]](Get-RegistryValue -Path ($settingsPath + '\Connections') -Name 'WinHttpSettings'))
    $perUser = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxySettingsPerUser'
    $scope = 'PerUser (default)'
    if ($null -ne $perUser -and [int]$perUser -eq 0) { $scope = 'MachineWide (policy)' }
    elseif ($null -ne $perUser) { $scope = 'PerUser (policy)' }
    $proxyEnable = Get-RegistryValue -Path $settingsPath -Name 'ProxyEnable'
    $machineInternet = [pscustomobject]@{
        proxyEnabled = ($null -ne $proxyEnable -and [int]$proxyEnable -eq 1)
        proxyServer = Hide-ProxyCredential ([string](Get-RegistryValue -Path $settingsPath -Name 'ProxyServer'))
        proxyOverride = Hide-ProxyCredential ([string](Get-RegistryValue -Path $settingsPath -Name 'ProxyOverride'))
        autoConfigUrl = Hide-ProxyCredential ([string](Get-RegistryValue -Path $settingsPath -Name 'AutoConfigURL'))
    }
    $environment = [ordered]@{}
    foreach ($name in 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY') {
        $environment[$name] = Hide-ProxyCredential ([Environment]::GetEnvironmentVariable($name, 'Machine'))
    }
    $match = $null
    if ($ExpectedProxy) {
        if ($ExpectedProxy -ieq 'direct') { $match = $winHttp.accessType -eq 'Direct' }
        else { $match = $winHttp.accessType -eq 'NamedProxy' -and $winHttp.proxyServer -ieq $ExpectedProxy }
    }
    $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
        check = 'Machine proxy settings / Maschinen-Proxyeinstellungen'
        winHttp = $winHttp; proxySettingsPerUser = $perUser; proxyScope = $scope
        machineInternetSettings = $machineInternet; machineEnvironment = [pscustomobject]$environment
        expectedProxy = $(if ($ExpectedProxy) { $ExpectedProxy } else { $null }); matchesExpected = $match
    })
    $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-NetworkReport -Content $report -Field $CustomField
    if ($match -eq $false) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
