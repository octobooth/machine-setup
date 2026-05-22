#!/bin/bash
#
# Setup script for GitHub development environment
# Installs and configures VS Code, VS Code Insiders, and GitHub tooling
#

# ----------------------------------------
# Constants
# ----------------------------------------

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Emojis
readonly CHECK="✅"
readonly WARN="⚠️"
readonly INFO="ℹ️"
readonly ERROR="❌"

readonly CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/config.json"

# When true, skip detection is bypassed and everything is reinstalled
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"

# Returns 0 (true) if we should check for already-installed items
should_skip_installed() {
    [[ "$FORCE_REINSTALL" != "true" ]]
}

# Mutable state
failed_items=()

# ----------------------------------------
# Logging Helpers
# ----------------------------------------

log_info()    { echo -e "${BLUE}${INFO} $1${NC}"; }
log_success() { echo -e "${GREEN}${CHECK} $1${NC}"; }
log_warn()    { echo -e "${YELLOW}${WARN} $1${NC}"; }
log_error()   { echo -e "${RED}${ERROR} $1${NC}"; }

# Runs a command and tracks failures without stopping the script
# $1 = description for error reporting, remaining args = command to run
try_install() {
    local description="$1"
    shift

    if ! "$@" 2>&1; then
        failed_items+=("$description")
        log_error "Failed: $description"
    fi
}

# Prints a summary of any failed installations
print_summary() {
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        echo ""
        log_warn "The following items failed to install:"
        for item in "${failed_items[@]}"; do
            log_warn "  - $item"
        done
        echo ""
    fi
}

# ----------------------------------------
# Bootstrap
# ----------------------------------------

# Installs Homebrew if not present and updates it
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Add brew to PATH for this session (needed on Apple Silicon and fresh installs)
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if ! command -v brew &> /dev/null; then
        log_error "Homebrew installation failed — brew not found in PATH"
        exit 1
    fi

    log_success "Homebrew is available"
    log_info "Updating Homebrew..."
    brew update
}

# Ensures jq is installed (required to read config.json)
install_jq() {
    if ! command -v jq &> /dev/null; then
        log_info "Installing jq..."
        brew install jq
    fi
}

# Load configuration from JSON file (called after jq is available)
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    readonly VSCODE_THEME=$(jq -r '.shared.vscode_theme' "$CONFIG_FILE")
    readonly VLC_SETTINGS=$(jq -r '.shared.vlc_settings' "$CONFIG_FILE")

    # Use read loop instead of mapfile for macOS bash 3.2 compatibility
    vs_code_extensions=()
    while IFS= read -r line; do vs_code_extensions+=("$line"); done < <(jq -r '.shared.vs_code_extensions[]' "$CONFIG_FILE")

    gh_cli_extensions=()
    while IFS= read -r line; do gh_cli_extensions+=("$line"); done < <(jq -r '.shared.gh_cli_extensions[]' "$CONFIG_FILE")

    brew_casks=()
    while IFS= read -r line; do brew_casks+=("$line"); done < <(jq -r '.mac.packages.casks[]' "$CONFIG_FILE")

    brew_formulas=()
    while IFS= read -r line; do brew_formulas+=("$line"); done < <(jq -r '.mac.packages.formulas[]' "$CONFIG_FILE")

    pwa_names=()
    while IFS= read -r line; do pwa_names+=("$line"); done < <(jq -r '.shared.pwa_sites[].name' "$CONFIG_FILE")

    pwa_urls=()
    while IFS= read -r line; do pwa_urls+=("$line"); done < <(jq -r '.shared.pwa_sites[].url' "$CONFIG_FILE")

    demo_sites=()
    while IFS= read -r line; do demo_sites+=("$line"); done < <(jq -r '.shared.demo_sites[]' "$CONFIG_FILE")

    placeholders=()
    while IFS= read -r line; do placeholders+=("$line"); done < <(jq -r '.shared.placeholders // [] | .[]' "$CONFIG_FILE")

    npm_global_packages=()
    while IFS= read -r line; do npm_global_packages+=("$line"); done < <(jq -r '.shared.npm_global_packages // [] | .[]' "$CONFIG_FILE")
}

# ----------------------------------------
# Function Definitions
# ----------------------------------------

# Configures VLC settings to hide filename display and enable loop by default
configure_vlc() {
    log_info "Configuring VLC settings..."

    local pref_file="$HOME/Library/Preferences/org.videolan.vlc/vlcrc"
    mkdir -p "$(dirname "$pref_file")"

    # Check if we've already configured settings
    if should_skip_installed && grep -q "# Setup-script-configured=true" "$pref_file" 2>/dev/null; then
        log_info "VLC settings already configured, skipping..."
        return
    fi

    # Kill VLC if running
    killall VLC 2>/dev/null || true

    # Add our sentinel and settings
    {
        echo "# Setup-script-configured=true"
        echo "$VLC_SETTINGS"
    } >> "$pref_file"

    log_success "VLC settings configured - please restart VLC"
}

# Installs all Brew casks and formulas from config.json
# Note: brew install is idempotent — no need to pre-check installed packages.
# Chrome is an exception: it may be pre-installed outside brew (e.g., by MDM
# or manual download), so brew wouldn't detect it and would fail on conflict.
install_packages() {
    log_info "Installing Brew casks..."

    for cask in "${brew_casks[@]}"; do
        # Chrome may be installed outside of brew (MDM, manual download, etc.)
        # so we check the filesystem to avoid install conflicts
        if should_skip_installed && [[ "$cask" == "google-chrome" ]] && [[ -d "/Applications/Google Chrome.app" ]]; then
            log_success "Already installed: $cask (found in /Applications)"
            continue
        fi

        try_install "brew cask: $cask" brew install --cask "$cask"
    done

    log_info "Installing Brew formulas..."
    for formula in "${brew_formulas[@]}"; do
        try_install "brew formula: $formula" brew install "$formula"
    done

    # Configure nvm and install Node LTS
    if brew list nvm &> /dev/null; then
        log_info "Configuring nvm and installing Node LTS..."
        export NVM_DIR="$HOME/.nvm"
        mkdir -p "$NVM_DIR"
        # shellcheck disable=SC1091
        . "$(brew --prefix nvm)/nvm.sh"
        nvm install --lts
        log_success "Node LTS installed: $(node --version)"

        # Ensure nvm is loaded in future terminal sessions
        local shell_rc="$HOME/.zshrc"
        if ! grep -q 'NVM_DIR' "$shell_rc" 2>/dev/null; then
            log_info "Adding nvm config to $shell_rc..."
            {
                echo ''
                echo '# nvm (Node Version Manager)'
                echo 'export NVM_DIR="$HOME/.nvm"'
                echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"'
                echo '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"'
            } >> "$shell_rc"
            log_success "nvm config added to $shell_rc"
        fi
    fi
}

# Installs a suite of GitHub CLI extensions for enhanced functionality
install_gh_extensions() {
    log_info "Installing GitHub CLI extensions..."

    local installed_exts=""
    if should_skip_installed; then
        installed_exts=$(gh extension list 2>/dev/null | awk '{print $2}' || true)
    fi

    for ext in "${gh_cli_extensions[@]}"; do
        if should_skip_installed && echo "$installed_exts" | grep -qx "$ext"; then
            log_success "Already installed: $ext (gh extension)"
            continue
        fi

        try_install "gh extension: $ext" gh extension install "$ext"
    done
}

# Launches apps that need to run after package installation
launch_post_install_apps() {
    post_install_apps=()
    while IFS= read -r line; do post_install_apps+=("$line"); done < <(jq -r '.mac.post_install_launch[]' "$CONFIG_FILE")

    if [[ ${#post_install_apps[@]} -eq 0 ]]; then
        return
    fi

    log_info "Launching post-install apps..."

    for app in "${post_install_apps[@]}"; do
        log_info "Opening $app..."
        open -a "$app" || log_warn "Could not open $app"
    done
}

# Clones repos from config into ~/repos
clone_repos() {
    local repos_dir="$HOME/repos"

    repos=()
    while IFS= read -r line; do repos+=("$line"); done < <(jq -r '.shared.repos_to_clone[]' "$CONFIG_FILE")

    if [[ ${#repos[@]} -eq 0 ]]; then
        return
    fi

    log_info "Cloning repos into $repos_dir..."
    mkdir -p "$repos_dir"

    for repo in "${repos[@]}"; do
        local repo_name="${repo##*/}"
        local target="$repos_dir/$repo_name"

        if should_skip_installed && [[ -d "$target" ]]; then
            log_info "$repo_name already exists, skipping..."
        else
            try_install "clone: $repo" gh repo clone "$repo" "$target"
        fi
    done
}

# Installs VS Code extensions for a given editor
# $1 = display name, $2 = binary path
install_vscode_extensions() {
    local name="$1"
    local binary="$2"

    log_info "Installing $name extensions..."

    if ! "$binary" --version &> /dev/null; then
        log_error "Error: $name binary not found"
        return 1
    fi

    local installed_exts=""
    if should_skip_installed; then
        installed_exts=$("$binary" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    fi

    for ext in "${vs_code_extensions[@]}"; do
        local ext_lower
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

        if should_skip_installed && echo "$installed_exts" | grep -qx "$ext_lower"; then
            log_success "Already installed: $ext ($name extension)"
            continue
        fi

        # Attempt install; handle built-in conflicts gracefully
        # (e.g., Copilot is now bundled in VS Code/Insiders)
        local output
        output=$("$binary" --install-extension "$ext" 2>&1)
        if [[ $? -ne 0 ]]; then
            if echo "$output" | grep -q "built-in extension"; then
                log_success "Built-in: $ext ($name), skipping..."
            else
                failed_items+=("$name extension: $ext")
                log_error "Failed: $name extension: $ext"
            fi
        fi
    done
}

# Ensures user is authenticated with GitHub CLI and installs extensions if authenticated
authenticate_gh() {
    if command -v gh &> /dev/null; then
        if ! gh auth status &> /dev/null; then
            log_info "Please login to GitHub CLI first..."
            gh auth login --web
        fi

        if gh auth status &> /dev/null; then
            install_gh_extensions
            log_success "GitHub CLI extensions installed"
        else
            log_warn "GitHub CLI login required for installing extensions. Please run 'gh auth login' manually."
        fi
    fi
}

# Guides user through GitHub web authentication process using Chrome
authenticate_github_web() {
    log_info "Opening GitHub.com in Chrome..."
    open -a "Google Chrome" https://github.com

    log_info "Please log in to GitHub.com in Chrome with the demo account"
    log_info "Press Enter once you have logged in..."
    read -r

    log_success "GitHub web authentication confirmed"
}

# Assists user in setting up Progressive Web Apps (PWAs)
install_pwas() {
    log_info "Opening required websites in Chrome..."

    for i in "${!pwa_urls[@]}"; do
        open -a "Google Chrome" "${pwa_urls[$i]}"
        log_info "Please manually add ${pwa_names[$i]} (${pwa_urls[$i]}) as a PWA by:"
        log_info "1. Click the three-dot menu in Chrome"
        log_info "2. Select 'Install page as app...'"
        log_info "Press Enter when done..."
        read -r
    done
}

# Sets the VS Code theme for a given editor
# $1 = display name, $2 = settings dir name (e.g. "Code" or "Code - Insiders")
configure_vscode_theme() {
    local name="$1"
    local settings_dir="$2"
    local settings_file="$HOME/Library/Application Support/$settings_dir/User/settings.json"

    log_info "Setting $name theme..."
    mkdir -p "$(dirname "$settings_file")"

    if [[ ! -f "$settings_file" ]]; then
        echo "{\"workbench.colorTheme\": \"$VSCODE_THEME\"}" > "$settings_file"
    else
        local tmp_file
        tmp_file=$(mktemp)
        jq ". + {\"workbench.colorTheme\": \"$VSCODE_THEME\"}" "$settings_file" > "$tmp_file"
        mv "$tmp_file" "$settings_file"
    fi
}

# Installs extensions and configures themes for all editors in config.json
configure_editors() {
    local editor_count
    editor_count=$(jq '.mac.editors | length' "$CONFIG_FILE")

    for i in $(seq 0 $((editor_count - 1))); do
        local editor_name editor_binary editor_settings_dir
        editor_name=$(jq -r ".mac.editors[$i].name" "$CONFIG_FILE")
        editor_binary=$(jq -r ".mac.editors[$i].binary" "$CONFIG_FILE")
        editor_settings_dir=$(jq -r ".mac.editors[$i].settings_dir" "$CONFIG_FILE")

        install_vscode_extensions "$editor_name" "$editor_binary"
        configure_vscode_theme "$editor_name" "$editor_settings_dir"
    done
}

# Returns 0 if any arg/url of the MCP server at the given index matches a placeholder
mcp_server_has_placeholder() {
    local idx="$1"

    if [[ ${#placeholders[@]} -eq 0 ]]; then
        return 1
    fi

    local values
    values=$(jq -r ".shared.mcp_servers[$idx] | (.args // []) + [(.url // empty)] | .[]" "$CONFIG_FILE")

    while IFS= read -r value; do
        for placeholder in "${placeholders[@]}"; do
            if [[ "$value" == *"$placeholder"* ]]; then
                return 0
            fi
        done
    done <<< "$values"

    return 1
}

# Registers MCP servers in Copilot CLI config
register_mcp_servers() {
    local copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
    local mcp_config="$copilot_home/mcp-config.json"

    log_info "Registering MCP servers for Copilot CLI..."

    # Create config directory if needed
    mkdir -p "$copilot_home"

    # Start with existing config or empty object
    if [[ -f "$mcp_config" ]]; then
        local existing
        existing=$(cat "$mcp_config")
    else
        local existing='{"mcpServers":{}}'
    fi

    local server_count
    server_count=$(jq '.shared.mcp_servers | length' "$CONFIG_FILE")

    for i in $(seq 0 $((server_count - 1))); do
        local name type
        name=$(jq -r ".shared.mcp_servers[$i].name" "$CONFIG_FILE")
        type=$(jq -r ".shared.mcp_servers[$i].type" "$CONFIG_FILE")

        if mcp_server_has_placeholder "$i"; then
            log_warn "Skipping MCP server '$name' (contains placeholder value — edit config.json and re-run)"
            continue
        fi

        if [[ "$type" == "local" ]]; then
            local command args
            command=$(jq -r ".shared.mcp_servers[$i].command" "$CONFIG_FILE")
            args=$(jq -c ".shared.mcp_servers[$i].args" "$CONFIG_FILE")

            existing=$(echo "$existing" | jq \
                --arg name "$name" \
                --arg type "$type" \
                --arg cmd "$command" \
                --argjson args "$args" \
                '.mcpServers[$name] = {"tools": ["*"], "type": $type, "command": $cmd, "args": $args}')
        else
            local url
            url=$(jq -r ".shared.mcp_servers[$i].url" "$CONFIG_FILE")

            existing=$(echo "$existing" | jq \
                --arg name "$name" \
                --arg type "$type" \
                --arg url "$url" \
                '.mcpServers[$name] = {"tools": ["*"], "type": $type, "url": $url, "headers": {}}')
        fi

        log_success "Registered MCP server: $name"
    done

    echo "$existing" | jq . > "$mcp_config"
    log_success "MCP servers written to $mcp_config"
}

# Installs the Microsoft Aspire CLI via the official installer script
install_aspire() {
    if should_skip_installed && command -v aspire &> /dev/null; then
        log_success "Already installed: aspire CLI"
        return
    fi

    log_info "Installing Aspire CLI..."

    local tmp
    tmp=$(mktemp)
    if ! curl -fsSL https://aspire.dev/install.sh -o "$tmp"; then
        failed_items+=("aspire CLI: download failed")
        log_error "Failed to download Aspire installer"
        rm -f "$tmp"
        return
    fi

    try_install "aspire CLI: install" bash "$tmp"
    rm -f "$tmp"

    # Make aspire available in this shell + persist for future shells
    local aspire_bin="$HOME/.aspire/bin"
    if [[ -d "$aspire_bin" ]]; then
        export PATH="$aspire_bin:$PATH"

        local shell_rc="$HOME/.zshrc"
        if ! grep -q '\.aspire/bin' "$shell_rc" 2>/dev/null; then
            log_info "Adding Aspire CLI to PATH in $shell_rc..."
            {
                echo ''
                echo '# Aspire CLI'
                echo 'export PATH="$HOME/.aspire/bin:$PATH"'
            } >> "$shell_rc"
        fi
    fi

    if command -v aspire &> /dev/null; then
        log_success "Aspire CLI installed"
    else
        log_warn "Aspire installer ran but 'aspire' is not yet on PATH"
    fi
}

# Creates a demo loader script to launch all required applications and sites
create_demo_loader() {
    log_info "Creating demo loader script..."
    local demo_script="$HOME/Desktop/load-demos.sh"

    # Create the script header
    cat > "$demo_script" << 'EOF'
#!/bin/bash

EOF

    # Add the sites dynamically
    echo "# Open all required sites in Chrome" >> "$demo_script"
    printf 'open -a "Google Chrome" %s\n\n' "$(printf '"%s" ' "${demo_sites[@]}")" >> "$demo_script"

    # Add the remaining standard content
    cat >> "$demo_script" << 'EOF'
# Open VS Code and VS Code Insiders
open -a "Visual Studio Code"
open -a "Visual Studio Code - Insiders"

# Open VLC pointing to Videos folder
open -a VLC "$HOME/Videos"
EOF

    chmod +x "$demo_script"
    log_success "Created demo loader script at $demo_script"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

# Install npm packages globally (so MCP servers don't need npx at runtime)
install_npm_globals() {
    if [[ ${#npm_global_packages[@]} -eq 0 ]]; then
        return
    fi

    # nvm-installed node may not be on PATH yet in this shell; source nvm if available
    if ! command -v npm &> /dev/null; then
        export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
        local nvm_sh
        nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
        if [[ -s "$nvm_sh" ]]; then
            # shellcheck disable=SC1090
            . "$nvm_sh"
        fi
    fi

    if ! command -v npm &> /dev/null; then
        log_warn "npm not available; skipping global npm package install"
        failed_items+=("npm global packages: npm not on PATH")
        return
    fi

    log_info "Installing npm packages globally..."
    for pkg in "${npm_global_packages[@]}"; do
        try_install "npm global: $pkg" npm install -g "$pkg"
    done
}

# Bootstrap: install homebrew and jq before loading config
install_homebrew
install_jq
load_config

# Install packages
install_packages
install_aspire
install_npm_globals
configure_vlc

# Launch post-install apps (e.g., Docker)
launch_post_install_apps

# Web authentication (after packages so Chrome is available)
authenticate_github_web

# Setup environments
authenticate_gh
clone_repos
install_pwas

# Install extensions and configure themes
configure_editors

# Register MCP servers for Copilot CLI
register_mcp_servers

# Create demo loader script
create_demo_loader

# Print summary and finish
print_summary
if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    log_warn "Script completed with ${#FAILED_ITEMS[@]} failure(s)"
    exit 1
fi
log_success "Script completed successfully"
