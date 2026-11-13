#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    export HOME="$BATS_TEST_TMPDIR/home"
    export COPILOT_HOME="$HOME/.copilot"

    mkdir -p "$HOME/Desktop" "$HOME/.copilot" "$HOME/Library/Application Support/Code/User"
}

load_script() {
    source "$REPO_ROOT/setup.sh"
}

@test "sourcing setup.sh does not execute main" {
    load_script

    [[ ! -f "$COPILOT_HOME/mcp-config.json" ]]
}

@test "configure_vscode_theme merges theme into existing settings" {
    load_script
    load_config

    local settings_file="$HOME/Library/Application Support/Code/User/settings.json"
    printf '{"editor.fontSize":14}\n' > "$settings_file"

    configure_vscode_theme "VS Code" "Code"

    run jq -r '.["workbench.colorTheme"]' "$settings_file"
    [ "$status" -eq 0 ]
    [ "$output" = "Light 2026" ]

    run jq -r '.["editor.fontSize"]' "$settings_file"
    [ "$status" -eq 0 ]
    [ "$output" = "14" ]
}

@test "register_mcp_servers writes config for http servers" {
    load_script
    load_config

    register_mcp_servers

    local mcp_config="$COPILOT_HOME/mcp-config.json"
    [[ -f "$mcp_config" ]]

    run jq -r '.mcpServers["microsoft-learn"].url' "$mcp_config"
    [ "$status" -eq 0 ]
    [ "$output" = "https://learn.microsoft.com/api/mcp" ]

    run jq -r '.mcpServers | has("playwright")' "$mcp_config"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "register_mcp_servers removes the old npx Playwright entry and keeps others" {
    load_script
    load_config

    printf '%s\n' '{"someOtherSetting":true,"mcpServers":{"playwright":{"tools":["*"],"type":"local","command":"npx","args":["@playwright/mcp@latest"]},"custom":{"type":"http","url":"https://example.com/mcp"}}}' \
        > "$COPILOT_HOME/mcp-config.json"

    register_mcp_servers

    local mcp_config="$COPILOT_HOME/mcp-config.json"
    run jq -r '.mcpServers | has("playwright")' "$mcp_config"
    [ "$output" = "false" ]

    run jq -r '.mcpServers.custom.url' "$mcp_config"
    [ "$output" = "https://example.com/mcp" ]

    run jq -r '.someOtherSetting' "$mcp_config"
    [ "$output" = "true" ]
}

@test "register_mcp_servers keeps a custom Playwright entry that doesn't use npx" {
    load_script
    load_config

    printf '%s\n' '{"mcpServers":{"playwright":{"type":"local","command":"/usr/local/bin/playwright-mcp","args":["@playwright/mcp"]}}}' \
        > "$COPILOT_HOME/mcp-config.json"

    register_mcp_servers

    run jq -r '.mcpServers.playwright.command' "$COPILOT_HOME/mcp-config.json"
    [ "$output" = "/usr/local/bin/playwright-mcp" ]
}

# Builds a fake Playwright MCP release (tgz + .sha256) for the pinned version in $1
make_playwright_mcp_release() {
    local release_dir="$1" version
    version=$(playwright_mcp_bundle_version)
    local src="$BATS_TEST_TMPDIR/bundle-src"
    mkdir -p "$src/node_modules/@playwright/mcp" "$release_dir"
    echo "console.log('fake playwright mcp')" > "$src/node_modules/@playwright/mcp/cli.js"
    tar -czf "$release_dir/playwright-mcp-$version.tgz" -C "$src" node_modules
    (cd "$release_dir" && shasum -a 256 "playwright-mcp-$version.tgz" > "playwright-mcp-$version.tgz.sha256")
}

# Puts a fake node first on PATH so registration doesn't depend on the machine
use_fake_node() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/node"
    chmod +x "$BATS_TEST_TMPDIR/bin/node"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "install_playwright_mcp_bundle installs the pinned release and skips it next time" {
    load_script
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    export PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release"

    run install_playwright_mcp_bundle
    [ "$status" -eq 0 ]
    [[ -f "$COPILOT_HOME/mcp-servers/playwright/node_modules/@playwright/mcp/cli.js" ]]
    [ "$(cat "$COPILOT_HOME/mcp-servers/playwright/.bundle-version")" = "$(playwright_mcp_bundle_version)" ]

    run install_playwright_mcp_bundle
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]] || false

    # No staging folders are left behind
    [ "$(find "$COPILOT_HOME/mcp-servers" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]
}

@test "install_playwright_mcp_bundle warns and skips when the checksum doesn't match" {
    load_script
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    echo "0000  tampered" > "$BATS_TEST_TMPDIR/release/playwright-mcp-$(playwright_mcp_bundle_version).tgz.sha256"
    export PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release"

    run install_playwright_mcp_bundle
    [ "$status" -eq 0 ]
    [[ "$output" == *"checksum"* ]] || false
    [[ ! -e "$COPILOT_HOME/mcp-servers/playwright" ]]
}

@test "install_playwright_mcp_bundle downloads both assets from octobooth by default" {
    load_script
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    unset PLAYWRIGHT_MCP_BUNDLE_URL
    fetch_playwright_mcp_file() {
        printf '%s\n' "$1/$2" >> "$BATS_TEST_TMPDIR/downloads"
        cp "$BATS_TEST_TMPDIR/release/$2" "$3/$2"
    }

    install_playwright_mcp_bundle

    local version base
    version=$(playwright_mcp_bundle_version)
    base="https://github.com/octobooth/machine-setup/releases/download/playwright-mcp-v$version"
    [ "$(cat "$BATS_TEST_TMPDIR/downloads")" = "$(printf '%s\n' "$base/playwright-mcp-$version.tgz" "$base/playwright-mcp-$version.tgz.sha256")" ]
    [[ -f "$(playwright_mcp_cli)" ]]
}

@test "install_playwright_mcp_bundle keeps the previous version when the new one can't be moved into place" {
    load_script
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    export PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release"
    local dest="$COPILOT_HOME/mcp-servers/playwright"
    mkdir -p "$dest/node_modules/@playwright/mcp"
    echo "old" > "$dest/node_modules/@playwright/mcp/cli.js"
    echo "0.0.1" > "$dest/.bundle-version"

    # Fail only the move of the new bundle into place
    mv() {
        if [[ "$1" == */bundle ]]; then return 1; fi
        command mv "$@"
    }

    run install_playwright_mcp_bundle
    [ "$status" -eq 0 ]
    [[ "$output" == *"keeping the previous version"* ]] || false
    [[ "$output" != *"Installed Playwright MCP"* ]] || false
    [ "$(cat "$dest/.bundle-version")" = "0.0.1" ]
    [ "$(cat "$dest/node_modules/@playwright/mcp/cli.js")" = "old" ]
    # No backup or staging folders are left behind
    [ "$(find "$COPILOT_HOME/mcp-servers" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]
}

@test "install_playwright_mcp_bundle warns and skips when it can't create a staging folder, even under set -e" {
    load_script
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    export PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release"
    # A file where the mcp-servers folder should be makes mkdir fail
    echo "not a folder" > "$COPILOT_HOME/mcp-servers"

    run bash -c 'set -e; source "$1/setup.sh"; install_playwright_mcp_bundle; echo "still running"' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Couldn't create a staging folder"* ]] || false
    [[ "$output" == *"still running"* ]] || false
}

@test "install_playwright_mcp_bundle warns and skips when the download fails" {
    load_script
    export PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/missing"

    run install_playwright_mcp_bundle
    [ "$status" -eq 0 ]
    [[ "$output" == *"Couldn't download"* ]] || false
    [[ ! -e "$COPILOT_HOME/mcp-servers/playwright" ]]
}

@test "register_mcp_servers registers the installed Playwright bundle with node and Chrome" {
    load_script
    load_config
    use_fake_node
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release" install_playwright_mcp_bundle

    register_mcp_servers

    local mcp_config="$COPILOT_HOME/mcp-config.json"
    run jq -r '.mcpServers.playwright.command' "$mcp_config"
    [ "$output" = "$BATS_TEST_TMPDIR/bin/node" ]

    run jq -r '.mcpServers.playwright.args | join(" ")' "$mcp_config"
    [ "$output" = "$COPILOT_HOME/mcp-servers/playwright/node_modules/@playwright/mcp/cli.js --browser=chrome" ]
}

@test "register_mcp_servers doesn't replace a custom Playwright entry with the bundle" {
    load_script
    load_config
    use_fake_node
    make_playwright_mcp_release "$BATS_TEST_TMPDIR/release"
    PLAYWRIGHT_MCP_BUNDLE_URL="$BATS_TEST_TMPDIR/release" install_playwright_mcp_bundle
    printf '%s\n' '{"mcpServers":{"playwright":{"type":"local","command":"/opt/my-playwright","args":[]}}}' \
        > "$COPILOT_HOME/mcp-config.json"

    register_mcp_servers

    run jq -r '.mcpServers.playwright.command' "$COPILOT_HOME/mcp-config.json"
    [ "$output" = "/opt/my-playwright" ]
}

@test "try_install records failures without exiting" {
    load_script

    failed_items=()
    try_install "example failure" false

    [ "${#failed_items[@]}" -eq 1 ]
    [ "${failed_items[0]}" = "example failure" ]
}

@test "clone_repos skips repos that already exist" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$GH_LOG"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"

    mkdir -p "$HOME/repos/repo-setup-scripts" "$HOME/repos/tailspin-toys" "$HOME/repos/security-octo-supply"

    load_script
    load_config
    clone_repos

    [[ ! -f "$GH_LOG" ]]
}

stub_iterm2_tools() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export PREFS_STORE="$BATS_TEST_TMPDIR/iterm2-prefs.plist"
    export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults.log"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # defaults stub: back the preferences domain with a plain plist file
    cat > "$BATS_TEST_TMPDIR/bin/defaults" <<'EOF'
#!/bin/bash
echo "$*" >> "$DEFAULTS_LOG"
case "$1" in
    export)
        if [[ -f "$PREFS_STORE" ]]; then cp "$PREFS_STORE" "$3"; else plutil -create xml1 "$3"; fi ;;
    import)
        cp "$3" "$PREFS_STORE" ;;
    read)
        [[ -f "$PREFS_STORE" ]] && /usr/libexec/PlistBuddy -c "Print ':$3'" "$PREFS_STORE" ;;
esac
EOF
    # pgrep stub: iTerm2 is not running unless ITERM2_RUNNING=true
    cat > "$BATS_TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "$ITERM2_RUNNING" == "true" ]]
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/defaults" "$BATS_TEST_TMPDIR/bin/pgrep"
}

prefs_value() {
    /usr/libexec/PlistBuddy -c "Print '$1'" "$PREFS_STORE"
}

# Prints the Red Component of a profile/preset color, rounded to 4 places
red_component() {
    printf '%.4f' "$(prefs_value "$1:Red Component")"
}

@test "config installs iTerm2 and font casks" {
    run jq -e '.mac.packages.casks | index("iterm2") and index("font-sf-mono") and index("font-monaspace") and index("font-mona-sans")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]

    local mode
    for mode in light dark; do
        run plutil -lint -s "$REPO_ROOT/$(jq -r ".mac.iterm2.$mode.color_scheme_file" "$REPO_ROOT/config.json")"
        [ "$status" -eq 0 ]
    done
}

@test "config follows macOS appearance with GitHub Light and Dark Default" {
    run jq -r '.mac.iterm2.light.color_preset, .mac.iterm2.dark.color_preset' "$REPO_ROOT/config.json"
    [ "${lines[0]}" = "GitHub Light Default" ]
    [ "${lines[1]}" = "GitHub Dark Default" ]
}

@test "configure_iterm2 creates a themed Default profile on a fresh install" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2

    run prefs_value ":New Bookmarks:0:Name"
    [ "$output" = "Default" ]

    local guid
    guid=$(prefs_value ":New Bookmarks:0:Guid")
    run prefs_value ":Default Bookmark Guid"
    [ "$output" = "$guid" ]

    run red_component ":New Bookmarks:0:Background Color"
    [ "$output" = "0.0510" ]

    run red_component ":New Bookmarks:0:Background Color (Light)"
    [ "$output" = "1.0000" ]

    run red_component ":New Bookmarks:0:Background Color (Dark)"
    [ "$output" = "0.0510" ]

    run red_component ":New Bookmarks:0:Foreground Color (Light)"
    [ "$output" = "0.1216" ]

    run prefs_value ":New Bookmarks:0:Use Separate Colors for Light and Dark Mode"
    [ "$output" = "true" ]

    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "MonaspaceNeonFrozen-Regular 14" ]

    run red_component ":Custom Color Presets:GitHub Dark Default:Background Color"
    [ "$output" = "0.0510" ]

    run red_component ":Custom Color Presets:GitHub Light Default:Background Color"
    [ "$output" = "1.0000" ]
}

@test "configure_iterm2 applies theme to the existing default profile only" {
    stub_iterm2_tools
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy \
        -c "Add ':Default Bookmark Guid' string GUID-B" \
        -c "Add ':New Bookmarks' array" \
        -c "Add ':New Bookmarks:0' dict" \
        -c "Add ':New Bookmarks:0:Name' string Other" \
        -c "Add ':New Bookmarks:0:Guid' string GUID-A" \
        -c "Add ':New Bookmarks:1' dict" \
        -c "Add ':New Bookmarks:1:Name' string Default" \
        -c "Add ':New Bookmarks:1:Guid' string GUID-B" \
        "$PREFS_STORE"
    # Split across calls: PlistBuddy aborts when given 15+ -c commands at once
    /usr/libexec/PlistBuddy \
        -c "Add ':New Bookmarks:1:Columns' integer 120" \
        -c "Add ':New Bookmarks:1:Normal Font' string 'Monaco 12'" \
        -c "Add ':New Bookmarks:1:Use Separate Colors for Light and Dark Mode' bool false" \
        -c "Add ':New Bookmarks:1:Background Color' dict" \
        -c "Add ':New Bookmarks:1:Background Color:Red Component' real 0.98" \
        -c "Add ':New Bookmarks:1:Background Color (Light)' dict" \
        -c "Add ':New Bookmarks:1:Background Color (Light):Red Component' real 0.5" \
        -c "Add ':Custom Color Presets' dict" \
        -c "Add ':Custom Color Presets:Mine' dict" \
        "$PREFS_STORE"

    load_script
    load_config
    configure_iterm2

    run red_component ":New Bookmarks:1:Background Color"
    [ "$output" = "0.0510" ]

    run prefs_value ":New Bookmarks:1:Normal Font"
    [ "$output" = "MonaspaceNeonFrozen-Regular 14" ]

    run red_component ":New Bookmarks:1:Background Color (Light)"
    [ "$output" = "1.0000" ]

    run prefs_value ":New Bookmarks:1:Use Separate Colors for Light and Dark Mode"
    [ "$output" = "true" ]

    run prefs_value ":New Bookmarks:1:Columns"
    [ "$output" = "120" ]

    run prefs_value ":Default Bookmark Guid"
    [ "$output" = "GUID-B" ]

    run prefs_value ":New Bookmarks:0:Background Color"
    [ "$status" -ne 0 ]

    run prefs_value ":Custom Color Presets:Mine"
    [ "$status" -eq 0 ]
}

@test "configure_iterm2 skips when already configured unless forced" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2
    /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'Menlo 14'" "$PREFS_STORE"

    configure_iterm2
    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "Menlo 14" ]

    FORCE_REINSTALL=true
    configure_iterm2
    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "MonaspaceNeonFrozen-Regular 14" ]

    run prefs_value ":New Bookmarks:1"
    [ "$status" -ne 0 ]
}

@test "config uses Monaspace Neon Frozen 14 and the Minimal theme in iTerm2" {
    run jq -r '.mac.iterm2.font, .mac.iterm2.theme, .mac.monaspace_frozen_version' "$REPO_ROOT/config.json"
    [ "${lines[0]}" = "MonaspaceNeonFrozen-Regular 14" ]
    [ "${lines[1]}" = "minimal" ]
    [ "${lines[2]}" = "1.400" ]
}

@test "iterm2_theme_value matches iTerm2's tab style values" {
    load_script

    [ "$(iterm2_theme_value regular)" = "4" ]
    [ "$(iterm2_theme_value minimal)" = "5" ]
    [ "$(iterm2_theme_value compact)" = "6" ]

    run iterm2_theme_value bogus
    [ "$status" -ne 0 ]
}

@test "configure_iterm2 sets the Minimal theme" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2

    run prefs_value ":TabStyleWithAutomaticOption"
    [ "$output" = "5" ]
}

@test "configure_iterm2 re-applies on machines set up before the font and theme settings" {
    stub_iterm2_tools
    load_script
    load_config

    # A machine configured by the previous version of setup.sh
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy \
        -c "Add ':MachineSetupColorPreset' string 'GitHub Dark Default'" \
        -c "Add ':TabStyleWithAutomaticOption' integer 4" \
        -c "Add ':New Bookmarks' array" \
        -c "Add ':New Bookmarks:0' dict" \
        -c "Add ':New Bookmarks:0:Name' string Default" \
        -c "Add ':New Bookmarks:0:Guid' string GUID-A" \
        -c "Add ':New Bookmarks:0:Normal Font' string 'MonaspaceNeon-Regular 12'" \
        "$PREFS_STORE"

    configure_iterm2

    run prefs_value ":New Bookmarks:0:Normal Font"
    [ "$output" = "MonaspaceNeonFrozen-Regular 14" ]
    run prefs_value ":TabStyleWithAutomaticOption"
    [ "$output" = "5" ]
    run prefs_value ":MachineSetupColorPreset"
    [ "$status" -ne 0 ]
}

@test "configure_iterm2 fails on an unknown theme without changing preferences" {
    stub_iterm2_tools
    load_script
    ITERM2_LIGHT_PRESET="GitHub Light Default"
    ITERM2_LIGHT_SCHEME_FILE="$REPO_ROOT/iterm2/github-light-default.itermcolors"
    ITERM2_DARK_PRESET="GitHub Dark Default"
    ITERM2_DARK_SCHEME_FILE="$REPO_ROOT/iterm2/github-dark-default.itermcolors"
    ITERM2_FONT="MonaspaceNeonFrozen-Regular 14"
    ITERM2_THEME=bogus

    run configure_iterm2
    [ "$status" -eq 1 ]
    [[ ! -f "$PREFS_STORE" ]] || false
}

# Stubs curl to "download" a small zip shaped like monaspace-frozen-v*.zip
stub_frozen_download() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    export FROZEN_ZIP="$BATS_TEST_TMPDIR/frozen.zip"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/zip/Frozen Fonts/Monaspace Neon"
    echo font > "$BATS_TEST_TMPDIR/zip/Frozen Fonts/Monaspace Neon/MonaspaceNeonFrozen-Regular.ttf"
    echo font > "$BATS_TEST_TMPDIR/zip/Frozen Fonts/Monaspace Neon/MonaspaceNeonFrozen-Bold.ttf"
    (cd "$BATS_TEST_TMPDIR/zip" && zip -qr "$FROZEN_ZIP" "Frozen Fonts")

    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CURL_LOG"
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then cp "$FROZEN_ZIP" "$2"; exit 0; fi
    shift
done
exit 1
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "install_monaspace_frozen installs the pinned release once unless forced" {
    stub_frozen_download
    load_script
    load_config

    run install_monaspace_frozen
    [ "$status" -eq 0 ]
    [[ -f "$HOME/Library/Fonts/MonaspaceNeonFrozen-Regular.ttf" ]] || false
    [[ -f "$HOME/Library/Fonts/MonaspaceNeonFrozen-Bold.ttf" ]] || false
    [ "$(cat "$HOME/Library/Fonts/.monaspace-frozen-version")" = "1.400" ]

    run grep -cF "releases/download/v1.400/monaspace-frozen-v1.400.zip" "$CURL_LOG"
    [ "$output" = "1" ]

    run install_monaspace_frozen
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" = "1" ]

    FORCE_REINSTALL=true
    run install_monaspace_frozen
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" = "2" ]
}

@test "install_monaspace_frozen fails when the download fails" {
    stub_frozen_download
    rm -f "$FROZEN_ZIP"
    load_script
    load_config

    run install_monaspace_frozen
    [ "$status" -eq 1 ]
    [[ ! -f "$HOME/Library/Fonts/.monaspace-frozen-version" ]] || false
}

@test "config turns on ligatures and turns off thin strokes in iTerm2" {
    run jq -r '.mac.iterm2.ligatures, .mac.iterm2.thin_strokes' "$REPO_ROOT/config.json"
    [ "${lines[0]}" = "true" ]
    [ "${lines[1]}" = "never" ]
}

@test "iterm2_thin_strokes_value matches iTerm2's thin strokes values" {
    load_script

    [ "$(iterm2_thin_strokes_value never)" = "0" ]
    [ "$(iterm2_thin_strokes_value always)" = "3" ]
    [ "$(iterm2_thin_strokes_value retina-only)" = "4" ]

    run iterm2_thin_strokes_value bogus
    [ "$status" -ne 0 ]
}

@test "configure_iterm2 sets ligatures and thin strokes on the default profile" {
    stub_iterm2_tools
    load_script
    load_config

    configure_iterm2

    run prefs_value ":New Bookmarks:0:ASCII Ligatures"
    [ "$output" = "true" ]
    run prefs_value ":New Bookmarks:0:Thin Strokes"
    [ "$output" = "0" ]
}

@test "configure_iterm2 re-applies on machines set up before ligatures and thin strokes" {
    stub_iterm2_tools
    load_script
    load_config

    # A machine configured by the previous version of setup.sh
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy \
        -c "Add ':MachineSetupITerm2Settings' string 'GitHub Dark Default|MonaspaceNeonFrozen-Regular 14|minimal'" \
        -c "Add ':New Bookmarks' array" \
        -c "Add ':New Bookmarks:0' dict" \
        -c "Add ':New Bookmarks:0:Name' string Default" \
        -c "Add ':New Bookmarks:0:Guid' string GUID-A" \
        -c "Add ':New Bookmarks:0:ASCII Ligatures' bool false" \
        -c "Add ':New Bookmarks:0:Thin Strokes' integer 4" \
        "$PREFS_STORE"

    configure_iterm2

    run prefs_value ":New Bookmarks:0:ASCII Ligatures"
    [ "$output" = "true" ]
    run prefs_value ":New Bookmarks:0:Thin Strokes"
    [ "$output" = "0" ]

    : > "$DEFAULTS_LOG"
    configure_iterm2
    run grep -c '^import' "$DEFAULTS_LOG"
    [ "$output" = "0" ]
}

@test "configure_iterm2 re-applies on machines set up with only the dark scheme" {
    stub_iterm2_tools
    load_script
    load_config

    # A machine configured by the previous version of setup.sh
    plutil -create xml1 "$PREFS_STORE"
    /usr/libexec/PlistBuddy \
        -c "Add ':MachineSetupITerm2Settings' string 'GitHub Dark Default|MonaspaceNeonFrozen-Regular 14|minimal|ligatures=true|thin_strokes=never'" \
        -c "Add ':New Bookmarks' array" \
        -c "Add ':New Bookmarks:0' dict" \
        -c "Add ':New Bookmarks:0:Name' string Default" \
        -c "Add ':New Bookmarks:0:Guid' string GUID-A" \
        -c "Add ':New Bookmarks:0:Use Separate Colors for Light and Dark Mode' bool false" \
        "$PREFS_STORE"

    configure_iterm2

    run prefs_value ":New Bookmarks:0:Use Separate Colors for Light and Dark Mode"
    [ "$output" = "true" ]
    run red_component ":New Bookmarks:0:Background Color (Light)"
    [ "$output" = "1.0000" ]

    : > "$DEFAULTS_LOG"
    configure_iterm2
    run grep -c '^import' "$DEFAULTS_LOG"
    [ "$output" = "0" ]
}

@test "configure_iterm2 refuses to change preferences while iTerm2 is running" {
    stub_iterm2_tools
    export ITERM2_RUNNING=true
    load_script
    load_config

    run configure_iterm2
    [ "$status" -eq 1 ]
    [[ ! -f "$PREFS_STORE" ]]
}

@test "config installs the GitHub Copilot app on both platforms" {
    run jq -e '.mac.packages.casks | index("github-copilot-app")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]

    run jq -e '.windows.packages | index("GitHub.CopilotApp")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "config installs PowerShell 7 first on Windows" {
    run jq -e '.windows.packages[0] == "Microsoft.PowerShell"' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "config installs Git on Windows before cloning repos" {
    run jq -e '.windows.packages | index("Git.Git")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

# gh stub: reports the scopes in GH_SCOPES and logs every call with the
# GH_TOKEN/GITHUB_TOKEN values it saw
stub_gh_auth() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'STUB'
#!/bin/bash
echo "$* [GH_TOKEN=${GH_TOKEN-unset} GITHUB_TOKEN=${GITHUB_TOKEN-unset}]" >> "$GH_LOG"
if [[ "$1 $2" == "auth status" ]]; then
    echo "  - Token scopes: $GH_SCOPES"
fi
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
}

@test "ensure_gh_scopes refreshes only missing scopes using the stored login" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'gist', 'repo'"
    export GH_TOKEN="env-token" GITHUB_TOKEN="env-token"
    load_script
    load_config

    ensure_gh_scopes

    run grep -F 'auth refresh -h github.com -s delete_repo,project,workflow [GH_TOKEN=unset GITHUB_TOKEN=unset]' "$GH_LOG"
    [ "$status" -eq 0 ]

    run grep -F 'env-token' "$GH_LOG"
    [ "$status" -ne 0 ]
}

@test "ensure_gh_scopes does nothing when all scopes are granted" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'delete_repo', 'project', 'repo', 'workflow'"
    load_script
    load_config

    ensure_gh_scopes

    run grep -F 'auth refresh' "$GH_LOG"
    [ "$status" -ne 0 ]
}

@test "install_demo_launcher skips when repo-setup-scripts has no Demo Launcher" {
    load_script

    failed_items=()
    install_demo_launcher

    [ "${#failed_items[@]}" -eq 0 ]
    [[ ! -e "$COPILOT_HOME/extensions/demo-launcher" ]]
}

@test "install_demo_launcher runs install.sh once unless forced" {
    local ext_dir="$HOME/repos/repo-setup-scripts/.github/extensions/demo-launcher"
    mkdir -p "$ext_dir"
    cat > "$ext_dir/install.sh" <<'STUB'
#!/bin/bash
echo run >> "$INSTALL_LOG"
mkdir -p "$COPILOT_HOME/extensions/demo-launcher"
touch "$COPILOT_HOME/extensions/demo-launcher/extension.mjs"
STUB
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    install_demo_launcher
    install_demo_launcher
    [ "$(wc -l < "$INSTALL_LOG")" -eq 1 ]

    FORCE_REINSTALL=true
    install_demo_launcher
    [ "$(wc -l < "$INSTALL_LOG")" -eq 2 ]
}

# Points the checkout's origin at the trusted GitHub URL, and redirects git to the
# local test origin for that URL, so the origin check passes without network access
trust_test_origin() {
    local trusted="https://github.com/octobooth/repo-setup-scripts.git"
    git -C "$1" remote set-url origin "$trusted"
    git -C "$1" config "url.$2.insteadOf" "$trusted"
}

@test "install_demo_launcher fast-forwards an existing repo-setup-scripts clone" {
    local origin="$BATS_TEST_TMPDIR/origin.git"
    local repo="$HOME/repos/repo-setup-scripts"
    git init -q --bare "$origin"
    git clone -q "$origin" "$repo"
    trust_test_origin "$repo" "$origin"
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$repo" push -q origin HEAD

    local other="$BATS_TEST_TMPDIR/other"
    git clone -q "$origin" "$other"
    mkdir -p "$other/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$other/.github/extensions/demo-launcher/install.sh"
    git -C "$other" add -A
    git -C "$other" -c user.name=t -c user.email=t@t commit -q -m launcher
    git -C "$other" push -q origin HEAD

    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    install_demo_launcher

    [[ -f "$repo/.github/extensions/demo-launcher/install.sh" ]]
    [ "$(wc -l < "$INSTALL_LOG")" -eq 1 ]
}

# Creates a bare origin for repo-setup-scripts with a main branch, tags v1.0.0
# and a moving v1 on the first commit, and a newer untagged commit on main.
# Clones it into ~/repos/repo-setup-scripts at the first commit.
make_release_origin() {
    export RELEASE_ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    export RELEASE_WORK="$BATS_TEST_TMPDIR/work"
    export RELEASE_REPO="$HOME/repos/repo-setup-scripts"
    git -c init.defaultBranch=main init -q --bare "$RELEASE_ORIGIN"
    git clone -q "$RELEASE_ORIGIN" "$RELEASE_WORK" 2>/dev/null
    git -C "$RELEASE_WORK" checkout -q -b main
    echo one > "$RELEASE_WORK/file.txt"
    git -C "$RELEASE_WORK" add file.txt
    git -C "$RELEASE_WORK" -c user.name=t -c user.email=t@t commit -q -m one
    git -C "$RELEASE_WORK" tag v1.0.0
    git -C "$RELEASE_WORK" tag v1
    git -C "$RELEASE_WORK" push -q origin main --tags
    git clone -q "$RELEASE_ORIGIN" "$RELEASE_REPO"
    trust_test_origin "$RELEASE_REPO" "$RELEASE_ORIGIN"
    release_commit two
}

# Commits a change to main in the origin
release_commit() {
    echo "$1" > "$RELEASE_WORK/file.txt"
    git -C "$RELEASE_WORK" -c user.name=t -c user.email=t@t commit -q -am "$1"
    git -C "$RELEASE_WORK" push -q origin main
}

@test "sync_demo_launcher_repo pins repo-setup-scripts to a release tag" {
    make_release_origin
    load_script

    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    [ "$status" -eq 0 ]
    [[ "$output" == *"pinned to release v1"* ]] || false
    run git -C "$RELEASE_REPO" symbolic-ref -q HEAD
    [ "$status" -ne 0 ]
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$(git -C "$RELEASE_WORK" rev-parse v1.0.0)" ]
}

@test "sync_demo_launcher_repo follows a moved major tag" {
    make_release_origin
    load_script
    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    [ "$status" -eq 0 ]

    git -C "$RELEASE_WORK" tag v1.1.0
    git -C "$RELEASE_WORK" tag -f v1 > /dev/null
    git -C "$RELEASE_WORK" push -q origin v1.1.0
    git -C "$RELEASE_WORK" push -q -f origin v1

    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    [ "$status" -eq 0 ]
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$(git -C "$RELEASE_WORK" rev-parse v1.1.0)" ]
}

@test "sync_demo_launcher_repo fails clearly when the release tag doesn't exist" {
    make_release_origin
    load_script
    local before
    before=$(git -C "$RELEASE_REPO" rev-parse HEAD)

    BOOTH_RELEASE=v9 run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Release tag v9 doesn't exist"* ]] || false
    [ "$(git -C "$RELEASE_REPO" symbolic-ref --short HEAD)" = main ]
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$before" ]
}

@test "sync_demo_launcher_repo refuses a release tag withdrawn on origin" {
    make_release_origin
    load_script
    git -C "$RELEASE_REPO" fetch -q --tags origin
    git -C "$RELEASE_WORK" push -q origin :refs/tags/v1.0.0

    BOOTH_RELEASE=v1.0.0 run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Release tag v1.0.0 isn't on GitHub (it may have been withdrawn)"* ]] || false
    [ "$(git -C "$RELEASE_REPO" symbolic-ref --short HEAD)" = main ]
    run git -C "$RELEASE_REPO" rev-parse -q --verify refs/tags/v1.0.0
    [ "$status" -ne 0 ]
}

@test "sync_demo_launcher_repo rejects an invalid release tag name" {
    make_release_origin
    load_script

    BOOTH_RELEASE="--upload-pack=x" run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"isn't a valid tag name"* ]] || false
}

@test "sync_demo_launcher_repo refuses to pin a checkout with local changes" {
    make_release_origin
    echo local > "$RELEASE_REPO/file.txt"
    load_script

    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"has local changes"* ]] || false
    [[ "$output" == *"stash"* ]] || false
    [ "$(git -C "$RELEASE_REPO" symbolic-ref --short HEAD)" = main ]
    [ "$(cat "$RELEASE_REPO/file.txt")" = local ]
}

@test "sync_demo_launcher_repo switches a pinned checkout back to main without a release" {
    make_release_origin
    load_script
    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    [ "$status" -eq 0 ]

    BOOTH_RELEASE="" run sync_demo_launcher_repo
    [ "$status" -eq 0 ]
    [[ "$output" == *"was pinned to v1"*"switching back to main"* ]] || false
    [ "$(git -C "$RELEASE_REPO" symbolic-ref --short HEAD)" = main ]
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$(git -C "$RELEASE_WORK" rev-parse main)" ]
}

@test "sync_demo_launcher_repo won't leave a pinned release with local changes" {
    make_release_origin
    load_script
    BOOTH_RELEASE=v1 run sync_demo_launcher_repo
    echo local > "$RELEASE_REPO/file.txt"

    BOOTH_RELEASE="" run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"has local changes"* ]] || false
    run git -C "$RELEASE_REPO" symbolic-ref -q HEAD
    [ "$status" -ne 0 ]
}

@test "install_demo_launcher doesn't run install.sh when the release can't be checked out" {
    make_release_origin
    mkdir -p "$RELEASE_REPO/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$RELEASE_REPO/.github/extensions/demo-launcher/install.sh"
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    BOOTH_RELEASE=v9
    failed_items=()
    install_demo_launcher

    [[ ! -f "$INSTALL_LOG" ]] || false
    [[ " ${failed_items[*]} " == *"release: octobooth/repo-setup-scripts at v9"* ]] || false
}

@test "install_demo_launcher rewrites an existing loader for a release" {
    make_release_origin
    mkdir -p "$RELEASE_REPO/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$RELEASE_REPO/.github/extensions/demo-launcher/install.sh"
    mkdir -p "$COPILOT_HOME/extensions/demo-launcher"
    touch "$COPILOT_HOME/extensions/demo-launcher/extension.mjs"
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    BOOTH_RELEASE=v1
    install_demo_launcher

    [ "$(wc -l < "$INSTALL_LOG")" -eq 1 ]
}

@test "install_demo_launcher doesn't run install.sh when a pinned checkout can't return to main" {
    make_release_origin
    git -C "$RELEASE_REPO" checkout -q --detach v1
    echo local > "$RELEASE_REPO/file.txt"
    mkdir -p "$RELEASE_REPO/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$RELEASE_REPO/.github/extensions/demo-launcher/install.sh"
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    load_script

    FORCE_REINSTALL=true
    failed_items=()
    install_demo_launcher

    [[ ! -f "$INSTALL_LOG" ]] || false
    [ "${#failed_items[@]}" -eq 1 ]
}

@test "demo_launcher_remote_trusted accepts only the trusted repo on github.com" {
    load_script
    local repo="$BATS_TEST_TMPDIR/remote-check"
    git init -q "$repo"
    git -C "$repo" remote add origin x

    local url
    for url in https://github.com/octobooth/repo-setup-scripts \
        https://github.com/octobooth/repo-setup-scripts.git \
        https://github.com/octobooth/repo-setup-scripts/ \
        git@github.com:octobooth/repo-setup-scripts.git \
        ssh://git@github.com/Octobooth/repo-setup-scripts.git; do
        git -C "$repo" remote set-url origin "$url"
        demo_launcher_remote_trusted "$repo" || { echo "rejected $url"; false; }
    done
    for url in https://github.com/attacker/repo-setup-scripts.git \
        https://github.com/octobooth-demos/repo-setup-scripts.git \
        https://ghe.example.com/octobooth/repo-setup-scripts.git \
        https://github.com/octobooth/repo-setup-scripts-fork \
        "$BATS_TEST_TMPDIR/origin.git"; do
        git -C "$repo" remote set-url origin "$url"
        ! demo_launcher_remote_trusted "$repo" || { echo "accepted $url"; false; }
    done
}

@test "sync_demo_launcher_repo refuses the source organization before fetching or installing" {
    make_release_origin
    mkdir -p "$RELEASE_REPO/.github/extensions/demo-launcher"
    printf '#!/bin/bash\necho run >> "$INSTALL_LOG"\n' > "$RELEASE_REPO/.github/extensions/demo-launcher/install.sh"
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install.log"
    git -C "$RELEASE_REPO" remote set-url origin https://github.com/octobooth-demos/repo-setup-scripts.git
    git -C "$RELEASE_REPO" config "url.$RELEASE_ORIGIN.insteadOf" https://github.com/octobooth-demos/repo-setup-scripts.git
    git -C "$RELEASE_WORK" tag v2.0.0
    git -C "$RELEASE_WORK" push -q origin v2.0.0
    load_script
    local before
    before=$(git -C "$RELEASE_REPO" rev-parse HEAD)

    BOOTH_RELEASE=v2.0.0 run sync_demo_launcher_repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"doesn't point at octobooth/repo-setup-scripts"* ]] || false
    [[ "$output" != *"Fetching"* ]] || false
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$before" ]
    run git -C "$RELEASE_REPO" rev-parse -q --verify refs/tags/v2.0.0
    [ "$status" -ne 0 ]

    BOOTH_RELEASE=""
    FORCE_REINSTALL=true
    failed_items=()
    install_demo_launcher
    [[ ! -f "$INSTALL_LOG" ]] || false
    [ "$(git -C "$RELEASE_REPO" rev-parse HEAD)" = "$before" ]
}

@test "check_demo_launcher_prereqs fails with login instructions when gh is logged out" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    load_script
    load_config

    run check_demo_launcher_prereqs
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh auth login -h github.com -s codespace,delete_repo,project,workflow"* ]] || false
}

@test "check_demo_launcher_prereqs warns about missing scopes but continues" {
    stub_gh_auth
    export GH_SCOPES="'codespace', 'repo'"
    load_script
    load_config

    run check_demo_launcher_prereqs
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh auth refresh -h github.com -s delete_repo,project,workflow"* ]] || false
}

@test "sourcing install-demo-launcher.sh does not execute it" {
    source "$REPO_ROOT/install-demo-launcher.sh"

    [[ ! -e "$HOME/repos" ]]
    declare -f demo_launcher_main > /dev/null
}

@test "install-demo-launcher.sh rejects unknown arguments" {
    run bash "$REPO_ROOT/install-demo-launcher.sh" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "install-demo-launcher.sh requires a tag after --ref" {
    run bash "$REPO_ROOT/install-demo-launcher.sh" --ref
    [ "$status" -eq 2 ]
    [[ "$output" == *"--ref v1"* ]] || false
}

@test "install-demo-launcher.sh --ref sets the release" {
    source "$REPO_ROOT/install-demo-launcher.sh"
    load_config() { :; }
    check_demo_launcher_prereqs() { :; }
    install_demo_launcher() { echo "release=$BOOTH_RELEASE"; }
    install_playwright_mcp_bundle() { :; }
    register_mcp_servers() { :; }
    mkdir -p "$HOME/repos/repo-setup-scripts/.git"

    run demo_launcher_main --ref v1.2.0
    [[ "$output" == *"release=v1.2.0"* ]] || false

    BOOTH_RELEASE=v1 run demo_launcher_main
    [[ "$output" == *"release=v1"* ]] || false
}

@test "install-demo-launcher.sh passes the caller's FORCE_REINSTALL to the Playwright bundle" {
    source "$REPO_ROOT/install-demo-launcher.sh"
    load_config() { :; }
    check_demo_launcher_prereqs() { :; }
    install_demo_launcher() { :; }
    install_playwright_mcp_bundle() { echo "bundle_force=$FORCE_REINSTALL"; }
    register_mcp_servers() { :; }
    mkdir -p "$HOME/repos/repo-setup-scripts/.git"

    FORCE_REINSTALL=false run demo_launcher_main
    [[ "$output" == *"bundle_force=false"* ]] || false

    FORCE_REINSTALL=true run demo_launcher_main
    [[ "$output" == *"bundle_force=true"* ]] || false
}

@test "setup.sh rejects unknown arguments" {
    run bash "$REPO_ROOT/setup.sh" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"--ref v1"* ]] || false
}

# Stubs xcode-select so `-p` succeeds once the CLT "install" has had
# $CLT_READY_AFTER polls, and logs every invocation
stub_xcode_select() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export XCODE_SELECT_LOG="$BATS_TEST_TMPDIR/xcode-select.log"
    export CLT_DIR="$BATS_TEST_TMPDIR/CommandLineTools"
    export CLT_POLLS="$BATS_TEST_TMPDIR/clt-polls"
    export CLT_READY_AFTER="${1:-0}"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    : > "$CLT_POLLS"

    cat > "$BATS_TEST_TMPDIR/bin/xcode-select" <<'STUB'
#!/bin/bash
echo "$*" >> "$XCODE_SELECT_LOG"
if [[ "$1" == "-p" ]]; then
    polls=$(wc -l < "$CLT_POLLS")
    echo x >> "$CLT_POLLS"
    if (( polls >= CLT_READY_AFTER )); then
        mkdir -p "$CLT_DIR"
        echo "$CLT_DIR"
        exit 0
    fi
    exit 2
fi
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/xcode-select"

    cat > "$BATS_TEST_TMPDIR/bin/sleep" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/sleep"
}

@test "install_xcode_clt does nothing when the tools are already installed" {
    stub_xcode_select 0
    load_script

    run install_xcode_clt
    [ "$status" -eq 0 ]

    run grep -F -- "--install" "$XCODE_SELECT_LOG"
    [ "$status" -ne 0 ]
}

@test "install_xcode_clt starts the installer and waits for it to finish" {
    stub_xcode_select 3
    load_script

    run install_xcode_clt
    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode Command Line Tools installed"* ]] || false

    run grep -c -F -- "--install" "$XCODE_SELECT_LOG"
    [ "$output" = "1" ]
}

@test "install_xcode_clt exits with guidance when the install times out" {
    stub_xcode_select 1000
    export XCODE_CLT_TIMEOUT=30 XCODE_CLT_POLL_INTERVAL=10
    load_script

    run install_xcode_clt
    [ "$status" -eq 1 ]
    [[ "$output" == *"xcode-select --install"* ]] || false
}

# Stubs defaultbrowser: lists browsers with "*" on $DEFAULT_BROWSER_FILE's
# contents, and `defaultbrowser chrome` switches it (simulating "Use Chrome")
stub_defaultbrowser() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DEFAULT_BROWSER_FILE="$BATS_TEST_TMPDIR/default-browser"
    export DEFAULTBROWSER_LOG="$BATS_TEST_TMPDIR/defaultbrowser.log"
    echo "$1" > "$DEFAULT_BROWSER_FILE"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/defaultbrowser" <<'STUB'
#!/bin/bash
echo "$*" >> "$DEFAULTBROWSER_LOG"
if [[ -n "$1" ]]; then
    [[ "${ACCEPT_DIALOG:-true}" == "true" ]] && echo "$1" > "$DEFAULT_BROWSER_FILE"
    exit 0
fi
current=$(cat "$DEFAULT_BROWSER_FILE")
for b in safari chrome; do
    if [[ "$b" == "$current" ]]; then echo "* $b"; else echo "  $b"; fi
done
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/defaultbrowser"
}

@test "config installs defaultbrowser on macOS" {
    run jq -e '.mac.packages.formulas | index("defaultbrowser")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "set_default_browser_chrome skips when Chrome is already the default" {
    stub_defaultbrowser chrome
    load_script

    run set_default_browser_chrome < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"already the default browser"* ]] || false

    run grep -Fx "chrome" "$DEFAULTBROWSER_LOG"
    [ "$status" -ne 0 ]
}

@test "set_default_browser_chrome switches the default to Chrome" {
    stub_defaultbrowser safari
    load_script

    run set_default_browser_chrome <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chrome is now the default browser"* ]] || false
    [ "$(cat "$DEFAULT_BROWSER_FILE")" = "chrome" ]
}

@test "set_default_browser_chrome reports failure when the dialog is declined" {
    stub_defaultbrowser safari
    export ACCEPT_DIALOG=false
    load_script

    run set_default_browser_chrome <<< ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"System Settings"* ]] || false
}

# Stubs dockutil, defaults, and killall with a Dock backed by files, and
# creates fake app bundles for every app in mac.dock_apps
stub_dock() {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DOCK_FILE="$BATS_TEST_TMPDIR/dock"
    export DOCK_LOG="$BATS_TEST_TMPDIR/dock.log"
    export SHOW_RECENTS_FILE="$BATS_TEST_TMPDIR/show-recents"
    export APPLICATIONS_DIR="$BATS_TEST_TMPDIR/Applications"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$APPLICATIONS_DIR"
    : > "$DOCK_FILE"
    rm -f "$SHOW_RECENTS_FILE"

    while IFS= read -r app; do mkdir -p "$APPLICATIONS_DIR/$app.app"; done \
        < <(jq -r '.mac.dock_apps[]' "$REPO_ROOT/config.json")

    cat > "$BATS_TEST_TMPDIR/bin/dockutil" <<'STUB'
#!/bin/bash
echo "dockutil $*" >> "$DOCK_LOG"
case "$1" in
    --find) grep -qxF "$2" "$DOCK_FILE" ;;
    --add) [[ "$3" == "--no-restart" ]] || exit 9; basename "$2" .app >> "$DOCK_FILE" ;;
esac
STUB
    cat > "$BATS_TEST_TMPDIR/bin/defaults" <<'STUB'
#!/bin/bash
echo "defaults $*" >> "$DOCK_LOG"
case "$1" in
    read) [[ -f "$SHOW_RECENTS_FILE" ]] && cat "$SHOW_RECENTS_FILE" ;;
    write) [[ "${DEFAULTS_WRITE_FAILS:-}" == "true" ]] && exit 1; echo 0 > "$SHOW_RECENTS_FILE" ;;
esac
STUB
    cat > "$BATS_TEST_TMPDIR/bin/killall" <<'STUB'
#!/bin/bash
echo "killall $*" >> "$DOCK_LOG"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/dockutil" "$BATS_TEST_TMPDIR/bin/defaults" "$BATS_TEST_TMPDIR/bin/killall"
}

@test "config installs dockutil and lists the Dock apps" {
    run jq -e '.mac.packages.formulas | index("dockutil")' "$REPO_ROOT/config.json"
    [ "$status" -eq 0 ]

    run jq -r '.mac.dock_apps | join(",")' "$REPO_ROOT/config.json"
    [ "$output" = "Google Chrome,GitHub Copilot,Visual Studio Code,Visual Studio Code - Insiders,iTerm,VLC" ]
}

@test "configure_dock adds apps, hides recents, and restarts the Dock once" {
    stub_dock
    load_script
    load_config

    run configure_dock
    [ "$status" -eq 0 ]

    run cat "$DOCK_FILE"
    [ "$output" = "$(jq -r '.mac.dock_apps[]' "$REPO_ROOT/config.json")" ]
    [ "$(cat "$SHOW_RECENTS_FILE")" = "0" ]
    [ "$(grep -c '^killall Dock$' "$DOCK_LOG")" = "1" ]

    run grep -E 'dockutil --remove|show-persistent|downloads|trash' "$DOCK_LOG"
    [ "$status" -ne 0 ]
}

@test "configure_dock is idempotent and doesn't restart the Dock when nothing changes" {
    stub_dock
    load_script
    load_config

    configure_dock
    : > "$DOCK_LOG"

    run configure_dock
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$DOCK_FILE" | tr -d ' ')" = "$(jq '.mac.dock_apps | length' "$REPO_ROOT/config.json")" ]

    run grep -E 'dockutil --add|defaults write|killall' "$DOCK_LOG"
    [ "$status" -ne 0 ]
}

@test "configure_dock fails when hiding recent apps fails" {
    stub_dock
    jq -r '.mac.dock_apps[]' "$REPO_ROOT/config.json" > "$DOCK_FILE"
    export DEFAULTS_WRITE_FAILS=true
    load_script
    load_config

    run configure_dock
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not hide suggested and recent apps in the Dock"* ]] || false
    [[ "$output" != *"Hid suggested and recent apps"* ]] || false
    [ ! -f "$SHOW_RECENTS_FILE" ]

    run grep -E 'killall' "$DOCK_LOG"
    [ "$status" -ne 0 ]
}

@test "configure_dock reports a missing app but still adds the others" {
    stub_dock
    rm -rf "$APPLICATIONS_DIR/iTerm.app"
    load_script
    load_config

    run configure_dock
    [ "$status" -eq 1 ]
    [[ "$output" == *"iTerm not found"* ]] || false

    run grep -cxF "iTerm" "$DOCK_FILE"
    [ "$output" = "0" ]
    [ "$(wc -l < "$DOCK_FILE" | tr -d ' ')" = "$(( $(jq '.mac.dock_apps | length' "$REPO_ROOT/config.json") - 1 ))" ]
}

@test "configure_dock doesn't duplicate Chrome when it's already in the Dock" {
    stub_dock
    echo "Google Chrome" > "$DOCK_FILE"
    load_script
    load_config

    run configure_dock
    [ "$status" -eq 0 ]
    [[ "$output" == *"Google Chrome is already in the Dock"* ]] || false

    run grep -cxF "Google Chrome" "$DOCK_FILE"
    [ "$output" = "1" ]

    run grep -F 'dockutil --add' "$DOCK_LOG"
    [[ "$output" != *"Google Chrome"* ]] || false
}
