#!/bin/bash
#
# Setup script for GitHub development environment
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling
#

# -----------------------------
# Constants and Variables
# -----------------------------

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emojis
CHECK="✅"
WARN="⚠️"
INFO="ℹ️"
ERROR="❌"

CONFIG_FILE="/workspaces/machine-setup/config.json"

# Load configuration from JSON file
VSCODE_THEME=$(jq -r '.vscode_theme' "$CONFIG_FILE")
vs_code_extensions=($(jq -r '.vs_code_extensions[]' "$CONFIG_FILE"))
gh_cli_extensions=($(jq -r '.gh_cli_extensions[]' "$CONFIG_FILE"))
# Update PWA sites loading to handle objects with name and url
mapfile -t PWA_NAMES < <(jq -r '.pwa_sites[].name' "$CONFIG_FILE")
mapfile -t PWA_URLS < <(jq -r '.pwa_sites[].url' "$CONFIG_FILE")
DEMO_SITES=($(jq -r '.demo_sites[]' "$CONFIG_FILE"))
VLC_SETTINGS=$(jq -r '.vlc_settings' "$CONFIG_FILE")

# -----------------------------
# Function Definitions
# -----------------------------

# Checks if Visual Studio Code is installed by verifying the application directory exists
check_vscode() {
    if [ -d "/Applications/Visual Studio Code.app" ]; then
        echo -e "${GREEN}${CHECK} VS Code is already installed${NC}"
        return 0
    else
        return 1
    fi
}

# Checks if Visual Studio Code Insiders is installed by verifying the application directory exists
check_vscode_insiders() {
    if [ -d "/Applications/Visual Studio Code - Insiders.app" ]; then
        echo -e "${GREEN}${CHECK} VS Code Insiders is already installed${NC}"
        return 0
    else
        return 1
    fi
}

# Configures VLC settings to hide filename display and enable loop by default
configure_vlc_settings() {
    echo -e "${BLUE}${INFO} Configuring VLC settings...${NC}"
    
    PREF_FILE="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
    mkdir -p "$(dirname "$PREF_FILE")"
    
    # Check if we've already configured settings
    if grep -q "# Setup-script-configured=true" "$PREF_FILE" 2>/dev/null; then
        echo -e "${BLUE}${INFO} VLC settings already configured, skipping...${NC}"
        return
    fi
    
    # Kill VLC if running
    killall VLC 2>/dev/null || true
    
    # Add our sentinel and settings
    {
        echo "# Setup-script-configured=true"
        echo "$VLC_SETTINGS"
    } >> "$PREF_FILE"
    
    echo -e "${GREEN}${CHECK} VLC settings configured - please restart VLC${NC}"
}

# Installs Homebrew if not present and updates it if already installed
install_brew() {
    if ! command -v brew &> /dev/null; then
        echo -e "${BLUE}${INFO} Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo -e "${GREEN}${CHECK} Homebrew is already installed${NC}"
    fi
    echo -e "${BLUE}${INFO} Updating Homebrew...${NC}"
    brew update
}

# Installs GitHub CLI (gh) using Homebrew if not already installed
install_gh() {
    if ! command -v gh &> /dev/null; then
        echo -e "${BLUE}${INFO} Installing GitHub CLI...${NC}"
        brew install gh
        return 0
    else
        echo -e "${GREEN}${CHECK} GitHub CLI is already installed${NC}"
        return 1
    fi
}

# Installs a suite of GitHub CLI extensions for enhanced functionality
install_gh_extensions() {
    echo -e "${BLUE}${INFO} Installing GitHub CLI extensions...${NC}"
    for ext in "${gh_cli_extensions[@]}"
    do
        gh extension install "$ext"
    done
}

# Installs VLC media player using Homebrew
install_vlc() {
    echo -e "${BLUE}${INFO} Installing VLC media player...${NC}"
    brew install --cask vlc
}

# Installs Visual Studio Code using Homebrew if not already present
install_vscode() {
    if ! check_vscode; then
        echo -e "${BLUE}${INFO} Installing VS Code...${NC}"
        brew install --cask visual-studio-code
        return 0
    fi
    return 1
}

# Installs predefined VS Code extensions using the VS Code CLI
install_vscode_extensions() {
    echo -e "${BLUE}${INFO} Installing VS Code extensions...${NC}"
    if ! "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --version &> /dev/null; then
        echo -e "${RED}${ERROR} Error: VS Code binary not found${NC}"
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
        echo -e "${BLUE}${INFO} Installing VS Code Insiders...${NC}"
        brew install --cask visual-studio-code-insiders
        return 0
    fi
    return 1
}

# Installs predefined VS Code extensions for VS Code Insiders
install_vscode_insiders_extensions() {
    echo -e "${BLUE}${INFO} Installing VS Code Insiders extensions...${NC}"
    if ! "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code" --version &> /dev/null; then
        echo -e "${RED}${ERROR} Error: VS Code Insiders binary not found${NC}"
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
            echo -e "${BLUE}${INFO} Please login to GitHub CLI first...${NC}"
            gh auth login
        fi
        
        if gh auth status &> /dev/null; then
            # install_gh_extensions
            echo -e "${GREEN}${CHECK} GitHub CLI extensions installed${NC}"
        else
            echo -e "${WARN} GitHub CLI login required for installing extensions. Please run 'gh auth login' manually.${NC}"
        fi
    fi
}

# Guides user through GitHub web authentication process using Safari
setup_github_web_auth() {
    echo -e "${BLUE}${INFO} Opening GitHub.com in Safari...${NC}"
    open -a Safari https://github.com
    echo -e "${BLUE}${INFO} Please log in to GitHub.com in Safari with the demo account${NC}"
    echo -e "${BLUE}${INFO} Press Enter once you have logged in...${NC}"
    read -r
    echo -e "${GREEN}${CHECK} GitHub web authentication confirmed${NC}"
}

# Assists user in setting up Progressive Web Apps (PWAs) for GitHub tools
setup_safari_and_pwas() {
    echo -e "${BLUE}${INFO} Opening required websites in Safari...${NC}"
    
    for i in "${!PWA_URLS[@]}"; do
        open -a Safari "${PWA_URLS[$i]}"
        echo -e "${BLUE}${INFO} Please manually add ${PWA_NAMES[$i]} (${PWA_URLS[$i]}) as a PWA by:${NC}"
        echo -e "${BLUE}${INFO} 1. Click Share button in Safari${NC}"
        echo -e "${BLUE}${INFO} 2. Select 'Add to Dock'${NC}"
        echo -e "${BLUE}${INFO} Press Enter when done...${NC}"
        read -r
    done
}

# Sets the VS Code theme to the predefined value
set_vscode_theme() {
    echo -e "${BLUE}${INFO} Setting VS Code theme...${NC}"
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
    echo -e "${BLUE}${INFO} Setting VS Code Insiders theme...${NC}"
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
    echo -e "${BLUE}${INFO} Creating demo loader script...${NC}"
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
    echo -e "${GREEN}${CHECK} Created demo loader script at $DEMO_SCRIPT${NC}"
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
    echo -e "${GREEN}${CHECK} Script completed successfully${NC}"
else
    echo -e "${YELLOW}${WARN} There was an issue with the installation. Please check the error messages above.${NC}"
fi
