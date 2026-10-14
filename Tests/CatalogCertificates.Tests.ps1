BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $folder = '04 - Certificates'
    $rdpScript = Join-Path $root "$folder/checkRdpCertificate.ps1"
    $sslScript = Join-Path $root "$folder/checkSslBindingCertificates.ps1"
    $tlsScript = Join-Path $root "$folder/checkRemoteTlsCertificate.ps1"
    $chainScript = Join-Path $root "$folder/checkCertificateChain.ps1"
    $weakScript = Join-Path $root "$folder/checkWeakCertificates.ps1"
    $autoEnrollScript = Join-Path $root "$folder/checkAutoEnrollmentPolicy.ps1"
    $disallowedScript = Join-Path $root "$folder/readDisallowedCertificates.ps1"
    $rootUpdateScript = Join-Path $root "$folder/checkRootAutoUpdate.ps1"
    $presenceScript = Join-Path $root "$folder/checkCertificatePresence.ps1"
    $codeSigningScript = Join-Path $root "$folder/checkCodeSigningCertificates.ps1"
    $schannelScript = Join-Path $root "$folder/checkSchannelProtocols.ps1"
    $dotNetScript = Join-Path $root "$folder/checkDotNetStrongCrypto.ps1"

    # DE: Windows- und NinjaOne-Aufrufe isolieren. EN: Isolate Windows and NinjaOne calls.
    function Get-CimInstance { param($ClassName, $Namespace, $Filter) }
    function netsh {}
    function Ninja-Property-Set { param($Name, $Value) }

    $script:envNames = @(
        'certRdpWarningDays', 'certRdpFailOnSelfSigned', 'certSslBindingWarningDays', 'certSslBindingMaxRecords',
        'certTlsTargetHost', 'certTlsTargetPort', 'certTlsTimeoutMs', 'certTlsWarningDays',
        'certChainRevocationMode', 'certChainMaxCertificates', 'certWeakAdditionalStores', 'certWeakMaxRecords',
        'certAutoEnrollRequireEnabled', 'certDisallowedRequiredThumbprints', 'certDisallowedMaxRecords',
        'certRootMaxSyncAgeDays', 'certPresenceStoreName', 'certPresenceThumbprints', 'certPresenceSubject',
        'certCodeSigningWarningDays', 'certCodeSigningMaxRecords', 'certSchannelStrictMode', 'certDotNetIncludeV2',
        'resultCustomField')

    function New-TestCertificate {
        param(
            [string]$Subject = 'CN=test.contoso.local',
            [int]$NotBeforeDays = -1,
            [int]$NotAfterDays = 365,
            [int]$RsaBits = 2048,
            [string]$Curve = '',
            [string[]]$Eku = @(),
            [string[]]$DnsNames = @(),
            [object]$Issuer = $null,
            [switch]$CertificateAuthority,
            [switch]$PublicOnly
        )
        $now = [DateTimeOffset]::UtcNow
        $sha256 = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        if ($Curve) {
            $key = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName($Curve))
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($Subject, $key, $sha256)
        } else {
            $key = [System.Security.Cryptography.RSA]::Create($RsaBits)
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($Subject, $key, $sha256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        }
        if ($CertificateAuthority) {
            $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true))
            $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'KeyCertSign, CrlSign, DigitalSignature', $true))
        }
        if ($Eku.Count -gt 0) {
            $oids = [System.Security.Cryptography.OidCollection]::new()
            foreach ($value in $Eku) { $null = $oids.Add([System.Security.Cryptography.Oid]::new($value)) }
            $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
        }
        if ($DnsNames.Count -gt 0) {
            $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
            foreach ($name in $DnsNames) { $san.AddDnsName($name) }
            $request.CertificateExtensions.Add($san.Build())
        }
        if ($null -eq $Issuer) {
            $certificate = $request.CreateSelfSigned($now.AddDays($NotBeforeDays), $now.AddDays($NotAfterDays))
        } else {
            $serial = [byte[]](1..8 | ForEach-Object { Get-Random -Minimum 1 -Maximum 255 })
            $signed = $request.Create($Issuer, $now.AddDays($NotBeforeDays), $now.AddDays($NotAfterDays), $serial)
            if ($Curve) {
                $certificate = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::CopyWithPrivateKey($signed, $key)
            } else {
                $certificate = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($signed, $key)
            }
        }
        if ($PublicOnly) { return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate.RawData) }
        $certificate
    }

    # DE: Öffentliches SHA1-signiertes Testzertifikat (ohne Schlüssel). EN: Public SHA1-signed test certificate (no key).
    $sha1Base64 = 'MIIDGTCCAgGgAwIBAgIUZVJFxPbTsF48/uahH/uVmWAOnr4wDQYJKoZIhvcNAQEFBQAwGzEZMBcGA1UEAwwQTGVnYWN5IFNIQTEgVGVzdDAgFw0yNjEwMTQxNzM4MzlaGA8yMTI2MDkyMDE3MzgzOVowGzEZMBcGA1UEAwwQTGVnYWN5IFNIQTEgVGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJo60gCp+jm4RBRw60ng5Npb1DlZ2q4N6HZzt93v7vs+7snIOMSpbU+WnObpa2AD1ZcEJejXTRR72NLu8X5SvkKUWpD0srBATI/kW1riAwRQfuYpbvlF9Q4JrV5dnr1FIHxBtX8LLzZVva/EHTrSh9up7NB6vcUwtb01+o8In7dBTFuTbsIvvDDAo6jqXiTxPRWKqdfCVfK2JSAVJI3qEfwX5cZljzdqMa5YR0LzLqWLNmdUj33XvcmEGqpX6ihXXdEHtinZ1gUJjynoyuRt6eEL8nsb32XnQ/lm3hiP1g3fMV6vqfH0gTP5g73RwUVYRZeISe9uajHpFOW+a1d6vKUCAwEAAaNTMFEwHQYDVR0OBBYEFCQ6BOd9rdbRvPdesIFKfXbd6UxaMB8GA1UdIwQYMBaAFCQ6BOd9rdbRvPdesIFKfXbd6UxaMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQEFBQADggEBAJXbwrwusQs6CThZCp/dUbd9k6rppGFduE54s2EhlseaMnHxKBf2ggf+f2tkZD12aXnLCSfrGhtxnC2dOGKB2ZC5WnpDJj9y2I1Y0EG/pdFfcivU1o6DBDiC+oFroCEFgBKuwIOJ095+VsA38CL66/MyJgnPOxA59MKOWH+AM6BsOGkC1YrV/BmfRRlHXGYXa2UhaaNz4VizT9JoiIuV1gUvLUqyvvEAtj0JAW+UDR6/kvw9nsQRyJioZBgW7QhdJPhph5nKs0PSfBVO/H/kdyyhUgtb2n3XQIBpaVUb6wDWIakVcevKROKAy5Uej+5yt1d/dakpvULHoafn+7qQN24='
    $script:sha1Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($sha1Base64))

    # DE: Test-CA temporär im CurrentUser\Root (Linux-.NET) vertrauen. EN: Temporarily trust a test CA in CurrentUser\Root (Linux .NET).
    $script:testCa = New-TestCertificate -Subject 'CN=Pester Test Root CA' -NotBeforeDays -2 -NotAfterDays 3650 -CertificateAuthority
    $script:trustStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'CurrentUser')
    $script:trustStore.Open('ReadWrite')
    $script:trustStore.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($script:testCa.RawData))

    function Start-TestTlsServer {
        param($Certificate)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Any, 0)
        $listener.Server.DualMode = $true
        $listener.Start()
        $shell = [powershell]::Create()
        $null = $shell.AddScript({
                param($Listener, $ServerCertificate)
                $client = $Listener.AcceptTcpClient()
                try {
                    $stream = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
                    $stream.AuthenticateAsServer($ServerCertificate, $false, [System.Security.Authentication.SslProtocols]::Tls12, $false)
                    Start-Sleep -Milliseconds 300
                } catch {
                    $null = $_
                } finally { $client.Dispose() }
            }).AddArgument($listener).AddArgument($Certificate)
        $handle = $shell.BeginInvoke()
        @{ Listener = $listener; Shell = $shell; Handle = $handle; Port = $listener.LocalEndpoint.Port }
    }
    function Stop-TestTlsServer {
        param($Server)
        $Server.Listener.Stop()
        try { $null = $Server.Handle.AsyncWaitHandle.WaitOne(3000) } finally { $Server.Shell.Dispose() }
    }
}
AfterAll {
    if ($script:trustStore) {
        $script:trustStore.Remove([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($script:testCa.RawData))
        $script:trustStore.Dispose()
    }
    Remove-Variable -Name certTestStores, certTestRegistry, certTestRdpHash, certTestNetshLines -Scope Global -ErrorAction SilentlyContinue
}
Describe 'Certificate catalogue scripts / Zertifikatskatalog-Skripte' {
    BeforeEach {
        $script:savedEnv = @{}
        foreach ($name in $script:envNames) {
            $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $global:certTestStores = @{}
        $global:certTestRegistry = @{}
        Mock Get-ChildItem {
            $storeName = ([string]@($Path)[0]) -replace '^Cert:\\LocalMachine\\', ''
            if ($global:certTestStores.ContainsKey($storeName)) { return $global:certTestStores[$storeName] }
            throw [System.Management.Automation.ItemNotFoundException]::new("Cannot find path '$Path'.")
        } -ParameterFilter { ([string]@($Path)[0]) -like 'Cert:\LocalMachine\*' }
        Mock Get-ItemProperty {
            $key = [string]@($Path)[0]
            if ($global:certTestRegistry.ContainsKey($key)) { return $global:certTestRegistry[$key] }
            throw [System.Management.Automation.ItemNotFoundException]::new("Cannot find path '$key'.")
        } -ParameterFilter { ([string]@($Path)[0]) -like 'HKLM:\*' }
        Mock Ninja-Property-Set {}
    }
    AfterEach {
        foreach ($name in $script:savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $script:savedEnv[$name]) }
    }

    Context 'checkRdpCertificate' {
        BeforeEach {
            $script:rdpCert = New-TestCertificate -Subject 'CN=rdp.contoso.local'
            $global:certTestRdpHash = $script:rdpCert.Thumbprint
            Mock Get-CimInstance { [pscustomobject]@{ TerminalName = 'RDP-Tcp'; SSLCertificateSHA1Hash = $global:certTestRdpHash } }
        }
        It 'Reports a valid RDP certificate / Meldet gültiges RDP-Zertifikat' {
            $global:certTestStores['Remote Desktop'] = @($script:rdpCert)
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Found | Should -BeTrue
            $report.Certificate.Store | Should -Be 'LocalMachine\Remote Desktop'
            $report.Certificate.SelfSigned | Should -BeTrue
        }
        It 'Warns on expiring certificate in My when Remote Desktop store is missing / Warnt bei bald ablaufendem Zertifikat' {
            $script:rdpCert = New-TestCertificate -Subject 'CN=rdp.contoso.local' -NotAfterDays 10
            $global:certTestRdpHash = $script:rdpCert.Thumbprint.ToLowerInvariant()
            $global:certTestStores['My'] = @($script:rdpCert)
            $env:resultCustomField = 'rdpCertificate'
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'ExpiringSoon'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'rdpCertificate' }
        }
        It 'Warns when the certificate is missing or self-signed is forbidden / Warnt bei fehlendem oder verbotenem selbst signiertem Zertifikat' {
            $global:certTestStores['My'] = @()
            $report = & $rdpScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'CertificateNotFound'
            $global:certTestStores['My'] = @($script:rdpCert)
            $report = & $rdpScript -FailOnSelfSigned TRUE | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'SelfSigned'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('abc', '-1', '3651', '1.5')) {
                $null = & $rdpScript -WarningDays $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $rdpScript -FailOnSelfSigned 'yes'
            $LASTEXITCODE | Should -Be 1
            $null = & $rdpScript -CustomField 'bad-name'
            $LASTEXITCODE | Should -Be 1
            Should -Invoke Get-CimInstance -Times 0 -Exactly
        }
    }

    Context 'checkSslBindingCertificates' {
        BeforeEach {
            $script:certA = New-TestCertificate -Subject 'CN=www.contoso.com'
            $script:certB = New-TestCertificate -Subject 'CN=api.contoso.com'
            $global:certTestStores['MY'] = @($script:certA)
            $global:certTestStores['WebHosting'] = @($script:certB)
            $global:certTestNetshLines = @(
                '', 'SSL Certificate bindings:', '-------------------------', '',
                '    IP:port                      : 0.0.0.0:443',
                "    Certificate Hash             : $($script:certA.Thumbprint.ToLowerInvariant())",
                '    Application ID               : {4dc3e181-e14b-4a21-b022-59fc669b0914}',
                '    Certificate Store Name       : MY',
                '    Verify Client Certificate Revocation : Enabled',
                '    Ctl Store Name               : (null)', '',
                '    Hostname:port                : api.contoso.com:8443',
                "    Certificate Hash             : $($script:certB.Thumbprint)",
                '    Certificate Store Name       : WebHosting', '',
                '    Central Certificate Store    : 9443',
                '    Certificate Hash             : (null)', '')
            Mock netsh { $global:LASTEXITCODE = 0; $global:certTestNetshLines }
        }
        It 'Resolves all bindings / Löst alle Bindungen auf' {
            $report = & $sslScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalBindings | Should -Be 3
            ($report.Bindings | Where-Object Endpoint -EQ 'api.contoso.com:8443').Store | Should -Be 'WebHosting'
            ($report.Bindings | Where-Object Kind -EQ 'CentralCertificateStore').Status | Should -Be 'NotApplicable'
        }
        It 'Parses German labels / Liest deutsche Beschriftungen' {
            $global:certTestNetshLines = @(
                '    IP:Port                      : [::]:443',
                "    Zertifikathash               : $($script:certA.Thumbprint)",
                '    Zertifikatspeichername       : My')
            $report = & $sslScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Bindings[0].Status | Should -Be 'OK'
        }
        It 'Warns on missing and expired certificates / Warnt bei fehlenden und abgelaufenen Zertifikaten' {
            $global:certTestStores['WebHosting'] = @(New-TestCertificate -Subject 'CN=old' -NotBeforeDays -30 -NotAfterDays -1)
            $global:certTestNetshLines[12] = "    Certificate Hash             : $($global:certTestStores['WebHosting'][0].Thumbprint)"
            $global:certTestStores['MY'] = @()
            $env:resultCustomField = 'sslBindings'
            $report = & $sslScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FindingCount | Should -Be 2
            @($report.Bindings.Status) | Should -Contain 'Expired'
            @($report.Bindings.Status) | Should -Contain 'CertificateMissing'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Bounds the record list / Begrenzt die Einträge' {
            $report = & $sslScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.ReportedRecords | Should -Be 1
            $report.Truncated | Should -BeTrue
        }
        It 'Reports netsh and input errors / Meldet netsh- und Eingabefehler' {
            Mock netsh { $global:LASTEXITCODE = 1; 'The requested operation failed.' }
            $null = & $sslScript
            $LASTEXITCODE | Should -Be 1
            foreach ($value in @('0', '101', 'x')) {
                $null = & $sslScript -MaxRecords $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkRemoteTlsCertificate' {
        It 'Rejects invalid hosts, ports and timeouts / Lehnt ungültige Hosts, Ports und Timeouts ab' {
            foreach ($value in @('', 'null', 'https://contoso.com', 'user@host', 'a b', '1234', '10.1', 'host;rm')) {
                $null = & $tlsScript -TargetHost $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $tlsScript -TargetHost 'localhost' -TargetPort '70000'
            $LASTEXITCODE | Should -Be 1
            $null = & $tlsScript -TargetHost 'localhost' -TimeoutMs '500'
            $LASTEXITCODE | Should -Be 1
        }
        It 'Warns when the endpoint is unreachable / Warnt bei nicht erreichbarem Endpunkt' {
            $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
            $report = & $tlsScript -TargetHost '127.0.0.1' -TargetPort $port -TimeoutMs 2000 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Outcome | Should -BeLike 'Connect*'
        }
        It 'Accepts a trusted certificate / Akzeptiert ein vertrauenswürdiges Zertifikat' {
            $leaf = New-TestCertificate -Subject 'CN=localhost' -DnsNames @('localhost') -Eku @('1.3.6.1.5.5.7.3.1') -Issuer $script:testCa
            $server = Start-TestTlsServer -Certificate $leaf
            try {
                $env:certTlsTargetHost = 'localhost'
                $env:certTlsTargetPort = [string]$server.Port
                $env:resultCustomField = 'tlsEndpoint'
                $report = & $tlsScript -TimeoutMs 5000 | ConvertFrom-Json
            } finally { Stop-TestTlsServer -Server $server }
            $report.Findings | Should -BeNullOrEmpty
            $LASTEXITCODE | Should -Be 0
            $report.Outcome | Should -Be 'HandshakeCompleted'
            $report.Certificate.Thumbprint | Should -Be $leaf.Thumbprint
            @($report.SubjectAlternativeNames).Count | Should -Be 1
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly -ParameterFilter { $Name -eq 'tlsEndpoint' }
        }
        It 'Warns on untrusted, mismatching certificates / Warnt bei nicht vertrauenswürdigem Zertifikat' {
            $leaf = New-TestCertificate -Subject 'CN=other.contoso.local' -DnsNames @('other.contoso.local') -NotAfterDays 5
            $server = Start-TestTlsServer -Certificate $leaf
            try {
                $report = & $tlsScript -TargetHost 'localhost' -TargetPort $server.Port -TimeoutMs 5000 | ConvertFrom-Json
            } finally { Stop-TestTlsServer -Server $server }
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'ExpiringSoon'
            $report.PolicyErrors | Should -Match 'RemoteCertificateNameMismatch'
            $report.PolicyErrors | Should -Match 'RemoteCertificateChainErrors'
        }
    }

    Context 'checkCertificateChain' {
        It 'Accepts trusted chains and ignores certificates without key / Akzeptiert vertrauenswürdige Ketten' {
            $leaf = New-TestCertificate -Subject 'CN=server01.contoso.local' -Issuer $script:testCa
            $global:certTestStores['My'] = @($leaf, (New-TestCertificate -Subject 'CN=public-only' -PublicOnly))
            $report = & $chainScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalWithPrivateKey | Should -Be 1
            $report.Checked | Should -Be 1
            $report.Certificates[0].ChainLength | Should -Be 2
        }
        It 'Warns on untrusted chains and honours the bound / Warnt bei nicht vertrauenswürdigen Ketten' {
            $global:certTestStores['My'] = @((New-TestCertificate -Subject 'CN=self1'), (New-TestCertificate -Subject 'CN=self2'))
            $env:resultCustomField = 'certificateChain'
            $report = & $chainScript -MaxCertificates 1 -RevocationMode offline | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.RevocationMode | Should -Be 'Offline'
            $report.Checked | Should -Be 1
            $report.NotChecked | Should -Be 1
            $report.Certificates[0].Valid | Should -BeFalse
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $chainScript -RevocationMode 'Sometimes'
            $LASTEXITCODE | Should -Be 1
            foreach ($value in @('0', '201', 'x')) {
                $null = & $chainScript -MaxCertificates $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkWeakCertificates' {
        It 'Accepts strong certificates / Akzeptiert starke Zertifikate' {
            $global:certTestStores['My'] = @((New-TestCertificate -Subject 'CN=rsa'), (New-TestCertificate -Subject 'CN=ecc' -Curve 'nistP256'))
            $report = & $weakScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.CheckedCertificates | Should -Be 2
            $report.WeakCount | Should -Be 0
        }
        It 'Detects weak signatures and keys / Erkennt schwache Signaturen und Schlüssel' {
            $global:certTestStores['My'] = @(
                (New-TestCertificate -Subject 'CN=rsa1024' -RsaBits 1024),
                (New-TestCertificate -Subject 'CN=ecc224' -Curve 'secp224r1'),
                $script:sha1Certificate)
            $env:resultCustomField = 'weakCertificates'
            $report = & $weakScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.WeakCount | Should -Be 3
            $all = @($report.WeakCertificates.Findings)
            $all | Should -Contain 'WeakRsaKey:1024'
            $all | Should -Contain 'WeakEccKey:224'
            $all | Should -Contain 'WeakSignature:SHA1RSA'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Skips self-signed root signatures and lists missing stores / Überspringt Root-Selbstsignaturen' {
            $global:certTestStores['My'] = @()
            $global:certTestStores['Root'] = @($script:sha1Certificate)
            $report = & $weakScript -AdditionalStores 'root, remote desktop' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Stores) | Should -Be @('My', 'Root', 'Remote Desktop')
            @($report.MissingStores) | Should -Be @('Remote Desktop')
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $weakScript -AdditionalStores 'Root,..\My'
            $LASTEXITCODE | Should -Be 1
            $null = & $weakScript -MaxRecords '0'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkAutoEnrollmentPolicy' {
        BeforeAll { $script:aePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment' }
        It 'Reports a missing policy without warning / Meldet fehlende Richtlinie ohne Warnung' {
            $report = & $autoEnrollScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.State | Should -Be 'NotConfigured'
        }
        It 'Decodes an enabled policy / Dekodiert aktive Richtlinie' {
            $global:certTestRegistry[$script:aePath] = [pscustomobject]@{ AEPolicy = 7; OfflineExpirationPercent = 10 }
            $report = & $autoEnrollScript -RequireEnabled true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Enabled | Should -BeTrue
            $report.AEPolicy.RenewExpiredRemoveRevoked | Should -BeTrue
            $report.AEPolicy.RetrievePending | Should -BeTrue
            $report.AEPolicy.Hex | Should -Be '0x00000007'
        }
        It 'Warns when required but disabled / Warnt bei Pflicht und deaktivierter Richtlinie' {
            $global:certTestRegistry[$script:aePath] = [pscustomobject]@{ AEPolicy = 0x8000 }
            $env:certAutoEnrollRequireEnabled = 'true'
            $env:resultCustomField = 'autoEnrollment'
            $report = & $autoEnrollScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.State | Should -Be 'Disabled'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Rejects invalid input and registry errors / Lehnt ungültige Eingaben und Registryfehler ab' {
            $null = & $autoEnrollScript -RequireEnabled 'maybe'
            $LASTEXITCODE | Should -Be 1
            Mock Get-ItemProperty { throw 'Access denied' } -ParameterFilter { ([string]@($Path)[0]) -like 'HKLM:\*' }
            $null = & $autoEnrollScript
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'readDisallowedCertificates' {
        BeforeEach {
            $script:blocked = @(1..3 | ForEach-Object { New-TestCertificate -Subject "CN=blocked$_" -PublicOnly })
            $global:certTestStores['Disallowed'] = $script:blocked
        }
        It 'Inventories the store and finds required thumbprints / Inventarisiert und findet Pflicht-Thumbprints' {
            $thumb = $script:blocked[1].Thumbprint
            $spaced = ($thumb.ToLowerInvariant() -replace '(.{4})', '$1 ').Trim()
            $report = & $disallowedScript -RequiredThumbprints $spaced | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalCertificates | Should -Be 3
            @($report.MissingRequired).Count | Should -Be 0
        }
        It 'Warns on missing required thumbprints / Warnt bei fehlenden Pflicht-Thumbprints' {
            $env:certDisallowedRequiredThumbprints = "$($script:blocked[0].Thumbprint);0123456789ABCDEF0123456789ABCDEF01234567"
            $env:resultCustomField = 'disallowedCertificates'
            $report = & $disallowedScript -MaxRecords 1 | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            @($report.MissingRequired) | Should -Be @('0123456789ABCDEF0123456789ABCDEF01234567')
            $report.Truncated | Should -BeTrue
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Treats a missing store as empty / Behandelt fehlenden Speicher als leer' {
            $global:certTestStores.Remove('Disallowed')
            $report = & $disallowedScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.StoreFound | Should -BeFalse
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('ABC', '0123456789ABCDEF0123456789ABCDEF0123456G', '*')) {
                $null = & $disallowedScript -RequiredThumbprints $value
                $LASTEXITCODE | Should -Be 1
            }
            $null = & $disallowedScript -MaxRecords '101'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkRootAutoUpdate' {
        BeforeAll {
            $script:autoPath = 'HKLM:\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate'
            $script:policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot'
            function ConvertTo-FileTimeBytes { param([int]$DaysAgo) , [BitConverter]::GetBytes([DateTime]::UtcNow.AddDays(-$DaysAgo).ToFileTimeUtc()) }
        }
        It 'Accepts recent syncs / Akzeptiert aktuelle Synchronisierung' {
            $global:certTestRegistry[$script:autoPath] = [pscustomobject]@{ LastSyncTime = (ConvertTo-FileTimeBytes 2); DisallowedCertLastSyncTime = (ConvertTo-FileTimeBytes 1); RootDirUrl = 'http://ctldl.windowsupdate.com/msdownload/update/v3/static/trustedr/en' }
            $report = & $rootUpdateScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.LastSync.LastSyncTime.AgeDays | Should -BeGreaterThan 1.5
            $report.LastSync.PinRulesLastSyncTime.Utc | Should -BeNullOrEmpty
        }
        It 'Warns when auto update is disabled by policy / Warnt bei deaktiviertem Auto-Update' {
            $global:certTestRegistry[$script:policyPath] = [pscustomobject]@{ DisableRootAutoUpdate = 1; EnableDisallowedCertAutoUpdate = 0 }
            $env:resultCustomField = 'rootAutoUpdate'
            $report = & $rootUpdateScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'RootAutoUpdateDisabled'
            $report.Findings | Should -Contain 'DisallowedAutoUpdateDisabled'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Warns on stale or undecodable sync times / Warnt bei alten oder ungültigen Zeiten' {
            $global:certTestRegistry[$script:autoPath] = [pscustomobject]@{ LastSyncTime = (ConvertTo-FileTimeBytes 40); DisallowedCertLastSyncTime = [byte[]](1, 2, 3) }
            $report = & $rootUpdateScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'RootSyncStale'
            $report.Findings | Should -Contain 'DisallowedSyncMissing'
            $null = & $rootUpdateScript -MaxSyncAgeDays 60
            $LASTEXITCODE | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            foreach ($value in @('0', '3651', 'x')) {
                $null = & $rootUpdateScript -MaxSyncAgeDays $value
                $LASTEXITCODE | Should -Be 1
            }
        }
    }

    Context 'checkCertificatePresence' {
        BeforeEach {
            $script:present = New-TestCertificate -Subject 'CN=web01.contoso.com, O=Contoso'
            $script:expired = New-TestCertificate -Subject 'CN=old.contoso.com' -NotBeforeDays -30 -NotAfterDays -2
            $global:certTestStores['My'] = @($script:present, $script:expired)
        }
        It 'Finds present certificates by thumbprint and subject / Findet vorhandene Zertifikate' {
            $report = & $presenceScript -Thumbprints $script:present.Thumbprint -Subject 'cn=web01.contoso.com, o=contoso' | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.FailedChecks | Should -Be 0
            $report.TotalChecks | Should -Be 2
        }
        It 'Warns on missing and expired certificates / Warnt bei fehlenden und abgelaufenen Zertifikaten' {
            $env:certPresenceThumbprints = "$($script:expired.Thumbprint),0123456789ABCDEF0123456789ABCDEF01234567"
            $env:certPresenceSubject = 'CN=web01'
            $env:resultCustomField = 'certificatePresence'
            $report = & $presenceScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.FailedChecks | Should -Be 3
            @($report.Checks.Status) | Should -Contain 'Expired'
            @($report.Checks.Status) | Should -Contain 'Missing'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Accepts allow-listed stores case-insensitively / Akzeptiert erlaubte Speicher' {
            $global:certTestStores['Remote Desktop'] = @($script:present)
            $report = & $presenceScript -StoreName 'remote desktop' -Thumbprints $script:present.Thumbprint | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.Store | Should -Be 'LocalMachine\Remote Desktop'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $presenceScript
            $LASTEXITCODE | Should -Be 1
            $null = & $presenceScript -StoreName '..\My' -Thumbprints $script:present.Thumbprint
            $LASTEXITCODE | Should -Be 1
            $null = & $presenceScript -Thumbprints 'XYZ'
            $LASTEXITCODE | Should -Be 1
            $null = & $presenceScript -Subject "CN=a`nb"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkCodeSigningCertificates' {
        It 'Accepts valid code-signing certificates / Akzeptiert gültige Codesignatur-Zertifikate' {
            $global:certTestStores['My'] = @(
                (New-TestCertificate -Subject 'CN=Contoso Code Signing' -Eku @('1.3.6.1.5.5.7.3.3')),
                (New-TestCertificate -Subject 'CN=tls' -Eku @('1.3.6.1.5.5.7.3.1') -NotAfterDays 2))
            $global:certTestStores['TrustedPublisher'] = @()
            $report = & $codeSigningScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $report.TotalCodeSigning | Should -Be 1
        }
        It 'Warns on expired code-signing certificates / Warnt bei abgelaufenen Codesignatur-Zertifikaten' {
            $global:certTestStores['My'] = @()
            $global:certTestStores['TrustedPublisher'] = @(New-TestCertificate -Subject 'CN=Old Publisher' -Eku @('1.3.6.1.5.5.7.3.3') -NotBeforeDays -400 -NotAfterDays -5 -PublicOnly)
            $env:resultCustomField = 'codeSigning'
            $report = & $codeSigningScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Certificates[0].Status | Should -Be 'Expired'
            $report.Certificates[0].Store | Should -Be 'TrustedPublisher'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Reports field write failures and invalid input / Meldet Schreibfehler und ungültige Eingaben' {
            $global:certTestStores['My'] = @()
            Mock Ninja-Property-Set { $global:LASTEXITCODE = 3 }
            $null = & $codeSigningScript -CustomField 'codeSigning'
            $LASTEXITCODE | Should -Be 1
            $null = & $codeSigningScript -WarningDays '-5'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkSchannelProtocols' {
        BeforeAll { $script:schannel = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols' }
        It 'Reports OS defaults without warning / Meldet OS-Standard ohne Warnung' {
            $report = & $schannelScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Protocols).Count | Should -Be 12
            @($report.Protocols | Where-Object Configuration -EQ 'NotConfigured').Count | Should -Be 12
        }
        It 'Warns on explicitly enabled legacy or disabled TLS 1.2 / Warnt bei Altprotokollen oder deaktiviertem TLS 1.2' {
            $global:certTestRegistry["$script:schannel\TLS 1.0\Server"] = [pscustomobject]@{ Enabled = 1; DisabledByDefault = 0 }
            $global:certTestRegistry["$script:schannel\SSL 3.0\Client"] = [pscustomobject]@{ Enabled = -1 }
            $global:certTestRegistry["$script:schannel\TLS 1.2\Client"] = [pscustomobject]@{ Enabled = 0 }
            $env:resultCustomField = 'schannelProtocols'
            $report = & $schannelScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.Findings | Should -Contain 'TLS 1.0 Server ExplicitlyEnabled'
            $report.Findings | Should -Contain 'SSL 3.0 Client ExplicitlyEnabled'
            $report.Findings | Should -Contain 'TLS 1.2 Client ExplicitlyDisabled'
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Strict mode requires explicit legacy disablement / Strenger Modus verlangt ausdrückliche Deaktivierung' {
            $null = & $schannelScript -StrictMode true
            $LASTEXITCODE | Should -Be 2
            foreach ($protocol in @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1')) {
                foreach ($role in @('Server', 'Client')) { $global:certTestRegistry["$script:schannel\$protocol\$role"] = [pscustomobject]@{ Enabled = 0; DisabledByDefault = 1 } }
            }
            $report = & $schannelScript -StrictMode true | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            ($report.Protocols | Where-Object { $_.Protocol -eq 'TLS 1.0' -and $_.Role -eq 'Server' }).EffectiveState | Should -Be 'Disabled'
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $schannelScript -StrictMode 'on'
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'checkDotNetStrongCrypto' {
        BeforeEach {
            foreach ($view in @('HKLM:\SOFTWARE\Microsoft\.NETFramework', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework')) {
                foreach ($version in @('v4.0.30319', 'v2.0.50727')) {
                    $global:certTestRegistry["$view\$version"] = [pscustomobject]@{ SchUseStrongCrypto = 1; SystemDefaultTlsVersions = 1 }
                }
            }
        }
        It 'Accepts strong crypto settings / Akzeptiert starke Kryptografie' {
            $report = & $dotNetScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Settings).Count | Should -Be 4
        }
        It 'Warns on missing values / Warnt bei fehlenden Werten' {
            $global:certTestRegistry.Remove('HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319')
            $global:certTestRegistry['HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'] = [pscustomobject]@{ SchUseStrongCrypto = 0 }
            $env:resultCustomField = 'dotNetCrypto'
            $report = & $dotNetScript | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 2
            $report.NonCompliantCount | Should -Be 2
            Should -Invoke Ninja-Property-Set -Times 1 -Exactly
        }
        It 'Can skip v2.0.50727 / Kann v2.0.50727 auslassen' {
            $global:certTestRegistry.Remove('HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727')
            $report = & $dotNetScript -IncludeV2 false | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            @($report.Settings).Count | Should -Be 2
        }
        It 'Rejects invalid input / Lehnt ungültige Eingaben ab' {
            $null = & $dotNetScript -IncludeV2 'sometimes'
            $LASTEXITCODE | Should -Be 1
            $null = & $dotNetScript -CustomField '1field'
            $LASTEXITCODE | Should -Be 1
        }
    }
}
