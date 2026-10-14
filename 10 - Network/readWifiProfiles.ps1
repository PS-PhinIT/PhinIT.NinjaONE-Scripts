#Requires -Version 5.1

<#
.SYNOPSIS
DE: Gespeicherte WLAN-Profile und deren Sicherheit melden. EN: Report saved Wi-Fi profiles and their security.
.DESCRIPTION
DE: Liest "netsh wlan show profiles" und je Profil "netsh wlan show profile name=..." OHNE key=clear.
Gemeldet werden Authentifizierung, Verschluesselung, Verbindungsmodus und ob ein Schluessel vorhanden ist.
WLAN-Schluessel werden nie abgefragt oder ausgegeben. Keine Aenderungen.
EN: Reads "netsh wlan show profiles" and per profile "netsh wlan show profile name=..." WITHOUT key=clear.
Reports authentication, cipher, connection mode and whether a key is present.
Wi-Fi keys are never requested or printed. No system changes.
DE: Profilnamen werden als ein einzelnes Argument uebergeben; Namen mit Steuerzeichen, Anfuehrungszeichen
oder ueber 64 Zeichen werden nicht abgefragt (Klassifizierung Skipped).
EN: Profile names are passed as one single argument; names with control characters, quotes or over
64 characters are not queried (classification Skipped).
DE: Sprachhinweis: Schluessel werden ueber bekannte englische/deutsche Bezeichnungen zugeordnet
(Authentication/Authentifizierung, Cipher/Verschluesselung, Security key/Sicherheitsschluessel,
Connection mode/Verbindungsmodus, All User Profile/Profil fuer alle Benutzer). Bei anderen Sprachen
oder Abfragefehlern lautet die Klassifizierung Unknown (kein Alarm). Gruppenrichtlinienprofile ohne
"Schluessel : Wert"-Zeile werden nicht erfasst. Ist WlanSvc nicht gestartet: NoWireless (Exit 0).
EN: Locale caveat: keys are mapped via known English/German labels (see above). Other languages or
query failures yield classification Unknown (no alert). Group policy profiles without a
"key : value" line are not listed. If WlanSvc is not running: NoWireless (exit 0).
DE: Optionales MultiLine-Feld (resultCustomField); Profilliste wird bis 4000 Zeichen gekuerzt (truncated).
EN: Optional MultiLine field (resultCustomField); the profile list shrinks to fit 4000 characters (truncated).
.PARAMETER MaxProfiles
DE: NinjaOne networkWifiMaxProfiles (Integer); max. abgefragte Profile 1..100; Standard 25.
EN: NinjaOne networkWifiMaxProfiles (integer); max. queried profiles 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text); leer/null = kein Feld; Name [A-Za-z][A-Za-z0-9_]{0,99}.
EN: NinjaOne resultCustomField (text); blank/null = no field; name [A-Za-z][A-Za-z0-9_]{0,99}.
.EXAMPLE
.\readWifiProfiles.ps1
DE: Bis zu 25 Profile pruefen; Exit 2 bei offenen oder WEP-Profilen.
EN: Check up to 25 profiles; exit 2 on open or WEP profiles.
.EXAMPLE
.\readWifiProfiles.ps1 -MaxProfiles 50 -CustomField wifiProfiles
DE: Bis zu 50 Profile; JSON-Bericht in wifiProfiles. EN: Up to 50 profiles; JSON report to wifiProfiles.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Nur lesend; keine Schluessel.
Exit 0 = keine offenen/WEP-Profile oder NoWireless, 1 = Eingabe-/Abfrage-/Schreibfehler,
2 = mindestens ein abgefragtes Profil mit Authentifizierung Open/Shared oder Verschluesselung WEP.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only; no keys.
Exit 0 = no open/WEP profiles or NoWireless, 1 = input/query/write error,
2 = at least one queried profile with authentication Open/Shared or cipher WEP.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MaxProfiles = $env:networkWifiMaxProfiles,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function ConvertTo-NetworkSetting {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -ieq 'null') { return '' }
    return $text
}
function Invoke-NetshWlan {
    param([string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        # DE: stderr unter PS 5.1 nicht als Abbruch werten. EN: Do not turn stderr into a terminating error under PS 5.1.
        $ErrorActionPreference = 'Continue'
        $lines = @(netsh @Arguments 2>&1 | ForEach-Object { [string]$_ })
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines }
    } finally {
        $ErrorActionPreference = $previousPreference
    }
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
    $MaxProfiles = ConvertTo-NetworkSetting $MaxProfiles
    $CustomField = ConvertTo-NetworkSetting $CustomField
    if (-not $MaxProfiles) { $MaxProfiles = '25' }
    $limit = 0
    if (-not [int]::TryParse($MaxProfiles, [ref]$limit) -or $limit -lt 1 -or $limit -gt 100) { throw 'networkWifiMaxProfiles must be 1..100 / muss 1..100 sein.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $service = Get-Service -Name 'WlanSvc' -ErrorAction SilentlyContinue
    $status = 'NoWireless'
    $names = New-Object System.Collections.Generic.List[string]
    if ($null -ne $service -and [string]$service.Status -eq 'Running') {
        $status = 'Wireless'
        $result = Invoke-NetshWlan -Arguments @('wlan', 'show', 'profiles')
        if ($result.ExitCode -ne 0) {
            if (($result.Lines -join ' ') -notmatch 'no wireless interface|keine Drahtlosschnittstelle') { throw ('netsh wlan show profiles failed with exit code {0} / fehlgeschlagen.' -f $result.ExitCode) }
            $status = 'NoWireless'
        }
        foreach ($line in $result.Lines) {
            if ($line -match '^\s*([^:]*Profil[^:]*?)\s+:\s*(.+)$' -and -not $names.Contains($Matches[2].Trim())) { $names.Add($Matches[2].Trim()) }
        }
    }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($name in ($names | Select-Object -First $limit)) {
        $record = [ordered]@{ name = ($name -replace '[\x00-\x1F\x7F]', ''); classification = 'Unknown'; authentication = @(); cipher = @(); securityKey = $null; connectionMode = $null }
        if ($name.Length -gt 64 -or $name -match '["\x00-\x1F\x7F]') {
            $record.classification = 'Skipped'
            $records.Add([pscustomobject]$record)
            continue
        }
        # DE: Name als EIN Argument, nie key=clear. EN: Name as ONE argument, never key=clear.
        $detail = Invoke-NetshWlan -Arguments @('wlan', 'show', 'profile', ('name={0}' -f $name))
        if ($detail.ExitCode -eq 0) {
            $auth = New-Object System.Collections.Generic.List[string]
            $cipher = New-Object System.Collections.Generic.List[string]
            foreach ($line in $detail.Lines) {
                if ($line -notmatch '^\s*([^:]+?)\s+:\s*(.*)$') { continue }
                $key = $Matches[1].Trim()
                $value = $Matches[2].Trim()
                if ($key -match '^(Authentication|Authentifizierung)$' -and -not $auth.Contains($value)) { $auth.Add($value) }
                elseif ($key -match '^(Cipher|Verschl.{1,3}sselung)$' -and -not $cipher.Contains($value)) { $cipher.Add($value) }
                elseif ($key -match '^(Security key|Sicherheitsschl.{1,3}ssel)$') { $record.securityKey = $value }
                elseif ($key -match '^(Connection mode|Verbindungsmodus)$') { $record.connectionMode = $value }
            }
            $record.authentication = $auth.ToArray()
            $record.cipher = $cipher.ToArray()
            if (@($cipher | Where-Object { $_ -match '^WEP' }).Count -gt 0 -or @($auth | Where-Object { $_ -match '^(Shared|Freigegeben)' }).Count -gt 0) {
                $record.classification = 'WEP'
            } elseif (@($auth | Where-Object { $_ -match '^(Open|Offen)$' }).Count -gt 0) {
                $record.classification = 'Open'
            } elseif ($auth.Count -gt 0) {
                $record.classification = 'Secured'
            }
        }
        $records.Add([pscustomobject]$record)
    }
    $insecure = @($records | Where-Object { $_.classification -in @('Open', 'WEP') }).Count
    $shown = $records.ToArray()
    do {
        $report = ConvertTo-Json -Depth 5 -Compress -InputObject ([pscustomobject]@{
            inventory = 'Wi-Fi profiles (no keys) / WLAN-Profile (ohne Schluessel)'; status = $status
            totalProfiles = $names.Count; queriedProfiles = $records.Count; insecureProfiles = $insecure
            reportedProfiles = $shown.Count; truncated = ($shown.Count -lt $names.Count); profiles = $shown
        })
        $report = $report -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
        if ($report.Length -le 4000) { break }
        if ($shown.Count -eq 0) { throw 'Report too large / Bericht zu gross.' }
        # DE: Unsichere Profile zuletzt kuerzen. EN: Truncate insecure profiles last.
        $shown = @(@($shown | Where-Object { $_.classification -in @('Open', 'WEP') }) + @($shown | Where-Object { $_.classification -notin @('Open', 'WEP') }) | Select-Object -First ($shown.Count - 1))
    } while ($true)
    Write-NetworkReport -Content $report -Field $CustomField
    if ($insecure -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
