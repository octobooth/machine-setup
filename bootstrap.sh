#!/bin/bash

# Download the complete setup tree before running it, leaving stdin for prompts.
bootstrap_main() (
    local ref="${BOOTH_RELEASE:-main}" archive_ref release="" work_dir status
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ref)
                [[ -n "${2:-}" ]] || { echo "Usage: bootstrap.sh [--ref main|v1|v1.2.0|COMMIT_SHA]" >&2; return 2; }
                ref="$2"; shift 2 ;;
            --ref=*) ref="${1#--ref=}"; shift ;;
            -h|--help) echo "Usage: bootstrap.sh [--ref main|v1|v1.2.0|COMMIT_SHA]"; return 0 ;;
            *) echo "Usage: bootstrap.sh [--ref main|v1|v1.2.0|COMMIT_SHA]" >&2; return 2 ;;
        esac
    done
    if [[ "$ref" == main ]]; then
        archive_ref="refs/heads/main"
    elif [[ "$ref" =~ ^v[0-9]+(\.[0-9]+\.[0-9]+)?$ ]]; then
        archive_ref="refs/tags/$ref"
        release="$ref"
    elif [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
        archive_ref="$ref"
    else
        echo "Invalid ref '$ref': use main, a release tag such as v1 or v1.2.0, or a full 40-character commit SHA." >&2
        return 2
    fi

    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/machine-setup.XXXXXXXX") || return 1
    trap 'rm -rf "$work_dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    echo "Downloading machine-setup at $ref..."
    curl --fail --silent --show-error --location \
        "https://github.com/octobooth/machine-setup/archive/$archive_ref.tar.gz" \
        --output "$work_dir/setup.tar.gz" || return "$?"
    mkdir "$work_dir/source" || return 1
    tar -xzf "$work_dir/setup.tar.gz" -C "$work_dir/source" --strip-components=1 || return "$?"
    if [[ ! -f "$work_dir/source/setup.sh" || ! -f "$work_dir/source/config.json" ]]; then
        echo "Downloaded archive is missing setup.sh or config.json; setup was not started." >&2
        return 1
    fi

    echo "Running machine-setup at $ref. Answer the setup and sign-in prompts in this terminal."
    if [[ -n "$release" ]]; then
        BOOTH_RELEASE="$release" bash "$work_dir/source/setup.sh" --ref "$release"
    else
        BOOTH_RELEASE="" bash "$work_dir/source/setup.sh"
    fi
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Setup failed (exit $status). Fix the reported problem and rerun the bootstrap." >&2
    fi
    return "$status"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bootstrap_main "$@"
fi
