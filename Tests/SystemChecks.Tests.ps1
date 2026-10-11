BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $diskScript = Join-Path $root '01 - System/checkDiskSpace.ps1'
    $serviceScript = Join-Path $root '01 - System/checkRequiredServices.ps1'
    $zoneScript = Join-Path $root '01 - System/checkTimeZone.ps1'
    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-CimInstance { param($ClassName, $Filter) }
    function Get-Service {}
    function Ninja-Property-Set { param($Name, $Value) }
}
Describe 'Read-only system checks / Lesende Systemprüfungen' {
    BeforeEach {
        $saved = @{}
        foreach ($name in @('minimumFreePercent', 'requiredServiceNames', 'expectedTimeZone', 'resultCustomField')) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 25GB } }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
    It 'Reports disk capacity / Meldet Speicherplatz' {
        $report = & $diskScript
        $LASTEXITCODE | Should -Be 0
        ($report | ConvertFrom-Json).Disks[0].FreePercent | Should -Be 25
    }
    It 'Warns below configured threshold / Warnt unter Grenzwert' {
        $env:minimumFreePercent = '30'
        $env:resultCustomField = 'diskStatus'
        $null = & $diskScript
        $LASTEXITCODE | Should -Be 2
        Should -Invoke Ninja-Property-Set -Times 1 -ParameterFilter { $Name -eq 'diskStatus' }
    }
    It 'Explicit parameters override variables / Parameter überschreiben Variablen' {
        $env:minimumFreePercent = '30'
        $env:resultCustomField = 'ignored'
        $null = & $diskScript -MinimumFreePercent 20 -CustomField ''
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }
    It 'Accepts the exact threshold / Akzeptiert den exakten Grenzwert' {
        $null = & $diskScript -MinimumFreePercent 25
        $LASTEXITCODE | Should -Be 0
    }
    It 'Reports query errors rather than a healthy status / Meldet Abfragefehler statt OK' {
        Mock Get-CimInstance { throw 'Simulated CIM failure' }
        $null = & $diskScript
        $LASTEXITCODE | Should -Be 1
    }
    It 'Rejects invalid injected thresholds / Lehnt ungültige Variablen ab' {
        foreach ($value in @('0', '100', 'abc', '1.5')) {
            $env:minimumFreePercent = $value
            $null = & $diskScript
            $LASTEXITCODE | Should -Be 1
        }
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }
    It 'Rejects unavailable capacity / Lehnt fehlende Kapazität ab' {
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'C:'; Size = 0; FreeSpace = 0 } }
        $null = & $diskScript
        $LASTEXITCODE | Should -Be 1
    }
    It 'Reports field write failures / Meldet Schreibfehler' {
        Mock Ninja-Property-Set { $global:LASTEXITCODE = 4 }
        $null = & $diskScript -CustomField 'diskStatus'
        $LASTEXITCODE | Should -Be 1
    }
    It 'Rejects missing or wildcard service input / Lehnt fehlende Namen und Wildcards ab' {
        foreach ($value in @('', 'null', '*', 'Spooler,')) {
            $null = & $serviceScript -ServiceNames $value
            $LASTEXITCODE | Should -Be 1
        }
    }
    It 'Detects stopped and missing services / Erkennt gestoppte und fehlende Dienste' {
        Mock Get-Service { [pscustomobject]@{ Name = 'W32Time'; Status = 'Stopped' } }
        $report = & $serviceScript -ServiceNames 'W32Time,Spooler'
        $LASTEXITCODE | Should -Be 2
        ($report | ConvertFrom-Json)[1].Status | Should -Be 'Missing'
    }
    It 'Accepts running services / Akzeptiert laufende Dienste' {
        Mock Get-Service { [pscustomobject]@{ Name = 'W32Time'; Status = 'Running' } }
        $null = & $serviceScript -ServiceNames 'W32Time'
        $LASTEXITCODE | Should -Be 0
    }
    It 'Accepts literal SQL instance and spaced service names / Akzeptiert SQL-Instanzen und Leerzeichen' {
        Mock Get-Service {
            [pscustomobject]@{ Name = 'MSSQL$SQLEXPRESS'; Status = 'Running' }
            [pscustomobject]@{ Name = 'Example Service'; Status = 'Running' }
        }
        $null = & $serviceScript -ServiceNames 'MSSQL$SQLEXPRESS,Example Service'
        $LASTEXITCODE | Should -Be 0
    }
    It 'Rejects oversized field reports / Lehnt übergroße Feldberichte ab' {
        $names = @(1..20 | ForEach-Object { ('Service' + $_).PadRight(128, 'x') })
        Mock Get-Service {
            foreach ($name in $names) {
                [pscustomobject]@{ Name = $name; Status = ('Unknown').PadRight(128, 'x') }
            }
        }
        $null = & $serviceScript -ServiceNames ($names -join ',') -CustomField 'serviceStatus'
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Ninja-Property-Set -Times 0 -Exactly
    }
    It 'Reads time zone without changing it / Liest Zeitzone ohne Änderung' {
        $report = & $zoneScript -ExpectedTimeZone '' -CustomField ''
        $LASTEXITCODE | Should -Be 0
        ($report | ConvertFrom-Json).Id | Should -Not -BeNullOrEmpty
    }
    It 'Rejects unknown time zones / Lehnt unbekannte Zeitzonen ab' {
        $null = & $zoneScript -ExpectedTimeZone 'Not-A-Timezone'
        $LASTEXITCODE | Should -Be 1
    }
}
