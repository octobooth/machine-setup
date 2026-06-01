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

# Returns 0 (true) if a package entry is "active" (should be installed). An entry
# is treated as disabled (returns non-zero) when it is empty/whitespace-only or its
# trimmed value begins with '#'. config.json can't carry real JSON comments, so we
# document and disable packages by prefixing their name with '# '.
is_active_package_entry() {
    local entry="$1"
    # Strip leading whitespace.
    local trimmed="${entry#"${entry%%[![:space:]]*}"}"
    [[ -n "$trimmed" ]] || return 1
    [[ "$trimmed" != \#* ]] || return 1
    return 0
}

# Trims leading and trailing whitespace from $1 and prints the result.
trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Mutable state
failed_items=()

# Per-run install choices for the optional editors (Neovim, IDEs).
# Default to true (so unattended runs install everything active, unchanged).
# Overridable via INSTALL_NEOVIM / INSTALL_JETBRAINS env vars or the interactive
# prompt. Per-run only; never persisted to setup state.
WANT_NEOVIM=true
WANT_JETBRAINS=true

# When true, the interactive sign-in checklist is skipped
SKIP_SIGNIN="${SKIP_SIGNIN:-false}"
for arg in "$@"; do
    case "$arg" in
        --skip-signin) SKIP_SIGNIN=true ;;
    esac
done

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
    while IFS= read -r line; do brew_casks+=("$line"); done < <(jq -r '.mac.packages.casks[] | if . == null then "" else . end' "$CONFIG_FILE")

    brew_formulas=()
    while IFS= read -r line; do brew_formulas+=("$line"); done < <(jq -r '.mac.packages.formulas[] | if . == null then "" else . end' "$CONFIG_FILE")

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
        # Skip disabled/documentation entries (those prefixed with '# ' in config.json).
        if ! is_active_package_entry "$cask"; then
            log_info "Skipping disabled package: $cask"
            continue
        fi

        # Honor the interactive IDE install choice.
        if [[ "$WANT_JETBRAINS" != "true" ]] && is_ide_cask "$(trim_ws "$cask")"; then
            log_info "Skipping IDE (not selected): $cask"
            continue
        fi

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
        # Skip disabled/documentation entries (those prefixed with '# ' in config.json).
        if ! is_active_package_entry "$formula"; then
            log_info "Skipping disabled package: $formula"
            continue
        fi

        # Honor the interactive Neovim install choice.
        if [[ "$WANT_NEOVIM" != "true" ]] && [[ "$(trim_ws "$formula")" == "neovim" ]]; then
            log_info "Skipping Neovim (not selected): $formula"
            continue
        fi

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

# Installs the official github/copilot.vim plugin into Neovim's native package
# start path so it loads automatically. Idempotent and never fatal.
install_neovim_copilot() {
    if [[ "$WANT_NEOVIM" != "true" ]]; then
        log_info "Neovim was not selected; skipping Copilot plugin setup."
        return 0
    fi

    log_info "Setting up Neovim GitHub Copilot plugin..."

    if ! command -v nvim &> /dev/null; then
        log_info "Neovim (nvim) not found on PATH; skipping Copilot plugin setup."
        return 0
    fi

    if ! command -v git &> /dev/null; then
        log_warn "git not found on PATH; cannot install Neovim Copilot plugin. Skipping."
        return 0
    fi

    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local target="$data_home/nvim/site/pack/github/start/copilot.vim"
    local parent
    parent="$(dirname "$target")"

    if [[ ! -d "$parent" ]]; then
        if ! mkdir -p "$parent"; then
            log_warn "Could not create Neovim plugin directory '$parent'."
            failed_items+=("Neovim Copilot plugin (mkdir)")
            return 0
        fi
    fi

    if [[ ! -d "$target" ]]; then
        if ! git clone --depth 1 https://github.com/github/copilot.vim "$target" 2>&1; then
            log_warn "Failed to clone Neovim Copilot plugin; continuing."
            failed_items+=("Neovim Copilot plugin (clone)")
            return 0
        fi
    elif [[ -d "$target/.git" ]]; then
        # Already a git checkout; refresh best-effort.
        if ! git -C "$target" pull --ff-only 2>&1; then
            log_warn "Could not update Neovim Copilot plugin (git pull failed); continuing."
        fi
    else
        log_warn "Neovim Copilot plugin path exists but is not a git repo; leaving it untouched: $target"
        return 0
    fi

    if ! command -v node &> /dev/null; then
        log_warn "Node.js (node) not found on PATH; Neovim Copilot may not work until Node is available."
    fi

    log_success "Neovim GitHub Copilot plugin ready"
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

# Opens a URL in the platform's default browser
open_url() {
    local url="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        open "$url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$url"
    else
        return 1
    fi
}

# Prints a numbered checklist header and waits for the user to confirm.
# $1 = index, $2 = total, $3 = surface name, $4 = manual hint,
# remaining args = command to launch the surface (run via "$@").
signin_step() {
    local index="$1" total="$2" name="$3" hint="$4"
    shift 4

    echo ""
    echo -e "${BLUE}[$index/$total] $name${NC}"

    if [[ $# -eq 0 ]]; then
        # Manual-only step: nothing to launch, just surface the instructions.
        [[ -n "$hint" ]] && log_info "$hint"
    elif "$@"; then
        [[ -n "$hint" ]] && log_info "$hint"
    else
        log_warn "Could not launch $name automatically."
        [[ -n "$hint" ]] && log_warn "Manual step: $hint"
    fi

    log_info "Press Enter once you've signed in to $name (or to skip)..."
    read -r
    log_success "$name - confirmed"
}

# Launch helpers for each surface (return non-zero on failure so signin_step
# can fall back to the manual hint).
launch_browser_signin() { open_url "https://github.com/login"; }

launch_copilot_cli_signin() {
    command -v copilot &> /dev/null || return 1
    if [[ "$OSTYPE" == darwin* ]]; then
        # Open the Copilot CLI in a new Terminal window so the user can run /login.
        osascript -e 'tell application "Terminal" to activate' \
                  -e 'tell application "Terminal" to do script "copilot"' &> /dev/null
    else
        # TODO: verify a reliable terminal launcher across Linux desktops.
        if command -v x-terminal-emulator &> /dev/null; then
            x-terminal-emulator -e copilot &> /dev/null &
        else
            return 1
        fi
    fi
}

launch_editor_signin() {
    # $1 = editor command (code / code-insiders)
    local cmd="$1"
    command -v "$cmd" &> /dev/null || return 1
    "$cmd" --command "github.copilot.signIn" &> /dev/null
}

launch_copilot_app_signin() {
    if [[ "$OSTYPE" == darwin* ]]; then
        open -a "GitHub Copilot"
    else
        # TODO: verify the Copilot desktop app launch target on Linux.
        if command -v github-copilot &> /dev/null; then
            github-copilot &> /dev/null &
        else
            return 1
        fi
    fi
}

launch_neovim_signin() {
    command -v nvim &> /dev/null || return 1
    if [[ "$OSTYPE" == darwin* ]]; then
        # Best-effort: open a new Terminal window running Neovim with Copilot setup.
        osascript -e 'tell application "Terminal" to activate' \
                  -e 'tell application "Terminal" to do script "nvim +\":Copilot setup\""' &> /dev/null
    else
        # TODO: verify a reliable terminal launcher across Linux desktops.
        if command -v x-terminal-emulator &> /dev/null; then
            x-terminal-emulator -e nvim +":Copilot setup" &> /dev/null &
        else
            return 1
        fi
    fi
}

# Returns 0 if the given Homebrew cask is a known IDE that gets a sign-in step.
# Covers the JetBrains family plus Google's Android Studio (which is IntelliJ-based
# and supports the GitHub Copilot plugin). Android Studio is matched explicitly so
# this never accidentally matches other Google casks like google-chrome.
is_ide_cask() {
    case "$1" in
        intellij-idea|intellij-idea-ce|pycharm|pycharm-ce|rider|webstorm|goland|clion|phpstorm|rubymine|datagrip|rustrover|android-studio)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# Maps an IDE Homebrew cask to a friendly display name. Unknown casks fall
# back to the raw cask name so we never crash.
ide_cask_display_name() {
    case "$1" in
        intellij-idea)     echo "IntelliJ IDEA Ultimate" ;;
        intellij-idea-ce)  echo "IntelliJ IDEA Community" ;;
        pycharm)           echo "PyCharm Professional" ;;
        pycharm-ce)        echo "PyCharm Community" ;;
        rider)             echo "Rider" ;;
        webstorm)          echo "WebStorm" ;;
        android-studio)    echo "Android Studio" ;;
        goland)            echo "GoLand" ;;
        clion)             echo "CLion" ;;
        phpstorm)          echo "PhpStorm" ;;
        rubymine)          echo "RubyMine" ;;
        datagrip)          echo "DataGrip" ;;
        rustrover)         echo "RustRover" ;;
        *)                 echo "$1" ;;
    esac
}

# Guides the user through signing in to every GitHub surface, one at a time.
# Order matters: the browser session is established first so the other tools
# inherit the correct account.
start_signin_checklist() {
    if [[ "$SKIP_SIGNIN" == "true" ]]; then
        log_info "Skipping sign-in checklist (--skip-signin was specified)."
        return 0
    fi

    # Only run when both stdin and stdout are TTYs (matches prompt_for_inputs).
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        log_info "Non-interactive session detected; skipping sign-in checklist."
        return 0
    fi

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}GitHub sign-in checklist${NC}"
    echo -e "${BLUE}Sign in to each surface one at a time.${NC}"
    echo -e "${BLUE}Order matters: the browser session is the source of truth others inherit.${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [[ -n "${DEMO_GH_USER:-}" ]]; then
        log_info "Expected demo account: $DEMO_GH_USER  (verify every surface signs in as this user)"
    else
        log_info "Tip: set DEMO_GH_USER to display the expected demo account here."
    fi

    # Build ordered, parallel arrays of step descriptors so [index/total] is always
    # correct as steps are added or removed. Each launcher is a command string
    # ("" for a manual-hint-only step); step_skip marks a step as already done.
    local step_names=()
    local step_hints=()
    local step_launchers=()
    local step_skip=()

    add_signin_step() {
        step_names+=("$1")
        step_hints+=("$2")
        step_launchers+=("$3")
        step_skip+=("${4:-false}")
    }

    # Web browser (establish the browser session first)
    add_signin_step "Web browser (github.com)" \
        "Open https://github.com/login and sign in as the demo account." \
        "launch_browser_signin"

    # GitHub CLI (skip if authenticate_gh already signed in)
    local gh_skip="false"
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        gh_skip="true"
    fi
    add_signin_step "GitHub CLI (gh)" \
        "Run 'gh auth login --web' and complete the device flow in the browser." \
        "gh auth login --web" \
        "$gh_skip"

    # Copilot CLI (first-run device flow via /login)
    add_signin_step "Copilot CLI (copilot)" \
        "In the Copilot CLI window, run the '/login' slash command to authenticate." \
        "launch_copilot_cli_signin"

    # VS Code
    add_signin_step "VS Code" \
        "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left)." \
        "launch_editor_signin code"

    # VS Code Insiders
    add_signin_step "VS Code Insiders" \
        "If Copilot doesn't prompt, sign in via the Accounts menu (bottom-left)." \
        "launch_editor_signin code-insiders"

    # Neovim (only when selected and nvim is installed)
    if [[ "$WANT_NEOVIM" == "true" ]] && command -v nvim &> /dev/null; then
        add_signin_step "Neovim" \
            "Inside Neovim, run ':Copilot setup' to authenticate. If you signed in to the Copilot CLI above, Neovim may already be signed in via the shared token at ~/.config/github-copilot." \
            "launch_neovim_signin"
    fi

    # IDEs (dynamic from active config casks; manual-hint only). Commenting
    # out an IDE in config also removes its checklist step automatically.
    if [[ "$WANT_JETBRAINS" == "true" ]]; then
        local cask ide_name
        for cask in "${brew_casks[@]}"; do
            is_active_package_entry "$cask" || continue
            cask="$(trim_ws "$cask")"
            is_ide_cask "$cask" || continue
            ide_name="$(ide_cask_display_name "$cask")"
            add_signin_step "$ide_name" \
                "Open $ide_name, install the GitHub Copilot plugin (Settings/Preferences > Plugins > Marketplace > search 'GitHub Copilot'), then sign in to Copilot inside the IDE." \
                ""
        done
    fi

    # Copilot desktop app (keep last)
    add_signin_step "Copilot app (desktop)" \
        "Launch the GitHub Copilot app and sign in inside the app." \
        "launch_copilot_app_signin"

    local total=${#step_names[@]}
    local i index name hint launcher skip
    for (( i=0; i<total; i++ )); do
        index=$(( i + 1 ))
        name="${step_names[$i]}"
        hint="${step_hints[$i]}"
        launcher="${step_launchers[$i]}"
        skip="${step_skip[$i]}"

        if [[ "$skip" == "true" ]]; then
            echo ""
            echo -e "${BLUE}[$index/$total] $name${NC}"
            log_success "$name - already authenticated, skipping"
            continue
        fi

        if [[ -z "$launcher" ]]; then
            signin_step "$index" "$total" "$name" "$hint"
        else
            local launcher_parts=()
            read -ra launcher_parts <<< "$launcher"
            signin_step "$index" "$total" "$name" "$hint" "${launcher_parts[@]}"
        fi
    done

    echo ""
    log_success "Sign-in checklist complete."
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

# Returns 0 if any of the given values (passed as args) contains a placeholder
mcp_values_have_placeholder() {
    if [[ ${#placeholders[@]} -eq 0 ]]; then
        return 1
    fi

    for value in "$@"; do
        for placeholder in "${placeholders[@]}"; do
            if [[ "$value" == *"$placeholder"* ]]; then
                return 0
            fi
        done
    done

    return 1
}

# Path to the per-machine setup state file (separate from checked-in config)
setup_state_path() {
    local copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
    echo "$copilot_home/machine-setup-state.json"
}

# Reads the setup state file into the global ADO_ORG_VALUE / ADO_ORG_MODE vars.
# Tolerates missing or corrupt state — warns and continues with defaults.
load_setup_state() {
    ADO_ORG_VALUE=""
    ADO_ORG_MODE=""
    VIDEO_SUBFOLDER_VALUE=""

    local state_path
    state_path=$(setup_state_path)
    [[ -f "$state_path" ]] || return 0

    if ! jq empty "$state_path" 2>/dev/null; then
        log_warn "Setup state file at $state_path is not valid JSON; ignoring"
        return 0
    fi

    ADO_ORG_VALUE=$(jq -r '.inputs.azure_devops_org.value // ""' "$state_path")
    ADO_ORG_MODE=$(jq -r '.inputs.azure_devops_org.mode // ""' "$state_path")
    # Re-sanitize cached value so a hand-edited state file can't inject
    VIDEO_SUBFOLDER_VALUE=$(sanitize_video_subfolder "$(jq -r '.inputs.video_subfolder.value // ""' "$state_path")")
}

# Atomically writes the current ADO_ORG_VALUE / ADO_ORG_MODE to the state file.
save_setup_state() {
    local state_path
    state_path=$(setup_state_path)
    local copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
    mkdir -p "$copilot_home"

    local existing='{}'
    if [[ -f "$state_path" ]] && jq empty "$state_path" 2>/dev/null; then
        existing=$(cat "$state_path")
    fi

    local updated
    updated=$(echo "$existing" | jq \
        --arg value "$ADO_ORG_VALUE" \
        --arg mode "$ADO_ORG_MODE" \
        --arg vsub "$VIDEO_SUBFOLDER_VALUE" \
        '.inputs //= {} | .inputs.azure_devops_org = {value: $value, mode: $mode} | .inputs.video_subfolder = {value: $vsub}')

    local tmp="${state_path}.tmp.$$"
    printf '%s\n' "$updated" > "$tmp" || { log_warn "Failed to write setup state"; rm -f "$tmp"; return 0; }
    if ! jq empty "$tmp" 2>/dev/null; then
        log_warn "Setup state write produced invalid JSON; discarding"
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$state_path"
    chmod 600 "$state_path" 2>/dev/null || true
}

# Prompts (when TTY) for inputs that vary per machine.
prompt_for_inputs() {
    load_setup_state
    prompt_for_ado_org
    prompt_for_video_subfolder
    prompt_for_optional_editors
}

# Resolves an install choice into the global named by $1 ("true"/"false").
# Precedence: env var override > interactive prompt (default yes) > non-interactive
# default yes (so piped/unattended runs install everything active, unchanged).
# Per-run only; never persisted. Args:
#   $1 = output global var name, $2 = question, $3 = env var name (for messages),
#   $4 = env state ("set"/"unset"), $5 = raw env value.
resolve_optional_editor_choice() {
    local out_var="$1" question="$2" env_name="$3" env_state="$4" raw="$5"
    local norm answer

    if [[ "$env_state" == "set" ]]; then
        norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
        norm="$(trim_ws "$norm")"
        case "$norm" in
            1|true|yes|y|on)  printf -v "$out_var" '%s' "true";  return 0 ;;
            0|false|no|n|off) printf -v "$out_var" '%s' "false"; return 0 ;;
            "") : ;;
            *) log_warn "Unrecognized value '$raw' for $env_name; ignoring it." ;;
        esac
    fi

    # Only prompt when both stdin and stdout are TTYs (matches prompt_for_inputs).
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        printf -v "$out_var" '%s' "true"
        return 0
    fi

    printf '%s [Y/n]\n> ' "$question" >&2
    IFS= read -r answer || answer=""
    norm="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    norm="$(trim_ws "$norm")"
    case "$norm" in
        ""|y|yes) printf -v "$out_var" '%s' "true" ;;
        n|no)     printf -v "$out_var" '%s' "false" ;;
        *) log_warn "Unrecognized response '$answer'; defaulting to yes."
           printf -v "$out_var" '%s' "true" ;;
    esac
}

# Asks whether to install the optional editors (Neovim, IDEs). The
# results gate the install loop, the Neovim Copilot plugin, and the matching
# sign-in checklist steps. Choices are per-run only and never persisted.
prompt_for_optional_editors() {
    local nv_state="unset" nv_raw=""
    if [[ -n "${INSTALL_NEOVIM+x}" ]]; then nv_state="set"; nv_raw="$INSTALL_NEOVIM"; fi
    resolve_optional_editor_choice WANT_NEOVIM \
        "Install Neovim (and auto-configure its GitHub Copilot plugin)?" \
        "INSTALL_NEOVIM" "$nv_state" "$nv_raw"
    if [[ "$WANT_NEOVIM" == "true" ]]; then
        log_info "Neovim will be installed."
    else
        log_info "Skipping Neovim (and its Copilot plugin)."
    fi

    local jb_state="unset" jb_raw=""
    if [[ -n "${INSTALL_JETBRAINS+x}" ]]; then jb_state="set"; jb_raw="$INSTALL_JETBRAINS"; fi
    resolve_optional_editor_choice WANT_JETBRAINS \
        "Install IDEs (PyCharm, Rider, Android Studio)?" \
        "INSTALL_JETBRAINS" "$jb_state" "$jb_raw"
    if [[ "$WANT_JETBRAINS" == "true" ]]; then
        log_info "IDEs will be installed."
    else
        log_info "Skipping IDEs."
    fi
}

# Prompts (when TTY) for the Azure DevOps org. Sets ADO_ORG_VALUE
# and ADO_ORG_MODE ("configured", "skip", or "" = not answered).
#
# Precedence:
#   1. ADO_ORG env var (if set, including empty = explicit skip)
#   2. Interactive prompt with cached value as default
#   3. Cached value (when non-interactive)
#   4. Skip
prompt_for_ado_org() {
    # 1. Env var override (always wins; explicit empty = skip)
    if [[ -n "${ADO_ORG+x}" ]]; then
        local trimmed
        trimmed="${ADO_ORG#"${ADO_ORG%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ -z "$trimmed" ]]; then
            ADO_ORG_VALUE=""
            ADO_ORG_MODE="skip"
            log_info "ADO_ORG is empty in env; Azure DevOps MCP server will be skipped"
        else
            ADO_ORG_VALUE="$trimmed"
            ADO_ORG_MODE="configured"
            log_info "Using Azure DevOps org from ADO_ORG env var: $ADO_ORG_VALUE"
        fi
        save_setup_state
        return 0
    fi

    # 2. Interactive prompt (only when both stdin and stdout are TTYs)
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        local prompt_label="Azure DevOps organization name"
        local hint
        if [[ "$ADO_ORG_MODE" == "configured" ]] && [[ -n "$ADO_ORG_VALUE" ]]; then
            hint="[current: $ADO_ORG_VALUE; Enter to keep, '-' to clear]"
        else
            hint="(leave blank to skip the Azure DevOps MCP server)"
        fi

        local answer
        printf '%s %s\n> ' "$prompt_label" "$hint" >&2
        IFS= read -r answer || answer=""

        local trimmed
        trimmed="${answer#"${answer%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        if [[ -z "$trimmed" ]]; then
            if [[ "$ADO_ORG_MODE" == "configured" ]] && [[ -n "$ADO_ORG_VALUE" ]]; then
                log_info "Keeping cached Azure DevOps org: $ADO_ORG_VALUE"
            else
                ADO_ORG_VALUE=""
                ADO_ORG_MODE="skip"
                log_info "Azure DevOps MCP server will be skipped"
            fi
        elif [[ "$trimmed" == "-" ]]; then
            ADO_ORG_VALUE=""
            ADO_ORG_MODE="skip"
            log_info "Cleared Azure DevOps org; the MCP server will be skipped"
        else
            if [[ "$trimmed" == *" "* ]] || [[ "$trimmed" == *"/"* ]] || [[ "$trimmed" == *":"* ]]; then
                log_warn "Azure DevOps org '$trimmed' contains unusual characters; accepting anyway"
            fi
            ADO_ORG_VALUE="$trimmed"
            ADO_ORG_MODE="configured"
            log_success "Azure DevOps org set to: $ADO_ORG_VALUE"
        fi
        save_setup_state
        return 0
    fi

    # 3. Non-interactive: fall back to cached value if present
    if [[ "$ADO_ORG_MODE" == "configured" ]] && [[ -n "$ADO_ORG_VALUE" ]]; then
        log_info "Non-interactive run; using cached Azure DevOps org: $ADO_ORG_VALUE"
    elif [[ "$ADO_ORG_MODE" == "skip" ]]; then
        log_info "Non-interactive run; cached state says skip Azure DevOps MCP server"
    else
        log_info "Non-interactive run with no cached value; Azure DevOps MCP server will be skipped"
        ADO_ORG_VALUE=""
        ADO_ORG_MODE="skip"
    fi
}

# Sanitizes a video subfolder value. Echoes a safe relative subfolder, or "" for
# empty/unsafe input (path traversal, absolute paths, or quote chars). Any
# warning is sent to stderr so it does not pollute the captured value.
sanitize_video_subfolder() {
    local raw="$1"
    local v
    v="${raw#"${raw%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    [[ -z "$v" ]] && { echo ""; return; }
    # Normalize backslashes to forward slashes (loader uses POSIX paths)
    v="${v//\\//}"
    # Reject path traversal, drive-rooted (C:), UNC-style (//), shell metacharacters
    # ($ ` " expand inside the double-quoted loader string), or control chars
    if [[ "$v" == *".."* ]] || [[ "$v" =~ ^[A-Za-z]: ]] || [[ "$v" == //* ]] \
        || [[ "$v" == *'"'* ]] || [[ "$v" == *'$'* ]] || [[ "$v" == *'`'* ]] \
        || [[ "$v" == *[[:cntrl:]]* ]]; then
        log_warn "Video subfolder '$raw' looks unsafe (path traversal, absolute path, or special characters); using ~/Videos root" >&2
        echo ""
        return
    fi
    # Strip leading/trailing slashes and collapse duplicate separators
    v="${v#/}"
    v="${v%/}"
    while [[ "$v" == *"//"* ]]; do v="${v//\/\//\/}"; done
    echo "$v"
}

# Lists immediate subdirectory names under the given dir as a comma-separated
# string. Hint only; never required and never blocks.
list_video_subfolders() {
    local root="$1"
    [[ -d "$root" ]] || { echo ""; return; }
    local out="" d name
    for d in "$root"/*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        name="${d##*/}"
        if [[ -z "$out" ]]; then out="$name"; else out="$out, $name"; fi
    done
    echo "$out"
}

# Warns (but never fails) when the chosen subfolder is not yet present on disk.
warn_if_video_subfolder_missing() {
    local root="$1"
    [[ -n "$VIDEO_SUBFOLDER_VALUE" ]] || return 0
    if [[ ! -d "$root/$VIDEO_SUBFOLDER_VALUE" ]]; then
        log_warn "Videos subfolder '$VIDEO_SUBFOLDER_VALUE' not found yet under ~/Videos; make sure the videos are copied there before running the demo loader."
    fi
}

# Prompts (when TTY) for the per-machine video subfolder under ~/Videos.
# Sets VIDEO_SUBFOLDER_VALUE ("" = play ~/Videos root).
#
# Precedence:
#   1. VIDEO_SUBFOLDER env var (if set; empty/unsafe = root)
#   2. Interactive prompt with cached value as default
#   3. Cached value (when non-interactive)
#   4. Root ("")
prompt_for_video_subfolder() {
    local videos_root="$HOME/Videos"

    # 1. Env var override
    if [[ -n "${VIDEO_SUBFOLDER+x}" ]]; then
        VIDEO_SUBFOLDER_VALUE=$(sanitize_video_subfolder "$VIDEO_SUBFOLDER")
        if [[ -z "$VIDEO_SUBFOLDER_VALUE" ]]; then
            log_info "VIDEO_SUBFOLDER is empty; demo loader will play ~/Videos directly"
        else
            log_info "Using video subfolder from VIDEO_SUBFOLDER env var: $VIDEO_SUBFOLDER_VALUE"
        fi
        warn_if_video_subfolder_missing "$videos_root"
        save_setup_state
        return 0
    fi

    # 2. Interactive prompt (only when both stdin and stdout are TTYs)
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        local hint
        if [[ -n "$VIDEO_SUBFOLDER_VALUE" ]]; then
            hint="[current: $VIDEO_SUBFOLDER_VALUE; Enter to keep, '-' to clear to root]"
        else
            hint="(blank to play ~/Videos directly)"
        fi
        local available
        available=$(list_video_subfolders "$videos_root")
        if [[ -n "$available" ]]; then
            hint="$hint (available: $available)"
        fi

        local answer
        printf 'Video subfolder under ~/Videos to play %s\n> ' "$hint" >&2
        IFS= read -r answer || answer=""

        local trimmed
        trimmed="${answer#"${answer%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        if [[ -z "$trimmed" ]]; then
            if [[ -n "$VIDEO_SUBFOLDER_VALUE" ]]; then
                log_info "Keeping cached video subfolder: $VIDEO_SUBFOLDER_VALUE"
            else
                VIDEO_SUBFOLDER_VALUE=""
                log_info "Demo loader will play ~/Videos directly"
            fi
        elif [[ "$trimmed" == "-" ]]; then
            VIDEO_SUBFOLDER_VALUE=""
            log_info "Cleared video subfolder; demo loader will play ~/Videos directly"
        else
            VIDEO_SUBFOLDER_VALUE=$(sanitize_video_subfolder "$trimmed")
            if [[ -z "$VIDEO_SUBFOLDER_VALUE" ]]; then
                log_info "Demo loader will play ~/Videos directly"
            else
                log_success "Video subfolder set to: $VIDEO_SUBFOLDER_VALUE"
            fi
        fi
        warn_if_video_subfolder_missing "$videos_root"
        save_setup_state
        return 0
    fi

    # 3. Non-interactive: fall back to cached value if present
    if [[ -n "$VIDEO_SUBFOLDER_VALUE" ]]; then
        log_info "Non-interactive run; using cached video subfolder: $VIDEO_SUBFOLDER_VALUE"
    else
        log_info "Non-interactive run; demo loader will play ~/Videos directly"
    fi
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

        # Explicit skip: azure-devops requires a configured org
        if [[ "$name" == "azure-devops" ]] && [[ "$ADO_ORG_MODE" != "configured" || -z "$ADO_ORG_VALUE" ]]; then
            log_warn "Skipping MCP server 'azure-devops' (no Azure DevOps org configured — re-run setup to provide one or set ADO_ORG)"
            continue
        fi

        if [[ "$type" == "local" ]]; then
            local command args
            command=$(jq -r ".shared.mcp_servers[$i].command" "$CONFIG_FILE")
            args=$(jq -c ".shared.mcp_servers[$i].args" "$CONFIG_FILE")

            # Substitute placeholders in args using known inputs
            if [[ -n "$ADO_ORG_VALUE" ]]; then
                args=$(echo "$args" | jq --arg v "$ADO_ORG_VALUE" 'map(if . == "<YOUR-ADO-ORG>" then $v else . end)')
            fi

            # Defensive backstop: refuse to register if any placeholder slipped through
            local arg_strings
            arg_strings=$(echo "$args" | jq -r '.[]')
            local has_ph=0
            while IFS= read -r v; do
                if mcp_values_have_placeholder "$v"; then has_ph=1; break; fi
            done <<< "$arg_strings"
            if [[ "$has_ph" -eq 1 ]]; then
                log_warn "Skipping MCP server '$name' (placeholder still present after substitution)"
                continue
            fi

            existing=$(echo "$existing" | jq \
                --arg name "$name" \
                --arg type "$type" \
                --arg cmd "$command" \
                --argjson args "$args" \
                '.mcpServers[$name] = {"tools": ["*"], "type": $type, "command": $cmd, "args": $args}')
        else
            local url
            url=$(jq -r ".shared.mcp_servers[$i].url" "$CONFIG_FILE")

            if mcp_values_have_placeholder "$url"; then
                log_warn "Skipping MCP server '$name' (URL still contains a placeholder)"
                continue
            fi

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
EOF

    # Emit the VLC line outside the quoted heredoc so the chosen subfolder is
    # injected now while $HOME stays literal (resolved at loader runtime).
    if [[ -n "$VIDEO_SUBFOLDER_VALUE" ]]; then
        printf 'open -a VLC "$HOME/Videos/%s"\n' "$VIDEO_SUBFOLDER_VALUE" >> "$demo_script"
    else
        printf 'open -a VLC "$HOME/Videos"\n' >> "$demo_script"
    fi

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

# Prompt for per-machine inputs early, so the user isn't stuck waiting later
prompt_for_inputs

# Install packages
install_packages
install_neovim_copilot
install_aspire
install_npm_globals
configure_vlc

# Launch post-install apps (e.g., Docker)
launch_post_install_apps

# Setup environments
authenticate_gh
clone_repos
install_pwas

# Install extensions and configure themes
configure_editors

# Guided GitHub sign-in across all surfaces (browser first so others inherit the session)
start_signin_checklist

# Register MCP servers for Copilot CLI
register_mcp_servers

# Create demo loader script
create_demo_loader

# Print summary and finish
print_summary
if [[ ${#failed_items[@]} -gt 0 ]]; then
    log_warn "Script completed with ${#failed_items[@]} failure(s)"
    exit 1
fi
log_success "Script completed successfully"
