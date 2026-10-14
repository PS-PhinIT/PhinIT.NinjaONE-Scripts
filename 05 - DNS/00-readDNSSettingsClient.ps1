<#
.SYNOPSIS
    Liest DNS-Einstellungen von Clients aus und generiert einen Bericht.

.DESCRIPTION
    Dieses Skript sammelt DNS-Serveradressen von allen Netzwerkadaptern auf dem Client und
    generiert einen strukturierten Bericht. Es ist für die Ausführung über NINJA RMM konzipiert.

.PARAMETER NoCSV
    Mit diesem Parameter wird keine CSV-Datei erstellt.

.PARAMETER NoCustomField
    Mit diesem Parameter wird das Custom Field nicht aktualisiert.

.PARAMETER LogRetentionDays
    Anzahl der Tage (0-3650), für die CSV-Berichte und DNS-Logdateien aufbewahrt werden (Standard: 30).
    0 deaktiviert die Rotation. Ungültige Werte führen zum Standardwert 30.

.EXAMPLE
    .\00-readDNSSettingsClient.ps1 -NoCSV
    Bericht und Custom Fields DNS_Summary/DNS_Mismatch ohne CSV-Export.

.EXAMPLE
    .\00-readDNSSettingsClient.ps1 -LogRetentionDays 14 -NoCustomField
    Nur Bericht und CSV; CSV-/Logdateien älter als 14 Tage werden gelöscht.

.NOTES
    Exit-Codes: 0 = Bericht erstellt, 1 = keine Adapter/Abfragefehler.
    Custom Fields: DNS_Summary (Text, mehrzeilig), DNS_Mismatch (Checkbox).

    Dateiname: 00-readDNSSettingsClient.ps1
    Autor:     Andreas Hepp
    Update:    14.10.2026
    Version:   1.5
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$NoCSV,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCustomField,
    
    [Parameter(Mandatory = $false)]
    [object]$LogRetentionDays = 30
)

#requires -Version 5.1

#region Initialisierung und Konfiguration
# Sicherstellen, dass Fehler und Verbose ausgegeben werden
$ErrorActionPreference = "Continue"
$VerbosePreference = "Continue"

# Parameter-Validierung und Konvertierung (NinjaOne übergibt Werte als Text)
$parsedRetention = 0
if ([int]::TryParse(([string]$LogRetentionDays).Trim(), [ref]$parsedRetention) -and $parsedRetention -ge 0 -and $parsedRetention -le 3650) {
    $LogRetentionDays = $parsedRetention
} else {
    Write-Warning "Ungültiger Wert für LogRetentionDays ('$LogRetentionDays') - Standardwert 30 wird verwendet."
    $LogRetentionDays = 30
}

# Optional Logging aktivieren - im gleichen Verzeichnis wie das Set-Skript
$logDir = "$env:ProgramData\NinjaRMMAgent\Logs"
$logPath = "$logDir\DNSClient_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)
# Logs-Verzeichnis erstellen, falls nicht vorhanden
New-Item -ItemType Directory -Path $logDir -EA Ignore | Out-Null
Start-Transcript -Path $logPath -ErrorAction SilentlyContinue

# Modulprüfung und Fallback vorbereiten
if (-not (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue)) {
    Write-Verbose "Cmdlet Get-DnsClientServerAddress nicht verfügbar - WMI-Fallback wird verwendet."
}
#endregion

#region Hilfsfunktionen
# Funktion zum Formatieren der Ausgabe
function Format-Output {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    Write-Output "`n==== $Title ====`n"
    Write-Output "$Content"
    Write-Output "`n=====================`n"
}
#endregion

#region DNS-Informationssammlung
# Funktion zum Sammeln von DNS-Informationen mit modernen PowerShell-Cmdlets
function Get-DnsInfoModern {
    try {
        # Systeminfos sammeln (CIM statt des sehr langsamen Get-ComputerInfo)
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $hostname = $computerSystem.Name
        $domain = $computerSystem.Domain
        $osInfo = "$($operatingSystem.Caption) $($operatingSystem.Version)"
        
        # Adapter sammeln - Kompatibilität mit älteren Treibern
        # Filter für virtuelle und spezielle Interfaces
        $networkAdapters = Get-NetAdapter | Where-Object { 
            ($_.Status -in @('Up','Unknown') -or [uint64]$_.Speed -gt 0) -and 
            # Erweiterte Blacklist für virtuelle, Container und spezielle Adapter
            $_.InterfaceDescription -notmatch 'VMware|Hyper-V|vEthernet|WSL|Docker|VPN|loopback|Loopback|Tunnel|TAP|Wi-Fi Direct|WAN Miniport|Bluetooth'
        }
        $dnsReport = @()
        
        foreach ($adapter in $networkAdapters) {
            $adapterName = $adapter.Name
            $adapterType = $adapter.InterfaceDescription
            $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
            
            # DNS-Einstellungen abrufen
            $dnsSettings = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex | 
                          Where-Object { $_.AddressFamily -eq 2 -or $_.AddressFamily -eq 23 } # IPv4 (2) und IPv6 (23)
            
            # DNS-Suffix für diesen Adapter
            $dnsSuffix = (Get-DnsClient -InterfaceIndex $adapter.ifIndex).ConnectionSpecificSuffix
            if ([string]::IsNullOrEmpty($dnsSuffix)) {
                $dnsSuffix = "(Keine)"
            }
            
            # IP-Konfiguration
            $ipAddress = ($ipConfig.IPv4Address.IPAddress) -join ", "
            if ([string]::IsNullOrEmpty($ipAddress)) {
                $ipAddress = "(Keine)"
            }
            
            $ipv6Address = ($ipConfig.IPv6Address.IPAddress) -join ", "
            if ([string]::IsNullOrEmpty($ipv6Address)) {
                $ipv6Address = "(Keine)"
            }
            
            # Gateway
            $gateway = ($ipConfig.IPv4DefaultGateway.NextHop) -join ", "
            if ([string]::IsNullOrEmpty($gateway)) {
                $gateway = "(Keine)"
            }
            
            # DNS-Server sammeln
            $dnsServers = $dnsSettings | ForEach-Object {
                $addressFamily = if ($_.AddressFamily -eq 2) { "IPv4" } else { "IPv6" }
                $serverAddresses = $_.ServerAddresses -join ", "
                if ([string]::IsNullOrEmpty($serverAddresses)) {
                    $serverAddresses = "(Keine)"
                }
                
                [PSCustomObject]@{
                    AdapterName = $adapterName
                    AddressFamily = $addressFamily
                    ServerAddresses = $serverAddresses
                }
            }
            
            $dnsReport += [PSCustomObject]@{
                AdapterName = $adapterName
                AdapterDescription = $adapterType
                IPAddress = $ipAddress
                IPv6Address = $ipv6Address
                Gateway = $gateway
                DNSSuffix = $dnsSuffix
                DNSServers = $dnsServers
            }
        }
        
        return @{
            Hostname = $hostname
            Domain = $domain
            OSInfo = $osInfo
            DnsReport = $dnsReport
        }
    }
    catch {
        Write-Warning "Fehler bei Get-DnsInfoModern: $_"
        return $null
    }
}

# Funktion zum Sammeln von DNS-Informationen mit WMI für ältere Server (Windows 2008 R2)
function Get-DnsInfoWMI {
    try {
        # Systeminfos sammeln mit CIM (WMI-Klassen, ohne NetAdapter-/DnsClient-Module)
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        
        $hostname = $computerSystem.Name
        $domain = $computerSystem.Domain
        $osName = $osInfo.Caption
        $osVersion = $osInfo.Version
        $osInfoString = "$osName $osVersion"
        
        # Adapter sammeln mit CIM
        # Filter für virtuelle und spezielle Interfaces
        $networkAdapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -ErrorAction Stop | Where-Object { 
            # VMware, HyperV, VPN und Loopback ausfiltern
            $_.Description -notmatch 'VMware|Hyper-V|VPN|loopback|Loopback|Tunnel|TAP|Microsoft Wi-Fi Direct|WAN Miniport'
        }
        $dnsReport = @()
        
        foreach ($adapter in $networkAdapters) {
            $adapterName = $adapter.Description
            $adapterType = $adapter.Description
            
            # IP-Konfiguration
            $ipAddress = ($adapter.IPAddress | Where-Object { $_ -match '^[0-9]+\.' }) -join ", "
            if ([string]::IsNullOrEmpty($ipAddress)) {
                $ipAddress = "(Keine)"
            }
            
            $ipv6Address = ($adapter.IPAddress | Where-Object { $_ -match ':' }) -join ", "
            if ([string]::IsNullOrEmpty($ipv6Address)) {
                $ipv6Address = "(Keine)"
            }
            
            # Gateway
            $gateway = ($adapter.DefaultIPGateway) -join ", "
            if ([string]::IsNullOrEmpty($gateway)) {
                $gateway = "(Keine)"
            }
            
            # DNS-Suffix
            $dnsSuffix = $adapter.DNSDomainSuffixSearchOrder -join ", "
            if ([string]::IsNullOrEmpty($dnsSuffix)) {
                $dnsSuffix = "(Keine)"
            }
            
            # DNS-Server
            $dnsServerAddresses = $adapter.DNSServerSearchOrder -join ", "
            if ([string]::IsNullOrEmpty($dnsServerAddresses)) {
                $dnsServerAddresses = "(Keine)"
            }
            
            $dnsServers = @([PSCustomObject]@{
                AdapterName = $adapterName
                AddressFamily = "IPv4"
                ServerAddresses = $dnsServerAddresses
            })
            
            $dnsReport += [PSCustomObject]@{
                AdapterName = $adapterName
                AdapterDescription = $adapterType
                IPAddress = $ipAddress
                IPv6Address = $ipv6Address
                Gateway = $gateway
                DNSSuffix = $dnsSuffix
                DNSServers = $dnsServers
            }
        }
        
        return @{
            Hostname = $hostname
            Domain = $domain
            OSInfo = $osInfoString
            DnsReport = $dnsReport
        }
    }
    catch {
        Write-Warning "Fehler bei Get-DnsInfoWMI: $_"
        return $null
    }
}

# Versuche zuerst mit modernen Cmdlets, dann mit WMI-Fallback
try {
    $dnsInfo = Get-DnsInfoModern
    if (-not $dnsInfo) {
        Write-Output "Verwende WMI-Fallback für ältere Betriebssysteme..."
        $dnsInfo = Get-DnsInfoWMI
    }
    
    # Ergebnisse extrahieren
    $hostname = $dnsInfo.Hostname
    $domain = $dnsInfo.Domain
    $osInfo = $dnsInfo.OSInfo
    $dnsReport = $dnsInfo.DnsReport
}
catch {
    Write-Error "Kritischer Fehler beim Sammeln der DNS-Informationen: $_"
    exit 1
}
#endregion

# Netzwerkadapter und DNS-Informationen werden jetzt über die Funktionen Get-DnsInfoModern oder Get-DnsInfoWMI abgerufen

# Prüfen, ob überhaupt aktive Adapter gefunden wurden
if (-not $dnsReport -or $dnsReport.Count -eq 0) { 
    Write-Error "Keine aktiven Netzwerkadapter gefunden."
    exit 1 
}

Write-Verbose "$($dnsReport.Count) aktive Netzwerkadapter gefunden."

#region Berichtsgenerierung
# Bericht generieren
$reportOutput = [System.Text.StringBuilder]::new()

# Header
[void]$reportOutput.AppendLine("DNS-Einstellungen Bericht")
[void]$reportOutput.AppendLine("========================")
[void]$reportOutput.AppendLine("Erstellt: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')")
[void]$reportOutput.AppendLine("")

# System-Informationen
[void]$reportOutput.AppendLine("## System-Informationen")
[void]$reportOutput.AppendLine("Hostname: $hostname")
[void]$reportOutput.AppendLine("Domain/Workgroup: $domain")
[void]$reportOutput.AppendLine("Betriebssystem: $osInfo")
[void]$reportOutput.AppendLine("")

# DNS-Einstellungen nach Adapter
[void]$reportOutput.AppendLine("## DNS-Einstellungen nach Netzwerkadapter")

foreach ($adapter in $dnsReport) {
    [void]$reportOutput.AppendLine("`n### Adapter: $($adapter.AdapterName)")
    [void]$reportOutput.AppendLine("Beschreibung: $($adapter.AdapterDescription)")
    [void]$reportOutput.AppendLine("IP-Adresse (IPv4): $($adapter.IPAddress)")
    [void]$reportOutput.AppendLine("IP-Adresse (IPv6): $($adapter.IPv6Address)")
    [void]$reportOutput.AppendLine("Gateway: $($adapter.Gateway)")
    [void]$reportOutput.AppendLine("DNS-Suffix: $($adapter.DNSSuffix)")
    
    [void]$reportOutput.AppendLine("`nDNS-Server:")
    foreach ($dns in $adapter.DNSServers) {
        [void]$reportOutput.AppendLine("- $($dns.AddressFamily): $($dns.ServerAddresses)")
    }
    [void]$reportOutput.AppendLine("---")
}

# Zusätzlich: Für NINJA RMM - Kurze Zusammenfassung als separate Ausgabe
$summaryOutput = [System.Text.StringBuilder]::new()

# Für Log-Ausgabe komplettere Information mit Adapter-Namen
[void]$summaryOutput.AppendLine("Hostname: $hostname | Domain: $domain")
foreach ($adapter in $dnsReport) {
    $ipv4DNS = ($adapter.DNSServers | Where-Object { $_.AddressFamily -eq "IPv4" }).ServerAddresses
    [void]$summaryOutput.AppendLine("$($adapter.AdapterName): $ipv4DNS")
}

# Für Custom Field nur die reinen DNS-Server sammeln
$customFieldDnsServers = [System.Collections.ArrayList]@()
$adapterDnsServers = @{} # Speichert DNS je Adapter für Mismatch-Erkennung

foreach ($adapter in $dnsReport) {
    $ipv4DNS = ($adapter.DNSServers | Where-Object { $_.AddressFamily -eq "IPv4" }).ServerAddresses
    if ($ipv4DNS -and $ipv4DNS -ne "(Keine)") {
        # Für Custom Field sammeln (ohne Duplikate)
        if ($customFieldDnsServers -notcontains $ipv4DNS) {
            $null = $customFieldDnsServers.Add($ipv4DNS)
        }
        
        # Für DNS-Mismatch-Erkennung je Adapter speichern
        $adapterDnsServers[$adapter.AdapterName] = $ipv4DNS
    }
}


# DNS Mismatch-Erkennung: Prüfen, ob verschiedene DNS-Server bei aktiven Adaptern vorhanden sind
$hasDnsMismatch = $false

# Nur prüfen wenn mindestens zwei Adapter mit DNS-Servern vorhanden sind
if ($adapterDnsServers.Keys.Count -gt 1) {
    $firstDnsServer = $null
    
    # Den ersten DNS-Server als Referenz nehmen
    foreach ($adapter in $adapterDnsServers.Keys) {
        if (-not $firstDnsServer) {
            $firstDnsServer = $adapterDnsServers[$adapter]
        } else {
            # DNS-Server dieses Adapters mit dem Referenz-DNS vergleichen
            if ($adapterDnsServers[$adapter] -ne $firstDnsServer) {
                $hasDnsMismatch = $true
                Write-Verbose "DNS-Mismatch gefunden: Adapter '$adapter' verwendet '$($adapterDnsServers[$adapter])' statt '$firstDnsServer'"
                break
            }
        }
    }
}

# DNS-Mismatch-Warnung in den Bericht aufnehmen, wenn gefunden
if ($hasDnsMismatch) {
    [void]$reportOutput.AppendLine("`n## Warnungen")
    [void]$reportOutput.AppendLine("Warnung: Unterschiedliche DNS-Server zwischen Adaptern erkannt!")
    [void]$reportOutput.AppendLine("Dies kann zu Netzwerkproblemen und inkonsistentem Verhalten führen.")
}

# Ausgabe für NinjaOne (erst nach der Mismatch-Erkennung, damit Warnungen enthalten sind)
Format-Output -Title "DNS-Einstellungen Bericht" -Content $reportOutput.ToString()

# Ausgabe der Zusammenfassung
Format-Output -Title "DNS-Zusammenfassung" -Content $summaryOutput.ToString()
#endregion

#region CSV-Export
# === CSV-Datei für Tabular Report erstellen ===========================
if (-not $NoCSV) {
    try {
        # Verzeichnis für Berichte erstellen, falls nicht vorhanden
        $reportDir = Join-Path $logDir 'Reports'
        New-Item -Path $reportDir -ItemType Directory -EA Ignore | Out-Null
        
        # Log-Rotation: Alte Berichte, DNS-Logs und temporäre Anhänge löschen (nach LogRetentionDays)
        if ($LogRetentionDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
            $oldReports = @(
                Get-ChildItem -Path $reportDir -Filter 'DNS_Report_*.csv' -File -ErrorAction SilentlyContinue
                Get-ChildItem -Path $logDir -Filter 'DNS*.log' -File -ErrorAction SilentlyContinue
                if ($env:TEMP) { Get-ChildItem -Path $env:TEMP -Filter 'DNSReport_*.csv' -File -ErrorAction SilentlyContinue }
            ) | Where-Object { $_.LastWriteTime -lt $cutoff }
            
            if ($oldReports.Count -gt 0) {
                Write-Output "$($oldReports.Count) alte Berichte/Logs werden gelöscht (älter als $LogRetentionDays Tage)"
                $oldReports | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        
        # CSV-Datei erstellen (permanenter Speicherort) mit Zeitstempel zur Vermeidung von Namenskonflikten
        $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $csvFile = Join-Path -Path $reportDir -ChildPath "DNS_Report_${hostname}_${timestamp}.csv"
        
        # Daten für CSV vorbereiten
        $csvData = @()
        foreach ($adapter in $dnsReport) {
            foreach ($dns in $adapter.DNSServers) {
                $csvData += [PSCustomObject]@{
                    Hostname = $hostname
                    Domain = $domain
                    AdapterName = $adapter.AdapterName
                    AdapterDescription = $adapter.AdapterDescription
                    IPAddress = $adapter.IPAddress
                    Gateway = $adapter.Gateway
                    DNSSuffix = $adapter.DNSSuffix
                    AddressFamily = $dns.AddressFamily
                    DNSServers = $dns.ServerAddresses
                    ReportDate = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                }
            }
        }
        
        # CSV exportieren (mit Force zum Überschreiben vorhandener Dateien)
        $csvData | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Force
        Write-Output "CSV-Bericht erstellt: $csvFile"
        
        # Temporäre Datei für Ninja-Anhang erstellen (mit Zeitstempel gegen Namenskonflikte)
        $tempCsvPath = Join-Path $env:TEMP "DNSReport_${hostname}_${timestamp}.csv"
        $csvData | Export-Csv -Path $tempCsvPath -NoTypeInformation -Encoding UTF8 -Force
        Write-Output "SCRIPT_FILE:$tempCsvPath"  # <- Ninja erkennt das Präfix und hängt die Datei an
    }
    catch {
        Write-Warning "CSV-Export fehlgeschlagen: $_"
    }
}
else {
    Write-Output "CSV-Export übersprungen (Parameter -NoCSV aktiviert)"
}
#endregion

#region Custom-Field-Update
# === Custom-Field-Update für DNS_Summary und DNS_Mismatch =================
if (-not $NoCustomField) {
    try {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
            throw 'Ninja-Property-Set ist nicht verfügbar (NinjaOne-Agent >= 5.3 erforderlich).'
        }
        # Nicht-terminierende Fehler von Ninja-Property-Set ebenfalls abfangen
        $ErrorActionPreference = 'Stop'

        # Liste für alle gefundenen DNS-Server
        $dnsServerList = [System.Collections.ArrayList]@()
        
        # Über alle Adapter iterieren und ihre DNS-Server sammeln
        foreach ($adapter in $dnsReport) {
            # Für jeden Adapter über die DNS-Server-Einträge iterieren
            foreach ($dnsInfo in $adapter.DNSServers) {
                # Nur IPv4 DNS-Server berücksichtigen
                if ($dnsInfo.AddressFamily -eq "IPv4") {
                    $servers = $dnsInfo.ServerAddresses
                    if ($servers -and $servers -ne "(Keine)") {
                        # Einzelne Server extrahieren (falls mehrere durch Komma getrennt sind)
                        $serverArray = $servers -split "[,;]" | ForEach-Object { $_.Trim() }
                        foreach ($server in $serverArray) {
                            if ($server -and $server -ne "(Keine)" -and $server -notmatch "^$") {
                                $null = $dnsServerList.Add($server)
                            }
                        }
                    }
                }
            }
        }
        
        # Duplikate entfernen
        $uniqueDnsServers = @($dnsServerList | Select-Object -Unique)
        
        # Kommagetrennter String mit den DNS-Servern
        $fieldValue = if ($uniqueDnsServers.Count) {
            $uniqueDnsServers -join ", "
        } else {
            "Keine DNS-Server gefunden"
        }

        # Custom Field DNS_Summary aktualisieren
        Ninja-Property-Set DNS_Summary "$fieldValue"
        Write-Verbose "Custom Field 'DNS_Summary' erfolgreich mit DNS-Server-Adressen befüllt"

        # Custom Field DNS_Mismatch (Checkbox) aktualisieren
        Ninja-Property-Set DNS_Mismatch $hasDnsMismatch
        Write-Verbose "Custom Field 'DNS_Mismatch' auf '$hasDnsMismatch' gesetzt"
    }
    catch {
        Write-Warning "Custom-Field-Update für 'DNS_Summary'/'DNS_Mismatch' fehlgeschlagen: $_"
    }
    finally {
        $ErrorActionPreference = 'Continue'
    }
}
else {
    Write-Output "Custom-Field-Update übersprungen (Parameter -NoCustomField aktiviert)"
}

# Transcript beenden
Stop-Transcript -ErrorAction SilentlyContinue
#endregion
 
#region Abschluss
Write-Verbose "Skriptausführung erfolgreich abgeschlossen."
Write-Output "DNS-Bericht erfolgreich erstellt."
exit 0 
#endregion
