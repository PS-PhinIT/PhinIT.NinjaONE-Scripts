#Requires -Version 5.1

<#
.SYNOPSIS
DE: VPN-Verbindungen fuer alle Benutzer inventarisieren. EN: Inventory all-user VPN connections.
.DESCRIPTION
DE: Liest Get-VpnConnection -AllUserConnection und meldet Name, Server, Tunneltyp, Authentifizierung,
Split-Tunneling und Verbindungsstatus. Keine Zugangsdaten, keine Aenderungen.
EN: Reads Get-VpnConnection -AllUserConnection and reports name, server, tunnel type, authentication,
split tunneling and connection status. No credentials, no system changes.
DE: Benutzerbezogene VPN-Verbindungen (Telefonbuch des Benutzers) sind fuer SYSTEM nicht sichtbar;
VPN-Clients von Drittanbietern werden nicht erfasst.
EN: Per-user VPN connections (user phonebook) are not visible to SYSTEM; third-party VPN clients are
not covered.
DE: Optionales MultiLine-Feld (resultCustomField); die Liste wird bis 4000 Zeichen gekuerzt (truncated).
EN: Optional MultiLine field (resultCustomField); the list shrinks to fit 4000 characters (truncated).
.PARAMETER RequiredConnection
DE: NinjaOne networkRequiredVpnName (Text); leer/null = keine Pflicht; exakter Name (ohne Gross-/Kleinschreibung),
1..256 Zeichen, keine Steuerzeichen, Anfuehrungszeichen oder Wildcards (*?[]).
EN: NinjaOne networkRequiredVpnName (text); blank/null = none required; exact name (case-insensitive),
1..256 characters, no control characters, quotes or wildcards (*?[]).
.PARAMETER MaxRecords
DE: NinjaOne networkVpnMaxRecords (Integer); Bereich 1..100; Standard 25.
EN: NinjaOne networkVpnMaxRecords (integer); range 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\checkVpnConnections.ps1
DE: Alle VPN-Verbindungen fuer alle Benutzer als JSON. EN: All all-user VPN connections as JSON.
.EXAMPLE
.\checkVpnConnections.ps1 -RequiredConnection 'Contoso VPN' -CustomField vpnConnections
DE: Exit 2, wenn "Contoso VPN" fehlt; JSON in vpnConnections. EN: Exit 2 if "Contoso VPN" is missing; JSON to vpnConnections.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend.
Exit 0 = gelesen (und Pflichtverbindung vorhanden), 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = networkRequiredVpnName ist nicht als Verbindung fuer alle Benutzer konfiguriert.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only.
Exit 0 = read (and required connection present), 1 = input/query/write error,
2 = networkRequiredVpnName is not configured as an all-user connection.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RequiredConnection = $env:networkRequiredVpnName,
    [string]$MaxRecords = $env:networkVpnMaxRecords,
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
    $RequiredConnection = ConvertTo-NetworkSetting $RequiredConnection
    $MaxRecords = ConvertTo-NetworkSetting $MaxRecords
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $MaxRecords) { $MaxRecords = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'networkVpnMaxRecords must be 1..100 / muss 1..100 sein.' }
    if ($RequiredConnection -and $RequiredConnection -notmatch '^[^\x00-\x1F\x7F"*?\[\]]{1,256}$') { throw 'Invalid networkRequiredVpnName / Ungueltiger networkRequiredVpnName.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue)) { throw 'Get-VpnConnection unavailable / nicht verfuegbar.' }
    # DE: "Keine Verbindung gefunden" ist kein Fehler. EN: "No connection found" is not an error.
    $vpnErrors = $null
    $found = @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue -ErrorVariable vpnErrors)
    $realErrors = @($vpnErrors | Where-Object { $_.CategoryInfo.Category -ne 'ObjectNotFound' })
    if ($realErrors.Count -gt 0) { throw $realErrors[0] }
    $connections = @($found | Where-Object { $null -ne $_ } | Sort-Object Name)
    $records = @($connections | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{
            name = ([string]$_.Name -replace '[\x00-\x1F\x7F]', ''); serverAddress = [string]$_.ServerAddress
            tunnelType = [string]$_.TunnelType; authentication = @($_.AuthenticationMethod | ForEach-Object { [string]$_ })
            splitTunneling = [bool]$_.SplitTunneling; connectionStatus = [string]$_.ConnectionStatus
        }
    })
    $present = $null
    if ($RequiredConnection) { $present = @($connections | Where-Object { [string]$_.Name -ieq $RequiredConnection }).Count -gt 0 }
    $shown = $records
    do {
        $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
            inventory = 'All-user VPN connections / VPN-Verbindungen aller Benutzer'
            requiredConnection = $(if ($RequiredConnection) { $RequiredConnection } else { $null }); requiredPresent = $present
            total = $connections.Count; returned = $shown.Count; truncated = ($shown.Count -lt $connections.Count); connections = $shown
        })
        $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
        if ($report.Length -le 4000) { break }
        if ($shown.Count -eq 0) { throw 'Report too large / Bericht zu gross.' }
        $shown = @($shown | Select-Object -First ($shown.Count - 1))
    } while ($true)
    Write-NetworkReport -Content $report -Field $CustomField
    if ($present -eq $false) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
