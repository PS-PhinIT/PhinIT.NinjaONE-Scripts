BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = '06 - Bitlocker'
    $complianceScript = Join-Path $root "$folder/checkBitLockerCompliance.ps1"
    $suspendedScript = Join-Path $root "$folder/checkBitLockerSuspended.ps1"
    $policyScript = Join-Path $root "$folder/checkBitLockerPolicy.ps1"
    $preBootScript = Join-Path $root "$folder/checkPreBootAuthentication.ps1"
    $escrowScript = Join-Path $root "$folder/readRecoveryKeyEscrowEvents.ps1"
    $removableScript = Join-Path $root "$folder/checkRemovableDriveEncryption.ps1"
    $deviceScript = Join-Path $root "$folder/checkDeviceEncryptionSupport.ps1"
    $eventErrorScript = Join-Path $root "$folder/readBitLockerEventErrors.ps1"
    $winreScript = Join-Path $root "$folder/checkWinREStatus.ps1"
    $usedSpaceScript = Join-Path $root "$folder/checkUsedSpaceOnlyEncryption.ps1"

    # DE: Windows-Stubs, damit Mock unter Linux funktioniert. EN: Windows stubs so Mock works on Linux.
    function Get-BitLockerVolume { [CmdletBinding()] param($MountPoint) }
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Namespace, $Filter) }
    function Invoke-CimMethod { [CmdletBinding()] param($InputObject, $MethodName, $Arguments) }
    function Get-WinEvent { [CmdletBinding()] param($FilterHashtable, $MaxEvents) }
    function Get-Tpm { [CmdletBinding()] param() }
    function reagentc { }
    function Ninja-Property-Set { param($Name, $Value) }

    function New-TestVolume {
        param($MountPoint = 'C:', $VolumeType = 'OperatingSystem', $VolumeStatus = 'FullyEncrypted',
            $ProtectionStatus = 'On', $EncryptionMethod = 'XtsAes256', $Protectors = @('Tpm', 'RecoveryPassword'))
        [pscustomobject]@{
            MountPoint = $MountPoint; VolumeType = $VolumeType; VolumeStatus = $VolumeStatus
            ProtectionStatus = $ProtectionStatus; EncryptionMethod = $EncryptionMethod; EncryptionPercentage = 100
            KeyProtector = @($Protectors | ForEach-Object {
                [pscustomobject]@{ KeyProtectorId = '{' + [guid]::NewGuid().ToString() + '}'; KeyProtectorType = $_; RecoveryPassword = '111111-222222-333333-444444-555555-666666-777777-888888' }
            })
        }
    }
    function New-TestEvent {
        param([int]$Id, [datetime]$Time, [string]$Volume = 'C:', [int]$Level = 4, [string]$LogName = 'Microsoft-Windows-BitLocker/BitLocker Management', [string]$Message = 'Test message')
        $xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data Name='ProtectorGUID'>{00000000-1111-2222-3333-444444444444}</Data><Data Name='VolumeMountPoint'>$Volume</Data></EventData></Event>"
        $object = [pscustomobject]@{ Id = $Id; TimeCreated = $Time; Level = $Level; LogName = $LogName; Message = $Message; TestXml = $xml }
        $object | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.TestXml }
        $object
    }
}

Describe 'BitLocker catalogue checks / BitLocker-Katalogprüfungen' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('resultCustomField', 'bitlockerAllowedEncryptionMethods', 'bitlockerIncludeFixedDataDrives',
                'bitlockerExpectedMinimumMethod', 'bitlockerRequirePin', 'bitlockerEscrowDays', 'bitlockerEscrowMaxEvents',
                'bitlockerEscrowTarget', 'bitlockerEscrowRequireEvent', 'bitlockerRequireRemovableEncryption',
                'bitlockerRequireDeviceEncryptionSupport', 'bitlockerEventDays', 'bitlockerEventMaxEvents',
                'bitlockerEventMaxRecords', 'bitlockerRequireFullDiskEncryption', 'SystemDrive')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:SystemDrive = 'C:'
        Mock Ninja-Property-Set {}
        Mock Get-CimInstance { @() }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    Context 'checkBitLockerCompliance' {
        BeforeEach {
            Mock Get-BitLockerVolume { New-TestVolume; New-TestVolume -MountPoint 'D:' -VolumeType 'Data' -EncryptionMethod 'Aes256' }
            Mock Get-CimInstance { [pscustomobject]@{ DriveLetter = 'E:'; VolumeType = 2 } }
        }
        It 'Accepts compliant volumes / Akzeptiert konforme Volumes' {
            $report = & $complianceScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.NonCompliantVolumes | Should -Be 0
            @($report.Volumes).Count | Should -Be 2
        }
        It 'Warns on suspended or disallowed volumes and writes field / Warnt und schreibt Feld' {
            Mock Get-BitLockerVolume { New-TestVolume -ProtectionStatus 'Off'; New-TestVolume -MountPoint 'D:' -VolumeType 'Data' -EncryptionMethod 'Aes128' }
            $report = & $complianceScript -AllowedMethods 'XtsAes256' -CustomField 'bitlockerCompliance' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.NonCompliantVolumes | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'bitlockerCompliance' }
        }
        It 'Skips removable and data volumes when excluded / Überspringt Wechsel- und Datenvolumes' {
            Mock Get-BitLockerVolume { New-TestVolume; New-TestVolume -MountPoint 'E:' -VolumeType 'Data' -VolumeStatus 'FullyDecrypted' -EncryptionMethod 'None' }
            $null = & $complianceScript
            $LASTEXITCODE | Should -Be 0
            $env:bitlockerIncludeFixedDataDrives = 'false'
            Mock Get-BitLockerVolume { New-TestVolume; New-TestVolume -MountPoint 'D:' -VolumeType 'Data' -VolumeStatus 'FullyDecrypted' -EncryptionMethod 'None' }
            $null = & $complianceScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ AllowedMethods = 'Des' }, @{ IncludeFixedData = 'maybe' }, @{ CustomField = '1bad;name' })) {
                $null = & $complianceScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkBitLockerSuspended' {
        It 'Reports no suspended volume / Meldet kein angehaltenes Volume' {
            Mock Get-BitLockerVolume { New-TestVolume }
            $report = & $suspendedScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.SuspendedVolumes | Should -Be 0
        }
        It 'Reports suspended volume with reboot count / Meldet Neustartzähler' {
            Mock Get-BitLockerVolume { New-TestVolume -ProtectionStatus 'Off' }
            Mock Get-CimInstance { [pscustomobject]@{ DriveLetter = 'C:'; DeviceID = '\\?\Volume{1}\' } }
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; SuspendCount = 2 } }
            $report = & $suspendedScript -CustomField 'bitlockerSuspended' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Volumes[0].RemainingRebootCount | Should -Be 2
            Should -Invoke Invoke-CimMethod -Times 1 -ParameterFilter { $MethodName -eq 'GetSuspendCount' }
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Keeps reboot count null when unavailable / Zähler null wenn nicht verfügbar' {
            Mock Get-BitLockerVolume { New-TestVolume -ProtectionStatus 'Off' }
            Mock Get-CimInstance { [pscustomobject]@{ DriveLetter = 'C:' } }
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 50; SuspendCount = 0 } }
            $report = & $suspendedScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Volumes[0].RemainingRebootCount | Should -BeNullOrEmpty
            $report.Volumes[0].RebootCountSource | Should -Be 'Unavailable'
        }
        It 'Rejects invalid field names and query errors / Lehnt Feldnamen und Abfragefehler ab' {
            $null = & $suspendedScript -CustomField 'bad name'
            $LASTEXITCODE | Should -Be 1
            Mock Get-BitLockerVolume { throw 'Access denied' }
            $null = & $suspendedScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkBitLockerPolicy' {
        BeforeEach {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ItemProperty {
                if ($LiteralPath -like '*SOFTWARE*') {
                    [pscustomobject]@{ EncryptionMethodWithXtsOs = 7; EncryptionMethodWithXtsFdv = 6; EncryptionMethodWithXtsRdv = 4
                        UseAdvancedStartup = 1; UseTPM = 2; UseTPMPIN = 1; OSRecovery = 1; OSActiveDirectoryBackup = 1
                        OSRequireActiveDirectoryBackup = 1; OSActiveDirectoryInfoToStore = 1; OSEncryptionType = 2; MinimumPIN = 6
                        CustomValue = 'x'; PSPath = 'ignored' }
                } else { [pscustomobject]@{ RDVDenyWriteAccess = 1 } }
            }
        }
        It 'Decodes policy values / Dekodiert Richtlinienwerte' {
            $report = & $policyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Values.EncryptionMethodWithXtsOs | Should -Be 'XtsAes256 (7)'
            $report.Values.UseTPMPIN | Should -Be 'Require (1)'
            $report.Values.OSEncryptionType | Should -Be 'UsedSpaceOnly (2)'
            $report.Values.RDVDenyWriteAccess | Should -Be 'Enabled (1)'
            $report.Values.MinimumPIN | Should -Be '6'
            @($report.OtherValueNames) | Should -Be @('CustomValue')
        }
        It 'Warns when method is weaker than expected / Warnt bei schwächerem Verfahren' {
            $env:bitlockerExpectedMinimumMethod = 'xtsaes256'
            $report = & $policyScript -CustomField 'bitlockerPolicy' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Findings) | Should -Be @('EncryptionMethodWithXtsFdv:WeakerThanXtsAes256')
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Warns when no policy is configured / Warnt ohne Richtlinie' {
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            $report = & $policyScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Findings) | Should -Contain 'NotConfigured'
        }
        It 'Rejects unknown minimum methods / Lehnt unbekannte Verfahren ab' {
            $null = & $policyScript -ExpectedMinimumMethod 'Aes512'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkPreBootAuthentication' {
        It 'Accepts TPM protector without PIN requirement / Akzeptiert TPM ohne PIN-Pflicht' {
            Mock Get-BitLockerVolume { New-TestVolume }
            $output = & $preBootScript
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).HasTpmProtector | Should -BeTrue
            $output | Should -Not -Match '111111-222222'
        }
        It 'Warns on TPM-only when PIN is required / Warnt bei reinem TPM mit PIN-Pflicht' {
            Mock Get-BitLockerVolume { New-TestVolume }
            $report = & $preBootScript -RequirePin true -CustomField 'bitlockerPreBoot' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Issues) | Should -Be @('TpmOnlyWherePinRequired')
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Accepts TPM+PIN and warns without TPM / Akzeptiert TPM+PIN, warnt ohne TPM' {
            Mock Get-BitLockerVolume { New-TestVolume -Protectors @('TpmPin', 'RecoveryPassword') }
            $null = & $preBootScript -RequirePin true
            $LASTEXITCODE | Should -Be 0
            Mock Get-BitLockerVolume { New-TestVolume -Protectors @('RecoveryPassword') }
            $null = & $preBootScript
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $preBootScript -RequirePin 'yes'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readRecoveryKeyEscrowEvents' {
        It 'Accepts latest successful OS escrow / Akzeptiert letzten erfolgreichen Escrow' {
            Mock Get-WinEvent {
                New-TestEvent -Id 846 -Time (Get-Date).AddDays(-3)
                New-TestEvent -Id 845 -Time (Get-Date).AddDays(-1)
                New-TestEvent -Id 846 -Time (Get-Date).AddHours(-1) -Volume 'D:'
            }
            $report = & $escrowScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.LatestOsStatus | Should -Be 'Success'
            $report.LatestOsEvent.Target | Should -Be 'EntraId'
            $report.OsVolumeEvents | Should -Be 2
        }
        It 'Warns on latest failure and writes field / Warnt bei letztem Fehlschlag' {
            Mock Get-WinEvent { New-TestEvent -Id 784 -Time (Get-Date).AddDays(-2); New-TestEvent -Id 785 -Time (Get-Date).AddDays(-1) }
            $report = & $escrowScript -Target activedirectory -CustomField 'bitlockerEscrow' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.LatestOsStatus | Should -Be 'Failure'
            Should -Invoke Get-WinEvent -Times 1 -ParameterFilter { @($FilterHashtable.Id) -join ',' -eq '784,785' -and $MaxEvents -eq 200 }
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Handles no events configurable / Keine Ereignisse konfigurierbar' {
            Mock Get-WinEvent {
                $exception = New-Object System.Exception 'No events were found'
                throw (New-Object System.Management.Automation.ErrorRecord $exception, 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
            }
            $null = & $escrowScript
            $LASTEXITCODE | Should -Be 2
            $env:bitlockerEscrowRequireEvent = 'false'
            $null = & $escrowScript
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($arguments in @(@{ Days = '0' }, @{ MaxEvents = '5000' }, @{ Target = 'Cloud' }, @{ RequireEvent = 'x' })) {
                $null = & $escrowScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkRemovableDriveEncryption' {
        BeforeEach {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_EncryptableVolume') {
                    [pscustomobject]@{ DriveLetter = 'C:'; VolumeType = 0; ConversionStatus = 1; ProtectionStatus = 1 }
                    [pscustomobject]@{ DriveLetter = 'E:'; VolumeType = 2; ConversionStatus = 0; ProtectionStatus = 0 }
                } else {
                    [pscustomobject]@{ DeviceID = 'E:'; Size = 16GB }
                    [pscustomobject]@{ DeviceID = 'F:'; Size = $null }
                }
            }
        }
        It 'Reports only when policy does not require encryption / Nur Bericht ohne Richtlinie' {
            $report = & $removableScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.UnencryptedDrives | Should -Be 1
            @($report.Drives).Count | Should -Be 1
        }
        It 'Warns when policy denies write access / Warnt bei Richtlinie' {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*SYSTEM*' }
            Mock Get-ItemProperty { [pscustomobject]@{ RDVDenyWriteAccess = 1 } }
            $report = & $removableScript -CustomField 'removableEncryption' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.EncryptionRequired | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Accepts encrypted or locked drives when required / Akzeptiert verschlüsselte Laufwerke' {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_EncryptableVolume') {
                    [pscustomobject]@{ DriveLetter = 'E:'; VolumeType = 2; ConversionStatus = 1; ProtectionStatus = 1 }
                    [pscustomobject]@{ DriveLetter = 'G:'; VolumeType = 2; ConversionStatus = $null; ProtectionStatus = 2 }
                }
            }
            $null = & $removableScript -RequireEncrypted true
            $LASTEXITCODE | Should -Be 0
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $removableScript -RequireEncrypted 'always'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkDeviceEncryptionSupport' {
        BeforeEach {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ItemProperty {
                switch -Wildcard ($LiteralPath) {
                    '*\BitLockerStatus' { [pscustomobject]@{ BootStatus = 0 } }
                    '*\BitLocker' { [pscustomobject]@{ Other = 1 } }
                    '*\SecureBoot\State' { [pscustomobject]@{ UEFISecureBootEnabled = 1 } }
                    default { [pscustomobject]@{ PEFirmwareType = 2 } }
                }
            }
            Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $true; TpmReady = $true } }
        }
        It 'Reports supported device / Meldet unterstütztes Gerät' {
            $report = & $deviceScript -RequireSupport true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Supported | Should -BeTrue
            $report.FirmwareType | Should -Be 'UEFI'
        }
        It 'Is informational by default and warns when required / Info standardmäßig, Warnung bei Pflicht' {
            Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $false; TpmReady = $false } }
            $report = & $deviceScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Reasons) | Should -Contain 'TpmNotPresent'
            $env:bitlockerRequireDeviceEncryptionSupport = 'true'
            $null = & $deviceScript -CustomField 'deviceEncryption'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Detects PreventDeviceEncryption / Erkennt PreventDeviceEncryption' {
            Mock Get-ItemProperty { [pscustomobject]@{ PreventDeviceEncryption = 1; PEFirmwareType = 2; UEFISecureBootEnabled = 1 } }
            $report = & $deviceScript -RequireSupport 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.Reasons) | Should -Be @('PreventDeviceEncryptionSet')
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $deviceScript -RequireSupport 'sometimes'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readBitLockerEventErrors' {
        It 'Reports no events as OK / Keine Ereignisse sind OK' {
            Mock Get-WinEvent {
                $exception = New-Object System.Exception 'No events'
                throw (New-Object System.Management.Automation.ErrorRecord $exception, 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
            }
            $report = & $eventErrorScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalEvents | Should -Be 0
            Should -Invoke Get-WinEvent -Times 4 -ParameterFilter { $MaxEvents -eq 200 -and (@($FilterHashtable.Level) -join ',') -eq '2,3' }
        }
        It 'Groups errors by id and redacts secrets / Gruppiert und maskiert' {
            Mock Get-WinEvent {
                if ($FilterHashtable.LogName -eq 'Microsoft-Windows-BitLocker/BitLocker Management') {
                    New-TestEvent -Id 846 -Level 2 -Time (Get-Date).AddHours(-2) -Message "Failed 111111-222222-333333-444444-555555-666666-777777-888888`r`nDetails"
                    New-TestEvent -Id 846 -Level 2 -Time (Get-Date).AddHours(-1)
                    New-TestEvent -Id 775 -Level 3 -Time (Get-Date).AddHours(-1)
                }
            }
            $output = & $eventErrorScript -CustomField 'bitlockerEvents'
            $LASTEXITCODE | Should -Be 2
            $report = $output | ConvertFrom-Json
            $report.ErrorEvents | Should -Be 2
            $report.TotalGroups | Should -Be 2
            ($report.Groups | Where-Object { $_.Id -eq 846 }).Count | Should -Be 2
            $output | Should -Not -Match '111111-222222'
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Reports warnings only as OK and lists missing logs / Nur Warnungen sind OK' {
            Mock Get-WinEvent {
                if ($FilterHashtable.LogName -like '*DrivePreparationTool*') {
                    $exception = New-Object System.Exception 'No log'
                    throw (New-Object System.Management.Automation.ErrorRecord $exception, 'NoMatchingLogsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
                }
                New-TestEvent -Id 775 -Level 3 -Time (Get-Date).AddHours(-1) -LogName $FilterHashtable.LogName
            }
            $report = & $eventErrorScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.MissingLogs).Count | Should -Be 2
            $report.Truncated | Should -BeTrue
        }
        It 'Rejects invalid input and query errors / Lehnt Eingaben und Abfragefehler ab' {
            foreach ($arguments in @(@{ Days = '91' }, @{ MaxEvents = 'abc' }, @{ MaxRecords = '0' })) {
                $null = & $eventErrorScript @arguments
                $LASTEXITCODE | Should -Be 1
            }
            Mock Get-WinEvent { throw 'Access denied' }
            $null = & $eventErrorScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkWinREStatus' {
        It 'Detects enabled WinRE / Erkennt aktiviertes WinRE' {
            Mock reagentc {
                $global:LASTEXITCODE = 0
                'Windows RE status:         Enabled'
                'Windows RE location:       \\?\GLOBALROOT\device\harddisk0\partition4\Recovery\WindowsRE'
                'Boot Configuration Data (BCD) identifier: 5a8b6f0e-1111-2222-3333-444455556666'
            }
            $report = & $winreScript -CustomField 'winreStatus' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.WinREStatus | Should -Be 'Enabled'
            $report.PartitionNumber | Should -Be 4
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Detects disabled WinRE locale-independently / Erkennt deaktiviertes WinRE' {
            Mock reagentc {
                $global:LASTEXITCODE = 0
                'Status der Windows RE:     Deaktiviert'
                'Speicherort der Windows RE:'
                'BCD-ID (Startkonfigurationsdaten): 00000000-0000-0000-0000-000000000000'
            }
            $report = & $winreScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.WinREStatus | Should -Be 'Disabled'
        }
        It 'Fails on reagentc errors and unparseable output / Fehler bei reagentc' {
            Mock reagentc { $global:LASTEXITCODE = 5; 'Access denied' }
            $null = & $winreScript
            $LASTEXITCODE | Should -Be 1
            Mock reagentc { $global:LASTEXITCODE = 0; 'Unbekannte Ausgabe' }
            $null = & $winreScript
            $LASTEXITCODE | Should -Be 1
            $null = & $winreScript -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkUsedSpaceOnlyEncryption' {
        BeforeEach {
            Mock Get-CimInstance {
                [pscustomobject]@{ DriveLetter = 'C:'; DeviceID = '\\?\Volume{1}\'; VolumeType = 0 }
                [pscustomobject]@{ DriveLetter = 'E:'; DeviceID = '\\?\Volume{2}\'; VolumeType = 2 }
            }
            Mock Invoke-CimMethod {
                if ($InputObject.DriveLetter -eq 'C:') { [pscustomobject]@{ ReturnValue = 0; ConversionStatus = 1; EncryptionFlags = 0 } }
                else { [pscustomobject]@{ ReturnValue = 0; ConversionStatus = 1; EncryptionFlags = 1 } }
            }
        }
        It 'Reports full disk and used space only modes / Meldet Modi' {
            $report = & $usedSpaceScript -RequireFullDisk true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Volumes | Where-Object { $_.Volume -eq 'C:' }).Mode | Should -Be 'FullDisk'
            ($report.Volumes | Where-Object { $_.Volume -eq 'E:' }).Mode | Should -Be 'UsedSpaceOnly'
            Should -Invoke Invoke-CimMethod -Times 2 -ParameterFilter { $MethodName -eq 'GetConversionStatus' -and $Arguments.PrecisionFactor -eq 0 }
        }
        It 'Warns on used space only OS volume when required / Warnt bei Pflicht' {
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; ConversionStatus = 1; EncryptionFlags = 1 } }
            $null = & $usedSpaceScript
            $LASTEXITCODE | Should -Be 0
            $env:bitlockerRequireFullDiskEncryption = 'true'
            $null = & $usedSpaceScript -CustomField 'bitlockerMode'
            $LASTEXITCODE | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1
        }
        It 'Reports locked volumes as Unknown / Gesperrte Volumes als Unknown' {
            Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 2150694912 } }
            $report = & $usedSpaceScript -RequireFullDisk true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.UnknownVolumes | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $usedSpaceScript -RequireFullDisk 'full'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
