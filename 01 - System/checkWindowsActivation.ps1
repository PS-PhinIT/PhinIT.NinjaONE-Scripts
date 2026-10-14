#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft den Aktivierungsstatus von Windows, ohne Produktschlüssel auszugeben.
    EN: Checks the Windows activation status without exposing product keys.
.DESCRIPTION
    DE: Liest SoftwareLicensingProduct per CIM, gefiltert auf Windows
        (ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f) mit installiertem
        Schlüssel (PartialProductKey nicht leer). LicenseStatus wird als Text
        gemeldet (Unlicensed, Licensed, OOBGrace, OOTGrace, NonGenuineGrace,
        Notification, ExtendedGrace). Es werden nur die letzten 5 Zeichen des
        Schlüssels (PartialProductKey) ausgegeben, niemals vollständige Schlüssel.
        Max. 5 Einträge. Ausgabe als JSON, optional in ein MultiLine-Feld
        (max. 4000 Zeichen). Exit 0 = Windows lizenziert (Licensed), 1 = Eingabe-,
        Abfrage- oder Schreibfehler, 2 = kein Windows-Produkt mit Status Licensed
        (auch: kein Schlüssel installiert). Nur lesend; die Abfrage kann einige
        Sekunden dauern.
    EN: Reads SoftwareLicensingProduct via CIM, filtered to Windows
        (ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f) with an installed key
        (PartialProductKey not null). LicenseStatus is reported as text
        (Unlicensed, Licensed, OOBGrace, OOTGrace, NonGenuineGrace, Notification,
        ExtendedGrace). Only the last 5 key characters (PartialProductKey) are
        output, never full keys. Max. 5 entries. Outputs JSON, optionally to a
        MultiLine field (max. 4000 characters). Exit 0 = Windows licensed,
        1 = input, query or write error, 2 = no Windows product with status
        Licensed (including: no key installed). Read-only; the query may take a
        few seconds.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Gerätefeldes; leer = kein Export.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine device field; empty = no export.
.EXAMPLE
    .\checkWindowsActivation.ps1
    DE: Warnt (Exit 2), wenn Windows nicht aktiviert ist.
    EN: Warns (exit 2) if Windows is not activated.
.EXAMPLE
    .\checkWindowsActivation.ps1 -CustomField windowsActivation
    DE: Zusätzlich JSON ins Feld windowsActivation schreiben.
    EN: Additionally write the JSON to the field windowsActivation.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = aktiviert, 1 = Fehler, 2 = nicht aktiviert. Nur lesend.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = activated, 1 = error, 2 = not activated. Read-only.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') {
        throw 'Ungültiger Feldname / Invalid custom field name.'
    }
    $statusMap = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOTGrace'; 4 = 'NonGenuineGrace'
        5 = 'Notification'; 6 = 'ExtendedGrace' }
    $filter = "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
    $products = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $filter |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.PartialProductKey) })
    $records = @(foreach ($product in ($products | Select-Object -First 5)) {
        $code = -1
        if ($null -ne $product.LicenseStatus) { $code = [int]$product.LicenseStatus }
        # DE: Nur 5 Zeichen zulassen; alles andere verwerfen. EN: Allow only 5 characters; discard anything else.
        $partial = ([string]$product.PartialProductKey).Trim()
        if ($partial -notmatch '^[A-Za-z0-9]{5}$') { $partial = $null }
        $name = (([string]$product.Name) -replace '[\x00-\x1F\x7F]', '').Trim()
        $channel = (([string]$product.ProductKeyChannel) -replace '[^A-Za-z0-9_:\-]', '')
        [pscustomobject]@{
            Name = $name.Substring(0, [Math]::Min(120, $name.Length))
            LicenseStatus = $(if ($statusMap.ContainsKey($code)) { $statusMap[$code] } else { "Code $code" })
            LicenseStatusCode = $code
            PartialProductKey = $partial
            ProductKeyChannel = $channel.Substring(0, [Math]::Min(40, $channel.Length))
            GraceMinutesRemaining = $product.GracePeriodRemaining
        }
    })
    $licensed = @($products | Where-Object { $null -ne $_.LicenseStatus -and [int]$_.LicenseStatus -eq 1 }).Count -gt 0
    $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
        Activated = $licensed
        ProductsWithKey = $products.Count
        Products = $records
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if (-not $licensed) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
