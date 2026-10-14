#Requires -Version 5.1

<#
.SYNOPSIS
DE: Temporaere und beschaedigte Benutzerprofile erkennen. EN: Detect temporary and corrupted user profiles.
.DESCRIPTION
DE: Prueft HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList auf *.bak-Schluessel,
State-Flags und ProfileImagePath-Ordner TEMP bzw. TEMP.*, Win32_UserProfile.Status (dokumentiert:
1 = Temporary, 8 = Corrupted) sowie die Ereignisse 1511/1515 des User Profile Service
(Anwendungsprotokoll) der letzten N Tage. Nur lesend; keine SIDs, Pfade oder Loeschung.
EN: Checks HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList for *.bak keys, State
flags and ProfileImagePath folder TEMP or TEMP.*, Win32_UserProfile.Status (documented: 1 =
Temporary, 8 = Corrupted) and User Profile Service events 1511/1515 (Application log) within the
last N days. Read-only; no SIDs, paths or deletion.
DE: State-Bits sind von Microsoft nicht offiziell dokumentiert (Community-Quellen, userenv):
0x0800 = PROFILE_TEMP_ASSIGNED (temporaeres Profil), 0x8000 = PROFILE_THIS_IS_BAK (Sicherungsschluessel).
Ereignis 1511 = Anmeldung mit temporaerem Profil; 1515 = Profil gesichert, Sicherung wird verwendet.
EN: State bits are not officially documented by Microsoft (community sources, userenv):
0x0800 = PROFILE_TEMP_ASSIGNED (temporary profile), 0x8000 = PROFILE_THIS_IS_BAK (backup key).
Event 1511 = logon with temporary profile; 1515 = profile backed up, backup will be used.
.PARAMETER EventDays
DE: NinjaOne userTempProfileEventDays (Integer), 1..365; Standard 7. Maximal 200 Ereignisse.
EN: NinjaOne userTempProfileEventDays (integer), 1..365; default 7. At most 200 events.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkTemporaryProfiles.ps1
DE: Registry, CIM und Ereignisse der letzten 7 Tage pruefen. EN: Check registry, CIM and events of the last 7 days.
.EXAMPLE
.\checkTemporaryProfiles.ps1 -EventDays 30 -CustomField tempProfiles
DE: Ereignisse der letzten 30 Tage; JSON in tempProfiles. EN: Events of the last 30 days; JSON to tempProfiles.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = keine Befunde, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein Registry-, CIM- oder Ereignisbefund.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no findings, 1 = input/query/write error, 2 = at least one registry, CIM or event finding.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$EventDays = $env:userTempProfileEventDays,
    [string]$MaxRecords = $env:userMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputValue {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw ('{0} must be {1}..{2} / muss {1}..{2} sein.' -f $Name, $Minimum, $Maximum)
    }
    return $number
}
function Get-BoundedEvent {
    param([hashtable]$Filter, [int]$Maximum)
    try { Get-WinEvent -FilterHashtable $Filter -MaxEvents $Maximum -ErrorAction Stop }
    catch {
        # DE: Keine Treffer sind kein Fehler. EN: No matching events is not an error.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    }
}
function Write-InventoryReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([System.Collections.IDictionary]$Report, [int]$Limit, [string]$Field)
    $all = @($Report['records'])
    $count = [Math]::Min($all.Count, $Limit)
    while ($true) {
        $Report['records'] = @($all | Select-Object -First $count)
        $Report['returned'] = $count
        $Report['truncated'] = ($count -lt $all.Count)
        $content = ConvertTo-Json -InputObject $Report -Depth 5
        if ($content.Length -le 4000 -or $count -eq 0) { break }
        $count--
    }
    Write-Output $content
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($content.Length -gt 4000) { throw 'Report exceeds 4000 characters / Bericht zu lang.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set unavailable / nicht verfuegbar.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $content | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Ninja-Property-Set failed / fehlgeschlagen.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell / 64-Bit-PowerShell verwenden.' }
    $days = ConvertTo-BoundedInt -Value (Get-InputValue $EventDays '7') -Name 'userTempProfileEventDays' -Minimum 1 -Maximum 365
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $findings = New-Object System.Collections.Generic.List[object]
    $listPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $keys = @(Get-ChildItem -LiteralPath $listPath -ErrorAction Stop)
    foreach ($key in $keys) {
        $keyName = [string]$key.PSChildName
        $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
        $folder = ((([string]$values.ProfileImagePath).TrimEnd('\', '/') -split '[\\/]')[-1])
        $state = [long]0
        if ($null -ne $values.State) { $state = ([long]$values.State) -band 0xFFFFFFFFL }
        $reasons = @()
        if ($keyName -match '\.bak$') { $reasons += 'BackupKey (.bak)' }
        if ($state -band 0x800) { $reasons += 'StateTempAssigned (0x800)' }
        if ($state -band 0x8000) { $reasons += 'StateThisIsBak (0x8000)' }
        if ($folder -match '^TEMP(\.|$)') { $reasons += 'TempProfileImagePath' }
        if ($reasons.Count -gt 0) {
            $findings.Add([pscustomobject]@{ source = 'ProfileList'; profileFolder = $folder; finding = ($reasons -join ', '); state = ('0x{0:X}' -f $state); timeUtc = $null })
        }
    }
    foreach ($userProfile in @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)) {
        $status = [long]$userProfile.Status
        $reasons = @()
        if ($status -band 1) { $reasons += 'Temporary (1)' }
        if ($status -band 8) { $reasons += 'Corrupted (8)' }
        if ($reasons.Count -gt 0) {
            $findings.Add([pscustomobject]@{
                source = 'Win32_UserProfile'; profileFolder = ((([string]$userProfile.LocalPath).TrimEnd('\', '/') -split '[\\/]')[-1])
                finding = ($reasons -join ', '); state = ('0x{0:X}' -f $status); timeUtc = $null
            })
        }
    }
    $filter = @{ LogName = 'Application'; ProviderName = 'Microsoft-Windows-User Profiles Service'; Id = @(1511, 1515); StartTime = (Get-Date).AddDays(-$days) }
    $events = @(Get-BoundedEvent -Filter $filter -Maximum 200)
    foreach ($logEvent in ($events | Sort-Object TimeCreated -Descending)) {
        $meaning = 'Backup profile will be used / Sicherungsprofil wird verwendet'
        if ($logEvent.Id -eq 1511) { $meaning = 'Temporary profile logon / Anmeldung mit temporaerem Profil' }
        $findings.Add([pscustomobject]@{
            source = ('Event {0}' -f $logEvent.Id); profileFolder = $null; finding = $meaning; state = $null
            timeUtc = ([DateTime]$logEvent.TimeCreated).ToUniversalTime().ToString('o')
        })
    }
    $report = [ordered]@{
        check = 'Temporary/corrupted profiles / Temporaere/beschaedigte Profile'; eventDays = $days
        profileListKeys = $keys.Count; eventCount = $events.Count; eventLimitReached = ($events.Count -ge 200)
        total = $findings.Count; returned = 0; truncated = $false; records = $findings.ToArray()
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
