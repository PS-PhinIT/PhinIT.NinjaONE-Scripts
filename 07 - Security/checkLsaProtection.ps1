#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft den LSA-Schutz (LSASS als geschuetzter Prozess, RunAsPPL).
EN: Checks LSA protection (LSASS as a protected process, RunAsPPL).
.DESCRIPTION
DE: Liest HKLM:\SYSTEM\CurrentControlSet\Control\Lsa RunAsPPL und RunAsPPLBoot
    (0 aus, 1 aktiv mit UEFI-Sperre, 2 aktiv ohne UEFI-Sperre, ab Windows 11 22H2) sowie den
    Auditmodus (IFEO LSASS.exe AuditLevel 8). Fehlende Werte = State NotConfigured; wirksamer
    Standard RunAsPPL 0 (aus). Ausnahme: Windows 11 22H2+ kann LSA-Schutz auf geeigneten Geraeten
    ohne Registrywert aktivieren; dann bestaetigt das Wininit-Ereignis 12 im System-Log seit dem
    letzten Start ("LSASS.exe was started as a protected process") den Schutz.
    Die Ereignisabfrage ist auf den letzten Start und 1 Ereignis begrenzt; ein rotiertes
    System-Log kann das Ereignis entfernt haben (EventCheck NotFound).
EN: Reads HKLM:\SYSTEM\CurrentControlSet\Control\Lsa RunAsPPL and RunAsPPLBoot
    (0 off, 1 on with UEFI lock, 2 on without UEFI lock, Windows 11 22H2+) and audit mode
    (IFEO LSASS.exe AuditLevel 8). Absent values = State NotConfigured; effective default
    RunAsPPL 0 (off). Exception: Windows 11 22H2+ may enable LSA protection on eligible devices
    without a registry value; then Wininit event 12 in the System log since last boot
    ("LSASS.exe was started as a protected process") confirms protection.
    The event query is bounded to the last boot and 1 event; a rolled-over System log may have
    removed the event (EventCheck NotFound).
DE: Exit 2 = weder RunAsPPL 1/2 noch Ereignis 12 seit Start, ungueltiger Wert oder (bei
    RequireEvent=true) kein Ereignis 12 seit dem letzten Start.
EN: Exit 2 = neither RunAsPPL 1/2 nor event 12 since boot, invalid value or (with
    RequireEvent=true) no event 12 since the last boot.
.PARAMETER CheckEvent
DE: NinjaOne Checkbox/Text securityLsaCheckEvent: true/false; Standard true. Sucht Wininit-Ereignis 12 seit dem Start.
EN: NinjaOne checkbox/text securityLsaCheckEvent: true/false; default true. Looks for Wininit event 12 since boot.
.PARAMETER RequireEvent
DE: NinjaOne Checkbox/Text securityLsaRequireEvent: true/false; Standard false. true verlangt das Ereignis (impliziert CheckEvent).
EN: NinjaOne checkbox/text securityLsaRequireEvent: true/false; default false. true requires the event (implies CheckEvent).
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkLsaProtection.ps1
DE: Prueft RunAsPPL und sucht das Bestaetigungsereignis seit dem letzten Start.
EN: Checks RunAsPPL and looks for the confirmation event since the last boot.
.EXAMPLE
.\checkLsaProtection.ps1 -RequireEvent true -CustomField lsaProtection
DE: Verlangt zusaetzlich Ereignis 12; JSON in das MultiLine-Feld lsaProtection.
EN: Additionally requires event 12; JSON to the MultiLine field lsaProtection.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = geschuetzt, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = nicht geschuetzt/nicht bestaetigt.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = protected, 1 = input/query/write error, 2 = not protected/not confirmed.
#>
[CmdletBinding()]
param(
    [string]$CheckEvent = $env:securityLsaCheckEvent,
    [string]$RequireEvent = $env:securityLsaRequireEvent,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'

function Get-RegistrySetting {
    param([string]$Path, [string]$Name, $DefaultValue, [hashtable]$Map)
    $raw = $null
    if (Test-Path -LiteralPath $Path) {
        $property = (Get-ItemProperty -LiteralPath $Path).PSObject.Properties[$Name]
        if ($null -ne $property) { $raw = $property.Value }
    }
    $state = 'NotConfigured'
    $value = $null
    $effective = $DefaultValue
    if ($null -ne $raw) {
        $number = 0
        if ([int]::TryParse(([string]$raw).Trim(), [ref]$number)) { $state = 'Configured'; $value = $number; $effective = $number }
        else { $state = 'Invalid'; $effective = $null }
    }
    $meaning = $null
    if ($Map) {
        $meaning = 'Unknown'
        if ($null -ne $effective -and $Map.ContainsKey($effective)) { $meaning = $Map[$effective] }
    }
    [pscustomobject]@{ Name = $Name; State = $state; Value = $value; EffectiveValue = $effective; Meaning = $meaning }
}

try {
    $CheckEvent = ([string]$CheckEvent).Trim()
    if ($CheckEvent -ieq 'null' -or -not $CheckEvent) { $CheckEvent = 'true' }
    $withEvent = $false
    if (-not [bool]::TryParse($CheckEvent, [ref]$withEvent)) { throw 'CheckEvent muss true/false sein / must be true/false.' }
    $RequireEvent = ([string]$RequireEvent).Trim()
    if ($RequireEvent -ieq 'null' -or -not $RequireEvent) { $RequireEvent = 'false' }
    $needEvent = $false
    if (-not [bool]::TryParse($RequireEvent, [ref]$needEvent)) { throw 'RequireEvent muss true/false sein / must be true/false.' }
    if ($needEvent) { $withEvent = $true }
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }

    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $pplMap = @{ 0 = 'Disabled'; 1 = 'EnabledWithUefiLock'; 2 = 'EnabledWithoutUefiLock' }
    $runAsPpl = Get-RegistrySetting -Path $lsaPath -Name 'RunAsPPL' -DefaultValue 0 -Map $pplMap
    $runAsPplBoot = Get-RegistrySetting -Path $lsaPath -Name 'RunAsPPLBoot' -DefaultValue $null -Map $pplMap
    $audit = Get-RegistrySetting -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe' -Name 'AuditLevel' -DefaultValue $null -Map @{ 8 = 'AuditMode' }
    $registryEnabled = @(1, 2) -contains $runAsPpl.EffectiveValue

    $eventCheck = 'Skipped'
    $eventTime = $null
    $eventLevel = $null
    if ($withEvent) {
        $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        if ($null -eq $boot) { throw 'LastBootUpTime fehlt / unavailable.' }
        $events = @()
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Wininit'; Id = 12; StartTime = [datetime]$boot } -MaxEvents 1)
        }
        catch {
            if ([string]$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and [string]$_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
        }
        $eventCheck = 'NotFound'
        if ($events.Count -gt 0 -and $null -ne $events[0]) {
            $eventCheck = 'Verified'
            if ($null -ne $events[0].TimeCreated) { $eventTime = ([datetime]$events[0].TimeCreated).ToUniversalTime().ToString('o') }
            # DE: Erstes Datenfeld = Schutzlevel (unverifiziert, nur Info). EN: First data field = protection level (unverified, info only).
            $eventProperties = @($events[0].Properties)
            if ($eventProperties.Count -gt 0 -and $null -ne $eventProperties[0]) { $eventLevel = [string]$eventProperties[0].Value }
        }
    }
    $protected = $registryEnabled -or $eventCheck -eq 'Verified'

    $findings = New-Object System.Collections.Generic.List[string]
    if ($runAsPpl.State -eq 'Invalid') { $findings.Add('RunAsPPLInvalid') }
    if (-not $protected) { $findings.Add('LsaProtectionNotEnabled') }
    if ($needEvent -and $eventCheck -ne 'Verified') { $findings.Add('ProtectionEventMissing') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status; Protected = $protected; RegistryEnabled = $registryEnabled
        RunAsPPL = $runAsPpl; RunAsPPLBoot = $runAsPplBoot; LsassAuditLevel = $audit
        EventCheck = $eventCheck; EventTimeUtc = $eventTime; EventProtectionLevel = $eventLevel
        RequireEvent = $needEvent; Findings = @($findings)
    })
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
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
