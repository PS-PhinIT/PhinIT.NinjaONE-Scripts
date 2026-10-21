BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:updateScript = Join-Path $root 'Installations-Scripte/updateWinGet.ps1'
    $appsRoot = 'C:\Program Files\WindowsApps'
    $oldDir = 'Microsoft.DesktopAppInstaller_1.31.220.0_x64__8wekyb3d8bbwe'
    $newDir = 'Microsoft.DesktopAppInstaller_1.32.380.0_x64__8wekyb3d8bbwe'
    $tag = 'v1.29.380'
    $download = 'https://github.com/microsoft/winget-cli/releases/download/{0}/' -f $tag
    $fakeBundleHash = 'AB' * 32
    $fakeDepsHash = 'CD' * 32
    # DE: Gemeinsamer Fake-Zustand. EN: Shared fake state.
    $wingetFake = @{ Dirs = @(); Version = ''; Release = $null; OnProvision = $null }
    # DE: Windows-/NinjaOne-Aufrufe isolieren. EN: Isolate Windows/NinjaOne calls.
    function icacls { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
    function Ninja-Property-Set { param($Name, $Value) }
    function Get-AuthenticodeSignature { param($LiteralPath, $ErrorAction) }
    function Add-AppxProvisionedPackage { param([switch]$Online, $PackagePath, $DependencyPackagePath, $LicensePath, $ErrorAction) }
    function New-FakeRelease {
        param([string]$Tag = $tag)
        $names = @('Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle', 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt',
            'DesktopAppInstaller_Dependencies.zip', 'DesktopAppInstaller_Dependencies.txt', 'e53e159d00e04f729cc2180cffd1c02e_License1.xml')
        [pscustomobject]@{
            tag_name = $Tag
            assets   = @($names | ForEach-Object { [pscustomobject]@{ name = $_; browser_download_url = ('https://github.com/microsoft/winget-cli/releases/download/{0}/{1}' -f $Tag, $_) } })
        }
    }
    function New-FakeProcess {
        param([bool]$Finished = $true)
        $process = [pscustomobject]@{ ExitCode = 0; Handle = [IntPtr]::Zero; Finished = $Finished }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) $this.Finished }
        $process
    }
}

Describe 'updateWinGet.ps1' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('installAllow', 'installTimeoutMinutes', 'resultCustomField', 'ProgramFiles')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:ProgramFiles = 'C:\Program Files'
        $wingetFake.Dirs = @($oldDir)
        $wingetFake.Version = 'v1.28.220'
        $wingetFake.Release = New-FakeRelease
        $wingetFake.OnProvision = { $wingetFake.Dirs = @($oldDir, $newDir); $wingetFake.Version = 'v1.29.380' }
        Mock Test-Path {
            $path = [string]($LiteralPath | Select-Object -First 1)
            if ($path -eq $appsRoot) { return $PathType -ne 'Leaf' }
            foreach ($dir in $wingetFake.Dirs) { if ($path -eq ('{0}\{1}\winget.exe' -f $appsRoot, $dir)) { return $PathType -ne 'Container' } }
            if ($path -like '*PhinIT-Install-*') { return $true }
            return $false
        }
        Mock Get-ChildItem {
            $path = [string]($LiteralPath | Select-Object -First 1)
            if ($path -eq $appsRoot) { return @($wingetFake.Dirs | ForEach-Object { [pscustomobject]@{ Name = $_; PSIsContainer = $true } }) }
            if ($path -match '[\\/]Dependencies[\\/]x64$') {
                return @('Microsoft.VCLibs.140.00_x64.appx', 'Microsoft.WindowsAppRuntime.1.8_x64.appx') | ForEach-Object { [pscustomobject]@{ FullName = (Join-Path $path $_); PSIsContainer = $false } }
            }
        }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock Start-Process { New-FakeProcess }
        Mock Get-Content {
            $path = [string]($LiteralPath | Select-Object -First 1)
            if ($path -like '*-version.txt') { return $wingetFake.Version }
            if ($path -like '*Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt') { return "$($fakeBundleHash.ToLowerInvariant())`r`n" }
            if ($path -like '*DesktopAppInstaller_Dependencies.txt') { return $fakeDepsHash }
        }
        Mock Invoke-RestMethod { $wingetFake.Release }
        Mock Invoke-WebRequest {}
        Mock Get-FileHash {
            $hash = if ([string]$LiteralPath -like '*.zip') { $fakeDepsHash } else { $fakeBundleHash }
            [pscustomobject]@{ Hash = $hash }
        }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' } } }
        Mock Expand-Archive {}
        Mock Add-AppxProvisionedPackage { if ($wingetFake.OnProvision) { & $wingetFake.OnProvision } }
        Mock New-Item { [pscustomobject]@{ FullName = $Path } }
        Mock icacls { $global:LASTEXITCODE = 0 }
        Mock Remove-Item {}
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }

    It 'has UTF-8 BOM and parsable help / hat BOM und lesbare Hilfe' {
        $bytes = [IO.File]::ReadAllBytes($script:updateScript)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
        $help = Get-Help $script:updateScript
        $help.Synopsis | Should -Match 'DE: Aktualisiert die lokale WinGet'
        @($help.Parameters.Parameter.Name) | Should -Contain 'AllowInstall'
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:updateScript, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
    It 'only audits by default and reports an available update / prüft standardmäßig nur' {
        $report = & $script:updateScript | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 2
        $report.Mode | Should -Be 'Audit'
        $report.Action | Should -Be 'UpdateAvailable'
        $report.VersionBefore | Should -Be '1.28.220'
        $report.LatestVersion | Should -Be '1.29.380'
        $report.WingetPath | Should -Be ('{0}\{1}\winget.exe' -f $appsRoot, $oldDir)
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '--version' }
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
    It 'reports a missing installation in audit mode / meldet fehlende Installation' {
        $wingetFake.Dirs = @()
        $report = & $script:updateScript | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 2
        $report.Action | Should -Be 'NotInstalled'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'does nothing when winget is current / macht nichts bei aktueller Version' {
        $wingetFake.Version = 'v1.29.380'
        $report = & $script:updateScript -AllowInstall true | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $report.Action | Should -Be 'UpToDate'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
    It 'updates an outdated winget with verified packages / aktualisiert mit geprüften Paketen' {
        $report = & $script:updateScript -AllowInstall true | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $report.Mode | Should -Be 'Update'
        $report.Action | Should -Be 'Updated'
        $report.VersionAfter | Should -Be '1.29.380'
        $report.WingetPath | Should -Be ('{0}\{1}\winget.exe' -f $appsRoot, $newDir)
        $report.InstallerSha256 | Should -Be $fakeBundleHash
        $report.InstallerSigner | Should -Match '^CN=Microsoft Corporation,'
        Should -Invoke Invoke-WebRequest -Times 5 -Exactly -ParameterFilter { $Uri -like "$download*" -and $OutFile -like '*PhinIT-Install-*' -and $UseBasicParsing }
        Should -Invoke icacls -Times 1 -Exactly
        Should -Invoke Get-AuthenticodeSignature -Times 3 -Exactly
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $Online -and $PackagePath -like '*Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -and @($DependencyPackagePath).Count -eq 2 -and
            $LicensePath -like '*e53e159d00e04f729cc2180cffd1c02e_License1.xml'
        }
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*PhinIT-Install-*' -and $Recurse }
    }
    It 'installs a missing winget / installiert fehlendes winget' {
        $wingetFake.Dirs = @()
        $wingetFake.OnProvision = { $wingetFake.Dirs = @($newDir); $wingetFake.Version = 'v1.29.380' }
        $report = & $script:updateScript -AllowInstall true | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $report.Mode | Should -Be 'Install'
        $report.Action | Should -Be 'Installed'
        $report.VersionBefore | Should -BeNullOrEmpty
    }
    It 'repairs an unusable winget / repariert nicht lauffähiges winget' {
        $wingetFake.Version = ''
        $report = & $script:updateScript | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 2
        $report.Action | Should -Be 'Unusable'
        $report = & $script:updateScript -AllowInstall true | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $report.Action | Should -Be 'Installed'
    }
    It 'simulates with -WhatIf / simuliert mit -WhatIf' {
        $report = & $script:updateScript -AllowInstall true -WhatIf | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $report.Action | Should -Be 'WhatIf'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
    It 'refuses a hash mismatch / verweigert abweichenden Hash' {
        Mock Get-FileHash { [pscustomobject]@{ Hash = ('EF' * 32) } }
        $output = & $script:updateScript -AllowInstall true
        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') | Should -Match 'SHA256'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*PhinIT-Install-*' }
    }
    It 'refuses packages without a valid Microsoft signature / verweigert ungültige Signatur' {
        foreach ($signature in @([pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation' } },
                [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Contoso Ltd, O=Contoso' } })) {
            Mock Get-AuthenticodeSignature { $signature }.GetNewClosure()
            $output = & $script:updateScript -AllowInstall true
            $LASTEXITCODE | Should -Be 1
            ($output -join ' ') | Should -Match 'Signatur'
        }
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
    It 'ignores assets outside the official release / ignoriert fremde Download-URLs' {
        $release = New-FakeRelease
        $release.assets[0].browser_download_url = 'https://evil.example/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $wingetFake.Release = $release
        $output = & $script:updateScript -AllowInstall true
        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') | Should -Match 'Release-Datei fehlt'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
    It 'fails when winget is not current after provisioning / Fehler ohne aktuelle Version danach' {
        $wingetFake.OnProvision = $null
        $output = & $script:updateScript -AllowInstall true
        $LASTEXITCODE | Should -Be 1
        ($output -join ' ') | Should -Match 'not current after provisioning'
    }
    It 'fails when GitHub is unreachable / Fehler ohne GitHub' {
        Mock Invoke-RestMethod { throw 'offline' }
        $null = & $script:updateScript
        $LASTEXITCODE | Should -Be 1
    }
    It 'rejects invalid input / lehnt ungültige Eingaben ab' {
        foreach ($case in @(@{ AllowInstall = 'yes' }, @{ TimeoutMinutes = '0' }, @{ TimeoutMinutes = '241' }, @{ CustomField = '1field' })) {
            $null = & $script:updateScript @case
            $LASTEXITCODE | Should -Be 1 -Because ($case | ConvertTo-Json -Compress)
        }
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
    It 'writes the custom field / schreibt das Custom Field' {
        $env:installAllow = 'true'
        $env:resultCustomField = 'wingetReport'
        $null = & $script:updateScript
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'wingetReport' -and ($Value | ConvertFrom-Json).Action -eq 'Updated' }
    }
}
