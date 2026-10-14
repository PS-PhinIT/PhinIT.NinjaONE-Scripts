#Requires -Version 5.1

<#
.SYNOPSIS
DE: Prueft die Einstellungen der Benutzerkontensteuerung (UAC), ohne etwas zu aendern.
EN: Audits User Account Control (UAC) settings without changing anything.
.DESCRIPTION
DE: Liest HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System und dekodiert
    EnableLUA, ConsentPromptBehaviorAdmin, ConsentPromptBehaviorUser, PromptOnSecureDesktop
    und FilterAdministratorToken. Fehlt ein Wert, meldet das Skript State NotConfigured und
    den wirksamen Windows-Standard: EnableLUA 1 (UAC an), ConsentPromptBehaviorAdmin 5
    (Zustimmung fuer Nicht-Windows-Binaries), ConsentPromptBehaviorUser 3 (Anmeldedaten),
    PromptOnSecureDesktop 1 (sicherer Desktop), FilterAdministratorToken 0 (kein
    Admin-Genehmigungsmodus fuer das integrierte Administratorkonto).
    Nicht numerische Werte erscheinen als State Invalid und gelten als Warnung.
EN: Reads HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System and decodes
    EnableLUA, ConsentPromptBehaviorAdmin, ConsentPromptBehaviorUser, PromptOnSecureDesktop
    and FilterAdministratorToken. If a value is absent, the script reports State NotConfigured
    and the effective Windows default: EnableLUA 1 (UAC on), ConsentPromptBehaviorAdmin 5
    (consent for non-Windows binaries), ConsentPromptBehaviorUser 3 (prompt for credentials),
    PromptOnSecureDesktop 1 (secure desktop), FilterAdministratorToken 0 (no Admin Approval
    Mode for the built-in Administrator). Non-numeric values are reported as State Invalid
    and count as a warning.
DE: Exit 2 = UAC deaktiviert (EnableLUA 0), Admin-Prompt 0 (ohne Nachfrage erhoehen),
    PromptOnSecureDesktop 0 oder ungueltiger Wert. Neustart noetig, bis EnableLUA wirkt.
EN: Exit 2 = UAC disabled (EnableLUA 0), admin prompt 0 (elevate without prompting),
    PromptOnSecureDesktop 0 or invalid value. EnableLUA changes need a reboot to take effect.
.PARAMETER CustomField
DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld fuer den JSON-Bericht (max. 4000 Zeichen); Standard leer.
EN: NinjaOne Text resultCustomField: optional MultiLine field for the JSON report (max. 4000 characters); default empty.
.EXAMPLE
.\checkUacSettings.ps1
DE: Gibt die dekodierten UAC-Einstellungen als JSON aus.
EN: Outputs the decoded UAC settings as JSON.
.EXAMPLE
.\checkUacSettings.ps1 -CustomField uacStatus
DE: Schreibt den JSON-Bericht zusaetzlich in das MultiLine-Feld uacStatus.
EN: Additionally writes the JSON report to the MultiLine field uacStatus.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Explizite Parameter vor Variablen.
    Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = unsichere UAC-Konfiguration.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Explicit parameters override variables.
    Exit 0 = OK, 1 = input/query/write error, 2 = insecure UAC configuration.
#>
[CmdletBinding()]
param([string]$CustomField = $env:resultCustomField)

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
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges CustomField / Invalid CustomField.' }

    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $onOff = @{ 0 = 'Disabled'; 1 = 'Enabled' }
    $admin = @{
        0 = 'ElevateWithoutPrompting'; 1 = 'PromptForCredentialsOnSecureDesktop'; 2 = 'PromptForConsentOnSecureDesktop'
        3 = 'PromptForCredentials'; 4 = 'PromptForConsent'; 5 = 'PromptForConsentForNonWindowsBinaries'
    }
    $user = @{ 0 = 'AutomaticallyDenyElevation'; 1 = 'PromptForCredentialsOnSecureDesktop'; 3 = 'PromptForCredentials' }
    $lua = Get-RegistrySetting -Path $path -Name 'EnableLUA' -DefaultValue 1 -Map $onOff
    $adminPrompt = Get-RegistrySetting -Path $path -Name 'ConsentPromptBehaviorAdmin' -DefaultValue 5 -Map $admin
    $userPrompt = Get-RegistrySetting -Path $path -Name 'ConsentPromptBehaviorUser' -DefaultValue 3 -Map $user
    $secure = Get-RegistrySetting -Path $path -Name 'PromptOnSecureDesktop' -DefaultValue 1 -Map $onOff
    $filter = Get-RegistrySetting -Path $path -Name 'FilterAdministratorToken' -DefaultValue 0 -Map $onOff
    $settings = @($lua, $adminPrompt, $userPrompt, $secure, $filter)

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($setting in $settings) { if ($setting.State -eq 'Invalid') { $findings.Add($setting.Name + 'Invalid') } }
    if ($lua.EffectiveValue -eq 0) { $findings.Add('UacDisabled') }
    if ($adminPrompt.EffectiveValue -eq 0) { $findings.Add('AdminElevationWithoutPrompt') }
    if ($secure.EffectiveValue -eq 0) { $findings.Add('SecureDesktopDisabled') }

    $status = 'OK'
    if ($findings.Count -gt 0) { $status = 'Warning' }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Status = $status; UacEnabled = ($lua.EffectiveValue -ne 0 -and $null -ne $lua.EffectiveValue)
        RegistryPath = $path; Settings = $settings; Findings = @($findings)
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
