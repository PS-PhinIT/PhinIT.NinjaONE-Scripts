#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft Netzlaufwerke des angemeldeten Benutzers und verbindet sie optional dauerhaft mit festen Laufwerksbuchstaben.
    EN: Audits the logged-on user's network drives and optionally maps them persistently to fixed drive letters.
.DESCRIPTION
    DE: NetworkDrives enthält eine oder mehrere Zuordnungen "<Buchstabe>=<UNC-Pfad>", getrennt durch Semikolon oder
        Zeilenumbruch, z. B. "P=\\fs01\projekte;S=\\fs01.contoso.local\scan$". Für jeden Buchstaben wird die
        gespeicherte (dauerhafte) Zuordnung aus HKCU:\Network\<Buchstabe> und das aktuelle Laufwerk (Get-PSDrive)
        gelesen. Status: OK (dauerhaft mit dem Ziel verbunden), Missing (Buchstabe frei), NotPersistent (verbunden,
        aber nicht dauerhaft), Conflict (anderer Netzwerkpfad) oder LocalDrive (lokales Laufwerk/anderes Gerät).
        Ohne Opt-in (configNetworkDrivesAllow=true) wird nichts geändert. Mit Opt-in wird innerhalb von ShouldProcess
        "net use <X>: <UNC> /persistent:yes" ausgeführt (bei NotPersistent nach "net use <X>: /delete /y"); Conflict
        wird nur mit configNetworkDrivesReplace=true ersetzt, LocalDrive nie. Danach wird der Zustand erneut gelesen.
        Anmeldung: Es werden die Windows-Anmeldung des Benutzers bzw. in der Anmeldeinformationsverwaltung hinterlegte
        Anmeldeinformationen verwendet (siehe setNetworkCredentials.ps1); Kennwörter werden nicht übergeben.
        Laufwerke gehören immer zum Benutzer: In NinjaOne mit "Ausführen als: Angemeldeter Benutzer" starten; unter
        SYSTEM bricht das Skript mit Exit 1 ab. Nicht erhöht ausführen (UAC trennt Laufwerke erhöhter Prozesse).
        Bericht: Drives (Letter, Path, Before, After, CurrentPath, Changed, Error), Compliant, Allowed, WhatIf.
    EN: NetworkDrives holds one or more mappings "<letter>=<UNC path>", separated by semicolons or line breaks, e.g.
        "P=\\fs01\projects;S=\\fs01.contoso.local\scan$". For every letter the stored (persistent) mapping in
        HKCU:\Network\<letter> and the current drive (Get-PSDrive) are read. Status: OK (persistently mapped to the
        target), Missing (letter free), NotPersistent (connected but not persistent), Conflict (other network path) or
        LocalDrive (local disk/other device). Without opt-in (configNetworkDrivesAllow=true) nothing is changed. With
        opt-in "net use <X>: <UNC> /persistent:yes" runs inside ShouldProcess (for NotPersistent after
        "net use <X>: /delete /y"); Conflict is only replaced with configNetworkDrivesReplace=true, LocalDrive never.
        The state is read again afterwards.
        Sign-in: the user's Windows logon or credentials stored in Credential Manager are used (see
        setNetworkCredentials.ps1); no passwords are passed.
        Drives always belong to the user: run in NinjaOne with "Run As: Current Logged On User"; under SYSTEM the
        script stops with exit 1. Do not run elevated (UAC separates drives of elevated processes).
        Report: Drives (Letter, Path, Before, After, CurrentPath, Changed, Error), Compliant, Allowed, WhatIf.
.PARAMETER NetworkDrives
    DE: NinjaOne Text configNetworkDrives; erforderlich; "<Buchstabe>=<UNC>" je Laufwerk, getrennt durch ";" oder Zeilenumbruch; Buchstaben D-Z, je einmal; max. 24 Einträge; UNC \\Server\Freigabe[\Ordner], max. 260 Zeichen.
    EN: NinjaOne text configNetworkDrives; required; "<letter>=<UNC>" per drive, separated by ";" or line breaks; letters D-Z, each once; max. 24 entries; UNC \\server\share[\folder], max. 260 characters.
.PARAMETER Replace
    DE: NinjaOne Checkbox/Text configNetworkDrivesReplace; true/false; Standard false. true = Buchstaben ersetzen, die mit einem anderen Netzwerkpfad verbunden sind.
    EN: NinjaOne checkbox/text configNetworkDrivesReplace; true/false; default false. true = replace letters mapped to a different network path.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configNetworkDrivesAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configNetworkDrivesAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setNetworkDrives.ps1 -NetworkDrives 'P=\\fs01\projekte;S=\\fs01\scan$'
    DE: Nur Prüfung: Exit 2, wenn ein Laufwerk fehlt oder abweicht.
    EN: Audit only: exit 2 if a drive is missing or differs.
.EXAMPLE
    .\setNetworkDrives.ps1 -NetworkDrives 'P=\\fs01\projekte;S=\\fs01\scan$' -Allow true -WhatIf
    DE: Simuliert die Zuordnung; nichts wird geändert (Exit 0).
    EN: Simulates the mapping; nothing is changed (exit 0).
.EXAMPLE
    .\setNetworkDrives.ps1 -NetworkDrives 'P=\\nas.partner.local\daten' -Replace true -Allow true -CustomField driveReport
    DE: Verbindet P: dauerhaft (ersetzt eine abweichende Zuordnung) und schreibt das JSON in driveReport.
    EN: Maps P: persistently (replaces a different mapping) and writes the JSON to driveReport.
.NOTES
    DE: Windows PowerShell 5.1, 64-Bit, als angemeldeter Benutzer (nicht SYSTEM). Explizite Parameter haben Vorrang;
        leer/'null' = nicht gesetzt. Bei abweichendem Konto zuerst setNetworkCredentials.ps1 ausführen.
        Exit 0 = alle Laufwerke dauerhaft verbunden, erfolgreich verbunden oder -WhatIf mit Opt-in;
        1 = Eingabe-, Abfrage-, Verbindungs- oder Verifikationsfehler, Ausführung als SYSTEM, LocalDrive mit Opt-in;
        2 = Abweichung ohne Opt-in bzw. Conflict ohne configNetworkDrivesReplace oder Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, 64-bit, as the logged-on user (not SYSTEM). Explicit parameters win; empty/'null' =
        not set. For a different account run setNetworkCredentials.ps1 first.
        Exit 0 = all drives persistently mapped, mapped successfully or -WhatIf with opt-in;
        1 = input, query, mapping or verification error, run as SYSTEM, LocalDrive with opt-in;
        2 = drift without opt-in or Conflict without configNetworkDrivesReplace, or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$NetworkDrives = $env:configNetworkDrives,
    [string]$Replace = $env:configNetworkDrivesReplace,
    [string]$Allow = $env:configNetworkDrivesAllow,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-BooleanSetting {
    param([string]$Value, [string]$Name)
    $result = $false
    if (-not [bool]::TryParse($Value, [ref]$result)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $result
}
function Test-IsSystem {
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18' }
    catch { return [string]$env:USERNAME -eq ('{0}$' -f $env:COMPUTERNAME) }
}
function ConvertTo-DriveMapping {
    param([string]$Text)
    $mappings = @()
    foreach ($entry in @($Text -split '[;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $match = [regex]::Match($entry, '^([A-Za-z]):?\s*=\s*(.+)$')
        if (-not $match.Success) { throw ('configNetworkDrives: "<Buchstabe>=<UNC>" erwartet / expected: {0}' -f $entry) }
        $letter = $match.Groups[1].Value.ToUpperInvariant()
        $path = $match.Groups[2].Value.Trim().TrimEnd('\')
        if ($letter -notmatch '^[D-Z]$') { throw ('configNetworkDrives: Buchstabe D-Z / letter D-Z: {0}' -f $letter) }
        if ($path.Length -gt 260 -or $path -notmatch '^\\\\[A-Za-z0-9][A-Za-z0-9._-]*(\\[^\\/:*?"<>|\x00-\x1f]+)+$' -or $path -match '\\\.{1,2}(\\|$)') {
            throw ('configNetworkDrives: UNC \\Server\Freigabe erwartet / expected: {0}' -f $path)
        }
        if (@($mappings | Where-Object { $_.Letter -eq $letter }).Count -gt 0) { throw ('configNetworkDrives: Buchstabe doppelt / duplicate letter: {0}' -f $letter) }
        $mappings += [pscustomobject]@{ Letter = $letter; Path = $path }
    }
    if ($mappings.Count -eq 0) { throw 'configNetworkDrives erforderlich / required.' }
    if ($mappings.Count -gt 24) { throw 'configNetworkDrives: max. 24 Einträge / entries.' }
    return $mappings
}
function Get-DriveState {
    param([string]$Letter, [string]$Path)
    $persistent = $null
    $key = 'HKCU:\Network\{0}' -f $Letter
    if (Test-Path -LiteralPath $key) { $persistent = [string](Get-ItemProperty -LiteralPath $key -ErrorAction Stop).RemotePath }
    $drive = Get-PSDrive -Name $Letter -PSProvider FileSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $displayRoot = if ($drive) { ([string]$drive.DisplayRoot).TrimEnd('\') } else { '' }
    $connected = if ($displayRoot -like '\\*') { $displayRoot } else { '' }
    $persistent = ([string]$persistent).TrimEnd('\')
    $current = if ($persistent) { $persistent } elseif ($connected) { $connected } else { $null }
    $status = if ($drive -and -not $connected -and -not $persistent) { 'LocalDrive' }
    elseif (-not $current) { 'Missing' }
    elseif ($persistent -eq $Path -and (-not $connected -or $connected -eq $Path)) { 'OK' }
    elseif (-not $persistent -and $connected -eq $Path) { 'NotPersistent' }
    else { 'Conflict' }
    [pscustomobject]@{ Status = $status; CurrentPath = $current }
}
function Invoke-NetUse {
    param([string[]]$Arguments)
    $global:LASTEXITCODE = 0
    $output = @(net use @Arguments 2>&1 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($global:LASTEXITCODE -ne 0) {
        throw ('net use {0}: Exitcode / exit code {1}; {2}' -f ($Arguments -join ' '), $global:LASTEXITCODE, (@($output | Select-Object -Last 2) -join ' '))
    }
}
try {
    $NetworkDrives = Resolve-Setting $NetworkDrives ''
    $Replace = Resolve-Setting $Replace 'false'
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $mappings = @(ConvertTo-DriveMapping $NetworkDrives)
    $replaceConflicts = ConvertTo-BooleanSetting $Replace 'configNetworkDrivesReplace'
    $allowed = ConvertTo-BooleanSetting $Allow 'configNetworkDrivesAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    if (Test-IsSystem) { throw 'Als angemeldeter Benutzer ausführen, nicht als SYSTEM / Run as the logged-on user, not as SYSTEM.' }

    $results = @()
    foreach ($mapping in $mappings) {
        $state = Get-DriveState -Letter $mapping.Letter -Path $mapping.Path
        $result = [ordered]@{ Letter = $mapping.Letter; Path = $mapping.Path; Before = $state.Status; After = $state.Status; CurrentPath = $state.CurrentPath; Changed = $false; Error = $null }
        $needsChange = $state.Status -in @('Missing', 'NotPersistent') -or ($state.Status -eq 'Conflict' -and $replaceConflicts)
        if ($allowed -and $state.Status -eq 'LocalDrive') {
            $result.Error = 'Buchstabe durch lokales Laufwerk belegt / Letter used by a local drive.'
        } elseif ($allowed -and $needsChange -and $PSCmdlet.ShouldProcess(('{0}:' -f $mapping.Letter), ('Dauerhaft verbinden mit / Map persistently to {0}' -f $mapping.Path))) {
            try {
                if ($state.Status -ne 'Missing') { Invoke-NetUse @(('{0}:' -f $mapping.Letter), '/delete', '/y') }
                Invoke-NetUse @(('{0}:' -f $mapping.Letter), $mapping.Path, '/persistent:yes')
                $result.Changed = $true
                $after = Get-DriveState -Letter $mapping.Letter -Path $mapping.Path
                $result.After = $after.Status
                $result.CurrentPath = $after.CurrentPath
                if ($after.Status -ne 'OK') { $result.Error = ('Verifikation fehlgeschlagen / Verification failed: {0}' -f $after.Status) }
            }
            catch { $result.Error = $_.Exception.Message }
        }
        $results += [pscustomobject]$result
    }

    $errors = @($results | Where-Object { $_.Error })
    $pending = @($results | Where-Object { $_.After -ne 'OK' })
    $compliant = $pending.Count -eq 0
    $exitCode = 0
    if ($errors.Count -gt 0) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference -and @($pending | Where-Object { $_.After -eq 'Conflict' -and -not $replaceConflicts }).Count -eq 0)) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; User = $env:USERNAME; Setting = 'NetworkDrives'; Compliant = $compliant
        Allowed = $allowed; Replace = $replaceConflicts; WhatIf = [bool]$WhatIfPreference; Drives = @($results)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit $exitCode
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
