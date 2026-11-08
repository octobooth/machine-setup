#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    export HOME="$BATS_TEST_TMPDIR/home"
    export COPILOT_HOME="$HOME/.copilot"
    mkdir -p "$HOME"
    source "$REPO_ROOT/setup.sh"
    TARGET="$COPILOT_HOME/copilot-instructions.md"
}

# The managed block setup should write: markers around the source file's text
expected_block() {
    echo "$BOOTH_INSTRUCTIONS_BEGIN"
    cat "$BOOTH_INSTRUCTIONS_SOURCE"
    echo "$BOOTH_INSTRUCTIONS_END"
}

@test "booth instructions source steers away from npm and pip" {
    run cat "$BOOTH_INSTRUCTIONS_SOURCE"
    [[ "$output" == *"npm install"* ]]
    [[ "$output" == *"pip install"* ]]
    [[ "$output" == *"index.html"* ]]
    [[ "$output" == *"Cloud session"* ]]
}

@test "install_booth_instructions creates the file and its folder" {
    install_booth_instructions

    [ "$(cat "$TARGET")" = "$(expected_block)" ]
}

@test "install_booth_instructions keeps the user's instructions and appends the block" {
    mkdir -p "$COPILOT_HOME"
    printf 'My rule\nAnother rule' > "$TARGET"

    install_booth_instructions

    [ "$(head -3 "$TARGET")" = "$(printf 'My rule\nAnother rule\n')" ]
    [ "$(tail -n +4 "$TARGET")" = "$(expected_block)" ]
}

@test "install_booth_instructions is idempotent" {
    mkdir -p "$COPILOT_HOME"
    printf 'My rule\n' > "$TARGET"

    install_booth_instructions
    local first
    first="$(cat "$TARGET")"
    run install_booth_instructions

    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date"* ]]
    [ "$(cat "$TARGET")" = "$first" ]
    [ "$(grep -cxF "$BOOTH_INSTRUCTIONS_BEGIN" "$TARGET")" -eq 1 ]
}

@test "install_booth_instructions replaces only the managed block" {
    mkdir -p "$COPILOT_HOME"
    printf 'Before\n%s\nold booth text\n%s\nAfter\n' \
        "$BOOTH_INSTRUCTIONS_BEGIN" "$BOOTH_INSTRUCTIONS_END" > "$TARGET"

    install_booth_instructions

    [ "$(cat "$TARGET")" = "$(printf 'Before\n%s\nAfter' "$(expected_block)")" ]
}

@test "install_booth_instructions leaves the file alone when markers are unmatched" {
    mkdir -p "$COPILOT_HOME"
    printf 'Mine\n%s\nmore of mine\n' "$BOOTH_INSTRUCTIONS_BEGIN" > "$TARGET"
    local before
    before="$(cat "$TARGET")"

    run install_booth_instructions

    [ "$status" -eq 1 ]
    [ "$(cat "$TARGET")" = "$before" ]
}

@test "install_booth_instructions fails when the source file is missing" {
    BOOTH_INSTRUCTIONS_SOURCE="$BATS_TEST_TMPDIR/missing.md" run install_booth_instructions

    [ "$status" -eq 1 ]
    [[ ! -f "$TARGET" ]]
}
