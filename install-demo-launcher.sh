#!/bin/bash
#
# Installs (or updates) the Demo Launcher canvas so it's available in every
# GitHub Copilot session, without rerunning the full setup.sh. It also installs
# the pinned Playwright MCP bundle and refreshes the Copilot CLI MCP servers.
# Safe to re-run. See https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine
#
# Usage: bash install-demo-launcher.sh [--ref <tag>] [--uninstall]
#
#   --ref <tag>  Check out ~/repos/repo-setup-scripts at a release tag: the
#                major the booth uses (v1) or a full version (v1.2.0). Also
#                read from BOOTH_RELEASE. Without one, a checkout pinned to a
#                release (detached HEAD) switches back to its default branch
#                and pulls it (untested main), while a checkout on a branch
#                stays on that branch and pulls it. setup.sh does the same.
#

# setup.sh only runs main when executed directly, so sourcing it just loads its helpers
# shellcheck source=setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup.sh"

usage() {
    echo "Usage: bash install-demo-launcher.sh [--ref v1] [--uninstall]"
}

demo_launcher_main() {
    local installer uninstall=false
    installer="$(demo_launcher_repo_dir)/.github/extensions/demo-launcher/install.sh"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall) uninstall=true; shift ;;
            --ref)
                [[ -n "${2:-}" ]] || { usage >&2; exit 2; }
                BOOTH_RELEASE="$2"; shift 2 ;;
            --ref=*) BOOTH_RELEASE="${1#--ref=}"; shift ;;
            -h|--help) usage; return ;;
            *) usage >&2; exit 2 ;;
        esac
    done

    if [[ "$uninstall" == true ]]; then
        if [[ ! -f "$installer" ]]; then
            log_error "Demo Launcher installer not found at ${installer/#$HOME/~}"
            exit 1
        fi
        bash "$installer" --uninstall || exit 1
        log_success "Demo Launcher removed. Restart the GitHub Copilot app to unload it."
        return
    fi

    load_config
    check_demo_launcher_prereqs || exit 1
    [[ -n "$BOOTH_RELEASE" ]] && log_info "Using release $BOOTH_RELEASE of $DEMO_LAUNCHER_REPO"
    # install_demo_launcher updates an existing checkout; only clone here
    if [[ ! -d "$(demo_launcher_repo_dir)/.git" ]]; then
        sync_demo_launcher_repo || { print_summary; exit 1; }
    fi

    # install.sh is idempotent, so always run it to refresh the loader
    local requested_force="$FORCE_REINSTALL"
    FORCE_REINSTALL=true
    install_demo_launcher

    if [[ ! -f "$installer" ]]; then
        failed_items+=("Demo Launcher (install.sh not found in $DEMO_LAUNCHER_REPO)")
    fi

    # Also roll out the pinned Playwright MCP bundle and MCP servers. Only reinstall the
    # bundle when its version changes (or the caller set FORCE_REINSTALL), and never
    # fail the launcher install over it.
    FORCE_REINSTALL="$requested_force"
    install_playwright_mcp_bundle
    register_mcp_servers

    print_summary
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        exit 1
    fi

    log_success "Demo Launcher installed"
    log_info "Restart the GitHub Copilot app (or reload extensions), then ask Copilot to \"open the demo launcher\" in any chat or session."
    log_info "Also add the existing ~/repos/repo-setup-scripts folder (don't re-clone) as a project in the Copilot app, so you can pin a session (choose Current checkout, not New worktree) or the canvas for quick access."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_launcher_main "$@"
fi
