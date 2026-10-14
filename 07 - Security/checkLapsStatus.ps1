#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prueft Windows-LAPS-/Legacy-LAPS-Konfiguration und Rotationsereignisse, ohne Kennwoerter zu lesen.
    EN: Checks Windows LAPS / legacy LAPS configuration and rotation events without reading passwords.
.DESCRIPTION
    DE: Liest die Richtlinienwurzeln in der Windows-LAPS-Reihenfolge: CSP (HKLM\SOFTWARE\Microsoft\Policies\LAPS),
        Gruppenrichtlinie (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS), lokale Konfiguration
        (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config) und Legacy-LAPS
        (HKLM\SOFTWARE\Policies\Microsoft Services\AdmPwd, AdmPwdEnabled). Die erste Wurzel mit Werten gilt.
        BackupDirectory: 0 = deaktiviert, 1 = Microsoft Entra ID, 2 = Active Directory.
        Ereignisse aus Microsoft-Windows-LAPS/Operational der letzten MaxSuccessAgeDays Tage (max. 500):
        Erfolg = 10004 (Richtlinienzyklus erfolgreich), 10020 (lokales Konto aktualisiert), 10044 (Reset nach
        Anmeldung); Fehler = 10005 (Richtlinienzyklus fehlgeschlagen), 10043 (Reset nach Anmeldung fehlgeschlagen).
        Verzeichnis-Updates 10018 (AD) / 10029 (Entra ID) werden gezaehlt. Quelle: Microsoft Learn
        "Use Windows LAPS event logs". Ist nur Legacy-LAPS mit installierter AdmPwd-CSE aktiv, entfaellt die
        Ereignispruefung (die CSE schreibt keine Windows-LAPS-Ereignisse).
        Es werden keine Kennwoerter, AD-Attribute oder Entra-Daten gelesen.
    EN: Reads the policy roots in Windows LAPS precedence: CSP (HKLM\SOFTWARE\Microsoft\Policies\LAPS),
        Group Policy (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS), local configuration
        (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config) and legacy LAPS
        (HKLM\SOFTWARE\Policies\Microsoft Services\AdmPwd, AdmPwdEnabled). The first root with values wins.
        BackupDirectory: 0 = disabled, 1 = Microsoft Entra ID, 2 = Active Directory.
        Events from Microsoft-Windows-LAPS/Operational of the last MaxSuccessAgeDays days (max. 500):
        success = 10004 (policy cycle succeeded), 10020 (local account updated), 10044 (post-authentication
        reset); failure = 10005 (policy cycle failed), 10043 (post-authentication reset failed).
        Directory updates 10018 (AD) / 10029 (Entra ID) are counted. Source: Microsoft Learn
        "Use Windows LAPS event logs". If only legacy LAPS with the AdmPwd CSE installed is active, the event
        check is skipped (the CSE does not write Windows LAPS events).
        No passwords, AD attributes or Entra data are read.
.PARAMETER MaxSuccessAgeDays
    DE: NinjaOne Integer securityLapsMaxSuccessAgeDays, 1..365; Standard 7. Zeitfenster fuer Erfolgsereignisse.
    EN: NinjaOne Integer securityLapsMaxSuccessAgeDays, 1..365; default 7. Window for success events.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkLapsStatus.ps1
    DE: Prueft LAPS-Richtlinie und verlangt einen Erfolg in den letzten 7 Tagen.
    EN: Checks LAPS policy and requires a success event within the last 7 days.
.EXAMPLE
    .\checkLapsStatus.ps1 -MaxSuccessAgeDays 2 -CustomField lapsStatus
    DE: Erfolg in den letzten 2 Tagen verlangen; JSON ins Feld lapsStatus.
    EN: Require success within 2 days; JSON to the field lapsStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter vor Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = kein LAPS konfiguriert, BackupDirectory 0,
        kein Erfolgsereignis im Zeitfenster oder letzter Fehler neuer als letzter Erfolg.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = no LAPS configured, BackupDirectory 0,
        no success event within the window or latest failure newer than latest success.
#>
[CmdletBinding()]
param(
    [string]$MaxSuccessAgeDays = $env:securityLapsMaxSuccessAgeDays,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-RegistryEntry {
    param([string]$Path)
    $map = @{}
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $map }
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { $map[$property.Name] = $property.Value }
    }
    return $map
}
try {
    $text = ([string]$MaxSuccessAgeDays).Trim()
    if (-not $text -or $text -ieq 'null') { $text = '7' }
    $days = 0
    if (-not [int]::TryParse($text, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$days) -or $days -lt 1 -or $days -gt 365) {
        throw 'securityLapsMaxSuccessAgeDays: 1..365 erforderlich / required.'
    }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }

    $roots = @(
        @{ Source = 'CSP'; Path = 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS' },
        @{ Source = 'GPO'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS' },
        @{ Source = 'LocalConfig'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config' }
    )
    $source = 'None'; $settings = @{}
    foreach ($root in $roots) {
        $values = Get-RegistryEntry -Path $root.Path
        if ($values.Count -gt 0) { $source = $root.Source; $settings = $values; break }
    }
    $legacy = Get-RegistryEntry -Path 'HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd'
    $legacyCse = (Get-RegistryEntry -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\GPExtensions\{D76B9641-3288-4f75-942D-087DE603E3EA}').Count -gt 0
    $legacyEnabled = $legacy.ContainsKey('AdmPwdEnabled') -and [string]$legacy['AdmPwdEnabled'] -eq '1'
    $backup = $null
    $findings = New-Object System.Collections.Generic.List[string]
    if ($source -ne 'None') {
        $backup = 0
        if ($settings.ContainsKey('BackupDirectory')) { $backup = [int]$settings['BackupDirectory'] }
        if ($backup -notin @(1, 2)) { $findings.Add('BackupDirectoryDisabled') }
    } elseif ($legacyEnabled) {
        $source = 'LegacyLAPS'; $settings = $legacy; $backup = 2
    } else {
        $findings.Add('NotConfigured')
    }
    $backupName = $null
    if ($null -ne $backup) { $backupName = @{ 0 = 'Disabled'; 1 = 'EntraID'; 2 = 'ActiveDirectory' }[$backup]; if (-not $backupName) { $backupName = 'Unknown' } }
    $eventCheck = 'Skipped'
    $lastSuccess = $null; $lastRotation = $null; $lastFailure = $null; $failureCount = 0; $directoryUpdates = 0
    if ($findings.Count -eq 0 -and -not ($source -eq 'LegacyLAPS' -and $legacyCse)) {
        $eventCheck = 'Evaluated'
        $filter = @{ LogName = 'Microsoft-Windows-LAPS/Operational'; Id = @(10004, 10005, 10018, 10020, 10029, 10043, 10044); StartTime = (Get-Date).AddDays(-$days) }
        $events = @()
        try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 500 -ErrorAction Stop) }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatching*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
        }
        foreach ($logEntry in ($events | Sort-Object TimeCreated -Descending)) {
            $time = ([datetime]$logEntry.TimeCreated).ToUniversalTime()
            if ($logEntry.Id -in @(10004, 10020, 10044) -and $null -eq $lastSuccess) { $lastSuccess = $time }
            if ($logEntry.Id -in @(10020, 10044) -and $null -eq $lastRotation) { $lastRotation = $time }
            if ($logEntry.Id -in @(10018, 10029)) { $directoryUpdates++ }
            if ($logEntry.Id -in @(10005, 10043)) { $failureCount++; if ($null -eq $lastFailure) { $lastFailure = $time } }
        }
        if ($null -eq $lastSuccess) { $findings.Add('NoSuccessWithinWindow') }
        elseif ($null -ne $lastFailure -and $lastFailure -gt $lastSuccess) { $findings.Add('LatestEventIsFailure') }
    } elseif ($source -eq 'LegacyLAPS') { $eventCheck = 'SkippedLegacyCse' }

    $reportObject = [ordered]@{
        PolicySource = $source; BackupDirectory = $backup; BackupDirectoryName = $backupName
        PasswordAgeDays = $settings['PasswordAgeDays']; PasswordLength = $settings['PasswordLength']; PasswordComplexity = $settings['PasswordComplexity']
        AdministratorAccountName = $(if ($settings.ContainsKey('AdministratorAccountName')) { [string]$settings['AdministratorAccountName'] } else { [string]$settings['AdminAccountName'] })
        LegacyPolicyEnabled = $legacyEnabled; LegacyCseInstalled = $legacyCse
        EventCheck = $eventCheck; WindowDays = $days
        LastSuccessUtc = $(if ($lastSuccess) { $lastSuccess.ToString('o') } else { $null })
        LastRotationUtc = $(if ($lastRotation) { $lastRotation.ToString('o') } else { $null })
        LastFailureUtc = $(if ($lastFailure) { $lastFailure.ToString('o') } else { $null })
        FailureEvents = $failureCount; DirectoryUpdateEvents = $directoryUpdates
        Findings = @($findings)
    }
    $report = ConvertTo-Json -InputObject $reportObject -Depth 4
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
