BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $lapsScript = Join-Path $root '07 - Security/checkLapsStatus.ps1'
    $rdpScript = Join-Path $root '07 - Security/checkRdpSecurity.ps1'
    $passwordScript = Join-Path $root '07 - Security/checkPasswordPolicy.ps1'
    $auditScript = Join-Path $root '07 - Security/checkAuditPolicy.ps1'
    $logonScript = Join-Path $root '07 - Security/readFailedLogons.ps1'
    $accountScript = Join-Path $root '07 - Security/checkBuiltinAccounts.ps1'
    $asrScript = Join-Path $root '07 - Security/checkDefenderAsrRules.ps1'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $MaxEvents) }
    function Get-LocalUser { [CmdletBinding()] param() }
    function Get-MpPreference { [CmdletBinding()] param() }
    function secedit { $global:LASTEXITCODE = 0 }
    function auditpol { $global:LASTEXITCODE = 0 }
    function Ninja-Property-Set { param($Name, $Value) }
    function New-TestEvent {
        param([int]$Id, [datetime]$Time, [hashtable]$Data = @{})
        $body = ($Data.GetEnumerator() | ForEach-Object { "<Data Name='{0}'>{1}</Data>" -f $_.Key, $_.Value }) -join ''
        $item = [pscustomobject]@{ Id = $Id; TimeCreated = $Time; Xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData>$body</EventData></Event>" }
        $item | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
        $item
    }
    $auditHeader = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting'
    $auditRows = @(
        'PC1,System,Credential Validation,{0CCE923F-69AE-11D9-BED3-505054503030},Success and Failure,'
        'PC1,System,Logon,{0CCE9215-69AE-11D9-BED3-505054503030},Success and Failure,'
        'PC1,System,Account Lockout,{0CCE9217-69AE-11D9-BED3-505054503030},Failure,'
        'PC1,System,User Account Management,{0CCE9235-69AE-11D9-BED3-505054503030},Success and Failure,'
        'PC1,System,Security Group Management,{0CCE9237-69AE-11D9-BED3-505054503030},Success,'
        'PC1,System,Process Creation,{0CCE922B-69AE-11D9-BED3-505054503030},Success,'
        'PC1,System,Audit Policy Change,{0CCE922F-69AE-11D9-BED3-505054503030},Success,'
    )
    $secpol = @('[Unicode]', 'Unicode=yes', '[System Access]', 'MinimumPasswordAge = 1', 'MaximumPasswordAge = -1',
        'MinimumPasswordLength = 14', 'PasswordComplexity = 1', 'PasswordHistorySize = 24', 'LockoutBadCount = 5',
        'ResetLockoutCount = 15', 'LockoutDuration = 15', 'ClearTextPassword = 0', '[Version]', 'signature="$CHICAGO$"')
}
Describe 'Security catalogue B / Sicherheitskatalog B' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('securityLapsMaxSuccessAgeDays', 'securityRdpAllow', 'securityPasswordMinLength', 'securityPasswordRequireComplexity',
                'securityPasswordMinHistory', 'securityPasswordMaxAgeDays', 'securityLockoutMaxThreshold', 'securityAuditRequiredSubcategories',
                'securityFailedLogonHours', 'securityFailedLogonThreshold', 'securityFailedLogonMaxEvents', 'securityFailedLogonMaxRecords',
                'securityAllowBuiltinAdminEnabled', 'securityRequireBuiltinAdminRenamed', 'securityAsrRequiredRules', 'securityAsrAllowAudit',
                'resultCustomField')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Ninja-Property-Set {}
        Mock Get-ItemProperty { $null }
        Mock Get-WinEvent {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'checkLapsStatus' {
        It 'Accepts Windows LAPS with recent success / Akzeptiert LAPS mit aktuellem Erfolg' {
            Mock Get-ItemProperty { [pscustomobject]@{ BackupDirectory = 2; PasswordAgeDays = 30; PSPath = 'x' } } -ParameterFilter { $LiteralPath -like '*CurrentVersion\Policies\LAPS' }
            Mock Get-WinEvent { New-TestEvent -Id 10004 -Time (Get-Date).AddHours(-1); New-TestEvent -Id 10005 -Time (Get-Date).AddHours(-3) }
            $report = & $lapsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.PolicySource | Should -Be 'GPO'
            $report.BackupDirectoryName | Should -Be 'ActiveDirectory'
            $report.FailureEvents | Should -Be 1
        }
        It 'Warns when the latest event is a failure / Warnt bei letztem Fehlerereignis' {
            Mock Get-ItemProperty { [pscustomobject]@{ BackupDirectory = 1 } } -ParameterFilter { $LiteralPath -like '*Microsoft\Policies\LAPS' }
            Mock Get-WinEvent { New-TestEvent -Id 10005 -Time (Get-Date).AddHours(-1); New-TestEvent -Id 10020 -Time (Get-Date).AddDays(-2) }
            $report = & $lapsScript -CustomField 'lapsStatus' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'LatestEventIsFailure'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'lapsStatus' }
        }
        It 'Warns without LAPS configuration or events / Warnt ohne LAPS bzw. Ereignisse' {
            $report = & $lapsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'NotConfigured'
            Mock Get-ItemProperty { [pscustomobject]@{ BackupDirectory = 2 } } -ParameterFilter { $LiteralPath -like '*LAPS\Config' }
            Mock Get-WinEvent { Write-Error -Message 'No events were found' -Category ObjectNotFound -ErrorId 'NoMatchingEventsFound' }
            $report = & $lapsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'NoSuccessWithinWindow'
        }
        It 'Skips events for legacy LAPS with CSE / Ueberspringt Ereignisse bei Legacy-CSE' {
            Mock Get-ItemProperty { [pscustomobject]@{ AdmPwdEnabled = 1 } } -ParameterFilter { $LiteralPath -like '*AdmPwd' }
            Mock Get-ItemProperty { [pscustomobject]@{ DllName = 'AdmPwd.dll' } } -ParameterFilter { $LiteralPath -like '*GPExtensions*' }
            $report = & $lapsScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.EventCheck | Should -Be 'SkippedLegacyCse'
            Should -Invoke Get-WinEvent -Times 0 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('0', '366', 'abc', '-1')) {
                $null = & $lapsScript -MaxSuccessAgeDays $value
                $LASTEXITCODE | Should -Be 1
            }
            $env:resultCustomField = 'bad-name'
            $null = & $lapsScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkRdpSecurity' {
        BeforeEach {
            Mock Get-ItemProperty { [pscustomobject]@{ fDenyTSConnections = 0 } } -ParameterFilter { $LiteralPath -like '*Control\Terminal Server' }
            Mock Get-ItemProperty { [pscustomobject]@{ UserAuthentication = 1; SecurityLayer = 2; MinEncryptionLevel = 3; PortNumber = 3389 } } -ParameterFilter { $LiteralPath -like '*RDP-Tcp' }
        }
        It 'Accepts RDP with NLA and TLS / Akzeptiert RDP mit NLA und TLS' {
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RdpEnabled | Should -BeTrue
            $report.SecurityLayerName | Should -Be 'TLS'
            $report.PortNumber | Should -Be 3389
        }
        It 'Policy overrides local NLA setting / Richtlinie ueberschreibt NLA' {
            Mock Get-ItemProperty { [pscustomobject]@{ UserAuthentication = 0 } } -ParameterFilter { $LiteralPath -like '*Windows NT\Terminal Services' }
            $report = & $rdpScript -CustomField 'rdpSecurity' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'NlaNotEnforced'
            $report.Settings.UserAuthentication.Source | Should -Be 'Policy'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'rdpSecurity' }
        }
        It 'Warns on enabled RDP when not allowed / Warnt bei nicht erlaubtem RDP' {
            $env:securityRdpAllow = 'false'
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'RdpEnabledButNotAllowed'
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $rdpScript -AllowRdp 'maybe'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkPasswordPolicy' {
        BeforeEach {
            Mock Get-Content { $secpol } -ParameterFilter { $LiteralPath -like '*ninjaSecPol_*' }
            Mock secedit { $global:LASTEXITCODE = 0 }
        }
        It 'Accepts a compliant policy / Akzeptiert konforme Richtlinie' {
            $report = & $passwordScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Policy.MinimumPasswordLength | Should -Be 14
            Should -Invoke secedit -Times 1
        }
        It 'Warns on violations / Warnt bei Verstoessen' {
            $env:securityPasswordMinLength = '16'
            $env:resultCustomField = 'passwordPolicy'
            $report = & $passwordScript -MaxAgeDays 90 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'MinimumPasswordLength<16'
            $report.Findings | Should -Contain 'MaximumPasswordAge>90'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'passwordPolicy' }
        }
        It 'Deletes the temp export file / Loescht die Temp-Exportdatei' {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*ninjaSecPol_*' }
            Mock Remove-Item {} -ParameterFilter { $LiteralPath -like '*ninjaSecPol_*' }
            $null = & $passwordScript
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*ninjaSecPol_*' }
        }
        It 'Reports secedit failures / Meldet secedit-Fehler' {
            Mock secedit { $global:LASTEXITCODE = 3 }
            $null = & $passwordScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('129', 'x', '1.5')) {
                $null = & $passwordScript -MinLength $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $passwordScript -RequireComplexity 'yes'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke secedit -Times 0 -Exactly
        }
    }

    Context 'checkAuditPolicy' {
        It 'Accepts the default baseline / Akzeptiert Standard-Basislinie' {
            Mock auditpol { $global:LASTEXITCODE = 0; $auditHeader; $auditRows }
            $report = & $auditScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RequiredCount | Should -Be 7
            $report.Violations | Should -Be 0
        }
        It 'Warns on missing or insufficient settings (German output) / Warnt bei fehlenden Einstellungen' {
            Mock auditpol {
                $global:LASTEXITCODE = 0
                $auditHeader
                'PC1,System,Anmelden,{0CCE9215-69AE-11D9-BED3-505054503030},Erfolg,'
                'PC1,System,Kontosperrung,{0CCE9217-69AE-11D9-BED3-505054503030},Erfolg und Fehler,'
            }
            $report = & $auditScript -CustomField 'auditPolicy' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            ($report.Subcategories | Where-Object { $_.Guid -eq '{0CCE9215-69AE-11D9-BED3-505054503030}' }).Status | Should -Be 'Insufficient'
            ($report.Subcategories | Where-Object { $_.Guid -eq '{0CCE9217-69AE-11D9-BED3-505054503030}' }).Status | Should -Be 'OK'
            ($report.Subcategories | Where-Object { $_.Guid -eq '{0CCE922B-69AE-11D9-BED3-505054503030}' }).Status | Should -Be 'Missing'
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Accepts a custom requirement list / Akzeptiert eigene Liste' {
            Mock auditpol { $global:LASTEXITCODE = 0; $auditHeader; $auditRows }
            $env:securityAuditRequiredSubcategories = '0cce9217-69ae-11d9-bed3-505054503030=Failure; {0CCE922B-69AE-11D9-BED3-505054503030}=Success'
            $report = & $auditScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RequiredCount | Should -Be 2
        }
        It 'Rejects invalid input and auditpol errors / Lehnt Eingaben und auditpol-Fehler ab' {
            Mock auditpol { $global:LASTEXITCODE = 0; $auditHeader; $auditRows }
            foreach ($value in @('Logon=Success', '{0CCE9215-69AE-11D9-BED3-505054503030}=Always')) {
                $null = & $auditScript -RequiredSubcategories $value
                $LASTEXITCODE | Should -Be 1
            }
            Mock auditpol { $global:LASTEXITCODE = 0; $auditHeader; 'PC1,System,Logon,{0CCE9215-69AE-11D9-BED3-505054503030},Réussite,' }
            $null = & $auditScript -RequiredSubcategories '{0CCE9215-69AE-11D9-BED3-505054503030}=Success'
            $LASTEXITCODE | Should -Be 1
            Mock auditpol { $global:LASTEXITCODE = 5; 'Error 0x00000522' }
            $null = & $auditScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readFailedLogons' {
        BeforeEach {
            Mock Get-WinEvent {
                1..3 | ForEach-Object { New-TestEvent -Id 4625 -Time (Get-Date).AddMinutes(-$_) -Data @{ TargetUserName = 'admin'; IpAddress = '10.0.0.5'; LogonType = '3' } }
                New-TestEvent -Id 4625 -Time (Get-Date).AddMinutes(-9) -Data @{ TargetUserName = 'bob'; IpAddress = '-'; LogonType = '2' }
            } -ParameterFilter { $FilterHashtable.Id -eq 4625 }
            Mock Get-WinEvent { New-TestEvent -Id 4740 -Time (Get-Date) -Data @{ TargetUserName = 'bob'; TargetDomainName = 'PC1' } } -ParameterFilter { $FilterHashtable.Id -eq 4740 }
        }
        It 'Groups failed logons below threshold / Gruppiert unter Grenzwert' {
            $report = & $logonScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.FailedLogonCount | Should -Be 4
            $report.LockoutCount | Should -Be 1
            $report.Groups[0].TargetUserName | Should -Be 'admin'
            $report.Groups[0].Attempts | Should -Be 3
            $report.Groups[0].LogonTypeName | Should -Be 'Network'
        }
        It 'Warns at threshold and writes field / Warnt ab Grenzwert und schreibt Feld' {
            $env:securityFailedLogonThreshold = '4'
            $env:resultCustomField = 'failedLogons'
            $report = & $logonScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Truncated | Should -BeTrue
            @($report.Groups).Count | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'failedLogons' }
        }
        It 'Treats no events as OK / Keine Ereignisse sind OK' {
            Mock Get-WinEvent { Write-Error -Message 'No events were found' -Category ObjectNotFound -ErrorId 'NoMatchingEventsFound' } -ParameterFilter { $true }
            $report = & $logonScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.FailedLogonCount | Should -Be 0
        }
        It 'Reports access errors / Meldet Zugriffsfehler' {
            Mock Get-WinEvent { throw [System.UnauthorizedAccessException]::new('denied') } -ParameterFilter { $true }
            $null = & $logonScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('0', '721', 'x')) {
                $null = & $logonScript -Hours $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $logonScript -MaxEvents 20001
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-WinEvent -Times 0 -Exactly
        }
    }

    Context 'checkBuiltinAccounts' {
        BeforeEach {
            Mock Get-LocalUser {
                [pscustomobject]@{ Name = 'Administrator'; SID = 'S-1-5-21-1-2-3-500'; Enabled = $false; LastLogon = $null; PasswordLastSet = (Get-Date) }
                [pscustomobject]@{ Name = 'Gast'; SID = 'S-1-5-21-1-2-3-501'; Enabled = $false; LastLogon = $null; PasswordLastSet = $null }
                [pscustomobject]@{ Name = 'DefaultAccount'; SID = 'S-1-5-21-1-2-3-503'; Enabled = $false; LastLogon = $null; PasswordLastSet = $null }
                [pscustomobject]@{ Name = 'helpdesk'; SID = 'S-1-5-21-1-2-3-1001'; Enabled = $true; LastLogon = $null; PasswordLastSet = $null }
            }
        }
        It 'Accepts disabled built-in accounts / Akzeptiert deaktivierte Konten' {
            $report = & $accountScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Accounts.Guest.Name | Should -Be 'Gast'
            $report.Accounts.Guest.RenamedFromDefault | Should -BeFalse
            $report.Accounts.WDAGUtilityAccount | Should -BeNullOrEmpty
        }
        It 'Warns on enabled Guest and Administrator / Warnt bei aktiviertem Gast und Administrator' {
            Mock Get-LocalUser {
                [pscustomobject]@{ Name = 'Administrator'; SID = 'S-1-5-21-1-2-3-500'; Enabled = $true; LastLogon = (Get-Date); PasswordLastSet = $null }
                [pscustomobject]@{ Name = 'Guest'; SID = 'S-1-5-21-1-2-3-501'; Enabled = $true; LastLogon = $null; PasswordLastSet = $null }
            }
            $report = & $accountScript -CustomField 'builtinAccounts' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'GuestEnabled'
            $report.Findings | Should -Contain 'BuiltinAdministratorEnabled'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'builtinAccounts' }
        }
        It 'Honors allow and rename options / Beachtet Optionen' {
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'Administrator'; SID = 'S-1-5-21-1-2-3-500'; Enabled = $true; LastLogon = $null; PasswordLastSet = $null } }
            $env:securityAllowBuiltinAdminEnabled = 'true'
            $null = & $accountScript
            $LASTEXITCODE | Should -Be 0
            $report = & $accountScript -RequireAdminRenamed 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Be @('BuiltinAdministratorNotRenamed')
        }
        It 'Rejects invalid input and query errors / Lehnt Eingaben und Abfragefehler ab' {
            $null = & $accountScript -AllowAdminEnabled 'perhaps'
            $LASTEXITCODE | Should -Be 1
            Mock Get-LocalUser { throw 'not supported on DC' }
            $null = & $accountScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkDefenderAsrRules' {
        BeforeEach {
            Mock Get-MpPreference {
                [pscustomobject]@{
                    AttackSurfaceReductionRules_Ids = @('9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2', '56a863a9-875e-4185-98a7-b882c64b5ce5', 'd4f940ab-401b-4efc-aadc-ad5f3c50688a')
                    AttackSurfaceReductionRules_Actions = @(1, 2, 6)
                }
            }
        }
        It 'Reports rules with names and modes / Meldet Regeln mit Namen und Modus' {
            $report = & $asrScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalRules | Should -Be 3
            ($report.Rules | Where-Object { $_.Id -eq '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' }).Mode | Should -Be 'Block'
            ($report.Rules | Where-Object { $_.Id -eq 'd4f940ab-401b-4efc-aadc-ad5f3c50688a' }).Mode | Should -Be 'Warn'
        }
        It 'Warns when required rules are not Block / Warnt bei Pflichtregeln ohne Block' {
            $env:securityAsrRequiredRules = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2,{56A863A9-875E-4185-98A7-B882C64B5CE5};c1db55ab-c21a-4637-bb3f-a12568109d35'
            $report = & $asrScript -CustomField 'asrRules' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.ViolationCount | Should -Be 2
            ($report.Violations | Where-Object { $_.Id -eq 'c1db55ab-c21a-4637-bb3f-a12568109d35' }).Mode | Should -Be 'NotConfigured'
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'asrRules' }
        }
        It 'Accepts audit and warn when allowed / Akzeptiert Audit und Warn wenn erlaubt' {
            $null = & $asrScript -RequiredRules '56a863a9-875e-4185-98a7-b882c64b5ce5,d4f940ab-401b-4efc-aadc-ad5f3c50688a' -AllowAudit true
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $asrScript -RequiredRules 'not-a-guid'
            $LASTEXITCODE | Should -Be 1
            $null = & $asrScript -AllowAudit 'sometimes'
            $LASTEXITCODE | Should -Be 1
            Mock Get-MpPreference { [pscustomobject]@{ AttackSurfaceReductionRules_Ids = @('9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'); AttackSurfaceReductionRules_Actions = @() } }
            $null = & $asrScript
            $LASTEXITCODE | Should -Be 1
        }
    }
}
