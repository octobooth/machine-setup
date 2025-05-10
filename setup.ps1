<#
.SYNOPSIS
    Sets up a windows machine based on the needs for demoing at a booth.

.DESCRIPTION
    This script automates the installation and configuration of a complete
    development environment including VS Code, GitHub tooling, and related utilities.
    It handles software installation, extension setup, and environment configuration.

.PARAMETER None
    This script does not accept parameters but reads from config.json which is common
		for the linux and windows setup scripts.

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

# Setup.ps1
#
# Setup script for GitHub development environment on Windows
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling

# -----------------------------
# Constants and Variables
# -----------------------------

# Configuration is externalized to allow easy updates without modifying script logic
$config = Get-Content -Raw -Path "./config.json" | ConvertFrom-Json

$vscode_theme = $config.vscode_theme
$vs_code_extensions = $config.vs_code_extensions
$gh_cli_extensions = $config.gh_cli_extensions
$PWA_SITES = $config.pwa_sites
$DEMO_SITES = $config.demo_sites
$VLC_SETTINGS = $config.vlc_settings

# -----------------------------
# Function Definitions
# -----------------------------

function Install-App {
    <#
    .SYNOPSIS
        Installs an application using winget if not already installed.
    .PARAMETER Name
        Display name of the application
    .PARAMETER Id
        Winget package identifier
    #>
    param (
        [string]$Name,
        [string]$Id
    )
    if (-not (winget list | Select-String $Id)) {
        Write-Host "$([char]::ConvertFromUtf32(0x2139)) Installing $Name..." -ForegroundColor Blue
        winget install --id $Id -e --silent
    }
    else {
        Write-Host "$([char]::ConvertFromUtf32(0x2705)) $Name is already installed." -ForegroundColor Green
    }
}

function Install-VSCodeExtensions {
    <#
    .SYNOPSIS
        Installs extensions for regular VS Code build.
    .DESCRIPTION
        Iterates through configured extensions and installs them in VS Code stable.
    #>
    foreach ($ext in $vs_code_extensions) {
        code --install-extension $ext
    }
}

function Install-VSCodeInsidersExtensions {
    <#
    .SYNOPSIS
        Installs extensions for VS Code Insiders build.
    .DESCRIPTION
        Iterates through configured extensions and installs them in VS Code Insiders.
    #>
    foreach ($ext in $vs_code_extensions) {
        code-insiders --install-extension $ext
    }
}

function Install-GHExtensions {
    <#
    .SYNOPSIS
        Installs GitHub CLI extensions.
    .DESCRIPTION
        Installs configured GitHub CLI extensions after authentication is confirmed.
    #>
    foreach ($ext in $gh_cli_extensions) {
        gh extension install $ext
    }
}

function Set-VLCConfiguration {
    <#
    .SYNOPSIS
        Configures VLC media player settings.
    .DESCRIPTION
        Creates and populates VLC configuration file with predefined settings.
        Only creates new configuration if none exists.
    #>
    Write-Host "$([char]::ConvertFromUtf32(0x2139)) Configuring VLC settings..." -ForegroundColor Blue
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"
    if (-not (Test-Path $vlcConfigPath)) {
        New-Item -Path (Split-Path $vlcConfigPath) -ItemType Directory -Force
        New-Item -Path $vlcConfigPath -ItemType File -Force
    }
    Add-Content -Path $vlcConfigPath -Value "# Setup-script-configured=true"
    Add-Content -Path $vlcConfigPath -Value $VLC_SETTINGS
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) VLC settings configured - please restart VLC" -ForegroundColor Green
}

function Set-VSCodeTheme {
    <#
    .SYNOPSIS
        Sets the VS Code color theme.
    .DESCRIPTION
        Creates or updates VS Code settings.json to apply the configured theme.
        Creates settings file if it doesn't exist.
    #>
    $settingsPath = "$env:APPDATA\Code\User\settings.json"
    
    # Create settings file if it doesn't exist
    if (-not (Test-Path $settingsPath)) {
        New-Item -Path (Split-Path $settingsPath) -ItemType Directory -Force
        New-Item -Path $settingsPath -ItemType File -Force
        "{}" | Out-File -FilePath $settingsPath
    }
    
    # Read current settings
    $settings = Get-Content -Path $settingsPath | ConvertFrom-Json
    
    # Set the theme directly in settings object
    $settings | Add-Member -NotePropertyName "workbench.colorTheme" -NotePropertyValue $vscode_theme -Force
    
    # Save settings
    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsPath -Force
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) VS Code theme set to $vscode_theme" -ForegroundColor Green
}

function New-DemoLoader {
    <#
    .SYNOPSIS
        Creates a PowerShell script for loading demo environment.
    .DESCRIPTION
        Generates a script on the desktop that opens configured demo sites
        and launches required applications with appropriate delays.
    #>
    # Creates a convenience script for demo environment setup
    # Delays between operations to ensure smooth loading
    $demoScript = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'load-demos.ps1')
    
    # Create the initial script content
    $scriptContent = @"
# Demo Loader Script
Write-Host "Loading demo environment..." -ForegroundColor Blue

# Open required sites
foreach (`$url in @(
"@ 
    # Add each demo site URL
    foreach ($url in $DEMO_SITES) {
        $scriptContent += "    `"$url`",`n"
    }
    
    # Remove the last comma and close the array
    $scriptContent = $scriptContent.TrimEnd(",`n")
    
    # Add the rest of the script
    $scriptContent += @"
)) {
    Write-Host "Opening `$url" -ForegroundColor Gray
    Start-Process "`$url"
    Start-Sleep -Seconds 1
}

# Open applications
Write-Host "Launching applications..." -ForegroundColor Blue
& code
& code-insiders
Start-Process "vlc" -ArgumentList "$env:USERPROFILE\Videos"

Write-Host "Demo environment loaded!" -ForegroundColor Green
"@

    # Write the complete script to file
    $scriptContent | Out-File -FilePath $demoScript -Force -Encoding UTF8

    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) Created demo loader script at $demoScript" -ForegroundColor Green
}

function Install-PWAs {
    <#
    .SYNOPSIS
        Installs Progressive Web Apps using Microsoft Edge.
    .DESCRIPTION
        Ensures Edge is installed then installs configured PWAs.
        Includes delay for user interaction with installation prompts.
    #>
    # Progressive Web Apps improve desktop integration for web tools
    # Edge is required for PWA functionality
    # Ensure Edge is installed
    if (-not (winget list | Select-String "Microsoft.Edge")) {
        Write-Host "$([char]::ConvertFromUtf32(0x2139)) Installing Microsoft Edge..." -ForegroundColor Blue
        winget install --id Microsoft.Edge -e --silent
    }

    foreach ($site in $PWA_SITES) {
        $name = $site.name
        $url = $site.url
        Write-Host "$([char]::ConvertFromUtf32(0x2139)) Installing PWA for $name..." -ForegroundColor Blue
        # Launch Edge with the --app parameter to trigger PWA installation
        Start-Process "msedge" "--install-webapp=$url"

				# Await user input to confirm they have added the website as a PWA (prompt in Edge)
				$input = Read-Host "Press Enter after you have added the PWA for $name in Edge"
    }
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) PWA installation completed - accept the prompts in Edge to add them to Start" -ForegroundColor Green
}

# -----------------------------
# Main Execution
# -----------------------------

# Main execution block
# Order is important: base apps → authentication → extensions → configuration
# This ensures dependencies are available when needed

# Install core applications first
Install-App -Name "Visual Studio Code" -Id "Microsoft.VisualStudioCode"
Install-App -Name "Visual Studio Code Insiders" -Id "Microsoft.VisualStudioCode.Insiders"
Install-App -Name "Windows Terminal" -Id "Microsoft.WindowsTerminal"
Install-App -Name "GitHub CLI" -Id "GitHub.cli"
Install-App -Name "VLC Media Player" -Id "VideoLAN.VLC"

# Refresh the path so that GitHub CLI Extension installations work correctly
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") 

# Install PWAs
Install-PWAs

# Install extensions
Install-VSCodeExtensions
Install-VSCodeInsidersExtensions

# Configure VLC
Set-VLCConfiguration

# Authenticate GitHub CLI
if (-not (gh auth status)) {
    Write-Host "$([char]::ConvertFromUtf32(0x2139)) Please authenticate with GitHub..." -ForegroundColor Blue
    gh auth login
}

# Check if the user is logged in
if (gh auth status) {
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) GitHub authentication successful" -ForegroundColor Green
    Install-GHExtensions
}
else {
    Write-Host "$([char]::ConvertFromUtf32(0x26A0)) You must be logged in to install extensions." -ForegroundColor Yellow
}

# Set VS Code theme
Set-VSCodeTheme

# Create demo loader script
New-DemoLoader

# Final verification ensures all critical components are installed
$installed = @(
    "Visual Studio Code",
    "Visual Studio Code Insiders",
    "VLC Media Player",
    "GitHub CLI"
) | ForEach-Object { winget list | Select-String $_ }

if ($installed.Count -ge 4) {
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) Script completed successfully" -ForegroundColor Green
}
else {
    Write-Host "$([char]::ConvertFromUtf32(0x26A0)) There was an issue with the installation. Please check the error messages above." -ForegroundColor Yellow
}
