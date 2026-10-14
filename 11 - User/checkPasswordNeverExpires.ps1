#Requires -Version 5.1

<#
.SYNOPSIS
DE: Lokale Konten mit nie ablaufendem/nicht erforderlichem Kennwort finden. EN: Find local accounts with non-expiring or not-required passwords.
.DESCRIPTION
DE: Prueft aktivierte lokale Konten (Get-LocalUser): PasswordExpires leer (laeuft nie ab) und/oder
PasswordRequired false (Kennwort nicht erforderlich). Optionale Ausnahmeliste exakter Kontennamen.
Nur lesend; keine Kennwoerter, SIDs oder Beschreibungen.
EN: Checks enabled local accounts (Get-LocalUser): PasswordExpires empty (never expires) and/or
PasswordRequired false (password not required). Optional allowlist of exact account names.
Read-only; no passwords, SIDs or descriptions.
DE: Hinweis: Ist die maximale Kennwortgueltigkeit der Richtlinie 0 (unbegrenzt), ist PasswordExpires
fuer alle Konten leer. Benoetigt Get-LocalUser (Windows 10/Server 2016+); keine lokale SAM auf DCs.
EN: Caveat: if the policy maximum password age is 0 (unlimited), PasswordExpires is empty for all
accounts. Requires Get-LocalUser (Windows 10/Server 2016+); no local SAM on domain controllers.
.PARAMETER CheckMode
DE: NinjaOne userPasswordCheckMode (Auswahl), Both/NeverExpires/NotRequired; Standard Both.
EN: NinjaOne userPasswordCheckMode (drop-down), Both/NeverExpires/NotRequired; default Both.
.PARAMETER Allowlist
DE: NinjaOne userPasswordAllowlist (Text), kommagetrennte exakte lokale Kontennamen (max. 50, je 1..20 Zeichen, ohne " / \ [ ] : ; | = , + * ? < >); Standard leer.
EN: NinjaOne userPasswordAllowlist (text), comma-separated exact local account names (max 50, 1..20 characters each, without " / \ [ ] : ; | = , + * ? < >); default empty.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkPasswordNeverExpires.ps1
DE: Beide Pruefungen fuer alle aktivierten lokalen Konten. EN: Both checks for all enabled local accounts.
.EXAMPLE
.\checkPasswordNeverExpires.ps1 -CheckMode NeverExpires -Allowlist 'svcBackup,kiosk' -CustomField pwdNeverExpires
DE: Nur "laeuft nie ab", zwei Konten erlaubt; JSON in pwdNeverExpires. EN: Only "never expires", two accounts allowed; JSON to pwdNeverExpires.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = keine Befunde ausserhalb der Ausnahmeliste, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein nicht erlaubtes aktiviertes Konto mit Befund.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no findings outside the allowlist, 1 = input/query/write error, 2 = at least one non-allowlisted enabled account with a finding.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CheckMode = $env:userPasswordCheckMode,
    [string]$Allowlist = $env:userPasswordAllowlist,
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
    $CheckMode = Get-InputValue $CheckMode 'Both'
    if ($CheckMode -notin @('Both', 'NeverExpires', 'NotRequired')) { throw 'userPasswordCheckMode must be Both/NeverExpires/NotRequired / muss Both/NeverExpires/NotRequired sein.' }
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $Allowlist = Get-InputValue $Allowlist ''
    $allowed = @()
    if ($Allowlist) {
        $allowed = @($Allowlist.Split(',') | ForEach-Object { $_.Trim() })
        if ($allowed.Count -gt 50) { throw 'userPasswordAllowlist: max 50 names / maximal 50 Namen.' }
        foreach ($name in $allowed) {
            if ($name -notmatch '^[^\x00-\x1F"/\\\[\]:;|=,+*?<>]{1,20}$' -or $name -match '^[. ]+$') { throw 'Invalid userPasswordAllowlist entry / Ungueltiger Eintrag.' }
        }
    }
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) { throw 'Get-LocalUser unavailable / nicht verfuegbar.' }
    $checkExpiry = $CheckMode -in @('Both', 'NeverExpires')
    $checkRequired = $CheckMode -in @('Both', 'NotRequired')
    $users = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled })
    $findings = @(foreach ($user in $users) {
        $neverExpires = $checkExpiry -and ($null -eq $user.PasswordExpires)
        $notRequired = $checkRequired -and (-not $user.PasswordRequired)
        if ($neverExpires -or $notRequired) {
            # DE: -contains vergleicht ohne Gross-/Kleinschreibung wie die SAM. EN: -contains is case-insensitive like the SAM.
            [pscustomobject]@{
                name = [string]$user.Name; passwordNeverExpires = $neverExpires
                passwordNotRequired = $notRequired; allowlisted = ($allowed -contains [string]$user.Name)
            }
        }
    })
    $alerts = @($findings | Where-Object { -not $_.allowlisted })
    $sorted = @($findings | Sort-Object allowlisted, name)
    $report = [ordered]@{
        check = 'Local password policy flags / Lokale Kennwort-Flags'; mode = $CheckMode
        enabledUsers = $users.Count; allowlistCount = $allowed.Count; alertCount = $alerts.Count
        total = $sorted.Count; returned = 0; truncated = $false; records = $sorted
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($alerts.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
