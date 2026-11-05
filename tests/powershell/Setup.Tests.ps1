$script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

Describe 'setup.ps1' {
    BeforeAll {
        . (Join-Path (Get-Location) 'setup.ps1')
        $script:config = Get-Content -Raw -Path (Join-Path (Get-Location) 'config.json') | ConvertFrom-Json

        # Silence the script's console logging so passing tests stay clean.
        # Assertions run against state ($failedItems, files), not console output.
        Mock Write-Info { }
        Mock Write-Success { }
        Mock Write-Warn { }
        Mock Write-Err { }
        Mock Write-Host { }
    }

    BeforeEach {
        $script:failedItems = @()
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Item Function:\winget -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
        Remove-Item Function:\winget -ErrorAction SilentlyContinue
    }

    It 'Set-EditorTheme merges the configured theme into settings.json' {
        $env:APPDATA = Join-Path $TestDrive 'AppData\Roaming'
        $settingsDir = Join-Path $env:APPDATA 'Code\User'
        $settingsPath = Join-Path $settingsDir 'settings.json'
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        '{"editor.fontSize":14}' | Out-File -FilePath $settingsPath -Encoding utf8

        Set-EditorTheme -Name 'VS Code' -SettingsDir 'Code'

        $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $settings.'workbench.colorTheme' | Should -Be 'Light 2026'
        $settings.'editor.fontSize' | Should -Be 14
    }

    It 'Register-MCPServers writes local and http server entries' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'

        Register-MCPServers

        $configPath = Join-Path $env:COPILOT_HOME 'mcp-config.json'
        Test-Path $configPath | Should -BeTrue

        $mcpConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $mcpConfig.mcpServers.playwright.command | Should -Be 'npx'
        $mcpConfig.mcpServers.'microsoft-learn'.url | Should -Be 'https://learn.microsoft.com/api/mcp'
    }

    It 'Register-MCPServers initializes mcpServers on an existing config that lacks it' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        '{"someOtherSetting":true}' | Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

        Register-MCPServers

        $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
        $mcpConfig.someOtherSetting | Should -BeTrue
        $mcpConfig.mcpServers.playwright.command | Should -Be 'npx'
    }

    It 'Invoke-SafeInstall records native command failures' {
        Invoke-SafeInstall -Description 'example failure' -Action { & cmd /c exit 1 }

        $script:failedItems | Should -Contain 'example failure'
    }

    It 'Install-WingetPackage explicitly selects the winget source' {
        $wingetLog = Join-Path $TestDrive 'winget.log'
        function global:winget {
            Set-Content -Path $wingetLog -Value ($args -join ' ')
            $global:LASTEXITCODE = 0
        }

        Install-WingetPackage -PackageId 'Microsoft.VisualStudioCode'

        (Get-Content -Path $wingetLog -Raw).Trim() | Should -Be 'install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements --silent'
        $script:failedItems | Should -BeNullOrEmpty
    }

    It 'Install-WingetPackage treats "already installed" exit code as success' {
        function global:winget { $global:LASTEXITCODE = -1978335135 }

        Install-WingetPackage -PackageId 'Example.Package'

        $script:failedItems | Should -Not -Contain 'winget: Example.Package'
        Remove-Item Function:\winget -ErrorAction SilentlyContinue
    }

    It 'Install-WingetPackage treats reboot-required exit code as success' {
        function global:winget { $global:LASTEXITCODE = 3010 }

        Install-WingetPackage -PackageId 'Example.Package'

        $script:failedItems | Should -Not -Contain 'winget: Example.Package'
        Remove-Item Function:\winget -ErrorAction SilentlyContinue
    }

    It 'Install-WingetPackage records genuine winget failures' {
        function global:winget { $global:LASTEXITCODE = -1978335231 }

        Install-WingetPackage -PackageId 'Example.Package'

        $script:failedItems | Should -Contain 'winget: Example.Package'
        Remove-Item Function:\winget -ErrorAction SilentlyContinue
    }

    It 'Install-GHExtension treats an already-installed extension as success' {
        function global:gh {
            Write-Output 'there is already an installed extension that provides the "example" command'
            $global:LASTEXITCODE = 1
        }

        Install-GHExtension -Extension 'github/gh-example'

        $script:failedItems | Should -Not -Contain 'gh extension: github/gh-example'
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
    }

    It 'Install-GHExtension skips extensions unsupported on the current architecture' {
        function global:gh {
            Write-Output 'gh-example unsupported for windows-arm64.'
            $global:LASTEXITCODE = 1
        }

        Install-GHExtension -Extension 'github/gh-example'

        $script:failedItems | Should -Not -Contain 'gh extension: github/gh-example'
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
    }

    It 'Install-GHExtension records genuine extension failures' {
        function global:gh {
            Write-Output 'HTTP 404: Not Found'
            $global:LASTEXITCODE = 1
        }

        Install-GHExtension -Extension 'github/gh-missing'

        $script:failedItems | Should -Contain 'gh extension: github/gh-missing'
        Remove-Item Function:\gh -ErrorAction SilentlyContinue
    }

    It 'Get-EdgePath falls back to command lookup when Edge is not in Program Files' {
        Mock Test-Path { $false } -ParameterFilter { $Path -like '*msedge.exe' }
        Mock Get-Command { [PSCustomObject]@{ Source = 'C:\Tools\msedge.exe' } } -ParameterFilter { $Name -eq 'msedge' }

        Get-EdgePath | Should -Be 'C:\Tools\msedge.exe'
    }

    It 'Get-EdgePath returns the full path when a single Program Files match exists' {
        $expected = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
        Mock Test-Path { $Path -eq $expected } -ParameterFilter { $Path -like '*msedge.exe' }

        Get-EdgePath | Should -Be $expected
    }

    It 'Copy-Repos skips repositories that already exist' {
        $env:USERPROFILE = $TestDrive
        $reposDir = Join-Path $env:USERPROFILE 'repos'
        $ghLog = Join-Path $TestDrive 'gh.log'
        New-Item -Path $reposDir -ItemType Directory -Force | Out-Null

        foreach ($repo in $script:config.shared.repos_to_clone) {
            $repoName = ($repo -split '/')[-1]
            New-Item -Path (Join-Path $reposDir $repoName) -ItemType Directory -Force | Out-Null
        }

        function global:gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
            Add-Content -Path $ghLog -Value ($Args -join ' ')
        }

        Copy-Repos

        Test-Path $ghLog | Should -BeFalse
    }

    It 'config installs the GitHub Copilot app' {
        $script:config.windows.packages | Should -Contain 'GitHub.CopilotApp'
        $script:config.windows.packages | Should -Contain 'Git.Git'
        $script:config.shared.gh_auth_scopes | Should -Contain 'codespace'
        $script:config.shared.gh_auth_scopes | Should -Contain 'delete_repo'
        $script:config.shared.gh_auth_scopes | Should -Contain 'project'
        $script:config.shared.gh_auth_scopes | Should -Contain 'workflow'
    }

    It 'config installs PowerShell 7 first on Windows' {
        $script:config.windows.packages[0] | Should -Be 'Microsoft.PowerShell'
    }

    It 'Copy-Repos defers new clones without recording failures when requested' {
        $env:USERPROFILE = Join-Path $TestDrive 'unauthenticated'
        Mock gh { throw 'Cloning must not run without credentials' }

        Copy-Repos -SkipClone

        Should -Invoke gh -Times 0 -Exactly
        Should -Invoke Write-Warn -Times $script:config.shared.repos_to_clone.Count -Exactly -ParameterFilter {
            $Message -like 'Skipping clone:*'
        }
        $script:failedItems | Should -BeNullOrEmpty
    }

    Context 'Set-TaskbarPins' {
        BeforeEach {
            $script:savedPolicyKey = $script:TaskbarPolicyKey
            $script:savedForce = $script:ForceReinstall
            $testId = [guid]::NewGuid().ToString('N')
            $script:TaskbarPolicyKey = "TestRegistry:\Policies\$testId\Explorer"
            $script:ForceReinstall = $false
            $env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH = Join-Path $TestDrive "$testId\TaskbarLayout.xml"
            Mock Restart-Explorer { }
            if (-not (Get-Command Get-StartApps -ErrorAction SilentlyContinue)) {
                function global:Get-StartApps { }
            }
            Mock Get-StartApps { @() }
        }

        AfterEach {
            $script:TaskbarPolicyKey = $script:savedPolicyKey
            $script:ForceReinstall = $script:savedForce
            Remove-Item Env:\SETUP_SCRIPT_TASKBAR_LAYOUT_PATH -ErrorAction SilentlyContinue
        }

        It 'writes the layout, sets the policy, and restarts Explorer' {
            Set-TaskbarPins

            [xml]$layout = Get-Content -Raw -Path $env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH
            $pinList = $layout.LayoutModificationTemplate.CustomTaskbarLayoutCollection.TaskbarLayout.TaskbarPinList
            @($pinList.DesktopApp.DesktopApplicationID) | Should -Be @(
                'Microsoft.VisualStudioCode', 'Microsoft.VisualStudioCodeInsiders', 'com.github.githubapp',
                '{6D809377-6AF0-444B-8957-A3773F02200E}\VideoLAN\VLC\vlc.exe')
            $pinList.UWA.AppUserModelID | Should -Be 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App'

            $policy = Get-ItemProperty -Path $script:TaskbarPolicyKey
            $policy.StartLayoutFile | Should -Be $env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH
            $policy.LockedStartLayout | Should -Be 1
            Should -Invoke Restart-Explorer -Times 1 -Exactly
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'skips restarting Explorer when the layout is already applied' {
            Set-TaskbarPins
            Set-TaskbarPins

            Should -Invoke Restart-Explorer -Times 1 -Exactly
        }

        It 'reapplies the layout with FORCE_REINSTALL' {
            Set-TaskbarPins
            $script:ForceReinstall = $true
            Set-TaskbarPins

            Should -Invoke Restart-Explorer -Times 2 -Exactly
        }
    }

    Context 'Invoke-Main authentication modes' {
        BeforeEach {
            $script:savedNonInteractive = $script:NonInteractive
            Mock Test-Prerequisites { $true }
            Mock Import-Config { }
            Mock Install-Packages { }
            Mock Set-VLCConfiguration { }
            Mock Set-TaskbarPins { }
            Mock Start-PostInstallApps { }
            Mock Connect-GitHubWeb { }
            Mock Connect-GH { }
            Mock Install-GHExtensions { }
            Mock Copy-Repos { }
            Mock Initialize-Editors { }
            Mock Register-MCPServers { }
                Mock Write-Summary { }
            Mock Get-Command { $true } -ParameterFilter { $Name -eq 'gh' }
        }

        AfterEach {
            $script:NonInteractive = $script:savedNonInteractive
        }

        It 'uses active credentials even when an inactive account is expired' {
            $script:NonInteractive = $true
            $ghLog = Join-Path $TestDrive 'gh-active-auth.log'
            function global:gh {
                Add-Content -Path $ghLog -Value ($args -join ' ')
                $global:LASTEXITCODE = if ($args -contains '--active') { 0 } else { 1 }
            }

            Invoke-Main

            @(Get-Content -Path $ghLog).Count | Should -Be 1
            Get-Content -Path $ghLog | Should -Be 'auth status --active -h github.com'
            Should -Invoke Install-GHExtensions -Times 1 -Exactly
            Should -Invoke Copy-Repos -Times 1 -Exactly -ParameterFilter { -not $SkipClone }
            Should -Invoke Connect-GH -Times 0 -Exactly
            Should -Invoke Connect-GitHubWeb -Times 0 -Exactly
        }

        It 'defers extensions and clones when credentials are unavailable' {
            $script:NonInteractive = $true
            Mock gh { $global:LASTEXITCODE = 1 }

            Invoke-Main

            Should -Invoke Install-GHExtensions -Times 0 -Exactly
            Should -Invoke Copy-Repos -Times 1 -Exactly -ParameterFilter { $SkipClone }
            Should -Invoke Connect-GH -Times 0 -Exactly
            Should -Invoke Connect-GitHubWeb -Times 0 -Exactly
            Should -Invoke Write-Warn -Times 1 -Exactly -ParameterFilter {
                $Message -like 'GitHub CLI credentials unavailable:*'
            }
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'defers extensions and clones when gh is unavailable' {
            $script:NonInteractive = $true
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gh' }
            Mock gh { throw 'GitHub CLI is unavailable' }

            Invoke-Main

            Should -Invoke gh -Times 0 -Exactly
            Should -Invoke Install-GHExtensions -Times 0 -Exactly
            Should -Invoke Copy-Repos -Times 1 -Exactly -ParameterFilter { $SkipClone }
        }

        It 'preserves interactive authentication and cloning by default' {
            $script:NonInteractive = $false
            Mock gh { throw 'Connect-GH handles interactive authentication' }

            Invoke-Main

            Should -Invoke Connect-GitHubWeb -Times 1 -Exactly
            Should -Invoke Connect-GH -Times 1 -Exactly
            Should -Invoke Copy-Repos -Times 1 -Exactly -ParameterFilter { -not $SkipClone }
            Should -Invoke gh -Times 0 -Exactly
        }
    }

    It 'Confirm-GHScope refreshes only missing scopes using the stored login' {
        $ghLog = Join-Path $TestDrive 'gh-scope-refresh.log'
        $env:GH_TOKEN = 'env-token'
        function global:gh {
            Add-Content -Path $ghLog -Value "$($args -join ' ') [GH_TOKEN=$env:GH_TOKEN]"
            if ($args[0] -eq 'auth' -and $args[1] -eq 'status') {
                Write-Output "  - Token scopes: 'codespace', 'gist', 'repo'"
            }
            $global:LASTEXITCODE = 0
        }

        try {
            Confirm-GHScope
            $log = Get-Content -Path $ghLog
            $log | Should -Contain 'auth refresh -h github.com -s delete_repo,project,workflow [GH_TOKEN=]'
            $env:GH_TOKEN | Should -Be 'env-token'
            $script:failedItems | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        }
    }

    It 'Confirm-GHScope does nothing when all scopes are granted' {
        $ghLog = Join-Path $TestDrive 'gh-scope-noop.log'
        function global:gh {
            Add-Content -Path $ghLog -Value ($args -join ' ')
            Write-Output "  - Token scopes: 'codespace', 'delete_repo', 'project', 'repo', 'workflow'"
            $global:LASTEXITCODE = 0
        }

        Confirm-GHScope

        Get-Content -Path $ghLog -Raw | Should -Not -Match 'auth refresh'
    }
}
