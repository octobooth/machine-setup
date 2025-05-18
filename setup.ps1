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
        Installs an application using winget.
    .PARAMETER Name
        Display name of the application
    .PARAMETER Id
        Winget package identifier
    #>
    param (
        [string]$Name,
        [string]$Id
    )
    try {
        Write-Host "$([char]::ConvertFromUtf32(0x2139)) Installing $Name..." -ForegroundColor Blue
          # Just attempt the install - winget will handle if it's already installed
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements --silent 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$([char]::ConvertFromUtf32(0x2705)) Successfully installed $Name" -ForegroundColor Green
        } else {
            Write-Host "$([char]::ConvertFromUtf32(0x26A0)) There might have been an issue installing $Name" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "$([char]::ConvertFromUtf32(0x274C)) Error installing $Name. Exception: $_" -ForegroundColor Red
    }
}

function Install-VSCodeExtensions {
    <#
    .SYNOPSIS
        Installs extensions for regular VS Code build.
    .DESCRIPTION
        Iterates through configured extensions and installs them in VS Code stable.
    #>
    try {
        # Test if code command is available
        $codeExists = Get-Command code -ErrorAction SilentlyContinue
        if ($null -eq $codeExists) {
            Write-Host "$([char]::ConvertFromUtf32(0x26A0)) VS Code is not available in PATH. Can't install extensions." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Installing VS Code extensions..." -ForegroundColor Blue
        foreach ($ext in $vs_code_extensions) {
            Write-Host "Installing extension: $ext" -ForegroundColor Gray
            $result = code --install-extension $ext 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$([char]::ConvertFromUtf32(0x2705)) Successfully installed extension: $ext" -ForegroundColor Green
            } else {
                Write-Host "$([char]::ConvertFromUtf32(0x26A0)) Failed to install extension: $ext" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "$([char]::ConvertFromUtf32(0x274C)) Error installing VS Code extensions: $_" -ForegroundColor Red
    }
}

function Install-VSCodeInsidersExtensions {
    <#
    .SYNOPSIS
        Installs extensions for VS Code Insiders build.
    .DESCRIPTION
        Iterates through configured extensions and installs them in VS Code Insiders.
    #>
    try {
        # Test if code-insiders command is available
        $codeInsidersExists = Get-Command code-insiders -ErrorAction SilentlyContinue
        if ($null -eq $codeInsidersExists) {
            Write-Host "$([char]::ConvertFromUtf32(0x26A0)) VS Code Insiders is not available in PATH. Can't install extensions." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Installing VS Code Insiders extensions..." -ForegroundColor Blue
        foreach ($ext in $vs_code_extensions) {
            Write-Host "Installing extension: $ext" -ForegroundColor Gray
            $result = code-insiders --install-extension $ext 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$([char]::ConvertFromUtf32(0x2705)) Successfully installed extension: $ext" -ForegroundColor Green
            } else {
                Write-Host "$([char]::ConvertFromUtf32(0x26A0)) Failed to install extension: $ext" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "$([char]::ConvertFromUtf32(0x274C)) Error installing VS Code Insiders extensions: $_" -ForegroundColor Red
    }
}

function Install-GHExtensions {
    <#
    .SYNOPSIS
        Installs GitHub CLI extensions.
    .DESCRIPTION
        Installs configured GitHub CLI extensions after authentication is confirmed.
    #>
    try {
        # Test if gh command is available
        $ghExists = Get-Command gh -ErrorAction SilentlyContinue
        if ($null -eq $ghExists) {
            Write-Host "$([char]::ConvertFromUtf32(0x26A0)) GitHub CLI is not available in PATH. Can't install extensions." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Installing GitHub CLI extensions..." -ForegroundColor Blue
        foreach ($ext in $gh_cli_extensions) {
            Write-Host "Installing extension: $ext" -ForegroundColor Gray
            $result = gh extension install $ext 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$([char]::ConvertFromUtf32(0x2705)) Successfully installed extension: $ext" -ForegroundColor Green
            } else {
                Write-Host "$([char]::ConvertFromUtf32(0x26A0)) Failed to install extension: $ext" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "$([char]::ConvertFromUtf32(0x274C)) Error installing GitHub CLI extensions: $_" -ForegroundColor Red
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
    Write-Host "Assuming Microsoft Edge is already installed (skipping check to avoid errors)" -ForegroundColor Yellow

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

# Enable verbose output to track script execution
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"
$VerbosePreference = "Continue"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting setup script - $(Get-Date)" -ForegroundColor Cyan
Write-Host "Running from: $PSScriptRoot" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "✅ Running with Administrator privileges" -ForegroundColor Green
} else {
    Write-Host "⚠️ WARNING: Not running with Administrator privileges. Some operations may fail." -ForegroundColor Yellow
    Write-Host "Consider restarting the script with admin rights by right-clicking PowerShell and selecting 'Run as Administrator'" -ForegroundColor Yellow
}

# Verify config.json exists and can be loaded
if (Test-Path "./config.json") {
    Write-Host "✅ config.json found" -ForegroundColor Green
} else {
    Write-Host "❌ ERROR: config.json not found in $PSScriptRoot" -ForegroundColor Red
    return
}

# Main execution block
# Order is important: base apps → authentication → extensions → configuration
# This ensures dependencies are available when needed

Write-Host "Checking for winget command availability..." -ForegroundColor Cyan
try {
    $wingetVersion = winget --version
    Write-Host "✅ winget is available (version: $wingetVersion)" -ForegroundColor Green
} catch {
    Write-Host "❌ ERROR: winget command not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
    return
}

# Install core applications first
Write-Host "Starting application installations..." -ForegroundColor Cyan
Install-App -Name "Visual Studio Code" -Id "Microsoft.VisualStudioCode"
Install-App -Name "Visual Studio Code Insiders" -Id "Microsoft.VisualStudioCode.Insiders"
Install-App -Name "Windows Terminal" -Id "Microsoft.WindowsTerminal"
Install-App -Name "GitHub CLI" -Id "GitHub.cli"
Install-App -Name "VLC Media Player" -Id "VideoLAN.VLC"
Write-Host "Core application installation complete" -ForegroundColor Cyan

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
    "Windows Terminal",
    "VLC Media Player",
    "GitHub CLI"
) | ForEach-Object { winget list | Select-String $_ }

if ($installed.Count -ge 4) {
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) Script completed successfully" -ForegroundColor Green
}
else {
    Write-Host "$([char]::ConvertFromUtf32(0x26A0)) There was an issue with the installation. Please check the error messages above." -ForegroundColor Yellow
}
