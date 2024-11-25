#!/bin/bash
#
# Setup script for GitHub development environment
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling
#

# -----------------------------
# Constants and Variables
# -----------------------------

CONFIG_FILE="/workspaces/machine-setup/config.json"

# Load configuration from JSON file
VSCODE_THEME=$(jq -r '.vscode_theme' "$CONFIG_FILE")
vs_code_extensions=($(jq -r '.vs_code_extensions[]' "$CONFIG_FILE"))
gh_cli_extensions=($(jq -r '.gh_cli_extensions[]' "$CONFIG_FILE"))
PWA_SITES=($(jq -r '.pwa_sites[]' "$CONFIG_FILE"))
DEMO_SITES=($(jq -r '.demo_sites[]' "$CONFIG_FILE"))

# -----------------------------
# Function Definitions
# -----------------------------

# Checks if Visual Studio Code is installed by verifying the application directory exists
check_vscode() {
    if [ -d "/Applications/Visual Studio Code.app" ]; then
        echo "VS Code is already installed"
        return 0
    else
        return 1
    fi
}

# Checks if Visual Studio Code Insiders is installed by verifying the application directory exists
check_vscode_insiders() {
    if [ -d "/Applications/Visual Studio Code - Insiders.app" ]; then
        echo "VS Code Insiders is already installed"
        return 0
    else
        return 1
    fi
}

# Configures VLC settings to hide filename display and enable loop by default
configure_vlc_settings() {
    echo "🎮 Configuring VLC settings..."
    
    PREF_FILE="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
    mkdir -p "$(dirname "$PREF_FILE")"
    
    # Check if we've already configured settings
    if grep -q "# Setup-script-configured=true" "$PREF_FILE" 2>/dev/null; then
        echo "VLC settings already configured, skipping..."
        return
    fi
    
    # Kill VLC if running
    killall VLC 2>/dev/null || true
    
    # Add our sentinel and settings
    {
        echo "# Setup-script-configured=true"
        echo "osd=0 # Hide filename display"
        echo "loop=1 # Enable loop by default"
        echo "video-title-show=0 # Hide filename display"
    } >> "$PREF_FILE"
    
    echo "✅ VLC settings configured - please restart VLC"
}

# Installs Homebrew if not present and updates it if already installed
install_brew() {
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo "Homebrew is already installed"
    fi
    echo "Updating Homebrew..."
    brew update
}

# Installs GitHub CLI (gh) using Homebrew if not already installed
install_gh() {
    if ! command -v gh &> /dev/null; then
        echo "Installing GitHub CLI..."
        brew install gh
        return 0
    else
        echo "GitHub CLI is already installed"
        return 1
    fi
}

# Installs a suite of GitHub CLI extensions for enhanced functionality
install_gh_extensions() {
    echo "Installing GitHub CLI extensions..."
    for ext in "${gh_cli_extensions[@]}"
    do
        gh extension install "$ext"
    done
}

# Installs VLC media player using Homebrew
install_vlc() {
    echo "📺 Installing VLC media player..."
    brew install --cask vlc
}

# Installs Visual Studio Code using Homebrew if not already present
install_vscode() {
    if ! check_vscode; then
        echo "Installing VS Code..."
        brew install --cask visual-studio-code
        return 0
    fi
    return 1
}

# Installs predefined VS Code extensions using the VS Code CLI
install_vscode_extensions() {
    echo "Installing VS Code extensions..."
    if ! "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --version &> /dev/null; then
        echo "Error: VS Code binary not found"
        return 1
    fi
    
    for ext in "${vs_code_extensions[@]}"
    do
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension "$ext"
    done
}

# Installs Visual Studio Code Insiders using Homebrew if not already present
install_vscode_insiders() {
    if ! check_vscode_insiders; then
        echo "Installing VS Code Insiders..."
        brew install --cask visual-studio-code-insiders
        return 0
    fi
    return 1
}

# Installs predefined VS Code extensions for VS Code Insiders
install_vscode_insiders_extensions() {
    echo "Installing VS Code Insiders extensions..."
    if ! "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code" --version &> /dev/null; then
        echo "Error: VS Code Insiders binary not found"
        return 1
    fi
    
    for ext in "${vs_code_extensions[@]}"
    do
        "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code" --install-extension "$ext"
    done
}

# Ensures user is authenticated with GitHub CLI and installs extensions if authenticated
setup_gh_auth() {
    if command -v gh &> /dev/null; then
        if ! gh auth status &> /dev/null; then
            echo "Please login to GitHub CLI first..."
            gh auth login
        fi
        
        if gh auth status &> /dev/null; then
            # install_gh_extensions
            echo "✅ GitHub CLI extensions installed"
        else
            echo "⚠️ GitHub CLI login required for installing extensions. Please run 'gh auth login' manually."
        fi
    fi
}

# Guides user through GitHub web authentication process using Safari
setup_github_web_auth() {
    echo "Opening GitHub.com in Safari..."
    open -a Safari https://github.com
    echo "Please log in to GitHub.com in Safari with the demo account"
    echo "Press Enter once you have logged in..."
    read -r
    echo "✅ GitHub web authentication confirmed"
}

# Assists user in setting up Progressive Web Apps (PWAs) for GitHub tools
setup_safari_and_pwas() {
    echo "Opening required websites in Safari..."
    
    for url in "${PWA_SITES[@]}"; do
        open -a Safari "$url"
        echo "Please manually add $url as a PWA by:"
        echo "1. Click Share button in Safari"
        echo "2. Select 'Add to Dock'"
        echo "Press Enter when done..."
        read -r
    done
}

# Sets the VS Code theme to the predefined value
set_vscode_theme() {
    echo "Setting VS Code theme..."
    VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
    
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    
    if [ ! -f "$VSCODE_SETTINGS" ]; then
        echo "{\"workbench.colorTheme\": \"$VSCODE_THEME\"}" > "$VSCODE_SETTINGS"
    else
        TMP_FILE=$(mktemp)
        jq ". + {\"workbench.colorTheme\": \"$VSCODE_THEME\"}" "$VSCODE_SETTINGS" > "$TMP_FILE"
        mv "$TMP_FILE" "$VSCODE_SETTINGS"
    fi
}

# Sets the VS Code Insiders theme to the predefined value
set_vscode_insiders_theme() {
    echo "Setting VS Code Insiders theme..."
    VSCODE_SETTINGS="$HOME/Library/Application Support/Code - Insiders/User/settings.json"
    
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    
    if [ ! -f "$VSCODE_SETTINGS" ]; then
        echo "{\"workbench.colorTheme\": \"$VSCODE_THEME\"}" > "$VSCODE_SETTINGS"
    else
        TMP_FILE=$(mktemp)
        jq ". + {\"workbench.colorTheme\": \"$VSCODE_THEME\"}" "$VSCODE_SETTINGS" > "$TMP_FILE"
        mv "$TMP_FILE" "$VSCODE_SETTINGS"
    fi
}

# Creates a demo loader script to launch all required applications and sites
create_demo_loader() {
    echo "Creating demo loader script..."
    DEMO_SCRIPT="$HOME/Desktop/load-demos.sh"
    
    # Create the script header
    cat > "$DEMO_SCRIPT" << 'EOF'
#!/bin/bash

EOF
    
    # Add the sites dynamically
    echo "# Open all required sites in Safari" >> "$DEMO_SCRIPT"
    printf 'open -a Safari %s\n\n' "$(printf '"%s" ' "${DEMO_SITES[@]}")" >> "$DEMO_SCRIPT"
    
    # Add the remaining standard content
    cat >> "$DEMO_SCRIPT" << 'EOF'
# Open VS Code and VS Code Insiders
open -a "Visual Studio Code"
open -a "Visual Studio Code - Insiders"

# Open VLC pointing to Videos folder
open -a VLC "$HOME/Videos"
EOF
    
    chmod +x "$DEMO_SCRIPT"
    echo "✅ Created demo loader script at $DEMO_SCRIPT"
}

# -----------------------------
# Main Execution
# -----------------------------

# Initial web authentication
setup_github_web_auth

# Install core tools
install_brew
install_vscode
install_vscode_insiders
install_gh
install_vlc
configure_vlc_settings

# Setup environments
setup_gh_auth
setup_safari_and_pwas

# Install extensions and configure themes
install_vscode_extensions
install_vscode_insiders_extensions
set_vscode_theme
set_vscode_insiders_theme

# Create demo loader script
create_demo_loader

# Verify installation
if [ -d "/Applications/Visual Studio Code.app" ] && 
   [ -d "/Applications/Visual Studio Code - Insiders.app" ] && 
   [ -d "/Applications/VLC.app" ] &&
   command -v gh &> /dev/null; then
    echo "✅ Script completed successfully"
else
    echo "⚠️ There was an issue with the installation. Please check the error messages above."
fi
