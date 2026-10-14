#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Inventarisiert Java-Laufzeiten/JDKs (Oracle, OpenJDK, Adoptium, Zulu, Microsoft u. a.) mit Hersteller und Version.
    EN: Inventories Java runtimes/JDKs (Oracle, OpenJDK, Adoptium, Zulu, Microsoft etc.) with vendor and version.
.DESCRIPTION
    DE: Quellen: 64-/32-Bit-Uninstall-Schlüssel unter HKLM (Anzeigename enthält Java/JRE/JDK/OpenJDK/Temurin/
        Adoptium/Zulu/Corretto/Liberica; Updater ausgeschlossen) und HKLM\SOFTWARE\JavaSoft (JRE/JDK-Versionsschlüssel,
        Familienschlüssel wie "1.8" oder "17" werden ausgelassen, wenn ein genauerer Schlüssel existiert).
        Verschwundene Unterschlüssel werden übersprungen. Versionsnormalisierung: "_" und "+" werden zu ".",
        "1.8.0_391" -> 8.0.391, "Java 8 Update 391" -> 8.0.391. Herstellereigene Schemata (z. B. Azul-Zulu-
        Produktversion) können von der Java-Version abweichen; nicht auswertbare Versionen sind kein Befund.
        Portable Installationen ohne Registry-Eintrag werden nicht erkannt. Begrenzte Liste (4000 Zeichen).
        Exit 0 = OK/Inventar, 1 = Eingabe-, Registry- oder Schreibfehler,
        2 = WarnIfPresent=true und Java gefunden, oder ein Eintrag liegt unter MinimumVersion.
    EN: Sources: 64-/32-bit HKLM uninstall keys (display name contains Java/JRE/JDK/OpenJDK/Temurin/Adoptium/Zulu/
        Corretto/Liberica; updaters excluded) and HKLM\SOFTWARE\JavaSoft (JRE/JDK version keys; family keys such as
        "1.8" or "17" are skipped when a more specific key exists).
        Vanished subkeys are skipped. Version normalization: "_" and "+" become ".",
        "1.8.0_391" -> 8.0.391, "Java 8 Update 391" -> 8.0.391. Vendor-specific schemes (e.g. Azul Zulu product
        version) may differ from the Java version; unparseable versions are not a finding.
        Portable installs without registry entries are not detected. Bounded list (4000 characters).
        Exit 0 = OK/inventory, 1 = input, registry or write error,
        2 = WarnIfPresent=true and Java found, or an entry is below MinimumVersion.
.PARAMETER WarnIfPresent
    DE: NinjaOne Checkbox/Text softwareJavaWarnIfPresent; true/false; Standard false.
    EN: NinjaOne checkbox/text softwareJavaWarnIfPresent; true/false; default false.
.PARAMETER MinimumVersion
    DE: NinjaOne Text softwareJavaMinimumVersion; optional; 1-4 numerische Komponenten (z. B. 17.0.9 oder 8.0.391); Standard leer.
    EN: NinjaOne Text softwareJavaMinimumVersion; optional; 1-4 numeric components (e.g. 17.0.9 or 8.0.391); default empty.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne Text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\readJavaInstallations.ps1
    DE: Inventar aller registrierten Java-Installationen.
    EN: Inventory of all registered Java installations.
.EXAMPLE
    .\readJavaInstallations.ps1 -MinimumVersion 8.0.401 -CustomField javaInventory
    DE: Exit 2, wenn eine Java-Version älter als 8.0.401 ist; JSON in javaInventory.
    EN: Exit 2 if any Java version is older than 8.0.401; JSON to javaInventory.
.EXAMPLE
    .\readJavaInstallations.ps1 -WarnIfPresent true
    DE: Exit 2, sobald irgendeine Java-Installation gefunden wird.
    EN: Exit 2 as soon as any Java installation is found.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen. Nur lesend; java.exe wird nicht gestartet.
        Exit 0 = OK, 1 = Fehler, 2 = Java vorhanden (WarnIfPresent) oder unter Mindestversion.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables. Read-only; java.exe is never started.
        Exit 0 = OK, 1 = error, 2 = Java present (WarnIfPresent) or below minimum version.
#>
[CmdletBinding()]
param(
    [string]$WarnIfPresent = $env:softwareJavaWarnIfPresent,
    [string]$MinimumVersion = $env:softwareJavaMinimumVersion,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-JavaVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match(($Text.Trim() -replace '[_+]', '.'), '^(\d+(?:\.\d+){0,3})')
    if (-not $match.Success) { return $null }
    $parts = @($match.Groups[1].Value.Split('.'))
    # DE: Altes Schema 1.x (bis Java 8) auf x abbilden. EN: Map legacy 1.x scheme (up to Java 8) to x.
    if ($parts.Count -ge 2 -and $parts[0] -eq '1' -and $parts[1].Length -le 2 -and [int]$parts[1] -le 8) { $parts = @($parts | Select-Object -Skip 1) }
    while ($parts.Count -lt 4) { $parts += '0' }
    $parsed = $null
    if ([version]::TryParse((($parts | Select-Object -First 4) -join '.'), [ref]$parsed)) { return $parsed }
    return $null
}
function Get-JavaVendor {
    param([string]$Text)
    $vendors = [ordered]@{
        'Eclipse Adoptium' = 'Adoptium|Temurin'; 'AdoptOpenJDK' = 'AdoptOpenJDK'; 'Azul Zulu' = 'Azul|Zulu'
        'Amazon Corretto' = 'Amazon|Corretto'; 'BellSoft Liberica' = 'BellSoft|Liberica'; 'Red Hat' = 'Red ?Hat'
        'Microsoft' = 'Microsoft'; 'Oracle' = 'Oracle|Java\(TM\)|\\Java\\'; 'OpenJDK' = 'OpenJDK'
    }
    foreach ($vendor in $vendors.Keys) { if ($Text -match $vendors[$vendor]) { return $vendor } }
    return 'Unknown'
}
function Get-RegistrySubkey {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $enumErrors = $null
    $keys = @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue -ErrorVariable enumErrors)
    foreach ($enumError in @($enumErrors)) {
        if ($enumError.Exception -isnot [System.Management.Automation.ItemNotFoundException]) { throw $enumError.Exception }
    }
    foreach ($key in $keys) {
        # DE: Während Installationen entfernte Schlüssel überspringen. EN: Skip keys removed during installs.
        try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { continue }
        [pscustomobject]@{ KeyName = [string]$key.PSChildName; Properties = $props }
    }
}
try {
    $WarnIfPresent = Resolve-Setting $WarnIfPresent 'false'
    $MinimumVersion = Resolve-Setting $MinimumVersion ''
    $CustomField = Resolve-Setting $CustomField ''
    $warnPresent = $false
    if (-not [bool]::TryParse($WarnIfPresent, [ref]$warnPresent)) { throw 'softwareJavaWarnIfPresent: true/false.' }
    $minimum = $null
    if ($MinimumVersion) {
        if ($MinimumVersion -notmatch '^\d{1,9}(\.\d{1,9}){0,3}$') { throw 'softwareJavaMinimumVersion: z. B. / e.g. 17.0.9' }
        $minimum = ConvertTo-JavaVersion $MinimumVersion
        if ($null -eq $minimum) { throw 'softwareJavaMinimumVersion ungültig / invalid.' }
    }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $views = [ordered]@{ x64 = 'HKLM:\SOFTWARE'; x86 = 'HKLM:\SOFTWARE\WOW6432Node' }
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($arch in $views.Keys) {
        foreach ($entry in @(Get-RegistrySubkey ($views[$arch] + '\Microsoft\Windows\CurrentVersion\Uninstall'))) {
            $name = ([string]$entry.Properties.DisplayName).Trim()
            if ($name -notmatch '(?i)\b(java|jre|jdk|openjdk|temurin|adoptium|zulu|corretto|liberica)\b' -or $name -match '(?i)updater|update scheduler') { continue }
            $legacy = [regex]::Match($name, '(?i)\b(?:Java|Kit)\s+(\d+)\s+Update\s+(\d+)')
            $version = if ($legacy.Success) { '{0}.0.{1}' -f $legacy.Groups[1].Value, $legacy.Groups[2].Value } else { [string]$entry.Properties.DisplayVersion }
            $found.Add([pscustomobject]@{ Source = 'Uninstall'; Name = $name; Vendor = Get-JavaVendor ('{0} {1}' -f $entry.Properties.Publisher, $name); Version = $version; Architecture = $arch; JavaHome = [string]$entry.Properties.InstallLocation })
        }
        foreach ($product in @('Java Runtime Environment', 'Java Development Kit', 'JRE', 'JDK')) {
            $subkeys = @(Get-RegistrySubkey ('{0}\JavaSoft\{1}' -f $views[$arch], $product))
            $names = @($subkeys | ForEach-Object { $_.KeyName })
            foreach ($subkey in $subkeys) {
                $keyName = $subkey.KeyName
                # DE: Familienschlüssel (1.8, 17) auslassen, wenn genauer vorhanden. EN: Skip family keys if a specific one exists.
                if (@($names | Where-Object { $_ -ne $keyName -and ($_.StartsWith($keyName + '.') -or $_.StartsWith($keyName + '_')) }).Count -gt 0) { continue }
                $javaHome = [string]$subkey.Properties.JavaHome
                $found.Add([pscustomobject]@{ Source = 'JavaSoft'; Name = $product; Vendor = Get-JavaVendor $javaHome; Version = $keyName; Architecture = $arch; JavaHome = $javaHome })
            }
        }
    }
    $belowCount = 0
    $all = @(foreach ($item in $found) {
        $normalized = ConvertTo-JavaVersion $item.Version
        $below = ($null -ne $minimum -and $null -ne $normalized -and $normalized -lt $minimum)
        if ($below) { $belowCount++ }
        $item | Add-Member -NotePropertyName NormalizedVersion -NotePropertyValue $(if ($normalized) { $normalized.ToString() } else { $null }) -PassThru |
            Add-Member -NotePropertyName BelowMinimum -NotePropertyValue $below -PassThru
    })
    $all = @($all | Sort-Object @{ Expression = { -not $_.BelowMinimum } }, Vendor, Name, Architecture)
    $records = @($all | Select-Object -First 50)
    do {
        $report = ConvertTo-Json -Depth 4 -InputObject ([ordered]@{
            Computer = $env:COMPUTERNAME; JavaPresent = $all.Count -gt 0; WarnIfPresent = $warnPresent
            MinimumVersion = if ($minimum) { $minimum.ToString() } else { $null }; TotalEntries = $all.Count
            BelowMinimumCount = $belowCount; ReportedRecords = $records.Count; Truncated = $records.Count -lt $all.Count
            Installations = $records
        })
        if ($report.Length -le 4000) { break }
        if ($records.Count -eq 0) { throw 'Bericht zu groß / Report too large.' }
        $records = @($records | Select-Object -First ($records.Count - 1))
    } while ($true)
    Write-Output $report
    if ($CustomField) {
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if (($warnPresent -and $all.Count -gt 0) -or $belowCount -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
