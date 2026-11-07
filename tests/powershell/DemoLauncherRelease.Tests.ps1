# Uses real git repos, so these tests don't share the git mock in InstallDemoLauncher.Tests.ps1
Describe 'Demo Launcher releases' {
    BeforeAll {
        . (Join-Path (Get-Location) 'install-demo-launcher.ps1')

        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }
        Mock Out-Host { }
        # The test origin is a local folder, so treat it as the trusted repo
        Mock Test-DemoLauncherRemote { $true }
        Mock Test-DemoLauncherPrerequisite { $true }

        function Invoke-TestGit {
            param([Parameter(ValueFromRemainingArguments)][string[]]$GitArgs)
            $output = & git -c user.name=t -c user.email=t@t -c core.autocrlf=false @GitArgs 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $output" }
            return $output
        }

        # Commits a change to main in the work clone and pushes it to the origin
        function Add-ReleaseCommit {
            param([string]$Text)
            [System.IO.File]::WriteAllText((Join-Path $script:work 'file.txt'), $Text)
            Invoke-TestGit -C $script:work commit -q -am $Text | Out-Null
            Invoke-TestGit -C $script:work push -q origin main | Out-Null
        }

        function Get-Head {
            param([string]$Target, [string]$Rev = 'HEAD')
            return "$(git -C $Target rev-parse $Rev)".Trim()
        }

        function Test-Detached {
            git -C $script:checkout symbolic-ref --quiet HEAD 2>$null | Out-Null
            return ($LASTEXITCODE -ne 0)
        }
    }

    BeforeEach {
        $script:originalUserProfile = $env:USERPROFILE
        $script:originalCopilotHome = $env:COPILOT_HOME
        $script:originalRelease = $env:BOOTH_RELEASE
        $env:USERPROFILE = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:COPILOT_HOME = $null
        $env:BOOTH_RELEASE = $null
        New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
        $script:failedItems = @()

        # Origin with v1.0.0 and a moving v1 on the first commit, plus a newer commit on main
        $script:origin = Join-Path $env:USERPROFILE 'origin.git'
        $script:work = Join-Path $env:USERPROFILE 'work'
        $script:checkout = Get-DemoLauncherRepoDir
        Invoke-TestGit -c init.defaultBranch=main init -q --bare $script:origin | Out-Null
        Invoke-TestGit -c init.defaultBranch=main init -q $script:work | Out-Null
        Invoke-TestGit -C $script:work checkout -q -b main | Out-Null
        $launcherDir = Join-Path (Join-Path (Join-Path $script:work '.github') 'extensions') 'demo-launcher'
        New-Item -Path $launcherDir -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $launcherDir 'extension.mjs'), '// launcher')
        [System.IO.File]::WriteAllText((Join-Path $script:work 'file.txt'), 'one')
        Invoke-TestGit -C $script:work add -A | Out-Null
        Invoke-TestGit -C $script:work commit -q -m one | Out-Null
        Invoke-TestGit -C $script:work tag v1.0.0 | Out-Null
        Invoke-TestGit -C $script:work tag v1 | Out-Null
        Invoke-TestGit -C $script:work remote add origin $script:origin | Out-Null
        Invoke-TestGit -C $script:work push -q origin main --tags | Out-Null
        Invoke-TestGit clone -q $script:origin $script:checkout | Out-Null
        Add-ReleaseCommit -Text 'two'
    }

    AfterEach {
        $env:USERPROFILE = $script:originalUserProfile
        $env:COPILOT_HOME = $script:originalCopilotHome
        $env:BOOTH_RELEASE = $script:originalRelease
    }

    It 'pins the checkout to a release with -Ref and writes the loader' {
        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0

        Test-Detached | Should -BeTrue
        Get-Head $script:checkout | Should -Be (Get-Head $script:work 'v1.0.0')
        Test-Path (Get-DemoLauncherLoaderPath) | Should -BeTrue
    }

    It 'reads the release from BOOTH_RELEASE' {
        $env:BOOTH_RELEASE = 'v1.0.0'

        Invoke-DemoLauncherMain | Should -Be 0

        Get-Head $script:checkout | Should -Be (Get-Head $script:work 'v1.0.0')
    }

    It 'follows a major tag that moved to a newer release' {
        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0
        Invoke-TestGit -C $script:work tag v1.1.0 | Out-Null
        Invoke-TestGit -C $script:work tag -f v1 | Out-Null
        Invoke-TestGit -C $script:work push -q origin v1.1.0 | Out-Null
        Invoke-TestGit -C $script:work push -q -f origin v1 | Out-Null

        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0

        Get-Head $script:checkout | Should -Be (Get-Head $script:work 'v1.1.0')
    }

    It 'fails without changing the checkout when the release tag does not exist' {
        $before = Get-Head $script:checkout

        Invoke-DemoLauncherMain -Ref v9 | Should -Be 1

        $script:failedItems | Should -Contain 'release: octobooth-demos/repo-setup-scripts at v9'
        Should -Invoke Write-Err -ParameterFilter { $Message -like "Release tag v9 doesn't exist*" }
        Test-Detached | Should -BeFalse
        Get-Head $script:checkout | Should -Be $before
        Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
    }

    It 'refuses a release tag withdrawn on origin and deletes the local copy' {
        git -C $script:checkout fetch -q --tags origin 2>$null
        Invoke-TestGit -C $script:work push -q origin :refs/tags/v1.0.0 | Out-Null

        Invoke-DemoLauncherMain -Ref v1.0.0 | Should -Be 1

        Should -Invoke Write-Err -ParameterFilter { $Message -like "Release tag v1.0.0 isn't on GitHub (it may have been withdrawn)*" }
        Test-Detached | Should -BeFalse
        git -C $script:checkout rev-parse -q --verify refs/tags/v1.0.0 2>$null | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
    }

    It 'rejects an invalid release tag name' {
        Invoke-DemoLauncherMain -Ref '--upload-pack=x' | Should -Be 1

        Should -Invoke Write-Err -ParameterFilter { $Message -like "*isn't a valid tag name*" }
    }

    It 'refuses to pin a checkout with local changes' {
        [System.IO.File]::WriteAllText((Join-Path $script:checkout 'file.txt'), 'local')

        Invoke-DemoLauncherMain -Ref v1 | Should -Be 1

        Should -Invoke Write-Err -ParameterFilter { $Message -like '*has local changes*' }
        Should -Invoke Write-Err -ParameterFilter { $Message -like '*stash*' }
        Test-Detached | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $script:checkout 'file.txt')) | Should -Be 'local'
    }

    It 'switches a pinned checkout back to main and pulls without a release' {
        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0

        Invoke-DemoLauncherMain | Should -Be 0

        Test-Detached | Should -BeFalse
        "$(git -C $script:checkout symbolic-ref --short HEAD)".Trim() | Should -Be 'main'
        Get-Head $script:checkout | Should -Be (Get-Head $script:work 'main')
        Should -Invoke Write-Info -ParameterFilter { $Message -like '*was pinned to v1*switching back to main*' }
    }

    It 'switches a pinned checkout back to main when git writes trace lines to stderr' {
        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0

        # Trace lines on stderr must not end up in the branch name it parses
        $env:GIT_TRACE = '1'
        try {
            Invoke-DemoLauncherMain | Should -Be 0
        }
        finally {
            Remove-Item Env:\GIT_TRACE -ErrorAction SilentlyContinue
        }

        "$(git -C $script:checkout symbolic-ref --short HEAD)".Trim() | Should -Be 'main'
        Should -Invoke Write-Info -ParameterFilter { $Message -like '*was pinned to v1;*switching back to main*' }
    }

    It 'stays on the pinned release when it has local changes' {
        Invoke-DemoLauncherMain -Ref v1 | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $script:checkout 'file.txt'), 'local')

        Invoke-DemoLauncherMain | Should -Be 1

        $script:failedItems | Should -Contain "update: octobooth-demos/repo-setup-scripts (couldn't leave its pinned release)"
        Test-Detached | Should -BeTrue
    }

    Context 'setup.ps1' {
        It 'pins repo-setup-scripts when a release is requested' {
            Sync-DemoLauncherRelease -Release v1 | Should -BeTrue

            Get-Head $script:checkout | Should -Be (Get-Head $script:work 'v1')
        }

        It 'reports a missing release so the loader is not rewritten' {
            Sync-DemoLauncherRelease -Release v9 | Should -BeFalse

            Test-Detached | Should -BeFalse
        }

        It 'leaves the checkout alone without a release' {
            $before = Get-Head $script:checkout

            Sync-DemoLauncherRelease -Release '' | Should -BeTrue

            Get-Head $script:checkout | Should -Be $before
            Should -Invoke Write-Warn -Times 0 -Exactly
        }

        It 'moves a pinned checkout back to main and pulls without a release' {
            Sync-DemoLauncherRelease -Release v1 | Should -BeTrue

            Sync-DemoLauncherRelease -Release '' | Should -BeTrue

            Test-Detached | Should -BeFalse
            Get-Head $script:checkout | Should -Be (Get-Head $script:work 'main')
        }

        It 'keeps a pinned checkout with local changes and skips the loader' {
            Sync-DemoLauncherRelease -Release v1 | Should -BeTrue
            [System.IO.File]::WriteAllText((Join-Path $script:checkout 'file.txt'), 'local')

            Sync-DemoLauncherRelease -Release '' | Should -BeFalse

            Test-Detached | Should -BeTrue
        }

        It 'prefers -Ref over BOOTH_RELEASE' {
            $env:BOOTH_RELEASE = 'v1'
            Get-BoothRelease -Ref 'v1.0.0' | Should -Be 'v1.0.0'
            Get-BoothRelease | Should -Be 'v1'
        }
    }
}
