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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="$SCRIPT_DIR/config.json"
readonly DEMO_LAUNCHER_REPO="octobooth-demos/repo-setup-scripts"

# When true, skip detection is bypassed and everything is reinstalled
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"

# Release tag to pin repo-setup-scripts to: a moving major tag (v1) or a full version (v1.2.0). Empty tracks main.
BOOTH_RELEASE="${BOOTH_RELEASE:-}"

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

# How long to wait (in seconds) for the Xcode Command Line Tools installer
XCODE_CLT_TIMEOUT="${XCODE_CLT_TIMEOUT:-1800}"
XCODE_CLT_POLL_INTERVAL="${XCODE_CLT_POLL_INTERVAL:-10}"

# Returns 0 if the Xcode Command Line Tools are installed
xcode_clt_installed() {
    local clt_path
    clt_path=$(xcode-select -p 2>/dev/null) && [[ -d "$clt_path" ]]
}

# Installs the Xcode Command Line Tools if missing. On a new Mac, git is only a
# stub until they are installed, and Homebrew requires them too.
install_xcode_clt() {
    if xcode_clt_installed; then
        log_success "Xcode Command Line Tools are installed"
        return 0
    fi

    log_info "Installing Xcode Command Line Tools (needed for git and Homebrew)..."
    log_info "Click Install in the dialog that appears and accept the license. This can take several minutes."
    xcode-select --install &> /dev/null || true

    local waited=0
    until xcode_clt_installed; do
        if (( waited >= XCODE_CLT_TIMEOUT )); then
            log_error "Xcode Command Line Tools were not installed after ${XCODE_CLT_TIMEOUT}s."
            log_error "Run 'xcode-select --install', finish the installer, then run setup.sh again."
            exit 1
        fi
        sleep "$XCODE_CLT_POLL_INTERVAL"
        waited=$((waited + XCODE_CLT_POLL_INTERVAL))
    done

    log_success "Xcode Command Line Tools installed"
}

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

    VSCODE_THEME=$(jq -r '.shared.vscode_theme' "$CONFIG_FILE")
    readonly VSCODE_THEME
    VLC_SETTINGS=$(jq -r '.shared.vlc_settings' "$CONFIG_FILE")
    readonly VLC_SETTINGS
    ITERM2_LIGHT_PRESET=$(jq -r '.mac.iterm2.light.color_preset' "$CONFIG_FILE")
    readonly ITERM2_LIGHT_PRESET
    ITERM2_LIGHT_SCHEME_FILE="$SCRIPT_DIR/$(jq -r '.mac.iterm2.light.color_scheme_file' "$CONFIG_FILE")"
    readonly ITERM2_LIGHT_SCHEME_FILE
    ITERM2_DARK_PRESET=$(jq -r '.mac.iterm2.dark.color_preset' "$CONFIG_FILE")
    readonly ITERM2_DARK_PRESET
    ITERM2_DARK_SCHEME_FILE="$SCRIPT_DIR/$(jq -r '.mac.iterm2.dark.color_scheme_file' "$CONFIG_FILE")"
    readonly ITERM2_DARK_SCHEME_FILE
    ITERM2_FONT=$(jq -r '.mac.iterm2.font' "$CONFIG_FILE")
    readonly ITERM2_FONT
    ITERM2_THEME=$(jq -r '.mac.iterm2.theme // "regular"' "$CONFIG_FILE")
    readonly ITERM2_THEME
    ITERM2_LIGATURES=$(jq -r '.mac.iterm2.ligatures // false' "$CONFIG_FILE")
    readonly ITERM2_LIGATURES
    ITERM2_THIN_STROKES=$(jq -r '.mac.iterm2.thin_strokes // "retina-only"' "$CONFIG_FILE")
    readonly ITERM2_THIN_STROKES
    MONASPACE_FROZEN_VERSION=$(jq -r '.mac.monaspace_frozen_version // empty' "$CONFIG_FILE")
    readonly MONASPACE_FROZEN_VERSION

    # Use read loop instead of mapfile for macOS bash 3.2 compatibility
    vs_code_extensions=()
    while IFS= read -r line; do vs_code_extensions+=("$line"); done < <(jq -r '.shared.vs_code_extensions[]' "$CONFIG_FILE")

    gh_cli_extensions=()
    while IFS= read -r line; do gh_cli_extensions+=("$line"); done < <(jq -r '.shared.gh_cli_extensions[]' "$CONFIG_FILE")

    brew_casks=()
    while IFS= read -r line; do brew_casks+=("$line"); done < <(jq -r '.mac.packages.casks[]' "$CONFIG_FILE")

    dock_apps=()
    while IFS= read -r line; do dock_apps+=("$line"); done < <(jq -r '.mac.dock_apps // [] | .[]' "$CONFIG_FILE")

    brew_formulas=()
    while IFS= read -r line; do brew_formulas+=("$line"); done < <(jq -r '.mac.packages.formulas[]' "$CONFIG_FILE")

    pwa_names=()
    while IFS= read -r line; do pwa_names+=("$line"); done < <(jq -r '.shared.pwa_sites[].name' "$CONFIG_FILE")

    pwa_urls=()
    while IFS= read -r line; do pwa_urls+=("$line"); done < <(jq -r '.shared.pwa_sites[].url' "$CONFIG_FILE")

    gh_auth_scopes=()
    while IFS= read -r line; do gh_auth_scopes+=("$line"); done < <(jq -r '.shared.gh_auth_scopes // [] | .[]' "$CONFIG_FILE")
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

# Returns 0 if a font with the given PostScript name is installed
font_installed() {
    [[ "$(osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSFont.fontWithNameSize('$1', 12).isNil()" 2>/dev/null)" == "false" ]]
}

# Installs the Monaspace "Frozen" fonts (fixed-feature TTFs, e.g.
# MonaspaceNeonFrozen-Regular) from the pinned githubnext/monaspace release.
# The font-monaspace cask doesn't include them.
install_monaspace_frozen() {
    local version="$MONASPACE_FROZEN_VERSION"
    local fonts_dir="$HOME/Library/Fonts"
    local marker="$fonts_dir/.monaspace-frozen-version"
    local url="https://github.com/githubnext/monaspace/releases/download/v$version/monaspace-frozen-v$version.zip"

    if [[ -z "$version" ]]; then
        log_info "No Monaspace Frozen version configured, skipping..."
        return 0
    fi

    if should_skip_installed && [[ "$(cat "$marker" 2>/dev/null)" == "$version" ]]; then
        log_success "Already installed: Monaspace Frozen fonts v$version"
        return 0
    fi

    log_info "Installing Monaspace Frozen fonts v$version..."
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! curl -fsSL -o "$tmp_dir/frozen.zip" "$url" || \
       ! unzip -q "$tmp_dir/frozen.zip" -d "$tmp_dir/fonts"; then
        log_error "Could not download Monaspace Frozen fonts from $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    mkdir -p "$fonts_dir"
    local font count=0
    while IFS= read -r -d '' font; do
        cp -f "$font" "$fonts_dir/" && count=$((count + 1))
    done < <(find "$tmp_dir/fonts" -name '*.ttf' -print0)
    rm -rf "$tmp_dir"

    if [[ $count -eq 0 ]]; then
        log_error "No fonts found in $url"
        return 1
    fi

    echo "$version" > "$marker"
    log_success "Installed $count Monaspace Frozen fonts (v$version)"
}

# Prints iTerm2's TabStyleWithAutomaticOption value for a theme name
# (Settings > Appearance > General > Theme), from iTermPreferencesTabStyle in
# iTerm2's sources/Settings/iTermPreferences.h
iterm2_theme_value() {
    case "$1" in
        light) echo 0 ;;
        dark) echo 1 ;;
        light-high-contrast) echo 2 ;;
        dark-high-contrast) echo 3 ;;
        regular) echo 4 ;;
        minimal) echo 5 ;;
        compact) echo 6 ;;
        *) return 1 ;;
    esac
}

# Prints iTerm2's "Thin Strokes" profile value for a setting name
# (Settings > Profiles > Text > Use thin strokes), from iTermThinStrokesSetting
# in iTerm2's sources/Settings/Profiles/ITAddressBookMgr.h
iterm2_thin_strokes_value() {
    case "$1" in
        never) echo 0 ;;
        retina-dark-backgrounds-only) echo 1 ;;
        dark-backgrounds-only) echo 2 ;;
        always) echo 3 ;;
        retina-only) echo 4 ;;
        *) return 1 ;;
    esac
}

# Writes a copy of an .itermcolors file with " (<suffix>)" appended to every
# color key, e.g. "Background Color (Light)", the keys iTerm2 reads when a
# profile uses separate colors for light and dark mode
iterm2_suffixed_scheme() {
    local scheme_file="$1" suffix="$2" out_file="$3"
    plutil -convert xml1 -o "$out_file" "$scheme_file" &&
        SUFFIX="$suffix" perl -pi -e 's/^\t<key>(.*)<\/key>$/\t<key>$1 ($ENV{SUFFIX})<\/key>/' "$out_file" &&
        plutil -lint -s "$out_file"
}

# Applies the configured light and dark color schemes, font, and theme to
# iTerm2. The default profile follows the macOS appearance (light scheme in
# light mode, dark scheme in dark mode) and both schemes are added to
# Settings > Profiles > Colors > Color Presets.
configure_iterm2() {
    local prefs_domain="com.googlecode.iterm2"
    local sentinel_key="MachineSetupITerm2Settings"
    local legacy_sentinel_key="MachineSetupColorPreset"
    local theme_key="TabStyleWithAutomaticOption"
    local plist_buddy="/usr/libexec/PlistBuddy"
    local light_preset_key=":Custom Color Presets:$ITERM2_LIGHT_PRESET"
    local dark_preset_key=":Custom Color Presets:$ITERM2_DARK_PRESET"
    local separate_colors_key="Use Separate Colors for Light and Dark Mode"

    local theme_value
    if ! theme_value=$(iterm2_theme_value "$ITERM2_THEME"); then
        log_error "Unknown iTerm2 theme '$ITERM2_THEME' in config.json"
        return 1
    fi

    local thin_strokes_value
    if ! thin_strokes_value=$(iterm2_thin_strokes_value "$ITERM2_THIN_STROKES"); then
        log_error "Unknown iTerm2 thin_strokes '$ITERM2_THIN_STROKES' in config.json"
        return 1
    fi

    if [[ "$ITERM2_LIGATURES" != "true" && "$ITERM2_LIGATURES" != "false" ]]; then
        log_error "iTerm2 ligatures must be true or false in config.json"
        return 1
    fi

    # Records every applied setting, so changing any of them in config.json
    # re-applies them on machines that were already set up
    local settings="light=$ITERM2_LIGHT_PRESET|dark=$ITERM2_DARK_PRESET|$ITERM2_FONT|$ITERM2_THEME|ligatures=$ITERM2_LIGATURES|thin_strokes=$ITERM2_THIN_STROKES"

    log_info "Configuring iTerm2 with $ITERM2_LIGHT_PRESET (light mode) and $ITERM2_DARK_PRESET (dark mode)..."

    if should_skip_installed && [[ "$(defaults read "$prefs_domain" "$sentinel_key" 2>/dev/null)" == "$settings" ]]; then
        log_info "iTerm2 already configured, skipping..."
        return 0
    fi

    # iTerm2 saves its in-memory profiles on quit, which would undo these changes
    if pgrep -xq iTerm2; then
        log_error "iTerm2 is running - quit it and re-run setup to apply the theme"
        return 1
    fi

    local scheme_file
    for scheme_file in "$ITERM2_LIGHT_SCHEME_FILE" "$ITERM2_DARK_SCHEME_FILE"; do
        if ! plutil -lint -s "$scheme_file"; then
            log_error "Invalid iTerm2 color scheme: $scheme_file"
            return 1
        fi
    done

    local color_keys=()
    while IFS= read -r line; do color_keys+=("$line"); done < <(
        { plutil -convert json -o - "$ITERM2_LIGHT_SCHEME_FILE" | jq -r 'keys[]'
          plutil -convert json -o - "$ITERM2_DARK_SCHEME_FILE" | jq -r 'keys[]'; } | sort -u)

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local prefs_file="$tmp_dir/iterm2.plist"
    local light_suffixed="$tmp_dir/light.plist"
    local dark_suffixed="$tmp_dir/dark.plist"

    if ! iterm2_suffixed_scheme "$ITERM2_LIGHT_SCHEME_FILE" Light "$light_suffixed" || \
       ! iterm2_suffixed_scheme "$ITERM2_DARK_SCHEME_FILE" Dark "$dark_suffixed"; then
        log_error "Could not prepare the light and dark iTerm2 color schemes"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! defaults export "$prefs_domain" "$prefs_file"; then
        log_error "Could not read iTerm2 preferences"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Use the current default profile, else the first profile, else create one
    # (iTerm2 only creates its own Default profile on first launch)
    local default_guid profile_index=-1 profile_guid="" i=0 guid
    default_guid=$("$plist_buddy" -c "Print ':Default Bookmark Guid'" "$prefs_file" 2>/dev/null || true)
    while guid=$("$plist_buddy" -c "Print ':New Bookmarks:$i:Guid'" "$prefs_file" 2>/dev/null); do
        if [[ $profile_index -lt 0 || "$guid" == "$default_guid" ]]; then
            profile_index=$i
            profile_guid="$guid"
        fi
        i=$((i + 1))
    done

    if [[ $profile_index -lt 0 ]]; then
        profile_index=0
        profile_guid=$(uuidgen)
        "$plist_buddy" -c "Add ':New Bookmarks' array" "$prefs_file" &> /dev/null || true
        "$plist_buddy" -c "Add ':New Bookmarks:0' dict" \
            -c "Add ':New Bookmarks:0:Name' string Default" \
            -c "Add ':New Bookmarks:0:Guid' string $profile_guid" "$prefs_file"
    fi

    # PlistBuddy can't overwrite with Add/Merge, so clear existing values first
    local profile=":New Bookmarks:$profile_index"
    local key
    for key in "${color_keys[@]}"; do
        "$plist_buddy" -c "Delete '$profile:$key'" \
            -c "Delete '$profile:$key (Light)'" \
            -c "Delete '$profile:$key (Dark)'" "$prefs_file" &> /dev/null || true
    done
    for key in "$separate_colors_key" "Normal Font" "ASCII Ligatures" "Thin Strokes"; do
        "$plist_buddy" -c "Delete '$profile:$key'" "$prefs_file" &> /dev/null || true
    done
    for key in ":Default Bookmark Guid" ":$sentinel_key" ":$legacy_sentinel_key" ":$theme_key" "$light_preset_key" "$dark_preset_key"; do
        "$plist_buddy" -c "Delete '$key'" "$prefs_file" &> /dev/null || true
    done
    "$plist_buddy" -c "Add ':Custom Color Presets' dict" "$prefs_file" &> /dev/null || true

    # The profile gets "(Light)" and "(Dark)" colors so it follows the macOS
    # appearance. The plain keys get the dark scheme as a fallback for iTerm2
    # versions without separate light/dark colors (before 3.5).
    # PlistBuddy aborts when given 15+ -c commands at once, so this is split.
    if ! "$plist_buddy" \
            -c "Merge '$ITERM2_DARK_SCHEME_FILE' '$profile'" \
            -c "Merge '$light_suffixed' '$profile'" \
            -c "Merge '$dark_suffixed' '$profile'" \
            -c "Add '$profile:$separate_colors_key' bool true" \
            -c "Add '$profile:Normal Font' string '$ITERM2_FONT'" \
            -c "Add '$profile:ASCII Ligatures' bool $ITERM2_LIGATURES" \
            -c "Add '$profile:Thin Strokes' integer $thin_strokes_value" \
            -c "Add ':Default Bookmark Guid' string $profile_guid" \
            "$prefs_file" || \
       ! "$plist_buddy" \
            -c "Add '$light_preset_key' dict" \
            -c "Merge '$ITERM2_LIGHT_SCHEME_FILE' '$light_preset_key'" \
            -c "Add '$dark_preset_key' dict" \
            -c "Merge '$ITERM2_DARK_SCHEME_FILE' '$dark_preset_key'" \
            -c "Add ':$theme_key' integer $theme_value" \
            -c "Add ':$sentinel_key' string '$settings'" \
            "$prefs_file" || \
       ! defaults import "$prefs_domain" "$prefs_file"; then
        log_error "Could not update iTerm2 preferences"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    if ! font_installed "${ITERM2_FONT% *}"; then
        log_warn "Font ${ITERM2_FONT% *} is not installed - iTerm2 will fall back to its default font"
    fi
    log_success "iTerm2 configured with $ITERM2_LIGHT_PRESET/$ITERM2_DARK_PRESET colors, $ITERM2_FONT, and the $ITERM2_THEME theme"
}

# Adds the apps in config.json's mac.dock_apps to the Dock and turns off
# "Show suggested and recent apps in Dock". Leaves everything else (including
# Downloads and Trash) alone. Apps already in the Dock are skipped even when
# FORCE_REINSTALL=true, because adding them again would create duplicate icons.
configure_dock() {
    local apps_dir="${APPLICATIONS_DIR:-/Applications}"
    local dock_changed=false
    local failed=false

    if ! command -v dockutil &> /dev/null; then
        log_warn "dockutil is not installed - add apps to the Dock manually"
        failed=true
    else
        local app app_path
        for app in "${dock_apps[@]}"; do
            app_path="$apps_dir/$app.app"
            if [[ ! -d "$app_path" ]]; then
                log_warn "$app not found at $app_path - skipping Dock icon"
                failed=true
            elif dockutil --find "$app" &> /dev/null; then
                log_success "$app is already in the Dock"
            elif dockutil --add "$app_path" --no-restart &> /dev/null; then
                log_success "Added $app to the Dock"
                dock_changed=true
            else
                log_error "Could not add $app to the Dock"
                failed=true
            fi
        done
    fi

    if [[ "$(defaults read com.apple.dock show-recents 2>/dev/null)" == "0" ]]; then
        log_success "Suggested and recent apps are already hidden in the Dock"
    elif defaults write com.apple.dock show-recents -bool false; then
        log_success "Hid suggested and recent apps in the Dock"
        dock_changed=true
    else
        log_error "Could not hide suggested and recent apps in the Dock"
        failed=true
    fi

    if [[ "$dock_changed" == "true" ]]; then
        log_info "Restarting the Dock..."
        killall Dock 2>/dev/null || true
    fi

    [[ "$failed" == "false" ]]
}

# Prints the app bundle for casks that are often installed outside brew
cask_app_path() {
    case "$1" in
        google-chrome) echo "/Applications/Google Chrome.app" ;;
        github-copilot-app) echo "/Applications/GitHub Copilot.app" ;;
    esac
}

# Installs all Brew casks and formulas from config.json
# Note: brew install is idempotent — no need to pre-check installed packages.
# Chrome and the GitHub Copilot app are exceptions: they may be pre-installed
# outside brew (e.g., by MDM or manual download), so brew wouldn't detect them
# and would fail on conflict.
install_packages() {
    log_info "Installing Brew casks..."

    for cask in "${brew_casks[@]}"; do
        # Check the filesystem for apps that may be installed outside of brew
        local app_path
        app_path=$(cask_app_path "$cask")
        if should_skip_installed && [[ -n "$app_path" && -d "$app_path" ]]; then
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

# Path of the repo-setup-scripts checkout the Demo Launcher loader imports from
demo_launcher_repo_dir() {
    echo "$HOME/repos/${DEMO_LAUNCHER_REPO##*/}"
}

# Checks what the Demo Launcher needs (gh, git, jq and a gh login with the
# configured scopes). Login is interactive, so this only says what to run.
# Returns 1 if the launcher can't be installed yet.
check_demo_launcher_prereqs() {
    local cmd missing_cmds=()
    for cmd in gh git jq; do
        command -v "$cmd" &> /dev/null || missing_cmds+=("$cmd")
    done
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing ${missing_cmds[*]}. Install with: brew install gh jq"
        return 1
    fi

    local scopes
    scopes=$(IFS=,; echo "${gh_auth_scopes[*]}")
    if ! gh_stored_auth auth status -h github.com &> /dev/null; then
        log_error "GitHub CLI is not logged in. Run: gh auth login -h github.com${scopes:+ -s $scopes}"
        return 1
    fi

    local missing
    missing=$(gh_missing_scopes | paste -sd, -)
    if [[ -n "$missing" ]]; then
        log_warn "GitHub CLI login is missing scopes the demos need. Run: gh auth refresh -h github.com -s $missing"
    fi
}

# Returns 0 if the checkout at $1 has origin set to $DEMO_LAUNCHER_REPO on github.com
# (https or ssh, with or without .git), the only repo trusted to run in every Copilot session
demo_launcher_remote_trusted() {
    local url
    url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 1
    url=$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')
    url="${url%/}"
    url="${url%.git}"
    case "$url" in
        https://github.com/*) url="${url#https://github.com/}" ;;
        git@github.com:*) url="${url#git@github.com:}" ;;
        ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
        *) return 1 ;;
    esac
    [[ "$url" == "$(printf '%s' "$DEMO_LAUNCHER_REPO" | tr '[:upper:]' '[:lower:]')" ]]
}

# Returns 0 if the checkout at $1 has no uncommitted changes to tracked files
git_worktree_clean() {
    [[ -z "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)" ]]
}

# Prints how to clear local changes in the checkout at $1
log_local_changes_help() {
    local shown="${1/#$HOME/~}"
    log_error "${shown} has local changes:"
    git -C "$1" status --short --untracked-files=no >&2
    log_error "Save them with: git -C \"$shown\" stash   (or discard them with: git -C \"$shown\" checkout -- .), then re-run."
}

# Pins the checkout at $1 to event release tag $2 (detached HEAD).
# Returns 1, without changing the checkout, if the tag is missing or there are local changes.
checkout_booth_release() {
    local target="$1" ref="$2" shown="${1/#$HOME/~}"

    if [[ "$ref" == -* ]] || ! git check-ref-format "refs/tags/$ref"; then
        log_error "\"$ref\" isn't a valid tag name. Releases are tagged like v1 (latest tested v1.x.y) or v1.2.0."
        return 1
    fi

    log_info "Fetching release tags for $shown..."
    # --force so a moving major tag (v1) follows the remote when it's moved to a newer release
    if ! git -C "$target" fetch --quiet --tags --force origin; then
        log_error "Couldn't fetch tags for $shown. Check the network and the GitHub CLI login, then re-run."
        return 1
    fi

    # fetch --tags doesn't remove tags deleted on origin, so check origin still has it
    local remote_status=0
    git -C "$target" ls-remote --quiet --exit-code --tags origin "refs/tags/$ref" > /dev/null || remote_status=$?
    if [[ $remote_status -eq 2 ]]; then
        if git -C "$target" tag -d "$ref" > /dev/null 2>&1; then
            log_error "Release tag $ref isn't on GitHub (it may have been withdrawn), so its local copy was removed. Use the major the booth uses (currently v1), or run without a release to track main."
        else
            log_error "Release tag $ref doesn't exist in $DEMO_LAUNCHER_REPO. Use the major the booth uses (currently v1), or run without a release to track main."
        fi
        return 1
    elif [[ $remote_status -ne 0 ]]; then
        log_error "Couldn't check $DEMO_LAUNCHER_REPO for release tag $ref. Check the network and the GitHub CLI login, then re-run."
        return 1
    fi

    if ! git -C "$target" rev-parse --quiet --verify "refs/tags/$ref^{commit}" > /dev/null; then
        log_error "Release tag $ref doesn't exist in $DEMO_LAUNCHER_REPO. Use the major the booth uses (currently v1), or run without a release to track main."
        return 1
    fi

    if ! git_worktree_clean "$target"; then
        log_local_changes_help "$target"
        return 1
    fi

    git -C "$target" checkout --quiet --detach "refs/tags/$ref" || return 1
    log_success "$shown pinned to release $ref"
}

# If the checkout at $1 is on a detached HEAD (pinned to a release earlier),
# switches it back to its default branch so it tracks main again
return_to_default_branch() {
    local target="$1" shown="${1/#$HOME/~}" branch pinned

    git -C "$target" symbolic-ref --quiet HEAD > /dev/null && return 0

    branch=$(git -C "$target" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    branch="${branch#origin/}"
    branch="${branch:-main}"
    pinned=$(git -C "$target" describe --tags --exact-match HEAD 2>/dev/null || git -C "$target" rev-parse --short HEAD)

    if ! git_worktree_clean "$target"; then
        log_local_changes_help "$target"
        return 1
    fi

    log_info "$shown was pinned to $pinned; switching back to $branch to track the latest changes"
    git -C "$target" checkout --quiet "$branch"
}

# Clones repo-setup-scripts, or updates an existing checkout so the loader
# (which imports from it) picks up Demo Launcher updates. With BOOTH_RELEASE
# set, pins the checkout to that event release tag instead of tracking main.
# Returns 1 if the checkout couldn't be put on the requested release or branch.
sync_demo_launcher_repo() {
    local target shown
    target=$(demo_launcher_repo_dir)
    shown="${target/#$HOME/~}"

    local fresh_clone=false
    if [[ ! -d "$target/.git" ]]; then
        mkdir -p "$(dirname "$target")"
        try_install "clone: $DEMO_LAUNCHER_REPO" gh repo clone "$DEMO_LAUNCHER_REPO" "$target"
        [[ -d "$target/.git" ]] || return 1
        fresh_clone=true
    fi

    # Checked before any fetch, pull, or checkout, and before install.sh runs from the checkout
    if ! demo_launcher_remote_trusted "$target"; then
        failed_items+=("update: $DEMO_LAUNCHER_REPO ($shown origin isn't $DEMO_LAUNCHER_REPO)")
        log_error "$shown doesn't point at $DEMO_LAUNCHER_REPO, so it wasn't updated and the Demo Launcher wasn't installed. Check: git -C \"$shown\" remote -v"
        return 1
    fi
    [[ "$fresh_clone" == true && -z "$BOOTH_RELEASE" ]] && return 0

    if [[ -n "$BOOTH_RELEASE" ]]; then
        if ! checkout_booth_release "$target" "$BOOTH_RELEASE"; then
            failed_items+=("release: $DEMO_LAUNCHER_REPO at $BOOTH_RELEASE")
            return 1
        fi
        return 0
    fi

    if ! return_to_default_branch "$target"; then
        failed_items+=("update: $DEMO_LAUNCHER_REPO (couldn't leave its pinned release)")
        return 1
    fi
    log_info "Updating $shown..."
    git -C "$target" pull --ff-only --quiet ||
        log_warn "Could not fast-forward $shown; using it as is"
}

# Makes the Demo Launcher canvas (from repo-setup-scripts) available in every
# Copilot session; skipped until the cloned repo ships the extension
install_demo_launcher() {
    local installer
    installer="$(demo_launcher_repo_dir)/.github/extensions/demo-launcher/install.sh"
    local loader="${COPILOT_HOME:-$HOME/.copilot}/extensions/demo-launcher/extension.mjs"

    if [[ -d "$(demo_launcher_repo_dir)/.git" ]]; then
        if ! sync_demo_launcher_repo; then
            log_error "Demo Launcher not updated, because repo-setup-scripts isn't at ${BOOTH_RELEASE:-its default branch}"
            return
        fi
    fi

    if [[ ! -f "$installer" ]]; then
        log_info "Demo Launcher not found in repo-setup-scripts, skipping..."
        return
    fi

    # A release run always rewrites the loader, so it matches the checked-out release
    if [[ -z "$BOOTH_RELEASE" ]] && should_skip_installed && [[ -f "$loader" ]]; then
        log_info "Demo Launcher already installed, skipping..."
        return
    fi

    log_info "Installing the Demo Launcher canvas for all Copilot sessions..."
    try_install "Demo Launcher" bash "$installer"
}

# User-level Copilot instructions that keep booth sessions away from npm and pip, which
# booth networks block. Only the block between these markers is managed; the rest of the
# user's copilot-instructions.md is left alone. setup.ps1 uses the same markers.
BOOTH_INSTRUCTIONS_SOURCE="$SCRIPT_DIR/copilot/booth-instructions.md"
readonly BOOTH_INSTRUCTIONS_BEGIN="<!-- BEGIN machine-setup booth instructions (managed by setup; changes inside this block are replaced) -->"
readonly BOOTH_INSTRUCTIONS_END="<!-- END machine-setup booth instructions -->"

booth_instructions_path() {
    echo "${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md"
}

# Prints $1 (an instructions file, which may be missing) with the managed block replaced by
# the current booth instructions, or appended if it has none. Returns 1, printing nothing,
# if the markers aren't a single BEGIN/END pair.
booth_instructions_content() {
    local existing="$1"
    local script='
        function strip(s) { sub(/\r$/, "", s); return s }
        function emit(   i) { print begin; for (i = 1; i <= n; i++) print src[i]; print end }
        BEGIN {
            while ((getline line < source) > 0) src[++n] = strip(line)
            close(source)
            while (n > 0 && src[n] ~ /^[ \t]*$/) n--
            if (only_block) { emit(); exit }
        }
        FNR == NR {
            l = strip($0)
            if (l == begin) { nb++; bl = FNR } else if (l == end) { ne++; el = FNR }
            next
        }
        FNR == 1 && (nb > 1 || nb != ne || el < bl) { bad = 1; exit 1 }
        skipping { if (strip($0) == end) skipping = 0; next }
        strip($0) == begin { emit(); skipping = 1; replaced = 1; next }
        { print; last = $0 }
        END {
            if (bad || only_block) exit bad
            if (!replaced) { if (last !~ /^[ \t\r]*$/) print ""; emit() }
        }'
    if [[ -s "$existing" ]]; then
        awk -v source="$BOOTH_INSTRUCTIONS_SOURCE" -v begin="$BOOTH_INSTRUCTIONS_BEGIN" \
            -v end="$BOOTH_INSTRUCTIONS_END" -v only_block=0 "$script" "$existing" "$existing"
    else
        awk -v source="$BOOTH_INSTRUCTIONS_SOURCE" -v begin="$BOOTH_INSTRUCTIONS_BEGIN" \
            -v end="$BOOTH_INSTRUCTIONS_END" -v only_block=1 "$script"
    fi
}

# Adds or refreshes the booth instructions block in the user-level Copilot instructions
install_booth_instructions() {
    local target shown content
    target="$(booth_instructions_path)"
    shown="${target/#$HOME/~}"

    if [[ ! -f "$BOOTH_INSTRUCTIONS_SOURCE" ]]; then
        log_error "$BOOTH_INSTRUCTIONS_SOURCE not found, so the Copilot booth instructions weren't installed"
        return 1
    fi
    if ! content="$(booth_instructions_content "$target")"; then
        log_error "$shown has unmatched machine-setup booth instructions markers. Remove them and re-run."
        return 1
    fi
    if [[ -f "$target" ]] && [[ "$(cat "$target")" == "$content" ]]; then
        log_success "Copilot booth instructions are up to date in $shown"
        return 0
    fi

    mkdir -p "$(dirname "$target")" || return 1
    printf '%s\n' "$content" > "$target" || return 1
    log_success "Copilot booth instructions written to $shown"
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

# Runs gh against the stored login: GH_TOKEN/GITHUB_TOKEN would override it
# (and make `gh auth refresh` refuse to run)
gh_stored_auth() {
    env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"
}

# Prints each configured gh_auth_scopes entry the stored login doesn't have
gh_missing_scopes() {
    local granted scope
    granted=$(gh_stored_auth auth status -h github.com 2>/dev/null | grep 'Token scopes:' || true)
    for scope in "${gh_auth_scopes[@]}"; do
        if [[ "$granted" != *"'$scope'"* ]]; then
            echo "$scope"
        fi
    done
}

# Ensures the GitHub CLI login has the configured scopes (codespace for
# Codespace demos, delete_repo for the Demo Launcher's cleanup, project for
# the Copilot Airways demo's GitHub Project and its cleanup, workflow for
# pushing .github/workflows files to demo repos)
ensure_gh_scopes() {
    if [[ ${#gh_auth_scopes[@]} -eq 0 ]]; then
        return 0
    fi

    local missing
    missing=$(gh_missing_scopes | paste -sd, -)
    if [[ -z "$missing" ]]; then
        log_success "GitHub CLI login has the required scopes"
        return 0
    fi

    log_info "Adding GitHub CLI scopes: $missing..."
    if ! gh_stored_auth auth refresh -h github.com -s "$missing"; then
        log_warn "Could not add scopes. Run 'gh auth refresh -h github.com -s $missing' manually."
        return 1
    fi
}

# Ensures user is authenticated with GitHub CLI and installs extensions if authenticated
authenticate_gh() {
    if command -v gh &> /dev/null; then
        if ! gh_stored_auth auth status -h github.com &> /dev/null; then
            log_info "Please login to GitHub CLI first..."
            local scope_args=()
            if [[ ${#gh_auth_scopes[@]} -gt 0 ]]; then
                scope_args=(-s "$(IFS=,; echo "${gh_auth_scopes[*]}")")
            fi
            gh_stored_auth auth login --web -h github.com "${scope_args[@]}"
        fi

        if gh_stored_auth auth status -h github.com &> /dev/null; then
            try_install "gh auth scopes: ${gh_auth_scopes[*]}" ensure_gh_scopes
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

# Returns 0 if Chrome is the default browser (defaultbrowser marks it with "*")
chrome_is_default_browser() {
    defaultbrowser 2>/dev/null | grep -Eq '^\* chrome$'
}

# Makes Google Chrome the default browser. Works whether Chrome was installed by
# this script or beforehand, as long as it has been launched once (which
# authenticate_github_web does) so it is registered with macOS.
set_default_browser_chrome() {
    if ! command -v defaultbrowser &> /dev/null; then
        log_warn "defaultbrowser is not installed - set Chrome as the default browser in System Settings > Desktop & Dock"
        return 1
    fi

    if chrome_is_default_browser; then
        log_success "Chrome is already the default browser"
        return 0
    fi

    log_info "Setting Chrome as the default browser..."
    if ! defaultbrowser chrome; then
        log_error "Could not set Chrome as the default browser"
        return 1
    fi

    log_info "Click \"Use Google Chrome\" in the macOS dialog, then press Enter..."
    read -r

    if ! chrome_is_default_browser; then
        log_warn "Chrome is not the default browser - set it in System Settings > Desktop & Dock"
        return 1
    fi

    log_success "Chrome is now the default browser"
}

# Assists user in setting up Progressive Web Apps (PWAs)
install_pwas() {
    log_info "PWA setup is currently disabled. See README for details."
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

# ----------------------------------------
# Playwright MCP bundle
# ----------------------------------------
# Booth machines can't reach the npm registry, so the Playwright MCP server comes prebuilt
# from this repo's releases. mcp-bundle/package.json pins the version, and the
# "Playwright MCP bundle" workflow publishes it as playwright-mcp-v<version>.

readonly PLAYWRIGHT_MCP_BUNDLE_REPO="octobooth-demos/machine-setup"
readonly PLAYWRIGHT_MCP_BROWSER="chrome"

playwright_mcp_bundle_version() {
    jq -r '.dependencies["@playwright/mcp"] // empty' "$SCRIPT_DIR/mcp-bundle/package.json" 2>/dev/null
}

playwright_mcp_dir() {
    echo "${COPILOT_HOME:-$HOME/.copilot}/mcp-servers/playwright"
}

playwright_mcp_cli() {
    echo "$(playwright_mcp_dir)/node_modules/@playwright/mcp/cli.js"
}

# Absolute path to node, loading nvm if it isn't on PATH yet. GUI apps don't read
# shell profiles, so the MCP config needs the absolute path.
find_node_bin() {
    if ! command -v node &> /dev/null; then
        local nvm_sh
        for nvm_sh in "${NVM_DIR:-$HOME/.nvm}/nvm.sh" /opt/homebrew/opt/nvm/nvm.sh /usr/local/opt/nvm/nvm.sh; do
            if [[ -s "$nvm_sh" ]]; then
                export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
                # shellcheck source=/dev/null
                . "$nvm_sh" &> /dev/null || true
                break
            fi
        done
    fi
    command -v node
}

# Copies one bundle file from a release URL or, for offline installs and tests, a local folder
# (PLAYWRIGHT_MCP_BUNDLE_URL)
fetch_playwright_mcp_file() {
    local source="$1" name="$2" dest_dir="$3"
    if [[ "$source" =~ ^https?:// ]]; then
        curl -fsSL --connect-timeout 15 --max-time 300 --retry 2 -o "$dest_dir/$name" "$source/$name"
    else
        cp "$source/$name" "$dest_dir/$name"
    fi
}

# Downloads, verifies, and unpacks the pinned bundle into ~/.copilot/mcp-servers/playwright.
# Never fails setup: it warns and skips if the bundle can't be installed.
install_playwright_mcp_bundle() {
    local version
    version=$(playwright_mcp_bundle_version)
    if [[ -z "$version" ]]; then
        log_warn "No Playwright MCP version pinned in mcp-bundle/package.json, skipping it"
        return 0
    fi

    local dest
    dest=$(playwright_mcp_dir)
    if should_skip_installed && [[ -f "$(playwright_mcp_cli)" ]] && \
        [[ "$(cat "$dest/.bundle-version" 2>/dev/null)" == "$version" ]]; then
        log_info "Playwright MCP $version already installed, skipping..."
        return 0
    fi

    local asset="playwright-mcp-$version.tgz"
    local source="${PLAYWRIGHT_MCP_BUNDLE_URL:-https://github.com/$PLAYWRIGHT_MCP_BUNDLE_REPO/releases/download/playwright-mcp-v$version}"
    log_info "Installing Playwright MCP $version..."

    # Stage next to the destination so the final move is a rename
    local parent tmp
    parent=$(dirname "$dest")
    if ! mkdir -p "$parent" || ! tmp=$(mktemp -d "$parent/.playwright-download.XXXXXX"); then
        log_warn "Couldn't create a staging folder in ${parent/#$HOME/~}, skipping Playwright MCP $version"
        return 0
    fi

    if ! fetch_playwright_mcp_file "$source" "$asset" "$tmp" || \
       ! fetch_playwright_mcp_file "$source" "$asset.sha256" "$tmp"; then
        log_warn "Couldn't download Playwright MCP $version from $source, skipping it"
        rm -rf "$tmp"
        return 0
    fi

    local expected actual
    expected=$(awk '{print $1; exit}' "$tmp/$asset.sha256")
    actual=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        log_warn "Playwright MCP $version download failed its checksum, skipping it"
        rm -rf "$tmp"
        return 0
    fi

    mkdir -p "$tmp/bundle"
    if ! tar -xzf "$tmp/$asset" -C "$tmp/bundle" || [[ ! -f "$tmp/bundle/node_modules/@playwright/mcp/cli.js" ]]; then
        log_warn "Couldn't unpack Playwright MCP $version, skipping it"
        rm -rf "$tmp"
        return 0
    fi
    echo "$version" > "$tmp/bundle/.bundle-version"

    # Keep the previous version until the new one is in place, so a failed move can't lose both
    local backup="$dest.old" had_previous=false
    rm -rf "$backup"
    if [[ -e "$dest" ]]; then
        if ! mv "$dest" "$backup"; then
            log_warn "Couldn't replace Playwright MCP in ${dest/#$HOME/~}, keeping the previous version"
            rm -rf "$tmp"
            return 0
        fi
        had_previous=true
    fi

    if ! mv "$tmp/bundle" "$dest"; then
        if [[ "$had_previous" == true ]]; then
            rm -rf "$dest"
            mv "$backup" "$dest"
            log_warn "Couldn't install Playwright MCP $version, keeping the previous version"
        else
            log_warn "Couldn't install Playwright MCP $version, skipping it"
        fi
        rm -rf "$tmp"
        return 0
    fi

    rm -rf "$backup" "$tmp"
    log_success "Installed Playwright MCP $version to ${dest/#$HOME/~}"
}

# Prints the mcp-config.json with the bundled Playwright server added, if it's installed.
# Leaves a playwright entry alone if someone set up their own.
add_playwright_mcp_server() {
    local existing="$1" cli node_bin
    cli=$(playwright_mcp_cli)
    if [[ ! -f "$cli" ]]; then
        echo "$existing"
        return 0
    fi

    if ! node_bin=$(find_node_bin) || [[ -z "$node_bin" ]]; then
        log_warn "Node.js not found, so the Playwright MCP server wasn't registered" >&2
        echo "$existing"
        return 0
    fi

    if [[ "$(echo "$existing" | jq --arg cli "$cli" \
            '(.mcpServers.playwright? // null) as $p | $p != null and (($p.args? // [])[0]? // "") != $cli')" == "true" ]]; then
        log_info "Keeping your own 'playwright' MCP server entry" >&2
        echo "$existing"
        return 0
    fi

    echo "$existing" | jq --arg cmd "$node_bin" --arg cli "$cli" --arg browser "--browser=$PLAYWRIGHT_MCP_BROWSER" \
        '.mcpServers.playwright = {"tools": ["*"], "type": "local", "command": $cmd, "args": [$cli, $browser]}'
    log_success "Registered MCP server: playwright (prebuilt)" >&2
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

    # Earlier setups registered Playwright MCP via npx, which hangs where npm is blocked
    local stale_playwright_filter='(.mcpServers.playwright? // null) as $p
        | ($p | type) == "object" and $p.command == "npx"
          and (($p.args // []) | type) == "array"
          and (($p.args // []) | any(type == "string" and contains("@playwright/mcp")))'
    if [[ "$(echo "$existing" | jq "$stale_playwright_filter")" == "true" ]]; then
        existing=$(echo "$existing" | jq 'del(.mcpServers.playwright)')
        log_success "Removed old Playwright MCP server (npx @playwright/mcp)"
    fi

    local server_count
    server_count=$(jq '.shared.mcp_servers | length' "$CONFIG_FILE")

    for i in $(seq 0 $((server_count - 1))); do
        local name type
        name=$(jq -r ".shared.mcp_servers[$i].name" "$CONFIG_FILE")
        type=$(jq -r ".shared.mcp_servers[$i].type" "$CONFIG_FILE")

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

    existing=$(add_playwright_mcp_server "$existing")

    echo "$existing" | jq . > "$mcp_config"
    log_success "MCP servers written to $mcp_config"
}

# ----------------------------------------
# Main Execution
# ----------------------------------------

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ref) [[ -n "${2:-}" ]] || { echo "Usage: ./setup.sh [--ref v1]" >&2; exit 2; }
                BOOTH_RELEASE="$2"; shift 2 ;;
            --ref=*) BOOTH_RELEASE="${1#--ref=}"; shift ;;
            -h|--help) echo "Usage: ./setup.sh [--ref v1]"; return ;;
            *) echo "Usage: ./setup.sh [--ref v1]" >&2; exit 2 ;;
        esac
    done
    [[ -n "$BOOTH_RELEASE" ]] && log_info "Using event release $BOOTH_RELEASE of $DEMO_LAUNCHER_REPO"

    # Bootstrap: install Xcode CLT (for git), homebrew, and jq before loading config
    install_xcode_clt
    install_homebrew
    install_jq
    load_config

    # Install packages
    install_packages
    configure_vlc
    try_install "Monaspace Frozen fonts" install_monaspace_frozen
    try_install "iTerm2 theme: $ITERM2_LIGHT_PRESET/$ITERM2_DARK_PRESET" configure_iterm2
    try_install "Dock apps and settings" configure_dock

    # Launch post-install apps (e.g., Docker)
    launch_post_install_apps

    # Web authentication (after packages so Chrome is available)
    authenticate_github_web
    try_install "Chrome as default browser" set_default_browser_chrome

    # Setup environments
    authenticate_gh
    clone_repos
    install_demo_launcher
    try_install "Copilot booth instructions" install_booth_instructions

    # PWA setup is intentionally disabled until the booth workflow needs it again.
    # See README for the rationale and re-enable notes.
    # install_pwas

    # Install extensions and configure themes
    configure_editors

    # Register MCP servers for Copilot CLI, including the prebuilt Playwright server
    install_playwright_mcp_bundle
    register_mcp_servers

    # Print summary and finish
    print_summary
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        log_warn "Script completed with ${#failed_items[@]} failure(s)"
        exit 1
    fi
    log_success "Script completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
