#Requires -Version 5.1

<#
.SYNOPSIS
DE: Vergleicht lokale Administratoren mit einer zwingend angegebenen SID-Allowlist.
EN: Compares local Administrators membership against a required identity allowlist.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer; leere Allowlist ist Fehler. EN: NinjaOne literal null is empty; an empty allowlist is an error.
DE: SYSTEM, 64-Bit Windows PowerShell; nur direkte Mitgliedschaft, keine Gruppenaufloesung.
EN: SYSTEM, 64-bit Windows PowerShell; direct membership only, no nested group expansion.
DE: AllowedIdentities / securityAllowedAdminIdentities: durch Komma, Semikolon oder Zeilen getrennte
    SIDs oder qualifizierte DOMAIN\Name / COMPUTER\Name / UPN. Keine Platzhalter/unkwalifizierten Namen.
EN: AllowedIdentities / securityAllowedAdminIdentities: comma, semicolon or newline separated
    SIDs or qualified DOMAIN\Name / COMPUTER\Name / UPN. No wildcards/unqualified names.
DE: Kontonamen muessen in SIDs aufloesbar sein. Unaufloesbare Namen/fehlende Liste sind Fehler.
EN: Account names must resolve to SIDs. Unresolvable names/missing list are errors.
DE: SID-Vergleich vermeidet lokalisierte Gruppennamen. Auch SYSTEM muss explizit erlaubt werden.
EN: SID comparison avoids localized group names. Even SYSTEM must be explicitly allowed.
DE: Erlaubte Domaingruppen koennen indirekt weitere Administratoren enthalten; separat pruefen.
EN: Allowed domain groups may contain indirect administrators; audit separately.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang; keine Konten/Gruppen werden geaendert.
EN: Explicit parameters take precedence; no accounts/groups are changed.
DE/EN: Exit 0 = OK, 1 = Fehler/error, 2 = unerlaubte Mitglieder/unauthorized members.
.PARAMETER AllowedIdentities
DE: Erforderliche SID-/Kontenliste; securityAllowedAdminIdentities; kein Standard.
EN: Required SID/account list; securityAllowedAdminIdentities; no default.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
.EXAMPLE
.\detectUnauthorizedLocalAdmins.ps1 -AllowedIdentities 'S-1-5-18;S-1-5-21-1004336348-1177238915-682003330-500'
DE: Erlaubt nur SYSTEM und das angegebene lokale Administratorkonto (SID).
EN: Allows only SYSTEM and the given local Administrator account (SID).
.EXAMPLE
.\detectUnauthorizedLocalAdmins.ps1 -AllowedIdentities 'S-1-5-18;CONTOSO\Domain Admins;CONTOSO\IT-Support' -CustomField localAdminAudit
DE: SID und qualifizierte Domaingruppen erlauben; Exit 2 bei weiteren Mitgliedern; JSON in localAdminAudit.
EN: Allows a SID and qualified domain groups; exit 2 for other members; JSON to localAdminAudit.
#>
[CmdletBinding()]
param([string]$AllowedIdentities = '', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Fehlende Allowlist niemals durch Standardkonten ersetzen. EN: Never invent default allowed accounts.
    if (-not $PSBoundParameters.ContainsKey('AllowedIdentities')) { $AllowedIdentities = $env:securityAllowedAdminIdentities }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $CustomField = ([string]$CustomField).Trim()
    $AllowedIdentities = ([string]$AllowedIdentities).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($AllowedIdentities -ieq 'null') { $AllowedIdentities = '' }
    if (-not $AllowedIdentities -or $AllowedIdentities.Length -gt 16000) { throw 'Gueltige AllowedIdentities-Liste erforderlich / Valid AllowedIdentities list required.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $allowedSids = @{}
    foreach ($entry in ($AllowedIdentities -split '[,;\r\n]+')) {
        $identity = $entry.Trim()
        if (-not $identity -or $identity -match '[*?\[\]]') { throw 'Leere Identitaet/Platzhalter nicht erlaubt / Empty identity/wildcard not allowed.' }
        if ($identity -match '^S-\d+(?:-\d+)+$') {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($identity)
        } elseif ($identity -match '^[^\\\s]+\\[^\\]+$' -or $identity -match '^[^@\s]+@[^@\s]+$') {
            $account = New-Object System.Security.Principal.NTAccount($identity)
            $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        } else { throw 'Qualifizierter Kontoname oder SID erforderlich / Qualified account name or SID required.' }
        $allowedSids[$sid.Value] = $true
    }
    if (-not $allowedSids.Count) { throw 'Leere SID-Liste / Empty SID list.' }
    $null = Get-Command Get-LocalGroupMember -ErrorAction Stop
    $group = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
    $members = @(Get-LocalGroupMember -Group $group -ErrorAction Stop)
    $rows = @($members | ForEach-Object {
        if ($null -eq $_.SID -or -not $_.SID.Value) { throw 'Mitglied ohne SID / Member without SID.' }
        $authorized = $allowedSids.ContainsKey($_.SID.Value)
        [pscustomobject]@{ Name = [string]$_.Name; SID = $_.SID.Value; ObjectClass = [string]$_.ObjectClass; Authorized = $authorized }
    })
    $warning = @($rows | Where-Object { -not $_.Authorized }).Count -gt 0
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{ GroupSID = 'S-1-5-32-544'; DirectMembers = $rows }) -Depth 4 -Compress
    if ($text.Length -gt 4000) { throw 'Ergebnis groesser als 4000 Zeichen / Result exceeds 4000 characters.' }
    Write-Output $text
    if ($CustomField) {
        $null = Get-Command Ninja-Property-Set -ErrorAction Stop
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $text -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'CustomField konnte nicht geschrieben werden / Field write failed.' }
    }
    if ($warning) { exit 2 }
    exit 0
} catch {
    Write-Error ("Administratorpruefung fehlgeschlagen / Administrator audit failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}