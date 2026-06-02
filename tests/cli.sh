#!/usr/bin/env bash
set -euo pipefail

declare -r TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -r TEST_PHOTOALBUM="${PHOTOALBUM:-$TEST_REPO_ROOT/bin/photoalbum}"

# shellcheck source=tests/helpers.sh
source "$TEST_REPO_ROOT/tests/helpers.sh"

test_version() {
    local output

    output=$(test::run_photoalbum --version)
    test::assert_contains 'This is Photoalbum Version' "$output"
}

test_init() {
    local config

    test::setup
    (
        cd "$TEST_TMPDIR"
        PHOTOALBUM_DEFAULT_RC="$TEST_TMPDIR/missing" \
            "$TEST_PHOTOALBUM" --init >/dev/null
        test::assert_file_exists photoalbum.conf
        test::assert_path_absent Makefile
    )
    config=$(<"$TEST_TMPDIR/photoalbum.conf")
    test::assert_contains \
        "TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default" \
        "$config"
    test::teardown
}

test_init_existing_config_fails_without_overwrite() {
    local output

    test::setup
    printf 'sentinel\n' > "$TEST_TMPDIR/photoalbum.conf"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_PHOTOALBUM" --init
    )

    test::assert_contains 'Error: photoalbum.conf already exists' "$output"
    test "$(cat "$TEST_TMPDIR/photoalbum.conf")" = 'sentinel'
    test::teardown
}

test_clean() {
    test::setup
    printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/photoalbum.conf"
    mkdir -p "$TEST_TMPDIR/dist"

    (
        cd "$TEST_TMPDIR"
        "$TEST_PHOTOALBUM" --clean
        test::assert_path_absent "$TEST_TMPDIR/dist"
    )
    test::teardown
}

test_clean_with_config() {
    local config_file

    test::setup
    config_file="$TEST_TMPDIR/custom.conf"
    printf 'DIST_DIR=%q/custom-dist\n' "$TEST_TMPDIR" > "$config_file"
    mkdir -p "$TEST_TMPDIR/custom-dist"

    (
        cd "$TEST_TMPDIR"
        "$TEST_PHOTOALBUM" --clean --config "$config_file"
        test::assert_path_absent "$TEST_TMPDIR/custom-dist"
    )
    test::teardown
}

test_clean_cli_dist_overrides_config() {
    local config_file

    test::setup
    config_file="$TEST_TMPDIR/photoalbum.conf"
    printf 'DIST_DIR=%q/config-dist\n' "$TEST_TMPDIR" > "$config_file"
    mkdir -p "$TEST_TMPDIR/config-dist" "$TEST_TMPDIR/cli-dist"

    (
        cd "$TEST_TMPDIR"
        "$TEST_PHOTOALBUM" --clean --dist "$TEST_TMPDIR/cli-dist"
        test::assert_dir_exists "$TEST_TMPDIR/config-dist"
        test::assert_path_absent "$TEST_TMPDIR/cli-dist"
    )
    test::teardown
}

test_missing_config_fails_without_legacy_fallbacks() {
    local default_rc
    local home_dir
    local generate_output
    local clean_output

    test::setup
    home_dir="$TEST_TMPDIR/home"
    default_rc="$TEST_TMPDIR/default-photoalbum"
    mkdir -p "$home_dir"

    printf 'DIST_DIR=%q/legacy-dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/photoalbumrc"
    printf 'DIST_DIR=%q/home-dist\n' "$TEST_TMPDIR" > "$home_dir/.photoalbumrc"
    printf 'DIST_DIR=%q/default-dist\n' "$TEST_TMPDIR" > "$default_rc"

    generate_output=$(
        cd "$TEST_TMPDIR"
        HOME="$home_dir" PHOTOALBUM_DEFAULT_RC="$default_rc" \
            test::capture_failure_output "$TEST_PHOTOALBUM" --generate
    )
    clean_output=$(
        cd "$TEST_TMPDIR"
        HOME="$home_dir" PHOTOALBUM_DEFAULT_RC="$default_rc" \
            test::capture_failure_output "$TEST_PHOTOALBUM" --clean
    )

    test::assert_contains 'Error: Can not find config file ./photoalbum.conf' \
        "$generate_output"
    test::assert_contains 'Run photoalbum --init to create ./photoalbum.conf.' \
        "$generate_output"
    test::assert_contains 'Error: Can not find config file ./photoalbum.conf' \
        "$clean_output"
    test::assert_contains 'Run photoalbum --init to create ./photoalbum.conf.' \
        "$clean_output"
    test::assert_path_absent "$TEST_TMPDIR/legacy-dist"
    test::assert_path_absent "$TEST_TMPDIR/home-dist"
    test::assert_path_absent "$TEST_TMPDIR/default-dist"
    test::teardown
}

test_generate_with_config_missing_incoming_fails() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/custom.conf"
    {
        printf 'INCOMING_DIR=%q/missing\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/custom-dist\n' "$TEST_TMPDIR"
    } > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_PHOTOALBUM" --generate --config "$config_file"
    )

    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    test::teardown
}

test_generate_with_config_succeeds_without_default_config() {
    local config_file
    local fake_bin

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/custom.conf"

    test::install_fake_imagemagick "$fake_bin"
    test::generate_fixture_images "$TEST_TMPDIR/custom-incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/custom-incoming" \
        "$TEST_TMPDIR/custom-dist" 'Custom config album' 3

    (
        cd "$TEST_TMPDIR"
        test::assert_path_absent photoalbum.conf
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" \
            --generate --config "$config_file"
    )

    test::assert_file_exists "$TEST_TMPDIR/custom-dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/custom-dist/html/page-2.html"
    test::teardown
}

test_generate_cli_overrides_config_values() {
    local config_file
    local fake_bin
    local page_html
    local view_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/cli-incoming"

    {
        printf 'TITLE=%q\n' 'Config title'
        printf 'THUMBHEIGHT=10\n'
        printf 'HEIGHT=20\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'SHUFFLE=yes\n'
        printf 'INCOMING_DIR=%q/config-incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/config-dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/config-template\n' "$TEST_TMPDIR"
        printf 'TARBALL_INCLUDE=yes\n'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" \
            --generate \
            --incoming "$TEST_TMPDIR/cli-incoming" \
            --dist "$TEST_TMPDIR/cli-dist" \
            --template "$TEST_REPO_ROOT/share/templates/default" \
            --title 'CLI title' \
            --height 456 \
            --thumbheight 45 \
            --maxpreviews 1 \
            --no-shuffle \
            --no-tarball
    )

    page_html=$(<"$TEST_TMPDIR/cli-dist/html/page-1.html")
    view_html=$(<"$TEST_TMPDIR/cli-dist/html/1-1.html")

    test::assert_file_exists "$TEST_TMPDIR/cli-dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/cli-dist/photos/02-portrait.jpg"
    test::assert_file_exists "$TEST_TMPDIR/cli-dist/photos/03-square.jpg"
    test::assert_file_exists \
        "$TEST_TMPDIR/cli-dist/photos/04 filename with spaces.jpg"
    test::assert_file_exists "$TEST_TMPDIR/cli-dist/photos/05-extra.jpg"
    test::assert_file_exists "$TEST_TMPDIR/cli-dist/photos/06-extra.jpg"
    test::assert_path_absent "$TEST_TMPDIR/config-dist"
    test::assert_find_count 0 "$TEST_TMPDIR/cli-dist" '*.tar'
    test::assert_contains '<title>CLI title</title>' "$page_html"
    test::assert_contains 'height: 45px;' "$page_html"
    test::assert_contains 'max-height: 456px;' "$view_html"
    test::assert_contains 'Next 1 pictures' "$page_html"
    test::assert_not_contains 'Config title' "$page_html"

    test::teardown
}

test_generate_shuffle_override_uses_random_order() {
    local config_file
    local fake_bin
    local sort_log_output
    local sort_log

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    sort_log="$TEST_TMPDIR/sort.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_sort_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Shuffle override' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_SORT_LOG="$sort_log" \
            "$TEST_PHOTOALBUM" --generate --shuffle
    )

    sort_log_output=$(<"$sort_log")
    test::assert_contains 'photo-shuffle -R' "$sort_log_output"
    test::teardown
}

test_generate_no_shuffle_override_uses_sorted_order() {
    local config_file
    local fake_bin
    local page_html
    local sort_log

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    sort_log="$TEST_TMPDIR/sort.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_sort_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No shuffle override' 40
    printf 'SHUFFLE=yes\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_SORT_LOG="$sort_log" \
            "$TEST_PHOTOALBUM" --generate --no-shuffle
    )

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")
    test::assert_contains_before \
        "name='01-landscape.jpg'" \
        "name='06-extra.jpg'" \
        "$page_html"
    test::assert_path_absent "$sort_log"
    test::teardown
}

test_generate_cli_tarball_overrides_config() {
    local config_file
    local fake_bin
    local tarball
    local tarball_listing

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Tarball override' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate --tarball
    )

    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tar' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
    tarball_listing=$(tar -tf "$tarball")
    test::assert_contains 'incoming/01-landscape.jpg' "$tarball_listing"

    test::teardown
}

test_generate_cli_no_tarball_overrides_config() {
    local config_file
    local fake_bin

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No tarball override' 40
    printf 'TARBALL_INCLUDE=yes\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate --no-tarball
    )

    test::assert_find_count 0 "$TEST_TMPDIR/dist" '*.tar'
    test::teardown
}

test_generate_missing_incoming_fails() {
    local output

    test::setup
    {
        printf 'INCOMING_DIR=%q/missing\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
    } > "$TEST_TMPDIR/photoalbum.conf"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_PHOTOALBUM" --generate
    )

    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    test::teardown
}

test_integration_generates_album_outputs_and_cleans() {
    local config_file
    local fake_bin
    local page_html
    local tarball
    local tarball_listing
    local top_index_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Integration album' 2

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/02-portrait.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/03-square.jpg"
    test::assert_file_exists \
        "$TEST_TMPDIR/dist/photos/04 filename with spaces.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/blurs/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/page-1.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/page-2.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/page-3.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/1-1.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/3-2.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/html/index.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/index.html"

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")
    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains "name='04 filename with spaces.jpg'" \
        "$(<"$TEST_TMPDIR/dist/html/page-2.html")"
    test::assert_contains 'Next 2 pictures' "$page_html"
    test::assert_contains 'url=./html/index.html' "$top_index_html"
    test::assert_find_count 0 "$TEST_TMPDIR/dist" '*.tar'

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate --tarball
    )
    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tar' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
    tarball_listing=$(tar -tf "$tarball")
    test::assert_contains \
        'incoming/04 filename with spaces.jpg' \
        "$tarball_listing"

    (
        cd "$TEST_TMPDIR"
        "$TEST_PHOTOALBUM" --clean
    )
    test::assert_path_absent "$TEST_TMPDIR/dist"
    test::teardown
}

test_generate_missing_imagemagick_fails() {
    local config_file
    local output
    local path_bin

    test::setup
    config_file="$TEST_TMPDIR/photoalbum.conf"
    path_bin="$TEST_TMPDIR/path-bin"

    test::install_coreutils_without_imagemagick "$path_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Missing ImageMagick' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$path_bin" test::capture_failure_output \
            "$TEST_PHOTOALBUM" --generate
    )

    test::assert_contains \
        'ERROR: ImageMagick is required; install magick or convert' \
        "$output"
    test::teardown
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

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    photo_name="kid's_\"<tag>&.jpg"
    photo_html='kid&#39;s_&quot;&lt;tag&gt;&amp;.jpg'
    css_photo='kid\000027s_\000022\00003ctag\00003e\000026.jpg'
    title="A & \"quoted\" <title> 'ok'"
    title_html='A &amp; &quot;quoted&quot; &lt;title&gt; &#39;ok&#39;'
    original_basepath="https://example.test/original?album=\"<x>&owner=O'Neil"
    original_basepath_html='https://example.test/original?album=&quot;&lt;x&gt;&amp;owner=O&#39;Neil'

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/$photo_name"

    {
        printf 'TITLE=%q\n' "$title"
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$TEST_REPO_ROOT"
        printf 'ORIGINAL_BASEPATH=%q\n' "$original_basepath"
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TARBALL_SUFFIX=%q\n' '&"'\''.tar'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")
    view_html=$(<"$TEST_TMPDIR/dist/html/1-1.html")

    test::assert_contains "<title>$title_html</title>" "$page_html"
    test::assert_contains \
        "background-image: url(\"../blurs/$css_photo\");" \
        "$page_html"
    test::assert_contains "name='$photo_html'" "$page_html"
    test::assert_contains "src='../thumbs/$photo_html'" "$page_html"
    test::assert_contains '&amp;&quot;&#39;.tar' "$page_html"
    test::assert_contains "href=\"page-1.html#$photo_html\"" "$view_html"
    test::assert_contains "href ='../photos/$photo_html'" "$view_html"
    test::assert_contains \
        "href=\"$original_basepath_html/$photo_html\"" \
        "$view_html"
    test::assert_not_contains '<title>A & "quoted" <title>' "$page_html"
    test::assert_not_contains "$photo_name" "$view_html"

    test::teardown
}

test_generate_preserves_space_filename_without_reprocessing() {
    local config_file
    local fake_bin
    local first_output
    local photo_name
    local second_output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"
    photo_name='a b.jpg'

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/$photo_name"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Space test' 40

    first_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate
    )
    second_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/$photo_name"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/a_b.jpg"
    test::assert_contains "Processing $photo_name to" "$first_output"
    test::assert_contains \
        "Already exists: $TEST_TMPDIR/dist/photos/$photo_name" \
        "$second_output"
    test::assert_not_contains "Processing $photo_name to" "$second_output"

    test::teardown
}

test_generate_handles_space_and_underscore_names_distinctly() {
    local config_file
    local fake_bin
    local page_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/photoalbum.conf"

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a b.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a_b.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Collision test' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_PHOTOALBUM" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/html/page-1.html")

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/a b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/a_b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/a b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/a_b.jpg"
    test::assert_contains "src='../thumbs/a b.jpg'" "$page_html"
    test::assert_contains "src='../thumbs/a_b.jpg'" "$page_html"

    test::teardown
}

test_positional_commands_fail_without_deprecation() {
    local output
    local old_command
    local -a old_commands=(clean generate version makemake)

    for old_command in "${old_commands[@]}"; do
        output=$(test::capture_failure_output "$TEST_PHOTOALBUM" "$old_command")
        test::assert_contains 'Usage:' "$output"
        test::assert_not_contains 'deprecat' "$output"
        test::assert_not_contains 'makemake' "$output"
    done
}

test_unknown_options_and_conflicting_actions_fail() {
    test::assert_failure 'unsupported option is rejected' \
        "$TEST_PHOTOALBUM" --unknown
    test::assert_failure 'generate/clean conflict is rejected' \
        "$TEST_PHOTOALBUM" --generate --clean
    test::assert_failure 'generate/init conflict is rejected' \
        "$TEST_PHOTOALBUM" --generate --init
    test::assert_failure 'clean/version conflict is rejected' \
        "$TEST_PHOTOALBUM" --clean --version
}

test_empty_args_fail() {
    local output

    output=$(test::capture_failure_output "$TEST_PHOTOALBUM")
    test::assert_contains 'Usage:' "$output"
}

test_extra_args_fail() {
    test::assert_failure 'extra operand is rejected' "$TEST_PHOTOALBUM" --version extra
    test::assert_failure \
        '--incoming is rejected with --version' \
        "$TEST_PHOTOALBUM" --version --incoming /tmp/incoming
    test::assert_failure \
        '--config is rejected with --init' \
        "$TEST_PHOTOALBUM" --init --config custom.conf
}

test_missing_option_values_fail() {
    local option
    local -a value_options=(
        --config
        --incoming
        --dist
        --template
        --title
        --height
        --thumbheight
        --maxpreviews
    )

    for option in "${value_options[@]}"; do
        test::assert_failure "$option requires a value" "$TEST_PHOTOALBUM" "$option"
    done
}

main() {
    trap test::teardown EXIT

    test::run_case '--version succeeds' test_version
    test::run_case '--init succeeds' test_init
    test::run_case \
        '--init refuses existing config without overwrite' \
        test_init_existing_config_fails_without_overwrite
    test::run_case '--clean succeeds' test_clean
    test::run_case '--clean --config succeeds' test_clean_with_config
    test::run_case '--clean --dist overrides config' \
        test_clean_cli_dist_overrides_config
    test::run_case \
        'missing config ignores legacy fallbacks' \
        test_missing_config_fails_without_legacy_fallbacks
    test::run_case \
        '--generate --config reads selected config on failure path' \
        test_generate_with_config_missing_incoming_fails
    test::run_case \
        '--generate --config succeeds without default config' \
        test_generate_with_config_succeeds_without_default_config
    test::run_case \
        '--generate CLI options override config' \
        test_generate_cli_overrides_config_values
    test::run_case \
        '--generate --shuffle overrides config' \
        test_generate_shuffle_override_uses_random_order
    test::run_case \
        '--generate --no-shuffle overrides config' \
        test_generate_no_shuffle_override_uses_sorted_order
    test::run_case \
        '--generate --tarball overrides config' \
        test_generate_cli_tarball_overrides_config
    test::run_case \
        '--generate --no-tarball overrides config' \
        test_generate_cli_no_tarball_overrides_config
    test::run_case \
        '--generate missing incoming fails' \
        test_generate_missing_incoming_fails
    test::run_case \
        '--generate creates output structure and --clean removes it' \
        test_integration_generates_album_outputs_and_cleans
    test::run_case \
        '--generate fails when ImageMagick is missing' \
        test_generate_missing_imagemagick_fails
    test::run_case \
        '--generate escapes generated HTML values' \
        test_generate_escapes_html_values
    test::run_case \
        '--generate preserves filenames with spaces without reprocessing' \
        test_generate_preserves_space_filename_without_reprocessing
    test::run_case \
        '--generate handles spaces and underscores distinctly' \
        test_generate_handles_space_and_underscore_names_distinctly
    test::run_case \
        'positional commands fail without deprecation output' \
        test_positional_commands_fail_without_deprecation
    test::run_case \
        'unknown options and conflicting actions fail' \
        test_unknown_options_and_conflicting_actions_fail
    test::run_case 'empty args fail' test_empty_args_fail
    test::run_case 'extra args fail' test_extra_args_fail
    test::run_case 'missing option values fail' test_missing_option_values_fail
}

main "$@"
