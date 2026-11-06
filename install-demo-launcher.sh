#!/bin/bash
#
# Installs (or updates) the Demo Launcher canvas so it's available in every
# GitHub Copilot session, without rerunning the full setup.sh.
# Safe to re-run. See https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine
#
# Usage: bash install-demo-launcher.sh [--uninstall]
#

# setup.sh only runs main when executed directly, so sourcing it just loads its helpers
# shellcheck source=setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup.sh"

usage() {
    echo "Usage: bash install-demo-launcher.sh [--uninstall]"
}

demo_launcher_main() {
    local installer
    installer="$(demo_launcher_repo_dir)/.github/extensions/demo-launcher/install.sh"

    case "${1:-}" in
        "") ;;
        --uninstall)
            if [[ ! -f "$installer" ]]; then
                log_error "Demo Launcher installer not found at ${installer/#$HOME/~}"
                exit 1
            fi
            bash "$installer" --uninstall || exit 1
            log_success "Demo Launcher removed. Restart the GitHub Copilot app to unload it."
            return
            ;;
        -h|--help) usage; return ;;
        *) usage >&2; exit 2 ;;
    esac

    load_config
    check_demo_launcher_prereqs || exit 1
    # install_demo_launcher pulls an existing checkout; only clone here
    [[ -d "$(demo_launcher_repo_dir)/.git" ]] || sync_demo_launcher_repo

    # install.sh is idempotent, so always run it to refresh the loader
    FORCE_REINSTALL=true
    install_demo_launcher

    if [[ ! -f "$installer" ]]; then
        failed_items+=("Demo Launcher (install.sh not found in $DEMO_LAUNCHER_REPO)")
    fi

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
