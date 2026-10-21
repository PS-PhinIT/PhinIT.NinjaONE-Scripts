BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:drivesScript = Join-Path $root '09 - Configuration/setNetworkDrives.ps1'
    $script:credentialScript = Join-Path $root '09 - Configuration/setNetworkCredentials.ps1'
    # DE: Stubs erlauben Mocks ohne Windows/NinjaOne. EN: Stubs allow mocks without Windows/NinjaOne.
    function net { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }
    function Ninja-Property-Get { param($Name) }
    # DE: Ersatz für die Anmeldeinformationsverwaltung (das Skript lädt den Typ nur, wenn er fehlt).
    # EN: Fake Credential Manager (the script only loads the type when it is missing).
    if (-not ('PhinIT.CredentialVault' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
namespace PhinIT {
    public static class CredentialVault {
        public static Dictionary<string, string[]> Store = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        public static string FailWith = null;
        public static int Writes = 0;
        public static string GetUserName(string target) {
            string[] value;
            return Store.TryGetValue(target, out value) ? value[0] : null;
        }
        public static void Write(string target, string userName, string password) {
            if (!string.IsNullOrEmpty(FailWith)) { throw new InvalidOperationException(FailWith); }
            Writes++;
            Store[target] = new string[] { userName, password };
        }
    }
}
'@
    }
    function Test-ScriptHelp {
        param([string]$Path, [string]$Synopsis)
        $bytes = [IO.File]::ReadAllBytes($Path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
        (Get-Help $Path).Synopsis | Should -Match $Synopsis
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Network drives and credentials / Netzlaufwerke und Anmeldeinformationen' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('configNetworkDrives', 'configNetworkDrivesReplace', 'configNetworkDrivesAllow', 'configCredentialTargets',
                'configCredentialUserName', 'configCredentialPassword', 'configCredentialPasswordField', 'configCredentialAllow',
                'resultCustomField', 'USERNAME', 'COMPUTERNAME')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:USERNAME = 'alice'
        $env:COMPUTERNAME = 'PC01'
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'setNetworkDrives.ps1' {
        BeforeEach {
            # DE: Persistent = HKCU:\Network, Connected = aktuelle Laufwerke. EN: Persistent = HKCU:\Network, Connected = current drives.
            $driveFake = @{ Persistent = @{}; Connected = @{}; Local = @(); FailMap = $false }
            Mock Test-Path { $driveFake.Persistent.ContainsKey(([string]$LiteralPath -replace '^HKCU:\\Network\\', '')) }
            Mock Get-ItemProperty { [pscustomobject]@{ RemotePath = $driveFake.Persistent[([string]$LiteralPath -replace '^HKCU:\\Network\\', '')] } }
            Mock Get-PSDrive {
                if ($driveFake.Local -contains $Name) { return [pscustomobject]@{ Name = $Name; DisplayRoot = $null } }
                if ($driveFake.Connected.ContainsKey([string]$Name)) { return [pscustomobject]@{ Name = $Name; DisplayRoot = $driveFake.Connected[[string]$Name] } }
            }
            Mock net {
                $letter = ([string]$Arguments[1]).TrimEnd(':')
                if ($Arguments -contains '/delete') {
                    $driveFake.Persistent.Remove($letter); $driveFake.Connected.Remove($letter)
                } elseif ($driveFake.FailMap) {
                    $global:LASTEXITCODE = 2; return 'Systemfehler 53 aufgetreten.'
                } else {
                    $driveFake.Persistent[$letter] = [string]$Arguments[2]; $driveFake.Connected[$letter] = [string]$Arguments[2]
                }
                $global:LASTEXITCODE = 0
            }
        }

        It 'has UTF-8 BOM and parsable help / hat BOM und lesbare Hilfe' {
            Test-ScriptHelp -Path $script:drivesScript -Synopsis 'DE: Prüft Netzlaufwerke'
        }
        It 'only audits by default / prüft standardmäßig nur' {
            $driveFake.Persistent['P'] = '\\fs01\projekte'
            $driveFake.Connected['P'] = '\\fs01\projekte'
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte\; s:=\\fs01\scan$' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Compliant | Should -BeFalse
            ($report.Drives | Where-Object Letter -eq 'P').Before | Should -Be 'OK'
            ($report.Drives | Where-Object Letter -eq 'S').Before | Should -Be 'Missing'
            Should -Invoke net -Times 0 -Exactly
        }
        It 'maps missing drives persistently / verbindet fehlende Laufwerke dauerhaft' {
            $env:configNetworkDrives = "P=\\fs01\projekte`nS=\\fs01.contoso.local\scan$"
            $env:configNetworkDrivesAllow = 'true'
            $report = & $script:drivesScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Compliant | Should -BeTrue
            @($report.Drives | Where-Object { $_.Changed -and $_.After -eq 'OK' }).Count | Should -Be 2
            Should -Invoke net -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'use P: \\fs01\projekte /persistent:yes' }
            Should -Invoke net -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'use S: \\fs01.contoso.local\scan$ /persistent:yes' }
        }
        It 'makes a temporary connection persistent / macht temporäre Verbindung dauerhaft' {
            $driveFake.Connected['P'] = '\\fs01\projekte'
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Drives[0].Before | Should -Be 'NotPersistent'
            Should -Invoke net -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'use P: /delete /y' }
        }
        It 'replaces conflicts only with Replace / ersetzt Konflikte nur mit Replace' {
            $driveFake.Persistent['P'] = '\\old\share'
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Drives[0].After | Should -Be 'Conflict'
            $report.Drives[0].CurrentPath | Should -Be '\\old\share'
            Should -Invoke net -Times 0 -Exactly
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true -Replace true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Drives[0].After | Should -Be 'OK'
            Should -Invoke net -Times 2 -Exactly
        }
        It 'never replaces a local drive / ersetzt nie lokale Laufwerke' {
            $driveFake.Local = @('D')
            $report = & $script:drivesScript -NetworkDrives 'D=\\fs01\daten' -Allow true -Replace true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $report.Drives[0].Before | Should -Be 'LocalDrive'
            $report.Drives[0].Error | Should -Match 'local drive'
            Should -Invoke net -Times 0 -Exactly
        }
        It 'reports net use errors / meldet net-use-Fehler' {
            $driveFake.FailMap = $true
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $report.Drives[0].Error | Should -Match 'Systemfehler 53'
        }
        It 'simulates with -WhatIf / simuliert mit -WhatIf' {
            $report = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WhatIf | Should -BeTrue
            Should -Invoke net -Times 0 -Exactly
        }
        It 'refuses to run as SYSTEM / verweigert Ausführung als SYSTEM' {
            $env:USERNAME = 'PC01$'
            $output = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'SYSTEM'
            Should -Invoke net -Times 0 -Exactly
        }
        It 'rejects invalid input / lehnt ungültige Eingaben ab' {
            foreach ($case in @(@{ NetworkDrives = '' }, @{ NetworkDrives = 'P' }, @{ NetworkDrives = 'C=\\fs01\c' }, @{ NetworkDrives = 'P=C:\Daten' },
                    @{ NetworkDrives = 'P=\\fs01' }, @{ NetworkDrives = 'P=\\fs01\a;P=\\fs01\b' }, @{ NetworkDrives = 'P=\\fs01\..\x' },
                    @{ NetworkDrives = 'P=\\fs01\a'; Allow = 'yes' }, @{ NetworkDrives = 'P=\\fs01\a'; Replace = 'maybe' }, @{ NetworkDrives = 'P=\\fs01\a'; CustomField = '1x' })) {
                $null = & $script:drivesScript @case
                $LASTEXITCODE | Should -Be 1 -Because ($case | ConvertTo-Json -Compress)
            }
            Should -Invoke net -Times 0 -Exactly
        }
        It 'writes the custom field / schreibt das Custom Field' {
            $null = & $script:drivesScript -NetworkDrives 'P=\\fs01\projekte' -Allow true -CustomField driveReport
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'driveReport' -and ($Value | ConvertFrom-Json).Compliant }
        }
    }

    Context 'setNetworkCredentials.ps1' {
        BeforeEach {
            [PhinIT.CredentialVault]::Store.Clear()
            [PhinIT.CredentialVault]::FailWith = $null
            [PhinIT.CredentialVault]::Writes = 0
            Mock Ninja-Property-Get { 'Feld-Geheim!1' }
        }

        It 'has UTF-8 BOM and parsable help / hat BOM und lesbare Hilfe' {
            Test-ScriptHelp -Path $script:credentialScript -Synopsis 'DE: Hinterlegt Netzwerk-Anmeldeinformationen'
        }
        It 'only audits by default / prüft standardmäßig nur' {
            [PhinIT.CredentialVault]::Store['nas01'] = @('PARTNER\svc-scan', 'x')
            [PhinIT.CredentialVault]::Store['nas02'] = @('PARTNER\other', 'x')
            $report = & $script:credentialScript -Targets 'nas01, nas02;\\nas03\share' -UserName 'partner\SVC-SCAN' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Targets.Target) | Should -Be @('nas01', 'nas02', 'nas03')
            @($report.Targets.Before) | Should -Be @('Present', 'DifferentUser', 'Missing')
            [PhinIT.CredentialVault]::Writes | Should -Be 0
        }
        It 'stores credentials without exposing the password / speichert ohne Kennwort-Ausgabe' {
            $env:configCredentialTargets = 'nas01,nas01.partner.local'
            $env:configCredentialUserName = 'PARTNER\svc-scan'
            $env:configCredentialPassword = ' Geheim!23 '
            $env:configCredentialAllow = 'true'
            $env:resultCustomField = 'credentialReport'
            $output = & $script:credentialScript
            $LASTEXITCODE | Should -Be 0
            ($output -join ' ') | Should -Not -Match 'Geheim'
            $report = $output | ConvertFrom-Json
            $report.Compliant | Should -BeTrue
            $report.PasswordSource | Should -Be 'Parameter'
            @($report.Targets | Where-Object { $_.Changed -and $_.After -eq 'Present' }).Count | Should -Be 2
            [PhinIT.CredentialVault]::Store['nas01.partner.local'] | Should -Be @('PARTNER\svc-scan', ' Geheim!23 ')
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'credentialReport' -and $Value -notmatch 'Geheim' }
        }
        It 'reads the password from a custom field / liest das Kennwort aus einem Custom Field' {
            [PhinIT.CredentialVault]::Store['nas01'] = @('nas01\backup', 'alt')
            $report = & $script:credentialScript -Targets 'nas01' -UserName 'nas01\backup' -PasswordField nasPassword -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.PasswordSource | Should -Be 'CustomField'
            $report.Targets[0].Before | Should -Be 'Present'
            [PhinIT.CredentialVault]::Store['nas01'][1] | Should -Be 'Feld-Geheim!1'
            Should -Invoke Ninja-Property-Get -Times 1 -Exactly -ParameterFilter { $Name -eq 'nasPassword' }
        }
        It 'supports wildcard targets and -WhatIf / unterstützt Platzhalter und -WhatIf' {
            $report = & $script:credentialScript -Targets '*.partner.local' -UserName 'user@partner.local' -Password 'x' -Allow true -WhatIf | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Targets[0].Target | Should -Be '*.partner.local'
            [PhinIT.CredentialVault]::Writes | Should -Be 0
        }
        It 'reports write errors / meldet Schreibfehler' {
            [PhinIT.CredentialVault]::FailWith = 'Zugriff verweigert'
            $report = & $script:credentialScript -Targets 'nas01' -UserName 'nas01\backup' -Password 'x' -Allow true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $report.Targets[0].Error | Should -Match 'Zugriff verweigert'
        }
        It 'refuses to run as SYSTEM / verweigert Ausführung als SYSTEM' {
            $env:USERNAME = 'PC01$'
            $output = & $script:credentialScript -Targets 'nas01' -UserName 'nas01\backup' -Password 'x' -Allow true
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'SYSTEM'
            [PhinIT.CredentialVault]::Writes | Should -Be 0
        }
        It 'rejects invalid input / lehnt ungültige Eingaben ab' {
            foreach ($case in @(@{ UserName = 'a\b' }, @{ Targets = 'nas01' }, @{ Targets = 'nas 01!'; UserName = 'a\b' }, @{ Targets = 'nas01'; UserName = 'a"b' },
                    @{ Targets = 'nas01'; UserName = 'a\b'; Allow = 'true' }, @{ Targets = 'nas01'; UserName = 'a\b'; Password = 'x'; PasswordField = 'pw' },
                    @{ Targets = 'nas01'; UserName = 'a\b'; PasswordField = '1pw' }, @{ Targets = 'nas01'; UserName = 'a\b'; Allow = 'yes' },
                    @{ Targets = (1..11 | ForEach-Object { "nas$_" }) -join ','; UserName = 'a\b' })) {
                $output = & $script:credentialScript @case
                $LASTEXITCODE | Should -Be 1 -Because ($case | ConvertTo-Json -Compress)
                ($output -join ' ') | Should -Not -Match '"Targets"'
            }
            [PhinIT.CredentialVault]::Writes | Should -Be 0
        }
    }
}
