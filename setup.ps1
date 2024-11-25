# Setup.ps1
#
# Setup script for GitHub development environment on Windows
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling

# -----------------------------
# Constants and Variables
# -----------------------------

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
    foreach ($ext in $vs_code_extensions) {
        code --install-extension $ext
    }
}

function Install-VSCodeInsidersExtensions {
    foreach ($ext in $vs_code_extensions) {
        code-insiders --install-extension $ext
    }
}

function Install-GHExtensions {
    foreach ($ext in $gh_cli_extensions) {
        gh extension install $ext
    }
}

function Set-VLCConfiguration {
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
    $demoScript = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'load-demos.ps1')
    @"
# Demo Loader Script

# Open required sites
"@ | Out-File -FilePath $demoScript

    foreach ($url in $DEMO_SITES) {
        "@{ Write-Output `"Opening $url`"; Start-Process $url }" | Out-File -FilePath $demoScript -Append
    }

    @"
# Open applications
Start-Process "C:\Program Files\Microsoft VS Code\Code.exe"
Start-Process "C:\Program Files\Microsoft VS Code Insiders\Code - Insiders.exe"
Start-Process "C:\Program Files\VideoLAN\VLC\vlc.exe" "$env:USERPROFILE\Videos"
"@ | Out-File -FilePath $demoScript -Append

    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) Created demo loader script at $demoScript" -ForegroundColor Green
}

function Install-PWAs {
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
        Start-Process "msedge" "--app=$url"
        
        # Give user time to accept the PWA installation
        Start-Sleep -Seconds 5
    }
    Write-Host "$([char]::ConvertFromUtf32(0x2705)) PWA installation completed - accept the prompts in Edge to add them to Start" -ForegroundColor Green
}

# -----------------------------
# Main Execution
# -----------------------------

# Install core applications
Install-App -Name "Visual Studio Code" -Id "Microsoft.VisualStudioCode"
Install-App -Name "Visual Studio Code Insiders" -Id "Microsoft.VisualStudioCode.Insiders"
Install-App -Name "GitHub CLI" -Id "GitHub.cli"
Install-App -Name "VLC Media Player" -Id "VideoLAN.VLC"

# Refresh the path so that GitHub CLI Extension installations work correctly
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 

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
} else {
    Write-Host "$([char]::ConvertFromUtf32(0x26A0)) You must be logged in to install extensions." -ForegroundColor Yellow
}

# Set VS Code theme
Set-VSCodeTheme

# Create demo loader script
New-DemoLoader

# Verify installation
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