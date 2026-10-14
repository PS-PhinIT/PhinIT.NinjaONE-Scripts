BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = Join-Path $root '02 - Updates'
    $lastInstallScript = Join-Path $folder 'readLastUpdateInstall.ps1'
    $pendingScript = Join-Path $folder 'readPendingUpdates.ps1'
    $failureScript = Join-Path $folder 'readUpdateHistoryFailures.ps1'
    $wsusScript = Join-Path $folder 'checkWsusConfiguration.ps1'
    $policyScript = Join-Path $folder 'checkWindowsUpdatePolicy.ps1'
    $targetScript = Join-Path $folder 'checkTargetReleaseVersion.ps1'
    $pauseScript = Join-Path $folder 'checkUpdatePauseState.ps1'
    $doScript = Join-Path $folder 'readDeliveryOptimizationStatus.ps1'
    $dismScript = Join-Path $folder 'checkComponentStoreHealth.ps1'
    $officeScript = Join-Path $folder 'readOfficeUpdateChannel.ps1'
    $wuPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $mdmUpdate = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'

    # DE: Stubs erlauben Mocks ohne Windows/NinjaOne. EN: Stubs allow mocks without Windows/NinjaOne.
    function New-Object { param($TypeName, $ComObject, $ArgumentList, $Property) }
    function Get-HotFix { param($Id) }
    function Get-DeliveryOptimizationPerfSnap { param() }
    function Get-DOConfig { param() }
    function dism { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }

    function New-FakeUpdateSession {
        param($History = @(), $Updates = @(), [int]$ResultCode = 2)
        $searcher = [pscustomobject]@{ Online = $true; History = @($History); Updates = @($Updates); Code = $ResultCode }
        $searcher | Add-Member -MemberType ScriptMethod -Name GetTotalHistoryCount -Value { @($this.History).Count }
        $searcher | Add-Member -MemberType ScriptMethod -Name QueryHistory -Value { param($Start, $Count) @($this.History | Select-Object -Skip $Start -First $Count) }
        $searcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
            param($Criteria)
            if ($Criteria -ne "IsInstalled=0 and IsHidden=0 and Type='Software'") { throw "Unexpected criteria $Criteria" }
            [pscustomobject]@{ ResultCode = $this.Code; Updates = $this.Updates }
        }
        $session = [pscustomobject]@{ Searcher = $searcher }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $this.Searcher }
        $session
    }
    function New-HistoryEntry {
        param([int]$DaysAgo, [string]$Title = 'Cumulative Update (KB5031354)', [int]$ResultCode = 2, [int]$Operation = 1, [int]$HResult = 0)
        [pscustomobject]@{ Date = [DateTime]::UtcNow.AddDays(-$DaysAgo); Title = $Title; ResultCode = $ResultCode; Operation = $Operation; HResult = $HResult }
    }
    function New-PendingUpdate {
        param([string]$Title, [string]$Severity = '', [string]$ClassificationId = 'cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83', [string]$ClassificationName = 'Updates')
        [pscustomobject]@{
            Title = $Title; MsrcSeverity = $Severity; KBArticleIDs = @('5031354'); IsDownloaded = $false
            Categories = @(
                [pscustomobject]@{ Name = $ClassificationName; CategoryID = $ClassificationId; Type = 'UpdateClassification' }
                [pscustomobject]@{ Name = 'Windows 11'; CategoryID = '72e7624a-5b00-45d2-b92f-e561c0a6a160'; Type = 'Product' }
            )
        }
    }
}

Describe 'Update catalogue scripts / Update-Katalogskripte' {
    BeforeEach {
        $savedEnvironment = @{}
        foreach ($name in @('updateLastInstallMaxDays', 'updateLastInstallIncludeDefinitions', 'updatePendingWarnOn', 'updatePendingOnlineSearch',
                'updatePendingMaxRecords', 'updateFailureDays', 'updateFailureMaxRecords', 'updateWsusExpectedServer', 'updateWsusExpectedTargetGroup',
                'updatePolicyMaxQualityDeferralDays', 'updateTargetExpectedVersion', 'updateTargetExpectedProduct', 'updateOfficeExpectedChannel',
                'resultCustomField')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $registry = @{}
        $fakeSession = New-FakeUpdateSession
        Mock Test-Path { $registry.ContainsKey([string]$LiteralPath) }
        Mock Get-ItemProperty { [pscustomobject]$registry[[string]$LiteralPath] }
        Mock New-Object { $fakeSession } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        Mock Get-HotFix {}
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    }

    Context 'readLastUpdateInstall' {
        It 'Reports a recent installation / Meldet aktuelle Installation' {
            $fakeSession = New-FakeUpdateSession -History @((New-HistoryEntry -DaysAgo 5), (New-HistoryEntry -DaysAgo 2 -ResultCode 4))
            $report = & $lastInstallScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'WindowsUpdateHistory'
            [Math]::Round($report.DaysSinceLastInstall) | Should -Be 5
        }
        It 'Ignores definition updates and warns when too old / Ignoriert Definitionen und warnt' {
            $fakeSession = New-FakeUpdateSession -History @(
                (New-HistoryEntry -DaysAgo 1 -Title 'Security Intelligence Update for Microsoft Defender Antivirus - KB2267602 (Version 1.1)'),
                (New-HistoryEntry -DaysAgo 50))
            $env:resultCustomField = 'lastUpdateInstall'
            $null = & $lastInstallScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'lastUpdateInstall' }
            $null = & $lastInstallScript -IncludeDefinitionUpdates true -CustomField ''
            $LASTEXITCODE | Should -Be 0
        }
        It 'Falls back to Get-HotFix / Nutzt Get-HotFix als Ersatz' {
            Mock New-Object { throw 'COM unavailable' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
            Mock Get-HotFix { [pscustomobject]@{ HotFixID = 'KB5031354'; InstalledOn = [DateTime]::Now.AddDays(-3) } }
            $report = & $lastInstallScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Source | Should -Be 'Get-HotFix'
            $report.WuaError | Should -Match 'COM unavailable'
        }
        It 'Warns when no installation is recorded / Warnt ohne Installation' {
            $null = & $lastInstallScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Fails when both sources fail / Fehler wenn beide Quellen scheitern' {
            Mock New-Object { throw 'COM unavailable' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
            Mock Get-HotFix { throw 'WMI unavailable' }
            $null = & $lastInstallScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '3651', 'abc', '1.5')) {
                $env:updateLastInstallMaxDays = $value
                $null = & $lastInstallScript
                $LASTEXITCODE | Should -Be 1
            }
            $env:updateLastInstallMaxDays = 'NULL'
            $null = & $lastInstallScript -IncludeDefinitionUpdates 'yes'
            $LASTEXITCODE | Should -Be 1
            $null = & $lastInstallScript -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke New-Object -Times 0 -Exactly
        }
    }

    Context 'readPendingUpdates' {
        It 'Reports no pending updates / Meldet keine ausstehenden Updates' {
            $report = & $pendingScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalPending | Should -Be 0
        }
        It 'Warns on security updates only by default / Warnt standardmäßig nur bei Sicherheitsupdates' {
            $fakeSession = New-FakeUpdateSession -Updates @(New-PendingUpdate -Title 'Feature pack')
            $null = & $pendingScript
            $LASTEXITCODE | Should -Be 0
            $null = & $pendingScript -WarnOn any
            $LASTEXITCODE | Should -Be 2
            $fakeSession = New-FakeUpdateSession -Updates @(
                (New-PendingUpdate -Title 'Feature pack'),
                (New-PendingUpdate -Title 'Servicing stack' -ClassificationId 'E6CF1350-C01B-414D-A61F-263D14D133B4' -ClassificationName 'Kritische Updates'))
            $report = & $pendingScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.SecurityOrCriticalCount | Should -Be 1
            $report.Updates[0].Title | Should -Be 'Servicing stack'
            $report.Updates[0].KB | Should -Be 'KB5031354'
            $null = & $pendingScript -WarnOn None
            $LASTEXITCODE | Should -Be 0
        }
        It 'Detects MSRC severity, honours offline search and writes field / Erkennt MSRC, Offline-Suche, Feld' {
            $fakeSession = New-FakeUpdateSession -Updates @(New-PendingUpdate -Title 'Cumulative Update' -Severity 'Critical')
            $env:updatePendingOnlineSearch = 'false'
            $env:resultCustomField = 'pendingUpdates'
            $report = & $pendingScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.OnlineSearch | Should -BeFalse
            $fakeSession.Searcher.Online | Should -BeFalse
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'pendingUpdates' }
        }
        It 'Bounds the record list / Begrenzt die Liste' {
            $fakeSession = New-FakeUpdateSession -Updates @(1..40 | ForEach-Object { New-PendingUpdate -Title (('Update {0} ' -f $_).PadRight(140, 'x')) })
            $report = & $pendingScript -MaxRecords 100 -WarnOn None
            $LASTEXITCODE | Should -Be 0
            $report.Length | Should -BeLessOrEqual 4000
            $parsed = $report | ConvertFrom-Json
            $parsed.TotalPending | Should -Be 40
            $parsed.Truncated | Should -BeTrue
            $parsed.ReportedRecords | Should -BeLessThan 40
        }
        It 'Fails on search errors / Fehler bei Suchfehlern' {
            $fakeSession = New-FakeUpdateSession -ResultCode 4
            $null = & $pendingScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ WarnOn = 'Some' }, @{ MaxRecords = '0' }, @{ MaxRecords = '101' }, @{ OnlineSearch = 'maybe' }, @{ CustomField = '1field' })) {
                $null = & $pendingScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-Object -Times 0 -Exactly
        }
    }

    Context 'readUpdateHistoryFailures' {
        It 'Reports no failures in the window / Keine Fehler im Zeitraum' {
            $fakeSession = New-FakeUpdateSession -History @((New-HistoryEntry -DaysAgo 1), (New-HistoryEntry -DaysAgo 60 -ResultCode 4))
            $report = & $failureScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalFailures | Should -Be 0
            $report.ScannedEntries | Should -Be 2
        }
        It 'Warns on failed and aborted entries / Warnt bei Fehlern und Abbrüchen' {
            $fakeSession = New-FakeUpdateSession -History @(
                (New-HistoryEntry -DaysAgo 2 -ResultCode 4 -HResult -2145124329),
                (New-HistoryEntry -DaysAgo 3 -ResultCode 5 -Operation 2),
                (New-HistoryEntry -DaysAgo 4))
            $env:updateFailureDays = '7'
            $env:resultCustomField = 'updateFailures'
            $report = & $failureScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FailedCount | Should -Be 1
            $report.AbortedCount | Should -Be 1
            $report.Failures[0].HResult | Should -Be '0x80240017'
            $report.Failures[1].Operation | Should -Be 'Uninstallation'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'updateFailures' }
        }
        It 'Reports field write failures / Meldet Schreibfehler' {
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $failureScript -CustomField 'updateFailures'
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ Days = '0' }, @{ Days = '366' }, @{ Days = 'x' }, @{ MaxRecords = '500' })) {
                $null = & $failureScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke New-Object -Times 0 -Exactly
        }
    }

    Context 'checkWsusConfiguration' {
        It 'Reports missing WSUS policy without expectation / Ohne Erwartung kein Befund' {
            $report = & $wsusScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WsusEnabled | Should -BeFalse
        }
        It 'Accepts the expected server and group / Akzeptiert erwarteten Server und Gruppe' {
            $registry[$wuPolicy] = @{ WUServer = 'https://WSUS.contoso.local:8531/'; WUStatusServer = 'https://wsus.contoso.local:8531'; TargetGroupEnabled = 1; TargetGroup = 'Clients' }
            $registry["$wuPolicy\AU"] = @{ UseWUServer = 1 }
            $env:resultCustomField = 'wsusConfig'
            $report = & $wsusScript -ExpectedServer 'https://wsus.contoso.local:8531' -ExpectedTargetGroup 'clients' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WsusEnabled | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on mismatches / Warnt bei Abweichungen' {
            $registry[$wuPolicy] = @{ WUServer = 'http://old-wsus:8530'; WUStatusServer = 'http://old-wsus:8530' }
            $registry["$wuPolicy\AU"] = @{ UseWUServer = 1 }
            $env:updateWsusExpectedServer = 'https://wsus.contoso.local:8531'
            $report = & $wsusScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Findings).Count | Should -Be 2
            $null = & $wsusScript -ExpectedServer '' -ExpectedTargetGroup 'Servers'
            $LASTEXITCODE | Should -Be 2
        }
        It 'Warns on UseWUServer without server / Warnt bei UseWUServer ohne Server' {
            $registry["$wuPolicy\AU"] = @{ UseWUServer = 1 }
            $null = & $wsusScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('ftp://wsus', 'https://bad host', 'wsus.contoso.local', 'https://wsus/path')) {
                $null = & $wsusScript -ExpectedServer $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $wsusScript -ExpectedTargetGroup 'Clients<script>'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-ItemProperty -Times 0 -Exactly
        }
    }

    Context 'checkWindowsUpdatePolicy' {
        It 'Reports unconfigured policy as OK / Nicht konfiguriert ist OK' {
            $report = & $policyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.AutomaticUpdates | Should -Be 'NotConfigured'
        }
        It 'Maps configured policy values / Ordnet Werte zu' {
            $registry["$wuPolicy\AU"] = @{ NoAutoUpdate = 0; AUOptions = 4; ScheduledInstallDay = 3; ScheduledInstallTime = 3 }
            $registry[$wuPolicy] = @{ DeferQualityUpdates = 1; DeferQualityUpdatesPeriodInDays = 7; BranchReadinessLevel = 16 }
            $report = & $policyScript -MaxQualityDeferralDays 7 -CustomField 'updatePolicy' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.AutomaticUpdates | Should -Be 'Enabled'
            $report.AUOptionsName | Should -Be 'AutoDownloadScheduleInstall'
            $report.ScheduledInstallDayName | Should -Be 'Tuesday'
            $report.BranchReadiness | Should -Be 'GeneralAvailability'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when automatic updates are disabled / Warnt bei deaktivierten Updates' {
            $registry["$wuPolicy\AU"] = @{ NoAutoUpdate = 1 }
            $null = & $policyScript
            $LASTEXITCODE | Should -Be 2
            $registry.Remove("$wuPolicy\AU")
            $registry[$mdmUpdate] = @{ AllowAutoUpdate = 5 }
            $report = & $policyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.AutomaticUpdates | Should -Be 'Disabled'
        }
        It 'Warns on excessive deferral / Warnt bei zu langer Rückstellung' {
            $registry[$mdmUpdate] = @{ DeferQualityUpdatesPeriodInDays = 14 }
            $env:updatePolicyMaxQualityDeferralDays = '7'
            $null = & $policyScript
            $LASTEXITCODE | Should -Be 2
            $null = & $policyScript -MaxQualityDeferralDays 30
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('31', '-1', 'x')) {
                $null = & $policyScript -MaxQualityDeferralDays $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkTargetReleaseVersion' {
        BeforeEach {
            $registry['HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'] = @{ ProductName = 'Windows 10 Pro'; EditionID = 'Professional'; DisplayVersion = '23H2'; CurrentBuildNumber = '22631'; UBR = 4317 }
        }
        It 'Accepts matching policy / Akzeptiert passende Richtlinie' {
            $registry[$wuPolicy] = @{ TargetReleaseVersion = 1; TargetReleaseVersionInfo = '23H2'; ProductVersion = 'Windows 11' }
            $report = & $targetScript -ExpectedVersion 23h2 -ExpectedProduct 'windows 11' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.CurrentProduct | Should -Be 'Windows 11'
            $report.FullBuild | Should -Be '22631.4317'
            $report.PolicySource | Should -Be 'GroupPolicy'
        }
        It 'Warns on policy mismatch / Warnt bei Abweichung' {
            $registry[$wuPolicy] = @{ TargetReleaseVersion = 1; TargetReleaseVersionInfo = '24H2'; ProductVersion = 'Windows 11' }
            $env:resultCustomField = 'targetRelease'
            $null = & $targetScript
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns when expected version has no policy / Warnt ohne Richtlinie' {
            $null = & $targetScript
            $LASTEXITCODE | Should -Be 0
            $env:updateTargetExpectedVersion = '23H2'
            $null = & $targetScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Uses MDM policy as fallback / Nutzt MDM-Richtlinie' {
            $registry[$mdmUpdate] = @{ TargetReleaseVersion = '23H2'; ProductVersion = 'Windows 10' }
            $report = & $targetScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.PolicySource | Should -Be 'MDM'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ ExpectedVersion = '23H3' }, @{ ExpectedVersion = 'latest' }, @{ ExpectedProduct = 'Windows 12' })) {
                $null = & $targetScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            $registry.Clear()
            $null = & $targetScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkUpdatePauseState' {
        It 'Reports no pause / Keine Pause' {
            $registry['HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'] = @{ PauseUpdatesExpiryTime = [DateTime]::UtcNow.AddDays(-2).ToString('yyyy-MM-ddTHH:mm:ssZ') }
            $report = & $pauseScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Paused | Should -BeFalse
        }
        It 'Warns on a Settings app pause / Warnt bei Pause in Einstellungen' {
            $registry['HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'] = @{
                PauseUpdatesStartTime = [DateTime]::UtcNow.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
                PauseUpdatesExpiryTime = [DateTime]::UtcNow.AddDays(6).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            $env:resultCustomField = 'updatePauseState'
            $report = & $pauseScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.ActivePauses[0].Kind | Should -Be 'All'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Evaluates policy pauses / Wertet Richtlinienpausen aus' {
            $registry[$wuPolicy] = @{ PauseQualityUpdatesStartTime = [DateTime]::UtcNow.AddDays(-10).ToString('yyyy-MM-dd') }
            $null = & $pauseScript
            $LASTEXITCODE | Should -Be 2
            $registry[$wuPolicy] = @{ PauseQualityUpdatesStartTime = [DateTime]::UtcNow.AddDays(-40).ToString('yyyy-MM-dd') }
            $null = & $pauseScript
            $LASTEXITCODE | Should -Be 0
            $registry[$wuPolicy] = @{ PauseQualityUpdates = 0; PauseQualityUpdatesStartTime = [DateTime]::UtcNow.ToString('yyyy-MM-dd') }
            $null = & $pauseScript
            $LASTEXITCODE | Should -Be 0
            $registry[$mdmUpdate] = @{ PauseFeatureUpdates = 1 }
            $report = & $pauseScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.ActivePauses[0].Source | Should -Be 'MDM'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $pauseScript -CustomField 'bad field'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readDeliveryOptimizationStatus' {
        It 'Combines cmdlets and policy without printing the group ID / Kombiniert Daten ohne Gruppen-ID' {
            Mock Get-DeliveryOptimizationPerfSnap { [pscustomobject]@{ FileCount = 3; CacheSizeBytes = 1024; NumberOfPeers = 2; Unrelated = 'x' } }
            Mock Get-DOConfig { [pscustomobject]@{ DownloadMode = 'Lan'; DOGroupId = 'secret-group' } }
            $registry['HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'] = @{ DODownloadMode = 2; DOGroupId = '11111111-2222-3333-4444-555555555555' }
            $env:resultCustomField = 'deliveryOptimization'
            $output = & $doScript
            $LASTEXITCODE | Should -Be 0
            $output | Should -Not -Match '11111111|secret-group'
            $report = $output | ConvertFrom-Json
            $report.EffectiveDownloadModeName | Should -Be 'Group'
            $report.DownloadModeSource | Should -Be 'GroupPolicy'
            $report.GroupIdConfigured | Should -BeTrue
            $report.PerfSnap.NumberOfPeers | Should -Be 2
            $report.PerfSnap.PSObject.Properties.Name | Should -Not -Contain 'Unrelated'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Uses Get-DOConfig as last resort / Nutzt Get-DOConfig zuletzt' {
            Mock Get-DOConfig { [pscustomobject]@{ DownloadMode = 1 } }
            $report = & $doScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.EffectiveDownloadModeName | Should -Be 'Lan'
            $report.DownloadModeSource | Should -Be 'Get-DOConfig'
        }
        It 'Uses registry when cmdlets are unavailable / Nutzt Registry ohne Cmdlets' {
            Mock Get-Command { $null } -ParameterFilter { $Name -in @('Get-DeliveryOptimizationPerfSnap', 'Get-DOConfig') }
            $registry['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'] = @{ DODownloadMode = 0 }
            $report = & $doScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.EffectiveDownloadModeName | Should -Be 'HttpOnly'
        }
        It 'Fails without any data / Fehler ohne Daten' {
            Mock Get-Command { $null } -ParameterFilter { $Name -in @('Get-DeliveryOptimizationPerfSnap', 'Get-DOConfig') }
            $null = & $doScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $doScript -CustomField 'a-b'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkComponentStoreHealth' {
        It 'Reports a healthy store read-only / Meldet gesunden Speicher lesend' {
            Mock dism { $global:LASTEXITCODE = 0; 'Deployment Image Servicing and Management tool'; 'Image Version: 10.0.22631.4317'; 'No component store corruption detected.'; 'The operation completed successfully.' }
            $env:resultCustomField = 'componentStoreHealth'
            $report = & $dismScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Status | Should -Be 'Healthy'
            $report.ImageVersion | Should -Be '10.0.22631.4317'
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter { $Arguments -contains '/CheckHealth' -and $Arguments -contains '/English' -and $Arguments -notcontains '/RestoreHealth' }
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on repairable or corrupt stores / Warnt bei reparierbarem oder defektem Speicher' {
            Mock dism { $global:LASTEXITCODE = 0; 'The component store is repairable.'; 'The operation completed successfully.' }
            $report = & $dismScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'Repairable'
            Mock dism { $global:LASTEXITCODE = 14098; 'Error: 14098' }
            $report = & $dismScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Status | Should -Be 'Corrupt'
        }
        It 'Fails on DISM errors or unknown output / Fehler bei DISM-Fehlern' {
            Mock dism { $global:LASTEXITCODE = 740; 'Error: 740'; 'Elevated permissions are required to run DISM.' }
            $null = & $dismScript
            $LASTEXITCODE | Should -Be 1
            Mock dism { $global:LASTEXITCODE = 0; 'Unbekannte Ausgabe' }
            $null = & $dismScript
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            Mock dism { $global:LASTEXITCODE = 0; 'No component store corruption detected.' }
            $null = & $dismScript -CustomField '_field'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke dism -Times 0 -Exactly
        }
    }

    Context 'readOfficeUpdateChannel' {
        It 'Reports missing Office as OK / Ohne Office kein Befund' {
            $report = & $officeScript -ExpectedChannel Current | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Installed | Should -BeFalse
        }
        It 'Maps the installed channel / Ordnet den Kanal zu' {
            $registry['HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'] = @{
                VersionToReport = '16.0.17928.20156'; CDNBaseUrl = 'http://officecdn.microsoft.com/pr/492350F6-3A01-4F97-B9C0-C7C6DDF67D60'; UpdatesEnabled = 'True'
                UpdateChannel = 'http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6'
            }
            $env:resultCustomField = 'officeChannel'
            $report = & $officeScript -ExpectedChannel current | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.CurrentChannel | Should -Be 'Current'
            $report.TargetChannel | Should -Be 'MonthlyEnterprise'
            $report.ChannelChangePending | Should -BeTrue
            $report.Version | Should -Be '16.0.17928.20156'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on channel mismatch or disabled updates / Warnt bei Abweichung oder deaktivierten Updates' {
            $config = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
            $registry[$config] = @{ CDNBaseUrl = 'http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'; UpdatesEnabled = 'True' }
            $env:updateOfficeExpectedChannel = 'MonthlyEnterprise'
            $null = & $officeScript
            $LASTEXITCODE | Should -Be 2
            $env:updateOfficeExpectedChannel = $null
            $registry['HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate'] = @{ enableautomaticupdates = 0; updatebranch = 'FirstReleaseDeferred' }
            $report = & $officeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.TargetChannel | Should -Be 'SemiAnnualPreview'
            $registry.Remove('HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate')
            $registry[$config] = @{ CDNBaseUrl = '\\server\office'; UpdatesEnabled = 'False' }
            $report = & $officeScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.CurrentChannel | Should -Be 'Custom'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('Monthly', 'Current;', '*')) {
                $null = & $officeScript -ExpectedChannel $value
                $LASTEXITCODE | Should -Be 1
            }
            Should -Invoke Test-Path -Times 0 -Exactly
        }
    }
}
