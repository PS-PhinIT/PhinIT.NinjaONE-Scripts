#Requires -Version 5.1

<#
.SYNOPSIS
DE: Veraltete, nicht geladene Benutzerprofile melden (ohne Loeschung). EN: Report stale unloaded user profiles (no deletion).
.DESCRIPTION
DE: Liest Win32_UserProfile (Special = false, Loaded = false) und meldet nur Profile, deren
LastUseTime aelter als N Tage ist (optional auch unbekannte Zeiten), samt Hinweis, ob das Konto
noch aufloesbar ist (verwaistes Profil). Nur Profilordnername, keine SIDs/Pfade; KEINE Loeschung.
EN: Reads Win32_UserProfile (Special = false, Loaded = false) and reports only profiles whose
LastUseTime is older than N days (optionally also unknown times), including whether the account
still resolves (orphaned profile). Profile folder name only, no SIDs/paths; NO deletion.
DE: Abgrenzung: readLastLogonTimes listet Nutzungszeiten aller Profile; dieses Skript ist eine
fokussierte Alarmliste mit Verwaist-Erkennung. LastUseTime ist keine autoritative Anmeldezeit.
accountResolvable false kann auch bei nicht erreichbarem DC/Entra-Konto auftreten; null = unbekannt.
EN: Scope: readLastLogonTimes lists use times of all profiles; this script is a focused alert list
with orphan detection. LastUseTime is not an authoritative logon time. accountResolvable false may
also occur with an unreachable DC/Entra account; null = unknown.
.PARAMETER StaleDays
DE: NinjaOne userStaleProfileDays (Integer), 1..3650; Standard 90.
EN: NinjaOne userStaleProfileDays (integer), 1..3650; default 90.
.PARAMETER IncludeUnknown
DE: NinjaOne userStaleIncludeUnknown (Text/Checkbox), true/false/1/0; Standard false. true = Profile ohne LastUseTime gelten als veraltet.
EN: NinjaOne userStaleIncludeUnknown (text/checkbox), true/false/1/0; default false. true = profiles without LastUseTime count as stale.
.PARAMETER MaxRecords
DE: NinjaOne userMaxRecords (Integer), 1..100; Standard 25.
EN: NinjaOne userMaxRecords (integer), 1..100; default 25.
.PARAMETER CustomField
DE: NinjaOne resultCustomField (Text): MultiLine-Feld, Name [A-Za-z][A-Za-z0-9_]{0,99}; leer = kein Feld; -WhatIf unterdrueckt Schreiben.
EN: NinjaOne resultCustomField (text): MultiLine field, name [A-Za-z][A-Za-z0-9_]{0,99}; blank = no field; -WhatIf skips writing.
.EXAMPLE
.\checkStaleProfiles.ps1
DE: Exit 2 fuer ungeladene Profile, 90 Tage oder laenger ungenutzt. EN: Exit 2 for unloaded profiles unused for 90 days or more.
.EXAMPLE
.\checkStaleProfiles.ps1 -StaleDays 180 -IncludeUnknown true -CustomField staleProfiles
DE: Grenze 180 Tage, unbekannte Zeiten zaehlen; JSON in staleProfiles. EN: 180-day limit, unknown times count; JSON to staleProfiles.
.NOTES
DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter vor Variablen. Maximal 4000 Zeichen (Liste wird gekuerzt).
Exit 0 = keine veralteten Profile, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = mindestens ein veraltetes Profil.
EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. At most 4000 characters (list is truncated).
Exit 0 = no stale profiles, 1 = input/query/write error, 2 = at least one stale profile.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StaleDays = $env:userStaleProfileDays,
    [string]$IncludeUnknown = $env:userStaleIncludeUnknown,
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
function Test-AccountResolvable {
    param([string]$Sid)
    try {
        $null = (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid).Translate([System.Security.Principal.NTAccount])
        return $true
    } catch {
        $exception = $_.Exception
        while ($exception) {
            if ($exception -is [System.Security.Principal.IdentityNotMappedException]) { return $false }
            $exception = $exception.InnerException
        }
        return $null
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
    $days = ConvertTo-BoundedInt -Value (Get-InputValue $StaleDays '90') -Name 'userStaleProfileDays' -Minimum 1 -Maximum 3650
    $limit = ConvertTo-BoundedInt -Value (Get-InputValue $MaxRecords '25') -Name 'userMaxRecords' -Minimum 1 -Maximum 100
    $IncludeUnknown = Get-InputValue $IncludeUnknown 'false'
    if ($IncludeUnknown -notin @('true', 'false', '1', '0')) { throw 'userStaleIncludeUnknown must be true/false/1/0 / muss true/false/1/0 sein.' }
    $countUnknown = $IncludeUnknown -in @('true', '1')
    $CustomField = Get-InputValue $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Invalid custom field name / Ungueltiger Feldname.' }
    $now = [DateTime]::UtcNow
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and -not $_.Loaded })
    $unknownCount = 0
    $stale = @(foreach ($userProfile in $profiles) {
        $age = $null
        $lastText = $null
        if ($userProfile.LastUseTime -is [DateTime]) {
            $last = $userProfile.LastUseTime.ToUniversalTime()
            $lastText = $last.ToString('o')
            $age = [int][Math]::Floor(($now - $last).TotalDays)
        } else { $unknownCount++ }
        if (($null -ne $age -and $age -ge $days) -or ($null -eq $age -and $countUnknown)) {
            [pscustomobject]@{
                profileFolder = ((([string]$userProfile.LocalPath).TrimEnd('\', '/') -split '[\\/]')[-1])
                lastUseUtc = $lastText; ageDays = $age
                accountResolvable = (Test-AccountResolvable -Sid ([string]$userProfile.SID))
            }
        }
    })
    $sorted = @($stale | Sort-Object @{ Expression = { if ($null -eq $_.ageDays) { [int]::MaxValue } else { $_.ageDays } }; Descending = $true }, profileFolder)
    $report = [ordered]@{
        check = 'Stale unloaded profiles / Veraltete ungeladene Profile'; action = 'Report only / Nur Bericht'
        thresholdDays = $days; unknownCountedAsStale = $countUnknown; evaluatedProfiles = $profiles.Count
        unknownUseTime = $unknownCount
        orphanedCount = @($stale | Where-Object { $_.accountResolvable -eq $false }).Count
        total = $sorted.Count; returned = 0; truncated = $false; records = $sorted
    }
    Write-InventoryReport -Report $report -Limit $limit -Field $CustomField
    if ($sorted.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
