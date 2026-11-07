Describe 'install-demo-launcher.ps1' {
    BeforeAll {
        . (Join-Path (Get-Location) 'install-demo-launcher.ps1')

        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }
        Mock Out-Host { }
    }

    BeforeEach {
        $script:originalUserProfile = $env:USERPROFILE
        $script:originalCopilotHome = $env:COPILOT_HOME
        $env:USERPROFILE = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:COPILOT_HOME = $null
        New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:ghLoggedIn = $true
        $script:gitExitCode = 0
        $script:originUrl = 'https://github.com/octobooth-demos/repo-setup-scripts.git'

        Mock git {
            if ($args -contains 'remote') {
                $global:LASTEXITCODE = 0
                return $script:originUrl
            }
            $script:calls.Add("git $($args -join ' ')")
            $global:LASTEXITCODE = $script:gitExitCode
        }
        Mock gh {
            $script:calls.Add("gh $($args -join ' ')")
            if ($args[0] -eq 'auth') {
                $global:LASTEXITCODE = if ($script:ghLoggedIn) { 0 } else { 1 }
            } else {
                if ($args[0] -eq 'repo' -and $args[1] -eq 'clone') { New-FakeCheckout -Target $args[3] }
                $global:LASTEXITCODE = 0
            }
        }

        function New-FakeCheckout {
            param([string]$Target)
            $launcherDir = Join-Path (Join-Path (Join-Path $Target '.github') 'extensions') 'demo-launcher'
            New-Item -Path (Join-Path $Target '.git') -ItemType Directory -Force | Out-Null
            New-Item -Path $launcherDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $launcherDir 'extension.mjs') -Value '// launcher'
        }
    }

    AfterEach {
        $env:USERPROFILE = $script:originalUserProfile
        $env:COPILOT_HOME = $script:originalCopilotHome
    }

    It 'reads the repo-setup-scripts repo from config.json' {
        Import-Config
        Get-DemoLauncherRepo | Should -Be 'octobooth-demos/repo-setup-scripts'
    }

    It 'ignores an untrusted repo-setup-scripts entry in config.json' {
        $script:config = [pscustomobject]@{ shared = [pscustomobject]@{ repos_to_clone = @('attacker/repo-setup-scripts') } }

        Get-DemoLauncherRepo | Should -Be 'octobooth-demos/repo-setup-scripts'
        Should -Invoke Write-Warn -Times 1 -Exactly
    }

    It 'accepts SSH remotes for the trusted repo' {
        $script:originUrl = 'git@github.com:octobooth-demos/repo-setup-scripts.git'
        Test-DemoLauncherRemote -Target (Get-DemoLauncherRepoDir) | Should -BeTrue
    }

    It 'refuses to pull a checkout whose origin is not the trusted repo' {
        New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
        $script:originUrl = 'https://github.com/attacker/repo-setup-scripts.git'

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'git *pull*' } | Should -BeNullOrEmpty
    }

    It 'clones repo-setup-scripts when the checkout is missing' {
        $target = Get-DemoLauncherRepoDir

        Invoke-DemoLauncherMain | Should -Be 0

        $script:calls | Should -Contain "gh repo clone octobooth-demos/repo-setup-scripts $target"
        $script:calls | Where-Object { $_ -like 'git *pull*' } | Should -BeNullOrEmpty
    }

    It 'fast-forwards an existing checkout instead of cloning' {
        $target = Get-DemoLauncherRepoDir
        New-FakeCheckout -Target $target

        Invoke-DemoLauncherMain | Should -Be 0

        $script:calls | Should -Contain "git -C $target pull --ff-only"
        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
    }

    It 'fails without cloning when the GitHub CLI is not logged in' {
        $script:ghLoggedIn = $false

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
        $script:failedItems | Should -HaveCount 1
    }

    It 'reports a failed pull' {
        New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
        $script:gitExitCode = 1

        Invoke-DemoLauncherMain | Should -Be 1

        $script:failedItems | Should -Contain 'update: octobooth-demos/repo-setup-scripts'
    }

    It 'refuses to overwrite a folder that is not a git checkout' {
        New-Item -Path (Get-DemoLauncherRepoDir) -ItemType Directory -Force | Out-Null

        Invoke-DemoLauncherMain | Should -Be 1

        $script:calls | Where-Object { $_ -like 'gh repo clone*' } | Should -BeNullOrEmpty
    }

    Context 'loader' {
        It 'writes the loader under $HOME\.copilot by default' {
            Get-DemoLauncherLoaderPath | Should -Be (Join-Path (Join-Path (Join-Path (Join-Path $env:USERPROFILE '.copilot') 'extensions') 'demo-launcher') 'extension.mjs')
        }

        It 'writes the loader under COPILOT_HOME when it is set' {
            $env:COPILOT_HOME = Join-Path $TestDrive 'custom-copilot-home'
            Get-DemoLauncherLoaderPath | Should -Be (Join-Path (Join-Path (Join-Path $env:COPILOT_HOME 'extensions') 'demo-launcher') 'extension.mjs')
        }

        It 'installs a loader that imports the checkout via pathToFileURL and guards against a second copy' {
            Invoke-DemoLauncherMain | Should -Be 0

            $loader = Get-DemoLauncherLoaderPath
            $content = Get-Content -Raw -Path $loader
            $launcher = Join-Path (Join-Path (Join-Path (Join-Path (Get-DemoLauncherRepoDir) '.github') 'extensions') 'demo-launcher') 'extension.mjs'
            $content | Should -Match ([regex]::Escape('await import(pathToFileURL(launcher).href)'))
            $content | Should -Match 'function sessionRepoHasOwnCopy\(\)'
            $content | Should -Match ([regex]::Escape('await joinSession({})'))
            $content | Should -Match ([regex]::Escape('const launcher = ' + (ConvertTo-Json -InputObject $launcher -Compress) + ';'))
        }

        It 'writes the loader as UTF-8 without a BOM' {
            Invoke-DemoLauncherMain | Should -Be 0

            $bytes = [System.IO.File]::ReadAllBytes((Get-DemoLauncherLoaderPath))
            $bytes.Length | Should -BeGreaterThan 3
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }

        It 'escapes Windows paths into a valid JavaScript string' {
            $content = Get-DemoLauncherLoaderContent -LauncherPath 'C:\Users\o"booth\repos\repo-setup-scripts\.github\extensions\demo-launcher\extension.mjs'

            $content | Should -Match ([regex]::Escape('const launcher = "C:\\Users\\o\"booth\\repos\\repo-setup-scripts\\.github\\extensions\\demo-launcher\\extension.mjs";'))
        }

        It 'produces a loader that node can parse' -Skip:(-not (Get-Command node -ErrorAction SilentlyContinue)) {
            $file = Join-Path $TestDrive 'loader-check.mjs'
            $content = Get-DemoLauncherLoaderContent -LauncherPath 'C:\Users\octobooth\repos\repo-setup-scripts\.github\extensions\demo-launcher\extension.mjs'
            [System.IO.File]::WriteAllText($file, $content, (New-Object System.Text.UTF8Encoding $false))

            node --check $file
            $LASTEXITCODE | Should -Be 0
        }

        It 'copies the loader the checkout ships when it exists' {
            $target = Get-DemoLauncherRepoDir
            New-FakeCheckout -Target $target
            $shippedDir = Join-Path (Join-Path (Join-Path $target '.github') 'extensions') 'demo-launcher-loader'
            New-Item -Path $shippedDir -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $shippedDir 'extension.mjs'), "// shipped loader`n", (New-Object System.Text.UTF8Encoding $true))

            Invoke-DemoLauncherMain | Should -Be 0

            [System.IO.File]::ReadAllText((Get-DemoLauncherLoaderPath)) | Should -Be "// shipped loader`n"
            $bytes = [System.IO.File]::ReadAllBytes((Get-DemoLauncherLoaderPath))
            $bytes[0] | Should -Not -Be 0xEF
        }

        It 'fails without writing a loader when the checkout has no launcher' {
            New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null

            Invoke-DemoLauncherMain | Should -Be 1

            Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
        }

        It 'does not write a loader when the checkout origin is untrusted' {
            New-FakeCheckout -Target (Get-DemoLauncherRepoDir)
            $script:originUrl = 'https://github.com/attacker/repo-setup-scripts.git'

            Invoke-DemoLauncherMain | Should -Be 1

            Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
        }

        It '-Uninstall removes only the loader file' {
            $loader = Get-DemoLauncherLoaderPath
            $loaderDir = Split-Path $loader
            $artifacts = Join-Path $loaderDir 'artifacts'
            New-Item -Path $artifacts -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $artifacts 'run.json') -Value '{}'
            Set-Content -Path $loader -Value '// loader'

            Invoke-DemoLauncherMain -Uninstall | Should -Be 0

            Test-Path $loader | Should -BeFalse
            Test-Path (Join-Path $artifacts 'run.json') | Should -BeTrue
            $script:calls | Should -BeNullOrEmpty
        }

        It '-Uninstall succeeds when no loader is installed' {
            Invoke-DemoLauncherMain -Uninstall | Should -Be 0
        }
    }
}
