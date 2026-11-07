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
        $script:adminSkippedItems = @()
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
        $originalServers = $script:config.shared.mcp_servers
        $script:config.shared.mcp_servers = @($originalServers) + [PSCustomObject]@{ name = 'local-example'; type = 'local'; command = 'local-mcp'; args = @('--stdio') }

        try {
            Register-MCPServers
        } finally {
            $script:config.shared.mcp_servers = $originalServers
        }

        $configPath = Join-Path $env:COPILOT_HOME 'mcp-config.json'
        Test-Path $configPath | Should -BeTrue

        $mcpConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $mcpConfig.mcpServers.'local-example'.command | Should -Be 'local-mcp'
        $mcpConfig.mcpServers.'microsoft-learn'.url | Should -Be 'https://learn.microsoft.com/api/mcp'
        $mcpConfig.mcpServers.PSObject.Properties['playwright'] | Should -BeNullOrEmpty
    }

    It 'Register-MCPServers removes the old npx Playwright entry and keeps others' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        '{"someOtherSetting":true,"mcpServers":{"playwright":{"tools":["*"],"type":"local","command":"npx","args":["@playwright/mcp@latest"]},"custom":{"type":"http","url":"https://example.com/mcp"}}}' |
            Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

        Register-MCPServers

        $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
        $mcpConfig.mcpServers.PSObject.Properties['playwright'] | Should -BeNullOrEmpty
        $mcpConfig.mcpServers.custom.url | Should -Be 'https://example.com/mcp'
        $mcpConfig.someOtherSetting | Should -BeTrue
    }

    It 'Register-MCPServers keeps a custom Playwright entry that does not use npx' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        '{"mcpServers":{"playwright":{"type":"local","command":"C:\\tools\\playwright-mcp.exe","args":["@playwright/mcp"]}}}' |
            Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

        Register-MCPServers

        $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
        $mcpConfig.mcpServers.playwright.command | Should -Be 'C:\tools\playwright-mcp.exe'
    }

    It 'Register-MCPServers initializes mcpServers on an existing config that lacks it' {
        $env:COPILOT_HOME = Join-Path $TestDrive 'copilot'
        New-Item -Path $env:COPILOT_HOME -ItemType Directory -Force | Out-Null
        '{"someOtherSetting":true}' | Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

        Register-MCPServers

        $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
        $mcpConfig.someOtherSetting | Should -BeTrue
        $mcpConfig.mcpServers.'microsoft-learn'.url | Should -Be 'https://learn.microsoft.com/api/mcp'
    }

    Context 'Playwright MCP bundle' {
        BeforeEach {
            $script:savedForce = $script:ForceReinstall
            $script:ForceReinstall = $false
            $env:COPILOT_HOME = Join-Path $TestDrive ("copilot-" + [guid]::NewGuid().ToString('N'))
            $script:bundleVersion = Get-PlaywrightMcpBundleVersion
            $script:releaseDir = Join-Path $TestDrive ("release-" + [guid]::NewGuid().ToString('N'))
            $asset = "playwright-mcp-$script:bundleVersion.tgz"

            # A fake release: a tgz with cli.js and its .sha256, like the workflow publishes
            $src = Join-Path $TestDrive ("bundle-src-" + [guid]::NewGuid().ToString('N'))
            $cliDir = [System.IO.Path]::Combine($src, 'node_modules', '@playwright', 'mcp')
            New-Item -Path $cliDir -ItemType Directory -Force | Out-Null
            New-Item -Path $script:releaseDir -ItemType Directory -Force | Out-Null
            "console.log('fake playwright mcp')" | Set-Content -Path (Join-Path $cliDir 'cli.js')
            Invoke-NativeCommand (Get-TarCommand) -czf (Join-Path $script:releaseDir $asset) -C $src node_modules | Out-Null
            $hash = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $script:releaseDir $asset)).Hash.ToLowerInvariant()
            "$hash  $asset" | Set-Content -Path (Join-Path $script:releaseDir "$asset.sha256")
            $env:PLAYWRIGHT_MCP_BUNDLE_URL = $script:releaseDir

            $script:fakeNode = Join-Path $TestDrive 'node.exe'
            Mock Get-NodePath { $script:fakeNode }
        }

        AfterEach {
            $script:ForceReinstall = $script:savedForce
            Remove-Item Env:PLAYWRIGHT_MCP_BUNDLE_URL -ErrorAction SilentlyContinue
        }

        It 'pins an exact @playwright/mcp version' {
            $script:bundleVersion | Should -Match '^\d+\.\d+\.\d+$'
        }

        It 'installs the pinned release and skips it next time' {
            Install-PlaywrightMcpBundle

            Test-Path (Get-PlaywrightMcpCli) | Should -BeTrue
            (Get-Content -Raw -Path (Join-Path (Get-PlaywrightMcpDir) '.bundle-version')).Trim() | Should -Be $script:bundleVersion
            @(Get-ChildItem -Force -Path (Split-Path (Get-PlaywrightMcpDir))).Count | Should -Be 1

            Install-PlaywrightMcpBundle
            Should -Invoke Write-Info -ParameterFilter { $Message -like '*already installed*' } -Times 1 -Exactly
        }

        It 'warns and skips when the checksum does not match' {
            "0000  tampered" | Set-Content -Path (Join-Path $script:releaseDir "playwright-mcp-$script:bundleVersion.tgz.sha256")

            Install-PlaywrightMcpBundle

            Test-Path (Get-PlaywrightMcpDir) | Should -BeFalse
            Should -Invoke Write-Warn -ParameterFilter { $Message -like '*checksum*' } -Times 1 -Exactly
            $script:failedItems.Count | Should -Be 0
        }

        It 'warns and skips when the download fails' {
            $env:PLAYWRIGHT_MCP_BUNDLE_URL = Join-Path $TestDrive 'missing'

            Install-PlaywrightMcpBundle

            Test-Path (Get-PlaywrightMcpDir) | Should -BeFalse
            Should -Invoke Write-Warn -ParameterFilter { $Message -like "*Couldn't download*" } -Times 1 -Exactly
            $script:failedItems.Count | Should -Be 0
        }

        It 'registers the installed bundle with node and Edge' {
            Install-PlaywrightMcpBundle
            Register-MCPServers

            $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
            $mcpConfig.mcpServers.playwright.command | Should -Be $script:fakeNode
            @($mcpConfig.mcpServers.playwright.args) | Should -Be @((Get-PlaywrightMcpCli), '--browser=msedge')
        }

        It 'does not replace a custom Playwright entry with the bundle' {
            Install-PlaywrightMcpBundle
            '{"mcpServers":{"playwright":{"type":"local","command":"C:\\tools\\my-playwright.exe","args":[]}}}' |
                Out-File -FilePath (Join-Path $env:COPILOT_HOME 'mcp-config.json') -Encoding utf8

            Register-MCPServers

            $mcpConfig = Get-Content -Raw -Path (Join-Path $env:COPILOT_HOME 'mcp-config.json') | ConvertFrom-Json
            $mcpConfig.mcpServers.playwright.command | Should -Be 'C:\tools\my-playwright.exe'
        }
    }

    It 'Invoke-SafeInstall records native command failures' {
        Invoke-SafeInstall -Description 'example failure' -Action { & cmd /c exit 1 }

        $script:failedItems | Should -Contain 'example failure'
    }

    Context 'Install-WingetPackage' {
        BeforeEach {
            $script:savedForce = $script:ForceReinstall
            $script:ForceReinstall = $false
            $script:wingetLog = Join-Path $TestDrive "winget-$([guid]::NewGuid().ToString('N')).log"
            $script:wingetListExitCode = -1978335212 # NO_APPLICATIONS_FOUND
            $script:wingetInstallExitCode = 0
            function global:winget {
                Add-Content -Path $script:wingetLog -Value ($args -join ' ')
                if ($args[0] -eq 'list') {
                    $global:LASTEXITCODE = $script:wingetListExitCode
                }
                else {
                    $global:LASTEXITCODE = $script:wingetInstallExitCode
                }
            }
        }

        AfterEach {
            $script:ForceReinstall = $script:savedForce
            Remove-Variable -Name wingetLog, wingetListExitCode, wingetInstallExitCode -Scope Script -ErrorAction SilentlyContinue
        }

        It 'checks the winget source and installs a package that is not installed' {
            Install-WingetPackage -PackageId 'Microsoft.VisualStudioCode'

            @(Get-Content -Path $script:wingetLog) | Should -Be @(
                'list --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements'
                'install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements --silent'
            )
            Should -Invoke Write-Success -Times 1 -Exactly -ParameterFilter { $Message -eq 'Installed: Microsoft.VisualStudioCode' }
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'skips a package that is already installed' {
            $script:wingetListExitCode = 0

            Install-WingetPackage -PackageId 'Example.Package'

            @(Get-Content -Path $script:wingetLog) | Should -Not -Match '^install '
            Should -Invoke Write-Success -Times 1 -Exactly -ParameterFilter { $Message -eq 'Already installed: Example.Package' }
            Should -Invoke Write-Success -Times 0 -Exactly -ParameterFilter { $Message -like 'Installed:*' }
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'installs without checking when FORCE_REINSTALL is set' {
            $script:wingetListExitCode = 0
            $script:ForceReinstall = $true

            Install-WingetPackage -PackageId 'Example.Package'

            @(Get-Content -Path $script:wingetLog) | Should -Be @(
                'install --id Example.Package -e --source winget --accept-source-agreements --accept-package-agreements --silent'
            )
        }

        It 'falls back to installing when winget list returns an unexpected exit code' {
            $script:wingetListExitCode = -1978335138

            Install-WingetPackage -PackageId 'Example.Package'

            @(Get-Content -Path $script:wingetLog) | Should -Contain 'install --id Example.Package -e --source winget --accept-source-agreements --accept-package-agreements --silent'
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'reports "already installed" install exit codes as already installed, not failures' -ForEach @(
            @{ Code = -1978335135 }, # PACKAGE_ALREADY_INSTALLED
            @{ Code = -1978335189 }  # UPDATE_NOT_APPLICABLE
        ) {
            $script:wingetInstallExitCode = $Code

            Install-WingetPackage -PackageId 'Example.Package'

            Should -Invoke Write-Success -Times 1 -Exactly -ParameterFilter { $Message -eq 'Already installed: Example.Package' }
            Should -Invoke Write-Success -Times 0 -Exactly -ParameterFilter { $Message -like 'Installed:*' }
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'treats reboot-required exit code as success' {
            $script:wingetInstallExitCode = 3010

            Install-WingetPackage -PackageId 'Example.Package'

            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'records genuine winget failures' {
            $script:wingetInstallExitCode = -1978335231

            Install-WingetPackage -PackageId 'Example.Package'

            $script:failedItems | Should -Contain 'winget: Example.Package'
        }
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
            $script:savedIsAdmin = $script:IsAdmin
            $testId = [guid]::NewGuid().ToString('N')
            $script:TaskbarPolicyKey = "TestRegistry:\Policies\$testId\Explorer"
            $script:ForceReinstall = $false
            $script:IsAdmin = $true
            $script:adminSkippedItems = @()
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
            $script:IsAdmin = $script:savedIsAdmin
            $script:adminSkippedItems = @()
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

        It 'skips without touching the registry when not running as Administrator' {
            $script:IsAdmin = $false

            Set-TaskbarPins

            Test-Path $script:TaskbarPolicyKey | Should -BeFalse
            Test-Path $env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH | Should -BeFalse
            Should -Invoke Restart-Explorer -Times 0 -Exactly
            Should -Invoke Write-Warn -Times 1 -Exactly -ParameterFilter { $Message -like '*Terminal (Admin)*' }
            $script:adminSkippedItems | Should -Be @('taskbar pins')
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'checks for Administrator itself when run outside Invoke-Main' {
            $script:IsAdmin = $null
            Mock Test-IsAdmin { $false }

            Set-TaskbarPins

            Should -Invoke Test-IsAdmin -Times 1 -Exactly
            $script:adminSkippedItems | Should -Be @('taskbar pins')
        }

        It 'still reports already-configured pins when not running as Administrator' {
            Set-TaskbarPins
            $script:IsAdmin = $false

            Set-TaskbarPins

            Should -Invoke Write-Success -Times 1 -Exactly -ParameterFilter { $Message -eq 'Taskbar pins already configured' }
            $script:adminSkippedItems | Should -BeNullOrEmpty
        }
    }

    Context 'Administrator checks' {
        BeforeEach {
            $script:savedNonInteractive = $script:NonInteractive
            $script:savedIsAdmin = $script:IsAdmin
            $script:adminSkippedItems = @()
            Mock Read-Host { '' }
            function global:winget { 'v1.0.0'; $global:LASTEXITCODE = 0 }
        }

        AfterEach {
            $script:NonInteractive = $script:savedNonInteractive
            $script:IsAdmin = $script:savedIsAdmin
            $script:adminSkippedItems = @()
        }

        It 'warns prominently and pauses when not running as Administrator' {
            $script:NonInteractive = $false
            Mock Test-IsAdmin { $false }

            Test-Prerequisites | Should -BeTrue

            $script:IsAdmin | Should -BeFalse
            Should -Invoke Write-Warn -ParameterFilter { $Message -like '*NOT running as Administrator*' }
            Should -Invoke Read-Host -Times 1 -Exactly
        }

        It 'does not pause when NONINTERACTIVE is set' {
            $script:NonInteractive = $true
            Mock Test-IsAdmin { $false }

            Test-Prerequisites | Should -BeTrue

            Should -Invoke Write-Warn -ParameterFilter { $Message -like '*NOT running as Administrator*' }
            Should -Invoke Read-Host -Times 0 -Exactly
        }

        It 'does not warn or pause when running as Administrator' {
            $script:NonInteractive = $false
            Mock Test-IsAdmin { $true }

            Test-Prerequisites | Should -BeTrue

            $script:IsAdmin | Should -BeTrue
            Should -Invoke Write-Warn -Times 0 -Exactly -ParameterFilter { $Message -like '*NOT running as Administrator*' }
            Should -Invoke Read-Host -Times 0 -Exactly
        }

        It 'Write-Summary lists admin-skipped steps with rerun instructions' {
            $script:adminSkippedItems = @('taskbar pins')

            Write-Summary

            Should -Invoke Write-Warn -ParameterFilter { $Message -eq '  - taskbar pins' }
            Should -Invoke Write-Warn -ParameterFilter { $Message -like '*Terminal (Admin)*' }
        }
    }

    Context 'Install-DemoLauncher' {
        BeforeEach {
            $script:savedUserProfile = $env:USERPROFILE
            $script:savedCopilotHome = $env:COPILOT_HOME
            $env:USERPROFILE = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $env:COPILOT_HOME = $null
            $script:failedItems = @()
            $script:originUrl = 'https://github.com/octobooth-demos/repo-setup-scripts.git'
            Mock git { $global:LASTEXITCODE = 0; return $script:originUrl }
        }

        AfterEach {
            $env:USERPROFILE = $script:savedUserProfile
            $env:COPILOT_HOME = $script:savedCopilotHome
        }

        It 'writes the loader for a trusted checkout' {
            $launcherDir = Join-Path (Join-Path (Join-Path (Get-DemoLauncherRepoDir) '.github') 'extensions') 'demo-launcher'
            New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
            New-Item -Path $launcherDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $launcherDir 'extension.mjs') -Value '// launcher'

            Install-DemoLauncher

            Test-Path (Get-DemoLauncherLoaderPath) | Should -BeTrue
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'skips without failing when the checkout is missing' {
            Install-DemoLauncher

            Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
            $script:failedItems | Should -BeNullOrEmpty
        }

        It 'refuses a checkout whose origin is not the trusted repo' {
            New-Item -Path (Join-Path (Get-DemoLauncherRepoDir) '.git') -ItemType Directory -Force | Out-Null
            $script:originUrl = 'https://github.com/attacker/repo-setup-scripts.git'

            Install-DemoLauncher

            Test-Path (Get-DemoLauncherLoaderPath) | Should -BeFalse
            $script:failedItems | Should -HaveCount 1
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
            Mock Install-DemoLauncher { }
            Mock Initialize-Editors { }
            Mock Install-PlaywrightMcpBundle { }
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
