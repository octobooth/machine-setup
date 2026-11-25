#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    export TMPDIR="$BATS_TEST_TMPDIR/temp space"
    export FIXTURE="$BATS_TEST_TMPDIR/archive.tar.gz"
    export BOOTSTRAP_LOG="$BATS_TEST_TMPDIR/setup.log"
    export DOWNLOAD_LOG="$BATS_TEST_TMPDIR/download.log"
    unset BOOTH_RELEASE
    mkdir -p "$TMPDIR" "$BATS_TEST_TMPDIR/fixture/machine-setup-test/iterm2"
    local source="$BATS_TEST_TMPDIR/fixture/machine-setup-test"
    printf '{}\n' > "$source/config.json"
    printf 'theme\n' > "$source/iterm2/theme"
    cat > "$source/setup.sh" <<'SCRIPT'
#!/bin/bash
root="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$root/config.json" && -f "$root/iterm2/theme" ]] || exit 99
printf 'release=%s args=%s\n' "$BOOTH_RELEASE" "$*" > "$BOOTSTRAP_LOG"
read -r answer
printf 'answer=%s\n' "$answer" >> "$BOOTSTRAP_LOG"
exit "${SETUP_STATUS:-0}"
SCRIPT
    tar -czf "$FIXTURE" -C "$BATS_TEST_TMPDIR/fixture" machine-setup-test
    source "$REPO_ROOT/bootstrap.sh"
    curl() {
        printf '%s\n' "$*" > "$DOWNLOAD_LOG"
        [[ "${DOWNLOAD_STATUS:-0}" == 0 ]] || return "$DOWNLOAD_STATUS"
        cp "$FIXTURE" "${@: -1}"
    }
}

@test "sourcing bootstrap does not download or run setup" {
    [[ ! -e "$DOWNLOAD_LOG" && ! -e "$BOOTSTRAP_LOG" ]]
}

@test "main downloads the whole tree and leaves stdin for setup" {
    run bootstrap_main <<< "approved"
    [ "$status" -eq 0 ]
    [[ "$(cat "$DOWNLOAD_LOG")" == *"/archive/refs/heads/main.tar.gz"* ]]
    [ "$(cat "$BOOTSTRAP_LOG")" = "$(printf 'release= args=\nanswer=approved')" ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "README command downloads and runs main even with an inherited release" {
    export BOOTH_RELEASE=v1
    curl() {
        printf '%s\n' "$*" >> "$DOWNLOAD_LOG"
        case "$*" in
            *"https://raw.githubusercontent.com/octobooth/machine-setup/main/bootstrap.sh"*)
                cp "$REPO_ROOT/bootstrap.sh" "${@: -1}" ;;
            *"https://github.com/octobooth/machine-setup/archive/refs/heads/main.tar.gz"*)
                cp "$FIXTURE" "${@: -1}" ;;
            *) echo "Unexpected README download: $*" >&2; return 1 ;;
        esac
    }
    export -f curl
    local command
    command=$(awk '/```bash/ { getline; print; exit }' "$REPO_ROOT/README.md")

    run bash -c "$command" <<< "approved"

    [ "$status" -eq 0 ]
    [ "$(cat "$BOOTSTRAP_LOG")" = "$(printf 'release= args=\nanswer=approved')" ]
    [ "$BOOTH_RELEASE" = v1 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "release selection pins both setup and demo scripts" {
    export BOOTH_RELEASE=v1
    run bootstrap_main --ref v2.3.4 <<< "approved"
    [ "$status" -eq 0 ]
    [[ "$(cat "$DOWNLOAD_LOG")" == *"/archive/refs/tags/v2.3.4.tar.gz"* ]]
    [[ "$(cat "$BOOTSTRAP_LOG")" == "release=v2.3.4 args=--ref v2.3.4"* ]]
}

@test "environment release is used unless main is explicitly selected" {
    export BOOTH_RELEASE=v1
    run bootstrap_main <<< "approved"
    [ "$status" -eq 0 ]
    [[ "$(cat "$DOWNLOAD_LOG")" == *"/archive/refs/tags/v1.tar.gz"* ]]
    [[ "$(cat "$BOOTSTRAP_LOG")" == "release=v1 args=--ref v1"* ]]

    run bootstrap_main --ref main <<< "approved"
    [ "$status" -eq 0 ]
    [[ "$(cat "$BOOTSTRAP_LOG")" == "release= args="* ]]
    [ "$BOOTH_RELEASE" = v1 ]
}

@test "invalid or missing refs fail before download" {
    for ref in "" "../main" "refs/heads/main" "v1.2" "1234567"; do
        run bootstrap_main --ref "$ref"
        [ "$status" -eq 2 ]
        [[ ! -e "$DOWNLOAD_LOG" && ! -e "$BOOTSTRAP_LOG" ]]
    done
}

@test "commit selection pins the setup archive without treating it as a demo release" {
    export BOOTH_RELEASE=v1
    local ref=1234567890abcdef1234567890abcdef12345678
    run bootstrap_main --ref "$ref" <<< "approved"
    [ "$status" -eq 0 ]
    [[ "$(cat "$DOWNLOAD_LOG")" == *"/archive/$ref.tar.gz"* ]]
    [ "$(cat "$BOOTSTRAP_LOG")" = "$(printf 'release= args=\nanswer=approved')" ]
    [ "$BOOTH_RELEASE" = v1 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "download failure never starts setup and removes temporary files" {
    export DOWNLOAD_STATUS=22
    run bootstrap_main
    [ "$status" -eq 22 ]
    [[ ! -e "$BOOTSTRAP_LOG" ]]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "invalid and incomplete archives never start setup" {
    printf 'not an archive\n' > "$FIXTURE"
    run bootstrap_main
    [ "$status" -ne 0 ]
    [[ ! -e "$BOOTSTRAP_LOG" ]]
    [ -z "$(ls -A "$TMPDIR")" ]

    tar -czf "$FIXTURE" -C "$BATS_TEST_TMPDIR/fixture" machine-setup-test/config.json
    run bootstrap_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing setup.sh or config.json"* ]]
    [[ ! -e "$BOOTSTRAP_LOG" ]]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "setup failure propagates and removes temporary files" {
    export SETUP_STATUS=37
    run bootstrap_main <<< "approved"
    [ "$status" -eq 37 ]
    [[ "$output" == *"Setup failed (exit 37)"* ]]
    [[ -f "$BOOTSTRAP_LOG" ]]
    [ -z "$(ls -A "$TMPDIR")" ]
}
