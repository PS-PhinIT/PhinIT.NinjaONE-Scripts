#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prueft eingebaute lokale Konten (Administrator -500, Gast -501, DefaultAccount -503) per SID.
    EN: Checks built-in local accounts (Administrator -500, Guest -501, DefaultAccount -503) by SID.
.DESCRIPTION
    DE: Liest lokale Konten mit Get-LocalUser und erkennt die eingebauten Konten sprachunabhaengig ueber
        das SID-Suffix (S-1-5-21-...-500/-501/-503/-504). Gemeldet werden Name, Aktiviert, letzte Anmeldung
        und Kennwortalter-Datum; keine Kennwoerter. RenamedFromDefault ist eine Heuristik gegen bekannte
        Standardnamen (Administrator, Administrateur, Administrador, Amministratore, Administratör,
        Järjestelmänvalvoja, Rendszergazda bzw. Guest, Gast, Invité, Invitado, Ospite, Vieras, Gäst).
        Auf Domaenencontrollern ist Get-LocalUser nicht verfuegbar (Exit 1).
    EN: Reads local accounts via Get-LocalUser and identifies the built-in accounts language-independently
        by SID suffix (S-1-5-21-...-500/-501/-503/-504). Reports name, enabled state, last logon and
        password-last-set date; no passwords. RenamedFromDefault is a heuristic against known default names
        (Administrator, Administrateur, Administrador, Amministratore, Administratör, Järjestelmänvalvoja,
        Rendszergazda resp. Guest, Gast, Invité, Invitado, Ospite, Vieras, Gäst).
        Get-LocalUser is not available on domain controllers (exit 1).
.PARAMETER AllowAdminEnabled
    DE: NinjaOne Checkbox/Text securityAllowBuiltinAdminEnabled, true/false/1/0; Standard false
        (aktivierter eingebauter Administrator ist Befund).
    EN: NinjaOne checkbox/text securityAllowBuiltinAdminEnabled, true/false/1/0; default false
        (enabled built-in Administrator is a finding).
.PARAMETER RequireAdminRenamed
    DE: NinjaOne Checkbox/Text securityRequireBuiltinAdminRenamed, true/false/1/0; Standard false.
    EN: NinjaOne checkbox/text securityRequireBuiltinAdminRenamed, true/false/1/0; default false.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Feld (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: optional MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkBuiltinAccounts.ps1
    DE: Exit 2, wenn Gast oder eingebauter Administrator aktiviert ist.
    EN: Exit 2 if Guest or the built-in Administrator is enabled.
.EXAMPLE
    .\checkBuiltinAccounts.ps1 -AllowAdminEnabled true -RequireAdminRenamed true -CustomField builtinAccounts
    DE: Aktivierter (z. B. LAPS-verwalteter) Administrator erlaubt, muss aber umbenannt sein; JSON in builtinAccounts.
    EN: Enabled (e.g. LAPS-managed) Administrator allowed but must be renamed; JSON to builtinAccounts.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Parameter vor Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = Gast aktiviert, eingebauter Administrator
        aktiviert (wenn nicht erlaubt) oder nicht umbenannt (wenn verlangt).
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = Guest enabled, built-in Administrator enabled
        (unless allowed) or not renamed (if required).
#>
[CmdletBinding()]
param(
    [string]$AllowAdminEnabled = $env:securityAllowBuiltinAdminEnabled,
    [string]$RequireAdminRenamed = $env:securityRequireBuiltinAdminRenamed,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-BoolSetting {
    param([string]$Value, [bool]$Default, [string]$Name)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    if ($text -in @('true', '1')) { return $true }
    if ($text -in @('false', '0')) { return $false }
    throw ('{0}: true/false erforderlich / required.' -f $Name)
}
try {
    $allowAdmin = Get-BoolSetting $AllowAdminEnabled $false 'securityAllowBuiltinAdminEnabled'
    $requireRenamed = Get-BoolSetting $RequireAdminRenamed $false 'securityRequireBuiltinAdminRenamed'
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungueltiges resultCustomField / Invalid resultCustomField.' }
    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) { throw 'Get-LocalUser fehlt / unavailable.' }

    $defaults = @{
        '500' = @('Administrator', 'Administrateur', 'Administrador', 'Amministratore', 'Administratör', 'Järjestelmänvalvoja', 'Rendszergazda')
        '501' = @('Guest', 'Gast', 'Invité', 'Invitado', 'Ospite', 'Vieras', 'Gäst')
        '503' = @('DefaultAccount'); '504' = @('WDAGUtilityAccount')
    }
    $roles = @{ '500' = 'Administrator'; '501' = 'Guest'; '503' = 'DefaultAccount'; '504' = 'WDAGUtilityAccount' }
    $users = @(Get-LocalUser -ErrorAction Stop)
    $accounts = [ordered]@{}
    foreach ($rid in @('500', '501', '503', '504')) {
        $user = $users | Where-Object { [string]$_.SID -match ('^S-1-5-21-\d+-\d+-\d+-{0}$' -f $rid) } | Select-Object -First 1
        if ($null -eq $user) { $accounts[$roles[$rid]] = $null; continue }
        $accounts[$roles[$rid]] = [pscustomobject]@{
            Name = [string]$user.Name; Sid = [string]$user.SID; Enabled = [bool]$user.Enabled
            RenamedFromDefault = [string]$user.Name -notin $defaults[$rid]
            LastLogonUtc = $(if ($user.LastLogon) { ([datetime]$user.LastLogon).ToUniversalTime().ToString('o') } else { $null })
            PasswordLastSetUtc = $(if ($user.PasswordLastSet) { ([datetime]$user.PasswordLastSet).ToUniversalTime().ToString('o') } else { $null })
        }
    }
    if ($null -eq $accounts['Administrator'] -and $null -eq $accounts['Guest']) { throw 'Keine eingebauten Konten gefunden / No built-in accounts found.' }
    $findings = New-Object System.Collections.Generic.List[string]
    if ($accounts['Guest'] -and $accounts['Guest'].Enabled) { $findings.Add('GuestEnabled') }
    if ($accounts['Administrator']) {
        if ($accounts['Administrator'].Enabled -and -not $allowAdmin) { $findings.Add('BuiltinAdministratorEnabled') }
        if ($requireRenamed -and -not $accounts['Administrator'].RenamedFromDefault) { $findings.Add('BuiltinAdministratorNotRenamed') }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        AllowAdminEnabled = $allowAdmin; RequireAdminRenamed = $requireRenamed; Accounts = $accounts; Findings = @($findings)
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
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
