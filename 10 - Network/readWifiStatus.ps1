#Requires -Version 5.1

<#
.SYNOPSIS
DE: WLAN-Verbindungsstatus lesen. EN: Read Wi-Fi connection status.
.DESCRIPTION
DE: Liest "netsh wlan show interfaces" und meldet je WLAN-Schnittstelle Name, Status, SSID, BSSID,
Signal in %, Funktyp, Kanal und Authentifizierung. Keine Schluessel, keine Aenderungen.
EN: Reads "netsh wlan show interfaces" and reports name, state, SSID, BSSID, signal %, radio type,
channel and authentication per Wi-Fi interface. No keys, no system changes.
DE: Ist der Dienst WlanSvc nicht vorhanden/gestartet oder gibt es keine WLAN-Schnittstelle,
wird NoWireless gemeldet (Exit 0).
EN: If the WlanSvc service is missing/stopped or no Wi-Fi interface exists, NoWireless is reported (exit 0).
DE: Sprachhinweis: netsh-Ausgabe ist lokalisiert. Zeilen "Schluessel : Wert" werden ueber bekannte
englische und deutsche Schluessel zugeordnet (z. B. Radio type/Funktyp, Channel/Kanal,
Authentication/Authentifizierung). Andere Sprachen liefern ggf. leere Felder; SSID/BSSID/Signal
sind meist sprachneutral. Neuere Windows-Versionen koennen fuer netsh wlan eine Standortfreigabe
verlangen; dann endet das Skript mit Exit 1.
EN: Locale caveat: netsh output is localized. "key : value" lines are mapped via known English and
German keys (e.g. Radio type/Funktyp, Channel/Kanal, Authentication/Authentifizierung). Other
languages may leave fields empty; SSID/BSSID/signal are usually language-neutral. Newer Windows
builds may require location permission for netsh wlan; then the script exits 1.
DE: Optionales MultiLine-Feld (resultCustomField), maximal 4000 Zeichen; -WhatIf liest, schreibt aber nicht.
EN: Optional MultiLine field (resultCustomField), max. 4000 characters; -WhatIf reads but skips the write.
.PARAMETER MinSignalPercent
DE: NinjaOne networkMinSignalPercent (Integer); Bereich 1..100; Standard 40.
EN: NinjaOne networkMinSignalPercent (integer); range 1..100; default 40.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\readWifiStatus.ps1
DE: WLAN-Status als JSON; Exit 2 bei Signal unter 40 %. EN: Wi-Fi status as JSON; exit 2 if signal below 40%.
.EXAMPLE
.\readWifiStatus.ps1 -MinSignalPercent 60 -CustomField wifiStatus
DE: Grenzwert 60 %; JSON-Bericht in wifiStatus. EN: Threshold 60%; JSON report to wifiStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = OK, getrennt oder NoWireless, 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = mindestens eine verbundene Schnittstelle mit Signal unter networkMinSignalPercent.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = OK, disconnected or NoWireless, 1 = input/query/write error,
2 = at least one connected interface with signal below networkMinSignalPercent.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MinSignalPercent = $env:networkMinSignalPercent,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-NetworkSetting {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -ieq 'null') { return '' }
    return $text
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
    $MinSignalPercent = ConvertTo-NetworkSetting $MinSignalPercent
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $MinSignalPercent) { $MinSignalPercent = '40' }
    $minSignal = 0
    if (-not [int]::TryParse($MinSignalPercent, [ref]$minSignal) -or $minSignal -lt 1 -or $minSignal -gt 100) { throw 'networkMinSignalPercent must be 1..100 / muss 1..100 sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    # DE: Bekannte EN/DE-Schluessel auf Felder abbilden. EN: Map known EN/DE keys to fields.
    $keyMap = [ordered]@{
        '^(Name)$' = 'name'; '^(State|Status)$' = 'state'; '^SSID$' = 'ssid'; '^(AP )?BSSID$' = 'bssid'
        '^(Radio type|Funktyp)$' = 'radioType'; '^(Channel|Kanal)$' = 'channel'
        '^(Authentication|Authentifizierung)$' = 'authentication'; '^Signal$' = 'signal'; '^Band$' = 'band'
    }
    $service = Get-Service -Name 'WlanSvc' -ErrorAction SilentlyContinue
    $interfaces = New-Object System.Collections.Generic.List[object]
    $status = 'NoWireless'
    if ($null -ne $service -and [string]$service.Status -eq 'Running') {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $lines = @(netsh wlan show interfaces 2>&1 | ForEach-Object { [string]$_ })
            $netshExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        $current = $null
        foreach ($line in $lines) {
            if ($line -notmatch '^\s*([^:]+?)\s+:\s*(.*)$') { continue }
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $field = $null
            foreach ($pattern in $keyMap.Keys) { if ($key -match $pattern) { $field = $keyMap[$pattern]; break } }
            if (-not $field) { continue }
            if ($field -eq 'name' -or $null -eq $current) {
                $current = [ordered]@{ name = $null; state = $null; ssid = $null; bssid = $null; signalPercent = $null; radioType = $null; channel = $null; authentication = $null; band = $null; lowSignal = $false }
                $interfaces.Add($current)
            }
            if ($field -eq 'signal') {
                if ($value -match '(\d{1,3})\s*%') { $current.signalPercent = [int]$Matches[1] }
            } else {
                $current[$field] = $value
            }
        }
        if ($interfaces.Count -gt 0) {
            $status = 'Wireless'
        } elseif ($netshExit -ne 0 -and ($lines -join ' ') -notmatch 'no wireless interface|keine Drahtlosschnittstelle|wlansvc') {
            throw ('netsh wlan failed with exit code {0} / netsh wlan fehlgeschlagen.' -f $netshExit)
        }
    }
    $alert = $false
    foreach ($entry in $interfaces) {
        if ($entry.ssid -and $null -ne $entry.signalPercent -and $entry.signalPercent -lt $minSignal) {
            $entry.lowSignal = $true
            $alert = $true
        }
    }
    $records = @($interfaces | Select-Object -First 10 | ForEach-Object { [pscustomobject]$_ })
    $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
        inventory = 'Wi-Fi interfaces / WLAN-Schnittstellen'; status = $status
        minSignalPercent = $minSignal; totalInterfaces = $interfaces.Count
        connected = @($records | Where-Object { $_.ssid }).Count; interfaces = $records
    })
    $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    Write-NetworkReport -Content $report -Field $CustomField
    if ($alert) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
