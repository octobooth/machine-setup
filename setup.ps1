# Setup.ps1
#
# Setup script for GitHub development environment on Windows
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling

# -----------------------------
# Constants and Variables
# -----------------------------

$config = Get-Content -Raw -Path "/workspaces/machine-setup/config.json" | ConvertFrom-Json

$VSCODE_THEME = $config.vscode_theme
$vs_code_extensions = $config.vs_code_extensions
$gh_cli_extensions = $config.gh_cli_extensions
$PWA_SITES = $config.pwa_sites
$DEMO_SITES = $config.demo_sites
$VLC_SETTINGS = $config.vlc_settings

# -----------------------------
# Function Definitions
# -----------------------------

function Install-App {
    param (
        [string]$Name,
        [string]$Id
    )
    if (-not (winget list | Select-String $Id)) {
        Write-Output "Installing $Name..."
        winget install --id $Id -e --silent
    } else {
        Write-Output "$Name is already installed."
    }
}

function Install-VSCodeExtensions {
    foreach ($ext in $vs_code_extensions) {
        code --install-extension $ext
    }
}

function Install-GHExtensions {
    foreach ($ext in $gh_cli_extensions) {
        gh extension install $ext
    }
}

function Configure-VLC {
    Write-Output "Configuring VLC settings..."
    $vlcConfigPath = "$env:APPDATA\vlc\vlcrc"
    if (-not (Test-Path $vlcConfigPath)) {
        New-Item -Path (Split-Path $vlcConfigPath) -ItemType Directory -Force
        New-Item -Path $vlcConfigPath -ItemType File -Force
    }
    Add-Content -Path $vlcConfigPath -Value "# Setup-script-configured=true"
    Add-Content -Path $vlcConfigPath -Value $VLC_SETTINGS
    Write-Output "✅ VLC settings configured - please restart VLC"
}

function Set-VSCodeTheme {
    $settingsPath = "$env:APPDATA\Code\User\settings.json"
    if (-not (Test-Path $settingsPath)) {
        New-Item -Path (Split-Path $settingsPath) -ItemType Directory -Force
        '{ "workbench.colorTheme": "' + $VSCODE_THEME + '" }' | Out-File -FilePath $settingsPath
    } else {
        $settings = Get-Content $settingsPath | ConvertFrom-Json
        $settings.workbench.colorTheme = $VSCODE_THEME
        $settings | ConvertTo-Json | Out-File -FilePath $settingsPath
    }
}

function Create-DemoLoader {
    $demoScript = "$env:USERPROFILE\Desktop\load-demos.ps1"
    @"
# Demo Loader Script

# Open required sites
"@ | Out-File -FilePath $demoScript

    foreach ($url in $DEMO_SITES) {
        "@{ Write-Output "Opening $url"; Start-Process $url }" | Out-File -FilePath $demoScript -Append
    }

    @"
# Open applications
Start-Process "C:\Program Files\Microsoft VS Code\Code.exe"
Start-Process "C:\Program Files\Microsoft VS Code Insiders\Code - Insiders.exe"
Start-Process "C:\Program Files\VideoLAN\VLC\vlc.exe" "$env:USERPROFILE\Videos"
"@ | Out-File -FilePath $demoScript -Append

    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Output "✅ Created demo loader script at $demoScript"
}

# -----------------------------
# Main Execution
# -----------------------------

# Install core applications
Install-App -Name "Visual Studio Code" -Id "Microsoft.VisualStudioCode"
Install-App -Name "Visual Studio Code Insiders" -Id "Microsoft.VisualStudioCodeInsiders"
Install-App -Name "GitHub CLI" -Id "GitHub.cli"
Install-App -Name "VLC Media Player" -Id "VideoLAN.VLC"

# Install extensions
Install-VSCodeExtensions

# Configure VLC
Configure-VLC

# Install GitHub CLI extensions
Install-GHExtensions

# Authenticate GitHub CLI
if (-not (gh auth status)) {
    gh auth login
}

# Set VS Code theme
Set-VSCodeTheme

# Create demo loader script
Create-DemoLoader

# Verify installation
$installed = @(
    "Visual Studio Code",
    "Visual Studio Code Insiders",
    "VLC Media Player",
    "GitHub CLI"
) | ForEach-Object { winget list | Select-String $_ }

if ($installed.Count -eq 4) {
    Write-Output "✅ Script completed successfully"
} else {
    Write-Output "⚠️ There was an issue with the installation. Please check the error messages above."
}