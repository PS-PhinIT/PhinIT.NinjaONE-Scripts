#Requires -Version 5.1

<#
.SYNOPSIS
DE: Inventarisiert registrierte Antivirenprodukte ausser Windows/Microsoft Defender Antivirus.
EN: Inventories registered antivirus products other than Windows/Microsoft Defender Antivirus.
.DESCRIPTION
DE: NinjaOne-Text null gilt als leer vor Standardwerten. EN: NinjaOne literal null is empty before defaults.
DE: SYSTEM, 64-Bit Windows PowerShell; nur Windows-Clients via root\SecurityCenter2.
EN: SYSTEM, 64-bit Windows PowerShell; Windows clients only via root\SecurityCenter2.
DE: Server liefern Warnung "Unsupported", NICHT "kein Antivirus".
EN: Servers return an "Unsupported" warning, NOT "no antivirus".
DE: ExpectedProduct / securityExpectedProduct: optionaler woertlicher Teil des Anzeigenamens.
EN: ExpectedProduct / securityExpectedProduct: optional literal display-name substring.
DE: Leer bedeutet beliebiges Fremdprodukt. Registrierung kann veraltet sein;
    productState wird nur roh gemeldet, NICHT als Funktions-/Update-Nachweis interpretiert.
EN: Empty means any third-party product. Registrations may be stale;
    productState is reported raw, NOT interpreted as proof of health/updates.
DE: CustomField / resultCustomField: optionales MultiLine-JSON-Feld, maximal 4000 Zeichen.
EN: CustomField / resultCustomField: optional MultiLine JSON field, maximum 4000 characters.
DE: Explizite Parameter haben Vorrang; keine Installationen/Entfernungen.
EN: Explicit parameters take precedence; no installations/removals.
DE/EN: Exit 0 = registriert/registered, 1 = Fehler/error, 2 = fehlt/nicht unterstuetzt/missing/unsupported.
.PARAMETER ExpectedProduct
DE: Woertlicher Namensteil; securityExpectedProduct; Standard leer = jedes Fremdprodukt.
EN: Literal name substring; securityExpectedProduct; default empty = any third-party product.
.PARAMETER CustomField
DE: Optionales MultiLine-JSON-Feld; resultCustomField; Standard leer.
EN: Optional MultiLine JSON field; resultCustomField; default empty.
.EXAMPLE
.\checkAnotherSecurityProduct.ps1
DE: Exit 0, wenn irgendein registriertes Fremd-Antivirenprodukt gefunden wird.
EN: Exit 0 if any registered third-party antivirus product is found.
.EXAMPLE
.\checkAnotherSecurityProduct.ps1 -ExpectedProduct 'Sophos' -CustomField securityProducts
DE: Verlangt ein Produkt mit "Sophos" im Anzeigenamen; JSON in securityProducts.
EN: Requires a product with "Sophos" in its display name; JSON to securityProducts.
#>
[CmdletBinding()]
param([string]$ExpectedProduct = '', [string]$CustomField = '')

$global:LASTEXITCODE = 0
try {
    # DE: Keine Platzhalterauswertung. EN: Never interpret product names as wildcards.
    if (-not $PSBoundParameters.ContainsKey('ExpectedProduct')) { $ExpectedProduct = $env:securityExpectedProduct }
    if (-not $PSBoundParameters.ContainsKey('CustomField')) { $CustomField = $env:resultCustomField }
    $ExpectedProduct = ([string]$ExpectedProduct).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($ExpectedProduct -ieq 'null') { $ExpectedProduct = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($ExpectedProduct.Length -gt 200 -or $ExpectedProduct -match '[\r\n]') { throw 'Ungueltiges ExpectedProduct / Invalid ExpectedProduct.' }
    if ($CustomField -match '[\r\n]' -or $CustomField.Length -gt 128) { throw 'Ungueltiges CustomField / Invalid CustomField.' }
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-Bit Windows PowerShell erforderlich / required.' }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $supported = [int]$os.ProductType -eq 1
    $rows = @()
    if ($supported) {
        $products = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct -ErrorAction Stop)
        $rows = @($products | Where-Object {
            [string]$_.instanceGuid -ne '{D68DDC3A-831F-4fae-9E44-DA132C1ACF46}' -and
            [string]$_.displayName -notmatch '^(Windows Defender|Microsoft Defender Antivirus)$'
        } | ForEach-Object {
            $match = -not $ExpectedProduct -or ([string]$_.displayName).IndexOf($ExpectedProduct, [StringComparison]::OrdinalIgnoreCase) -ge 0
            [pscustomobject]@{ DisplayName = [string]$_.displayName; InstanceGuid = [string]$_.instanceGuid; ProductStateRaw = $_.productState; MatchesExpected = $match }
        })
    }
    $matched = @($rows | Where-Object { $_.MatchesExpected }).Count -gt 0
    $text = ConvertTo-Json -InputObject ([pscustomobject]@{
        CollectionStatus = $(if ($supported) { 'Supported_RegistrationOnly' } else { 'Unsupported_Server' })
        ExpectedProduct = $ExpectedProduct; MatchingRegistration = $matched; Products = $rows
    }) -Depth 4 -Compress
    if ($global:LASTEXITCODE -ne 0) { throw "Befehlsfehler / Command failed: $global:LASTEXITCODE" }
    if ($text.Length -gt 4000) { throw 'Ergebnis groesser als 4000 Zeichen / Result exceeds 4000 characters.' }
    Write-Output $text
    if ($CustomField) {
        $null = Get-Command Ninja-Property-Set -ErrorAction Stop
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $text -ErrorAction Stop | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'CustomField konnte nicht geschrieben werden / Field write failed.' }
    }
    if (-not $supported -or -not $matched) { exit 2 }
    exit 0
} catch {
    Write-Error ("Produktinventar fehlgeschlagen / Product inventory failed: " + $_.Exception.Message) -ErrorAction Continue
    exit 1
}