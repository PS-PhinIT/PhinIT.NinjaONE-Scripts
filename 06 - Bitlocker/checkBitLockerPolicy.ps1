#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Liest die BitLocker-Gruppenrichtlinienwerte (FVE) und dekodiert sie in Namen.
    EN: Reads BitLocker Group Policy (FVE) values and decodes them to names.
.DESCRIPTION
    DE: Liest HKLM\SOFTWARE\Policies\Microsoft\FVE sowie HKLM\SYSTEM\CurrentControlSet\Policies\
        Microsoft\FVE (dort liegen RDVDenyWriteAccess/FDVDenyWriteAccess). Bekannte Werte werden
        dekodiert: EncryptionMethodWithXtsOs/Fdv/Rdv (3 Aes128, 4 Aes256, 6 XtsAes128,
        7 XtsAes256), UseTPM/UseTPMPIN/UseTPMKey/UseTPMKeyPIN und *RecoveryPassword/*RecoveryKey
        (0 DoNotAllow, 1 Require, 2 Allow), *EncryptionType (0 AllowUserChoice, 1 FullEncryption,
        2 UsedSpaceOnly), *ActiveDirectoryInfoToStore (1 PasswordsAndKeyPackages, 2 PasswordsOnly),
        Schalter (0 Disabled, 1 Enabled), MinimumPIN als Zahl. Andere Wertnamen werden nur namentlich
        gelistet. Stärke-Rangfolge für den Mindestvergleich: Aes128 < XtsAes128 < Aes256 < XtsAes256
        (Schlüssellänge vor Modus). Richtlinien wirken erst bei neuer Verschlüsselung.
    EN: Reads HKLM\SOFTWARE\Policies\Microsoft\FVE and HKLM\SYSTEM\CurrentControlSet\Policies\
        Microsoft\FVE (where RDVDenyWriteAccess/FDVDenyWriteAccess live). Known values are
        decoded: EncryptionMethodWithXtsOs/Fdv/Rdv (3 Aes128, 4 Aes256, 6 XtsAes128,
        7 XtsAes256), UseTPM/UseTPMPIN/UseTPMKey/UseTPMKeyPIN and *RecoveryPassword/*RecoveryKey
        (0 DoNotAllow, 1 Require, 2 Allow), *EncryptionType (0 AllowUserChoice, 1 FullEncryption,
        2 UsedSpaceOnly), *ActiveDirectoryInfoToStore (1 PasswordsAndKeyPackages, 2 PasswordsOnly),
        switches (0 Disabled, 1 Enabled), MinimumPIN as number. Other value names are only listed
        by name. Strength order for the minimum comparison: Aes128 < XtsAes128 < Aes256 < XtsAes256
        (key length before mode). Policies only apply to newly started encryption.
.PARAMETER ExpectedMinimumMethod
    DE: NinjaOne Text bitlockerExpectedMinimumMethod; Aes128, XtsAes128, Aes256 oder XtsAes256;
        Standard leer = kein Mindestvergleich. Geprüft werden EncryptionMethodWithXtsOs und -Fdv.
    EN: NinjaOne Text bitlockerExpectedMinimumMethod; Aes128, XtsAes128, Aes256 or XtsAes256;
        default empty = no minimum comparison. EncryptionMethodWithXtsOs and -Fdv are checked.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkBitLockerPolicy.ps1
    DE: Listet dekodierte FVE-Richtlinienwerte; Exit 2, wenn keine Richtlinie konfiguriert ist.
    EN: Lists decoded FVE policy values; exit 2 if no policy is configured.
.EXAMPLE
    .\checkBitLockerPolicy.ps1 -ExpectedMinimumMethod XtsAes256 -CustomField bitlockerPolicy
    DE: Verlangt XTS-AES 256 für OS- und feste Datenlaufwerke; JSON ins Feld bitlockerPolicy.
    EN: Requires XTS-AES 256 for OS and fixed data drives; JSON to field bitlockerPolicy.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Nur lesend.
        Exit 0 = Richtlinie vorhanden (und ggf. Mindestverfahren erfüllt), 1 = Eingabe-/Abfrage-/
        Schreibfehler, 2 = keine bekannten FVE-Werte konfiguriert oder OS/Fdv-Verfahren fehlt bzw.
        ist schwächer als ExpectedMinimumMethod.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Read-only.
        Exit 0 = policy present (and minimum method met if requested), 1 = input/query/write
        error, 2 = no known FVE values configured or OS/Fdv method missing or weaker than
        ExpectedMinimumMethod.
#>
[CmdletBinding()]
param(
    [string]$ExpectedMinimumMethod = $env:bitlockerExpectedMinimumMethod,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
try {
    $ExpectedMinimumMethod = ([string]$ExpectedMinimumMethod).Trim()
    $CustomField = ([string]$CustomField).Trim()
    if ($ExpectedMinimumMethod -ieq 'null') { $ExpectedMinimumMethod = '' }
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    $methodNames = @{ 3 = 'Aes128'; 4 = 'Aes256'; 6 = 'XtsAes128'; 7 = 'XtsAes256' }
    $rank = @{ 'Aes128' = 1; 'XtsAes128' = 2; 'Aes256' = 3; 'XtsAes256' = 4 }
    $minimumRank = 0
    if ($ExpectedMinimumMethod) {
        $hit = @($rank.Keys | Where-Object { $_ -ieq $ExpectedMinimumMethod })
        if ($hit.Count -ne 1) { throw 'bitlockerExpectedMinimumMethod: Aes128, XtsAes128, Aes256, XtsAes256.' }
        $ExpectedMinimumMethod = $hit[0]
        $minimumRank = $rank[$ExpectedMinimumMethod]
    }
    $maps = @{
        Method = $methodNames
        Legacy = @{ 1 = 'Aes128Diffuser'; 2 = 'Aes256Diffuser'; 3 = 'Aes128'; 4 = 'Aes256' }
        Tri = @{ 0 = 'DoNotAllow'; 1 = 'Require'; 2 = 'Allow' }
        Bool = @{ 0 = 'Disabled'; 1 = 'Enabled' }
        Type = @{ 0 = 'AllowUserChoice'; 1 = 'FullEncryption'; 2 = 'UsedSpaceOnly' }
        Store = @{ 1 = 'PasswordsAndKeyPackages'; 2 = 'PasswordsOnly' }
    }
    $definitions = [ordered]@{
        EncryptionMethodWithXtsOs = 'Method'; EncryptionMethodWithXtsFdv = 'Method'; EncryptionMethodWithXtsRdv = 'Method'
        EncryptionMethod = 'Legacy'; UseAdvancedStartup = 'Bool'; EnableBDEWithNoTPM = 'Bool'
        UseTPM = 'Tri'; UseTPMPIN = 'Tri'; UseTPMKey = 'Tri'; UseTPMKeyPIN = 'Tri'; UseEnhancedPin = 'Bool'; MinimumPIN = 'Number'
        OSEncryptionType = 'Type'; FDVEncryptionType = 'Type'; RDVEncryptionType = 'Type'
        OSRecovery = 'Bool'; OSManageDRA = 'Bool'; OSRecoveryPassword = 'Tri'; OSRecoveryKey = 'Tri'; OSHideRecoveryPage = 'Bool'
        OSActiveDirectoryBackup = 'Bool'; OSActiveDirectoryInfoToStore = 'Store'; OSRequireActiveDirectoryBackup = 'Bool'
        FDVRecovery = 'Bool'; FDVRecoveryPassword = 'Tri'; FDVRecoveryKey = 'Tri'; FDVActiveDirectoryBackup = 'Bool'
        FDVActiveDirectoryInfoToStore = 'Store'; FDVRequireActiveDirectoryBackup = 'Bool'; FDVDenyWriteAccess = 'Bool'
        RDVConfigureBDE = 'Bool'; RDVAllowBDE = 'Bool'; RDVDisableBDE = 'Bool'; RDVRecovery = 'Bool'
        RDVRecoveryPassword = 'Tri'; RDVRecoveryKey = 'Tri'; RDVActiveDirectoryBackup = 'Bool'
        RDVActiveDirectoryInfoToStore = 'Store'; RDVRequireActiveDirectoryBackup = 'Bool'
        RDVDenyWriteAccess = 'Bool'; RDVDenyCrossOrg = 'Bool'
    }
    $raw = @{}
    $other = New-Object System.Collections.Generic.List[string]
    # DE: SYSTEM-Pfad zuletzt lesen, damit dessen Deny-Write-Werte Vorrang haben.
    # EN: Read the SYSTEM path last so its deny-write values take precedence.
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\FVE', 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE')) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-ItemProperty -LiteralPath $path
        if ($null -eq $item) { continue }
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $known = @($definitions.Keys | Where-Object { $_ -ieq $property.Name })
            if ($known.Count -eq 1) { $raw[$known[0]] = $property.Value }
            elseif (-not $other.Contains($property.Name) -and $other.Count -lt 30) { $other.Add($property.Name) }
        }
    }
    $values = [ordered]@{}
    foreach ($name in $definitions.Keys) {
        if (-not $raw.ContainsKey($name)) { continue }
        $number = 0
        if (-not [int]::TryParse([string]$raw[$name], [ref]$number)) { $values[$name] = 'Invalid'; continue }
        $kind = $definitions[$name]
        if ($kind -eq 'Number') { $values[$name] = [string]$number; continue }
        $text = $maps[$kind][$number]
        if (-not $text) { $text = 'Unknown' }
        $values[$name] = '{0} ({1})' -f $text, $number
    }
    $findings = @()
    if ($values.Count -eq 0) { $findings += 'NotConfigured' }
    if ($minimumRank -gt 0) {
        foreach ($name in @('EncryptionMethodWithXtsOs', 'EncryptionMethodWithXtsFdv')) {
            $number = 0
            if (-not $raw.ContainsKey($name) -or -not [int]::TryParse([string]$raw[$name], [ref]$number) -or -not $methodNames.ContainsKey($number)) {
                $findings += "${name}:NotConfigured"
            } elseif ($rank[$methodNames[$number]] -lt $minimumRank) {
                $findings += "${name}:WeakerThan$ExpectedMinimumMethod"
            }
        }
    }
    $report = ConvertTo-Json -InputObject ([ordered]@{
        PolicyConfigured = ($values.Count -gt 0); ExpectedMinimumMethod = $ExpectedMinimumMethod
        Findings = $findings; Values = $values; OtherValueNames = @($other)
    }) -Depth 4 -Compress
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
