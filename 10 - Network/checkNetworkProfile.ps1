#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft die Netzwerkkategorie (Firewallprofil) aktiver Verbindungen.
    EN: Checks the network category (firewall profile) of active connections.
.DESCRIPTION
    DE: Liest Get-NetConnectionProfile (Name, InterfaceAlias, NetworkCategory,
        IPv4-/IPv6-Konnektivität) und per CIM (Win32_ComputerSystem.PartOfDomain), ob
        das Gerät domänenverbunden ist. Exit 2, wenn auf einem Domänengerät ein Profil
        Public ist oder (falls gesetzt) eine Kategorie von ExpectedCategory abweicht.
        Mit ExpectedCategory ist auch "kein Verbindungsprofil" ein Befund. Keine
        Änderungen; JSON-Bericht max. 4000 Zeichen.
    EN: Reads Get-NetConnectionProfile (Name, InterfaceAlias, NetworkCategory,
        IPv4/IPv6 connectivity) and via CIM (Win32_ComputerSystem.PartOfDomain) whether
        the device is domain-joined. Exit 2 if a profile is Public on a domain-joined
        device or (when set) a category differs from ExpectedCategory. With
        ExpectedCategory, "no connection profile" is also a finding. No changes;
        JSON report max. 4000 characters.
.PARAMETER ExpectedCategory
    DE: NinjaOne Text networkExpectedCategory: Public, Private oder DomainAuthenticated; Standard leer (keine Vorgabe).
    EN: NinjaOne Text networkExpectedCategory: Public, Private or DomainAuthenticated; default empty (no expectation).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes; -WhatIf überspringt das Schreiben.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field; -WhatIf skips the write.
.EXAMPLE
    .\checkNetworkProfile.ps1
    DE: Exit 2, wenn ein Domänengerät ein Public-Profil hat.
    EN: Exit 2 if a domain-joined device has a Public profile.
.EXAMPLE
    .\checkNetworkProfile.ps1 -ExpectedCategory DomainAuthenticated -CustomField networkProfile
    DE: Erwartet überall DomainAuthenticated; JSON ins Feld networkProfile.
    EN: Expects DomainAuthenticated everywhere; JSON to the field networkProfile.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = OK, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = Public auf Domänengerät
        oder abweichende Kategorie. Nur lesend; der Netzwerkname kann eine SSID sein.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = OK, 1 = input/query/write error, 2 = Public on domain device or
        unexpected category. Read-only; the network name may be an SSID.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExpectedCategory = $env:networkExpectedCategory,
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
    $ExpectedCategory = Get-InputText $ExpectedCategory ''
    $CustomField = Get-InputText $CustomField ''
    $categories = @('Public', 'Private', 'DomainAuthenticated')
    if ($ExpectedCategory) {
        if ($ExpectedCategory -notin $categories) { throw 'networkExpectedCategory: Public, Private oder/or DomainAuthenticated.' }
        $ExpectedCategory = $categories | Where-Object { $_ -ieq $ExpectedCategory }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }

    $computer = @(Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop) | Select-Object -First 1
    if (-not $computer) { throw 'Win32_ComputerSystem nicht lesbar / not readable.' }
    $domainJoined = ($computer.PartOfDomain -eq $true)
    # DE: "Keine Profile" (ObjectNotFound) ist kein Abfragefehler. EN: "No profiles" (ObjectNotFound) is not a query error.
    $profileErrors = $null
    $rawProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue -ErrorVariable profileErrors)
    $realErrors = @($profileErrors | Where-Object { $_.CategoryInfo.Category -ne 'ObjectNotFound' })
    if ($realErrors.Count -gt 0) { throw $realErrors[0] }

    $findings = New-Object System.Collections.Generic.List[string]
    $profiles = @($rawProfiles | Where-Object { $null -ne $_ } | Sort-Object InterfaceIndex | ForEach-Object {
        $category = [string]$_.NetworkCategory
        $issues = @()
        if ($domainJoined -and $category -eq 'Public') { $issues += 'PublicOnDomainJoinedDevice' }
        if ($ExpectedCategory -and $category -ne $ExpectedCategory) { $issues += 'UnexpectedCategory' }
        foreach ($issue in $issues) { $findings.Add(('{0}: {1}' -f $_.InterfaceAlias, $issue)) }
        [pscustomobject]@{
            Name = [string]$_.Name; InterfaceAlias = [string]$_.InterfaceAlias; InterfaceIndex = [int]$_.InterfaceIndex
            NetworkCategory = $category; IPv4Connectivity = [string]$_.IPv4Connectivity
            IPv6Connectivity = [string]$_.IPv6Connectivity; Issues = $issues
        }
    })
    if ($ExpectedCategory -and $profiles.Count -eq 0) { $findings.Add('NoConnectionProfile') }

    $records = @($profiles | Select-Object -First 50)
    do {
        $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
            DomainJoined = $domainJoined; ExpectedCategory = $ExpectedCategory; Findings = @($findings | Select-Object -First 20)
            TotalProfiles = $profiles.Count; ReportedRecords = $records.Count; Truncated = ($records.Count -lt $profiles.Count)
            Profiles = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    Publish-NetworkReport -Report $report -Field $CustomField
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
