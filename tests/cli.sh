#!/usr/bin/env bash
set -euo pipefail

declare -r REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -r PHOTOALBUM="${PHOTOALBUM:-$REPO_ROOT/bin/photoalbum}"
TEST_TMPDIR="${TEST_TMPDIR:-}"

setup() {
    TEST_TMPDIR=$(mktemp -d)
}

teardown() {
    if [ -n "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

run_test() {
    local -r description="$1"; shift
    local output_file
    local -i status=0

    output_file=$(mktemp)
    set +e
    ( set -euo pipefail; trap teardown EXIT; "$@" ) > "$output_file" 2>&1
    status=$?
    set -e

    if (( status != 0 )); then
        echo "FAIL: $description" >&2
        cat "$output_file" >&2
        rm -f "$output_file"
        exit 1
    fi

    rm -f "$output_file"
}

assert_failure() {
    local -r description="$1"; shift
    local output_file
    local -i status=0

    output_file=$(mktemp)
    set +e
    "$@" > "$output_file" 2>&1
    status=$?
    set -e

    if (( status == 0 )); then
        echo "FAIL: $description" >&2
        cat "$output_file" >&2
        rm -f "$output_file"
        exit 1
    fi

    rm -f "$output_file"
}

capture_failure_output() {
    local output
    local output_file
    local -i status=0

    output_file=$(mktemp)
    set +e
    "$@" > "$output_file" 2>&1
    status=$?
    set -e

    if (( status == 0 )); then
        echo 'FAIL: expected command to fail' >&2
        output=$(<"$output_file")
        echo "$output" >&2
        rm -f "$output_file"
        exit 1
    fi

    output=$(<"$output_file")
    rm -f "$output_file"
    printf '%s\n' "$output"
}

assert_contains() {
    local -r needle="$1"; shift
    local -r haystack="$1"; shift

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: expected output to contain $needle" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

run_photoalbum() {
    "$PHOTOALBUM" "$@" 2>&1
}

test_version() {
    local output

    output=$(run_photoalbum --version)
    assert_contains 'This is Photoalbum Version' "$output"
}

test_init() {
    setup
    (
        cd "$TEST_TMPDIR"
        PHOTOALBUM_DEFAULT_RC="$TEST_TMPDIR/missing" \
            "$PHOTOALBUM" --init >/dev/null
        test -f photoalbum.conf
        test ! -f Makefile
        grep -q \
            "^TEMPLATE_DIR=$REPO_ROOT/share/templates/default$" \
            photoalbum.conf
    )
    teardown
}

test_clean() {
    setup
    printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/photoalbum.conf"
    mkdir -p "$TEST_TMPDIR/dist"

    (
        cd "$TEST_TMPDIR"
        "$PHOTOALBUM" --clean
        test ! -e "$TEST_TMPDIR/dist"
    )
    teardown
}

test_clean_with_config() {
    local config_file

    setup
    config_file="$TEST_TMPDIR/custom.conf"
    printf 'DIST_DIR=%q/custom-dist\n' "$TEST_TMPDIR" > "$config_file"
    mkdir -p "$TEST_TMPDIR/custom-dist"

    (
        cd "$TEST_TMPDIR"
        "$PHOTOALBUM" --clean --config "$config_file"
        test ! -e "$TEST_TMPDIR/custom-dist"
    )
    teardown
}

test_clean_missing_config_fails() {
    local output

    setup
    printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/photoalbumrc"
    output=$(
        cd "$TEST_TMPDIR"
        capture_failure_output "$PHOTOALBUM" --clean
    )

    assert_contains 'Error: Can not find config file ./photoalbum.conf' "$output"
    assert_contains 'Run photoalbum --init to create ./photoalbum.conf.' "$output"
    teardown
}

test_generate_with_config_missing_incoming_fails() {
    local config_file
    local output

    setup
    config_file="$TEST_TMPDIR/custom.conf"
    {
        printf 'INCOMING_DIR=%q/missing\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/custom-dist\n' "$TEST_TMPDIR"
    } > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        capture_failure_output "$PHOTOALBUM" --generate --config "$config_file"
    )

    assert_contains "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    teardown
}

test_generate_missing_incoming_fails() {
    setup
    {
        printf 'INCOMING_DIR=%q/missing\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
    } > "$TEST_TMPDIR/photoalbum.conf"

    (
        cd "$TEST_TMPDIR"
        assert_failure \
            '--generate fails when INCOMING_DIR is missing' \
            "$PHOTOALBUM" --generate
    )
    teardown
}

test_positional_commands_fail() {
    assert_failure 'positional clean is rejected' "$PHOTOALBUM" clean
    assert_failure 'positional generate is rejected' "$PHOTOALBUM" generate
    assert_failure 'positional version is rejected' "$PHOTOALBUM" version
}

test_extra_args_fail() {
    assert_failure 'extra operand is rejected' "$PHOTOALBUM" --version extra
    assert_failure 'unsupported option is rejected' "$PHOTOALBUM" --unknown
    assert_failure 'missing config value is rejected' "$PHOTOALBUM" --config
    assert_failure \
        '--config is rejected with --init' \
        "$PHOTOALBUM" --init --config custom.conf
}

main() {
    trap teardown EXIT

    run_test '--version succeeds' test_version
    run_test '--init succeeds' test_init
    run_test '--clean succeeds' test_clean
    run_test '--clean --config succeeds' test_clean_with_config
    run_test '--clean missing config fails clearly' test_clean_missing_config_fails
    run_test \
        '--generate --config reads selected config' \
        test_generate_with_config_missing_incoming_fails
    run_test \
        '--generate missing incoming fails' \
        test_generate_missing_incoming_fails
    run_test 'positional commands fail' test_positional_commands_fail
    run_test 'extra args fail' test_extra_args_fail
}

main "$@"
