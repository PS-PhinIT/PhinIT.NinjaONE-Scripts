<#
.SYNOPSIS
    Setzt oder entfernt statische IPv4-DNS-Server nur auf produktiven Netzwerk­adaptern.

    Ein Adapter ist „produktiv“, wenn  
      • ein Default-Gateway vorhanden ist **oder**  
      • seine IPv4-Adresse im -TargetSubnet liegt **oder**  
      • sein Gateway der -TargetGateway-Adresse entspricht.

.DESCRIPTION
    • Ausgeführt als SYSTEM unter NinjaOne / NinjaRMM  
    • Windows 10/11 und Server 2012 R2 +  
    • Nur physische LAN/WLAN-Adapter – virtuelle, VPN, Loopback, Tunnel, Wi-Fi-Direct u.a. werden ignoriert  
    • `Set-DnsClientServerAddress`, Fallback `netsh` für Legacy-OS  
    • Aktualisiert optional das Custom-Field **DNS_LastChange** (nur wenn mindestens ein Adapter geändert wurde)

.PARAMETER PrimaryDNS
    Neuer primärer DNS-Server (IPv4). Pflicht im Static-Modus, wenn -ResetDHCP nicht verwendet wird.

.PARAMETER SecondaryDNS
    Optionaler zweiter DNS-Server (IPv4).

.PARAMETER TargetSubnet
    IPv4-Subnetz in CIDR-Notation (z. B. 192.168.10.0/24).
    Wird angegeben, werden nur Adapter berücksichtigt, deren IPv4-Adresse innerhalb dieses Netzes liegt.

.PARAMETER TargetGateway
    Explizite Gateway-Adresse (z. B. 192.168.10.1).
    Wird angegeben, werden nur Adapter berücksichtigt, deren Default-Gateway exakt dieser Adresse entspricht.

.PARAMETER AdapterName
    Optionale Liste von Adapter-Aliasen (Unterstützt Wildcards: "Ethernet*").

.PARAMETER ResetDHCP
    Entfernt statische DNS-Einträge und schaltet DNS auf DHCP zurück.
    Im DHCP-Modus darf PrimaryDNS nicht angegeben werden.

.PARAMETER NoCustomField
    Unterdrückt das Update des Custom-Fields "DNS_LastChange".

.EXAMPLE
    .\01-setDNSSettingsClient.ps1 -PrimaryDNS 10.0.0.10 -SecondaryDNS 10.0.0.11 -WhatIf

.EXAMPLE
    .\01-setDNSSettingsClient.ps1 -ResetDHCP -TargetSubnet 192.168.10.0/24

.NOTES
    Exit-Codes:
    0 = geändert
    1 = Fehler (auch wenn mindestens ein Adapter nicht geändert werden konnte)
    2 = nichts zu tun
    3 = DNS geändert, Custom-Field fehlgeschlagen

    Dateiname: 01-setDNSSettingsClient.ps1
    Autor:     Andreas Hepp
    Update:    14.10.2026
    Version:   1.6
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'StaticDNS')]
param (
    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [ValidatePattern('^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$')]
    [Alias('DNS1')]
    [string]$PrimaryDNS,

    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [ValidatePattern('^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$')]
    [Alias('DNS2')]
    [string]$SecondaryDNS,

    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [Parameter(Mandatory = $false, ParameterSetName = 'DHCP')]
    [string]$TargetSubnet,

    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [Parameter(Mandatory = $false, ParameterSetName = 'DHCP')]
    [string]$TargetGateway,

    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [Parameter(Mandatory = $false, ParameterSetName = 'DHCP')]
    [string[]]$AdapterName,

    [Parameter(Mandatory = $true, ParameterSetName = 'DHCP')]
    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [switch]$ResetDHCP,

    [Parameter(Mandatory = $false, ParameterSetName = 'StaticDNS')]
    [Parameter(Mandatory = $false, ParameterSetName = 'DHCP')]
    [switch]$NoCustomField
)

#--------------------------------------------------
#region 1 – Grundprüfungen & Settings
#--------------------------------------------------

# Hilfsfunktion zum Auslesen von Custom Fields aus NinjaRMM
function Get-NinjaCustomField {
    param (
        [string]$FieldName,
        [switch]$AsBoolean
    )
    
    $value = $null
    
    # Überprüfen, ob die Ninja-Property-Cmdlets existieren (ab Agent 5.3)
    $ninjaPropertyAvailable = $null
    if (-not $script:checkedNinjaPropertySupport) {
        try {
            $ninjaPropertyAvailable = Get-Command "Ninja-Property-Get" -ErrorAction SilentlyContinue
            $script:ninjaPropertySupport = $null -ne $ninjaPropertyAvailable
        } catch {
            $script:ninjaPropertySupport = $false
        }
        $script:checkedNinjaPropertySupport = $true
    }
    
    # Versuch 1: Ninja-Property-Get verwenden (wenn verfügbar)
    if ($script:ninjaPropertySupport) {
        try {
            $value = Ninja-Property-Get $FieldName -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "Ninja-Property-Get für '$FieldName' fehlgeschlagen: $_"
        }
    }
    
    # Versuch 2: CLI verwenden
    if (-not $value) {
        $cli = 'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe'
        if (Test-Path $cli) {
            try {
                $value = & $cli get $FieldName 2>$null
                if ($LASTEXITCODE -ne 0) { $value = $null }
            } catch {
                Write-Verbose "ninjarmm-cli get '$FieldName' fehlgeschlagen: $_"
            }
        }
    }
    
    # Wenn als Boolean gewünscht - true/1/yes als true, false/0/no/leer als false, sonst null
    if ($AsBoolean) {
        $text = ([string]$value).Trim()
        if ([string]::IsNullOrEmpty($text)) { return $false }
        if ($text -match '^(true|1|yes)$') { return $true }
        elseif ($text -match '^(false|0|no)$') { return $false }
        else { return $null }
    }
    
    return $value
}

# Skriptvariablen initialisieren
$script:checkedNinjaPropertySupport = $false
$script:ninjaPropertySupport = $false


# IPv4-Muster (Punktnotation) für DNS-Server und Gateway
$ipv4Pattern = '^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$'

# Custom-Field-Werte vor der Zuweisung prüfen: Parameter mit ValidatePattern würden sonst
# bei ungültigen Werten mit einer unbehandelten Ausnahme abbrechen.
function Assert-IPv4FieldValue {
    param([string]$FieldName, [string]$Value)
    if ($Value -notmatch $ipv4Pattern) {
        Write-Error "Ungültige IPv4-Adresse im Custom Field '$FieldName': '$Value'"
        exit 1
    }
}

# Custom Fields auslesen und Parameter ergänzen
$cf_PrimaryDNS = Get-NinjaCustomField -FieldName "DNS_PrimaryServer"
if ($cf_PrimaryDNS -and -not $PrimaryDNS) {
    Assert-IPv4FieldValue -FieldName 'DNS_PrimaryServer' -Value ([string]$cf_PrimaryDNS).Trim()
    $PrimaryDNS = ([string]$cf_PrimaryDNS).Trim()
    Write-Verbose "PrimaryDNS aus Custom Field: $PrimaryDNS"
}

$cf_SecondaryDNS = Get-NinjaCustomField -FieldName "DNS_SecondaryServer"
if ($cf_SecondaryDNS -and -not $SecondaryDNS) {
    Assert-IPv4FieldValue -FieldName 'DNS_SecondaryServer' -Value ([string]$cf_SecondaryDNS).Trim()
    $SecondaryDNS = ([string]$cf_SecondaryDNS).Trim()
    Write-Verbose "SecondaryDNS aus Custom Field: $SecondaryDNS"
}

$cf_TargetSubnet = Get-NinjaCustomField -FieldName "DNS_TargetSubnet"
if ($cf_TargetSubnet -and -not $TargetSubnet) {
    $TargetSubnet = $cf_TargetSubnet.Trim()
    Write-Verbose "TargetSubnet aus Custom Field: $TargetSubnet"
}

$cf_TargetGateway = Get-NinjaCustomField -FieldName "DNS_TargetGateway"
if ($cf_TargetGateway -and -not $TargetGateway) {
    $TargetGateway = $cf_TargetGateway.Trim()
    Write-Verbose "TargetGateway aus Custom Field: $TargetGateway"
}

$cf_AdapterName = Get-NinjaCustomField -FieldName "DNS_AdapterAliases"
if ($cf_AdapterName -and -not $AdapterName) {
    # Komma-getrennte Liste in Array umwandeln
    $AdapterName = $cf_AdapterName -split ',' | ForEach-Object { $_.Trim() }
    Write-Verbose "AdapterName aus Custom Field: $($AdapterName -join ', ')"
}

$cf_ResetDHCP = Get-NinjaCustomField -FieldName "DNS_ResetToDHCP" -AsBoolean
if ($null -eq $cf_ResetDHCP) {
    Write-Warning "Ungültiger Wert in DNS_ResetToDHCP Custom Field"
}
elseif ($cf_ResetDHCP -and -not $ResetDHCP) {
    $ResetDHCP = $true
    Write-Verbose "ResetDHCP aus Custom Field aktiviert"
}

# Grundprüfungen
if (-not $ResetDHCP -and -not $PrimaryDNS) {
    Write-Error "PrimaryDNS fehlt. Entweder -PrimaryDNS übergeben, Custom Field 'DNS_PrimaryServer' setzen oder -ResetDHCP verwenden."
    exit 1
}

# DNS-Server-Validierung (nur gültige IPv4-Adressen in Punktnotation; gilt auch für Custom-Field-Werte)
if (-not $ResetDHCP) {
    foreach ($dnsCandidate in @($PrimaryDNS, $SecondaryDNS)) {
        if ($dnsCandidate -and $dnsCandidate -notmatch $ipv4Pattern) {
            Write-Error "Ungültige IPv4-Adresse für DNS-Server: '$dnsCandidate'"
            exit 1
        }
    }
}
if ($TargetGateway -and $TargetGateway -notmatch $ipv4Pattern) {
    Write-Error "Ungültige IPv4-Adresse für TargetGateway: '$TargetGateway'"
    exit 1
}

$ErrorActionPreference = "Stop"
$VerbosePreference     = "Continue"

# Regex zum Unterdrücken virtueller Adapter mit case-insensitive Pattern
$virtualPattern = '(?i)VMware|Hyper-V|vEthernet|VPN|loopback|Tunnel|TAP|Wi-Fi Direct|WAN Miniport|Bluetooth|Remote Access'

# Regex für erlaubte Adapter-Typen (LAN/WLAN)
$allowedPattern = '(?i)(Ethernet|LAN|Wi-?Fi|WLAN|802\.11|Wireless|Realtek|Intel|Broadcom|Atheros|Qualcomm|TP-Link|D-Link|MediaTek|Killer|Marvell|NVIDIA|ASIX|Aquantia|Belkin|Linksys|Microsoft Wireless|Microsoft Ethernet)'

#--------------------------------------------------
#endregion
#region 2 – Hilfsfunktionen
#--------------------------------------------------

function Test-IPv4InSubnet {
    param (
        [string]$Ip,
        [string]$Cidr    # z. B. 192.168.10.0/24
    )
    try {
        # IP-Validierung
        if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$null)) {
            return $false
        }
        
        [IPAddress]$ipAddr = $Ip
        $parts = $Cidr.Split('/')
        
        # CIDR-Format validieren
        if ($parts.Length -ne 2) { return $false }
        if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$null)) {
            return $false
        }
        
        [IPAddress]$netAddr = $parts[0]
        
        # Präfix validieren (1-32)
        [int]$prefix = $parts[1]
        if ($prefix -lt 1 -or $prefix -gt 32) {
            # Präfix 0 nicht erlaubt (entspricht dem kompletten Internet)
            return $false
        }

        # Korrekte PowerShell-Syntax für Byte-Array-Umkehrung
        $ipBytes = [byte[]]$ipAddr.GetAddressBytes()
        [array]::Reverse($ipBytes)
        $ipBits = [BitConverter]::ToUInt32($ipBytes, 0)
        
        $netBytes = [byte[]]$netAddr.GetAddressBytes()
        [array]::Reverse($netBytes)
        $netBits = [BitConverter]::ToUInt32($netBytes, 0)
        
        $maskBits = 0xffffffff -shl (32 - $prefix)

        return (($ipBits -band $maskBits) -eq ($netBits -band $maskBits))
    }
    catch { return $false }
}

function Get-TargetAdapter {
    # Adapter filtern: Nur aktive Adapter, keine virtuellen Adapter
    # Hinweis: LinkSpeed ist ein Text (z. B. "0 bps"); daher numerische Eigenschaft Speed verwenden.
    $candidates = @(Get-NetAdapter | Where-Object {
        ($_.Status -in @('Up','Unknown') -or [uint64]$_.Speed -gt 0) -and
        $_.InterfaceDescription -inotmatch $virtualPattern
    })

    # Nur LAN/WLAN: per Beschreibung oder (ab Windows 10 2004 / Build 19041) per Hardware-ID als WLAN erkannt.
    # Die Hardware-Abfrage erfolgt nur für Adapter, die nicht bereits über die Beschreibung qualifiziert sind.
    $checkHardware = [Environment]::OSVersion.Version.Build -ge 19041
    $adapters = foreach ($adapter in $candidates) {
        if ($adapter.InterfaceDescription -match $allowedPattern) {
            $adapter
            continue
        }
        if ($checkHardware) {
            try {
                $hw = Get-NetAdapterHardwareInfo -InterfaceIndex $adapter.InterfaceIndex -ErrorAction Stop
                if ($hw -and $hw.PnPDeviceID -imatch 'WLAN|WiFi|Wireless|802\.11') { $adapter }
            } catch {
                Write-Verbose "Hardware-Info für '$($adapter.Name)' nicht verfügbar: $_"
            }
        }
    }

    # AdapterName-Filter: Wildcard-Vergleich (-like) je Alias, z. B. "Ethernet*"
    if ($AdapterName) {
        $adapters = $adapters | Where-Object {
            $name = $_.Name
            @($AdapterName | Where-Object { $_ -and $name -like $_ }).Count -gt 0
        }
    }

    # Anreicherung mit IP/Gateway-Informationen.
    # @(...) verhindert, dass bei genau einer Adresse das erste Zeichen statt der Adresse indiziert wird.
    $enriched = foreach ($a in $adapters) {
        try {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction Stop
        } catch {
            Write-Warning "IP-Konfiguration für '$($a.Name)' nicht lesbar - Adapter wird übersprungen: $_"
            continue
        }
        $ipv4List = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress } | Where-Object { $_ })
        $gwList   = @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ })
        [PSCustomObject]@{
            IfIndex       = $a.ifIndex
            Alias         = $a.Name
            InterfaceGuid = $a.InterfaceGuid
            IPv4          = $ipv4List | Select-Object -First 1
            IPv4All       = $ipv4List
            Gateway       = $gwList | Select-Object -First 1
            GatewayAll    = $gwList
        }
    }
    
    # Adapter-Selektionsstrategie gemäß Spezifikation:
    # 1. Wenn expliziter Gateway-Filter -> Nur mit passendem Gateway
    if ($TargetGateway) {
        $enriched = $enriched | Where-Object { $_.GatewayAll -contains $TargetGateway }
    }
    # 2. Wenn Subnetz-Filter -> Adapter mit mindestens einer IPv4-Adresse in diesem Subnetz (mit oder ohne Gateway)
    elseif ($TargetSubnet) {
        $enriched = $enriched | Where-Object {
            $ips = $_.IPv4All
            @($ips | Where-Object { Test-IPv4InSubnet $_ $TargetSubnet }).Count -gt 0
        }
    }
    # 3. Wenn weder Gateway- noch Subnetz-Filter -> Nur Adapter mit Gateway
    else {
        $enriched = $enriched | Where-Object Gateway
    }

    return $enriched
}

function Set-DnsIPv4 {
    # Wird ausschließlich nach $PSCmdlet.ShouldProcess() im Hauptteil aufgerufen.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([bool])]
    param(
        [int]$Idx,
        [string[]]$Srv,
        [switch]$Dhcp
    )
    # Timeout-Parameter für den Job
    $timeoutSec = 15
    
    try {
        # Als Job ausführen, um Hänger bei defekten Treibern zu vermeiden
        $scriptBlock = {
            param($Idx, $Srv, $Dhcp)
            
            [int]$localIdx = $Idx
            [string[]]$localSrv = @($Srv)
            [bool]$localDhcp = $Dhcp
            
            if ($localDhcp) { 
                Set-DnsClientServerAddress -InterfaceIndex $localIdx -ResetServerAddresses -ErrorAction Stop
            } else { 
                Set-DnsClientServerAddress -InterfaceIndex $localIdx -ServerAddresses $localSrv -ErrorAction Stop
            }
        }
        
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $Idx, $Srv, ([bool]$Dhcp)
        $finished = Wait-Job $job -Timeout $timeoutSec
        if ($finished) {
            # Fehler aus dem Job auswerten (ein fehlgeschlagener Job darf nicht als Erfolg gelten)
            $jobErrors = $null
            Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable jobErrors | Out-Null
            $jobState = $job.State
            Remove-Job $job -Force
            if ($jobState -eq 'Completed' -and -not $jobErrors) {
                return $true
            }
            Write-Warning "Set-DnsClientServerAddress fehlgeschlagen ($jobState): $($jobErrors -join '; ') - Fallback auf netsh"
        } else {
            Stop-Job $job
            Remove-Job $job -Force
            Write-Warning "Timeout bei Set-DnsClientServerAddress nach $timeoutSec Sekunden - Fallback auf netsh"
        }
    } catch {
        Write-Warning "Fehler bei Set-DnsClientServerAddress: $_ - Fallback auf netsh"
    }
    
    # Fallback auf netsh bei Timeout oder Fehler (Exitcode jedes Aufrufs prüfen)
    try {
        $alias = (Get-NetAdapter -InterfaceIndex $Idx -ErrorAction Stop).InterfaceAlias
        if ($Dhcp) { 
            $netshOut = netsh interface ip set dns name="$alias" source=dhcp 2>&1
            if ($LASTEXITCODE -ne 0) { throw "netsh set dns source=dhcp (Code $LASTEXITCODE): $netshOut" }
        } else {
            $netshOut = netsh interface ip set dns name="$alias" static $Srv[0] primary 2>&1
            if ($LASTEXITCODE -ne 0) { throw "netsh set dns static (Code $LASTEXITCODE): $netshOut" }
            # Dynamische Indizes für alle weiteren DNS-Server
            for ($i = 1; $i -lt $Srv.Count; $i++) { 
                $netshOut = netsh interface ip add dns name="$alias" $Srv[$i] "index=$($i + 1)" 2>&1
                if ($LASTEXITCODE -ne 0) { throw "netsh add dns (Code $LASTEXITCODE): $netshOut" }
            }
        }
        return $true
    } catch {
        Write-Warning "Fehler auch bei netsh-Fallback: $_"
        return $false
    }
}

function Test-DnsSourceIsDhcp {
    # Liefert $true (DNS per DHCP), $false (statisch) oder $null (unbekannt).
    # Statische IPv4-DNS-Server stehen im Registry-Wert "NameServer" des Interfaces; leer = DHCP.
    [OutputType([object])]
    param([string]$InterfaceGuid)
    if (-not $InterfaceGuid) { return $null }
    try {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$InterfaceGuid"
        $nameServer = (Get-ItemProperty -Path $key -Name NameServer -ErrorAction Stop).NameServer
        return [string]::IsNullOrWhiteSpace([string]$nameServer)
    } catch {
        Write-Verbose "DNS-Quelle für $InterfaceGuid nicht ermittelbar: $_"
        return $null
    }
}

function Update-DnsLastChangeField {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([bool])]
    param([string]$Value)
    $ok = $false
    
    # Prüfen, ob Ninja-Property-Set verfügbar ist
    if (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue) {
        try { 
            Ninja-Property-Set DNS_LastChange "$Value"
            # Erfolgreich nur wenn kein Fehler aufgetreten ist ($ErrorActionPreference = Stop)
            $ok = $true
        } catch { 
            Write-Verbose "Fehler bei Ninja-Property-Set: $_" 
        }
    }
    
    # Fallback: CLI verwenden wenn Property-Set fehlgeschlagen ist
    if (-not $ok) {
        $cli = 'C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe'
        if (Test-Path $cli) { 
            try {
                $cliOutput = & $cli set DNS_LastChange "$Value" 2>&1
                # Bei Erfolg ist LASTEXITCODE 0
                if ($LASTEXITCODE -eq 0) { 
                    $ok = $true 
                } else { 
                    Write-Verbose "CLI-Fehler (Code $LASTEXITCODE): $cliOutput" 
                }
            } catch {
                Write-Verbose "Fehler bei CLI-Aufruf: $_"
            }
        }
    }
    return $ok
}

function Exit-DnsScript {
    # Beendet Transcript und Skript mit dem angegebenen Exitcode.
    param([int]$Code, [string]$ErrorMessage)
    if ($ErrorMessage) { Write-Error $ErrorMessage -ErrorAction Continue }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit $Code
}

#--------------------------------------------------
#endregion
#region 3 – Ausführung
#--------------------------------------------------

# Optional Logging aktivieren
$logDir  = Join-Path $env:ProgramData 'NinjaRMMAgent\Logs'
$logPath = Join-Path $logDir "DNS_$(Get-Date -f yyyyMMdd_HHmmss).log"
# Logs-Verzeichnis erstellen, falls nicht vorhanden
New-Item -ItemType Directory -Path $logDir -ErrorAction Ignore | Out-Null
try { Start-Transcript -Path $logPath -ErrorAction Stop | Out-Null } catch { Write-Verbose "Transcript nicht möglich: $_" }

# Adapter ermitteln
$targets = @(Get-TargetAdapter)
if ($targets.Count -eq 0) { 
    Exit-DnsScript -Code 1 -ErrorMessage 'Kein passender Adapter gefunden.'
}

# DNS-Server-Liste erstellen (leeres Array bei DHCP, sonst deduplizierte Liste)
$servers = if ($ResetDHCP) { 
    @() 
} else { 
    @(@($PrimaryDNS, $SecondaryDNS) | Where-Object { $_ } | Select-Object -Unique)
}

# Fail-Fast: Wenn keine DNS-Server definiert und nicht ResetDHCP
if ($servers.Count -eq 0 -and -not $ResetDHCP) {
    Exit-DnsScript -Code 1 -ErrorMessage 'Keine gültigen DNS-Server angegeben. Benutze -ResetDHCP oder gib mindestens einen DNS-Server an.'
}

# Zähler initialisieren
$changed = 0
$skipped = 0
$failed  = 0
$log = [System.Text.StringBuilder]::new()

# Adapter durchlaufen und DNS-Einstellungen ändern
foreach ($t in $targets) {
    # Aktuelle DNS-Server ermitteln (explizit nur IPv4)
    try {
        $old = @((Get-DnsClientServerAddress -InterfaceIndex $t.IfIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses) -join ','
    } catch {
        Write-Warning "[$($t.Alias)] Aktuelle DNS-Server nicht lesbar: $_"
        $old = ''
    }
    $isDhcp = Test-DnsSourceIsDhcp -InterfaceGuid $t.InterfaceGuid
    $new = if ($ResetDHCP) { 'DHCP' } else { $servers -join ',' }
    
    # Nur ändern, wenn nötig:
    #  - DHCP-Modus: bereits DHCP (kein statischer NameServer)
    #  - Statisch:   gleiche Server und nicht nachweislich per DHCP bezogen
    $upToDate = if ($ResetDHCP) { $isDhcp -eq $true } else { $old -eq $new -and $isDhcp -ne $true }
    if ($upToDate) { 
        $skipped++
        Write-Verbose "[$($t.Alias)] DNS-Einstellungen unverändert: $(if ($ResetDHCP) { 'DHCP' } else { $old })"
        continue 
    }
    
    # Aktion definieren
    $action = if ($ResetDHCP) { 'DHCP aktiviert' } else { "DNS -> $new" }
    
    # DNS-Änderung durchführen, wenn ShouldProcess das erlaubt
    if ($PSCmdlet.ShouldProcess($t.Alias, $action)) {
        $logEntry = "[$($t.Alias)] $action (alt: $old)"
        if ($t.Gateway) { $logEntry += " GW:$($t.Gateway)" }

        if (Set-DnsIPv4 -Idx $t.IfIndex -Srv $servers -Dhcp:$ResetDHCP) {
            [void]$log.AppendLine($logEntry)
            Write-Verbose $logEntry
            $changed++
        } else {
            [void]$log.AppendLine("$logEntry - FEHLGESCHLAGEN")
            Write-Warning "$logEntry - FEHLGESCHLAGEN"
            $failed++
        }
    }
}

# DNS-Cache nur nach tatsächlichen Änderungen leeren
if ($changed -gt 0) {
    ipconfig /flushdns | Out-Null
}

# Ergebnisse ausgeben
Write-Output "`n==== DNS-Änderungsprotokoll ====`n$($log.ToString())`n==============================="

#--------------------------------------------------
#endregion
#region 4 – Custom-Field
#--------------------------------------------------
$customFieldFailed = $false
if (-not $NoCustomField -and $changed -gt 0) {
    $ts = (Get-Date -f 'yyyy-MM-dd HH:mm')
    $val = if ($ResetDHCP) { "DHCP aktiviert $ts" } else { "$($servers -join ', ') | $ts" }
    
    if (-not (Update-DnsLastChangeField -Value $val)) { 
        Write-Warning 'Custom-Field-Update fehlgeschlagen.'
        $customFieldFailed = $true
    } else {
        Write-Output "Custom Field 'DNS_LastChange' aktualisiert."
    }
}

#--------------------------------------------------
#endregion
#region 5 – Zusammenfassung
#--------------------------------------------------

# Kompakte Zusammenfassung
Write-Output "`nZusammenfassung der Ausführung:`n- Geänderte Adapter: $changed`n- Unveränderte Adapter: $skipped`n- Fehlgeschlagene Adapter: $failed`n"

# Exit-Code basierend auf Ergebnis
if ($failed) {
    Exit-DnsScript -Code 1 -ErrorMessage "DNS-Änderung auf $failed Adapter(n) fehlgeschlagen."
} elseif ($changed -and $customFieldFailed) {
    Exit-DnsScript -Code 3  # Soft-Fail: DNS geändert, aber CF nicht aktualisiert
} elseif ($changed) { 
    Write-Output "DNS-Einstellungen erfolgreich geändert."
    Exit-DnsScript -Code 0  # Changed
} elseif ($skipped) { 
    Write-Output "Keine DNS-Einstellungen geändert, da bereits korrekt konfiguriert."
    Exit-DnsScript -Code 2  # No Change
} elseif ($WhatIfPreference) {
    Write-Output "WhatIf: keine Änderungen durchgeführt."
    Exit-DnsScript -Code 2
} else { 
    Exit-DnsScript -Code 1 -ErrorMessage 'Keine passenden Adapter gefunden.'
}

#--------------------------------------------------
#endregion
