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
    - Administrative privileges (Terminal (Admin)). Without them, setup warns,
      pauses, and skips steps that need elevation, such as the taskbar pins.
    - Internet connection

    Reruns skip steps that are already done, including winget packages that are
    already installed. Set $env:FORCE_REINSTALL = "true" to redo them.

.PARAMETER Ref
    Checks out $HOME\repos\repo-setup-scripts at a release tag: the major
    the booth uses (v1) or a full version (v1.2.0). Also read from
    $env:BOOTH_RELEASE. Without one, a checkout pinned to a release (detached
    HEAD) switches back to its default branch and pulls it (untested main),
    while a checkout already on a branch is left as is.

.EXAMPLE
    .\setup.ps1 -Ref v1
    Sets up the machine with the v1 release of the Demo Launcher
#>

param([string]$Ref)

# ----------------------------------------
# Constants
# ----------------------------------------

$script:configPath = Join-Path $PSScriptRoot "config.json"
$script:failedItems = @()
$script:adminSkippedItems = @()
$script:IsAdmin = $null # Set by Test-Prerequisites, or on first use by an admin-only step
$script:ForceReinstall = $env:FORCE_REINSTALL -eq "true"
$script:NonInteractive = $env:NONINTERACTIVE -eq "true"

# winget (and the installers it invokes) return non-zero exit codes for
# conditions that are not actual failures. Treat these as success so the
# script doesn't report false failures.
$script:WingetSuccessExitCodes = @(
    0,           # Success
    -1978335189, # 0x8A15002B APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already up to date)
    -1978335135, # 0x8A150061 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
    3010,        # ERROR_SUCCESS_REBOOT_REQUIRED (installer succeeded, reboot needed)
    1641         # ERROR_SUCCESS_REBOOT_INITIATED
)

# Install exit codes that mean the package was already there, so nothing was installed.
$script:WingetAlreadyInstalledExitCodes = @(
    -1978335189, # 0x8A15002B APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
    -1978335135  # 0x8A150061 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
)

# `winget list` exit code when no installed package matches the query.
$script:WingetNoPackageFoundExitCode = -1978335212 # 0x8A150014 APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND

function Test-ShouldSkipInstalled { return -not $script:ForceReinstall }

# Windows 11 has no API to pin apps directly; the supported route is a taskbar
# layout XML referenced by the StartLayoutFile policy, which Explorer reads at start.
$script:TaskbarPolicyKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"

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

# Runs a native command and returns its output as plain strings: stdout and stderr, or
# with -StdoutOnly just stdout. Windows PowerShell 5.1 turns redirected stderr, such as
# git's normal progress, into red NativeCommandError records even when the command
# succeeded, so callers must decide success from $LASTEXITCODE, which this leaves set.
function Invoke-NativeCommandLine {
    param(
        [object[]]$CommandLine,
        [switch]$StdoutOnly
    )
    $command = $CommandLine[0]
    # Assigned rather than returned from an if, which would unwrap a lone argument into a
    # string that splatting then passes one character at a time
    $arguments = @()
    if ($CommandLine.Count -gt 1) { $arguments = @($CommandLine[1..($CommandLine.Count - 1)]) }
    # With 'Stop', 5.1 would throw on the first stderr line instead of returning it
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $command @arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                if ($StdoutOnly) { Write-Verbose "$command (stderr): $($_.Exception.Message)" } else { $_.Exception.Message }
            } else {
                "$_"
            }
        }
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
}

# For output that's shown or searched for messages (Invoke-NativeCommand git -C $dir pull).
# Uses $args rather than a param block so flags like -C pass straight through.
function Invoke-NativeCommand {
    Invoke-NativeCommandLine -CommandLine $args
}

# For output that's parsed as a value (a URL, branch, or list), so warnings or trace
# lines on stderr (CRLF, safe.directory, GIT_TRACE) can't end up in it
function Get-NativeCommandOutput {
    Invoke-NativeCommandLine -CommandLine $args -StdoutOnly
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
    if ($script:adminSkippedItems.Count -gt 0) {
        Write-Host ""
        Write-Warn "Skipped because setup wasn't run as Administrator:"
        foreach ($item in $script:adminSkippedItems) {
            Write-Warn "  - $item"
        }
        Write-Warn "To finish them, open Terminal (Admin) and run .\setup.ps1 again."
        Write-Host ""
    }
}

# ----------------------------------------
# Bootstrap
# ----------------------------------------

function Test-IsAdmin {
    $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-NotAdminWarning {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Warn "setup.ps1 is NOT running as Administrator."
    Write-Warn "Setup will skip the taskbar pins, and some installs may fail or ask for approval."
    Write-Warn "To run everything: close this window, right-click Start, choose"
    Write-Warn "Terminal (Admin), approve the prompt, and run .\setup.ps1 again."
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    if (-not $script:NonInteractive) {
        Read-Host "Press Enter to continue without Administrator, or Ctrl+C to stop" | Out-Null
    }
}

function Test-Prerequisites {
    $script:IsAdmin = Test-IsAdmin
    if ($script:IsAdmin) {
        Write-Success "Running with Administrator privileges"
    } else {
        Write-NotAdminWarning
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
# Function Definitions
# ----------------------------------------

# Returns $true when installed, $false when not found, and $null when winget
# can't tell (any other exit code), so the caller falls back to installing.
# Only the exit code is used: winget truncates long IDs in its table output.
function Test-WingetPackageInstalled {
    param([string]$PackageId)

    try {
        winget list --id $PackageId -e --source winget --accept-source-agreements 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    }
    catch {
        return $null
    }

    if ($exitCode -eq 0) { return $true }
    if ($exitCode -eq $script:WingetNoPackageFoundExitCode) { return $false }
    return $null
}

function Install-WingetPackage {
    param([string]$PackageId)

    $description = "winget: $PackageId"

    if ((Test-ShouldSkipInstalled) -and ((Test-WingetPackageInstalled -PackageId $PackageId) -eq $true)) {
        Write-Success "Already installed: $PackageId"
        return
    }

    try {
        # Use the winget source to avoid unrelated Microsoft Store certificate failures.
        $output = Invoke-NativeCommand winget install --id $PackageId -e --source winget --accept-source-agreements --accept-package-agreements --silent
        $exitCode = $LASTEXITCODE

        if ($script:WingetAlreadyInstalledExitCodes -contains $exitCode) {
            Write-Success "Already installed: $PackageId"
        }
        elseif ($script:WingetSuccessExitCodes -contains $exitCode) {
            Write-Success "Installed: $PackageId"
        }
        else {
            $script:failedItems += $description
            Write-Err "Failed: $description (exit code: $exitCode)"
            if ($output) { Write-Host ($output | Out-String).TrimEnd() }
        }
    }
    catch {
        $script:failedItems += $description
        Write-Err "Failed: $description - $_"
    }
}

function Install-Packages {
    Write-Info "Installing packages via winget (already-installed packages are skipped)..."

    foreach ($package in $config.windows.packages) {
        Install-WingetPackage -PackageId $package
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

function Get-TaskbarLayoutPath {
    if ($env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH) {
        return $env:SETUP_SCRIPT_TASKBAR_LAYOUT_PATH
    }
    return (Join-Path $env:LOCALAPPDATA "machine-setup\TaskbarLayout.xml")
}

function New-TaskbarLayoutXml {
    param([object[]]$Pins)

    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<LayoutModificationTemplate'
        '    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"'
        '    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"'
        '    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"'
        '    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"'
        '    Version="1">'
        '  <CustomTaskbarLayoutCollection>'
        '    <defaultlayout:TaskbarLayout>'
        '      <taskbar:TaskbarPinList>'
    )
    foreach ($pin in $Pins) {
        $id = [System.Security.SecurityElement]::Escape($pin.app_id)
        # Packaged (UWP/MSIX) apps have an AUMID of the form "<PackageFamilyName>!<AppId>".
        if ($pin.app_id -like "*!*") {
            $lines += "        <taskbar:UWA AppUserModelID=`"$id`" />"
        }
        else {
            $lines += "        <taskbar:DesktopApp DesktopApplicationID=`"$id`" />"
        }
    }
    $lines += @(
        '      </taskbar:TaskbarPinList>'
        '    </defaultlayout:TaskbarLayout>'
        '  </CustomTaskbarLayoutCollection>'
        '</LayoutModificationTemplate>'
    )
    return ($lines -join "`r`n")
}

function Restart-Explorer {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

function Set-TaskbarPins {
    $pins = @($config.windows.taskbar_pins | Where-Object { $_ })
    if ($pins.Count -eq 0) {
        return
    }

    Write-Info "Pinning apps to the taskbar..."

    if (Get-Command Get-StartApps -ErrorAction SilentlyContinue) {
        $installedIds = @(Get-StartApps | ForEach-Object { $_.AppID })
        foreach ($pin in $pins) {
            if ($installedIds -notcontains $pin.app_id) {
                Write-Warn "$($pin.name) ($($pin.app_id)) isn't installed yet; its pin appears once it is"
            }
        }
    }

    $layoutPath = Get-TaskbarLayoutPath
    $layoutXml = New-TaskbarLayoutXml -Pins $pins

    $existingXml = if (Test-Path $layoutPath) { (Get-Content -Raw -Path $layoutPath).TrimEnd() } else { $null }
    $policy = Get-ItemProperty -Path $script:TaskbarPolicyKey -ErrorAction SilentlyContinue
    $alreadyApplied = ($existingXml -eq $layoutXml) -and
        ($policy.StartLayoutFile -eq $layoutPath) -and
        ($policy.LockedStartLayout -eq 1)

    if ($alreadyApplied -and (Test-ShouldSkipInstalled)) {
        Write-Success "Taskbar pins already configured"
        return
    }

    # The StartLayoutFile policy lives under HKCU\Software\Policies, which only
    # an elevated process can write.
    if ($null -eq $script:IsAdmin) { $script:IsAdmin = Test-IsAdmin }
    if (-not $script:IsAdmin) {
        $script:adminSkippedItems += "taskbar pins"
        Write-Warn "Skipping taskbar pins: they need Administrator. Open Terminal (Admin) and run .\setup.ps1 again."
        return
    }

    try {
        New-Item -Path (Split-Path $layoutPath) -ItemType Directory -Force | Out-Null
        $layoutXml | Out-File -FilePath $layoutPath -Force -Encoding UTF8

        if (-not (Test-Path $script:TaskbarPolicyKey)) {
            New-Item -Path $script:TaskbarPolicyKey -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $script:TaskbarPolicyKey -Name StartLayoutFile -Value $layoutPath -Type ExpandString -ErrorAction Stop
        Set-ItemProperty -Path $script:TaskbarPolicyKey -Name LockedStartLayout -Value 1 -Type DWord -ErrorAction Stop

        # Explorer only reads the layout policy when it starts.
        Restart-Explorer
        Write-Success "Taskbar pins configured from $layoutPath"
    }
    catch {
        $script:failedItems += "taskbar pins"
        Write-Err "Failed: taskbar pins - $_"
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
        $rawExts = Get-NativeCommandOutput $Command --list-extensions
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
            $output = Invoke-NativeCommand $Command --install-extension $ext
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

function Install-GHExtension {
    param([string]$Extension)

    $description = "gh extension: $Extension"
    try {
        $output = Invoke-NativeCommand gh extension install $Extension
        $exitCode = $LASTEXITCODE
        $text = ($output | Out-String)

        if ($exitCode -eq 0) {
            Write-Success "Installed: $Extension (gh extension)"
        }
        elseif ($text -match 'already installed' -or $text -match 'already exists' -or $text -match 'there is already an installed extension') {
            Write-Success "Already installed: $Extension (gh extension)"
        }
        elseif ($text -match 'unsupported for') {
            # Precompiled extensions may not ship a binary for every architecture
            # (e.g. windows-arm64). This isn't fixable here, so skip rather than fail.
            Write-Warn "Skipped: $Extension (gh extension) - not supported on this architecture"
        }
        else {
            $script:failedItems += $description
            Write-Err "Failed: $description (exit code: $exitCode)"
            if ($text.Trim()) { Write-Host $text.TrimEnd() }
        }
    }
    catch {
        $script:failedItems += $description
        Write-Err "Failed: $description - $_"
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
        $rawList = Get-NativeCommandOutput gh extension list
        if ($LASTEXITCODE -eq 0 -and $rawList) {
            $installedExts = $rawList | ForEach-Object { ($_ -split '\t')[1] } | Where-Object { $_ }
        }
    }

    foreach ($ext in $config.shared.gh_cli_extensions) {
        if ((Test-ShouldSkipInstalled) -and ($installedExts -contains $ext)) {
            Write-Success "Already installed: $ext (gh extension)"
            continue
        }

        Install-GHExtension -Extension $ext
    }
}

function Set-VLCConfiguration {
    Write-Info "Configuring VLC settings..."
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"
    Stop-Process -Name "vlc" -ErrorAction SilentlyContinue

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

    $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
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

# Runs gh against the stored login: GH_TOKEN/GITHUB_TOKEN would override it
# (and make `gh auth refresh` refuse to run). Uses $args rather than a param
# block so flags like -h and -s pass straight through to gh.
function Invoke-GHStoredAuth {
    $saved = @{ GH_TOKEN = $env:GH_TOKEN; GITHUB_TOKEN = $env:GITHUB_TOKEN }
    Remove-Item Env:\GH_TOKEN, Env:\GITHUB_TOKEN -ErrorAction SilentlyContinue
    try {
        gh @args
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -ne $saved[$name]) { Set-Item -Path "Env:\$name" -Value $saved[$name] }
        }
    }
}

# Returns each configured gh_auth_scopes entry the stored login doesn't have
function Get-GHMissingScope {
    $status = (Invoke-GHStoredAuth auth status -h github.com 2>&1) | Out-String
    $granted = ($status -split "`n" | Where-Object { $_ -match 'Token scopes:' }) -join ''
    return @($config.shared.gh_auth_scopes | Where-Object { $_ -and $granted -notmatch [regex]::Escape("'$_'") })
}

# Ensures the GitHub CLI login has the configured scopes (codespace for
# Codespace demos, delete_repo for the Demo Launcher's cleanup, project for
# the Copilot Airways demo's GitHub Project and its cleanup, workflow for
# pushing .github/workflows files to demo repos)
function Confirm-GHScope {
    $missing = @(Get-GHMissingScope)
    if ($missing.Count -eq 0) {
        Write-Success "GitHub CLI login has the required scopes"
        return
    }

    $scopes = $missing -join ','
    Write-Info "Adding GitHub CLI scopes: $scopes..."
    Invoke-GHStoredAuth auth refresh -h github.com -s $scopes
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += "gh auth scopes: $scopes"
        Write-Warn "Could not add scopes. Run 'gh auth refresh -h github.com -s $scopes' manually."
    }
}

function Connect-GH {
    $ghExists = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghExists) {
        Write-Warn "GitHub CLI not found, skipping authentication."
        return
    }

    Invoke-GHStoredAuth auth status -h github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Please authenticate with GitHub..."
        $scopeArgs = @()
        if (@($config.shared.gh_auth_scopes).Count -gt 0) {
            $scopeArgs = @('-s', ($config.shared.gh_auth_scopes -join ','))
        }
        Invoke-GHStoredAuth auth login --web -h github.com @scopeArgs
    }

    Invoke-GHStoredAuth auth status -h github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Confirm-GHScope
        Install-GHExtensions
        Write-Success "GitHub CLI extensions installed"
    } else {
        Write-Warn "GitHub CLI login required for extensions. Please run 'gh auth login' manually."
    }
}

function Get-EdgePath {
    $candidatePaths = @(
        @(
            (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
            (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
        ) | Where-Object { $_ -and (Test-Path $_) }
    )

    if ($candidatePaths.Count -gt 0) {
        return $candidatePaths[0]
    }

    $edgeCommand = Get-Command msedge -ErrorAction SilentlyContinue
    if ($null -ne $edgeCommand) {
        return $edgeCommand.Source
    }

    return $null
}

function Connect-GitHubWeb {
    Write-Info "Opening GitHub.com in Microsoft Edge..."
    $edgePath = Get-EdgePath

    $opened = $false
    if ($null -ne $edgePath) {
        try {
            Start-Process -FilePath $edgePath -ArgumentList "https://github.com"
            $opened = $true
        }
        catch {
            Write-Warn "Could not launch Microsoft Edge ($edgePath): $_"
        }
    }

    if (-not $opened) {
        Write-Warn "Falling back to the default browser."
        try {
            Start-Process "https://github.com"
        }
        catch {
            Write-Warn "Could not open a browser automatically. Please open https://github.com manually."
        }
    }

    Write-Info "Please log in to GitHub.com in your browser with the demo account"
    [void](Read-Host "Press Enter once you have logged in")
    Write-Success "GitHub web authentication confirmed"
}

function Copy-Repos {
    param([switch]$SkipClone)

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
        } elseif ($SkipClone) {
            Write-Warn "Skipping clone: $repo. Authenticate with 'gh auth login' and rerun setup."
        } else {
            Invoke-SafeInstall -Description "clone: $repo" -Action {
                Invoke-NativeCommand gh repo clone $repo $target
            }
        }
    }
}

function Get-CopilotHome {
    if ($env:COPILOT_HOME) { return $env:COPILOT_HOME }
    return Join-Path $env:USERPROFILE ".copilot"
}

# The user-level loader the Copilot app runs in every session, like install.sh writes on macOS/Linux.
# Its folder also holds the launcher's run history (artifacts), so only this file is ever replaced or removed.
function Get-DemoLauncherLoaderPath {
    return Join-Path (Join-Path (Join-Path (Get-CopilotHome) "extensions") "demo-launcher") "extension.mjs"
}

# Fallback copy of repo-setup-scripts' .github/extensions/demo-launcher-loader/extension.mjs,
# used until a checkout ships it. Keep it identical to that file.
$script:VendoredDemoLauncherLoader = Join-Path (Join-Path $PSScriptRoot "windows") "demo-launcher-loader.mjs"
$script:DemoLauncherRepoMarker = 'const INSTALLED_REPO = "";'

# Bakes the checkout into the loader's INSTALLED_REPO line, like install.sh does on macOS/Linux
function Get-DemoLauncherLoaderContent {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$CheckoutDir
    )

    if (-not $Template.Contains($script:DemoLauncherRepoMarker)) {
        Write-Warn "The Demo Launcher loader has no INSTALLED_REPO line, so it will use its default checkout path."
        return $Template
    }
    # JSON string escaping is valid JavaScript, so backslashes and quotes in the path stay intact
    $repoLiteral = ConvertTo-Json -InputObject $CheckoutDir -Compress
    return $Template.Replace($script:DemoLauncherRepoMarker, "const INSTALLED_REPO = $repoLiteral;")
}

function Install-DemoLauncherLoader {
    param([Parameter(Mandatory)][string]$CheckoutDir)

    $extensionsDir = Join-Path (Join-Path $CheckoutDir ".github") "extensions"
    $launcherPath = Join-Path (Join-Path $extensionsDir "demo-launcher") "extension.mjs"
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        $script:failedItems += "loader: Demo Launcher ($launcherPath not found)"
        Write-Err "$launcherPath not found, so the Demo Launcher loader wasn't installed. Pull $CheckoutDir and re-run."
        return
    }

    # Prefer the loader the checkout ships, so every platform runs the same file
    $shippedLoader = Join-Path (Join-Path $extensionsDir "demo-launcher-loader") "extension.mjs"
    $templatePath = if (Test-Path -LiteralPath $shippedLoader -PathType Leaf) { $shippedLoader } else { $script:VendoredDemoLauncherLoader }
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        $script:failedItems += "loader: Demo Launcher ($templatePath not found)"
        Write-Err "$templatePath not found, so the Demo Launcher loader wasn't installed. Pull machine-setup and re-run."
        return
    }
    $loaderPath = Get-DemoLauncherLoaderPath
    try {
        # Read before touching the existing loader, so a failed read can't leave it empty
        $content = Get-DemoLauncherLoaderContent -Template ([System.IO.File]::ReadAllText($templatePath)) -CheckoutDir $CheckoutDir
        New-Item -Path (Split-Path $loaderPath) -ItemType Directory -Force -ErrorAction Stop | Out-Null
        # Windows PowerShell 5.1's -Encoding UTF8 adds a BOM, so write the bytes directly
        [System.IO.File]::WriteAllText($loaderPath, $content, (New-Object System.Text.UTF8Encoding $false))
    } catch {
        $script:failedItems += "loader: Demo Launcher ($loaderPath)"
        Write-Err "Couldn't write the Demo Launcher loader to ${loaderPath}: $($_.Exception.Message)"
        return
    }
    Write-Success "Demo Launcher loader installed at $loaderPath"
}

function Uninstall-DemoLauncherLoader {
    $loaderPath = Get-DemoLauncherLoaderPath
    if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
        Write-Info "No Demo Launcher loader at $loaderPath; nothing to remove."
        return $true
    }
    try {
        Remove-Item -LiteralPath $loaderPath -Force -ErrorAction Stop
    } catch {
        Write-Err "Couldn't remove ${loaderPath}: $($_.Exception.Message)"
        return $false
    }
    Write-Success "Removed $loaderPath (run history in $(Split-Path $loaderPath) was kept)."
    return $true
}

# Only this repo is trusted as the Demo Launcher source, because the loader runs its code in
# every Copilot session and its checkout may be added as a Copilot project.
$script:TrustedDemoLauncherRepo = "octobooth-demos/repo-setup-scripts"

function Get-DemoLauncherRepoDir {
    return Join-Path (Join-Path $env:USERPROFILE "repos") "repo-setup-scripts"
}

function Test-DemoLauncherRemote {
    param([string]$Target)

    $url = Get-NativeCommandOutput git -C $Target remote get-url origin
    if ($LASTEXITCODE -ne 0) { return $false }
    $pattern = '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)' + [regex]::Escape($script:TrustedDemoLauncherRepo) + '(\.git)?/?$'
    return ("$url".Trim() -match $pattern)
}

# Release tag to pin repo-setup-scripts to: a moving major tag (v1) or a full
# version (v1.2.0). -Ref wins over $env:BOOTH_RELEASE; empty tracks main.
function Get-BoothRelease {
    param([string]$Ref)
    if ($Ref) { return $Ref }
    if ($env:BOOTH_RELEASE) { return $env:BOOTH_RELEASE }
    return ''
}

function Test-GitWorktreeClean {
    param([string]$Target)
    $status = Get-NativeCommandOutput git -C $Target status --porcelain --untracked-files=no
    return ($LASTEXITCODE -eq 0 -and -not $status)
}

function Test-GitDetachedHead {
    param([string]$Target)
    Invoke-NativeCommand git -C $Target symbolic-ref --quiet HEAD | Out-Null
    return ($LASTEXITCODE -ne 0)
}

function Write-LocalChangesHelp {
    param([string]$Target)
    Write-Err "$Target has local changes:"
    Invoke-NativeCommand git -C $Target status --short --untracked-files=no | Out-Host
    Write-Err "Save them with: git -C `"$Target`" stash   (or discard them with: git -C `"$Target`" checkout -- .), then re-run."
}

# Pins the checkout to release tag $Ref (detached HEAD). Returns $false, without
# changing the checkout, if the tag is missing or there are local changes.
function Switch-DemoLauncherRelease {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Ref
    )

    $failure = "release: $script:TrustedDemoLauncherRepo at $Ref"
    $validName = $false
    if (-not $Ref.StartsWith('-')) {
        Invoke-NativeCommand git check-ref-format "refs/tags/$Ref" | Out-Null
        $validName = ($LASTEXITCODE -eq 0)
    }
    if (-not $validName) {
        $script:failedItems += $failure
        Write-Err "`"$Ref`" isn't a valid tag name. Releases are tagged like v1 (latest tested v1.x.y) or v1.2.0."
        return $false
    }

    Write-Info "Fetching release tags for $Target..."
    # --force so a moving major tag (v1) follows the remote when it's moved to a newer release
    Invoke-NativeCommand git -C $Target fetch --quiet --tags --force origin | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += $failure
        Write-Err "Couldn't fetch tags for $Target. Check the network and the GitHub CLI login, then re-run."
        return $false
    }

    # fetch --tags doesn't remove tags deleted on origin, so check origin still has it
    Invoke-NativeCommand git -C $Target ls-remote --quiet --exit-code --tags origin "refs/tags/$Ref" | Out-Null
    if ($LASTEXITCODE -eq 2) {
        $script:failedItems += $failure
        Invoke-NativeCommand git -C $Target tag -d $Ref | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Err "Release tag $Ref isn't on GitHub (it may have been withdrawn), so its local copy was removed. Use the major the booth uses (currently v1), or run without a release to track main."
        } else {
            Write-Err "Release tag $Ref doesn't exist in $script:TrustedDemoLauncherRepo. Use the major the booth uses (currently v1), or run without a release to track main."
        }
        return $false
    }
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += $failure
        Write-Err "Couldn't check $script:TrustedDemoLauncherRepo for release tag $Ref. Check the network and the GitHub CLI login, then re-run."
        return $false
    }

    Invoke-NativeCommand git -C $Target rev-parse --quiet --verify "refs/tags/$Ref^{commit}" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += $failure
        Write-Err "Release tag $Ref doesn't exist in $script:TrustedDemoLauncherRepo. Use the major the booth uses (currently v1), or run without a release to track main."
        return $false
    }

    if (-not (Test-GitWorktreeClean -Target $Target)) {
        $script:failedItems += $failure
        Write-LocalChangesHelp -Target $Target
        return $false
    }

    Invoke-NativeCommand git -C $Target checkout --quiet --detach "refs/tags/$Ref" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += $failure
        Write-Err "Couldn't check out $Ref in $Target."
        return $false
    }
    Write-Success "$Target pinned to release $Ref"
    return $true
}

# If the checkout is on a detached HEAD (pinned to a release earlier), switches
# it back to its default branch so it tracks main again. Returns $false if it couldn't.
function Restore-DemoLauncherDefaultBranch {
    param([Parameter(Mandatory)][string]$Target)

    if (-not (Test-GitDetachedHead -Target $Target)) { return $true }

    $failure = "update: $script:TrustedDemoLauncherRepo (couldn't leave its pinned release)"
    $branch = Get-NativeCommandOutput git -C $Target symbolic-ref --quiet --short refs/remotes/origin/HEAD
    $branch = if ($LASTEXITCODE -eq 0 -and $branch) { "$branch".Trim() -replace '^origin/', '' } else { 'main' }
    $pinned = Get-NativeCommandOutput git -C $Target describe --tags --exact-match HEAD
    if ($LASTEXITCODE -ne 0 -or -not $pinned) { $pinned = Get-NativeCommandOutput git -C $Target rev-parse --short HEAD }

    if (-not (Test-GitWorktreeClean -Target $Target)) {
        $script:failedItems += $failure
        Write-LocalChangesHelp -Target $Target
        return $false
    }

    Write-Info "$Target was pinned to $("$pinned".Trim()); switching back to $branch to track the latest changes"
    Invoke-NativeCommand git -C $Target checkout --quiet $branch | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $script:failedItems += $failure
        Write-Err "Couldn't switch $Target back to $branch."
        return $false
    }
    return $true
}

# Pins repo-setup-scripts to the requested release, or, without one, moves a checkout that's
# on a release back to main (like setup.sh). setup.ps1 otherwise leaves existing clones as
# they are. Returns $false if the loader shouldn't be (re)written.
function Sync-DemoLauncherRelease {
    param([string]$Release)

    $checkout = Get-DemoLauncherRepoDir
    if (-not (Test-Path -LiteralPath (Join-Path $checkout ".git"))) { return $true }
    if (-not $Release -and -not (Test-GitDetachedHead -Target $checkout)) { return $true }
    # Install-DemoLauncher reports an untrusted origin, so don't fetch from it here
    if (-not (Test-DemoLauncherRemote -Target $checkout)) { return $true }
    if ($Release) { return (Switch-DemoLauncherRelease -Target $checkout -Ref $Release) }

    if (-not (Restore-DemoLauncherDefaultBranch -Target $checkout)) { return $false }
    Invoke-NativeCommand git -C $checkout pull --ff-only --quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Warn "Couldn't fast-forward $checkout; using it as is." }
    return $true
}

function Install-DemoLauncher {
    $checkout = Get-DemoLauncherRepoDir
    if (-not (Test-Path -LiteralPath (Join-Path $checkout ".git"))) {
        Write-Warn "$checkout isn't a git checkout yet, so the Demo Launcher wasn't installed. Run .\install-demo-launcher.ps1 once GitHub CLI is logged in."
        return
    }
    if (-not (Test-DemoLauncherRemote -Target $checkout)) {
        $script:failedItems += "loader: Demo Launcher ($checkout origin isn't $script:TrustedDemoLauncherRepo)"
        Write-Err "$checkout doesn't point at $script:TrustedDemoLauncherRepo, so the Demo Launcher loader wasn't installed."
        return
    }
    Install-DemoLauncherLoader -CheckoutDir $checkout
}

# ----------------------------------------
# Playwright MCP bundle
# ----------------------------------------
# Booth machines can't reach the npm registry, so the Playwright MCP server comes prebuilt
# from this repo's releases. mcp-bundle\package.json pins the version, and the
# "Playwright MCP bundle" workflow publishes it as playwright-mcp-v<version>.

$script:PlaywrightMcpBundleRepo = 'octobooth-demos/machine-setup'
$script:PlaywrightMcpBrowser = 'msedge'
$script:McpBundlePackagePath = Join-Path (Join-Path $PSScriptRoot 'mcp-bundle') 'package.json'

function Get-PlaywrightMcpBundleVersion {
    if (-not (Test-Path $script:McpBundlePackagePath)) { return $null }
    try {
        $package = Get-Content -Raw -Path $script:McpBundlePackagePath | ConvertFrom-Json
        return $package.dependencies.'@playwright/mcp'
    }
    catch {
        return $null
    }
}

function Get-PlaywrightMcpDir {
    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE ".copilot" }
    return Join-Path (Join-Path $copilotHome 'mcp-servers') 'playwright'
}

function Get-PlaywrightMcpCli {
    return [System.IO.Path]::Combine((Get-PlaywrightMcpDir), 'node_modules', '@playwright', 'mcp', 'cli.js')
}

# Absolute path to node.exe. The Copilot app may not see PATH changes from a winget install
# made earlier in this session, so also check the default install folder.
function Get-NodePath {
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($node) { return $node.Source }
    if ($env:ProgramFiles) {
        $default = Join-Path $env:ProgramFiles 'nodejs\node.exe'
        if (Test-Path $default) { return $default }
    }
    return $null
}

# Windows' own tar.exe, not Git's, which misreads C:\ paths
function Get-TarCommand {
    if ($env:SystemRoot) {
        $systemTar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path $systemTar) { return $systemTar }
    }
    return 'tar'
}

# Copies one bundle file from a release URL or, for offline installs and tests, a local folder
# ($env:PLAYWRIGHT_MCP_BUNDLE_URL)
function Save-PlaywrightMcpBundleFile {
    param(
        [string]$Source,
        [string]$Name,
        [string]$Destination
    )
    $outFile = Join-Path $Destination $Name
    if ($Source -match '^https?://') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        # The progress bar makes Invoke-WebRequest very slow in Windows PowerShell 5.1
        $savedProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri "$Source/$Name" -OutFile $outFile -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
        }
        finally {
            $ProgressPreference = $savedProgress
        }
    } else {
        Copy-Item -Path (Join-Path $Source $Name) -Destination $outFile -ErrorAction Stop
    }
}

# Downloads, verifies, and unpacks the pinned bundle into $HOME\.copilot\mcp-servers\playwright.
# Never fails setup: it warns and skips if the bundle can't be installed.
function Install-PlaywrightMcpBundle {
    $version = Get-PlaywrightMcpBundleVersion
    if (-not $version) {
        Write-Warn "No Playwright MCP version pinned in mcp-bundle\package.json, skipping it"
        return
    }

    $dest = Get-PlaywrightMcpDir
    $versionFile = Join-Path $dest '.bundle-version'
    if (-not $script:ForceReinstall -and (Test-Path (Get-PlaywrightMcpCli)) -and (Test-Path $versionFile) -and
        ((Get-Content -Raw -Path $versionFile).Trim() -eq $version)) {
        Write-Info "Playwright MCP $version already installed, skipping..."
        return
    }

    $asset = "playwright-mcp-$version.tgz"
    $source = if ($env:PLAYWRIGHT_MCP_BUNDLE_URL) { $env:PLAYWRIGHT_MCP_BUNDLE_URL } else {
        "https://github.com/$script:PlaywrightMcpBundleRepo/releases/download/playwright-mcp-v$version"
    }
    Write-Info "Installing Playwright MCP $version..."

    # Stage next to the destination so the final move stays on the same drive
    $parent = Split-Path $dest
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
    $tmp = Join-Path $parent (".playwright-download-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $tmp -ItemType Directory -Force | Out-Null

    try {
        try {
            Save-PlaywrightMcpBundleFile -Source $source -Name $asset -Destination $tmp
            Save-PlaywrightMcpBundleFile -Source $source -Name "$asset.sha256" -Destination $tmp
        }
        catch {
            Write-Warn "Couldn't download Playwright MCP $version from $source, skipping it"
            return
        }

        $expected = ((Get-Content -Path (Join-Path $tmp "$asset.sha256") -TotalCount 1) -split '\s+')[0]
        $actual = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $tmp $asset)).Hash
        if (-not $expected -or $expected -ne $actual) {
            Write-Warn "Playwright MCP $version download failed its checksum, skipping it"
            return
        }

        $bundle = Join-Path $tmp 'bundle'
        New-Item -Path $bundle -ItemType Directory -Force | Out-Null
        Invoke-NativeCommand (Get-TarCommand) -xzf (Join-Path $tmp $asset) -C $bundle | Out-Null
        $bundleCli = [System.IO.Path]::Combine($bundle, 'node_modules', '@playwright', 'mcp', 'cli.js')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bundleCli)) {
            Write-Warn "Couldn't unpack Playwright MCP $version, skipping it"
            return
        }
        Set-Content -Path (Join-Path $bundle '.bundle-version') -Value $version -Encoding ASCII

        if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force -ErrorAction Stop }
        Move-Item -Path $bundle -Destination $dest -ErrorAction Stop
        Write-Success "Installed Playwright MCP $version to $dest"
    }
    catch {
        Write-Warn "Couldn't install Playwright MCP $version, skipping it: $_"
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Adds the bundled Playwright server to the MCP config, if it's installed.
# Leaves a playwright entry alone if someone set up their own.
function Add-PlaywrightMcpServer {
    param([object]$McpConfig)

    $cli = Get-PlaywrightMcpCli
    if (-not (Test-Path $cli)) { return }

    $node = Get-NodePath
    if (-not $node) {
        Write-Warn "Node.js not found, so the Playwright MCP server wasn't registered"
        return
    }

    $existing = $McpConfig.mcpServers.PSObject.Properties['playwright']
    if ($null -ne $existing) {
        $existingArgs = @($existing.Value.args)
        if ($existingArgs.Count -eq 0 -or $existingArgs[0] -ne $cli) {
            Write-Info "Keeping your own 'playwright' MCP server entry"
            return
        }
    }

    $serverConfig = [PSCustomObject]@{
        tools   = @("*")
        type    = "local"
        command = $node
        args    = @($cli, "--browser=$script:PlaywrightMcpBrowser")
    }
    $McpConfig.mcpServers | Add-Member -NotePropertyName 'playwright' -NotePropertyValue $serverConfig -Force
    Write-Success "Registered MCP server: playwright (prebuilt)"
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

    if ($null -eq $mcpConfig.mcpServers) {
        $mcpConfig | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    # Earlier setups registered Playwright MCP via npx, which hangs where npm is blocked
    $playwright = $mcpConfig.mcpServers.PSObject.Properties['playwright']
    if ($null -ne $playwright -and $playwright.Value -is [PSCustomObject] -and $playwright.Value.command -eq 'npx') {
        $playwrightArgs = @($playwright.Value.args | Where-Object { $_ -is [string] -and $_.Contains('@playwright/mcp') })
        if ($playwrightArgs.Count -gt 0) {
            $mcpConfig.mcpServers.PSObject.Properties.Remove('playwright')
            Write-Success "Removed old Playwright MCP server (npx @playwright/mcp)"
        }
    }

    foreach ($server in $config.shared.mcp_servers) {
        $serverConfig = if ($server.type -eq "local") {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                command = $server.command
                args    = @($server.args)
            }
        } else {
            [PSCustomObject]@{
                tools   = @("*")
                type    = $server.type
                url     = $server.url
                headers = [PSCustomObject]@{}
            }
        }

        $mcpConfig.mcpServers | Add-Member -NotePropertyName $server.name -NotePropertyValue $serverConfig -Force
        Write-Success "Registered MCP server: $($server.name)"
    }

    Add-PlaywrightMcpServer -McpConfig $mcpConfig

    $mcpConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $mcpConfigPath -Force -Encoding UTF8
    Write-Success "MCP servers written to $mcpConfigPath"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

function Invoke-Main {
    param([string]$Ref)

    $ErrorActionPreference = "Continue"

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Starting setup script - $(Get-Date)"    -ForegroundColor Cyan
    Write-Host "Running from: $PSScriptRoot"             -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Bootstrap
    if (-not (Test-Prerequisites)) { return }
    Import-Config

    # Install packages
    Install-Packages
    Set-VLCConfiguration
    Set-TaskbarPins

    # Launch post-install apps
    Start-PostInstallApps

    $skipRepoClones = $false
    # Authentication steps need a human; NONINTERACTIVE=true skips them (e.g. for sandbox runs)
    if ($script:NonInteractive) {
        Write-Warn "NONINTERACTIVE set: skipping GitHub web and CLI authentication"
        $skipRepoClones = $true
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            Invoke-NativeCommand gh auth status --active -h github.com | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $skipRepoClones = $false
                Install-GHExtensions
            }
        }
        if ($skipRepoClones) {
            Write-Warn "GitHub CLI credentials unavailable: deferring CLI extensions and repository clones. Authenticate with 'gh auth login' and rerun setup."
        }
    }
    else {
        # Web authentication (Edge is preinstalled on Windows)
        Connect-GitHubWeb

        # Setup environments
        Connect-GH
    }
    Copy-Repos -SkipClone:$skipRepoClones

    # Make the Demo Launcher available in every Copilot session, at the requested release if any
    $release = Get-BoothRelease -Ref $Ref
    if ($release) { Write-Info "Using release $release of $script:TrustedDemoLauncherRepo" }
    if (Sync-DemoLauncherRelease -Release $release) {
        Install-DemoLauncher
    } else {
        Write-Err "Demo Launcher not updated, because repo-setup-scripts isn't at release $release"
    }

    # PWA setup is intentionally disabled until the booth workflow needs it again.
    # See README for the rationale and re-enable notes.
    # Install-PWAs

    # Install extensions and configure themes
    Initialize-Editors

    # Register MCP servers for Copilot CLI, including the prebuilt Playwright server
    Install-PlaywrightMcpBundle
    Register-MCPServers

    # Print summary and finish
    Write-Summary
    if ($script:failedItems.Count -gt 0) {
        Write-Warn "Script completed with $($script:failedItems.Count) failure(s)"
        exit 1
    }
    if ($script:adminSkippedItems.Count -gt 0) {
        Write-Warn "Script completed, but $($script:adminSkippedItems.Count) step(s) need Administrator (see above)"
        return
    }
    Write-Success "Script completed successfully"
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-Main -Ref $Ref
}
