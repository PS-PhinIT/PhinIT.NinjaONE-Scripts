#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert SMB-Freigaben und meldet zu weit gefasste Freigabeberechtigungen.
    EN: Inventories SMB shares and reports overly broad share permissions.
.DESCRIPTION
    DE: Liest Get-SmbShare und je Freigabe Get-SmbShareAccess (nur Freigabe-, nicht
        NTFS-Rechte). Riskant ist eine Allow-Regel Full oder Change für Jeder/Everyone
        (S-1-1-0), Authentifizierte Benutzer (S-1-5-11) oder Gäste/Guests (S-1-5-32-546);
        lokalisierte Kontonamen werden über die SIDs aufgelöst. Spezielle
        Verwaltungsfreigaben (C$, ADMIN$, IPC$) sind optional ausgeschlossen. Exit 2
        bei mindestens einer riskanten Freigabe. Keine Änderungen; JSON max. 4000
        Zeichen, Liste wird bei Bedarf gekürzt (max. 10 ACL-Einträge je Freigabe).
    EN: Reads Get-SmbShare and per share Get-SmbShareAccess (share permissions only,
        not NTFS). Risky is an Allow entry Full or Change for Everyone (S-1-1-0),
        Authenticated Users (S-1-5-11) or Guests (S-1-5-32-546); localized account names
        are resolved via the SIDs. Special administrative shares (C$, ADMIN$, IPC$) are
        optionally excluded. Exit 2 on at least one risky share. No changes; JSON max.
        4000 characters, list shortened if needed (max. 10 ACL entries per share).
.PARAMETER ExcludeSpecial
    DE: NinjaOne Checkbox/Text networkSmbExcludeSpecialShares: true/false/1/0; Standard true.
    EN: NinjaOne checkbox/text networkSmbExcludeSpecialShares: true/false/1/0; default true.
.PARAMETER MaxRecords
    DE: NinjaOne Integer networkSmbMaxRecords, 1..200; Standard 25.
    EN: NinjaOne Integer networkSmbMaxRecords, 1..200; default 25.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\readSmbShares.ps1
    DE: Nicht-spezielle Freigaben (max. 25); Exit 2 bei riskanten Rechten.
    EN: Non-special shares (max. 25); exit 2 on risky permissions.
.EXAMPLE
    .\readSmbShares.ps1 -ExcludeSpecial false -MaxRecords 50 -CustomField smbShares
    DE: Alle Freigaben inkl. Verwaltungsfreigaben ins Feld smbShares.
    EN: All shares including administrative shares to the field smbShares.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler (z. B. Serverdienst
        gestoppt), 2 = riskante Freigabe(n). Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error (e.g. Server service stopped),
        2 = risky share(s). Read-only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExcludeSpecial = $env:networkSmbExcludeSpecialShares,
    [string]$MaxRecords = $env:networkSmbMaxRecords,
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
function Get-InputText {
    param([string]$Value, [string]$Default)
    $text = ([string]$Value).Trim()
    if (-not $text -or $text -ieq 'null') { return $Default }
    return $text
}
function Publish-NetworkReport {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Report, [string]$Field)
    if ($Field -and $PSCmdlet.ShouldProcess($Field, 'Write NinjaOne field / NinjaOne-Feld schreiben')) {
        if ($Report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $Report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    $ExcludeSpecial = Get-InputText $ExcludeSpecial 'true'
    $MaxRecords = Get-InputText $MaxRecords '25'
    $CustomField = Get-InputText $CustomField ''
    if ($ExcludeSpecial -notin @('true', 'false', '1', '0')) { throw 'networkSmbExcludeSpecialShares: true/false/1/0.' }
    $skipSpecial = $ExcludeSpecial -in @('true', '1')
    $limit = 0
    if (-not [int]::TryParse($MaxRecords, [ref]$limit) -or $limit -lt 1 -or $limit -gt 200) { throw 'networkSmbMaxRecords: 1..200 erforderlich / required.' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    # DE: Englische Namen plus lokalisierte Namen aus den bekannten SIDs. EN: English names plus localized names from well-known SIDs.
    $broadNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('Everyone', 'Authenticated Users', 'Guests')) { [void]$broadNames.Add($name) }
    foreach ($sid in @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-546')) {
        try {
            $account = (New-Object System.Security.Principal.SecurityIdentifier $sid).Translate([System.Security.Principal.NTAccount]).Value
            [void]$broadNames.Add(($account -split '\\')[-1])
        } catch { Write-Verbose ('SID {0} nicht auflösbar / not resolvable.' -f $sid) }
    }

    $shares = @(Get-SmbShare -ErrorAction Stop | Where-Object { -not ($skipSpecial -and $_.Special -eq $true) } | Sort-Object Name)
    $all = @(foreach ($share in $shares) {
        $query = @{ Name = [string]$share.Name; ErrorAction = 'Stop' }
        if ($share.ScopeName -and [string]$share.ScopeName -ne '*') { $query['ScopeName'] = [string]$share.ScopeName }
        $access = @(Get-SmbShareAccess @query | ForEach-Object {
            $leaf = ([string]$_.AccountName -split '\\')[-1]
            [pscustomobject]@{
                Account = [string]$_.AccountName; Type = [string]$_.AccessControlType; Right = [string]$_.AccessRight
                Risky = ([string]$_.AccessControlType -eq 'Allow' -and [string]$_.AccessRight -in @('Full', 'Change') -and $broadNames.Contains($leaf))
            }
        })
        $risky = @($access | Where-Object { $_.Risky } | ForEach-Object { '{0}:{1}' -f $_.Account, $_.Right })
        [pscustomobject]@{
            Name = [string]$share.Name; Path = [string]$share.Path; Special = ($share.Special -eq $true)
            Risky = ($risky.Count -gt 0); RiskyAccess = $risky
            Access = @($access | Select-Object -First 10 | ForEach-Object { '{0}:{1}:{2}' -f $_.Account, $_.Type, $_.Right })
        }
    })
    $riskyShares = @($all | Where-Object { $_.Risky })
    $selected = @($all | Sort-Object @{ Expression = { -not $_.Risky } }, Name)
    $records = @($selected | Select-Object -First $limit)
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            ExcludeSpecial = $skipSpecial; TotalShares = $all.Count; RiskyShareCount = $riskyShares.Count
            RiskyShares = @($riskyShares | ForEach-Object { $_.Name } | Select-Object -First 20)
            ReportedRecords = $records.Count; Truncated = ($records.Count -lt $all.Count); Shares = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($riskyShares.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
