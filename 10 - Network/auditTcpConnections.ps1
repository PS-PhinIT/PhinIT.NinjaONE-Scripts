#Requires -Version 5.1
<#
.SYNOPSIS
DE: Lokales TCP-Verbindungsinventar. EN: Local TCP connection inventory.
.DESCRIPTION
DE: Nur lokale Daten; kein Portscan. Keine Prozessbefehle oder Zugangsdaten.
EN: Reads local data only; not a port scanner. No process command lines or credentials.
DE: Als SYSTEM mit 64-Bit-PowerShell starten. Momentaufnahme, keine Sicherheitsbewertung.
EN: Run as SYSTEM in 64-bit PowerShell. A snapshot, not a security assessment.
DE: Parameter haben Vorrang vor NinjaOne-Variablen tcpState, maxRecords,
resultFormat und resultCustomField. Leere Werte verwenden die Standardwerte.
EN: Explicit parameters override those NinjaOne variables; blanks use defaults.
DE/EN: resultFormat = Json (default) / PlainText; optionales/optional CustomField:
NinjaOne MultiLine (auch fuer JSON / also for JSON), maximal/maximum 4000 Zeichen/characters.
DE/EN: Exit 0 = Erfolg/success, 1 = Fehler/error, 2 = Alarm/alert (hier nicht verwendet/not used).
#>
[CmdletBinding()]
param(
    [string]$ConnectionState = $env:tcpState,
    [string]$MaxRecords = $env:maxRecords,
    [string]$ResultFormat = $env:resultFormat,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'

function Write-InventoryReport {
    param([object]$Report, [string]$Format, [string]$Field)
    if ($Format -eq 'Json') {
        $content = ConvertTo-Json -InputObject $Report -Depth 6 -Compress
    } else {
        $summary = $Report | Select-Object * -ExcludeProperty records | Format-List | Out-String -Width 200
        $rows = $Report.records | Format-List | Out-String -Width 200
        $content = ($summary + $rows).Trim()
    }
    # DE: Steuerzeichen entfernen. EN: Remove terminal control characters.
    $content = $content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    if ($Field) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters; reduce maxRecords. / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
    Write-Output $content
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Windows required / erforderlich.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $ConnectionState = ([string]$ConnectionState).Trim()
    $MaxRecords = ([string]$MaxRecords).Trim()
    $ResultFormat = ([string]$ResultFormat).Trim()
    $CustomField = ([string]$CustomField).Trim()
    # DE: NinjaOne-Platzhalter normalisieren. EN: Normalize NinjaOne null placeholders.
    if ($ConnectionState -ieq 'null') { $ConnectionState = '' }
    if ($MaxRecords -ieq 'null') { $MaxRecords = '' }
    if ($ResultFormat -ieq 'null') { $ResultFormat = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if (-not $ConnectionState) { $ConnectionState = 'All' }
    if (-not $MaxRecords) { $MaxRecords = '10' }
    if (-not $ResultFormat) { $ResultFormat = 'Json' }
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'maxRecords must be 1..100 / muss 1..100 sein.' }
    if ($ResultFormat -notin @('Json', 'PlainText')) { throw 'resultFormat must be Json or PlainText / muss Json oder PlainText sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if ($ConnectionState -notin @('All', 'Closed', 'SynSent', 'SynReceived', 'Established', 'FinWait1', 'FinWait2', 'CloseWait', 'Closing', 'LastAck', 'TimeWait', 'DeleteTCB', 'Bound')) { throw 'Invalid tcpState / Ungueltiger tcpState (Listen excluded / ausgeschlossen).' }
    $connections = @(Get-NetTCPConnection -ErrorAction Stop | Where-Object {
        $_.State -ne 'Listen' -and ($ConnectionState -eq 'All' -or $_.State -eq $ConnectionState)
    } | Sort-Object LocalAddress, LocalPort, RemoteAddress, RemotePort)
    $records = @($connections | Select-Object -First $limit | ForEach-Object {
        [pscustomobject]@{
            localAddress = $_.LocalAddress; localPort = $_.LocalPort
            remoteAddress = $_.RemoteAddress; remotePort = $_.RemotePort
            state = [string]$_.State; processId = $_.OwningProcess
        }
    })
    $report = [pscustomobject]@{
        inventory = 'Local TCP connections / Lokale TCP-Verbindungen'
        scope = 'Snapshot; excludes listeners / Momentaufnahme ohne Listener'
        filter = $ConnectionState; total = $connections.Count; returned = $records.Count
        truncated = ($connections.Count -gt $records.Count); records = $records
    }
    Write-InventoryReport -Report $report -Format $ResultFormat -Field $CustomField
    exit 0
} catch {
    # DE/EN: Keine Rohfehler mit Endpunktdaten / No raw errors containing endpoint data.
    Write-Error 'TCP inventory or field write failed; check Windows, parameters, permissions and NinjaOne field configuration. / TCP-Inventar oder Feldschreiben fehlgeschlagen.' -ErrorAction Continue
    exit 1
}