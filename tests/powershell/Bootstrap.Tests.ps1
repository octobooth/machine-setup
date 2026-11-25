Describe 'bootstrap.ps1' {
    BeforeAll {
        . (Join-Path (Get-Location) 'bootstrap.ps1')
    }

    BeforeEach {
        $script:savedRelease = $env:BOOTH_RELEASE
        $script:savedProtocol = [Net.ServicePointManager]::SecurityProtocol
        $env:BOOTH_RELEASE = $null
        $script:workDir = $null
        $script:setupStatus = 0
        $script:setupArgs = @()
        $script:setupRelease = $null
        $script:savedReleaseForCheck = $null
        Mock Write-Host { }
        Mock Invoke-WebRequest {
            $script:workDir = Split-Path $OutFile
            Set-Content -LiteralPath $OutFile -Value 'mock archive'
        }
        Mock Expand-Archive {
            $root = Join-Path $DestinationPath 'machine-setup-test'
            New-Item -ItemType Directory -Path (Join-Path $root 'windows') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'setup.ps1') -Value '# mock setup'
            Set-Content -LiteralPath (Join-Path $root 'config.json') -Value '{}'
            Set-Content -LiteralPath (Join-Path $root 'windows/demo-launcher-loader.mjs') -Value '// mock loader'
        }
        Mock powershell.exe {
            $script:setupArgs = @($args)
            $script:setupRelease = $env:BOOTH_RELEASE
            $setup = $args[4]
            Test-Path -LiteralPath (Join-Path (Split-Path $setup) 'windows/demo-launcher-loader.mjs') | Should -BeTrue
            $global:LASTEXITCODE = $script:setupStatus
        }
    }

    AfterEach {
        $env:BOOTH_RELEASE | Should -Be $script:savedReleaseForCheck
        [Net.ServicePointManager]::SecurityProtocol | Should -Be $script:savedProtocol
        $env:BOOTH_RELEASE = $script:savedRelease
        if ($script:workDir) {
            Test-Path -LiteralPath $script:workDir | Should -BeFalse
        }
    }

    It 'downloads main with all assets and no release argument' {
        Invoke-SetupBootstrap

        $LASTEXITCODE | Should -Be 0
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $UseBasicParsing -and $Uri -eq 'https://github.com/octobooth/machine-setup/archive/refs/heads/main.zip'
        }
        $script:setupRelease | Should -BeNullOrEmpty
        $script:setupArgs | Should -Not -Contain '-Ref'
        $script:setupArgs[0] | Should -Be '-NoProfile'
    }

    It 'README command downloads and invokes main even with an inherited release' {
        $env:BOOTH_RELEASE = 'v1'
        $script:savedReleaseForCheck = 'v1'
        $script:readmeInstaller = $null
        Mock Invoke-WebRequest {
            $script:readmeInstaller = $OutFile
            Set-Content -LiteralPath $OutFile -Value '# mock bootstrap'
        }
        Mock powershell.exe {
            $script:setupArgs = @($args)
            $global:LASTEXITCODE = 0
        }
        $readme = Get-Content -Raw -LiteralPath (Join-Path (Get-Location) 'README.md')
        $command = [regex]::Match($readme, '(?ms)^   ```powershell\r?\n(.*?)^   ```').Groups[1].Value

        & ([scriptblock]::Create($command))

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $UseBasicParsing -and $Uri -eq 'https://raw.githubusercontent.com/octobooth/machine-setup/main/bootstrap.ps1'
        }
        $script:setupArgs[-2] | Should -Be '-Ref'
        $script:setupArgs[-1] | Should -Be 'main'
        Test-Path -LiteralPath $script:readmeInstaller | Should -BeFalse
    }

    It 'pins both repositories to the explicit release' {
        $env:BOOTH_RELEASE = 'v1'
        $script:savedReleaseForCheck = 'v1'
        Invoke-SetupBootstrap -Ref v2.3.4

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://github.com/octobooth/machine-setup/archive/refs/tags/v2.3.4.zip'
        }
        $script:setupRelease | Should -Be 'v2.3.4'
        $script:setupArgs[-2] | Should -Be '-Ref'
        $script:setupArgs[-1] | Should -Be 'v2.3.4'
    }

    It 'uses the environment release unless main is explicitly selected' {
        $env:BOOTH_RELEASE = 'v1'
        $script:savedReleaseForCheck = 'v1'
        Invoke-SetupBootstrap
        $script:setupRelease | Should -Be 'v1'

        Invoke-SetupBootstrap -Ref main
        $script:setupRelease | Should -BeNullOrEmpty
        $script:setupArgs | Should -Not -Contain '-Ref'
    }

    It 'rejects invalid refs before downloading' {
        { Invoke-SetupBootstrap -Ref '../main' } | Should -Throw '*Invalid ref*'
        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke powershell.exe -Times 0
    }

    It 'pins the setup archive to a commit without treating it as a demo release' {
        $env:BOOTH_RELEASE = 'v1'
        $script:savedReleaseForCheck = 'v1'
        Invoke-SetupBootstrap -Ref '1234567890abcdef1234567890abcdef12345678'

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://github.com/octobooth/machine-setup/archive/1234567890abcdef1234567890abcdef12345678.zip'
        }
        $script:setupRelease | Should -BeNullOrEmpty
        $script:setupArgs | Should -Not -Contain '-Ref'
        $LASTEXITCODE | Should -Be 0
    }

    It 'does not start setup when the download fails' {
        Mock Invoke-WebRequest {
            $script:workDir = Split-Path $OutFile
            throw 'download failed'
        }
        { Invoke-SetupBootstrap } | Should -Throw '*download failed*'
        Should -Invoke Expand-Archive -Times 0
        Should -Invoke powershell.exe -Times 0
    }

    It 'does not start setup when extraction fails' {
        Mock Expand-Archive { throw 'invalid archive' }
        { Invoke-SetupBootstrap } | Should -Throw '*invalid archive*'
        Should -Invoke powershell.exe -Times 0
    }

    It 'does not start setup when the archive is incomplete' {
        Mock Expand-Archive {
            New-Item -ItemType Directory -Path (Join-Path $DestinationPath 'machine-setup-test') -Force | Out-Null
        }
        { Invoke-SetupBootstrap } | Should -Throw '*missing setup.ps1 or config.json*'
        Should -Invoke powershell.exe -Times 0
    }

    It 'preserves setup failures and restores the release environment' {
        $env:BOOTH_RELEASE = 'v1'
        $script:savedReleaseForCheck = 'v1'
        $script:setupStatus = 37
        Invoke-SetupBootstrap -Ref main

        $LASTEXITCODE | Should -Be 37
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*Setup failed (exit 37)*' }
    }
}
