BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $uacScript = Join-Path $root '07 - Security/checkUacSettings.ps1'
    $smb1Script = Join-Path $root '07 - Security/checkSmbv1Status.ps1'
    $signingScript = Join-Path $root '07 - Security/checkSmbSigning.ps1'
    $guardScript = Join-Path $root '07 - Security/checkCredentialGuard.ps1'
    $lsaScript = Join-Path $root '07 - Security/checkLsaProtection.ps1'
    $exclusionScript = Join-Path $root '07 - Security/checkDefenderExclusions.ps1'
    $legacyScript = Join-Path $root '07 - Security/checkLegacyAuthentication.ps1'
    $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $mrxPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10'
    $wdigestPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-CimInstance { param($ClassName, $Namespace, $Filter) }
    function Get-SmbServerConfiguration {}
    function Get-SmbClientConfiguration {}
    function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName) }
    function Get-WinEvent { param($FilterHashtable, $MaxEvents) }
    function Get-MpPreference {}
    function Ninja-Property-Set { param($Name, $Value) }
}

Describe 'Security catalogue A / Sicherheitskatalog A' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('resultCustomField', 'securitySmb1IncludeFeature', 'securitySmbSigningRequiredSide',
                'securitySmbRequireEncryption', 'securityRequireCredentialGuard', 'securityRequireHvci',
                'securityLsaCheckEvent', 'securityLsaRequireEvent', 'securityDefenderExclusionAllowlist',
                'securityDefenderWarnOnAnyExclusion', 'securityDefenderWarnOnHiddenExclusions',
                'securityDefenderExclusionMaxRecords', 'securityLmCompatibilityMinimum')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        # DE: Registry als Hashtable Pfad -> Objekt. EN: Registry as hashtable path -> object.
        $registry = @{}
        Mock Test-Path { $registry.ContainsKey([string]$LiteralPath) }
        Mock Get-ItemProperty { $registry[[string]$LiteralPath] }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'checkUacSettings' {
        It 'Reports defaults as NotConfigured and OK / Meldet Standards als NotConfigured' {
            $report = & $uacScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.UacEnabled | Should -BeTrue
            ($report.Settings | Where-Object Name -eq 'ConsentPromptBehaviorAdmin').State | Should -Be 'NotConfigured'
            ($report.Settings | Where-Object Name -eq 'ConsentPromptBehaviorAdmin').EffectiveValue | Should -Be 5
        }
        It 'Warns on disabled UAC and silent elevation / Warnt bei UAC aus' {
            $registry[$uacPath] = [pscustomobject]@{ EnableLUA = 0; ConsentPromptBehaviorAdmin = 0; PromptOnSecureDesktop = 0 }
            $env:resultCustomField = 'uacStatus'
            $report = & $uacScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'UacDisabled'
            $report.Findings | Should -Contain 'AdminElevationWithoutPrompt'
            $report.Findings | Should -Contain 'SecureDesktopDisabled'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'uacStatus' }
        }
        It 'Flags non-numeric values / Markiert ungueltige Werte' {
            $registry[$uacPath] = [pscustomobject]@{ EnableLUA = 'abc' }
            $null = & $uacScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid custom field names / Lehnt ungueltige Feldnamen ab' {
            $null = & $uacScript -CustomField 'bad name;'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 0 -Exactly
        }
        It 'Reports field write failures / Meldet Schreibfehler' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $uacScript -CustomField 'uacStatus'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkSmbv1Status' {
        BeforeEach {
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $false } }
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Disabled' } }
        }
        It 'Reports SMBv1 off / Meldet SMBv1 aus' {
            $report = & $smb1Script | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Client.State | Should -Be 'NotInstalled'
            $report.Feature.State | Should -Be 'Disabled'
        }
        It 'Warns on enabled client driver and server / Warnt bei aktivem Client und Server' {
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $true } }
            $registry[$mrxPath] = [pscustomobject]@{ Start = 2 }
            $report = & $smb1Script -IncludeFeature false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'ServerSmb1Enabled'
            $report.Findings | Should -Contain 'ClientSmb1Enabled'
            $report.Feature.State | Should -Be 'Skipped'
            Should -Invoke Get-WindowsOptionalFeature -Times 0 -Exactly
        }
        It 'Accepts a disabled client driver / Akzeptiert deaktivierten Treiber' {
            $registry[$mrxPath] = [pscustomobject]@{ Start = 4 }
            $null = & $smb1Script
            $LASTEXITCODE | Should -Be 0
        }
        It 'Warns on enabled feature and tolerates feature errors / Warnt bei Feature' {
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = 'Enabled' } }
            $null = & $smb1Script
            $LASTEXITCODE | Should -Be 2
            Mock Get-WindowsOptionalFeature { throw 'Feature name SMB1Protocol is unknown.' }
            $report = & $smb1Script | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Feature.State | Should -Be 'Unavailable'
        }
        It 'Rejects invalid booleans / Lehnt ungueltige Werte ab' {
            $env:securitySmb1IncludeFeature = 'yes'
            $null = & $smb1Script
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkSmbSigning' {
        BeforeEach {
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ RequireSecuritySignature = $true; EnableSecuritySignature = $true; EncryptData = $false; RejectUnencryptedAccess = $true } }
            Mock Get-SmbClientConfiguration { [pscustomobject]@{ RequireSecuritySignature = $false; EnableSecuritySignature = $true } }
        }
        It 'Warns when client signing is not required / Warnt ohne Client-Signierung' {
            $env:resultCustomField = 'smbSigning'
            $report = & $signingScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Be @('ClientSigningNotRequired')
            $report.Server.Registry.State | Should -Be 'NotConfigured'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Checks only the configured side / Prueft nur die gewaehlte Seite' {
            $null = & $signingScript -RequiredSide server
            $LASTEXITCODE | Should -Be 0
            $null = & $signingScript -RequiredSide Server -RequireEncryption true
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid sides / Lehnt ungueltige Seite ab' {
            $env:securitySmbSigningRequiredSide = 'Everything'
            $null = & $signingScript
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-SmbServerConfiguration -Times 0 -Exactly
        }
    }

    Context 'checkCredentialGuard' {
        BeforeEach {
            Mock Get-CimInstance {
                [pscustomobject]@{
                    VirtualizationBasedSecurityStatus = 2; SecurityServicesConfigured = @(1, 2); SecurityServicesRunning = @(1)
                    AvailableSecurityProperties = @(1, 2, 3); CodeIntegrityPolicyEnforcementStatus = 0
                }
            } -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' }
        }
        It 'Reports running Credential Guard / Meldet laufendes Credential Guard' {
            $registry[$lsaPath] = [pscustomobject]@{ LsaCfgFlags = 1 }
            $report = & $guardScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.VirtualizationBasedSecurity | Should -Be 'Running'
            $report.ServicesRunning | Should -Be @('CredentialGuard')
            $report.Registry[0].Meaning | Should -Be 'EnabledWithUefiLock'
        }
        It 'Warns when HVCI is required but not running / Warnt ohne HVCI' {
            $env:securityRequireHvci = 'true'
            $report = & $guardScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Be @('HvciNotRunning')
        }
        It 'Warns when Credential Guard is not running / Warnt ohne Credential Guard' {
            Mock Get-CimInstance { [pscustomobject]@{ VirtualizationBasedSecurityStatus = 0; SecurityServicesRunning = @(0) } } -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' }
            $null = & $guardScript -CustomField 'vbsStatus'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Reports query errors and invalid input / Meldet Fehler' {
            Mock Get-CimInstance { throw 'Invalid namespace' } -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' }
            $null = & $guardScript
            $LASTEXITCODE | Should -Be 1
            $null = & $guardScript -RequireCredentialGuard 'maybe'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkLsaProtection' {
        BeforeEach {
            Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddHours(-2) } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
            Mock Get-WinEvent {
                $exception = New-Object System.Exception 'No events were found that match the specified selection criteria.'
                throw (New-Object System.Management.Automation.ErrorRecord $exception, 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', ([System.Management.Automation.ErrorCategory]::ObjectNotFound), $null)
            }
        }
        It 'Accepts RunAsPPL 2 / Akzeptiert RunAsPPL 2' {
            $registry[$lsaPath] = [pscustomobject]@{ RunAsPPL = 2 }
            $report = & $lsaScript -CheckEvent false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.RunAsPPL.Meaning | Should -Be 'EnabledWithoutUefiLock'
            $report.EventCheck | Should -Be 'Skipped'
        }
        It 'Warns when not configured and no event / Warnt ohne Schutz' {
            $report = & $lsaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.RunAsPPL.State | Should -Be 'NotConfigured'
            $report.EventCheck | Should -Be 'NotFound'
        }
        It 'Accepts the Wininit event without registry value / Akzeptiert Ereignis 12' {
            Mock Get-WinEvent { [pscustomobject]@{ TimeCreated = (Get-Date).AddHours(-1); Properties = @([pscustomobject]@{ Value = 4 }) } }
            $env:securityLsaRequireEvent = 'true'
            $report = & $lsaScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.EventCheck | Should -Be 'Verified'
            $report.EventProtectionLevel | Should -Be '4'
        }
        It 'Requires the event when configured / Verlangt Ereignis' {
            $registry[$lsaPath] = [pscustomobject]@{ RunAsPPL = 1 }
            Mock Get-WinEvent {}
            $null = & $lsaScript -RequireEvent true -CustomField 'lsaStatus'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Reports unexpected event log errors / Meldet Ereignislogfehler' {
            $registry[$lsaPath] = [pscustomobject]@{ RunAsPPL = 1 }
            Mock Get-WinEvent { throw 'Access is denied.' }
            $null = & $lsaScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $lsaScript -CheckEvent '1'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkDefenderExclusions' {
        BeforeEach {
            Mock Get-MpPreference {
                [pscustomobject]@{
                    ExclusionPath = @('C:\App\Data', 'D:\Temp'); ExclusionExtension = @('.ldf'); ExclusionProcess = $null; ExclusionIpAddress = @()
                }
            }
        }
        It 'Warns on any exclusion by default / Warnt standardmaessig bei jedem Ausschluss' {
            $report = & $exclusionScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.TotalExclusions | Should -Be 3
            $report.Findings | Should -Contain 'ExclusionsPresent'
        }
        It 'Accepts allowlisted exclusions case-insensitively / Akzeptiert Allowlist' {
            $report = & $exclusionScript -WarnOnAny false -Allowlist 'c:\app\data; D:\TEMP,.LDF' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.UnapprovedExclusions | Should -Be 0
        }
        It 'Warns on exclusions outside the allowlist / Warnt ausserhalb der Allowlist' {
            $env:securityDefenderWarnOnAnyExclusion = 'false'
            $env:securityDefenderExclusionAllowlist = 'C:\App\Data'
            $env:resultCustomField = 'defenderExclusions'
            $report = & $exclusionScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.UnapprovedExclusions | Should -Be 2
            $report.Entries[0].Allowed | Should -BeFalse
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'defenderExclusions' }
        }
        It 'Inventory mode without allowlist exits 0 / Inventarmodus' {
            $null = & $exclusionScript -WarnOnAny false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Handles hidden exclusions / Behandelt verborgene Ausschluesse' {
            Mock Get-MpPreference { [pscustomobject]@{ ExclusionPath = @('N/A: Must be an administrator to view exclusions'); ExclusionExtension = $null; ExclusionProcess = $null; ExclusionIpAddress = $null } }
            $report = & $exclusionScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.HiddenCategories | Should -Be @('ExclusionPath')
            $report.TotalExclusions | Should -Be 0
            $null = & $exclusionScript -WarnOnHidden false
            $LASTEXITCODE | Should -Be 0
        }
        It 'Bounds and shrinks large reports / Begrenzt grosse Berichte' {
            Mock Get-MpPreference { [pscustomobject]@{ ExclusionPath = @(1..150 | ForEach-Object { 'C:\' + ('x' * 100) + $_ }) } }
            $report = & $exclusionScript -MaxRecords 200 -CustomField 'defenderExclusions'
            $LASTEXITCODE | Should -Be 2
            $report.Length | Should -BeLessOrEqual 4000
            $parsed = $report | ConvertFrom-Json
            $parsed.Truncated | Should -BeTrue
            $parsed.TotalExclusions | Should -Be 150
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('0', '201', 'abc')) {
                $null = & $exclusionScript -MaxRecords $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $exclusionScript -Allowlist ("C:\a`tb")
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-MpPreference -Times 0 -Exactly
        }
    }

    Context 'checkLegacyAuthentication' {
        It 'Accepts hardened settings / Akzeptiert gehaertete Werte' {
            $registry[$lsaPath] = [pscustomobject]@{ LmCompatibilityLevel = 5; NoLMHash = 1 }
            $report = & $legacyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Settings | Where-Object Name -eq 'UseLogonCredential').State | Should -Be 'NotConfigured'
            ($report.Settings | Where-Object Name -eq 'RestrictAnonymousSAM').EffectiveValue | Should -Be 1
        }
        It 'Warns on OS default level below minimum / Warnt bei Standardstufe 3' {
            $report = & $legacyScript -CustomField 'legacyAuth' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Be @('LmCompatibilityLevelBelowMinimum')
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Honors a lower minimum but flags WDigest and LM hashes / Meldet WDigest und LM-Hashes' {
            $env:securityLmCompatibilityMinimum = '3'
            $null = & $legacyScript
            $LASTEXITCODE | Should -Be 0
            $registry[$lsaPath] = [pscustomobject]@{ NoLMHash = 0 }
            $registry[$wdigestPath] = [pscustomobject]@{ UseLogonCredential = 1 }
            $report = & $legacyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'LmHashStorageAllowed'
            $report.Findings | Should -Contain 'WDigestCleartextEnabled'
        }
        It 'Rejects invalid minimum levels / Lehnt ungueltige Stufen ab' {
            foreach ($value in @('-1', '6', 'five')) {
                $null = & $legacyScript -MinimumLevel $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }
}
