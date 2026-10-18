#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Ermittelt lokale Benutzerprofile, die seit N Tagen nicht genutzt wurden, und entfernt sie optional.
    EN: Finds local user profiles not used for N days and optionally removes them.
.DESCRIPTION
    DE: Liest Get-CimInstance Win32_UserProfile. Kandidaten: nur Benutzer-SIDs (S-1-5-21-* und S-1-12-1-*),
        LastUseTime älter als MinimumAgeDays. NIE entfernt werden: Special=true, Loaded=true, S-1-5-18/19/20,
        Profile angemeldeter Benutzer (Win32_ComputerSystem.UserName und Besitzer von explorer.exe), Profile,
        deren Ordnername (LocalPath) oder aufgelöster Kontoname (DOMÄNE\Name oder Name) in Exclude steht,
        das integrierte Administratorkonto (SID endet auf -500) sowie Profile ohne LastUseTime (außer
        IncludeUnknownAge=true). Hinweis: LastUseTime wird von Windows teils auch ohne Anmeldung aktualisiert.
        Entfernt werden höchstens MaxRemovals Profile (älteste zuerst, unbekanntes Alter zuerst); weitere
        Kandidaten werden nur gemeldet (Deferred). Vor dem Entfernen wird das Profil erneut abgefragt (Loaded).
        Entfernen per Remove-CimInstance löscht Profilordner UND Registry-Eintrag korrekt.
        Ohne Allow=true wird nur inventarisiert; jedes Entfernen läuft über ShouldProcess (-WhatIf).
        Bericht als JSON (max. 25 Kandidaten), optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Reads Get-CimInstance Win32_UserProfile. Candidates: only user SIDs (S-1-5-21-* and S-1-12-1-*) with a
        LastUseTime older than MinimumAgeDays. NEVER removed: Special=true, Loaded=true, S-1-5-18/19/20, profiles
        of logged-on users (Win32_ComputerSystem.UserName and owners of explorer.exe), profiles whose folder name
        (LocalPath) or resolved account name (DOMAIN\name or name) is in Exclude, the built-in Administrator
        (SID ending in -500) and profiles without LastUseTime (unless IncludeUnknownAge=true). Note: Windows
        sometimes updates LastUseTime without a logon.
        At most MaxRemovals profiles are removed (oldest first, unknown age first); further candidates are only
        reported (Deferred). Before removal the profile is queried again (Loaded).
        Removal via Remove-CimInstance deletes the profile folder AND the registry entry correctly.
        Without Allow=true the script only audits; every removal goes through ShouldProcess (-WhatIf).
        JSON report (max. 25 candidates), optionally written to a MultiLine field (max. 4000 characters,
        otherwise exit 1).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text cleanupProfilesAllow; true/false; Standard false. Nur true entfernt Profile.
    EN: NinjaOne checkbox/text cleanupProfilesAllow; true/false; default false. Only true removes profiles.
.PARAMETER MinimumAgeDays
    DE: NinjaOne Text cleanupProfilesMinimumAgeDays; ganze Zahl 30-3650; Standard 90.
    EN: NinjaOne text cleanupProfilesMinimumAgeDays; integer 30-3650; default 90.
.PARAMETER Exclude
    DE: NinjaOne Text cleanupProfilesExclude; kommagetrennte Benutzer- oder Ordnernamen (max. 50, je 1-104 Zeichen,
        keine Wildcards/Steuerzeichen); Standard leer.
    EN: NinjaOne text cleanupProfilesExclude; comma-separated user or folder names (max. 50, each 1-104 characters,
        no wildcards/control characters); default empty.
.PARAMETER MaxRemovals
    DE: NinjaOne Text cleanupProfilesMaxRemovals; ganze Zahl 1-50; Standard 5. Weitere Kandidaten nur melden.
    EN: NinjaOne text cleanupProfilesMaxRemovals; integer 1-50; default 5. Further candidates are only reported.
.PARAMETER IncludeUnknownAge
    DE: NinjaOne Checkbox/Text cleanupProfilesIncludeUnknownAge; true/false; Standard false. true behandelt Profile
        ohne LastUseTime als Kandidaten.
    EN: NinjaOne checkbox/text cleanupProfilesIncludeUnknownAge; true/false; default false. true treats profiles
        without LastUseTime as candidates.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\removeStaleUserProfiles.ps1 -MinimumAgeDays 180
    DE: Nur Inventur: listet Profile, die seit 180 Tagen nicht genutzt wurden (Exit 2 bei Kandidaten).
    EN: Audit only: lists profiles not used for 180 days (exit 2 if candidates exist).
.EXAMPLE
    .\removeStaleUserProfiles.ps1 -Allow true -Exclude 'svc_backup,localadmin' -WhatIf
    DE: Simuliert das Entfernen; nichts wird gelöscht.
    EN: Simulates the removal; nothing is deleted.
.EXAMPLE
    .\removeStaleUserProfiles.ps1 -Allow true -MaxRemovals 10 -CustomField staleProfileReport
    DE: Entfernt bis zu 10 veraltete Profile und schreibt das JSON in staleProfileReport.
    EN: Removes up to 10 stale profiles and writes the JSON to staleProfileReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = keine Kandidaten, alle ausgewählten Profile entfernt (weitere Kandidaten werden als Deferred
                 gemeldet) oder -WhatIf.
        Exit 1 = Eingabe-, Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat Kandidaten gefunden; oder mindestens ein Profil konnte nicht entfernt
                 werden bzw. wurde bei der erneuten Prüfung übersprungen.
        ConfirmImpact bewusst Medium (nicht High), damit unbeaufsichtigte NinjaOne-Läufe ohne Rückfrage
        funktionieren; Schutz erfolgt über Allow, MaxRemovals und die Ausschlüsse. -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = no candidates, all selected profiles removed (further candidates are reported as Deferred) or
                 -WhatIf.
        Exit 1 = input, query or write error.
        Exit 2 = audit (Allow=false) found candidates; or at least one profile could not be removed or was
                 skipped by the recheck.
        ConfirmImpact is intentionally Medium (not High) so unattended NinjaOne runs work without prompts;
        protection comes from Allow, MaxRemovals and the exclusions. -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:cleanupProfilesAllow,
    [string]$MinimumAgeDays = $env:cleanupProfilesMinimumAgeDays,
    [string]$Exclude = $env:cleanupProfilesExclude,
    [string]$MaxRemovals = $env:cleanupProfilesMaxRemovals,
    [string]$IncludeUnknownAge = $env:cleanupProfilesIncludeUnknownAge,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-Boolean {
    param([string]$Value, [string]$Name)
    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw ('{0}: true/false erforderlich / true/false required.' -f $Name) }
    return $parsed
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $parsed = 0
    if ($Value -notmatch '^\d{1,9}$' -or -not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw ('{0}: ganze Zahl {1}-{2} erforderlich / integer {1}-{2} required.' -f $Name, $Minimum, $Maximum)
    }
    return $parsed
}
function Resolve-AccountName {
    param([string]$Sid)
    try { return ([Security.Principal.SecurityIdentifier]::new($Sid)).Translate([Security.Principal.NTAccount]).Value }
    catch { return $null }
}
function Get-LoggedOnIdentity {
    $identity = [pscustomobject]@{ Names = @(); Sids = @() }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
    if ($computer -and $computer.UserName) {
        $identity.Names += [string]$computer.UserName
        $identity.Names += ([string]$computer.UserName -split '\\')[-1]
    }
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)) {
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($null -ne $owner -and [int]$owner.ReturnValue -eq 0 -and $owner.User) {
            $identity.Names += [string]$owner.User
            if ($owner.Domain) { $identity.Names += ('{0}\{1}' -f $owner.Domain, $owner.User) }
        }
        $ownerSid = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($null -ne $ownerSid -and [int]$ownerSid.ReturnValue -eq 0 -and $ownerSid.Sid) { $identity.Sids += [string]$ownerSid.Sid }
    }
    return $identity
}
function Export-Report {
    param([System.Collections.IDictionary]$Data, [string]$Field)
    $json = ConvertTo-Json -Depth 5 -InputObject $Data
    if ($json.Length -gt 4000) { $json = ConvertTo-Json -Depth 5 -Compress -InputObject $Data }
    Write-Output $json
    if ($Field) {
        if ($json.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $json | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}
try {
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'cleanupProfilesAllow'
    $days = ConvertTo-BoundedInt -Value (Resolve-Setting $MinimumAgeDays '90') -Name 'cleanupProfilesMinimumAgeDays' -Minimum 30 -Maximum 3650
    $limit = ConvertTo-BoundedInt -Value (Resolve-Setting $MaxRemovals '5') -Name 'cleanupProfilesMaxRemovals' -Minimum 1 -Maximum 50
    $includeUnknown = ConvertTo-Boolean -Value (Resolve-Setting $IncludeUnknownAge 'false') -Name 'cleanupProfilesIncludeUnknownAge'
    $excludeText = Resolve-Setting $Exclude ''
    $exclusions = @()
    if ($excludeText) {
        if ($excludeText.Length -gt 6000) { throw 'cleanupProfilesExclude zu lang / too long.' }
        $exclusions = @($excludeText.Split(',') | ForEach-Object { $_.Trim() })
        if ($exclusions.Count -gt 50 -or @($exclusions | Where-Object { -not $_ -or $_.Length -gt 104 -or $_ -match '[\x00-\x1f*?"<>|/:\[\]]' }).Count -gt 0) {
            throw 'Ungültige cleanupProfilesExclude-Liste / Invalid cleanupProfilesExclude list.'
        }
    }
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $cutoff = [DateTime]::Now.AddDays(-$days)
    $loggedOn = Get-LoggedOnIdentity
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    $candidates = @()
    $protectedCount = 0
    foreach ($userProfile in $profiles) {
        $sid = [string]$userProfile.SID
        $localPath = [string]$userProfile.LocalPath
        $folder = if ($localPath) { ($localPath.TrimEnd('\', '/') -split '[\\/]')[-1] } else { '' }
        $reason = $null
        if ($sid -notmatch '^S-1-(5-21|12-1)-\d+(-\d+)*$' -or $sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { $reason = 'SystemSid' }
        elseif ($userProfile.Special -eq $true) { $reason = 'Special' }
        elseif ($userProfile.Loaded -eq $true) { $reason = 'Loaded' }
        elseif ($sid -match '-500$') { $reason = 'BuiltInAdministrator' }
        elseif (-not $localPath) { $reason = 'NoLocalPath' }
        if ($reason) { $protectedCount++; continue }
        $account = Resolve-AccountName -Sid $sid
        $accountShort = if ($account) { ($account -split '\\')[-1] } else { $null }
        if ($loggedOn.Sids -contains $sid -or $loggedOn.Names -contains $folder -or ($account -and ($loggedOn.Names -contains $account -or $loggedOn.Names -contains $accountShort))) { $protectedCount++; continue }
        if ($exclusions -contains $folder -or ($account -and ($exclusions -contains $account -or $exclusions -contains $accountShort))) { $protectedCount++; continue }
        $lastUse = $null
        if ($null -ne $userProfile.LastUseTime) { $lastUse = [datetime]$userProfile.LastUseTime }
        if ($null -eq $lastUse -and -not $includeUnknown) { $protectedCount++; continue }
        if ($null -ne $lastUse -and $lastUse -ge $cutoff) { continue }
        $candidates += [pscustomobject]@{
            Sid = $sid; LocalPath = $localPath; Account = $account
            LastUseTime = $(if ($null -ne $lastUse) { $lastUse.ToString('yyyy-MM-dd') } else { $null })
            AgeDays = $(if ($null -ne $lastUse) { [int]([DateTime]::Now - $lastUse).TotalDays } else { $null })
            SortKey = $(if ($null -ne $lastUse) { $lastUse } else { [DateTime]::MinValue })
            Status = 'Candidate'; Instance = $userProfile
        }
    }
    $candidates = @($candidates | Sort-Object -Property SortKey)
    $removed = 0
    $failed = 0
    for ($index = 0; $index -lt $candidates.Count; $index++) {
        $candidate = $candidates[$index]
        if ($index -ge $limit) { $candidate.Status = 'Deferred'; continue }
        if (-not $allowed) { continue }
        if (-not $PSCmdlet.ShouldProcess(('{0} ({1})' -f $candidate.LocalPath, $candidate.Sid), 'Benutzerprofil entfernen / Remove user profile')) { $candidate.Status = 'WhatIf'; continue }
        try {
            # DE: Unmittelbar vorher erneut prüfen. EN: Recheck immediately before removal.
            $current = @(Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $candidate.Sid) -ErrorAction Stop) | Select-Object -First 1
            if ($null -eq $current) { $candidate.Status = 'AlreadyRemoved'; continue }
            if ($current.Loaded -eq $true -or $current.Special -eq $true) { $candidate.Status = 'SkippedLoaded'; $failed++; continue }
            Remove-CimInstance -InputObject $current -ErrorAction Stop
            $candidate.Status = 'Removed'
            $removed++
        }
        catch {
            $message = [string]$_.Exception.Message
            if ($message.Length -gt 120) { $message = $message.Substring(0, 120) }
            $candidate.Status = 'Failed: ' + $message
            $failed++
        }
    }
    $maxRecords = 25
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; MinimumAgeDays = $days
        MaxRemovals = $limit; IncludeUnknownAge = $includeUnknown; ExclusionCount = $exclusions.Count
        ProfilesScanned = $profiles.Count; ProtectedOrExcluded = $protectedCount; CandidateCount = $candidates.Count
        Removed = $removed; Failed = $failed; Deferred = @($candidates | Where-Object { $_.Status -eq 'Deferred' }).Count
        CandidatesOmitted = [Math]::Max(0, $candidates.Count - $maxRecords)
        Candidates = @($candidates | Select-Object -First $maxRecords | Select-Object Sid, LocalPath, Account, LastUseTime, AgeDays, Status)
    })
    if (-not $allowed) {
        if ($candidates.Count -gt 0) { exit 2 }
        exit 0
    }
    if ($failed -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
