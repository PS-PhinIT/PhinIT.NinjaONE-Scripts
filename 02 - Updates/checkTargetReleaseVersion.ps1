#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Vergleicht installierte Windows-Version mit der TargetReleaseVersion-Richtlinie.
    EN: Compares the installed Windows version with the TargetReleaseVersion policy.
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion (ProductName, EditionID,
        DisplayVersion bzw. ReleaseId, CurrentBuildNumber, UBR) und die Richtlinie unter
        HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate (TargetReleaseVersion,
        TargetReleaseVersionInfo, ProductVersion), ersatzweise MDM-Werte unter
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update. Das Produkt wird aus der
        Build-Nummer abgeleitet (>= 22000 = Windows 11), da ProductName auf Windows 11
        weiterhin "Windows 10" enthalten kann. Exit 0 = keine Abweichung, 1 = Eingabe-,
        Abfrage- oder Schreibfehler, 2 = Abweichung: aktive Richtlinie und installierte
        Version/Produkt verschieden, oder ExpectedVersion/ExpectedProduct weicht von Richtlinie
        oder installierter Version ab.
    EN: Reads HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion (ProductName, EditionID,
        DisplayVersion or ReleaseId, CurrentBuildNumber, UBR) and the policy under
        HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate (TargetReleaseVersion,
        TargetReleaseVersionInfo, ProductVersion), falling back to MDM values under
        HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update. The product is derived
        from the build number (>= 22000 = Windows 11) because ProductName may still contain
        "Windows 10" on Windows 11. Exit 0 = no mismatch, 1 = input, query or write error,
        2 = mismatch: active policy and installed version/product differ, or ExpectedVersion/
        ExpectedProduct differs from the policy or the installed version.
.PARAMETER ExpectedVersion
    DE: NinjaOne Text updateTargetExpectedVersion: z. B. 23H2 oder 1909 (Format NNHn oder NNNN); Standard leer.
    EN: NinjaOne text updateTargetExpectedVersion: e.g. 23H2 or 1909 (format NNHn or NNNN); default empty.
.PARAMETER ExpectedProduct
    DE: NinjaOne Dropdown/Text updateTargetExpectedProduct: Windows 10 oder Windows 11; Standard leer.
    EN: NinjaOne drop-down/text updateTargetExpectedProduct: Windows 10 or Windows 11; default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; default empty.
.EXAMPLE
    .\checkTargetReleaseVersion.ps1
    DE: Warnt, wenn eine aktive Zielversionsrichtlinie nicht der installierten Version entspricht.
    EN: Warns if an active target version policy does not match the installed version.
.EXAMPLE
    .\checkTargetReleaseVersion.ps1 -ExpectedVersion 24H2 -ExpectedProduct 'Windows 11' -CustomField targetRelease
    DE: Erwartet Windows 11 24H2 in Richtlinie und Installation; JSON ins Feld targetRelease.
    EN: Expects Windows 11 24H2 in policy and installation; JSON to the field targetRelease.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend. Ein Gerät unter der Zielversion
        (Upgrade ausstehend) gilt ebenfalls als Abweichung. Exit 0 = OK, 1 = Fehler, 2 = Abweichung.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only. A device below the target version
        (upgrade pending) also counts as a mismatch. Exit 0 = OK, 1 = error, 2 = mismatch.
#>
[CmdletBinding()]
param(
    [string]$ExpectedVersion = $env:updateTargetExpectedVersion,
    [string]$ExpectedProduct = $env:updateTargetExpectedProduct,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Get-RegistryValueTable {
    param([string]$Path, [string[]]$Names)
    $table = [ordered]@{}
    $item = $null
    if (Test-Path -LiteralPath $Path) { $item = Get-ItemProperty -LiteralPath $Path }
    foreach ($name in $Names) {
        $value = $null
        if ($null -ne $item -and $item.PSObject.Properties[$name]) { $value = $item.$name }
        $table[$name] = $value
    }
    $table
}
try {
    if ([string]::IsNullOrWhiteSpace($ExpectedVersion) -or $ExpectedVersion.Trim() -eq 'null') { $ExpectedVersion = '' }
    if ([string]::IsNullOrWhiteSpace($ExpectedProduct) -or $ExpectedProduct.Trim() -eq 'null') { $ExpectedProduct = '' }
    if ([string]::IsNullOrWhiteSpace($CustomField) -or $CustomField.Trim() -eq 'null') { $CustomField = '' }
    $ExpectedVersion = $ExpectedVersion.Trim().ToUpperInvariant()
    $CustomField = $CustomField.Trim()
    if ($ExpectedVersion -and $ExpectedVersion -notmatch '^(\d{2}H[12]|\d{4})$') { throw 'updateTargetExpectedVersion: NNHn/NNNN erforderlich / required.' }
    if ($ExpectedProduct) {
        $product = @('Windows 10', 'Windows 11') | Where-Object { $_ -eq $ExpectedProduct.Trim() } | Select-Object -First 1
        if (-not $product) { throw 'updateTargetExpectedProduct: Windows 10/Windows 11 erforderlich / required.' }
        $ExpectedProduct = $product
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges CustomField / Invalid CustomField.' }
    $os = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Names @('ProductName', 'EditionID',
        'DisplayVersion', 'ReleaseId', 'CurrentBuildNumber', 'UBR')
    $build = 0
    if (-not [int]::TryParse([string]$os.CurrentBuildNumber, [ref]$build) -or $build -le 0) { throw 'CurrentBuildNumber nicht lesbar / unreadable.' }
    $version = [string]$os.DisplayVersion
    if (-not $version) { $version = [string]$os.ReleaseId }
    $currentProduct = [string]$os.ProductName
    if ($currentProduct -notmatch 'Server') { $currentProduct = $(if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }) }
    $gpo = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Names @('TargetReleaseVersion',
        'TargetReleaseVersionInfo', 'ProductVersion')
    $mdm = Get-RegistryValueTable -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -Names @('TargetReleaseVersion', 'ProductVersion')
    $policySource = $null; $targetVersion = $null; $targetProduct = $null
    if ([string]$gpo.TargetReleaseVersion -eq '1' -and [string]$gpo.TargetReleaseVersionInfo) {
        $policySource = 'GroupPolicy'; $targetVersion = ([string]$gpo.TargetReleaseVersionInfo).Trim(); $targetProduct = ([string]$gpo.ProductVersion).Trim()
    }
    elseif ([string]$mdm.TargetReleaseVersion) {
        $policySource = 'MDM'; $targetVersion = ([string]$mdm.TargetReleaseVersion).Trim(); $targetProduct = ([string]$mdm.ProductVersion).Trim()
    }
    $findings = [System.Collections.Generic.List[string]]::new()
    if ($policySource) {
        if ($version -ne $targetVersion) { $findings.Add("Installiert/Installed $version != Richtlinie/Policy $targetVersion") }
        if ($targetProduct -and $targetProduct -ne $currentProduct) { $findings.Add("Produkt/Product $currentProduct != Richtlinie/Policy $targetProduct") }
    }
    if ($ExpectedVersion) {
        if ($targetVersion -ne $ExpectedVersion) { $findings.Add("Richtlinie/Policy '$targetVersion' != erwartet/expected $ExpectedVersion") }
        if ($version -ne $ExpectedVersion) { $findings.Add("Installiert/Installed $version != erwartet/expected $ExpectedVersion") }
    }
    if ($ExpectedProduct) {
        if ($targetProduct -ne $ExpectedProduct) { $findings.Add("Richtlinie/Policy ProductVersion '$targetProduct' != erwartet/expected $ExpectedProduct") }
        if ($currentProduct -ne $ExpectedProduct) { $findings.Add("Produkt/Product $currentProduct != erwartet/expected $ExpectedProduct") }
    }
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; CurrentProduct = $currentProduct; EditionID = $os.EditionID; CurrentVersion = $version
        Build = $build; UBR = $os.UBR; FullBuild = ('{0}.{1}' -f $build, [int]$os.UBR)
        PolicySource = $policySource; TargetReleaseVersionInfo = $targetVersion; TargetProductVersion = $targetProduct
        ExpectedVersion = $ExpectedVersion; ExpectedProduct = $ExpectedProduct; GroupPolicy = $gpo; MdmPolicy = $mdm; Findings = @($findings)
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
