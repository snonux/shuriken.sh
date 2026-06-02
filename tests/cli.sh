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

assert_not_contains() {
    local -r needle="$1"; shift
    local -r haystack="$1"; shift

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL: expected output not to contain $needle" >&2
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

test_generate_escapes_html_values() {
    local config_file
    local css_photo
    local fake_bin
    local original_basepath
    local original_basepath_html
    local page_html
    local photo_html
    local photo_name
    local title
    local title_html
    local view_html

    setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    photo_name="kid's_\"<tag>&.jpg"
    photo_html='kid&#39;s_&quot;&lt;tag&gt;&amp;.jpg'
    css_photo='kid\000027s_\000022\00003ctag\00003e\000026.jpg'
    title="A & \"quoted\" <title> 'ok'"
    title_html='A &amp; &quot;quoted&quot; &lt;title&gt; &#39;ok&#39;'
    original_basepath="https://example.test/original?album=\"<x>&owner=O'Neil"
    original_basepath_html='https://example.test/original?album=&quot;&lt;x&gt;&amp;owner=O&#39;Neil'

    mkdir -p "$fake_bin" "$TEST_TMPDIR/incoming"
    cat > "$fake_bin/magick" <<'MAGICK'
#!/usr/bin/env bash
set -euo pipefail

dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
printf 'fake image\n' > "$dest"
MAGICK
    chmod 0755 "$fake_bin/magick"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/$photo_name"

    {
        printf 'TITLE=%q\n' "$title"
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$REPO_ROOT"
        printf 'ORIGINAL_BASEPATH=%q\n' "$original_basepath"
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TARBALL_SUFFIX=%q\n' '&"'\''.tar'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$PHOTOALBUM" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")
    view_html=$(<"$TEST_TMPDIR/dist/html/1-1.html")

    assert_contains "<title>$title_html</title>" "$page_html"
    assert_contains \
        "background-image: url(\"../blurs/$css_photo\");" \
        "$page_html"
    assert_contains "name='$photo_html'" "$page_html"
    assert_contains "src='../thumbs/$photo_html'" "$page_html"
    assert_contains '&amp;&quot;&#39;.tar' "$page_html"
    assert_contains "href=\"page-1.html#$photo_html\"" "$view_html"
    assert_contains "href ='../photos/$photo_html'" "$view_html"
    assert_contains \
        "href=\"$original_basepath_html/$photo_html\"" \
        "$view_html"
    assert_not_contains '<title>A & "quoted" <title>' "$page_html"
    assert_not_contains "$photo_name" "$view_html"

    teardown
}

test_generate_preserves_space_filename_without_reprocessing() {
    local config_file
    local fake_bin
    local first_output
    local photo_name
    local second_output

    setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    photo_name='a b.jpg'

    mkdir -p "$fake_bin" "$TEST_TMPDIR/incoming"
    cat > "$fake_bin/magick" <<'MAGICK'
#!/usr/bin/env bash
set -euo pipefail

dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
printf 'fake image\n' > "$dest"
MAGICK
    chmod 0755 "$fake_bin/magick"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/$photo_name"

    {
        printf 'TITLE=%q\n' 'Space test'
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$REPO_ROOT"
        printf 'TARBALL_INCLUDE=no\n'
    } > "$config_file"

    first_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$PHOTOALBUM" --generate
    )
    second_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$PHOTOALBUM" --generate
    )

    test -f "$TEST_TMPDIR/dist/photos/$photo_name"
    test ! -e "$TEST_TMPDIR/dist/photos/a_b.jpg"
    assert_contains "Processing $photo_name to" "$first_output"
    assert_contains "Already exists: $TEST_TMPDIR/dist/photos/$photo_name" \
        "$second_output"
    assert_not_contains "Processing $photo_name to" "$second_output"

    teardown
}

test_generate_handles_space_and_underscore_names_distinctly() {
    local config_file
    local fake_bin
    local page_html

    setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    mkdir -p "$fake_bin" "$TEST_TMPDIR/incoming"
    cat > "$fake_bin/magick" <<'MAGICK'
#!/usr/bin/env bash
set -euo pipefail

dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
printf 'fake image\n' > "$dest"
MAGICK
    chmod 0755 "$fake_bin/magick"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a b.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a_b.jpg"

    {
        printf 'TITLE=%q\n' 'Collision test'
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$REPO_ROOT"
        printf 'TARBALL_INCLUDE=no\n'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$PHOTOALBUM" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")

    test -f "$TEST_TMPDIR/dist/photos/a b.jpg"
    test -f "$TEST_TMPDIR/dist/photos/a_b.jpg"
    test -f "$TEST_TMPDIR/dist/thumbs/a b.jpg"
    test -f "$TEST_TMPDIR/dist/thumbs/a_b.jpg"
    assert_contains "src='../thumbs/a b.jpg'" "$page_html"
    assert_contains "src='../thumbs/a_b.jpg'" "$page_html"

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
    run_test \
        '--generate escapes generated HTML values' \
        test_generate_escapes_html_values
    run_test \
        '--generate preserves filenames with spaces without reprocessing' \
        test_generate_preserves_space_filename_without_reprocessing
    run_test \
        '--generate handles spaces and underscores distinctly' \
        test_generate_handles_space_and_underscore_names_distinctly
    run_test 'positional commands fail' test_positional_commands_fail
    run_test 'extra args fail' test_extra_args_fail
}

main "$@"
