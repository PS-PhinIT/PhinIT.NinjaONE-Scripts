#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft einen einzelnen Registrywert unter HKLM und setzt oder entfernt ihn optional (eingeschränkte Pfade).
    EN: Audits a single registry value under HKLM and optionally sets or removes it (restricted paths).
.DESCRIPTION
    DE: Erlaubt sind nur Pfade unter HKLM:\SOFTWARE\ oder HKLM:\SYSTEM\CurrentControlSet\ (max. 255 Zeichen, keine
        Wildcards * ? [ ], kein '..', keine leeren Pfadteile, keine Steuerzeichen). Abgelehnt werden zusätzlich
        HKLM:\SYSTEM\CurrentControlSet\Control\Lsa (und darunter), HKLM:\SYSTEM\CurrentControlSet\Services\NinjaRMMAgent*
        sowie jeder Pfadteil, der mit NinjaRMM beginnt (Schutz des NinjaOne-Agents). HKLM:\SECURITY und HKLM:\SAM sind
        damit ausgeschlossen. Der Wert wird mit Get-Item gelesen (Typ über GetValueKind, ExpandString ohne Auflösung)
        und mit Typ und Inhalt verglichen. Action Set schreibt mit New-ItemProperty -PropertyType <Typ> -Force (fehlender
        Schlüssel wird angelegt), Action Remove entfernt den Wert (fehlender Wert/Schlüssel = konform). Typen: String,
        ExpandString, DWord (0-4294967295, dezimal oder 0x-Hex; wird korrekt als vorzeichenbehafteter Int32 gespeichert),
        QWord (0-18446744073709551615, dezimal oder 0x-Hex), MultiString (Trennzeichen |). Werte max. 4000 Zeichen, keine
        Steuerzeichen. Im Bericht werden alter und neuer Wert/Typ auf 200 Zeichen gekürzt; enthält Pfad oder Name
        password, secret, token oder key (ohne Groß-/Kleinschreibung), wird '<redacted>' ausgegeben. Ohne Opt-in
        (configRegistryAllow=true) wird nichts geändert; jede Änderung läuft über ShouldProcess und wird zurückgelesen.
    EN: Only paths under HKLM:\SOFTWARE\ or HKLM:\SYSTEM\CurrentControlSet\ are allowed (max. 255 characters, no
        wildcards * ? [ ], no '..', no empty path parts, no control characters). Additionally rejected:
        HKLM:\SYSTEM\CurrentControlSet\Control\Lsa (and below), HKLM:\SYSTEM\CurrentControlSet\Services\NinjaRMMAgent*
        and every path part starting with NinjaRMM (protects the NinjaOne agent). HKLM:\SECURITY and HKLM:\SAM are thus
        excluded. The value is read with Get-Item (kind via GetValueKind, ExpandString unexpanded) and compared by kind
        and data. Action Set writes with New-ItemProperty -PropertyType <type> -Force (a missing key is created), Action
        Remove deletes the value (missing value/key = compliant). Types: String, ExpandString, DWord (0-4294967295,
        decimal or 0x hex; stored correctly as signed Int32), QWord (0-18446744073709551615, decimal or 0x hex),
        MultiString (separator |). Values max. 4000 characters, no control characters. The report truncates old and new
        value/type to 200 characters; if path or name contains password, secret, token or key (case-insensitive),
        '<redacted>' is printed. Without opt-in (configRegistryAllow=true) nothing is changed; every change runs inside
        ShouldProcess and is read back.
.PARAMETER Path
    DE: NinjaOne Text configRegistryPath; erforderlich; z. B. HKLM:\SOFTWARE\Contoso\App.
    EN: NinjaOne text configRegistryPath; required; e.g. HKLM:\SOFTWARE\Contoso\App.
.PARAMETER Name
    DE: NinjaOne Text configRegistryName; erforderlich; 1-255 Zeichen, keine Steuerzeichen/Wildcards; '(Default)' wird nicht unterstützt.
    EN: NinjaOne text configRegistryName; required; 1-255 characters, no control characters/wildcards; '(Default)' is not supported.
.PARAMETER Type
    DE: NinjaOne Dropdown/Text configRegistryType: String, ExpandString, DWord, QWord, MultiString; erforderlich für Set.
    EN: NinjaOne drop-down/text configRegistryType: String, ExpandString, DWord, QWord, MultiString; required for Set.
.PARAMETER Value
    DE: NinjaOne Text configRegistryValue; Wert passend zum Typ (max. 4000 Zeichen); leer = leere Zeichenfolge bzw. leere Liste (nicht für DWord/QWord).
    EN: NinjaOne text configRegistryValue; value matching the type (max. 4000 characters); empty = empty string or empty list (not for DWord/QWord).
.PARAMETER Action
    DE: NinjaOne Dropdown/Text configRegistryAction: Set oder Remove; Standard Set.
    EN: NinjaOne drop-down/text configRegistryAction: Set or Remove; default Set.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configRegistryAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configRegistryAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setRegistryValue.ps1 -Path 'HKLM:\SOFTWARE\Contoso\App' -Name 'Mode' -Type DWord -Value 1
    DE: Nur Prüfung: Exit 2, wenn Mode nicht DWORD 1 ist.
    EN: Audit only: exit 2 if Mode is not DWORD 1.
.EXAMPLE
    .\setRegistryValue.ps1 -Path 'HKLM:\SOFTWARE\Contoso\App' -Name 'Servers' -Type MultiString -Value 'srv1|srv2' -Allow true -WhatIf
    DE: Simuliert das Schreiben eines REG_MULTI_SZ; nichts wird geändert (Exit 0).
    EN: Simulates writing a REG_MULTI_SZ; nothing is changed (exit 0).
.EXAMPLE
    .\setRegistryValue.ps1 -Path 'HKLM:\SOFTWARE\Contoso\App' -Name 'Legacy' -Action Remove -Allow true -CustomField registryReport
    DE: Entfernt den Wert Legacy und schreibt das JSON in registryReport.
    EN: Removes the value Legacy and writes the JSON to registryReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit (64-Bit-Registryansicht). Explizite Parameter haben Vorrang; leer/'null' = nicht gesetzt.
        Binärwerte und der Standardwert werden nicht unterstützt. Gruppenrichtlinien können Werte unter Policies überschreiben.
        Exit 0 = Sollzustand erfüllt, erfolgreich geändert oder -WhatIf mit Opt-in; 1 = Eingabe-, Lese-, Schreib- oder
        Verifikationsfehler bzw. gesperrter Pfad; 2 = Abweichung ohne Opt-in (Drift) bzw. Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit (64-bit registry view). Explicit parameters win; empty/'null' = not set.
        Binary values and the default value are not supported. Group Policy may overwrite values under Policies.
        Exit 0 = desired state met, changed successfully or -WhatIf with opt-in; 1 = input, read, write or verification
        error or blocked path; 2 = drift without opt-in or change declined via -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Path = $env:configRegistryPath,
    [string]$Name = $env:configRegistryName,
    [string]$Type = $env:configRegistryType,
    [string]$Value = $env:configRegistryValue,
    [string]$Action = $env:configRegistryAction,
    [string]$Allow = $env:configRegistryAllow,
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
function Get-RegistryEntry {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Exists = $false; Kind = $null; Data = $null } }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    $actualName = @($key.GetValueNames()) | Where-Object { $_ -eq $Name } | Select-Object -First 1
    if ($null -eq $actualName) { return [pscustomobject]@{ Exists = $false; Kind = $null; Data = $null } }
    $data = $key.GetValue($actualName, $null, 'DoNotExpandEnvironmentNames')
    $kind = [string]$key.GetValueKind($actualName)
    if ($kind -eq 'MultiString') { $data = @(if ($null -ne $data) { $data }) }
    elseif ($kind -eq 'DWord' -and $null -ne $data) { $data = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$data), 0) }
    elseif ($kind -eq 'QWord' -and $null -ne $data) { $data = [BitConverter]::ToUInt64([BitConverter]::GetBytes([long]$data), 0) }
    return [pscustomobject]@{ Exists = $true; Kind = $kind; Data = $data }
}
function Format-DisplayValue {
    param($Data, [string]$Kind, [bool]$Redact)
    if ($null -eq $Kind -or $Kind -eq '') { return $null }
    if ($Redact) { return '<redacted>' }
    $text = [string]$Data
    if ($Kind -eq 'MultiString') { $text = @($Data) -join '|' }
    elseif ($Kind -eq 'Binary') { $text = '<binary>' }
    if ($text.Length -gt 200) { $text = $text.Substring(0, 200) + '...' }
    return $text
}
try {
    $Path = Resolve-Setting $Path ''
    $Name = Resolve-Setting $Name ''
    $Type = Resolve-Setting $Type ''
    $Action = Resolve-Setting $Action 'Set'
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    if ($null -eq $Value -or $Value.Trim() -eq 'null') { $Value = '' }
    $Path = $Path.TrimEnd('\')
    if (-not $Path -or $Path.Length -gt 255 -or $Path -match '[\x00-\x1f\x7f*?\[\]]' -or $Path.Contains('..') -or $Path.Contains('\\')) {
        throw 'configRegistryPath ungültig (max. 255 Zeichen, keine Wildcards/Steuerzeichen/..) / invalid (max. 255 characters, no wildcards/control characters/..).'
    }
    if ($Path -notmatch '^HKLM:\\(SOFTWARE|SYSTEM\\CurrentControlSet)\\[^\\]') {
        throw 'configRegistryPath muss mit HKLM:\SOFTWARE\ oder HKLM:\SYSTEM\CurrentControlSet\ beginnen / must start with HKLM:\SOFTWARE\ or HKLM:\SYSTEM\CurrentControlSet\.'
    }
    if ($Path -match '^HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa(\\|$)' -or $Path -match '^HKLM:\\SYSTEM\\CurrentControlSet\\Services\\NinjaRMMAgent' -or
        $Path -match '\\NinjaRMM') {
        throw ('Geschützter Registrypfad / Protected registry path: {0}' -f $Path)
    }
    if (-not $Name -or $Name.Length -gt 255 -or $Name -match '[\x00-\x1f\x7f*?\[\]]' -or $Name -eq '(Default)') {
        throw 'configRegistryName ungültig (1-255 Zeichen, keine Steuerzeichen/Wildcards, nicht (Default)) / invalid (1-255 characters, no control characters/wildcards, not (Default)).'
    }
    $actionMatch = @('Set', 'Remove') | Where-Object { $_ -eq $Action } | Select-Object -First 1
    if (-not $actionMatch) { throw 'configRegistryAction: Set oder/or Remove.' }
    $Action = $actionMatch
    $allowed = ConvertTo-BooleanSetting $Allow 'configRegistryAllow'
    $desiredData = $null
    $writeData = $null
    if ($Action -eq 'Set') {
        $typeMatch = @('String', 'ExpandString', 'DWord', 'QWord', 'MultiString') | Where-Object { $_ -eq $Type } | Select-Object -First 1
        if (-not $typeMatch) { throw 'configRegistryType: String, ExpandString, DWord, QWord oder/or MultiString.' }
        $Type = $typeMatch
        if ($Value.Length -gt 4000 -or $Value -match '[\x00-\x1f\x7f]') { throw 'configRegistryValue: max. 4000 Zeichen, keine Steuerzeichen / max. 4000 characters, no control characters.' }
        $text = $Value.Trim()
        switch ($Type) {
            'DWord' {
                $number = [uint32]0
                if ($text -match '^0x[0-9a-fA-F]{1,8}$') { $number = [Convert]::ToUInt32($text.Substring(2), 16) }
                elseif (-not ($text -match '^\d{1,10}$' -and [uint32]::TryParse($text, [ref]$number))) { throw 'configRegistryValue: DWord 0-4294967295 erforderlich / required.' }
                $desiredData = $number
                $writeData = [BitConverter]::ToInt32([BitConverter]::GetBytes($number), 0)
            }
            'QWord' {
                $number = [uint64]0
                if ($text -match '^0x[0-9a-fA-F]{1,16}$') { $number = [Convert]::ToUInt64($text.Substring(2), 16) }
                elseif (-not ($text -match '^\d{1,20}$' -and [uint64]::TryParse($text, [ref]$number))) { throw 'configRegistryValue: QWord 0-18446744073709551615 erforderlich / required.' }
                $desiredData = $number
                $writeData = [BitConverter]::ToInt64([BitConverter]::GetBytes($number), 0)
            }
            'MultiString' {
                $parts = [string[]]@()
                if ($Value.Length -gt 0) { $parts = [string[]]$Value.Split('|') }
                $desiredData = $parts
                $writeData = $parts
            }
            default { $desiredData = $Value; $writeData = $Value }
        }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $redact = ($Path + '\' + $Name) -match 'password|secret|token|key'
    $test = {
        param($Entry)
        if ($Action -eq 'Remove') { return -not $Entry.Exists }
        if (-not $Entry.Exists -or $Entry.Kind -ne $Type) { return $false }
        if ($Type -eq 'MultiString') {
            $currentItems = @($Entry.Data)
            if ($currentItems.Count -ne $desiredData.Count) { return $false }
            for ($i = 0; $i -lt $currentItems.Count; $i++) { if ([string]$currentItems[$i] -cne $desiredData[$i]) { return $false } }
            return $true
        }
        if ($Type -in @('DWord', 'QWord')) { return $Entry.Data -eq $desiredData }
        return [string]$Entry.Data -ceq $desiredData
    }
    $before = Get-RegistryEntry -Path $Path -Name $Name
    $entry = $before
    $compliant = [bool](& $test $entry)
    $attempted = $false
    $changed = $false
    if ($allowed -and -not $compliant) {
        if ($Action -eq 'Set') {
            if ($PSCmdlet.ShouldProcess("$Path\$Name", ('Registrywert setzen ({0}) / Set registry value ({0})' -f $Type))) {
                $attempted = $true
                if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
                $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $writeData -PropertyType $Type -Force -ErrorAction Stop
                $changed = $true
            }
        }
        elseif ($PSCmdlet.ShouldProcess("$Path\$Name", 'Registrywert entfernen / Remove registry value')) {
            $attempted = $true
            Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            $changed = $true
        }
        if ($attempted) {
            $entry = Get-RegistryEntry -Path $Path -Name $Name
            $compliant = [bool](& $test $entry)
        }
    }
    $verificationFailed = $attempted -and -not $compliant
    $exitCode = 0
    if ($verificationFailed) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $desiredDisplay = [ordered]@{ Action = $Action; Type = $null; Value = $null }
    if ($Action -eq 'Set') { $desiredDisplay.Type = $Type; $desiredDisplay.Value = Format-DisplayValue -Data $desiredData -Kind $Type -Redact $redact }
    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; Setting = 'RegistryValue'; Path = $Path; Name = $Name
        Previous = [ordered]@{ Exists = $before.Exists; Type = $before.Kind; Value = (Format-DisplayValue -Data $before.Data -Kind $before.Kind -Redact $redact) }
        Current = [ordered]@{ Exists = $entry.Exists; Type = $entry.Kind; Value = (Format-DisplayValue -Data $entry.Data -Kind $entry.Kind -Redact $redact) }
        Desired = $desiredDisplay; Compliant = $compliant; Changed = $changed; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference
        VerificationFailed = $verificationFailed; Redacted = [bool]$redact
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
