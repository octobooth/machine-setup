# Windows PowerShell 5.1 turns a native command's redirected stderr into red
# NativeCommandError records even when it succeeds, which made a successful
# `git pull` look like a failure. These use real processes, not mocks.
Describe 'Invoke-NativeCommand' {
    BeforeAll {
        . (Join-Path (Get-Location) 'install-demo-launcher.ps1')

        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }
        Mock Out-Host { }

        # The PowerShell running the tests (pwsh or powershell.exe), as a native command
        $script:shell = (Get-Process -Id $PID).Path

        function Invoke-FakeNative {
            param([int]$ExitCode)
            Invoke-NativeCommand $script:shell -NoProfile -NonInteractive -Command "[Console]::Out.WriteLine('Updating 1234567..89abcde'); [Console]::Error.WriteLine('   1234567..89abcde  main -> main'); exit $ExitCode"
        }

        function Invoke-TestGit {
            param([Parameter(ValueFromRemainingArguments)][string[]]$GitArgs)
            $output = & git -c user.name=t -c user.email=t@t -c core.autocrlf=false @GitArgs 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $output" }
        }
    }

    It 'returns stderr from a successful command as plain text' {
        $output = @(Invoke-FakeNative -ExitCode 0)
        $LASTEXITCODE | Should -Be 0
        # stdout and stderr are separate pipes, so their order isn't guaranteed
        $output.Count | Should -Be 2
        $output | Should -Contain 'Updating 1234567..89abcde'
        $output | Should -Contain '   1234567..89abcde  main -> main'
        $output | ForEach-Object { $_ | Should -BeOfType [string] }
    }

    It 'leaves $LASTEXITCODE set and returns the error text when the command fails' {
        $output = @(Invoke-FakeNative -ExitCode 1)
        $LASTEXITCODE | Should -Be 1
        $output | Should -Contain '   1234567..89abcde  main -> main'
        $output | ForEach-Object { $_ | Should -BeOfType [string] }
    }

    It "doesn't throw on stderr when ErrorActionPreference is Stop" {
        $ErrorActionPreference = 'Stop'
        { Invoke-FakeNative -ExitCode 0 } | Should -Not -Throw
        $ErrorActionPreference | Should -Be 'Stop'
    }

    It 'passes dash-prefixed arguments through to the command' {
        $output = @(Invoke-NativeCommand git -C (Get-Location) rev-parse --is-inside-work-tree)
        $LASTEXITCODE | Should -Be 0
        $output | Should -Be @('true')
    }

    It 'passes a single argument through whole' {
        $output = @(Invoke-NativeCommand git --version)
        $LASTEXITCODE | Should -Be 0
        $output[0] | Should -Match '^git version '
    }

    It 'runs a command with no arguments' {
        $output = @(Invoke-NativeCommand git)
        # git with no arguments prints its usage and exits 1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'usage: git'
    }

    It "doesn't throw when a silenced git command fails under ErrorActionPreference Stop" {
        $ErrorActionPreference = 'Stop'
        { Invoke-NativeCommand git -C (Get-Location) tag -d no-such-tag-for-tests | Out-Null } | Should -Not -Throw
        $LASTEXITCODE | Should -Be 1
    }

    Context 'Get-NativeCommandOutput' {
        BeforeAll {
            function Get-FakeValue {
                param([int]$ExitCode)
                Get-NativeCommandOutput $script:shell -NoProfile -NonInteractive -Command "[Console]::Error.WriteLine('warning: noise'); [Console]::Out.WriteLine('main'); [Console]::Error.WriteLine('trace: more noise'); exit $ExitCode"
            }
        }

        It 'returns only stdout when stderr has noise' {
            $output = @(Get-FakeValue -ExitCode 0)
            $LASTEXITCODE | Should -Be 0
            $output | Should -Be @('main')
            $output[0] | Should -BeOfType [string]
        }

        It 'leaves $LASTEXITCODE set when the command fails' {
            $output = @(Get-FakeValue -ExitCode 1)
            $LASTEXITCODE | Should -Be 1
            $output | Should -Be @('main')
        }

        It "doesn't throw on stderr when ErrorActionPreference is Stop" {
            $ErrorActionPreference = 'Stop'
            { Get-FakeValue -ExitCode 0 } | Should -Not -Throw
        }

        It 'keeps a trusted origin URL clean when git traces to stderr' {
            $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Invoke-TestGit -c init.defaultBranch=main init -q $repo
            Invoke-TestGit -C $repo remote add origin 'https://github.com/octobooth-demos/repo-setup-scripts.git'
            $env:GIT_TRACE = '1'
            try {
                $url = @(Get-NativeCommandOutput git -C $repo remote get-url origin)
                $trusted = Test-DemoLauncherRemote -Target $repo
            }
            finally {
                Remove-Item Env:\GIT_TRACE -ErrorAction SilentlyContinue
            }
            $url | Should -Be @('https://github.com/octobooth-demos/repo-setup-scripts.git')
            $trusted | Should -BeTrue
        }
    }

    Context 'install-demo-launcher.ps1 updating its checkout' {
        BeforeAll {
            # The test origin is a local folder, so treat it as the trusted repo
            Mock Test-DemoLauncherRemote { $true }
        }

        BeforeEach {
            $script:originalUserProfile = $env:USERPROFILE
            $env:USERPROFILE = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
            $script:failedItems = @()

            $script:origin = Join-Path $env:USERPROFILE 'origin.git'
            $script:work = Join-Path $env:USERPROFILE 'work'
            $script:checkout = Get-DemoLauncherRepoDir
            Invoke-TestGit -c init.defaultBranch=main init -q --bare $script:origin
            Invoke-TestGit -c init.defaultBranch=main init -q $script:work
            Invoke-TestGit -C $script:work checkout -q -b main
            [System.IO.File]::WriteAllText((Join-Path $script:work 'file.txt'), 'one')
            Invoke-TestGit -C $script:work add -A
            Invoke-TestGit -C $script:work commit -q -m one
            Invoke-TestGit -C $script:work remote add origin $script:origin
            Invoke-TestGit -C $script:work push -q origin main
            Invoke-TestGit clone -q $script:origin $script:checkout
            [System.IO.File]::WriteAllText((Join-Path $script:work 'file.txt'), 'two')
            Invoke-TestGit -C $script:work commit -q -am two
            Invoke-TestGit -C $script:work push -q origin main
        }

        AfterEach {
            $env:USERPROFILE = $script:originalUserProfile
        }

        It "prints git pull's stderr progress as text and succeeds" {
            $output = @(Sync-DemoLauncherRepo)
            $script:failedItems | Should -BeNullOrEmpty
            # git writes "main -> origin/main" to stderr even when the pull works
            ($output -join "`n") | Should -Match 'main\s+->\s+origin/main'
            $output | ForEach-Object { $_ | Should -BeOfType [string] }
            Should -Invoke Write-Err -Times 0 -Exactly
        }

        It 'reports a failed pull' {
            Remove-Item -LiteralPath $script:origin -Recurse -Force
            $output = @(Sync-DemoLauncherRepo)
            $script:failedItems | Should -Be @('update: octobooth-demos/repo-setup-scripts')
            ($output -join "`n") | Should -Match 'fatal:'
            $output | ForEach-Object { $_ | Should -BeOfType [string] }
            Should -Invoke Write-Err -ParameterFilter { $Message -eq 'Failed: update: octobooth-demos/repo-setup-scripts' }
        }
    }
}
