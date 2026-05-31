<#
.SYNOPSIS
    Sets up a Windows machine based on the needs for demoing at a booth.

.DESCRIPTION
    This script automates the installation and configuration of a complete
    development environment including VS Code, GitHub tooling, and related utilities.
    It handles software installation, extension setup, and environment configuration.

.EXAMPLE
    .\setup.ps1
    Installs and configures the complete development environment

.NOTES
    Requires:
    - Windows 10/11
    - winget package manager
    - Administrative privileges
    - Internet connection
#>

param(
    [switch]$SkipSignIn
)

# ----------------------------------------
# Constants
# ----------------------------------------

$script:configPath = Join-Path $PSScriptRoot "config.json"
$script:failedItems = @()
$script:ForceReinstall = $env:FORCE_REINSTALL -eq "true"

function Test-ShouldSkipInstalled { return -not $script:ForceReinstall }

# ----------------------------------------
# Logging Helpers
# ----------------------------------------

function Write-Info    { param([string]$Message) Write-Host "ℹ️  $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

function Invoke-SafeInstall {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    try {
        & $Action
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            $script:failedItems += $Description
            Write-Err "Failed: $Description"
        }
    }
    catch {
        $script:failedItems += $Description
        Write-Err "Failed: $Description - $_"
    }
}

function Write-Summary {
    if ($script:failedItems.Count -gt 0) {
        Write-Host ""
        Write-Warn "The following items failed to install:"
        foreach ($item in $script:failedItems) {
            Write-Warn "  - $item"
        }
        Write-Host ""
    }
}

# ----------------------------------------
# Bootstrap
# ----------------------------------------

function Test-Prerequisites {
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Success "Running with Administrator privileges"
    } else {
        Write-Warn "Not running with Administrator privileges. Some operations may fail."
        Write-Warn "Consider restarting with 'Run as Administrator'"
    }

    # Verify config.json exists
    if (-not (Test-Path $script:configPath)) {
        Write-Err "Config file not found: $script:configPath"
        return $false
    }
    Write-Success "config.json found"

    # Verify winget is available
    try {
        $wingetVersion = winget --version
        Write-Success "winget is available (version: $wingetVersion)"
    }
    catch {
        Write-Err "winget not found. Please install App Installer from Microsoft Store."
        return $false
    }

    return $true
}

function Import-Config {
    $script:config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
}

# ----------------------------------------
# Setup state (per-machine inputs)
# ----------------------------------------

function Get-SetupStatePath {
    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE ".copilot" }
    return (Join-Path $copilotHome "machine-setup-state.json")
}

# Reads the setup state into $script:AdoOrgValue and $script:AdoOrgMode.
# Tolerates missing or corrupt state.
function Get-SetupState {
    $script:AdoOrgValue = ""
    $script:AdoOrgMode = ""

    $statePath = Get-SetupStatePath
    if (-not (Test-Path $statePath)) { return }

    try {
        $state = Get-Content -Raw -Path $statePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "Setup state file at $statePath is not valid JSON; ignoring"
        return
    }

    if ($state.PSObject.Properties.Name -contains 'inputs' -and
        $state.inputs.PSObject.Properties.Name -contains 'azure_devops_org') {
        $entry = $state.inputs.azure_devops_org
        if ($entry.PSObject.Properties.Name -contains 'value') { $script:AdoOrgValue = [string]$entry.value }
        if ($entry.PSObject.Properties.Name -contains 'mode')  { $script:AdoOrgMode  = [string]$entry.mode  }
    }
}

# Atomically writes the current $script:AdoOrg* values to the state file.
function Save-SetupState {
    $statePath = Get-SetupStatePath
    $copilotHome = Split-Path -Parent $statePath
    if (-not (Test-Path $copilotHome)) {
        New-Item -Path $copilotHome -ItemType Directory -Force | Out-Null
    }

    $existing = [PSCustomObject]@{ inputs = [PSCustomObject]@{} }
    if (Test-Path $statePath) {
        try {
            $existing = Get-Content -Raw -Path $statePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -eq $existing.inputs) {
                $existing | Add-Member -NotePropertyName inputs -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
        } catch {
            $existing = [PSCustomObject]@{ inputs = [PSCustomObject]@{} }
        }
    }

    $entry = [PSCustomObject]@{ value = $script:AdoOrgValue; mode = $script:AdoOrgMode }
    $existing.inputs | Add-Member -NotePropertyName azure_devops_org -NotePropertyValue $entry -Force

    $tmp = "$statePath.tmp"
    try {
        $existing | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmp -Encoding UTF8 -Force
        # Validate before move
        $null = Get-Content -Raw -Path $tmp | ConvertFrom-Json
        Move-Item -Path $tmp -Destination $statePath -Force
    } catch {
        Write-Warn "Failed to persist setup state: $_"
        if (Test-Path $tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
}

# Prompts (when TTY) for per-machine inputs.
# Precedence: ADO_ORG env var > interactive prompt > cached value > skip.
function Read-SetupInputs {
    Get-SetupState

    # 1. Env var override (explicit empty = skip)
    if (Test-Path env:ADO_ORG) {
        $envVal = [string]$env:ADO_ORG
        $trimmed = $envVal.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) {
            $script:AdoOrgValue = ""
            $script:AdoOrgMode = "skip"
            Write-Info "ADO_ORG is empty in env; Azure DevOps MCP server will be skipped"
        } else {
            $script:AdoOrgValue = $trimmed
            $script:AdoOrgMode = "configured"
            Write-Info "Using Azure DevOps org from ADO_ORG env var: $($script:AdoOrgValue)"
        }
        Save-SetupState
        return
    }

    # 2. Interactive prompt (only when stdin isn't redirected)
    $interactive = $true
    try {
        if ([Console]::IsInputRedirected) { $interactive = $false }
    } catch {
        # Some hosts don't expose this; fall through to try Read-Host
    }

    if ($interactive) {
        if ($script:AdoOrgMode -eq 'configured' -and -not [string]::IsNullOrEmpty($script:AdoOrgValue)) {
            $hint = "[current: $($script:AdoOrgValue); Enter to keep, '-' to clear]"
        } else {
            $hint = "(leave blank to skip the Azure DevOps MCP server)"
        }

        $answer = $null
        try {
            $answer = Read-Host "Azure DevOps organization name $hint"
        } catch {
            Write-Warn "Could not prompt for input; treating Azure DevOps MCP server as skipped"
            $script:AdoOrgValue = ""
            $script:AdoOrgMode = "skip"
            Save-SetupState
            return
        }

        $trimmed = if ($null -eq $answer) { "" } else { $answer.Trim() }

        if ([string]::IsNullOrEmpty($trimmed)) {
            if ($script:AdoOrgMode -eq 'configured' -and -not [string]::IsNullOrEmpty($script:AdoOrgValue)) {
                Write-Info "Keeping cached Azure DevOps org: $($script:AdoOrgValue)"
            } else {
                $script:AdoOrgValue = ""
                $script:AdoOrgMode = "skip"
                Write-Info "Azure DevOps MCP server will be skipped"
            }
        } elseif ($trimmed -eq '-') {
            $script:AdoOrgValue = ""
            $script:AdoOrgMode = "skip"
            Write-Info "Cleared Azure DevOps org; the MCP server will be skipped"
        } else {
            if ($trimmed -match '[\s/:]') {
                Write-Warn "Azure DevOps org '$trimmed' contains unusual characters; accepting anyway"
            }
            $script:AdoOrgValue = $trimmed
            $script:AdoOrgMode = "configured"
            Write-Success "Azure DevOps org set to: $($script:AdoOrgValue)"
        }
        Save-SetupState
        return
    }

    # 3. Non-interactive: fall back to cached value if present
    if ($script:AdoOrgMode -eq 'configured' -and -not [string]::IsNullOrEmpty($script:AdoOrgValue)) {
        Write-Info "Non-interactive run; using cached Azure DevOps org: $($script:AdoOrgValue)"
    } elseif ($script:AdoOrgMode -eq 'skip') {
        Write-Info "Non-interactive run; cached state says skip Azure DevOps MCP server"
    } else {
        Write-Info "Non-interactive run with no cached value; Azure DevOps MCP server will be skipped"
        $script:AdoOrgValue = ""
        $script:AdoOrgMode = "skip"
    }
}

# ----------------------------------------
# Function Definitions
# ----------------------------------------

# Note: winget install is idempotent — no need to pre-check installed packages.
# Chrome is an exception: it may be pre-installed outside winget (e.g., by MDM
# or OEM image), so winget wouldn't detect it and would fail on conflict.
function Install-Packages {
    Write-Info "Installing packages via winget..."

    foreach ($package in $config.windows.packages) {
        # Chrome may be installed outside of winget (MDM, OEM, manual download, etc.)
        # so we check the filesystem to avoid install conflicts
        if ((Test-ShouldSkipInstalled) -and $package -eq "Google.Chrome" -and (Test-Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe")) {
            Write-Success "Already installed: $package (found in Program Files)"
            continue
        }

        Invoke-SafeInstall -Description "winget: $package" -Action {
            winget install --id $package -e --accept-source-agreements --accept-package-agreements --silent 2>&1
        }
    }

    # Refresh PATH so newly installed tools are available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    Write-Success "Package installation complete"
}

function Start-PostInstallApps {
    $apps = $config.windows.post_install_launch

    if ($null -eq $apps -or $apps.Count -eq 0) {
        return
    }

    Write-Info "Launching post-install apps..."

    foreach ($app in $apps) {
        Write-Info "Opening $app..."

        try {
            Start-Process $app
        }
        catch {
            Write-Warn "Could not open $app"
        }
    }
}

function Install-EditorExtensions {
    param(
        [string]$Name,
        [string]$Command
    )

    $commandExists = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $commandExists) {
        Write-Warn "$Name is not available in PATH. Can't install extensions."
        return
    }

    Write-Info "Installing $Name extensions..."

    $installedExts = @()
    if (Test-ShouldSkipInstalled) {
        $rawExts = & $Command --list-extensions 2>&1
        if ($rawExts) {
            $installedExts = $rawExts | ForEach-Object { $_.ToLower() }
        }
    }

    foreach ($ext in $config.shared.vs_code_extensions) {
        if ((Test-ShouldSkipInstalled) -and ($installedExts -contains $ext.ToLower())) {
            Write-Success "Already installed: $ext ($Name extension)"
            continue
        }

        # Attempt install; handle built-in conflicts gracefully
        # (e.g., Copilot is now bundled in VS Code/Insiders)
        try {
            $output = & $Command --install-extension $ext 2>&1
            if ($LASTEXITCODE -ne 0) {
                if ($output -match "built-in extension") {
                    Write-Success "Built-in: $ext ($Name), skipping..."
                } else {
                    $script:failedItems += "$Name extension: $ext"
                    Write-Err "Failed: $Name extension: $ext"
                }
            }
        }
        catch {
            $script:failedItems += "$Name extension: $ext"
            Write-Err "Failed: $Name extension: $ext - $_"
        }
    }
}

function Install-GHExtensions {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI is not available in PATH. Can't install extensions."
        return
    }

    Write-Info "Installing GitHub CLI extensions..."

    $installedExts = @()
    if (Test-ShouldSkipInstalled) {
        $rawList = gh extension list 2>&1
        if ($LASTEXITCODE -eq 0 -and $rawList) {
            $installedExts = $rawList | ForEach-Object { ($_ -split '\t')[1] } | Where-Object { $_ }
        }
    }

    foreach ($ext in $config.shared.gh_cli_extensions) {
        if ((Test-ShouldSkipInstalled) -and ($installedExts -contains $ext)) {
            Write-Success "Already installed: $ext (gh extension)"
            continue
        }

        Invoke-SafeInstall -Description "gh extension: $ext" -Action {
            gh extension install $ext 2>&1
        }
    }
}

function Set-VLCConfiguration {
    Write-Info "Configuring VLC settings..."
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"

    if ((Test-ShouldSkipInstalled) -and (Test-Path $vlcConfigPath)) {
        if (Select-String -Path $vlcConfigPath -Pattern "Setup-script-configured=true" -Quiet) {
            Write-Info "VLC settings already configured, skipping..."
            return
        }
    } else {
        New-Item -Path (Split-Path $vlcConfigPath) -ItemType Directory -Force | Out-Null
        New-Item -Path $vlcConfigPath -ItemType File -Force | Out-Null
    }

    Add-Content -Path $vlcConfigPath -Value "# Setup-script-configured=true"
    Add-Content -Path $vlcConfigPath -Value $config.shared.vlc_settings

    Write-Success "VLC settings configured - please restart VLC"
}

function Set-EditorTheme {
    param(
        [string]$Name,
        [string]$SettingsDir
    )

    Write-Info "Setting $Name theme..."
    $settingsPath = "$env:APPDATA\$SettingsDir\User\settings.json"

    if (-not (Test-Path $settingsPath)) {
        New-Item -Path (Split-Path $settingsPath) -ItemType Directory -Force | Out-Null
        "{}" | Out-File -FilePath $settingsPath -Encoding UTF8
    }

    $settings = Get-Content -Path $settingsPath | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName "workbench.colorTheme" -NotePropertyValue $config.shared.vscode_theme -Force
    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsPath -Force -Encoding UTF8
}

function Initialize-Editors {
    foreach ($editor in $config.windows.editors) {
        Install-EditorExtensions -Name $editor.name -Command $editor.command
        Set-EditorTheme -Name $editor.name -SettingsDir $editor.settings_dir
    }

    Write-Success "Editor configuration complete"
}

function Connect-GH {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI not found, skipping authentication."
        return
    }

    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Please authenticate with GitHub..."
        gh auth login --web
    }

    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Install-GHExtensions
        Write-Success "GitHub CLI extensions installed"
    } else {
        Write-Warn "GitHub CLI login required for extensions. Please run 'gh auth login' manually."
    }
}

function Invoke-SignInStep {
    param(
        [int]$Index,
        [int]$Total,
        [string]$Name,
        [scriptblock]$Launch,
        [string]$ManualHint
    )

    Write-Host ""
    Write-Host "[$Index/$Total] $Name" -ForegroundColor Cyan

    $launched = $false
    try {
        & $Launch
        $launched = $true
    } catch {
        Write-Warn "Could not launch $Name automatically: $_"
        if ($ManualHint) { Write-Warn "Manual step: $ManualHint" }
    }

    if ($launched -and $ManualHint) {
        Write-Info $ManualHint
    }

    [void](Read-Host "  -> Press Enter once you've signed in to $Name (or to skip)")
    Write-Success "$Name - confirmed"
}

function Start-SignInChecklist {
    if ($SkipSignIn) {
        Write-Info "Skipping sign-in checklist (-SkipSignIn was specified)."
        return
    }

    # Only run interactively (stdin not redirected); matches Read-SetupInputs convention.
    $interactive = $true
    try {
        if ([Console]::IsInputRedirected) { $interactive = $false }
    } catch {
        # Some hosts don't expose this; assume interactive and let Read-Host handle it.
    }
    if (-not $interactive) {
        Write-Info "Non-interactive session detected; skipping sign-in checklist."
        return
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "GitHub sign-in checklist"                 -ForegroundColor Cyan
    Write-Host "Sign in to each surface one at a time."    -ForegroundColor Cyan
    Write-Host "Order matters: the browser session is the source of truth others inherit." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if (-not [string]::IsNullOrWhiteSpace($Env:DEMO_GH_USER)) {
        Write-Info "Expected demo account: $Env:DEMO_GH_USER  (verify every surface signs in as this user)"
    } else {
        Write-Info "Tip: set DEMO_GH_USER to display the expected demo account here."
    }

    $total = 6

    # ---- Step 1: Web browser (establish the browser session first) ----
    Invoke-SignInStep -Index 1 -Total $total -Name "Web browser (github.com)" `
        -ManualHint "Open https://github.com/login and sign in as the demo account." `
        -Launch {
            Start-Process "https://github.com/login" | Out-Null
        }

    # ---- Step 2: GitHub CLI (skip if Connect-GH already authenticated) ----
    $ghAuthed = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
    }

    if ($ghAuthed) {
        Write-Host ""
        Write-Host "[2/$total] GitHub CLI (gh)" -ForegroundColor Cyan
        Write-Success "GitHub CLI - already authenticated, skipping"
    } else {
        Invoke-SignInStep -Index 2 -Total $total -Name "GitHub CLI (gh)" `
            -ManualHint "Run 'gh auth login --web' and complete the device flow in the browser." `
            -Launch {
                if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh not found on PATH" }
                gh auth login --web
                if ($LASTEXITCODE -ne 0) { throw "gh auth login exited with code $LASTEXITCODE" }
            }
    }

    # ---- Step 3: Copilot CLI (first-run device flow via /login) ----
    Invoke-SignInStep -Index 3 -Total $total -Name "Copilot CLI (copilot)" `
        -ManualHint "In the Copilot CLI window, run the '/login' slash command to authenticate." `
        -Launch {
            $copilotCmd = Get-Command copilot -ErrorAction SilentlyContinue
            if ($null -eq $copilotCmd) { throw "copilot not found on PATH" }
            # Launch in a persistent window so the user can run /login and see any errors.
            Start-Process powershell.exe -ArgumentList @('-NoExit', '-Command', "& '$($copilotCmd.Source)'") | Out-Null
        }

    # ---- Step 4: VS Code ----
    Invoke-SignInStep -Index 4 -Total $total -Name "VS Code" `
        -ManualHint "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left gear/avatar)." `
        -Launch {
            if (-not (Get-Command code -ErrorAction SilentlyContinue)) { throw "code (VS Code) not found on PATH" }
            & code --command "github.copilot.signIn" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "code exited with code $LASTEXITCODE" }
        }

    # ---- Step 5: VS Code Insiders ----
    Invoke-SignInStep -Index 5 -Total $total -Name "VS Code Insiders" `
        -ManualHint "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left gear/avatar)." `
        -Launch {
            if (-not (Get-Command code-insiders -ErrorAction SilentlyContinue)) { throw "code-insiders not found on PATH" }
            & code-insiders --command "github.copilot.signIn" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "code-insiders exited with code $LASTEXITCODE" }
        }

    # ---- Step 6: Copilot desktop app ----
    Invoke-SignInStep -Index 6 -Total $total -Name "Copilot app (desktop)" `
        -ManualHint "Launch the GitHub Copilot app from the Start Menu and sign in inside the app." `
        -Launch {
            $markerDirs = @(
                (Join-Path $env:LOCALAPPDATA "Programs\github-copilot"),
                (Join-Path $env:LOCALAPPDATA "Programs\GitHubCopilot"),
                (Join-Path $env:LOCALAPPDATA "Programs\GitHub Copilot")
            )

            $exe = $null

            # Prefer well-known executable names before falling back to a filtered search.
            $preferredNames = @('GitHub Copilot.exe', 'GitHubCopilot.exe', 'Copilot.exe')
            foreach ($dir in $markerDirs) {
                if (-not (Test-Path $dir)) { continue }
                foreach ($name in $preferredNames) {
                    $candidate = Join-Path $dir $name
                    if (Test-Path $candidate) { $exe = $candidate; break }
                }
                if ($exe) { break }
            }

            if ($null -eq $exe) {
                foreach ($dir in $markerDirs) {
                    if (-not (Test-Path $dir)) { continue }
                    $match = Get-ChildItem -Path $dir -Filter *.exe -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch '(?i)(unins|update|setup|crash|helper|elevate)' } |
                        Select-Object -First 1
                    if ($match) { $exe = $match.FullName; break }
                }
            }

            if ($null -eq $exe) {
                # Fall back to a Start Menu shortcut if the executable wasn't found.
                $startMenuDirs = @(
                    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
                    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs")
                )
                foreach ($sm in $startMenuDirs) {
                    if (-not (Test-Path $sm)) { continue }
                    $lnk = Get-ChildItem -Path $sm -Filter "*GitHub*Copilot*.lnk" -Recurse -File -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($lnk) { $exe = $lnk.FullName; break }
                }
            }

            if ($null -eq $exe) { throw "Copilot desktop app executable not found" }
            Start-Process $exe | Out-Null
        }

    Write-Host ""
    Write-Success "Sign-in checklist complete."
}

function Copy-Repos {
    $reposDir = Join-Path $env:USERPROFILE "repos"

    $repos = $config.shared.repos_to_clone
    if ($null -eq $repos -or $repos.Count -eq 0) {
        return
    }

    Write-Info "Cloning repos into $reposDir..."

    if (-not (Test-Path $reposDir)) {
        New-Item -Path $reposDir -ItemType Directory -Force | Out-Null
    }

    foreach ($repo in $repos) {
        $repoName = ($repo -split '/')[-1]
        $target = Join-Path $reposDir $repoName

        if ((Test-ShouldSkipInstalled) -and (Test-Path $target)) {
            Write-Info "$repoName already exists, skipping..."
        } else {
            Invoke-SafeInstall -Description "clone: $repo" -Action {
                gh repo clone $repo $target 2>&1
            }
        }
    }
}

function Install-PWAs {
    Write-Info "Opening required websites for PWA installation..."

    foreach ($site in $config.shared.pwa_sites) {
        Write-Info "Installing PWA for $($site.name)..."
        Start-Process "msedge" "--install-webapp=$($site.url)"
        Read-Host "Press Enter after you have added the PWA for $($site.name) in Edge"
    }
}

function Register-MCPServers {
    Write-Info "Registering MCP servers for Copilot CLI..."

    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE ".copilot" }
    $mcpConfigPath = Join-Path $copilotHome "mcp-config.json"

    # Create config directory if needed
    if (-not (Test-Path $copilotHome)) {
        New-Item -Path $copilotHome -ItemType Directory -Force | Out-Null
    }

    # Start with existing config or empty object
    if (Test-Path $mcpConfigPath) {
        $mcpConfig = Get-Content -Raw -Path $mcpConfigPath | ConvertFrom-Json
    } else {
        $mcpConfig = [PSCustomObject]@{ mcpServers = [PSCustomObject]@{} }
    }

    $placeholders = @()
    if ($config.shared.PSObject.Properties.Name -contains 'placeholders') {
        $placeholders = @($config.shared.placeholders)
    }

    foreach ($server in $config.shared.mcp_servers) {
        # Explicit skip: azure-devops requires a configured org
        if ($server.name -eq 'azure-devops' -and ($script:AdoOrgMode -ne 'configured' -or [string]::IsNullOrEmpty($script:AdoOrgValue))) {
            Write-Warn "Skipping MCP server 'azure-devops' (no Azure DevOps org configured — re-run setup to provide one or set ADO_ORG)"
            continue
        }

        # Build substituted args/url for this server
        $substArgs = @()
        if ($server.PSObject.Properties.Name -contains 'args' -and $server.args) {
            foreach ($a in $server.args) {
                if ($a -eq '<YOUR-ADO-ORG>' -and -not [string]::IsNullOrEmpty($script:AdoOrgValue)) {
                    $substArgs += $script:AdoOrgValue
                } else {
                    $substArgs += $a
                }
            }
        }
        $substUrl = $null
        if ($server.PSObject.Properties.Name -contains 'url' -and $server.url) {
            $substUrl = $server.url
        }

        # Defensive backstop: refuse to register if any placeholder slipped through
        $serverValues = @()
        $serverValues += $substArgs
        if ($null -ne $substUrl) { $serverValues += $substUrl }

        $hasPlaceholder = $false
        foreach ($value in $serverValues) {
            foreach ($placeholder in $placeholders) {
                if ($value -like "*$placeholder*") { $hasPlaceholder = $true; break }
            }
            if ($hasPlaceholder) { break }
        }

        if ($hasPlaceholder) {
            Write-Warn "Skipping MCP server '$($server.name)' (placeholder still present after substitution)"
            continue
        }

        $serverConfig = if ($server.type -eq "local") {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                command = $server.command
                args    = @($substArgs)
            }
        } else {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                url     = $substUrl
                headers = [PSCustomObject]@{}
            }
        }

        $mcpConfig.mcpServers | Add-Member -NotePropertyName $server.name -NotePropertyValue $serverConfig -Force
        Write-Success "Registered MCP server: $($server.name)"
    }

    $mcpConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $mcpConfigPath -Force -Encoding UTF8
    Write-Success "MCP servers written to $mcpConfigPath"
}

function Install-VisualStudio {
    if ($null -eq $config.windows.visual_studio) {
        return
    }

    $vs = $config.windows.visual_studio
    $edition = $vs.edition
    $url = $vs.bootstrapper_url
    $installPath = $vs.install_path

    if ((Test-ShouldSkipInstalled) -and $installPath -and (Test-Path $installPath)) {
        Write-Success "Already installed: Visual Studio $edition ($installPath)"
        return
    }

    Write-Info "Installing Visual Studio $edition from $url ..."

    $bootstrapper = Join-Path $env:TEMP "vs_$($edition.ToLower()).exe"

    try {
        Invoke-WebRequest -Uri $url -OutFile $bootstrapper -UseBasicParsing
    } catch {
        $script:failedItems += "Visual Studio: bootstrapper download failed"
        Write-Err "Failed to download Visual Studio bootstrapper: $_"
        return
    }

    # Build bootstrapper arguments: --add per workload, plus standard install flags
    $bootstrapperArgs = @()
    foreach ($workload in $vs.workloads) {
        $bootstrapperArgs += "--add"
        $bootstrapperArgs += $workload
    }
    if ($vs.include_recommended) { $bootstrapperArgs += "--includeRecommended" }
    $bootstrapperArgs += "--quiet"
    $bootstrapperArgs += "--wait"
    $bootstrapperArgs += "--norestart"
    $bootstrapperArgs += "--nocache"

    Write-Info "Running Visual Studio installer (this may take a while)..."
    try {
        $proc = Start-Process -FilePath $bootstrapper -ArgumentList $bootstrapperArgs -Wait -PassThru -NoNewWindow
        # Per Microsoft docs: 0 = success, 3010 = success but reboot required, 1602/1603 = user/install error
        if ($proc.ExitCode -eq 0) {
            Write-Success "Visual Studio $edition installed"
        } elseif ($proc.ExitCode -eq 3010) {
            Write-Success "Visual Studio $edition installed (reboot required)"
        } else {
            $script:failedItems += "Visual Studio: installer exit $($proc.ExitCode)"
            Write-Err "Visual Studio installer returned exit code $($proc.ExitCode)"
        }
    } catch {
        $script:failedItems += "Visual Studio: $_"
        Write-Err "Failed to run Visual Studio installer: $_"
    } finally {
        Remove-Item $bootstrapper -ErrorAction SilentlyContinue
    }
}

function Install-Aspire {
    if ((Test-ShouldSkipInstalled) -and (Get-Command aspire -ErrorAction SilentlyContinue)) {
        Write-Success "Already installed: aspire CLI"
        return
    }

    Write-Info "Installing Aspire CLI..."

    $tmp = Join-Path $env:TEMP "aspire-install.ps1"

    try {
        Invoke-WebRequest -Uri "https://aspire.dev/install.ps1" -OutFile $tmp -UseBasicParsing
    } catch {
        $script:failedItems += "aspire CLI: download failed"
        Write-Err "Failed to download Aspire installer: $_"
        return
    }

    Invoke-SafeInstall -Description "aspire CLI: install" -Action {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1
    }

    Remove-Item $tmp -ErrorAction SilentlyContinue

    # Refresh PATH from system + user, and make aspire available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $aspireBin = Join-Path $env:USERPROFILE ".aspire\bin"
    if ((Test-Path $aspireBin) -and ($env:Path -notlike "*$aspireBin*")) {
        $env:Path = "$aspireBin;$env:Path"
    }

    if (Get-Command aspire -ErrorAction SilentlyContinue) {
        Write-Success "Aspire CLI installed"
    } else {
        Write-Warn "Aspire installer ran but 'aspire' is not yet on PATH"
    }
}

function Install-NpmGlobals {
    $packages = $config.shared.npm_global_packages
    if ($null -eq $packages -or $packages.Count -eq 0) {
        return
    }

    # Refresh PATH so npm (installed by winget via OpenJS.NodeJS.LTS) is visible
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warn "npm not available on PATH; skipping global npm package install"
        $script:failedItems += "npm global packages: npm not on PATH"
        return
    }

    Write-Info "Installing npm packages globally..."
    foreach ($pkg in $packages) {
        Invoke-SafeInstall -Description "npm global: $pkg" -Action {
            npm install -g $pkg 2>&1
        }
    }
}

function Install-CopilotApp {
    if ($null -eq $config.windows.copilot_app) {
        return
    }

    $url = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        $config.windows.copilot_app.url_arm64
    } else {
        $config.windows.copilot_app.url_x64
    }

    # Common install locations the desktop app may use
    $installedMarkers = @(
        (Join-Path $env:LOCALAPPDATA "Programs\github-copilot"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHubCopilot"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHub Copilot")
    )
    if (Test-ShouldSkipInstalled) {
        foreach ($m in $installedMarkers) {
            if (Test-Path $m) {
                Write-Success "Already installed: GitHub Copilot app ($m)"
                return
            }
        }
    }

    Write-Info "Downloading GitHub Copilot app from $url ..."
    $installer = Join-Path $env:TEMP "GitHub-Copilot-setup.exe"

    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    } catch {
        $script:failedItems += "GitHub Copilot app: download failed"
        Write-Err "Failed to download GitHub Copilot app: $_"
        return
    }

    Write-Info "Running GitHub Copilot app installer (silent)..."
    try {
        $proc = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Warn "Silent install returned exit code $($proc.ExitCode); retrying interactively..."
            $proc2 = Start-Process -FilePath $installer -Wait -PassThru
            if ($proc2.ExitCode -ne 0) {
                $script:failedItems += "GitHub Copilot app: installer exit $($proc2.ExitCode)"
                Write-Err "GitHub Copilot app installer failed (exit $($proc2.ExitCode))"
            } else {
                Write-Success "GitHub Copilot app installed"
            }
        } else {
            Write-Success "GitHub Copilot app installed"
        }
    } catch {
        $script:failedItems += "GitHub Copilot app: $_"
        Write-Err "Failed to run GitHub Copilot app installer: $_"
    } finally {
        Remove-Item $installer -ErrorAction SilentlyContinue
    }
}

function New-DemoLoader {
    Write-Info "Creating demo loader script..."
    $demoScript = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'load-demos.ps1')

    $lines = @()
    $lines += "Write-Host 'Loading demo environment...' -ForegroundColor Blue"
    $lines += ""

    # Add demo sites
    $lines += "# Open demo sites"
    foreach ($url in $config.shared.demo_sites) {
        $lines += "Start-Process '$url'"
        $lines += "Start-Sleep -Seconds 1"
    }
    $lines += ""

    # Add editors from config
    $lines += "# Open editors"
    foreach ($editor in $config.windows.editors) {
        $lines += "& $($editor.command)"
    }
    $lines += ""

    # Add VLC
    $lines += "# Open VLC"
    $lines += 'Start-Process "vlc" -ArgumentList "$env:USERPROFILE\Videos"'
    $lines += ""
    $lines += "Write-Host 'Demo environment loaded!' -ForegroundColor Green"

    $lines -join "`n" | Out-File -FilePath $demoScript -Force -Encoding UTF8

    Write-Success "Created demo loader script at $demoScript"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting setup script - $(Get-Date)"    -ForegroundColor Cyan
Write-Host "Running from: $PSScriptRoot"             -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Bootstrap
if (-not (Test-Prerequisites)) { return }
Import-Config

# Prompt for per-machine inputs early
Read-SetupInputs

# Install packages
Install-Packages
Install-VisualStudio
Install-Aspire
Install-NpmGlobals
Set-VLCConfiguration

# Launch post-install apps
Start-PostInstallApps

# Setup environments
Connect-GH
Install-CopilotApp
Copy-Repos
Install-PWAs

# Install extensions and configure themes
Initialize-Editors

# Guided GitHub sign-in across all surfaces (browser first so others inherit the session)
Start-SignInChecklist

# Register MCP servers for Copilot CLI
Register-MCPServers

# Create demo loader script
New-DemoLoader

# Print summary and finish
Write-Summary
if ($script:failedItems.Count -gt 0) {
    Write-Warn "Script completed with $($script:failedItems.Count) failure(s)"
    exit 1
}
Write-Success "Script completed successfully"
