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

# Per-run install choices for the optional editors. Default to $true (so unattended
# runs install everything active, unchanged). Overridable via the INSTALL_NEOVIM /
# INSTALL_JETBRAINS env vars or the interactive prompt. Never persisted to state.
$script:InstallNeovim = $true
$script:InstallJetBrains = $true

function Test-ShouldSkipInstalled { return -not $script:ForceReinstall }

# Returns $true if a package entry is "active" (should be installed). An entry is
# considered disabled (returns $false) when it is null, whitespace-only, or its
# trimmed value begins with '#'. This lets config.json (which can't have real JSON
# comments) document and disable packages by prefixing their id with '# '.
function Test-ActivePackageEntry {
    param([string]$Entry)
    if ([string]::IsNullOrWhiteSpace($Entry)) { return $false }
    if ($Entry.TrimStart().StartsWith("#")) { return $false }
    return $true
}

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

# Reads the setup state into $script:AdoOrgValue / $script:AdoOrgMode and
# $script:VideoSubfolder. Tolerates missing or corrupt state.
function Get-SetupState {
    $script:AdoOrgValue = ""
    $script:AdoOrgMode = ""
    $script:VideoSubfolder = ""

    $statePath = Get-SetupStatePath
    if (-not (Test-Path $statePath)) { return }

    try {
        $state = Get-Content -Raw -Path $statePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "Setup state file at $statePath is not valid JSON; ignoring"
        return
    }

    if ($state.PSObject.Properties.Name -contains 'inputs') {
        if ($state.inputs.PSObject.Properties.Name -contains 'azure_devops_org') {
            $entry = $state.inputs.azure_devops_org
            if ($entry.PSObject.Properties.Name -contains 'value') { $script:AdoOrgValue = [string]$entry.value }
            if ($entry.PSObject.Properties.Name -contains 'mode')  { $script:AdoOrgMode  = [string]$entry.mode  }
        }
        if ($state.inputs.PSObject.Properties.Name -contains 'video_subfolder') {
            $videoEntry = $state.inputs.video_subfolder
            if ($videoEntry.PSObject.Properties.Name -contains 'value') {
                # Re-sanitize cached value so a hand-edited state file can't inject
                $script:VideoSubfolder = ConvertTo-SafeVideoSubfolder ([string]$videoEntry.value)
            }
        }
    }
}

# Atomically writes the current per-machine inputs to the state file.
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

    $videoEntry = [PSCustomObject]@{ value = $script:VideoSubfolder }
    $existing.inputs | Add-Member -NotePropertyName video_subfolder -NotePropertyValue $videoEntry -Force

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
function Read-SetupInputs {
    Get-SetupState
    Read-AdoOrgInput
    Read-VideoSubfolderInput
    Read-OptionalEditorChoices
}

# Resolves a yes/no choice. Precedence: env var override (truthy 1/true/yes/y/on,
# falsy 0/false/no/n/off) > interactive prompt (default yes) > non-interactive
# default yes (so piped/unattended runs install everything active, unchanged).
# Unrecognized env values or responses warn and fall back to yes.
function Read-YesNoChoice {
    param(
        [string]$Question,
        [string]$EnvVarName
    )

    if (-not [string]::IsNullOrEmpty($EnvVarName)) {
        $raw = [Environment]::GetEnvironmentVariable($EnvVarName)
        if ($null -ne $raw) {
            $norm = $raw.Trim().ToLowerInvariant()
            if ($norm -in @('1', 'true', 'yes', 'y', 'on'))  { return $true }
            if ($norm -in @('0', 'false', 'no', 'n', 'off')) { return $false }
            if (-not [string]::IsNullOrEmpty($norm)) {
                Write-Warn "Unrecognized value '$raw' for $EnvVarName; ignoring it."
            }
        }
    }

    $interactive = $true
    try {
        if ([Console]::IsInputRedirected) { $interactive = $false }
    } catch {
        # Some hosts don't expose this; assume interactive and let Read-Host handle it.
    }
    if (-not $interactive) { return $true }

    $answer = $null
    try {
        $answer = Read-Host "$Question [Y/n]"
    } catch {
        return $true
    }

    $trimmed = if ($null -eq $answer) { "" } else { $answer.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrEmpty($trimmed)) { return $true }
    if ($trimmed -in @('y', 'yes')) { return $true }
    if ($trimmed -in @('n', 'no'))  { return $false }
    Write-Warn "Unrecognized response '$answer'; defaulting to yes."
    return $true
}

# Asks whether to install the optional editors (Neovim, IDEs). The
# results gate the install loop, the Neovim Copilot plugin, and the matching
# sign-in checklist steps. Choices are per-run only and never persisted.
function Read-OptionalEditorChoices {
    $script:InstallNeovim = Read-YesNoChoice -Question "Install Neovim (and auto-configure its GitHub Copilot plugin)?" -EnvVarName "INSTALL_NEOVIM"
    if ($script:InstallNeovim) {
        Write-Info "Neovim will be installed."
    } else {
        Write-Info "Skipping Neovim (and its Copilot plugin)."
    }

    $script:InstallJetBrains = Read-YesNoChoice -Question "Install IDEs (PyCharm, Android Studio)?" -EnvVarName "INSTALL_JETBRAINS"
    if ($script:InstallJetBrains) {
        Write-Info "IDEs will be installed."
    } else {
        Write-Info "Skipping IDEs."
    }
}

# Prompts for the Azure DevOps organization.
# Precedence: ADO_ORG env var > interactive prompt > cached value > skip.
function Read-AdoOrgInput {
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

# Sanitizes a user-entered video subfolder. Returns "" (use ~/Videos root) for
# empty or unsafe input (path traversal, absolute/rooted paths, or quote chars).
function ConvertTo-SafeVideoSubfolder {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    $v = $Value.Trim()
    if ([string]::IsNullOrEmpty($v)) { return "" }
    # Normalize forward slashes to backslashes for uniform handling
    $v = $v -replace '/', '\'
    # Reject path traversal, drive-rooted (C:), UNC (\\), shell/PS metacharacters
    # ($ ` " expand inside the double-quoted loader string), or control chars
    if ($v -match '\.\.' -or $v -match '^[A-Za-z]:' -or $v.StartsWith('\\') -or
        $v.Contains('"') -or $v.Contains('$') -or $v.Contains('`') -or $v -match '[\x00-\x1f]') {
        Write-Warn "Video subfolder '$Value' looks unsafe (path traversal, absolute path, or special characters); using ~/Videos root"
        return ""
    }
    # Strip leading/trailing backslashes and collapse repeated separators
    $v = $v.Trim('\')
    $v = $v -replace '\\+', '\'
    return $v
}

# Returns a comma-separated list of immediate subdirectory names under $VideosRoot.
# Hint only; never required and never blocks.
function Get-VideoSubfolderHint {
    param([string]$VideosRoot)
    try {
        if (-not (Test-Path $VideosRoot)) { return "" }
        $dirs = Get-ChildItem -Path $VideosRoot -Directory -ErrorAction Stop | Select-Object -ExpandProperty Name
        if ($dirs) { return ($dirs -join ', ') }
    } catch {
        # Listing is a convenience only; ignore any failure
    }
    return ""
}

# Warns (but never fails) when the chosen subfolder is not yet present on disk.
function Test-VideoSubfolderPresent {
    param([string]$VideosRoot)
    if ([string]::IsNullOrEmpty($script:VideoSubfolder)) { return }
    $target = Join-Path $VideosRoot $script:VideoSubfolder
    if (-not (Test-Path $target)) {
        Write-Warn "Videos subfolder '$($script:VideoSubfolder)' not found yet under ~/Videos; make sure the videos are copied there before running the demo loader."
    }
}

# Prompts for the per-machine video subfolder under ~/Videos.
# Precedence: VIDEO_SUBFOLDER env var > interactive prompt > cached value > "" (root).
function Read-VideoSubfolderInput {
    $videosRoot = Join-Path $env:USERPROFILE "Videos"

    # 1. Env var override
    if (Test-Path env:VIDEO_SUBFOLDER) {
        $script:VideoSubfolder = ConvertTo-SafeVideoSubfolder ([string]$env:VIDEO_SUBFOLDER)
        if ([string]::IsNullOrEmpty($script:VideoSubfolder)) {
            Write-Info "VIDEO_SUBFOLDER is empty; demo loader will play ~/Videos directly"
        } else {
            Write-Info "Using video subfolder from VIDEO_SUBFOLDER env var: $($script:VideoSubfolder)"
        }
        Test-VideoSubfolderPresent $videosRoot
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
        if (-not [string]::IsNullOrEmpty($script:VideoSubfolder)) {
            $hint = "[current: $($script:VideoSubfolder); Enter to keep, '-' to clear to root]"
        } else {
            $hint = "(blank to play ~/Videos directly)"
        }
        $available = Get-VideoSubfolderHint $videosRoot
        if (-not [string]::IsNullOrEmpty($available)) {
            $hint = "$hint (available: $available)"
        }

        $answer = $null
        try {
            $answer = Read-Host "Video subfolder under ~/Videos to play $hint"
        } catch {
            Write-Warn "Could not prompt for video subfolder; demo loader will play ~/Videos"
            $script:VideoSubfolder = ""
            Save-SetupState
            return
        }

        $trimmed = if ($null -eq $answer) { "" } else { $answer.Trim() }

        if ([string]::IsNullOrEmpty($trimmed)) {
            if (-not [string]::IsNullOrEmpty($script:VideoSubfolder)) {
                Write-Info "Keeping cached video subfolder: $($script:VideoSubfolder)"
            } else {
                $script:VideoSubfolder = ""
                Write-Info "Demo loader will play ~/Videos directly"
            }
        } elseif ($trimmed -eq '-') {
            $script:VideoSubfolder = ""
            Write-Info "Cleared video subfolder; demo loader will play ~/Videos directly"
        } else {
            $script:VideoSubfolder = ConvertTo-SafeVideoSubfolder $trimmed
            if ([string]::IsNullOrEmpty($script:VideoSubfolder)) {
                Write-Info "Demo loader will play ~/Videos directly"
            } else {
                Write-Success "Video subfolder set to: $($script:VideoSubfolder)"
            }
        }
        Test-VideoSubfolderPresent $videosRoot
        Save-SetupState
        return
    }

    # 3. Non-interactive: fall back to cached value if present
    if (-not [string]::IsNullOrEmpty($script:VideoSubfolder)) {
        Write-Info "Non-interactive run; using cached video subfolder: $($script:VideoSubfolder)"
    } else {
        Write-Info "Non-interactive run; demo loader will play ~/Videos directly"
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
        # Skip disabled/documentation entries (those prefixed with '# ' in config.json).
        if (-not (Test-ActivePackageEntry $package)) {
            Write-Info "Skipping disabled package: $package"
            continue
        }

        # Honor the interactive install choices for the optional editors.
        $pkgTrim = $package.Trim()
        if ((-not $script:InstallNeovim) -and $pkgTrim -eq "Neovim.Neovim") {
            Write-Info "Skipping Neovim (not selected): $package"
            continue
        }
        if ((-not $script:InstallJetBrains) -and (Test-IdeEntry $package)) {
            Write-Info "Skipping IDE (not selected): $package"
            continue
        }

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

    # Defensive fallback: Git for Windows installs to C:\Program Files\Git\cmd.
    # If the PATH refresh above didn't surface it, add it so git-dependent steps
    # (gh git protocol, gh extensions) can find git.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $gitCmd = "C:\Program Files\Git\cmd"
        if (Test-Path (Join-Path $gitCmd "git.exe")) {
            $env:Path = "$gitCmd;$env:Path"
            Write-Info "Added $gitCmd to PATH for this session"
        }
        else {
            Write-Warn "git not found on PATH after install; git-dependent steps may fail"
        }
    }

    Write-Success "Package installation complete"
}

function Install-NeovimCopilot {
    # Installs the official github/copilot.vim plugin into Neovim's native package
    # start path so it loads automatically. Idempotent and never fatal.
    if (-not $script:InstallNeovim) {
        Write-Info "Neovim was not selected; skipping Copilot plugin setup."
        return
    }

    Write-Info "Setting up Neovim GitHub Copilot plugin..."

    if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) {
        Write-Info "Neovim (nvim) not found on PATH; skipping Copilot plugin setup."
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn "git not found on PATH; cannot install Neovim Copilot plugin. Skipping."
        return
    }

    $target = Join-Path $env:LOCALAPPDATA "nvim-data\site\pack\github\start\copilot.vim"
    $parent = Split-Path -Parent $target

    if (-not (Test-Path $parent)) {
        try {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        } catch {
            Write-Warn "Could not create Neovim plugin directory '$parent': $_"
            $script:failedItems += "Neovim Copilot plugin (mkdir)"
            return
        }
    }

    if (-not (Test-Path $target)) {
        Invoke-SafeInstall -Description "Neovim Copilot plugin (clone)" -Action {
            git clone --depth 1 https://github.com/github/copilot.vim $target 2>&1
        }
        if (-not (Test-Path (Join-Path $target ".git"))) {
            Write-Warn "Neovim Copilot plugin clone did not complete; skipping. You can retry later."
            return
        }
    }
    elseif (Test-Path (Join-Path $target ".git")) {
        if (Test-ShouldSkipInstalled) {
            # Already a repo and we're not forcing; refresh best-effort.
            try {
                git -C $target pull --ff-only 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Warn "Could not update Neovim Copilot plugin (git pull failed); continuing." }
            } catch {
                Write-Warn "Could not update Neovim Copilot plugin: $_"
            }
        } else {
            Invoke-SafeInstall -Description "Neovim Copilot plugin (pull)" -Action {
                git -C $target pull --ff-only 2>&1
            }
        }
    }
    else {
        Write-Warn "Neovim Copilot plugin path exists but is not a git repo; leaving it untouched: $target"
        return
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warn "Node.js (node) not found on PATH; Neovim Copilot may not work until Node is available."
    }

    Write-Success "Neovim GitHub Copilot plugin ready"
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
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Warn "git not found on PATH; gh extensions that shell out to git may fail. Install Git for Windows."
        }
        Install-GHExtensions
        Write-Success "GitHub CLI extensions installed"
    } else {
        Write-Warn "GitHub CLI login required for extensions. Please run 'gh auth login' manually."
    }
}

# Returns the install-marker directories the GitHub Copilot desktop app may use.
# Shared by Install-CopilotApp and the sign-in checklist so the two stay in sync.
function Get-CopilotAppMarkerDir {
    @(
        (Join-Path $env:LOCALAPPDATA "Programs\github-copilot"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHubCopilot"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHub Copilot")
    )
}

function Get-IdeDisplayName {
    param([string]$Id)
    # Map IDE package ids to friendly display names. Covers JetBrains winget ids
    # (with the 'JetBrains.' prefix stripped) plus Android Studio. Unknown ids fall
    # back to the raw id so we never crash.
    $trimmed = $Id.Trim()
    if ($trimmed -eq 'Google.AndroidStudio') { return 'Android Studio' }
    $map = @{
        'IntelliJIDEA.Ultimate'  = 'IntelliJ IDEA Ultimate'
        'IntelliJIDEA.Community' = 'IntelliJ IDEA Community'
        'PyCharm.Professional'   = 'PyCharm Professional'
        'PyCharm.Community'      = 'PyCharm Community'
        'Rider'                  = 'Rider'
        'WebStorm'               = 'WebStorm'
        'GoLand'                 = 'GoLand'
        'CLion'                  = 'CLion'
        'PhpStorm'               = 'PhpStorm'
        'RubyMine'               = 'RubyMine'
        'DataGrip'               = 'DataGrip'
        'RustRover'              = 'RustRover'
    }
    $suffix = $trimmed -replace '^JetBrains\.', ''
    if ($map.ContainsKey($suffix)) { return $map[$suffix] }
    return $Id
}

# Returns $true if a package entry is a JetBrains IDE (a 'JetBrains.*' id that is
# not JetBrains Toolbox).
function Test-JetBrainsIdeEntry {
    param([string]$Entry)
    if ([string]::IsNullOrWhiteSpace($Entry)) { return $false }
    $trimmed = $Entry.Trim()
    if ($trimmed -notlike 'JetBrains.*') { return $false }
    if ($trimmed -like 'JetBrains.Toolbox*') { return $false }
    return $true
}

# Returns $true if a package entry is an IDE we gate behind the "Install IDEs"
# prompt: any JetBrains IDE plus Android Studio (a Google package, not JetBrains).
# Shared by the install-loop gate and the checklist derivation so commenting out
# an IDE removes both its install and its sign-in step.
function Test-IdeEntry {
    param([string]$Entry)
    if (Test-JetBrainsIdeEntry $Entry) { return $true }
    if ([string]::IsNullOrWhiteSpace($Entry)) { return $false }
    if ($Entry.Trim() -eq 'Google.AndroidStudio') { return $true }
    return $false
}

function Get-ActiveIdeDisplayNames {
    # Returns friendly display names for the ACTIVE IDE entries in
    # config.windows.packages (JetBrains IDEs plus Android Studio), excluding
    # JetBrains Toolbox. Commenting out an IDE in config (prefixing '# ')
    # therefore also removes its checklist step.
    $names = @()
    foreach ($pkg in $config.windows.packages) {
        if (-not (Test-ActivePackageEntry $pkg)) { continue }
        if (-not (Test-IdeEntry $pkg)) { continue }
        $names += (Get-IdeDisplayName $pkg)
    }
    return $names
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

    if ($null -eq $Launch) {
        # Manual-only step: nothing to launch, just surface the instructions.
        if ($ManualHint) { Write-Info $ManualHint }
    } else {
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

    # Build an ordered list of step descriptors, then iterate so [index/total]
    # is always correct as steps are added or removed.
    $steps = @()

    # ---- Web browser (establish the browser session first) ----
    $steps += @{
        Name       = "Web browser (github.com)"
        ManualHint = "Open https://github.com/login and sign in as the demo account."
        Launch     = {
            Start-Process "https://github.com/login" | Out-Null
        }
    }

    # ---- GitHub CLI (skip if Connect-GH already authenticated) ----
    $ghAuthed = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
    }
    $steps += @{
        Name        = "GitHub CLI (gh)"
        ManualHint  = "Run 'gh auth login --web' and complete the device flow in the browser."
        Launch      = {
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh not found on PATH" }
            gh auth login --web
            if ($LASTEXITCODE -ne 0) { throw "gh auth login exited with code $LASTEXITCODE" }
        }
        SkipIf      = $ghAuthed
        SkipMessage = "GitHub CLI - already authenticated, skipping"
    }

    # ---- Copilot CLI (first-run device flow via /login) ----
    $steps += @{
        Name       = "Copilot CLI (copilot)"
        ManualHint = "In the Copilot CLI window, run the '/login' slash command to authenticate."
        Launch     = {
            $copilotCmd = Get-Command copilot -ErrorAction SilentlyContinue
            if ($null -eq $copilotCmd) { throw "copilot not found on PATH" }
            # Launch in a persistent window so the user can run /login and see any errors.
            Start-Process powershell.exe -ArgumentList @('-NoExit', '-Command', "& '$($copilotCmd.Source)'") | Out-Null
        }
    }

    # ---- VS Code ----
    $steps += @{
        Name       = "VS Code"
        ManualHint = "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left gear/avatar)."
        Launch     = {
            if (-not (Get-Command code -ErrorAction SilentlyContinue)) { throw "code (VS Code) not found on PATH" }
            & code --command "github.copilot.signIn" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "code exited with code $LASTEXITCODE" }
        }
    }

    # ---- VS Code Insiders ----
    $steps += @{
        Name       = "VS Code Insiders"
        ManualHint = "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left gear/avatar)."
        Launch     = {
            if (-not (Get-Command code-insiders -ErrorAction SilentlyContinue)) { throw "code-insiders not found on PATH" }
            & code-insiders --command "github.copilot.signIn" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "code-insiders exited with code $LASTEXITCODE" }
        }
    }

    # ---- Neovim (only when selected and nvim is installed) ----
    if ($script:InstallNeovim -and (Get-Command nvim -ErrorAction SilentlyContinue)) {
        $steps += @{
            Name       = "Neovim"
            ManualHint = "Inside Neovim, run ':Copilot setup' to authenticate. If you signed in to the Copilot CLI above, Neovim may already be signed in via the shared token at %LOCALAPPDATA%\github-copilot."
            Launch     = {
                if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) { throw "nvim not found on PATH" }
                # Prefer Windows Terminal; fall back to a persistent PowerShell window.
                if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
                    Start-Process wt.exe -ArgumentList 'nvim', '+":Copilot setup"' | Out-Null
                } else {
                    Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', 'nvim +":Copilot setup"' | Out-Null
                }
            }
        }
    }

    # ---- IDEs (dynamic from active config entries; manual-hint only) ----
    if ($script:InstallJetBrains) {
        foreach ($jbName in (Get-ActiveIdeDisplayNames)) {
            $steps += @{
                Name       = $jbName
                ManualHint = "Open $jbName, install the GitHub Copilot plugin (Settings/Preferences > Plugins > Marketplace > search 'GitHub Copilot'), then sign in to Copilot inside the IDE."
                Launch     = $null
            }
        }
    }

    # ---- Copilot desktop app (keep last) ----
    $steps += @{
        Name       = "Copilot app (desktop)"
        ManualHint = "Launch the GitHub Copilot app from the Start Menu and sign in inside the app."
        Launch     = {
            $markerDirs = Get-CopilotAppMarkerDir

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
    }

    $total = $steps.Count
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step  = $steps[$i]
        $index = $i + 1

        if ($step.ContainsKey('SkipIf') -and $step.SkipIf) {
            Write-Host ""
            Write-Host "[$index/$total] $($step.Name)" -ForegroundColor Cyan
            Write-Success $step.SkipMessage
            continue
        }

        $launch = $null
        if ($step.ContainsKey('Launch')) { $launch = $step.Launch }
        Invoke-SignInStep -Index $index -Total $total -Name $step.Name -Launch $launch -ManualHint $step.ManualHint
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
    $installedMarkers = Get-CopilotAppMarkerDir
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
    if (-not [string]::IsNullOrEmpty($script:VideoSubfolder)) {
        $lines += 'Start-Process "vlc" -ArgumentList "$env:USERPROFILE\Videos\' + $script:VideoSubfolder + '"'
    } else {
        $lines += 'Start-Process "vlc" -ArgumentList "$env:USERPROFILE\Videos"'
    }
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
Install-NeovimCopilot
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

# Register MCP servers for Copilot CLI
Register-MCPServers

# Guided GitHub sign-in across all surfaces (browser first so others inherit the session)
Start-SignInChecklist

# Visual Studio Enterprise install is long and blocking, so run it last (after the
# quick interactive steps) so the user can walk away while it completes.
Install-VisualStudio

# Create demo loader script
New-DemoLoader

# Print summary and finish
Write-Summary
if ($script:failedItems.Count -gt 0) {
    Write-Warn "Script completed with $($script:failedItems.Count) failure(s)"
    exit 1
}
Write-Success "Script completed successfully"
