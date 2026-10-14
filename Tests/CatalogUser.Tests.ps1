BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:paths = @{}
    foreach ($name in @('readLoggedOnUsers', 'checkInactiveLocalUsers', 'checkPasswordNeverExpires', 'checkStaleProfiles',
            'readUserProfileSizes', 'checkTemporaryProfiles', 'readRdpSessionHistory', 'readLogonEvents',
            'checkLockedOutUsers', 'readEntraJoinStatus', 'checkAutoLogon')) {
        $script:paths[$name] = Join-Path $root ('11 - User/{0}.ps1' -f $name)
    }
    # DE: Windows-, Native- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows, native and NinjaOne calls.
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Namespace, $Filter) }
    function Invoke-CimMethod { [CmdletBinding()] param($InputObject, $MethodName) }
    function Get-LocalUser { [CmdletBinding()] param($Name) }
    function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $MaxEvents, $LogName) }
    function quser { }
    function dsregcmd { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }

    function New-TestEvent {
        param([int]$Id, [datetime]$Time, [string]$Xml)
        $logEvent = [pscustomobject]@{ Id = $Id; TimeCreated = $Time; XmlText = $Xml }
        $logEvent | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.XmlText }
        $logEvent
    }
    function New-EventDataXml {
        param([hashtable]$Data)
        $items = foreach ($key in $Data.Keys) { '<Data Name="{0}">{1}</Data>' -f $key, $Data[$key] }
        '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>{0}</EventData></Event>' -f ($items -join '')
    }
    function New-RegistryKeyStub {
        param([hashtable]$Values, [string[]]$SubKeys)
        $key = [pscustomobject]@{ Values = $Values; SubKeys = $SubKeys; Requested = (New-Object System.Collections.Generic.List[string]) }
        $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { @($this.Values.Keys) }
        $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($ValueName) $this.Requested.Add($ValueName); $this.Values[$ValueName] }
        $key | Add-Member -MemberType ScriptMethod -Name GetSubKeyNames -Value { @($this.SubKeys) }
        $key
    }
    $script:noEvents = {
        throw [System.Management.Automation.ErrorRecord]::new([Exception]::new('No events were found'),
            'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
    }
    $script:envNames = @('userMaxRecords', 'userInactiveDays', 'userExcludeBuiltIn', 'userPasswordCheckMode', 'userPasswordAllowlist',
        'userStaleProfileDays', 'userStaleIncludeUnknown', 'userProfileSizeBudgetSeconds', 'userProfileSizeThresholdGB',
        'userTempProfileEventDays', 'userRdpHistoryDays', 'userRdpMaxEvents', 'userLogonTypes', 'userLogonEventDays',
        'userLogonMaxEvents', 'userLockoutEventHours', 'userExpectedJoinType', 'resultCustomField')
}

Describe 'User catalogue scripts / Benutzer-Katalogskripte' {
    BeforeEach {
        $saved = @{}
        foreach ($name in $script:envNames) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Ninja-Property-Set {}
        Mock Get-CimInstance {}
        Mock Get-WinEvent $script:noEvents
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'readLoggedOnUsers' {
        It 'Parses quser output including disconnected sessions / Parst quser inkl. getrennter Sitzungen' {
            Mock quser {
                $global:LASTEXITCODE = 0
                ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
                '>alice                 console             1  Active      none   10/14/2026 9:00 AM'
                ' bob                                       2  Disc         1:05  10/14/2026 8:00 AM'
                ' carol                 rdp-tcp#3           3  Active         .   10/14/2026 7:30 AM'
            }
            $report = (& $script:paths.readLoggedOnUsers) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.method | Should -Be 'quser'
            $report.total | Should -Be 3
            ($report.records | Where-Object userName -eq 'alice').sessionType | Should -Be 'Console'
            ($report.records | Where-Object userName -eq 'bob').sessionType | Should -Be 'None (disconnected)'
            ($report.records | Where-Object userName -eq 'carol').sessionType | Should -Be 'RDP'
            ($report.records | Where-Object userName -eq 'carol').logonTime | Should -Be '10/14/2026 7:30 AM'
        }
        It 'Treats "No User exists" as no sessions / Behandelt "No User exists" als keine Sitzungen' {
            Mock quser { $global:LASTEXITCODE = 1; 'No User exists for *' }
            $report = (& $script:paths.readLoggedOnUsers -CustomField 'loggedOn') | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 0
            Should -Invoke Get-CimInstance -Times 0 -Exactly
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'loggedOn' }
        }
        It 'Falls back to explorer.exe owners / Faellt auf explorer.exe-Besitzer zurueck' {
            Mock quser { $global:LASTEXITCODE = 5; 'Error 0x00000005' }
            Mock Get-CimInstance { [pscustomobject]@{ SessionId = 2; CreationDate = (Get-Date) }; [pscustomobject]@{ SessionId = 2; CreationDate = (Get-Date) } }
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; User = 'dave'; Domain = 'CONTOSO' } }
            $report = (& $script:paths.readLoggedOnUsers) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.method | Should -Match 'Win32_Process'
            $report.total | Should -Be 1
            $report.records[0].userName | Should -Be 'CONTOSO\dave'
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $env:userMaxRecords = '0'
            $null = & $script:paths.readLoggedOnUsers
            $LASTEXITCODE | Should -Be 1
            $null = & $script:paths.readLoggedOnUsers -MaxRecords 5 -CustomField '1bad'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkInactiveLocalUsers' {
        BeforeEach {
            Mock Get-LocalUser {
                [pscustomobject]@{ Name = 'Administrator'; Enabled = $true; SID = 'S-1-5-21-1-2-3-500'; LastLogon = $null }
                [pscustomobject]@{ Name = 'alice'; Enabled = $true; SID = 'S-1-5-21-1-2-3-1001'; LastLogon = (Get-Date).AddDays(-5) }
                [pscustomobject]@{ Name = 'old'; Enabled = $false; SID = 'S-1-5-21-1-2-3-1002'; LastLogon = $null }
            }
        }
        It 'Passes when only built-in or disabled accounts are idle / OK bei nur integrierten/deaktivierten Konten' {
            $report = (& $script:paths.checkInactiveLocalUsers) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.excludedBuiltInCount | Should -Be 1
            $report.total | Should -Be 0
        }
        It 'Warns for inactive or never-used accounts / Warnt bei inaktiven Konten' {
            $env:userExcludeBuiltIn = 'false'
            $env:resultCustomField = 'inactiveUsers'
            $report = (& $script:paths.checkInactiveLocalUsers -InactiveDays 3) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.total | Should -Be 2
            $report.records[0].name | Should -Be 'Administrator'
            $report.records[0].neverLoggedOn | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'inactiveUsers' }
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('0', '3651', 'abc')) {
                $null = & $script:paths.checkInactiveLocalUsers -InactiveDays $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $script:paths.checkInactiveLocalUsers -ExcludeBuiltIn 'yes'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-LocalUser -Times 0 -Exactly
        }
    }

    Context 'checkPasswordNeverExpires' {
        BeforeEach {
            Mock Get-LocalUser {
                [pscustomobject]@{ Name = 'alice'; Enabled = $true; PasswordExpires = (Get-Date).AddDays(10); PasswordRequired = $true }
                [pscustomobject]@{ Name = 'svcBackup'; Enabled = $true; PasswordExpires = $null; PasswordRequired = $true }
                [pscustomobject]@{ Name = 'Guest'; Enabled = $false; PasswordExpires = $null; PasswordRequired = $false }
            }
        }
        It 'Warns for never-expiring passwords / Warnt bei nie ablaufenden Kennwoertern' {
            $report = (& $script:paths.checkPasswordNeverExpires) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.alertCount | Should -Be 1
            $report.records[0].name | Should -Be 'svcBackup'
        }
        It 'Accepts allowlisted accounts / Akzeptiert erlaubte Konten' {
            $env:userPasswordAllowlist = 'SVCBACKUP, kiosk'
            $report = (& $script:paths.checkPasswordNeverExpires -CustomField 'pwdFlags') | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.records[0].allowlisted | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'NotRequired mode ignores expiry / NotRequired ignoriert Ablauf' {
            $null = & $script:paths.checkPasswordNeverExpires -CheckMode NotRequired
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($list in @('a,,b', 'bad*name', 'waytoolongaccountname123')) {
                $null = & $script:paths.checkPasswordNeverExpires -Allowlist $list
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $script:paths.checkPasswordNeverExpires -CheckMode 'Everything'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkStaleProfiles' {
        BeforeEach {
            Mock Get-CimInstance {
                [pscustomobject]@{ LocalPath = 'C:\Users\alice'; Special = $false; Loaded = $false; LastUseTime = (Get-Date).AddDays(-200); SID = 'S-1-5-21-1-2-3-1001' }
                [pscustomobject]@{ LocalPath = 'C:\Users\bob'; Special = $false; Loaded = $true; LastUseTime = (Get-Date).AddDays(-400); SID = 'S-1-5-21-1-2-3-1002' }
                [pscustomobject]@{ LocalPath = 'C:\Users\carol'; Special = $false; Loaded = $false; LastUseTime = $null; SID = 'S-1-5-21-1-2-3-1003' }
                [pscustomobject]@{ LocalPath = 'C:\Windows\system32\config\systemprofile'; Special = $true; Loaded = $false; LastUseTime = (Get-Date).AddDays(-900); SID = 'S-1-5-18' }
            } -ParameterFilter { $ClassName -eq 'Win32_UserProfile' }
        }
        It 'Warns for stale unloaded profiles without SIDs / Warnt ohne SIDs' {
            $output = & $script:paths.checkStaleProfiles
            $LASTEXITCODE | Should -Be 2
            $report = $output | ConvertFrom-Json
            $report.total | Should -Be 1
            $report.records[0].profileFolder | Should -Be 'alice'
            $report.unknownUseTime | Should -Be 1
            ($output -join "`n") | Should -Not -Match 'S-1-5-21'
        }
        It 'Optionally counts unknown use times / Zaehlt optional unbekannte Zeiten' {
            $report = (& $script:paths.checkStaleProfiles -IncludeUnknown true -CustomField 'staleProfiles') | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.total | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Passes with a high threshold / OK bei hoher Grenze' {
            $null = & $script:paths.checkStaleProfiles -StaleDays 365
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $script:paths.checkStaleProfiles -StaleDays '-1'
            $LASTEXITCODE | Should -Be 1
            $null = & $script:paths.checkStaleProfiles -IncludeUnknown 'maybe'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readUserProfileSizes' {
        BeforeEach {
            $usersRoot = Join-Path $TestDrive 'Users'
            $alice = Join-Path $usersRoot 'alice'
            $bob = Join-Path $usersRoot 'bob'
            $null = New-Item -ItemType Directory -Path (Join-Path $alice 'Documents') -Force
            $null = New-Item -ItemType Directory -Path $bob -Force
            $stream = [IO.File]::Create((Join-Path $alice 'Documents/big.bin'))
            try { $stream.SetLength(30MB) } finally { $stream.Dispose() }
            [IO.File]::WriteAllText((Join-Path $bob 'small.txt'), 'hello')
            if (-not (Test-Path (Join-Path $bob 'link'))) { $null = New-Item -ItemType SymbolicLink -Path (Join-Path $bob 'link') -Target $alice }
            $profileRoots = @($alice, $bob)
            Mock Get-CimInstance {
                [pscustomobject]@{ LocalPath = $profileRoots[0]; Special = $false; Loaded = $false }
                [pscustomobject]@{ LocalPath = $profileRoots[1]; Special = $false; Loaded = $true }
                [pscustomobject]@{ LocalPath = 'C:\Users\gone'; Special = $false; Loaded = $false }
            } -ParameterFilter { $ClassName -eq 'Win32_UserProfile' }
        }
        It 'Measures sizes and skips reparse points / Misst Groessen ohne Reparse-Punkte' {
            $report = (& $script:paths.readUserProfileSizes) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 3
            $aliceRecord = $report.records | Where-Object profileFolder -eq 'alice'
            $bobRecord = $report.records | Where-Object profileFolder -eq 'bob'
            $aliceRecord.sizeGB | Should -Be 0.03
            $aliceRecord.partial | Should -BeFalse
            $bobRecord.fileCount | Should -Be 1
            $bobRecord.skippedReparsePoints | Should -Be 1
            ($report.records | Where-Object profileFolder -eq 'gone').missing | Should -BeTrue
        }
        It 'Warns above the threshold / Warnt ueber der Grenze' {
            $env:userProfileSizeThresholdGB = '0.02'
            $report = (& $script:paths.readUserProfileSizes -CustomField 'profileSizes') | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.aboveThresholdCount | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'profileSizes' }
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($value in @('1,5', '0', 'abc', '200000')) {
                $null = & $script:paths.readUserProfileSizes -ThresholdGB $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $script:paths.readUserProfileSizes -TimeBudgetSeconds 2
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkTemporaryProfiles' {
        BeforeEach {
            $profileKeys = @(
                [pscustomobject]@{ PSChildName = 'S-1-5-21-1-2-3-1001'; PSPath = 'key1' }
                [pscustomobject]@{ PSChildName = 'S-1-5-21-1-2-3-1002'; PSPath = 'key2' }
            )
            $profileValues = @{
                key1 = [pscustomobject]@{ ProfileImagePath = 'C:\Users\alice'; State = 0 }
                key2 = [pscustomobject]@{ ProfileImagePath = 'C:\Users\bob'; State = 0x100 }
                key3 = [pscustomobject]@{ ProfileImagePath = 'C:\Users\TEMP'; State = 0x804 }
            }
            Mock Get-ChildItem { $profileKeys } -ParameterFilter { "$LiteralPath" -like '*ProfileList' }
            Mock Get-ItemProperty { $profileValues["$LiteralPath"] } -ParameterFilter { "$LiteralPath" -like 'key*' }
        }
        It 'Passes for healthy profiles / OK bei gesunden Profilen' {
            $report = (& $script:paths.checkTemporaryProfiles) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 0
            $report.profileListKeys | Should -Be 2
        }
        It 'Detects .bak keys, temp state and events / Erkennt .bak, Temp-State und Ereignisse' {
            $profileKeys += [pscustomobject]@{ PSChildName = 'S-1-5-21-1-2-3-1001.bak'; PSPath = 'key3' }
            Mock Get-WinEvent { New-TestEvent -Id 1511 -Time (Get-Date).AddHours(-2) -Xml '<Event />' }
            $output = & $script:paths.checkTemporaryProfiles -CustomField 'tempProfiles'
            $LASTEXITCODE | Should -Be 2
            $report = $output | ConvertFrom-Json
            $report.total | Should -Be 2
            $registry = $report.records | Where-Object source -eq 'ProfileList'
            $registry.finding | Should -Match 'BackupKey'
            $registry.finding | Should -Match 'StateTempAssigned'
            $registry.finding | Should -Match 'TempProfileImagePath'
            $registry.state | Should -Be '0x804'
            ($output -join "`n") | Should -Not -Match 'S-1-5-21'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Detects temporary status via CIM / Erkennt Temporary-Status per CIM' {
            Mock Get-CimInstance { [pscustomobject]@{ LocalPath = 'C:\Users\TEMP.CONTOSO'; Status = 1 } } -ParameterFilter { $ClassName -eq 'Win32_UserProfile' }
            $report = (& $script:paths.checkTemporaryProfiles) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.records[0].profileFolder | Should -Be 'TEMP.CONTOSO'
        }
        It 'Reports real event log errors / Meldet echte Ereignisprotokollfehler' {
            Mock Get-WinEvent { throw 'Access denied' }
            $null = & $script:paths.checkTemporaryProfiles
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $script:paths.checkTemporaryProfiles -EventDays 366
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readRdpSessionHistory' {
        It 'Parses user and source address / Parst Benutzer und Quelladresse' {
            $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><UserData><EventXML xmlns="Event_NS"><User>CONTOSO\alice</User><SessionID>3</SessionID><Address>10.0.0.5</Address></EventXML></UserData></Event>'
            Mock Get-WinEvent {
                New-TestEvent -Id 21 -Time (Get-Date).AddHours(-3) -Xml $xml
                New-TestEvent -Id 24 -Time (Get-Date).AddHours(-1) -Xml $xml
            }
            $report = (& $script:paths.readRdpSessionHistory -CustomField 'rdpHistory') | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 2
            $report.records[0].action | Should -Be 'Disconnect'
            $report.records[0].user | Should -Be 'CONTOSO\alice'
            $report.records[0].sourceAddress | Should -Be '10.0.0.5'
            $report.actionCounts.Logon | Should -Be 1
            $report.distinctUsers | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
            Should -Invoke Get-WinEvent -Times 1 -Exactly -ParameterFilter { $MaxEvents -eq 500 -and $FilterHashtable.Id -contains 25 }
        }
        It 'Treats no events as success / Keine Ereignisse sind kein Fehler' {
            $report = (& $script:paths.readRdpSessionHistory) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.total | Should -Be 0
        }
        It 'Truncates oversized lists / Kuerzt zu lange Listen' {
            $xml = '<Event><UserData><EventXML><User>CONTOSO\{0}</User><SessionID>3</SessionID><Address>10.0.0.5</Address></EventXML></UserData></Event>' -f ('u' * 60)
            Mock Get-WinEvent { foreach ($i in 1..100) { New-TestEvent -Id 21 -Time (Get-Date).AddMinutes(-$i) -Xml $xml } }
            $output = & $script:paths.readRdpSessionHistory -MaxRecords 100
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n").Length | Should -BeLessOrEqual 4000
            ($output | ConvertFrom-Json).truncated | Should -BeTrue
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $env:userRdpHistoryDays = '91'
            $null = & $script:paths.readRdpSessionHistory
            $LASTEXITCODE | Should -Be 1
            $null = & $script:paths.readRdpSessionHistory -Days 7 -MaxEvents 5
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readLogonEvents' {
        It 'Aggregates interactive logons and excludes system accounts / Aggregiert und filtert Systemkonten' {
            $logonEvents = @(
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-1) -Xml (New-EventDataXml @{ TargetUserName = 'alice'; TargetDomainName = 'CONTOSO'; TargetUserSid = 'S-1-5-21-1-2-3-1001'; LogonType = '10' })
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-5) -Xml (New-EventDataXml @{ TargetUserName = 'alice'; TargetDomainName = 'CONTOSO'; TargetUserSid = 'S-1-5-21-1-2-3-1001'; LogonType = '2' })
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-2) -Xml (New-EventDataXml @{ TargetUserName = 'bob'; TargetDomainName = 'CONTOSO'; TargetUserSid = 'S-1-5-21-1-2-3-1002'; LogonType = '3' })
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-2) -Xml (New-EventDataXml @{ TargetUserName = 'PC01$'; TargetDomainName = 'CONTOSO'; TargetUserSid = 'S-1-5-21-1-2-3-2001'; LogonType = '2' })
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-2) -Xml (New-EventDataXml @{ TargetUserName = 'DWM-1'; TargetDomainName = 'Window Manager'; TargetUserSid = 'S-1-5-90-0-1'; LogonType = '2' })
                New-TestEvent -Id 4624 -Time (Get-Date).AddHours(-2) -Xml (New-EventDataXml @{ TargetUserName = 'SYSTEM'; TargetDomainName = 'NT AUTHORITY'; TargetUserSid = 'S-1-5-18'; LogonType = '2' })
            )
            Mock Get-WinEvent { $logonEvents }
            $output = & $script:paths.readLogonEvents -CustomField 'logonSummary'
            $LASTEXITCODE | Should -Be 0
            $report = $output | ConvertFrom-Json
            $report.total | Should -Be 1
            $report.matchingEvents | Should -Be 2
            $report.records[0].user | Should -Be 'CONTOSO\alice'
            $report.records[0].logonCount | Should -Be 2
            @($report.records[0].logonTypes) | Should -Be @(2, 10)
            ($output -join "`n") | Should -Not -Match 'S-1-5-21'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Honors configured logon types / Beachtet konfigurierte Typen' {
            Mock Get-WinEvent { New-TestEvent -Id 4624 -Time (Get-Date) -Xml (New-EventDataXml @{ TargetUserName = 'bob'; TargetDomainName = 'CONTOSO'; TargetUserSid = 'S-1-5-21-1-2-3-1002'; LogonType = '3' }) }
            $env:userLogonTypes = '3'
            $report = (& $script:paths.readLogonEvents) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.records[0].user | Should -Be 'CONTOSO\bob'
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            foreach ($types in @('1', '2,,10', 'abc', '6')) {
                $null = & $script:paths.readLogonEvents -LogonTypes $types
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $script:paths.readLogonEvents -MaxEvents 50
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkLockedOutUsers' {
        It 'Passes without lockouts / OK ohne Sperren' {
            $report = (& $script:paths.checkLockedOutUsers) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.lockedNow | Should -Be 0
        }
        It 'Warns for locked accounts and lists 4740 events / Warnt bei Sperren und listet 4740' {
            Mock Get-CimInstance { [pscustomobject]@{ Name = 'alice'; Lockout = $true } } -ParameterFilter { $ClassName -eq 'Win32_UserAccount' -and $Filter -match 'Lockout = True' }
            Mock Get-WinEvent { New-TestEvent -Id 4740 -Time (Get-Date).AddHours(-1) -Xml (New-EventDataXml @{ TargetUserName = 'alice'; TargetDomainName = 'PC01'; TargetSid = 'S-1-5-21-1-2-3-1001' }) }
            $output = & $script:paths.checkLockedOutUsers -CustomField 'lockouts'
            $LASTEXITCODE | Should -Be 2
            $report = $output | ConvertFrom-Json
            $report.total | Should -Be 2
            ($report.records | Where-Object source -eq 'Event4740').callerComputer | Should -Be 'PC01'
            ($output -join "`n") | Should -Not -Match 'S-1-5-21'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Events alone are informational / Ereignisse allein sind informativ' {
            Mock Get-WinEvent { New-TestEvent -Id 4740 -Time (Get-Date) -Xml (New-EventDataXml @{ TargetUserName = 'bob'; TargetDomainName = 'PC02' }) }
            $null = & $script:paths.checkLockedOutUsers
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $script:paths.checkLockedOutUsers -EventHours 721
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readEntraJoinStatus' {
        BeforeEach {
            Mock dsregcmd {
                $global:LASTEXITCODE = 0
                '+----------------------------------------------------------------------+'
                '| Device State                                                         |'
                '+----------------------------------------------------------------------+'
                '             AzureAdJoined : YES'
                '          EnterpriseJoined : NO'
                '              DomainJoined : YES'
                '                DomainName : CONTOSO'
                '                  DeviceId : 11111111-2222-3333-4444-555555555555'
                '                Thumbprint : ABCDEF0123456789'
                '                TenantName : Contoso'
                '                  TenantId : 99999999-8888-7777-6666-555555555555'
                '          DeviceAuthStatus : SUCCESS'
                '                AzureAdPrt : NO'
            }
        }
        It 'Parses device state as hybrid / Parst Geraetestatus als Hybrid' {
            $output = & $script:paths.readEntraJoinStatus
            $LASTEXITCODE | Should -Be 0
            $report = $output | ConvertFrom-Json
            $report.joinType | Should -Be 'HybridJoined'
            $report.deviceState.TenantName | Should -Be 'Contoso'
            $report.deviceState.KeySignTest | Should -BeNullOrEmpty
            ($output -join "`n") | Should -Not -Match 'ABCDEF0123456789'
            ($output -join "`n") | Should -Not -Match 'AzureAdPrt'
        }
        It 'Warns on join type mismatch / Warnt bei abweichendem Typ' {
            $env:userExpectedJoinType = 'EntraJoined'
            $env:resultCustomField = 'joinState'
            $null = & $script:paths.readEntraJoinStatus
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'joinState' }
        }
        It 'Fails on dsregcmd errors / Fehler bei dsregcmd-Fehlern' {
            Mock dsregcmd { $global:LASTEXITCODE = 1; 'error' }
            $null = & $script:paths.readEntraJoinStatus
            $LASTEXITCODE | Should -Be 1
        }
        It 'Rejects invalid input / Lehnt ungueltige Eingaben ab' {
            $null = & $script:paths.readEntraJoinStatus -ExpectedJoinType 'AADJ'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkAutoLogon' {
        BeforeEach {
            $secretKey = New-RegistryKeyStub -Values @{} -SubKeys @('NL$KM')
            Mock Get-Item { $winlogonKey } -ParameterFilter { "$LiteralPath" -like '*Winlogon' }
            Mock Get-Item { $secretKey } -ParameterFilter { "$LiteralPath" -like '*Secrets' }
        }
        It 'Passes when autologon is off / OK wenn Autologon aus' {
            $winlogonKey = New-RegistryKeyStub -Values @{ AutoAdminLogon = '0'; DefaultUserName = 'alice' }
            $report = (& $script:paths.checkAutoLogon) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.autoAdminLogonEnabled | Should -BeFalse
            $report.lsaSecretDefaultPassword | Should -Be 'Absent'
        }
        It 'Warns on plaintext password without reading it / Warnt ohne Kennwort zu lesen' {
            $winlogonKey = New-RegistryKeyStub -Values @{ AutoAdminLogon = '1'; DefaultUserName = 'kiosk'; DefaultPassword = 'S3cr3t!Value'; AutoLogonCount = 3 }
            $secretKey = New-RegistryKeyStub -Values @{} -SubKeys @('DefaultPassword')
            $output = & $script:paths.checkAutoLogon -CustomField 'autoLogon'
            $LASTEXITCODE | Should -Be 2
            $report = $output | ConvertFrom-Json
            $report.plaintextDefaultPasswordPresent | Should -BeTrue
            $report.lsaSecretDefaultPassword | Should -Be 'Present'
            $report.autoLogonCount | Should -Be 3
            ($output -join "`n") | Should -Not -Match 'S3cr3t'
            $winlogonKey.Requested | Should -Not -Contain 'DefaultPassword'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Value -notmatch 'S3cr3t' }
        }
        It 'Reports LSA access problems as Unknown / Meldet LSA-Zugriffsprobleme als Unknown' {
            $winlogonKey = New-RegistryKeyStub -Values @{}
            Mock Get-Item { throw 'Access denied' } -ParameterFilter { "$LiteralPath" -like '*Secrets' }
            $report = (& $script:paths.checkAutoLogon) | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.lsaSecretDefaultPassword | Should -Be 'Unknown'
        }
        It 'Rejects invalid input and field write errors / Lehnt ungueltige Eingaben und Schreibfehler ab' {
            $winlogonKey = New-RegistryKeyStub -Values @{ AutoAdminLogon = '0' }
            $null = & $script:paths.checkAutoLogon -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 4 }
            $null = & $script:paths.checkAutoLogon -CustomField 'autoLogon'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
