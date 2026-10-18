#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft den Windows-Schnellstart (Hiberboot) und setzt ihn optional auf den Sollzustand.
    EN: Audits Windows Fast Startup (Hiberboot) and optionally sets it to the desired state.
.DESCRIPTION
    DE: Liest HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power, Wert HiberbootEnabled
        (DWORD 1 = aktiv, 0 = aus). Fehlt der Wert, gilt der Windows-Standard (aktiv); Current wird dann als
        'Default(Enabled)' gemeldet und als aktiv bewertet. Der Bericht enthält Current, Desired, Compliant,
        Changed, Allowed, WhatIf und Differences. Ohne Opt-in (configFastStartupAllow=true) wird nichts geändert.
        Mit Opt-in wird nur der abweichende Wert innerhalb von ShouldProcess als DWORD geschrieben (fehlender
        Schlüssel wird angelegt) und danach erneut gelesen. Schnellstart benötigt den Ruhezustand; HibernateEnabled
        aus HKLM:\SYSTEM\CurrentControlSet\Control\Power wird nur informativ gemeldet (keine Änderung).
    EN: Reads HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power, value HiberbootEnabled
        (DWORD 1 = enabled, 0 = disabled). A missing value means the Windows default (enabled); Current is then
        reported as 'Default(Enabled)' and treated as enabled. The report contains Current, Desired, Compliant,
        Changed, Allowed, WhatIf and Differences. Without opt-in (configFastStartupAllow=true) nothing is changed.
        With opt-in only the differing value is written as DWORD inside ShouldProcess (a missing key is created)
        and read back. Fast Startup requires hibernation; HibernateEnabled from
        HKLM:\SYSTEM\CurrentControlSet\Control\Power is reported for information only (never changed).
.PARAMETER Enabled
    DE: NinjaOne Checkbox/Text configFastStartupEnabled; erforderlich; true = Schnellstart aktiv, false = aus.
    EN: NinjaOne checkbox/text configFastStartupEnabled; required; true = Fast Startup on, false = off.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configFastStartupAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configFastStartupAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setFastStartup.ps1 -Enabled false
    DE: Nur Prüfung: Exit 2, wenn der Schnellstart aktiv ist; keine Änderung.
    EN: Audit only: exit 2 if Fast Startup is enabled; nothing is changed.
.EXAMPLE
    .\setFastStartup.ps1 -Enabled false -Allow true -WhatIf
    DE: Simuliert das Deaktivieren; nichts wird geschrieben (Exit 0).
    EN: Simulates disabling; nothing is written (exit 0).
.EXAMPLE
    .\setFastStartup.ps1 -Enabled false -Allow true -CustomField fastStartupReport
    DE: Deaktiviert den Schnellstart, prüft durch erneutes Lesen und schreibt das JSON in fastStartupReport.
    EN: Disables Fast Startup, verifies by reading back and writes the JSON to fastStartupReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang vor NinjaOne-Variablen; leer/'null' = nicht gesetzt.
        Wirksam ab dem nächsten Herunterfahren. Gruppenrichtlinien (HiberbootEnabled unter Policies) werden nicht ausgewertet.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler; 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win over NinjaOne variables; empty/'null' = not set.
        Effective from the next shutdown. Group Policy (HiberbootEnabled under Policies) is not evaluated.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error; 2 = drift without opt-in or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Enabled = $env:configFastStartupEnabled,
    [string]$Allow = $env:configFastStartupAllow,
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
function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($null -ne $item -and $item.PSObject.Properties[$Name]) { return $item.$Name }
    return $null
}
function Write-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop
}
try {
    $Enabled = Resolve-Setting $Enabled ''
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if (-not $Enabled) { throw 'configFastStartupEnabled erforderlich (true/false) / required (true/false).' }
    $desiredEnabled = ConvertTo-BooleanSetting $Enabled 'configFastStartupEnabled'
    $allowed = ConvertTo-BooleanSetting $Allow 'configFastStartupAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $powerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $desiredValue = 0
    $desiredText = 'Disabled'
    if ($desiredEnabled) { $desiredValue = 1; $desiredText = 'Enabled' }
    $readState = {
        $raw = Get-RegistryValue -Path $powerPath -Name 'HiberbootEnabled'
        $text = 'Invalid({0})' -f $raw
        if ($null -eq $raw) { $text = 'Default(Enabled)' }
        elseif ($raw -is [int] -and $raw -eq 1) { $text = 'Enabled' }
        elseif ($raw -is [int] -and $raw -eq 0) { $text = 'Disabled' }
        $isCompliant = ($raw -is [int] -and $raw -eq $desiredValue) -or ($desiredEnabled -and $null -eq $raw)
        [pscustomobject]@{ Raw = $raw; Text = $text; Compliant = [bool]$isCompliant }
    }
    $state = & $readState
    $differences = @()
    if (-not $state.Compliant) { $differences += ('HiberbootEnabled: {0} -> {1}' -f $state.Text, $desiredValue) }
    $attempted = $false
    $changed = $false
    if ($allowed -and -not $state.Compliant) {
        if ($PSCmdlet.ShouldProcess("$powerPath\HiberbootEnabled", ('Schnellstart setzen auf {0} / Set Fast Startup to {0}' -f $desiredText))) {
            $attempted = $true
            Write-RegistryValue -Path $powerPath -Name 'HiberbootEnabled' -Value ([int]$desiredValue) -Type 'DWord'
            $changed = $true
            $state = & $readState
        }
    }
    $hibernate = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
    $notes = @()
    if ($desiredEnabled -and $null -ne $hibernate -and [string]$hibernate -eq '0') {
        $notes += 'Ruhezustand deaktiviert, Schnellstart unwirksam / Hibernation disabled, Fast Startup has no effect'
    }
    $verificationFailed = $attempted -and -not $state.Compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $state.Compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'FastStartup'; Current = $state.Text; Desired = $desiredText
        Compliant = $state.Compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($differences)
        HibernateEnabled = $hibernate; Notes = @($notes)
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
