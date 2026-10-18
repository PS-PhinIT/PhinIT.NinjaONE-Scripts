#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Updatekanal-Richtlinie von Microsoft 365 Apps und setzt sie optional (updatebranch).
    EN: Audits the Microsoft 365 Apps update channel policy and optionally sets it (updatebranch).
.DESCRIPTION
    DE: Verwaltet HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate, Wert updatebranch (REG_SZ).
        Channel (Namen wie in 02 - Updates/readOfficeUpdateChannel.ps1) wird auf den Richtlinienwert abgebildet:
        Current = Current, CurrentPreview = FirstReleaseCurrent, MonthlyEnterprise = MonthlyEnterprise,
        SemiAnnual = Deferred, SemiAnnualPreview = FirstReleaseDeferred, BetaChannel = InsiderFast.
        Zusätzlich wird der installierte Kanal aus HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration CDNBaseUrl
        (Kanal-GUID) gemeldet; ohne Klick-und-Los gilt ClickToRunInstalled=false, das Setzen der Richtlinie bleibt erlaubt
        (die Updateaufgabe wird dann nur mit Hinweis übersprungen).
        Konformität bezieht sich nur auf die Richtlinie; der installierte Kanal wechselt erst beim nächsten Update
        (ChannelChangePending). Ohne Opt-in (configOfficeAllow=true) wird nichts geändert. Mit Opt-in wird der Wert
        innerhalb von ShouldProcess geschrieben (fehlender Schlüssel wird angelegt) und erneut gelesen. Optional
        (configOfficeTriggerUpdate=true) wird nach einer Änderung bei installiertem Klick-und-Los die geplante Aufgabe
        \Microsoft\Office\Office Automatic Updates 2.0 mit Start-ScheduledTask gestartet; ein Fehler ist nur eine Warnung (Exit 2).
        Bericht: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, InstalledChannel.
    EN: Manages HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate, value updatebranch (REG_SZ).
        Channel (names as in 02 - Updates/readOfficeUpdateChannel.ps1) maps to the policy value:
        Current = Current, CurrentPreview = FirstReleaseCurrent, MonthlyEnterprise = MonthlyEnterprise,
        SemiAnnual = Deferred, SemiAnnualPreview = FirstReleaseDeferred, BetaChannel = InsiderFast.
        The installed channel from HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration CDNBaseUrl (channel GUID) is
        reported as well; without Click-to-Run ClickToRunInstalled=false is reported and setting the policy is still
        allowed (the update task is then skipped with a note only). Compliance refers to the policy only; the installed channel switches at the next update
        (ChannelChangePending). Without opt-in (configOfficeAllow=true) nothing is changed. With opt-in the value is
        written inside ShouldProcess (a missing key is created) and read back. Optionally (configOfficeTriggerUpdate=true)
        the scheduled task \Microsoft\Office\Office Automatic Updates 2.0 is started with Start-ScheduledTask after a
        change when Click-to-Run is installed; a failure is only a warning (exit 2).
        Report: Current, Desired, Compliant, Changed, Allowed, WhatIf, Differences, InstalledChannel.
.PARAMETER Channel
    DE: NinjaOne Dropdown/Text configOfficeChannel; erforderlich: Current, CurrentPreview, MonthlyEnterprise, SemiAnnual, SemiAnnualPreview, BetaChannel.
    EN: NinjaOne drop-down/text configOfficeChannel; required: Current, CurrentPreview, MonthlyEnterprise, SemiAnnual, SemiAnnualPreview, BetaChannel.
.PARAMETER TriggerUpdate
    DE: NinjaOne Checkbox/Text configOfficeTriggerUpdate; true/false; Standard false. Nach einer Änderung die Office-Updateaufgabe starten.
    EN: NinjaOne checkbox/text configOfficeTriggerUpdate; true/false; default false. Start the Office update task after a change.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configOfficeAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configOfficeAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setOfficeUpdateChannel.ps1 -Channel MonthlyEnterprise
    DE: Nur Prüfung: Exit 2, wenn updatebranch nicht MonthlyEnterprise ist.
    EN: Audit only: exit 2 if updatebranch is not MonthlyEnterprise.
.EXAMPLE
    .\setOfficeUpdateChannel.ps1 -Channel SemiAnnual -Allow true -WhatIf
    DE: Simuliert das Setzen von updatebranch=Deferred; nichts wird geändert (Exit 0).
    EN: Simulates setting updatebranch=Deferred; nothing is changed (exit 0).
.EXAMPLE
    .\setOfficeUpdateChannel.ps1 -Channel MonthlyEnterprise -Allow true -TriggerUpdate true -CustomField officeChannelReport
    DE: Setzt die Richtlinie, startet die Office-Updateaufgabe und schreibt das JSON in officeChannelReport.
    EN: Sets the policy, starts the Office update task and writes the JSON to officeChannelReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Cloud-Richtlinien (config.office.com), Domänen-GPO und Intune können den Kanal überschreiben. MSI-Office wird nicht unterstützt.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler; 2 = Abweichung ohne Opt-in (Drift), Änderung per -Confirm abgelehnt oder Updateaufgabe nicht startbar.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Explicit parameters win; empty/'null' = not set.
        Cloud policies (config.office.com), domain GPO and Intune may override the channel. MSI Office is not supported.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error; 2 = drift without opt-in, change declined via -Confirm or update task could not be started.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Channel = $env:configOfficeChannel,
    [string]$TriggerUpdate = $env:configOfficeTriggerUpdate,
    [string]$Allow = $env:configOfficeAllow,
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
    $branchValues = [ordered]@{
        Current = 'Current'; CurrentPreview = 'FirstReleaseCurrent'; MonthlyEnterprise = 'MonthlyEnterprise'
        SemiAnnual = 'Deferred'; SemiAnnualPreview = 'FirstReleaseDeferred'; BetaChannel = 'InsiderFast'
    }
    $channelGuids = [ordered]@{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'; '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'; '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'; '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'PerpetualVL2019'; '5030841d-c919-4594-8d2d-84ae4f96e58e' = 'PerpetualVL2021'
        '7983bac0-e531-40cf-be00-fd24fe66619c' = 'PerpetualVL2024'
    }
    $Channel = Resolve-Setting $Channel ''
    $TriggerUpdate = Resolve-Setting $TriggerUpdate 'false'
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    $channelName = @($branchValues.Keys) | Where-Object { $_ -eq $Channel } | Select-Object -First 1
    if (-not $channelName) { throw ('configOfficeChannel: ' + (@($branchValues.Keys) -join ', ') + ' erforderlich / required.') }
    $desiredBranch = $branchValues[$channelName]
    $trigger = ConvertTo-BooleanSetting $TriggerUpdate 'configOfficeTriggerUpdate'
    $allowed = ConvertTo-BooleanSetting $Allow 'configOfficeAllow'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate'
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $clickToRun = [bool](Test-Path -LiteralPath $configPath)
    $installedChannel = $null
    if ($clickToRun) {
        $cdn = [string](Get-RegistryValue -Path $configPath -Name 'CDNBaseUrl')
        if ($cdn) {
            $installedChannel = 'Custom'
            if ($cdn -match '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})') {
                $mapped = $channelGuids[$Matches[1].ToLowerInvariant()]
                if ($mapped) { $installedChannel = $mapped }
            }
        }
    }
    $current = Get-RegistryValue -Path $policyPath -Name 'updatebranch'
    $compliant = $current -is [string] -and $current -ceq $desiredBranch
    $currentText = [string]$current
    if ($currentText.Length -gt 200) { $currentText = $currentText.Substring(0, 200) + '...' }
    $differences = @()
    if (-not $compliant) { $differences += ('updatebranch: {0} -> {1}' -f $currentText, $desiredBranch) }
    $attempted = $false
    $changed = $false
    $warnings = @()
    $notes = @()
    if ($allowed -and -not $compliant) {
        if ($PSCmdlet.ShouldProcess("$policyPath\updatebranch", ('Office-Updatekanal setzen auf {0} / Set Office update channel to {0}' -f $desiredBranch))) {
            $attempted = $true
            Write-RegistryValue -Path $policyPath -Name 'updatebranch' -Value $desiredBranch -Type 'String'
            $changed = $true
            $current = Get-RegistryValue -Path $policyPath -Name 'updatebranch'
            $compliant = $current -is [string] -and $current -ceq $desiredBranch
            $currentText = [string]$current
            if ($currentText.Length -gt 200) { $currentText = $currentText.Substring(0, 200) + '...' }
        }
    }
    $taskStarted = $false
    if ($changed -and $compliant -and $trigger) {
        if (-not $clickToRun) { $notes += 'Klick-und-Los fehlt, Updateaufgabe übersprungen / Click-to-Run missing, update task skipped' }
        elseif ($PSCmdlet.ShouldProcess('\Microsoft\Office\Office Automatic Updates 2.0', 'Office-Updateaufgabe starten / Start Office update task')) {
            try {
                Start-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0' -ErrorAction Stop
                $taskStarted = $true
            }
            catch { $warnings += ('Updateaufgabe nicht gestartet / Update task not started: {0}' -f $_.Exception.Message) }
        }
    }
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }
    elseif ($warnings.Count -gt 0) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'OfficeUpdateChannel'; Current = $(if ($null -eq $current) { $null } else { $currentText }); Desired = $desiredBranch; DesiredChannel = $channelName
        Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Differences = @($differences); ClickToRunInstalled = $clickToRun
        InstalledChannel = $installedChannel; ChannelChangePending = [bool]($installedChannel -and $installedChannel -ne $channelName)
        TriggerUpdate = $trigger; UpdateTaskStarted = $taskStarted; Warnings = @($warnings); Notes = @($notes)
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
