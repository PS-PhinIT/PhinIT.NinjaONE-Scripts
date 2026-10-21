#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Hinterlegt Netzwerk-Anmeldeinformationen für Server in der Windows-Anmeldeinformationsverwaltung des angemeldeten Benutzers.
    EN: Stores network credentials for servers in the logged-on user's Windows Credential Manager.
.DESCRIPTION
    DE: Für jedes Ziel in Targets (Servername, FQDN, IP-Adresse oder Platzhalter wie *.partner.local) wird geprüft,
        ob in der Anmeldeinformationsverwaltung des Benutzers eine Windows-Anmeldeinformation (Typ Domänenkennwort,
        wie "cmdkey /add") existiert und ob sie auf UserName lautet. Status: Present, DifferentUser oder Missing.
        Ohne Opt-in (configCredentialAllow=true) wird nichts geändert. Mit Opt-in wird innerhalb von ShouldProcess
        über die Windows-API CredWrite (advapi32) je Ziel die Anmeldeinformation angelegt bzw. überschrieben
        (Kennwortwechsel), Persistenz "Lokaler Computer", und erneut gelesen. Das Kennwort erscheint nicht in einer
        Befehlszeile (kein cmdkey), nicht im Bericht und nicht in der Ausgabe.
        Damit verbinden sich Netzlaufwerke (setNetworkDrives.ps1) auch mit einem Konto, das von der Windows-Anmeldung
        abweicht (z. B. fremde Domäne, NAS, Arbeitsgruppen-Server). Je Server ist nur ein Konto möglich.
        Kennwortquelle: entweder Password (Skriptvariable configCredentialPassword) oder PasswordField (interner Name
        eines NinjaOne-Custom-Fields, z. B. Typ "Sicher", gelesen mit Ninja-Property-Get); nicht beides.
        Die Anmeldeinformationsverwaltung gehört immer zum Benutzer: In NinjaOne mit "Ausführen als: Angemeldeter
        Benutzer" starten; unter SYSTEM bricht das Skript mit Exit 1 ab. Die Richtlinie "Netzwerkzugriff: Speicherung
        von Kennwörtern und Anmeldeinformationen für die Netzwerkauthentifizierung nicht zulassen" verhindert das Speichern.
        Bericht: Targets (Target, Before, After, StoredUserName, Changed, Error), UserName, PasswordSource, Compliant.
    EN: For every target in Targets (server name, FQDN, IP address or wildcard such as *.partner.local) the script
        checks whether the user's Credential Manager holds a Windows credential (domain password type, like
        "cmdkey /add") and whether it is for UserName. Status: Present, DifferentUser or Missing.
        Without opt-in (configCredentialAllow=true) nothing is changed. With opt-in the credential is created or
        overwritten (password change) per target through the Windows API CredWrite (advapi32) inside ShouldProcess,
        persistence "local computer", and read back. The password never appears on a command line (no cmdkey), in
        the report or in the output.
        This lets network drives (setNetworkDrives.ps1) connect with an account that differs from the Windows logon
        (e.g. another domain, NAS, workgroup server). Only one account per server is possible.
        Password source: either Password (script variable configCredentialPassword) or PasswordField (internal name of
        a NinjaOne custom field, e.g. type "Secure", read with Ninja-Property-Get); not both.
        Credential Manager always belongs to the user: run in NinjaOne with "Run As: Current Logged On User"; under
        SYSTEM the script stops with exit 1. The policy "Network access: Do not allow storage of passwords and
        credentials for network authentication" prevents storing.
        Report: Targets (Target, Before, After, StoredUserName, Changed, Error), UserName, PasswordSource, Compliant.
.PARAMETER Targets
    DE: NinjaOne Text configCredentialTargets; erforderlich; Servername, FQDN, IPv4 oder *.Domäne, mehrere durch Komma/Semikolon/Leerzeichen getrennt (z. B. "nas01,nas01.partner.local"); "\\Server\Freigabe" wird auf den Server gekürzt; Anführungszeichen werden ignoriert; max. 10.
    EN: NinjaOne text configCredentialTargets; required; server name, FQDN, IPv4 or *.domain, several separated by comma/semicolon/space (e.g. "nas01,nas01.partner.local"); "\\server\share" is reduced to the server; quotes are ignored; max. 10.
.PARAMETER UserName
    DE: NinjaOne Text configCredentialUserName; erforderlich; Konto als DOMÄNE\Benutzer, Server\Benutzer oder benutzer@domäne (max. 256 Zeichen).
    EN: NinjaOne text configCredentialUserName; required; account as DOMAIN\user, server\user or user@domain (max. 256 characters).
.PARAMETER Password
    DE: NinjaOne Text configCredentialPassword; Kennwort (max. 1024 Zeichen); nur mit Allow=true erforderlich, alternativ PasswordField. Wird nie ausgegeben.
    EN: NinjaOne text configCredentialPassword; password (max. 1024 characters); only required with Allow=true, alternatively PasswordField. Never output.
.PARAMETER PasswordField
    DE: NinjaOne Text configCredentialPasswordField; optional; interner Name eines Custom Fields mit dem Kennwort (Skript-Leserecht erforderlich). Ist der Wert kein vorhandenes Feld (ungültiger Name oder "Unable to find the specified field"), wird er selbst als Kennwort verwendet (PasswordSource=PasswordFieldValue). Wird nie ausgegeben.
    EN: NinjaOne text configCredentialPasswordField; optional; internal name of a custom field holding the password (script read permission required). If the value is no existing field (invalid name or "Unable to find the specified field"), it is used as the password itself (PasswordSource=PasswordFieldValue). Never output.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text configCredentialAllow; true/false; Standard false (nur Prüfung). Ausdrückliches Opt-in für Änderungen.
    EN: NinjaOne checkbox/text configCredentialAllow; true/false; default false (audit only). Explicit opt-in for changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes (Buchstabe zuerst, max. 100 Zeichen); Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field (letter first, max. 100 characters); default empty.
.EXAMPLE
    .\setNetworkCredentials.ps1 -Targets 'nas01,nas01.partner.local' -UserName 'PARTNER\svc-scan'
    DE: Nur Prüfung: Exit 2, wenn für ein Ziel keine Anmeldeinformation für PARTNER\svc-scan hinterlegt ist.
    EN: Audit only: exit 2 if a target has no credential for PARTNER\svc-scan.
.EXAMPLE
    .\setNetworkCredentials.ps1 -Targets 'nas01' -UserName 'nas01\backup' -PasswordField nasBackupPassword -Allow true
    DE: Liest das Kennwort aus dem Custom Field nasBackupPassword und hinterlegt es für nas01.
    EN: Reads the password from the custom field nasBackupPassword and stores it for nas01.
.EXAMPLE
    .\setNetworkCredentials.ps1 -Targets '*.partner.local' -UserName 'user@partner.local' -Password '<Kennwort>' -Allow true -WhatIf
    DE: Simuliert das Hinterlegen für alle Server der Domäne partner.local; nichts wird geändert (Exit 0).
    EN: Simulates storing for all servers of the partner.local domain; nothing is changed (exit 0).
.NOTES
    DE: Windows PowerShell 5.1, 64-Bit, als angemeldeter Benutzer (nicht SYSTEM). Explizite Parameter haben Vorrang;
        leer/'null' = nicht gesetzt. Kennwörter bevorzugt über ein gesichertes Custom Field übergeben.
        Bestehende Verbindungen nutzen neue Anmeldeinformationen erst nach dem Trennen bzw. der nächsten Anmeldung.
        Exit 0 = für alle Ziele hinterlegt (bereits vorhanden ohne Opt-in, erfolgreich geschrieben oder -WhatIf mit Opt-in);
        1 = Eingabe-, Abfrage-, Schreib- oder Verifikationsfehler oder Ausführung als SYSTEM;
        2 = fehlende oder abweichende Anmeldeinformation ohne Opt-in oder Änderung per -Confirm abgelehnt.
    EN: Windows PowerShell 5.1, 64-bit, as the logged-on user (not SYSTEM). Explicit parameters win; empty/'null' =
        not set. Prefer passing passwords through a secure custom field.
        Existing connections only use new credentials after disconnecting or the next sign-in.
        Exit 0 = stored for all targets (already present without opt-in, written successfully or -WhatIf with opt-in);
        1 = input, query, write or verification error, or run as SYSTEM;
        2 = missing or different credential without opt-in, or change declined via -Confirm.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'NinjaOne passes script variables as environment strings; the value is never output.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'PasswordField', Justification = 'Custom field name, not a secret.')]
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Targets = $env:configCredentialTargets,
    [string]$UserName = $env:configCredentialUserName,
    [string]$Password = $env:configCredentialPassword,
    [string]$PasswordField = $env:configCredentialPasswordField,
    [string]$Allow = $env:configCredentialAllow,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-BooleanSetting {
    param([string]$Value, [string]$Name)
    $result = $false
    if (-not [bool]::TryParse($Value, [ref]$result)) { throw ('{0}: true/false erforderlich / required.' -f $Name) }
    return $result
}
function Test-IsSystem {
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18' }
    catch { return [string]$env:USERNAME -eq ('{0}$' -f $env:COMPUTERNAME) }
}
function ConvertTo-CredentialTarget {
    param([string]$Text)
    $list = @()
    foreach ($entry in @($Text -split '[,;\s]+' | Where-Object { $_ })) {
        # DE: Anführungszeichen aus der NinjaOne-Eingabe entfernen ('192.168.1.10'). EN: Strip quotes typed into NinjaOne.
        $target = $entry.Trim([char[]]@([char]39, [char]34))
        if (-not $target) { continue }
        if ($target -match '^\\\\([^\\]+)') { $target = $Matches[1] }
        if ($target.Length -gt 253 -or $target -notmatch '^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$') {
            throw ('configCredentialTargets: Servername, FQDN, IPv4 oder / or *.domain erwartet / expected: {0}' -f $entry)
        }
        if (@($list | Where-Object { $_ -eq $target }).Count -eq 0) { $list += $target }
    }
    if ($list.Count -eq 0) { throw 'configCredentialTargets erforderlich / required.' }
    if ($list.Count -gt 10) { throw 'configCredentialTargets: max. 10.' }
    return $list
}
function Initialize-CredentialVault {
    if ('PhinIT.CredentialVault' -as [type]) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace PhinIT {
    public static class CredentialVault {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
        private const int CredTypeDomainPassword = 2;
        private const int CredPersistLocalMachine = 2;
        private const int ErrorNotFound = 1168;
        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);
        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref NativeCredential credential, int flags);
        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);
        public static string GetUserName(string target) {
            IntPtr pointer;
            if (!CredRead(target, CredTypeDomainPassword, 0, out pointer)) {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrorNotFound) { return null; }
                throw new Win32Exception(error);
            }
            try {
                NativeCredential credential = (NativeCredential)Marshal.PtrToStructure(pointer, typeof(NativeCredential));
                return credential.UserName ?? string.Empty;
            } finally { CredFree(pointer); }
        }
        public static void Write(string target, string userName, string password) {
            byte[] blob = System.Text.Encoding.Unicode.GetBytes(password);
            IntPtr buffer = Marshal.AllocHGlobal(blob.Length);
            try {
                Marshal.Copy(blob, 0, buffer, blob.Length);
                NativeCredential credential = new NativeCredential();
                credential.Type = CredTypeDomainPassword;
                credential.TargetName = target;
                credential.UserName = userName;
                credential.Comment = "PhinIT NinjaOne";
                credential.CredentialBlob = buffer;
                credential.CredentialBlobSize = blob.Length;
                credential.Persist = CredPersistLocalMachine;
                if (!CredWrite(ref credential, 0)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
            } finally {
                Marshal.Copy(new byte[blob.Length], 0, buffer, blob.Length);
                Marshal.FreeHGlobal(buffer);
                Array.Clear(blob, 0, blob.Length);
            }
        }
    }
}
'@
}
function Get-CredentialState {
    param([string]$Target, [string]$Expected)
    $stored = [PhinIT.CredentialVault]::GetUserName($Target)
    $status = if ($null -eq $stored) { 'Missing' } elseif ($stored -eq $Expected) { 'Present' } else { 'DifferentUser' }
    [pscustomobject]@{ Status = $status; UserName = $stored }
}
try {
    $Targets = Resolve-Setting $Targets ''
    $UserName = Resolve-Setting $UserName ''
    if ($UserName -match '^([''"])(.*)\1$') { $UserName = $Matches[2].Trim() }
    $PasswordField = Resolve-Setting $PasswordField ''
    $Allow = Resolve-Setting $Allow 'false'
    $CustomField = Resolve-Setting $CustomField ''
    # DE: Kennwort nicht trimmen (Leerzeichen sind gültig). EN: Do not trim the password (spaces are valid).
    if ([string]::IsNullOrEmpty($Password) -or $Password -eq 'null') { $Password = '' }
    $targetList = @(ConvertTo-CredentialTarget $Targets)
    if (-not $UserName -or $UserName.Length -gt 256 -or $UserName -match '[\x00-\x1f"/\[\]:;|=,+*?<>]') {
        throw 'configCredentialUserName erforderlich (DOMÄNE\Benutzer oder benutzer@domäne, max. 256 Zeichen) / required (DOMAIN\user or user@domain, max. 256 characters).'
    }
    $allowed = ConvertTo-BooleanSetting $Allow 'configCredentialAllow'
    if ($Password -and $PasswordField) { throw 'configCredentialPassword oder / or configCredentialPasswordField, nicht beides / not both.' }
    # DE: Kein gültiger Feldname = Kennwort wurde direkt eingetragen. EN: Not a valid field name = password was entered directly.
    $passwordIsFieldValue = $PasswordField -and $PasswordField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$'
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
    if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }
    if (Test-IsSystem) { throw 'Als angemeldeter Benutzer ausführen, nicht als SYSTEM / Run as the logged-on user, not as SYSTEM.' }

    $passwordSource = if ($passwordIsFieldValue) { 'PasswordFieldValue' } elseif ($PasswordField) { 'CustomField' } elseif ($Password) { 'Parameter' } else { $null }
    if ($allowed) {
        if ($PasswordField -and -not $passwordIsFieldValue) {
            if (-not (Get-Command Ninja-Property-Get -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Get fehlt / unavailable.' }
            # DE: Fehlertexte von Ninja-Property-Get enthalten den Feldwert (evtl. das Kennwort) und werden nie ausgegeben.
            # EN: Ninja-Property-Get error texts contain the field value (possibly the password) and are never output.
            $notFoundPattern = 'Unable to find the specified field'
            $fieldMissing = $false
            $fieldValue = $null
            try {
                $global:LASTEXITCODE = 0
                $fieldValue = ([string](@(Ninja-Property-Get $PasswordField 2>&1) -join "`n")).TrimEnd("`r", "`n")
                if ($fieldValue -match $notFoundPattern) { $fieldMissing = $true }
                elseif ($global:LASTEXITCODE -ne 0) { throw 'not readable' }
            }
            catch {
                if ($_.Exception.Message -match $notFoundPattern) { $fieldMissing = $true }
                else { throw 'Custom Field nicht lesbar / Custom field not readable (configCredentialPasswordField).' }
            }
            if ($fieldMissing) {
                # DE: Kein solches Feld = Wert ist das Kennwort selbst. EN: No such field = the value is the password itself.
                $Password = $PasswordField
                $passwordSource = 'PasswordFieldValue'
            }
            else { $Password = $fieldValue }
            $fieldValue = $null
        }
        elseif ($passwordIsFieldValue) { $Password = $PasswordField }
        if (-not $Password) { throw 'Kennwort erforderlich (configCredentialPassword oder configCredentialPasswordField) / Password required.' }
        if ($Password.Length -gt 1024 -or $Password.Contains([char]0)) { throw 'Kennwort ungültig (max. 1024 Zeichen) / Invalid password (max. 1024 characters).' }
    }

    Initialize-CredentialVault
    $results = @()
    foreach ($target in $targetList) {
        $result = [ordered]@{ Target = $target; Before = $null; After = $null; StoredUserName = $null; Changed = $false; Error = $null }
        try {
            $state = Get-CredentialState -Target $target -Expected $UserName
            $result.Before = $state.Status
            $result.After = $state.Status
            $result.StoredUserName = $state.UserName
            if ($allowed -and $PSCmdlet.ShouldProcess($target, ('Anmeldeinformation hinterlegen für / Store credential for {0}' -f $UserName))) {
                [PhinIT.CredentialVault]::Write($target, $UserName, $Password)
                $result.Changed = $true
                $state = Get-CredentialState -Target $target -Expected $UserName
                $result.After = $state.Status
                $result.StoredUserName = $state.UserName
                if ($state.Status -ne 'Present') { $result.Error = ('Verifikation fehlgeschlagen / Verification failed: {0}' -f $state.Status) }
            }
        }
        catch { $result.Error = $_.Exception.Message }
        $results += [pscustomobject]$result
    }
    $Password = $null

    $errors = @($results | Where-Object { $_.Error })
    $compliant = @($results | Where-Object { $_.After -ne 'Present' }).Count -eq 0
    $exitCode = 0
    if ($errors.Count -gt 0) { $exitCode = 1 }
    elseif (-not $compliant -and -not ($allowed -and $WhatIfPreference)) { $exitCode = 2 }

    $report = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        Computer = $env:COMPUTERNAME; User = $env:USERNAME; Setting = 'NetworkCredentials'; UserName = $UserName
        PasswordSource = $passwordSource; Compliant = $compliant; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; Targets = @($results)
    })
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    exit $exitCode
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
