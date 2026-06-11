#!/usr/bin/env bash
set -euo pipefail

TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -r TEST_REPO_ROOT
declare -r TEST_SHURIKEN="${SHURIKEN:-$TEST_REPO_ROOT/bin/shuriken}"

# shellcheck source=tests/helpers.sh
source "$TEST_REPO_ROOT/tests/helpers.sh"

test::write_preflight_config() {
    local -r config_file="$1"; shift
    local -r incoming_dir="$1"; shift
    local -r dist_dir="$1"; shift
    local -r template_dir="$1"; shift
    local -r omitted_var="${1:-}"

    {
        if [ "$omitted_var" != TITLE ]; then
            printf 'TITLE=%q\n' 'Preflight album'
        fi
        if [ "$omitted_var" != THUMBHEIGHT ]; then
            printf 'THUMBHEIGHT=30\n'
        fi
        if [ "$omitted_var" != HEIGHT ]; then
            printf 'HEIGHT=120\n'
        fi
        if [ "$omitted_var" != MAXPREVIEWS ]; then
            printf 'MAXPREVIEWS=40\n'
        fi
        if [ "$omitted_var" != IMAGE_JOBS ]; then
            printf 'IMAGE_JOBS=3\n'
        fi
        if [ "$omitted_var" != INCOMING_DIR ]; then
            printf 'INCOMING_DIR=%q\n' "$incoming_dir"
        fi
        if [ "$omitted_var" != DIST_DIR ]; then
            printf 'DIST_DIR=%q\n' "$dist_dir"
        fi
        if [ "$omitted_var" != TEMPLATE_DIR ]; then
            printf 'TEMPLATE_DIR=%q\n' "$template_dir"
        fi
        if [ "$omitted_var" != SHUFFLE ]; then
            printf 'SHUFFLE=no\n'
        fi
        if [ "$omitted_var" != SPLASH_PAGE ]; then
            printf 'SPLASH_PAGE=yes\n'
        fi
        if [ "$omitted_var" != TARBALL_INCLUDE ]; then
            printf 'TARBALL_INCLUDE=no\n'
        fi
    } > "$config_file"
}

test::assert_generation_metadata() {
    local -r metadata_file="$1"; shift
    local -r config_source="$1"; shift
    local -r incoming_dir="$1"; shift
    local -r dist_dir="$1"; shift
    local -r template_dir="$1"; shift
    local -r tarball_included="$1"; shift
    local -r title="$1"; shift
    local -r maxpreviews="$1"; shift

    python3 - \
        "$metadata_file" \
        "$config_source" \
        "$incoming_dir" \
        "$dist_dir" \
        "$template_dir" \
        "$tarball_included" \
        "$title" \
        "$maxpreviews" <<'PY'
import datetime
import json
import pathlib
import re
import sys

(
    metadata_file,
    config_source,
    incoming_dir,
    dist_dir,
    template_dir,
    tarball_included,
    title,
    maxpreviews,
) = sys.argv[1:]

metadata = json.loads(pathlib.Path(metadata_file).read_text())
required = {
    "generator",
    "generated_at",
    "config_source",
    "template",
    "source",
    "generated",
    "tarball",
    "settings",
}
missing = sorted(required - set(metadata))
assert not missing, f"missing metadata keys: {missing}"

timestamp = metadata["generated_at"]
assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", timestamp)
datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")

incoming_path = pathlib.Path(incoming_dir)
dist_path = pathlib.Path(dist_dir)
template_path = pathlib.Path(template_dir)
tarball_expected = tarball_included == "yes"
tarball_files = sorted(path.name for path in dist_path.glob("*.tar"))

assert metadata["generator"]["name"] == "shuriken"
assert re.fullmatch(r"\d+\.\d+\.\d+", metadata["generator"]["version"])
assert metadata["config_source"] == config_source
assert metadata["template"]["directory"] == template_dir
assert metadata["template"]["name"] == template_path.name
assert metadata["source"]["incoming_dir"] == incoming_dir
supported_extensions = {".gif", ".jpeg", ".jpg", ".png", ".webp"}
assert metadata["source"]["image_count"] == sum(
    1
    for path in incoming_path.iterdir()
    if path.is_file() and path.suffix.lower() in supported_extensions
)
assert metadata["generated"]["photo_count"] == sum(
    1 for path in (dist_path / "photos").iterdir() if path.is_file()
)
assert metadata["generated"]["thumb_count"] == sum(
    1 for path in (dist_path / "thumbs").iterdir() if path.is_file()
)
assert metadata["generated"]["html_count"] == sum(
    1 for path in dist_path.rglob("*.html") if path.is_file()
)
assert metadata["tarball"]["included"] is tarball_expected
assert metadata["tarball"]["file"] == (tarball_files[0] if tarball_files else "")
assert metadata["settings"]["title"] == title
assert metadata["settings"]["height"] == "120"
assert metadata["settings"]["thumbheight"] == "30"
assert metadata["settings"]["maxpreviews"] == maxpreviews
assert metadata["settings"]["image_jobs"] == "3"
assert metadata["settings"]["shuffle"] is False
assert isinstance(metadata["settings"]["splash_page"], bool)
assert "original_basepath" in metadata["settings"]
PY
}

test::assert_no_html_subdir_output() {
    local -r dist_dir="$1"; shift

    test::assert_path_absent "$dist_dir/html"
    if grep -R -n --include='*.html' 'html/' "$dist_dir"; then
        echo "FAIL: expected no html/ links in generated HTML" >&2
        exit 1
    fi
}

test_version() {
    local output

    output=$(test::run_shuriken --version)
    test::assert_contains 'This is Shuriken Version' "$output"
}

test_init() {
    local config

    test::setup
    (
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_RC="$TEST_TMPDIR/missing" \
            "$TEST_SHURIKEN" --init >/dev/null
        test::assert_file_exists shuriken.conf
    )
    config=$(<"$TEST_TMPDIR/shuriken.conf")
    test::assert_contains \
        "TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default" \
        "$config"
    test::teardown
}

test_init_with_hash_in_source_path() {
    local config
    local output_dir
    local repo_dir

    test::setup
    repo_dir="$TEST_TMPDIR/repo#with-hash"
    output_dir="$TEST_TMPDIR/output"
    mkdir -p "$repo_dir" "$output_dir"
    cp -R \
        "$TEST_REPO_ROOT/bin" \
        "$TEST_REPO_ROOT/share" \
        "$TEST_REPO_ROOT/src" \
        "$repo_dir/"

    (
        cd "$output_dir"
        SHURIKEN_DEFAULT_RC="$TEST_TMPDIR/missing" \
            "$repo_dir/bin/shuriken" --init >/dev/null
        test::assert_file_exists shuriken.conf
    )
    config=$(<"$output_dir/shuriken.conf")
    test::assert_contains \
        "TEMPLATE_DIR=$repo_dir/share/templates/default" \
        "$config"
    test::teardown
}

test_init_existing_config_fails_without_overwrite() {
    local output

    test::setup
    printf 'sentinel\n' > "$TEST_TMPDIR/shuriken.conf"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --init
    )

    test::assert_contains 'Error: shuriken.conf already exists' "$output"
    test "$(<"$TEST_TMPDIR/shuriken.conf")" = 'sentinel'
    test::teardown
}

test_just_install_and_deinstall_with_destdir() {
    local stage_dir

    test::setup
    stage_dir="$TEST_TMPDIR/stage"

    (
        cd "$TEST_REPO_ROOT"
        DESTDIR="$stage_dir" PREFIX=/usr just install
    )

    test::assert_file_exists "$stage_dir/usr/bin/shuriken"
    test::assert_file_exists "$stage_dir/etc/default/shuriken"
    test::assert_file_exists \
        "$stage_dir/usr/share/shuriken/templates/default/view.tmpl"
    test::assert_file_exists "$stage_dir/usr/share/shuriken/assets/favicon.ico"

    (
        cd "$TEST_REPO_ROOT"
        DESTDIR="$stage_dir" PREFIX=/usr just deinstall
    )

    test::assert_path_absent "$stage_dir/usr/bin/shuriken"
    test::assert_path_absent "$stage_dir/etc/default/shuriken"
    test::assert_path_absent "$stage_dir/usr/share/shuriken"
    test::teardown
}

test_clean() {
    local staging_dir

    test::setup
    printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/shuriken.conf"
    mkdir -p "$TEST_TMPDIR/dist"
    staging_dir="$TEST_TMPDIR/.shuriken.dist.staging.manual"
    mkdir -p "$staging_dir"

    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --clean
        test::assert_path_absent "$TEST_TMPDIR/dist"
        test::assert_dir_exists "$staging_dir"
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
        "$TEST_SHURIKEN" --clean --config "$config_file"
        test::assert_path_absent "$TEST_TMPDIR/custom-dist"
    )
    test::teardown
}

test_clean_cli_dist_overrides_config() {
    local config_file

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    printf 'DIST_DIR=%q/config-dist\n' "$TEST_TMPDIR" > "$config_file"
    mkdir -p "$TEST_TMPDIR/config-dist" "$TEST_TMPDIR/cli-dist"

    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --clean --dist "$TEST_TMPDIR/cli-dist"
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
    default_rc="$TEST_TMPDIR/default-shuriken"
    mkdir -p "$home_dir"

    printf 'DIST_DIR=%q/legacy-dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/shurikenrc"
    printf 'DIST_DIR=%q/home-dist\n' "$TEST_TMPDIR" > "$home_dir/.shurikenrc"
    printf 'DIST_DIR=%q/default-dist\n' "$TEST_TMPDIR" > "$default_rc"

    generate_output=$(
        cd "$TEST_TMPDIR"
        HOME="$home_dir" SHURIKEN_DEFAULT_RC="$default_rc" \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )
    clean_output=$(
        cd "$TEST_TMPDIR"
        HOME="$home_dir" SHURIKEN_DEFAULT_RC="$default_rc" \
            test::capture_failure_output "$TEST_SHURIKEN" --clean
    )

    test::assert_contains 'Error: Can not find config file ./shuriken.conf' \
        "$generate_output"
    test::assert_contains 'Run shuriken --init to create ./shuriken.conf.' \
        "$generate_output"
    test::assert_contains 'Error: Can not find config file ./shuriken.conf' \
        "$clean_output"
    test::assert_contains 'Run shuriken --init to create ./shuriken.conf.' \
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
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/missing" "$TEST_TMPDIR/custom-dist" \
        'Missing incoming config' 40

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_SHURIKEN" --generate --config "$config_file"
    )

    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/custom-dist"
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
        test::assert_path_absent shuriken.conf
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --generate --config "$config_file"
    )

    test::assert_file_exists "$TEST_TMPDIR/custom-dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/custom-dist/page-2.html"
    test::assert_path_absent "$TEST_TMPDIR/custom-dist/html"
    test::teardown
}

test_generate_cli_overrides_config_values() {
    local config_file
    local fake_bin
    local page_html
    local view_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

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
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
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

    page_html=$(<"$TEST_TMPDIR/cli-dist/page-1.html")
    view_html=$(<"$TEST_TMPDIR/cli-dist/1-1.html")

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
    test::assert_contains 'href="page-2.html" class="arrow">&rArr;</a>' \
        "$page_html"
    test::assert_not_contains 'Config title' "$page_html"

    test::teardown
}

test_generate_height_bounds_photo_height_without_upscaling() {
    local config_file
    local -a create_command=()
    local height
    local -a identify_command=()
    local landscape_dimensions
    local portrait_dimensions
    local small_portrait_dimensions

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    height=120

    if command -v magick >/dev/null 2>&1; then
        create_command=(magick)
        identify_command=(magick identify)
    else
        create_command=(convert)
        identify_command=(identify)
    fi

    mkdir -p "$TEST_TMPDIR/incoming"
    "${create_command[@]}" \
        -size 800x600 xc:red "$TEST_TMPDIR/incoming/landscape.jpg"
    "${create_command[@]}" \
        -size 600x800 xc:blue "$TEST_TMPDIR/incoming/portrait.jpg"
    "${create_command[@]}" \
        -size 60x80 xc:green "$TEST_TMPDIR/incoming/small-portrait.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Height bounds album' 40

    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --generate
    )

    landscape_dimensions=$(
        "${identify_command[@]}" -format '%wx%h' \
            "$TEST_TMPDIR/dist/photos/landscape.jpg"
    )
    portrait_dimensions=$(
        "${identify_command[@]}" -format '%wx%h' \
            "$TEST_TMPDIR/dist/photos/portrait.jpg"
    )
    small_portrait_dimensions=$(
        "${identify_command[@]}" -format '%wx%h' \
            "$TEST_TMPDIR/dist/photos/small-portrait.jpg"
    )

    if [ "$landscape_dimensions" != "160x$height" ]; then
        echo "FAIL: expected landscape photo height to be $height" >&2
        echo "found $landscape_dimensions" >&2
        exit 1
    fi
    if [ "$portrait_dimensions" != "90x$height" ]; then
        echo "FAIL: expected portrait photo height to be $height" >&2
        echo "found $portrait_dimensions" >&2
        exit 1
    fi
    if [ "$small_portrait_dimensions" != '60x80' ]; then
        echo 'FAIL: expected smaller portrait photo not to be upscaled' >&2
        echo "found $small_portrait_dimensions" >&2
        exit 1
    fi

    test::teardown
}

test_generate_shuffle_override_uses_random_order() {
    local config_file
    local fake_bin
    local sort_log_output
    local sort_log

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
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
            "$TEST_SHURIKEN" --generate --shuffle
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
    config_file="$TEST_TMPDIR/shuriken.conf"
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
            "$TEST_SHURIKEN" --generate --no-shuffle
    )

    page_html=$(<"$TEST_TMPDIR/dist/page-1.html")
    test::assert_contains_before \
        "name='01-landscape.jpg'" \
        "name='06-extra.jpg'" \
        "$page_html"
    test::assert_path_absent "$sort_log"
    test::teardown
}

test_generate_random_seed_repeats_html_with_shuffle() {
    local config_file
    local fake_bin
    local sort_log

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    sort_log="$TEST_TMPDIR/sort.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_sort_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist-one" \
        'Seeded shuffle album' 2

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_SORT_LOG="$sort_log" \
            "$TEST_SHURIKEN" \
                --generate \
                --shuffle \
                --random-seed stable-seed \
                --dist "$TEST_TMPDIR/dist-one"
        PATH="$fake_bin:$PATH" TEST_SORT_LOG="$sort_log" \
            "$TEST_SHURIKEN" \
                --generate \
                --shuffle \
                --random-seed stable-seed \
                --dist "$TEST_TMPDIR/dist-two"
    )

    if ! diff -ru \
        --exclude=blurs \
        --exclude=shuriken.json \
        --exclude=photos \
        --exclude=thumbs \
        "$TEST_TMPDIR/dist-one" \
        "$TEST_TMPDIR/dist-two"; then
        echo 'FAIL: seeded generation should produce identical HTML' >&2
        exit 1
    fi
    if ! cmp -s "$TEST_TMPDIR/dist-one/index.html" \
        "$TEST_TMPDIR/dist-two/index.html"; then
        echo 'FAIL: seeded generation should produce identical top-level HTML' >&2
        exit 1
    fi

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
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Tarball override' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate --tarball
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
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No tarball override' 40
    printf 'TARBALL_INCLUDE=yes\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate --no-tarball
    )

    test::assert_find_count 0 "$TEST_TMPDIR/dist" '*.tar'
    test::teardown
}

test_generate_default_tar_opts_create_archive() {
    local config_file
    local fake_bin
    local tar_log
    local tarball
    local tarball_listing

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    tar_log="$TEST_TMPDIR/tar.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_tar_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Default tar opts' 40
    printf 'TARBALL_INCLUDE=yes\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_TAR_LOG="$tar_log" \
            "$TEST_SHURIKEN" --generate
    )

    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tar' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
    tarball_listing=$(tar -tf "$tarball")
    test::assert_contains 'incoming/01-landscape.jpg' "$tarball_listing"
    test::assert_contains $'arg0=-c\narg1=-f' "$(<"$tar_log")"
    test::teardown
}

test_generate_custom_tarball_suffix_cleans_previous_archive() {
    local config_file
    local fake_bin
    local first_tarball
    local second_tarball

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    cat > "$fake_bin/date" <<'DATE'
#!/usr/bin/env bash
set -euo pipefail

count=0
if [ -f "$TEST_FAKE_DATE_COUNTER" ]; then
    count=$(<"$TEST_FAKE_DATE_COUNTER")
fi
count=$(( count + 1 ))
printf '%s\n' "$count" > "$TEST_FAKE_DATE_COUNTER"

if [ "${1:-}" = -u ]; then
    printf '2026-06-05T12:00:%02dZ\n' "$count"
else
    printf '2026-06-05-1200%02d\n' "$count"
fi
DATE
    chmod 0755 "$fake_bin/date"

    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Custom tarball suffix cleanup' 40
    {
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TARBALL_SUFFIX=.tgz\n'
    } >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_FAKE_DATE_COUNTER="$TEST_TMPDIR/date-count" \
            "$TEST_SHURIKEN" --generate
    )
    first_tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tgz' -print)

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_FAKE_DATE_COUNTER="$TEST_TMPDIR/date-count" \
            "$TEST_SHURIKEN" --generate
    )

    test::assert_find_count 1 "$TEST_TMPDIR/dist" '*.tgz'
    test::assert_path_absent "$first_tarball"
    second_tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tgz' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$second_tarball"

    test::teardown
}

test_generate_scalar_multi_tar_opts_create_archive() {
    local config_file
    local fake_bin
    local tar_log
    local tarball
    local tarball_listing

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    tar_log="$TEST_TMPDIR/tar.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_tar_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Scalar multi tar opts' 40
    {
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TAR_OPTS=%q\n' '--sort=name --mtime=@0 -c'
    } >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_TAR_LOG="$tar_log" \
            "$TEST_SHURIKEN" --generate
    )

    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tar' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
    tarball_listing=$(tar -tf "$tarball")
    test::assert_contains 'incoming/01-landscape.jpg' "$tarball_listing"
    test::assert_contains \
        $'arg0=--sort=name\narg1=--mtime=@0\narg2=-c\narg3=-f' \
        "$(<"$tar_log")"
    test::teardown
}

test_default_output_reports_routine_progress() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Default output album' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'Processing 01-landscape.jpg to' "$output"
    test::assert_contains 'Rendering header template into ' "$output"
    test::assert_contains 'Rendering view template into ' "$output"
    test::assert_contains 'Creating thumb ' "$output"
    test::assert_not_contains 'Verbose:' "$output"
    test::teardown
}

test_quiet_output_suppresses_routine_progress() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Quiet output album' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --quiet --generate
    )

    test::assert_not_contains 'Processing ' "$output"
    test::assert_not_contains 'Rendering ' "$output"
    test::assert_not_contains 'Creating thumb ' "$output"
    test::assert_file_exists "$TEST_TMPDIR/dist/shuriken.json"
    test::teardown
}

test_quiet_output_keeps_errors_on_stderr() {
    local config_file
    local output_file
    local stderr_file
    local stdout
    local stderr
    local -i status=0

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    output_file="$TEST_TMPDIR/stdout"
    stderr_file="$TEST_TMPDIR/stderr"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/missing" "$TEST_TMPDIR/dist" \
        'Quiet error album' 40

    set +e
    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --quiet --generate \
            > "$output_file" 2> "$stderr_file"
    )
    status=$?
    set -e

    if (( status == 0 )); then
        echo 'FAIL: expected quiet generation to fail' >&2
        exit 1
    fi

    stdout=$(<"$output_file")
    stderr=$(<"$stderr_file")
    test "$stdout" = ''
    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$stderr"
    test::teardown
}

test_verbose_output_reports_processing_decisions() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Verbose output album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate >/dev/null
    )
    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --verbose --generate
    )

    test::assert_contains 'Verbose: Selected config file: ./shuriken.conf' \
        "$output"
    test::assert_contains "Verbose: Effective incoming directory: $TEST_TMPDIR/incoming" \
        "$output"
    test::assert_contains "Verbose: Effective output directory: $TEST_TMPDIR/dist" \
        "$output"
    test::assert_contains \
        "Verbose: Effective template directory: $TEST_REPO_ROOT/share/templates/default" \
        "$output"
    test::assert_contains \
        'Verbose: Tarball disabled; no archive will be created' \
        "$output"
    test::assert_contains \
        "Verbose: Skipped existing photo $TEST_TMPDIR/dist/photos/01-landscape.jpg" \
        "$output"
    test::assert_contains 'Verbose: Skipped existing thumb and blur' "$output"
    test::teardown
}

test_generate_image_jobs_limits_parallel_imagemagick() {
    local active_file
    local config_file
    local fake_bin
    local lock_file
    local log_file
    local max_file
    local max_seen

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    lock_file="$TEST_TMPDIR/parallel.lock"
    active_file="$TEST_TMPDIR/parallel.active"
    max_file="$TEST_TMPDIR/parallel.max"
    log_file="$TEST_TMPDIR/parallel.log"

    test::install_parallel_imagemagick_spy "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/02.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/03.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/04.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Parallel image jobs album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_PARALLEL_MAGICK_LOCK="$lock_file" \
            TEST_PARALLEL_MAGICK_ACTIVE="$active_file" \
            TEST_PARALLEL_MAGICK_MAX="$max_file" \
            TEST_PARALLEL_MAGICK_LOG="$log_file" \
            "$TEST_SHURIKEN" --image-jobs 2 --generate
    )

    max_seen=$(<"$max_file")
    if (( max_seen < 2 || max_seen > 2 )); then
        echo "FAIL: expected max parallel ImageMagick jobs to be 2" >&2
        echo "max_seen=$max_seen" >&2
        cat "$log_file" >&2
        exit 1
    fi
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/01.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/blurs/01.jpg"
    test::teardown
}

test_generate_image_jobs_waits_for_any_finished_imagemagick() {
    local config_file
    local fake_bin
    local finish_01_line
    local lock_file
    local log_file
    local log_output
    local start_03_line

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    lock_file="$TEST_TMPDIR/wait-n.lock"
    log_file="$TEST_TMPDIR/wait-n.log"

    test::install_wait_n_imagemagick_spy "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/02.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/03.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/04.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Wait n image jobs album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_WAIT_N_MAGICK_LOCK="$lock_file" \
            TEST_WAIT_N_MAGICK_LOG="$log_file" \
            "$TEST_SHURIKEN" --image-jobs 2 --generate
    )

    log_output=$(<"$log_file")
    test::assert_contains 'start photos/03.jpg' "$log_output"
    test::assert_contains 'finish photos/01.jpg' "$log_output"
    start_03_line=$(
        grep -n '^start photos/03\.jpg$' "$log_file" \
            | head -n 1 \
            | cut -d: -f1
    )
    finish_01_line=$(
        grep -n '^finish photos/01\.jpg$' "$log_file" \
            | head -n 1 \
            | cut -d: -f1
    )

    if (( start_03_line >= finish_01_line )); then
        echo 'FAIL: expected photos/03.jpg to start before photos/01.jpg finished' >&2
        cat "$log_file" >&2
        exit 1
    fi

    test::teardown
}

test_generate_image_jobs_limits_parallel_identify() {
    local active_file
    local config_file
    local fake_bin
    local identify_count
    local lock_file
    local log_file
    local max_file
    local max_seen

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    lock_file="$TEST_TMPDIR/identify.lock"
    active_file="$TEST_TMPDIR/identify.active"
    max_file="$TEST_TMPDIR/identify.max"
    log_file="$TEST_TMPDIR/identify.log"

    test::install_parallel_identify_spy "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/02.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/03.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/04.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Parallel identify album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_PARALLEL_IDENTIFY_LOCK="$lock_file" \
            TEST_PARALLEL_IDENTIFY_ACTIVE="$active_file" \
            TEST_PARALLEL_IDENTIFY_MAX="$max_file" \
            TEST_PARALLEL_IDENTIFY_LOG="$log_file" \
            "$TEST_SHURIKEN" --image-jobs 2 --generate
    )

    max_seen=$(<"$max_file")
    if (( max_seen > 2 )); then
        echo 'FAIL: expected at most 2 parallel ImageMagick identify jobs' >&2
        echo "max_seen=$max_seen" >&2
        cat "$log_file" >&2
        exit 1
    fi

    identify_count=$(grep -c '^start ' "$log_file")
    if (( identify_count != 4 )); then
        echo 'FAIL: expected one identify call per source image' >&2
        echo "identify_count=$identify_count" >&2
        cat "$log_file" >&2
        exit 1
    fi
    test::teardown
}

test_generate_image_jobs_limits_parallel_template_rendering() {
    local active_file
    local config_file
    local fake_bin
    local lock_file
    local log_file
    local max_file
    local max_seen
    local render_count
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"
    lock_file="$TEST_TMPDIR/template.lock"
    active_file="$TEST_TMPDIR/template.active"
    max_file="$TEST_TMPDIR/template.max"
    log_file="$TEST_TMPDIR/template.log"

    test::install_fake_imagemagick "$fake_bin"
    test::install_parallel_template_spy \
        "$template_dir" \
        "$lock_file" \
        "$active_file" \
        "$max_file" \
        "$log_file"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/02.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/03.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/04.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Parallel template album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --image-jobs 2 \
            --template "$template_dir" \
            --generate
    )

    max_seen=$(<"$max_file")
    if (( max_seen != 2 )); then
        echo 'FAIL: expected max parallel template render jobs to be 2' >&2
        echo "max_seen=$max_seen" >&2
        cat "$log_file" >&2
        exit 1
    fi

    render_count=$(grep -c '^start ' "$log_file")
    if (( render_count != 8 )); then
        echo 'FAIL: expected view and details templates for each image' >&2
        echo "render_count=$render_count" >&2
        cat "$log_file" >&2
        exit 1
    fi
    test::teardown
}

test_repeated_output_flags_use_last_value() {
    local config_file
    local fake_bin
    local quiet_last_output
    local verbose_last_output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Repeated output flags album' 40

    verbose_last_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --quiet --verbose --generate
    )
    quiet_last_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --verbose --quiet --generate
    )

    test::assert_contains 'Verbose: Selected config file: ./shuriken.conf' \
        "$verbose_last_output"
    test::assert_not_contains 'Verbose:' "$quiet_last_output"
    test::assert_not_contains 'Processing ' "$quiet_last_output"
    test::assert_not_contains 'Rendering ' "$quiet_last_output"
    test::teardown
}

test_print_config_reflects_defaults() {
    local expected
    local output

    test::setup

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$TEST_TMPDIR/missing-installed" \
            "$TEST_SHURIKEN" \
            --print-config \
            --config "$TEST_REPO_ROOT/src/shuriken.default.conf"
    )
    expected=$(cat <<EOF
CONFIG_SOURCE=$TEST_REPO_ROOT/src/shuriken.default.conf
INCOMING_DIR=$TEST_TMPDIR/incoming
DIST_DIR=$TEST_TMPDIR/dist
TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default
TITLE=A\\ simple\\ Shuriken
HEIGHT=1200
THUMBHEIGHT=300
MAXPREVIEWS=40
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=no
SPLASH_PAGE=yes
TARBALL_INCLUDE=yes
TARBALL_SUFFIX=.tar
TAR_TIMEOUT=120
TAR_OPTS=( -c )
SYNC_DELETE=yes
SYNC_DESTINATIONS=( )
ORIGINAL_BASEPATH=''
EOF
)

    test "$output" = "$expected"
    test::teardown
}

test_print_config_keeps_explicit_config_template_dir() {
    local config_file
    local output
    local template_dir

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/explicit-config-template"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Explicit config template' 8
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$TEST_TMPDIR/missing-installed" \
            "$TEST_SHURIKEN" --print-config
    )

    test::assert_contains "TEMPLATE_DIR=$template_dir" "$output"
    test::teardown
}

test_print_config_resolves_installed_default_template() {
    local config_file
    local installed_template_dir
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    installed_template_dir="$TEST_TMPDIR/usr/share/shuriken/templates/default"
    mkdir -p "$(dirname "$installed_template_dir")"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$installed_template_dir"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        /usr/share/shuriken/templates/default

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$installed_template_dir" \
            "$TEST_SHURIKEN" --print-config
    )

    test::assert_contains "TEMPLATE_DIR=$installed_template_dir" "$output"
    test::teardown
}

test_print_config_resolves_repo_default_template() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        /usr/share/shuriken/templates/default

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$TEST_TMPDIR/missing-installed" \
            "$TEST_SHURIKEN" --print-config
    )

    test::assert_contains \
        "TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default" \
        "$output"
    test::teardown
}

test_print_config_keeps_cli_template_override() {
    local config_file
    local installed_template_dir
    local output
    local template_dir

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    installed_template_dir="$TEST_TMPDIR/usr/share/shuriken/templates/default"
    template_dir="$TEST_TMPDIR/cli-template"
    mkdir -p "$(dirname "$installed_template_dir")"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$installed_template_dir"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        /usr/share/shuriken/templates/default

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$installed_template_dir" \
            "$TEST_SHURIKEN" --print-config --template "$template_dir"
    )

    test::assert_contains "TEMPLATE_DIR=$template_dir" "$output"
    test::teardown
}

test_print_config_reads_selected_config() {
    local config_file
    local expected
    local output

    test::setup
    config_file="$TEST_TMPDIR/custom.conf"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/custom-incoming" \
        "$TEST_TMPDIR/custom-dist" 'Selected config' 7
    printf 'SHUFFLE=yes\n' >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --print-config --config "$config_file"
    )
    expected=$(cat <<EOF
CONFIG_SOURCE=$config_file
INCOMING_DIR=$TEST_TMPDIR/custom-incoming
DIST_DIR=$TEST_TMPDIR/custom-dist
TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default
TITLE=Selected\\ config
HEIGHT=120
THUMBHEIGHT=30
MAXPREVIEWS=7
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=yes
SPLASH_PAGE=yes
TARBALL_INCLUDE=no
TARBALL_SUFFIX=.tar
TAR_TIMEOUT=120
TAR_OPTS=( -c )
SYNC_DELETE=yes
SYNC_DESTINATIONS=( )
ORIGINAL_BASEPATH=''
EOF
)

    test "$output" = "$expected"
    test::teardown
}

test_print_config_reads_current_directory_config() {
    local expected
    local output

    test::setup
    test::write_album_config \
        "$TEST_TMPDIR/shuriken.conf" "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist" 'Current directory config' 8

    output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --print-config
    )
    expected=$(cat <<EOF
CONFIG_SOURCE=./shuriken.conf
INCOMING_DIR=$TEST_TMPDIR/incoming
DIST_DIR=$TEST_TMPDIR/dist
TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default
TITLE=Current\\ directory\\ config
HEIGHT=120
THUMBHEIGHT=30
MAXPREVIEWS=8
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=no
SPLASH_PAGE=yes
TARBALL_INCLUDE=no
TARBALL_SUFFIX=.tar
TAR_TIMEOUT=120
TAR_OPTS=( -c )
SYNC_DELETE=yes
SYNC_DESTINATIONS=( )
ORIGINAL_BASEPATH=''
EOF
)

    test "$output" = "$expected"
    test::teardown
}

test_print_config_applies_cli_overrides_without_writes() {
    local config_file
    local dist_dir
    local expected
    local fake_bin
    local forbidden_log
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/cli-dist"
    forbidden_log="$TEST_TMPDIR/forbidden-tools.log"

    test::install_failing_generation_tools "$fake_bin"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/config-incoming" \
        "$TEST_TMPDIR/config-dist" 'Config title' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_FORBIDDEN_TOOL_LOG="$forbidden_log" \
            "$TEST_SHURIKEN" \
                --print-config \
                --incoming "$TEST_TMPDIR/cli-incoming" \
                --dist "$dist_dir" \
                --template "$TEST_TMPDIR/cli-template" \
                --title 'CLI title' \
                --height 456 \
                --thumbheight 45 \
                --maxpreviews 9 \
                --image-jobs 2 \
                --random-seed cli-seed \
                --shuffle \
                --no-splash \
                --tarball
    )
    expected=$(cat <<EOF
CONFIG_SOURCE=./shuriken.conf
INCOMING_DIR=$TEST_TMPDIR/cli-incoming
DIST_DIR=$dist_dir
TEMPLATE_DIR=$TEST_TMPDIR/cli-template
TITLE=CLI\\ title
HEIGHT=456
THUMBHEIGHT=45
MAXPREVIEWS=9
IMAGE_JOBS=2
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=cli-seed
SHUFFLE=yes
SPLASH_PAGE=no
TARBALL_INCLUDE=yes
TARBALL_SUFFIX=.tar
TAR_TIMEOUT=120
TAR_OPTS=( -c )
SYNC_DELETE=yes
SYNC_DESTINATIONS=( )
ORIGINAL_BASEPATH=''
EOF
)

    test "$output" = "$expected"
    test::assert_path_absent "$dist_dir"
    test::assert_path_absent "$TEST_TMPDIR/config-dist"
    test::assert_path_absent "$forbidden_log"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_print_config_applies_negative_cli_overrides() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Negative overrides' 40
    {
        printf 'SHUFFLE=yes\n'
        printf 'TARBALL_INCLUDE=yes\n'
    } >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" \
            --print-config --no-shuffle --no-splash --no-tarball
    )

    test::assert_contains 'SHUFFLE=no' "$output"
    test::assert_contains 'SPLASH_PAGE=no' "$output"
    test::assert_contains 'TARBALL_INCLUDE=no' "$output"
    test::teardown
}

test_print_config_normalizes_scalar_and_array_tar_opts() {
    local array_config
    local array_output
    local scalar_config
    local scalar_output

    test::setup
    scalar_config="$TEST_TMPDIR/scalar.conf"
    array_config="$TEST_TMPDIR/array.conf"
    test::write_album_config \
        "$scalar_config" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Scalar tar opts' 40
    {
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TAR_OPTS=%q\n' '--sort=name --mtime=@0 -c'
    } >> "$scalar_config"
    test::write_album_config \
        "$array_config" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Array tar opts' 40
    printf 'TAR_OPTS=(--sort=name --mtime=@0 -c)\n' >> "$array_config"

    scalar_output=$("$TEST_SHURIKEN" --print-config --config "$scalar_config")
    array_output=$("$TEST_SHURIKEN" --print-config --config "$array_config")

    test::assert_contains \
        'TAR_OPTS=( --sort=name --mtime=@0 -c )' \
        "$scalar_output"
    test::assert_contains \
        'TAR_OPTS=( --sort=name --mtime=@0 -c )' \
        "$array_output"
    test::teardown
}

test_print_config_quiet_and_verbose_keep_machine_output() {
    local config_file
    local plain_output
    local quiet_output
    local verbose_output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Output mode config' 40

    plain_output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --print-config
    )
    quiet_output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --quiet --print-config
    )
    verbose_output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --verbose --print-config
    )

    test "$quiet_output" = "$plain_output"
    test "$verbose_output" = "$plain_output"
    test::assert_not_contains 'Verbose:' "$verbose_output"
    test::teardown
}

test_print_config_validates_basic_values_without_generation_preflight() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/missing-incoming" \
        "$TEST_TMPDIR/missing-parent/dist" 'Printable missing paths' 40
    printf 'TEMPLATE_DIR=%q\n' "$TEST_TMPDIR/missing-template" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --print-config
    )
    test::assert_contains "INCOMING_DIR=$TEST_TMPDIR/missing-incoming" "$output"
    test::assert_contains "DIST_DIR=$TEST_TMPDIR/missing-parent/dist" "$output"
    test::assert_contains "TEMPLATE_DIR=$TEST_TMPDIR/missing-template" "$output"

    printf 'MAXPREVIEWS=not-a-number\n' >> "$config_file"
    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --print-config
    )
    test::assert_contains 'ERROR: MAXPREVIEWS must be a positive integer' \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/missing-parent"
    test::teardown
}

test_dry_run_reports_cli_overrides_without_writes() {
    local config_file
    local dist_dir
    local fake_bin
    local forbidden_log
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/custom.conf"
    dist_dir="$TEST_TMPDIR/dry-dist"
    forbidden_log="$TEST_TMPDIR/forbidden-tools.log"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::install_failing_generation_tools "$fake_bin"

    {
        printf 'TITLE=%q\n' 'Config dry title'
        printf 'THUMBHEIGHT=10\n'
        printf 'HEIGHT=20\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'SHUFFLE=no\n'
        printf 'INCOMING_DIR=%q/config-incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/config-dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/config-template\n' "$TEST_TMPDIR"
        printf 'TARBALL_INCLUDE=no\n'
    } > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_FORBIDDEN_TOOL_LOG="$forbidden_log" \
            "$TEST_SHURIKEN" \
                --dry-run \
                --config "$config_file" \
                --incoming "$TEST_TMPDIR/incoming" \
                --dist "$dist_dir" \
                --template "$TEST_REPO_ROOT/share/templates/default" \
                --title 'CLI dry title' \
                --height 456 \
                --thumbheight 45 \
                --maxpreviews 2 \
                --image-jobs 2 \
                --random-seed dry-seed \
                --shuffle \
                --no-splash \
                --tarball
    )

    test::assert_contains 'Dry run: no files will be written.' "$output"
    test::assert_contains "Config source: $config_file" "$output"
    test::assert_contains "Incoming directory: $TEST_TMPDIR/incoming" "$output"
    test::assert_contains "Output directory: $dist_dir" "$output"
    test::assert_contains \
        "Template directory: $TEST_REPO_ROOT/share/templates/default" \
        "$output"
    test::assert_contains 'Title: CLI dry title' "$output"
    test::assert_contains 'Height: 456' "$output"
    test::assert_contains 'Thumb height: 45' "$output"
    test::assert_contains 'Max previews per page: 2' "$output"
    test::assert_contains 'Image jobs: 2' "$output"
    test::assert_contains 'Random seed: dry-seed' "$output"
    test::assert_contains 'Shuffle: yes' "$output"
    test::assert_contains 'Splash page: no' "$output"
    test::assert_contains 'Image count: 6' "$output"
    test::assert_contains 'Tarball setting: yes' "$output"
    test::assert_contains 'Tarball name plan: incoming-<timestamp>.tar' \
        "$output"
    test::assert_contains 'Planned directories:' "$output"
    test::assert_contains "  $dist_dir/photos" "$output"
    test::assert_contains 'Planned generated files:' "$output"
    test::assert_contains \
        "  $dist_dir/index.html (1 album index redirect)" \
        "$output"
    test::assert_contains "  $dist_dir/favicon.ico" "$output"
    test::assert_contains "  $dist_dir/shuriken.json" "$output"
    test::assert_contains "  $dist_dir/photos/* (6 image files)" "$output"
    test::assert_contains "  $dist_dir/thumbs/* (6 image files)" "$output"
    test::assert_contains "  $dist_dir/blurs/* (6 image files)" "$output"
    test::assert_contains "  $dist_dir/page-*.html (3 preview pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[page]-[image].html (6 view pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[page]-[image]-details.html (6 details pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[redirect].html (14 navigation redirects)" \
        "$output"
    test::assert_not_contains "$dist_dir/html" "$output"
    test::assert_contains "  $dist_dir/incoming-<timestamp>.tar" "$output"
    test::assert_not_contains 'Processing ' "$output"
    test::assert_not_contains 'Creating tarball ' "$output"
    test::assert_path_absent "$dist_dir"
    test::assert_path_absent "$TEST_TMPDIR/config-dist"
    test::assert_path_absent "$forbidden_log"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_dry_run_rejects_invalid_config_and_input() {
    local config_file
    local dist_dir
    local incoming_dir
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    incoming_dir="$TEST_TMPDIR/incoming"
    dist_dir="$TEST_TMPDIR/dist"
    mkdir -p "$incoming_dir"
    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" \
        "$TEST_REPO_ROOT/share/templates/default"
    printf 'MAXPREVIEWS=not-a-number\n' >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_SHURIKEN" --dry-run --config "$config_file"
    )

    test::assert_contains 'ERROR: MAXPREVIEWS must be a positive integer' \
        "$output"
    test::assert_path_absent "$dist_dir"

    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/missing" "$dist_dir" \
        "$TEST_REPO_ROOT/share/templates/default"
    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_SHURIKEN" --dry-run --config "$config_file"
    )

    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    test::assert_path_absent "$dist_dir"
    test::teardown
}

test_generate_ignores_unsupported_incoming_files_with_warning() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$TEST_TMPDIR/incoming/01-upper.JPG"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$TEST_TMPDIR/incoming/02-photo.jpeg"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$TEST_TMPDIR/incoming/03-photo.png"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$TEST_TMPDIR/incoming/04-photo.webp"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$TEST_TMPDIR/incoming/05-photo.gif"
    printf 'extension-looking basename\n' > "$TEST_TMPDIR/incoming/jpg"
    printf 'notes\n' > "$TEST_TMPDIR/incoming/notes.txt"
    printf '# album notes\n' > "$TEST_TMPDIR/incoming/README.md"
    mkdir -p "$TEST_TMPDIR/dist/photos"
    printf 'stale cached unsupported file\n' \
        > "$TEST_TMPDIR/dist/photos/jpg"
    printf 'stale cached unsupported file\n' \
        > "$TEST_TMPDIR/dist/photos/notes.txt"
    printf 'stale cached unsupported file\n' \
        > "$TEST_TMPDIR/dist/photos/README.md"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Extension filter album' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate 2>&1
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-upper.JPG"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/02-photo.jpeg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/03-photo.png"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/04-photo.webp"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/05-photo.gif"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/notes.txt"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/README.md"
    test::assert_contains \
        'WARNING: Ignoring unsupported incoming file: README.md' \
        "$output"
    test::assert_contains \
        'WARNING: Ignoring unsupported incoming file: notes.txt' \
        "$output"
    test::assert_contains \
        'WARNING: Ignoring unsupported incoming file: jpg' \
        "$output"
    test::assert_not_contains 'Processing notes.txt' "$output"
    test::assert_not_contains 'Processing README.md' "$output"
    test::assert_not_contains 'Processing jpg' "$output"

    python3 - "$TEST_TMPDIR/dist/shuriken.json" <<'PY'
import json
import pathlib
import sys

metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert metadata["source"]["image_count"] == 5
assert metadata["generated"]["photo_count"] == 5
PY

    test::teardown
}

test_generate_missing_incoming_fails() {
    local output

    test::setup
    test::write_album_config \
        "$TEST_TMPDIR/shuriken.conf" "$TEST_TMPDIR/missing" \
        "$TEST_TMPDIR/dist" 'Missing incoming' 40

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains \
        "ERROR: You have to create $TEST_TMPDIR/missing first" \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist"
    test::teardown
}

test_generate_preflight_rejects_missing_required_vars() {
    local case_dir
    local config_file
    local dist_dir
    local incoming_dir
    local output
    local required_var
    local -a required_vars=(
        TITLE
        THUMBHEIGHT
        MAXPREVIEWS
        INCOMING_DIR
        DIST_DIR
        TEMPLATE_DIR
    )

    test::setup
    for required_var in "${required_vars[@]}"; do
        case_dir="$TEST_TMPDIR/missing-$required_var"
        incoming_dir="$case_dir/incoming"
        dist_dir="$case_dir/dist"
        config_file="$case_dir/shuriken.conf"
        mkdir -p "$incoming_dir"
        test::write_preflight_config \
            "$config_file" "$incoming_dir" "$dist_dir" \
            "$TEST_REPO_ROOT/share/templates/default" "$required_var"

        output=$(
            cd "$case_dir"
            test::capture_failure_output \
                "$TEST_SHURIKEN" --generate --config "$config_file"
        )

        test::assert_contains \
            "ERROR: $required_var must be set in shuriken configuration" \
            "$output"
        test::assert_path_absent "$dist_dir"
    done
    test::teardown
}

test_generate_preflight_rejects_invalid_numbers() {
    local case_dir
    local config_file
    local dist_dir
    local incoming_dir
    local numeric_var
    local output
    local -a numeric_vars=(
        HEIGHT
        THUMBHEIGHT
        MAXPREVIEWS
        IMAGE_JOBS
    )

    test::setup
    for numeric_var in "${numeric_vars[@]}"; do
        case_dir="$TEST_TMPDIR/invalid-$numeric_var"
        incoming_dir="$case_dir/incoming"
        dist_dir="$case_dir/dist"
        config_file="$case_dir/shuriken.conf"
        mkdir -p "$incoming_dir"
        test::write_preflight_config \
            "$config_file" "$incoming_dir" "$dist_dir" \
            "$TEST_REPO_ROOT/share/templates/default"
        printf '%s=not-a-number\n' "$numeric_var" >> "$config_file"

        output=$(
            cd "$case_dir"
            test::capture_failure_output \
                "$TEST_SHURIKEN" --generate --config "$config_file"
        )

        test::assert_contains \
            "ERROR: $numeric_var must be a positive integer" \
            "$output"
        test::assert_path_absent "$dist_dir"
    done
    test::teardown
}

test_generate_preflight_accepts_empty_height() {
    local config_file
    local fake_bin

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default" HEIGHT

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::teardown
}

test_generate_preflight_rejects_invalid_yes_no_values() {
    local bool_var
    local case_dir
    local config_file
    local dist_dir
    local incoming_dir
    local output
    local -a bool_vars=(
        SHUFFLE
        SPLASH_PAGE
        TARBALL_INCLUDE
    )

    test::setup
    for bool_var in "${bool_vars[@]}"; do
        case_dir="$TEST_TMPDIR/invalid-$bool_var"
        incoming_dir="$case_dir/incoming"
        dist_dir="$case_dir/dist"
        config_file="$case_dir/shuriken.conf"
        mkdir -p "$incoming_dir"
        test::write_preflight_config \
            "$config_file" "$incoming_dir" "$dist_dir" \
            "$TEST_REPO_ROOT/share/templates/default"
        printf '%s=maybe\n' "$bool_var" >> "$config_file"

        output=$(
            cd "$case_dir"
            test::capture_failure_output \
                "$TEST_SHURIKEN" --generate --config "$config_file"
        )

        test::assert_contains "ERROR: $bool_var must be yes or no" "$output"
        test::assert_path_absent "$dist_dir"
    done
    test::teardown
}

test_generate_preflight_rejects_unwritable_dist_parent() {
    local config_file
    local dist_dir
    local dist_parent
    local incoming_dir
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_parent="$TEST_TMPDIR/unwritable"
    dist_dir="$dist_parent/dist"
    incoming_dir="$TEST_TMPDIR/incoming"
    mkdir -p "$incoming_dir" "$dist_parent"
    chmod 0555 "$dist_parent"

    if [ -w "$dist_parent" ]; then
        chmod 0755 "$dist_parent"
        test::teardown
        return
    fi

    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" \
        "$TEST_REPO_ROOT/share/templates/default"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_SHURIKEN" --generate --config "$config_file"
    )
    chmod 0755 "$dist_parent"

    test::assert_contains \
        "ERROR: DIST_DIR parent $dist_parent must be writable" \
        "$output"
    test::assert_path_absent "$dist_dir"
    test::teardown
}

test_generate_preflight_accepts_nested_new_dist_dir() {
    local config_file
    local dist_dir
    local fake_bin
    local incoming_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    incoming_dir="$TEST_TMPDIR/incoming"
    dist_dir="$TEST_TMPDIR/site/albums/out"
    mkdir -p "$TEST_TMPDIR/site"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" test::generate_fixture_images "$incoming_dir"
    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" \
        "$TEST_REPO_ROOT/share/templates/default"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    test::assert_file_exists "$dist_dir/photos/01-landscape.jpg"
    test::teardown
}

test_generate_preflight_rejects_missing_templates() {
    local config_file
    local dist_dir
    local incoming_dir
    local output
    local template_dir

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    incoming_dir="$TEST_TMPDIR/incoming"
    template_dir="$TEST_TMPDIR/templates"
    mkdir -p "$incoming_dir" "$template_dir"
    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" "$template_dir"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output \
            "$TEST_SHURIKEN" --generate --config "$config_file"
    )

    test::assert_contains \
        "ERROR: template file $template_dir/details.tmpl must be readable" \
        "$output"
    test::assert_path_absent "$dist_dir"
    test::teardown
}

test_dry_run_rejects_missing_default_template_dir() {
    local config_file
    local dist_dir
    local incoming_dir
    local output
    local shuriken_copy
    local template_dir

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    incoming_dir="$TEST_TMPDIR/incoming"
    shuriken_copy="$TEST_TMPDIR/shuriken"
    template_dir="$TEST_TMPDIR/missing-default-template"
    mkdir -p "$incoming_dir"
    cp "$TEST_SHURIKEN" "$shuriken_copy"
    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" \
        /usr/share/shuriken/templates/default

    output=$(
        cd "$TEST_TMPDIR"
        SHURIKEN_DEFAULT_TEMPLATE_DIR="$template_dir" \
            test::capture_failure_output \
                "$shuriken_copy" --dry-run --config "$config_file"
    )

    test::assert_contains \
        "ERROR: TEMPLATE_DIR $template_dir must be a readable directory" \
        "$output"
    test::assert_path_absent "$dist_dir"
    test::teardown
}

test_integration_generates_album_outputs_and_cleans() {
    local config_file
    local details_html
    local fake_bin
    local page_html
    local tarball
    local tarball_listing
    local top_index_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Integration album' 2

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/02-portrait.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/03-square.jpg"
    test::assert_file_exists \
        "$TEST_TMPDIR/dist/photos/04 filename with spaces.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/blurs/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/page-1.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/page-2.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/page-3.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/1-1.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/1-1-details.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/3-2.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/3-2-details.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/index.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/favicon.ico"
    test::assert_file_exists "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_html_subdir_output "$TEST_TMPDIR/dist"

    page_html=$(<"$TEST_TMPDIR/dist/page-1.html")
    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains "name='04 filename with spaces.jpg'" \
        "$(<"$TEST_TMPDIR/dist/page-2.html")"
    test::assert_contains 'Next 2 pictures' "$page_html"
    test::assert_contains \
        'href="https://codeberg.org/snonux/shuriken.sh"' \
        "$page_html"
    test::assert_contains 'codeberg.org/snonux/shuriken.sh' "$page_html"
    test::assert_not_contains 'codeberg.org/snonux/photoalbum' "$page_html"
    test::assert_contains 'No EXIF details available.' "$details_html"
    test::assert_contains '<div class="details-layout">' "$details_html"
    test::assert_contains '<div class="details-photo-column">' "$details_html"
    test::assert_contains '<div class="navigator details-navigator">' \
        "$details_html"
    test::assert_contains "class='view details-photo" "$details_html"
    test::assert_contains 'class="details-photo-link" href="1-2-details.html"' \
        "$details_html"
    test::assert_contains 'href="1-0-details.html" class="arrow">&lArr;</a>' \
        "$details_html"
    test::assert_contains 'href="1-1.html">Image view</a>' "$details_html"
    test::assert_contains 'href="1-2-details.html" class="arrow">&rArr;</a>' \
        "$details_html"
    test::assert_not_contains 'class="details-photo-link" href="1-2.html"' \
        "$details_html"
    test::assert_contains '<title>Integration album</title>' "$top_index_html"
    test::assert_contains \
        '<link rel="icon" href="./favicon.ico" type="image/x-icon">' \
        "$top_index_html"
    test::assert_contains \
        '<link rel="icon" href="./favicon.ico" type="image/x-icon">' \
        "$page_html"
    test::assert_contains 'Enter album' "$top_index_html"
    test::assert_contains 'href="page-1.html"' "$top_index_html"
    test::assert_contains \
        '<img class="splash-photo" src="./photos/' \
        "$top_index_html"
    test::assert_not_contains '<script' "$top_index_html"
    test::assert_not_contains 'javascript:' "$top_index_html"
    test::assert_not_contains "http-equiv='refresh'" "$top_index_html"
    test::assert_find_count 0 "$TEST_TMPDIR/dist" '*.tar'
    test::assert_generation_metadata \
        "$TEST_TMPDIR/dist/shuriken.json" \
        './shuriken.conf' \
        "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default" \
        no \
        'Integration album' \
        2

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate --tarball
    )
    test::assert_file_exists "$TEST_TMPDIR/dist/shuriken.json"
    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -name '*.tar' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
    tarball_listing=$(tar -tf "$tarball")
    test::assert_contains \
        'incoming/04 filename with spaces.jpg' \
        "$tarball_listing"
    test::assert_generation_metadata \
        "$TEST_TMPDIR/dist/shuriken.json" \
        './shuriken.conf' \
        "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default" \
        yes \
        'Integration album' \
        2

    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --clean
    )
    test::assert_path_absent "$TEST_TMPDIR/dist"
    test::teardown
}

test_render_view_redirects_uses_numeric_last_view() {
    local dist_dir
    local html_dir
    local redirect_html
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -A rendered_last_views=()
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -a rendered_view_pages=()
    local view

    test::setup
    dist_dir="$TEST_TMPDIR/dist"
    html_dir='.'
    mkdir -p "$dist_dir"

    # shellcheck source=/dev/null
    source <(sed '$d' "$TEST_SHURIKEN")

    export DIST_DIR="$dist_dir"
    export TEMPLATE_DIR="$TEST_REPO_ROOT/share/templates/default"
    export SHURIKEN_OUTPUT_MODE=quiet
    export MAXPREVIEWS=10

    for view in 1 2 3 4 5 6 7 8 9 10; do
        : > "$dist_dir/1-$view.html"
        record_rendered_view_page rendered_view_pages rendered_last_views \
            1 "$view"
    done
    : > "$dist_dir/2-1.html"
    record_rendered_view_page rendered_view_pages rendered_last_views 2 1
    touch -t 202606050000 "$dist_dir"/1-*.html "$dist_dir/2-1.html"

    render_view_redirects "$html_dir" rendered_view_pages rendered_last_views

    test::assert_file_exists "$dist_dir/1-11.html"
    test::assert_file_exists "$dist_dir/1-11-details.html"
    redirect_html=$(<"$dist_dir/1-11.html")
    test::assert_contains 'url=2-1.html' "$redirect_html"
    redirect_html=$(<"$dist_dir/1-11-details.html")
    test::assert_contains 'url=2-1-details.html' "$redirect_html"
    test "$(<"$dist_dir/1-10.html")" = ''
    test::teardown
}

test_render_view_redirects_wraps_when_last_page_full() {
    local dist_dir
    local html_dir
    local next_redirect_html
    local prev_redirect_html
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -A rendered_last_views=()
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -a rendered_view_pages=()
    local view

    test::setup
    dist_dir="$TEST_TMPDIR/dist"
    html_dir='.'
    mkdir -p "$dist_dir"

    # shellcheck source=/dev/null
    source <(sed '$d' "$TEST_SHURIKEN")

    export DIST_DIR="$dist_dir"
    export TEMPLATE_DIR="$TEST_REPO_ROOT/share/templates/default"
    export SHURIKEN_OUTPUT_MODE=quiet
    export MAXPREVIEWS=2

    for view in 1 2; do
        : > "$dist_dir/1-$view.html"
        : > "$dist_dir/2-$view.html"
        : > "$dist_dir/3-$view.html"
        record_rendered_view_page rendered_view_pages rendered_last_views \
            1 "$view"
        record_rendered_view_page rendered_view_pages rendered_last_views \
            2 "$view"
        record_rendered_view_page rendered_view_pages rendered_last_views \
            3 "$view"
    done

    render_view_redirects "$html_dir" rendered_view_pages rendered_last_views

    test::assert_file_exists "$dist_dir/0-2.html"
    test::assert_file_exists "$dist_dir/3-3.html"
    test::assert_file_exists "$dist_dir/0-2-details.html"
    test::assert_file_exists "$dist_dir/3-3-details.html"
    prev_redirect_html=$(<"$dist_dir/0-2.html")
    next_redirect_html=$(<"$dist_dir/3-3.html")
    test::assert_contains 'url=3-2.html' "$prev_redirect_html"
    test::assert_contains 'url=1-1.html' "$next_redirect_html"
    prev_redirect_html=$(<"$dist_dir/0-2-details.html")
    next_redirect_html=$(<"$dist_dir/3-3-details.html")
    test::assert_contains 'url=3-2-details.html' "$prev_redirect_html"
    test::assert_contains 'url=1-1-details.html' "$next_redirect_html"
    test::assert_path_absent "$dist_dir/4-1.html"
    test::teardown
}

test_generate_config_no_splash_keeps_index_redirect() {
    local config_file
    local fake_bin
    local top_index_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No splash config album' 40
    printf 'SPLASH_PAGE=no\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains 'url=page-1.html' "$top_index_html"
    test::assert_contains \
        '<link rel="icon" href="./favicon.ico" type="image/x-icon">' \
        "$top_index_html"
    test::assert_not_contains 'Enter album' "$top_index_html"
    test::assert_not_contains '<script' "$top_index_html"
    test::assert_not_contains 'javascript:' "$top_index_html"

    python3 - "$TEST_TMPDIR/dist/shuriken.json" <<'PY'
import json
import pathlib
import sys

metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert metadata["settings"]["splash_page"] is False
PY

    test::teardown
}

test_generate_cli_no_splash_overrides_config() {
    local config_file
    local fake_bin
    local template_dir
    local top_index_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    rm -f "$template_dir/splash.tmpl"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No splash CLI album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"
    printf 'SPLASH_PAGE=yes\n' >> "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --generate --no-splash
    )

    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains 'url=page-1.html' "$top_index_html"
    test::assert_not_contains 'Enter album' "$top_index_html"
    test::assert_not_contains '<script' "$top_index_html"
    test::assert_not_contains 'javascript:' "$top_index_html"
    test::teardown
}

test_refresh_splash_rewrites_only_index_from_existing_assets() {
    local after_index
    local after_metadata
    local after_page
    local before_index
    local before_metadata
    local before_page
    local config_file
    local failing_bin
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    failing_bin="$TEST_TMPDIR/failing-bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Refresh splash album' 2

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" \
            --generate --random-seed seed-one
    )

    before_index=$(<"$TEST_TMPDIR/dist/index.html")
    before_page=$(<"$TEST_TMPDIR/dist/page-1.html")
    before_metadata=$(<"$TEST_TMPDIR/dist/shuriken.json")

    test::install_failing_imagemagick "$failing_bin"
    output=$(
        cd "$TEST_TMPDIR"
        PATH="$failing_bin:$PATH" "$TEST_SHURIKEN" \
            --refresh-splash --random-seed seed-two
    )

    after_index=$(<"$TEST_TMPDIR/dist/index.html")
    after_page=$(<"$TEST_TMPDIR/dist/page-1.html")
    after_metadata=$(<"$TEST_TMPDIR/dist/shuriken.json")

    test::assert_contains 'Refreshed splash page' "$output"
    test::assert_contains '<img class="splash-photo" src="./photos/' \
        "$after_index"
    if [ "$before_index" = "$after_index" ]; then
        echo 'FAIL: expected --refresh-splash to choose a new splash image' >&2
        exit 1
    fi
    test "$before_page" = "$after_page"
    test "$before_metadata" = "$after_metadata"
    test::teardown
}

test_refresh_splash_copies_favicon_for_legacy_dist() {
    local config_file
    local output
    local top_index_html

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    mkdir -p \
        "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist/photos" \
        "$TEST_TMPDIR/dist/blurs"
    printf 'legacy photo\n' > "$TEST_TMPDIR/dist/photos/legacy.jpg"
    printf 'legacy blur\n' > "$TEST_TMPDIR/dist/blurs/legacy.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Legacy refresh album' 40

    output=$(
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --refresh-splash
    )

    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains 'Refreshed splash page' "$output"
    test::assert_contains \
        '<link rel="icon" href="./favicon.ico" type="image/x-icon">' \
        "$top_index_html"
    test::assert_file_exists "$TEST_TMPDIR/dist/favicon.ico"
    test::teardown
}

test_refresh_splash_requires_existing_generated_assets() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Missing splash assets album' 40

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --refresh-splash
    )

    test::assert_contains \
        "ERROR: DIST_DIR photos directory $TEST_TMPDIR/dist/photos must exist" \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist/index.html"
    test::teardown
}

test_refresh_splash_requires_existing_generated_blurs() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    mkdir -p "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist" \
        "$TEST_TMPDIR/dist/photos"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Missing splash blurs album' 40

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --refresh-splash
    )

    test::assert_contains \
        "ERROR: DIST_DIR blurs directory $TEST_TMPDIR/dist/blurs must exist" \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist/index.html"
    test::teardown
}

test_refresh_splash_rejects_no_splash_config() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'No splash refresh album' 40
    printf 'SPLASH_PAGE=no\n' >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --refresh-splash
    )

    test::assert_contains \
        'ERROR: SPLASH_PAGE must be yes to refresh the splash page' \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist/index.html"
    test::teardown
}

test_generate_replaces_dist_after_success() {
    local config_file
    local fake_bin

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Replace album' 40
    mkdir -p "$TEST_TMPDIR/dist/html" "$TEST_TMPDIR/dist/photos"
    printf 'stale\n' > "$TEST_TMPDIR/dist/stale-root-file"
    printf 'stale\n' > "$TEST_TMPDIR/dist/html/stale.html"
    printf 'stale\n' > "$TEST_TMPDIR/dist/photos/stale.jpg"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/page-1.html"
    test::assert_path_absent "$TEST_TMPDIR/dist/stale-root-file"
    test::assert_path_absent "$TEST_TMPDIR/dist/html"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/stale.jpg"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_imagemagick_failure_preserves_dist() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_failing_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    printf 'keep me\n' > "$TEST_TMPDIR/dist/sentinel"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Failing ImageMagick album' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'simulated ImageMagick failure' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test "$(<"$TEST_TMPDIR/dist/sentinel")" = 'keep me'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_imagemagick_timeout_preserves_dist() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_hanging_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    printf 'keep me\n' > "$TEST_TMPDIR/dist/sentinel"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Hanging ImageMagick album' 40
    printf 'IMAGEMAGICK_TIMEOUT=1\n' >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_HANG_SECONDS=2 \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains \
        'ERROR: ImageMagick timed out after 1 seconds' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test "$(<"$TEST_TMPDIR/dist/sentinel")" = 'keep me'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_sighup_cleans_staging_dir() {
    local config_file
    local fake_bin
    local output_file
    local release_file
    local started_file
    local -i release_pid=0
    local -i status=0
    local -i waited=0
    local -i generate_pid=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    output_file="$TEST_TMPDIR/generate.out"
    release_file="$TEST_TMPDIR/release-magick"
    started_file="$TEST_TMPDIR/magick-started"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::install_blocking_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'SIGHUP album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_BLOCKING_MAGICK_STARTED="$started_file" \
            TEST_BLOCKING_MAGICK_RELEASE="$release_file" \
            exec "$TEST_SHURIKEN" --generate
    ) > "$output_file" 2>&1 &
    generate_pid=$!

    while [ ! -f "$started_file" ] && kill -0 "$generate_pid" 2>/dev/null; do
        if (( waited >= 100 )); then
            touch "$release_file"
            wait "$generate_pid" || true
            echo 'FAIL: timed out waiting for fake ImageMagick to start' >&2
            cat "$output_file" >&2
            exit 1
        fi
        (( ++waited ))
        sleep 0.05
    done

    if [ ! -f "$started_file" ]; then
        touch "$release_file"
        wait "$generate_pid" || true
        echo 'FAIL: generate exited before fake ImageMagick started' >&2
        cat "$output_file" >&2
        exit 1
    fi

    ( sleep 5; touch "$release_file" ) &
    release_pid=$!

    kill -HUP "$generate_pid"
    set +e
    wait "$generate_pid"
    status=$?
    set -e

    touch "$release_file"
    kill "$release_pid" 2>/dev/null || true
    wait "$release_pid" 2>/dev/null || true

    if (( status != 129 )); then
        echo "FAIL: expected SIGHUP exit status 129, got $status" >&2
        cat "$output_file" >&2
        exit 1
    fi

    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_sigint_terminates_imagemagick_jobs() {
    local config_file
    local fake_bin
    local output_file
    local release_file
    local started_file
    local terminated_file
    local -i generate_pid=0
    local -i release_pid=0
    local -i status=0
    local -i waited=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    output_file="$TEST_TMPDIR/generate.out"
    release_file="$TEST_TMPDIR/release-magick"
    started_file="$TEST_TMPDIR/magick-started"
    terminated_file="$TEST_TMPDIR/magick-terminated"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::install_blocking_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'SIGINT album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_BLOCKING_MAGICK_STARTED="$started_file" \
            TEST_BLOCKING_MAGICK_RELEASE="$release_file" \
            TEST_BLOCKING_MAGICK_TERMINATED="$terminated_file" \
            exec env --default-signal=INT "$TEST_SHURIKEN" --generate
    ) > "$output_file" 2>&1 &
    generate_pid=$!

    while [ ! -f "$started_file" ] && kill -0 "$generate_pid" 2>/dev/null; do
        if (( waited >= 100 )); then
            touch "$release_file"
            wait "$generate_pid" || true
            echo 'FAIL: timed out waiting for fake ImageMagick to start' >&2
            cat "$output_file" >&2
            exit 1
        fi
        (( ++waited ))
        sleep 0.05
    done

    if [ ! -f "$started_file" ]; then
        touch "$release_file"
        wait "$generate_pid" || true
        echo 'FAIL: generate exited before fake ImageMagick started' >&2
        cat "$output_file" >&2
        exit 1
    fi

    ( sleep 5; touch "$release_file" ) &
    release_pid=$!

    kill -INT "$generate_pid"
    set +e
    wait "$generate_pid"
    status=$?
    set -e

    touch "$release_file"
    kill "$release_pid" 2>/dev/null || true
    wait "$release_pid" 2>/dev/null || true

    if (( status != 130 )); then
        echo "FAIL: expected SIGINT exit status 130, got $status" >&2
        cat "$output_file" >&2
        exit 1
    fi

    test::assert_file_exists "$terminated_file"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_tar_timeout_preserves_dist() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::install_hanging_tar "$fake_bin"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    printf 'keep me\n' > "$TEST_TMPDIR/dist/sentinel"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Hanging tar album' 40
    {
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TAR_TIMEOUT=1\n'
    } >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_HANG_SECONDS=2 \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'ERROR: tar timed out after 1 seconds' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test "$(<"$TEST_TMPDIR/dist/sentinel")" = 'keep me'
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_find_count 0 "$TEST_TMPDIR/dist" '*.tar'
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_template_failure_preserves_dist() {
    local config_file
    local fake_bin
    local output
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    printf 'return 42\n' > "$template_dir/preview.tmpl"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Failing template album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'Rendering preview template into ' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_templates_cannot_read_generation_locals() {
    local config_file
    local fake_bin
    local output
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    # shellcheck disable=SC2016
    printf 'printf "legacy num: %%s\\n" "${num}"\n' \
        > "$template_dir/preview.tmpl"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Renderer contract album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" num=ambient \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'num: unbound variable' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_templates_cannot_read_renderer_internals() {
    local config_file
    local fake_bin
    local output
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    # shellcheck disable=SC2016
    printf 'printf "context key: %%s\\n" "${context_key}"\n' \
        > "$template_dir/preview.tmpl"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Renderer internals album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" context_key=ambient \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'context_key: unbound variable' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_templates_cannot_read_serialized_context_hook() {
    local config_file
    local fake_bin
    local output
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    # shellcheck disable=SC2016
    printf 'printf "bash env: %%s\\n" "${BASH_ENV}"\n' \
        > "$template_dir/preview.tmpl"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Renderer context album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" BASH_ENV=ambient \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'BASH_ENV: unbound variable' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_swap_failure_restores_dist() {
    local config_file
    local fake_bin
    local mv_count_file
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    mv_count_file="$TEST_TMPDIR/mv-count"

    test::install_fake_imagemagick "$fake_bin"
    test::install_mv_spy "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    mkdir -p "$TEST_TMPDIR/dist"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    printf 'old sentinel\n' > "$TEST_TMPDIR/dist/sentinel"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Swap failure album' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_MV_COUNT_FILE="$mv_count_file" \
            TEST_FAIL_MV_ON=2 \
            test::capture_failure_output "$TEST_SHURIKEN" --generate
    )

    test::assert_contains 'simulated mv failure' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test "$(<"$TEST_TMPDIR/dist/sentinel")" = 'old sentinel'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01-landscape.jpg"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
    test::teardown
}

test_generate_missing_imagemagick_fails() {
    local config_file
    local output
    local path_bin

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
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
            "$TEST_SHURIKEN" --generate
    )

    test::assert_contains \
        'ERROR: ImageMagick is required; install magick or convert' \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist"
    test::teardown
}

test_template_stdout_escape_helpers_match_nameref_helpers() {
    local css_text
    local css_to
    local css_stdout
    local html_text
    local html_to
    local html_stdout

    # shellcheck source=src/lib/template.source.sh
    source "$TEST_REPO_ROOT/src/lib/template.source.sh"

    html_text=$'A & "quoted" <title> \'ok\''
    html_escape_to html_to "$html_text"
    html_stdout=$(_html_escape "$html_text")
    test "$html_stdout" = "$html_to"
    test "$html_stdout" = \
        'A &amp; &quot;quoted&quot; &lt;title&gt; &#39;ok&#39;'

    css_text=$'path\\kid\'s_"<tag>&.jpg'
    css_string_escape_to css_to "$css_text"
    css_stdout=$(_css_string_escape "$css_text")
    test "$css_stdout" = "$css_to"
    test "$css_stdout" = \
        'path\\kid\000027s_\000022\00003ctag\00003e\000026.jpg'
}

test_generate_escapes_html_values() {
    local config_file
    local css_photo
    local details_html
    local exif_value_html
    local fake_bin
    local original_basepath
    local original_basepath_html
    local page_html
    local photo_html
    local photo_name
    local title
    local title_html
    local top_index_html
    local view_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    photo_name="kid's_\"<tag>&.jpg"
    photo_html='kid&#39;s_&quot;&lt;tag&gt;&amp;.jpg'
    css_photo='kid\000027s_\000022\00003ctag\00003e\000026.jpg'
    title="A & \"quoted\" <title> 'ok'"
    title_html='A &amp; &quot;quoted&quot; &lt;title&gt; &#39;ok&#39;'
    exif_value_html='O&#39;Neil &amp; &quot;&lt;camera&gt;&quot;'
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
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT=$'  exif:Artist: O\'Neil & "<camera>"' \
            "$TEST_SHURIKEN" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/page-1.html")
    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    view_html=$(<"$TEST_TMPDIR/dist/1-1.html")
    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    test::assert_no_html_subdir_output "$TEST_TMPDIR/dist"

    test::assert_contains "<title>$title_html</title>" "$page_html"
    test::assert_contains "<title>$title_html</title>" "$top_index_html"
    test::assert_contains \
        "background-image: url(\"./blurs/$css_photo\");" \
        "$page_html"
    test::assert_contains "url(\"./blurs/$css_photo\")" "$top_index_html"
    test::assert_contains "src=\"./photos/$photo_html\"" "$top_index_html"
    test::assert_contains "name='$photo_html'" "$page_html"
    test::assert_contains "src='./thumbs/$photo_html'" "$page_html"
    test::assert_contains '&amp;&quot;&#39;.tar' "$page_html"
    test::assert_contains "href=\"page-1.html#$photo_html\"" "$view_html"
    test::assert_contains 'href="1-1-details.html">Details</a>' "$view_html"
    test::assert_contains "href ='./photos/$photo_html'" "$view_html"
    test::assert_contains \
        "href=\"$original_basepath_html/$photo_html\"" \
        "$view_html"
    test::assert_contains "src='./photos/$photo_html'" "$details_html"
    test::assert_contains '<th>exif:Artist</th>' "$details_html"
    test::assert_contains "<td>$exif_value_html</td>" "$details_html"
    test::assert_contains "href=\"1-1.html\">Image view</a>" "$details_html"
    test::assert_not_contains 'title="Camera:' "$details_html"
    test::assert_not_contains 'title=""' "$details_html"
    test::assert_not_contains '<title>A & "quoted" <title>' "$page_html"
    test::assert_not_contains "$photo_name" "$top_index_html"
    test::assert_not_contains "$photo_name" "$view_html"
    test::assert_not_contains "O'Neil & \"<camera>\"" "$details_html"

    test::teardown
}

test_generate_renders_exif_details() {
    local config_file
    local details_html
    local fake_bin
    local identify_output
    local view_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    identify_output=$'Image:\n'
    identify_output+=$'  exif:DateTimeOriginal: 2026:06:04 12:34:56\n'
    identify_output+=$'  exif:Make: ExampleCam\n'
    identify_output+=$'  exif:Model: Model & "X"\n'
    identify_output+=$'  exif:FNumber: f/2.8\n'
    identify_output+=$'  exif:ISOSpeedRatings: 400\n'
    identify_output+=$'  exif:ExposureTime: 1/125\n'
    identify_output+=$'  geometry: 120x90'

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'EXIF album' 1

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT="$identify_output" \
            "$TEST_SHURIKEN" --generate
    )

    view_html=$(<"$TEST_TMPDIR/dist/1-1.html")
    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")

    test::assert_contains 'href="1-1-details.html">Details</a>' "$view_html"
    test::assert_contains '<table class="details">' "$details_html"
    test::assert_contains \
        'title="Camera: ExampleCam Model &amp; &quot;X&quot;; Aperture: f/2.8; ISO: 400; Shutter speed: 1/125; Taken: 2026:06:04 12:34:56"' \
        "$details_html"
    test::assert_contains '<th>exif:DateTimeOriginal</th>' "$details_html"
    test::assert_contains '<td>2026:06:04 12:34:56</td>' "$details_html"
    test::assert_contains '<th>exif:Make</th>' "$details_html"
    test::assert_contains '<td>ExampleCam</td>' "$details_html"
    test::assert_contains '<th>exif:Model</th>' "$details_html"
    test::assert_contains '<td>Model &amp; &quot;X&quot;</td>' "$details_html"
    test::assert_contains '<th>exif:FNumber</th>' "$details_html"
    test::assert_contains '<td>f/2.8</td>' "$details_html"
    test::assert_contains '<th>exif:ISOSpeedRatings</th>' "$details_html"
    test::assert_contains '<td>400</td>' "$details_html"
    test::assert_contains '<th>exif:ExposureTime</th>' "$details_html"
    test::assert_contains '<td>1/125</td>' "$details_html"
    test::assert_not_contains 'geometry: 120x90' "$details_html"
    test::assert_not_contains 'Model & "X"' "$details_html"
    test::assert_not_contains 'No EXIF details available.' "$details_html"

    test::teardown
}

test_generate_reuses_cached_exif_details_unless_forced() {
    local config_file
    local details_html
    local fake_bin
    local identify_log
    local -i identify_count=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    identify_log="$TEST_TMPDIR/identify.log"

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Cached EXIF album' 1

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_LOG="$identify_log" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT=$'  exif:Make: FirstCam' \
            "$TEST_SHURIKEN" --generate
    )

    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    test::assert_contains '<td>FirstCam</td>' "$details_html"
    identify_count=$(wc -l < "$identify_log")
    test "$identify_count" -eq 1

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_LOG="$identify_log" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT=$'  exif:Make: SecondCam' \
            "$TEST_SHURIKEN" --generate
    )

    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    test::assert_contains '<td>FirstCam</td>' "$details_html"
    test::assert_not_contains '<td>SecondCam</td>' "$details_html"
    identify_count=$(wc -l < "$identify_log")
    test "$identify_count" -eq 1

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_LOG="$identify_log" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT=$'  exif:Make: SecondCam' \
            "$TEST_SHURIKEN" --generate --force
    )

    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    test::assert_contains '<td>SecondCam</td>' "$details_html"
    identify_count=$(wc -l < "$identify_log")
    test "$identify_count" -eq 2
    test::teardown
}

test_generate_metadata_escapes_json_and_custom_tarball_suffix() {
    local config_file
    local fake_bin
    local tarball
    local title

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    title=$'Metadata \e album'

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"

    {
        printf 'TITLE=%q\n' "$title"
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$TEST_REPO_ROOT"
        printf 'TARBALL_INCLUDE=yes\n'
        printf 'TARBALL_SUFFIX=.tgz\n'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    python3 - "$TEST_TMPDIR/dist/shuriken.json" "$title" <<'PY'
import json
import pathlib
import sys

metadata_file, title = sys.argv[1:]
metadata = json.loads(pathlib.Path(metadata_file).read_text())

assert metadata["settings"]["title"] == title
assert metadata["tarball"]["included"] is True
assert metadata["tarball"]["file"].endswith(".tgz")
PY

    tarball=$(find "$TEST_TMPDIR/dist" -maxdepth 1 -type f -name '*.tgz' -print)
    test::assert_contains "$TEST_TMPDIR/dist/incoming-" "$tarball"
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
    config_file="$TEST_TMPDIR/shuriken.conf"
    photo_name='a b.jpg'

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/$photo_name"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Space test' 40

    first_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )
    second_output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --verbose --generate
    )

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/$photo_name"
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/a_b.jpg"
    test::assert_contains "Processing $photo_name to" "$first_output"
    test::assert_contains \
        "Verbose: Skipped existing photo $TEST_TMPDIR/dist/photos/$photo_name" \
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
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a b.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/a_b.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Collision test' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate
    )

    page_html=$(<"$TEST_TMPDIR/dist/page-1.html")

    test::assert_file_exists "$TEST_TMPDIR/dist/photos/a b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/a_b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/a b.jpg"
    test::assert_file_exists "$TEST_TMPDIR/dist/thumbs/a_b.jpg"
    test::assert_contains "src='./thumbs/a b.jpg'" "$page_html"
    test::assert_contains "src='./thumbs/a_b.jpg'" "$page_html"

    test::teardown
}

test_sync_uses_config_destinations_with_delete() {
    local config_file
    local dist_dir
    local fake_bin
    local rsync_log
    local rsync_output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    rsync_log="$TEST_TMPDIR/rsync.log"

    test::install_rsync_spy "$fake_bin"
    mkdir -p "$dist_dir"
    printf 'generated\n' > "$dist_dir/index.html"
    {
        printf 'DIST_DIR=%q\n' "$dist_dir"
        printf 'SYNC_DESTINATIONS=(\n'
        printf '    %q\n' \
            'admin@fishfinger.buetow.org:/var/www/htdocs/example.org/'
        printf '    %q\n' \
            'admin@blowfish.buetow.org:/var/www/htdocs/example.org/'
        printf ')\n'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$rsync_log" \
            "$TEST_SHURIKEN" --sync
    )

    rsync_output=$(<"$rsync_log")
    test::assert_contains $'argc=4\narg0=-av\narg1=--delete' \
        "$rsync_output"
    test::assert_contains "arg2=$dist_dir/" "$rsync_output"
    test::assert_contains \
        'arg3=admin@fishfinger.buetow.org:/var/www/htdocs/example.org/' \
        "$rsync_output"
    test::assert_contains \
        'arg3=admin@blowfish.buetow.org:/var/www/htdocs/example.org/' \
        "$rsync_output"
    test::teardown
}

test_sync_cli_destinations_override_config_without_delete() {
    local config_file
    local dist_dir
    local fake_bin
    local rsync_log
    local rsync_output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    rsync_log="$TEST_TMPDIR/rsync.log"

    test::install_rsync_spy "$fake_bin"
    mkdir -p "$dist_dir"
    printf 'generated\n' > "$dist_dir/index.html"
    {
        printf 'DIST_DIR=%q\n' "$dist_dir"
        printf 'SYNC_DESTINATIONS=(%q)\n' \
            'admin@config.example:/var/www/config/'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$rsync_log" \
            "$TEST_SHURIKEN" \
                --sync \
                --no-sync-delete \
                --sync-destination 'admin@one.example:/var/www/one/' \
                --sync-destination 'admin@two.example:/var/www/two/'
    )

    rsync_output=$(<"$rsync_log")
    test::assert_contains $'argc=3\narg0=-av' "$rsync_output"
    test::assert_not_contains '--delete' "$rsync_output"
    test::assert_not_contains 'admin@config.example' "$rsync_output"
    test::assert_contains "arg1=$dist_dir/" "$rsync_output"
    test::assert_contains 'arg2=admin@one.example:/var/www/one/' \
        "$rsync_output"
    test::assert_contains 'arg2=admin@two.example:/var/www/two/' \
        "$rsync_output"
    test::teardown
}

test_sync_rejects_empty_destinations() {
    local config_file
    local dist_dir
    local fake_bin
    local output
    local rsync_log

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    rsync_log="$TEST_TMPDIR/rsync.log"

    test::install_rsync_spy "$fake_bin"
    mkdir -p "$dist_dir"
    printf 'DIST_DIR=%q\n' "$dist_dir" > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$rsync_log" \
            test::capture_failure_output "$TEST_SHURIKEN" --sync
    )

    test::assert_contains \
        'ERROR: SYNC_DESTINATIONS must contain at least one destination' \
        "$output"
    test::assert_path_absent "$rsync_log"
    test::teardown
}

test_sync_rejects_missing_dist() {
    local config_file
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_rsync_spy "$fake_bin"
    {
        printf 'DIST_DIR=%q\n' "$TEST_TMPDIR/missing-dist"
        printf 'SYNC_DESTINATIONS=(%q)\n' \
            'admin@example.org:/var/www/example.org/'
    } > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$TEST_TMPDIR/rsync.log" \
            test::capture_failure_output "$TEST_SHURIKEN" --sync
    )

    test::assert_contains \
        "ERROR: DIST_DIR $TEST_TMPDIR/missing-dist must be a readable directory" \
        "$output"
    test::assert_path_absent "$TEST_TMPDIR/rsync.log"
    test::teardown
}

test_positional_commands_fail_without_deprecation() {
    local output
    local old_command
    local -a old_commands=(clean generate version makemake)

    for old_command in "${old_commands[@]}"; do
        output=$(test::capture_failure_output "$TEST_SHURIKEN" "$old_command")
        test::assert_contains 'Usage:' "$output"
        test::assert_not_contains 'deprecat' "$output"
        test::assert_not_contains 'makemake' "$output"
    done
}

test_unknown_options_and_conflicting_actions_fail() {
    test::assert_failure 'unsupported option is rejected' \
        "$TEST_SHURIKEN" --unknown
    test::assert_failure 'generate/clean conflict is rejected' \
        "$TEST_SHURIKEN" --generate --clean
    test::assert_failure 'generate/init conflict is rejected' \
        "$TEST_SHURIKEN" --generate --init
    test::assert_failure 'clean/version conflict is rejected' \
        "$TEST_SHURIKEN" --clean --version
    test::assert_failure 'print-config/dry-run conflict is rejected' \
        "$TEST_SHURIKEN" --print-config --dry-run
    test::assert_failure '--force without generate is rejected' \
        "$TEST_SHURIKEN" --sync --force
}

test_empty_args_fail() {
    local output

    output=$(test::capture_failure_output "$TEST_SHURIKEN")
    test::assert_contains 'Usage:' "$output"
}

test_extra_args_fail() {
    test::assert_failure 'extra operand is rejected' "$TEST_SHURIKEN" --version extra
    test::assert_failure \
        '--incoming is rejected with --version' \
        "$TEST_SHURIKEN" --version --incoming /tmp/incoming
    test::assert_failure \
        '--config is rejected with --init' \
        "$TEST_SHURIKEN" --init --config custom.conf
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
        --image-jobs
        --random-seed
        --sync-destination
    )

    for option in "${value_options[@]}"; do
        test::assert_failure "$option requires a value" "$TEST_SHURIKEN" "$option"
    done
}

main() {
    trap test::teardown EXIT

    test::run_case '--version succeeds' test_version
    test::run_case '--init succeeds' test_init
    test::run_case \
        '--init succeeds when source path contains #' \
        test_init_with_hash_in_source_path
    test::run_case \
        '--init refuses existing config without overwrite' \
        test_init_existing_config_fails_without_overwrite
    test::run_case \
        'just install and deinstall supports DESTDIR' \
        test_just_install_and_deinstall_with_destdir
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
        '--generate HEIGHT bounds photo height without upscaling' \
        test_generate_height_bounds_photo_height_without_upscaling
    test::run_case \
        '--generate --shuffle overrides config' \
        test_generate_shuffle_override_uses_random_order
    test::run_case \
        '--generate --no-shuffle overrides config' \
        test_generate_no_shuffle_override_uses_sorted_order
    test::run_case \
        '--generate --random-seed repeats HTML with shuffle' \
        test_generate_random_seed_repeats_html_with_shuffle
    test::run_case \
        '--generate --tarball overrides config' \
        test_generate_cli_tarball_overrides_config
    test::run_case \
        '--generate --no-tarball overrides config' \
        test_generate_cli_no_tarball_overrides_config
    test::run_case \
        '--generate default TAR_OPTS creates archive' \
        test_generate_default_tar_opts_create_archive
    test::run_case \
        '--generate custom TARBALL_SUFFIX cleans previous archive' \
        test_generate_custom_tarball_suffix_cleans_previous_archive
    test::run_case \
        '--generate scalar multi-option TAR_OPTS creates archive' \
        test_generate_scalar_multi_tar_opts_create_archive
    test::run_case \
        'default output reports routine progress' \
        test_default_output_reports_routine_progress
    test::run_case \
        '--quiet suppresses routine progress' \
        test_quiet_output_suppresses_routine_progress
    test::run_case \
        '--quiet keeps errors on stderr' \
        test_quiet_output_keeps_errors_on_stderr
    test::run_case \
        '--verbose reports processing decisions' \
        test_verbose_output_reports_processing_decisions
    test::run_case \
        '--generate --image-jobs limits ImageMagick parallelism' \
        test_generate_image_jobs_limits_parallel_imagemagick
    test::run_case \
        '--generate --image-jobs waits for any finished ImageMagick job' \
        test_generate_image_jobs_waits_for_any_finished_imagemagick
    test::run_case \
        '--generate --image-jobs limits ImageMagick identify parallelism' \
        test_generate_image_jobs_limits_parallel_identify
    test::run_case \
        '--generate --image-jobs limits template rendering parallelism' \
        test_generate_image_jobs_limits_parallel_template_rendering
    test::run_case \
        'repeated output flags use last value' \
        test_repeated_output_flags_use_last_value
    test::run_case \
        '--print-config reflects defaults' \
        test_print_config_reflects_defaults
    test::run_case \
        '--print-config keeps explicit config template dir' \
        test_print_config_keeps_explicit_config_template_dir
    test::run_case \
        '--print-config resolves installed default template dir' \
        test_print_config_resolves_installed_default_template
    test::run_case \
        '--print-config resolves repo default template dir' \
        test_print_config_resolves_repo_default_template
    test::run_case \
        '--print-config keeps CLI template override' \
        test_print_config_keeps_cli_template_override
    test::run_case \
        '--print-config reads selected config' \
        test_print_config_reads_selected_config
    test::run_case \
        '--print-config reads current directory config' \
        test_print_config_reads_current_directory_config
    test::run_case \
        '--print-config applies CLI overrides without writes' \
        test_print_config_applies_cli_overrides_without_writes
    test::run_case \
        '--print-config applies negative CLI overrides' \
        test_print_config_applies_negative_cli_overrides
    test::run_case \
        '--print-config normalizes scalar and array TAR_OPTS' \
        test_print_config_normalizes_scalar_and_array_tar_opts
    test::run_case \
        '--print-config quiet and verbose keep machine output' \
        test_print_config_quiet_and_verbose_keep_machine_output
    test::run_case \
        '--print-config validates values without generation preflight' \
        test_print_config_validates_basic_values_without_generation_preflight
    test::run_case \
        '--dry-run reports CLI overrides without writes' \
        test_dry_run_reports_cli_overrides_without_writes
    test::run_case \
        '--dry-run rejects invalid config and input' \
        test_dry_run_rejects_invalid_config_and_input
    test::run_case \
        '--generate ignores unsupported incoming files with warning' \
        test_generate_ignores_unsupported_incoming_files_with_warning
    test::run_case \
        '--generate missing incoming fails' \
        test_generate_missing_incoming_fails
    test::run_case \
        '--generate preflight rejects missing required vars' \
        test_generate_preflight_rejects_missing_required_vars
    test::run_case \
        '--generate preflight rejects invalid numbers' \
        test_generate_preflight_rejects_invalid_numbers
    test::run_case \
        '--generate preflight accepts empty HEIGHT' \
        test_generate_preflight_accepts_empty_height
    test::run_case \
        '--generate preflight rejects invalid yes/no values' \
        test_generate_preflight_rejects_invalid_yes_no_values
    test::run_case \
        '--generate preflight rejects unwritable dist parent' \
        test_generate_preflight_rejects_unwritable_dist_parent
    test::run_case \
        '--generate preflight accepts nested new dist dir' \
        test_generate_preflight_accepts_nested_new_dist_dir
    test::run_case \
        '--generate preflight rejects missing templates' \
        test_generate_preflight_rejects_missing_templates
    test::run_case \
        '--dry-run rejects missing default template dir' \
        test_dry_run_rejects_missing_default_template_dir
    test::run_case \
        '--generate creates output structure and --clean removes it' \
        test_integration_generates_album_outputs_and_cleans
    test::run_case \
        'view redirects use numeric last view' \
        test_render_view_redirects_uses_numeric_last_view
    test::run_case \
        'view redirects wrap when last page is full' \
        test_render_view_redirects_wraps_when_last_page_full
    test::run_case \
        '--generate SPLASH_PAGE=no keeps root index redirect' \
        test_generate_config_no_splash_keeps_index_redirect
    test::run_case \
        '--generate --no-splash keeps root index redirect' \
        test_generate_cli_no_splash_overrides_config
    test::run_case \
        '--refresh-splash rewrites only root index from existing assets' \
        test_refresh_splash_rewrites_only_index_from_existing_assets
    test::run_case \
        '--refresh-splash copies favicon for legacy dist' \
        test_refresh_splash_copies_favicon_for_legacy_dist
    test::run_case \
        '--refresh-splash requires existing generated assets' \
        test_refresh_splash_requires_existing_generated_assets
    test::run_case \
        '--refresh-splash requires existing generated blurs' \
        test_refresh_splash_requires_existing_generated_blurs
    test::run_case \
        '--refresh-splash rejects SPLASH_PAGE=no' \
        test_refresh_splash_rejects_no_splash_config
    test::run_case \
        '--generate replaces final dist after success' \
        test_generate_replaces_dist_after_success
    test::run_case \
        '--generate ImageMagick failure preserves final dist' \
        test_generate_imagemagick_failure_preserves_dist
    test::run_case \
        '--generate ImageMagick timeout preserves final dist' \
        test_generate_imagemagick_timeout_preserves_dist
    test::run_case \
        '--generate SIGHUP cleans staging directory' \
        test_generate_sighup_cleans_staging_dir
    test::run_case \
        '--generate SIGINT terminates ImageMagick jobs' \
        test_generate_sigint_terminates_imagemagick_jobs
    test::run_case \
        '--generate tar timeout preserves final dist' \
        test_generate_tar_timeout_preserves_dist
    test::run_case \
        '--generate template failure preserves final dist' \
        test_generate_template_failure_preserves_dist
    test::run_case \
        '--generate templates cannot read generation locals' \
        test_generate_templates_cannot_read_generation_locals
    test::run_case \
        '--generate templates cannot read renderer internals' \
        test_generate_templates_cannot_read_renderer_internals
    test::run_case \
        '--generate templates cannot read serialized context hook' \
        test_generate_templates_cannot_read_serialized_context_hook
    test::run_case \
        '--generate swap failure restores final dist' \
        test_generate_swap_failure_restores_dist
    test::run_case \
        '--generate fails when ImageMagick is missing' \
        test_generate_missing_imagemagick_fails
    test::run_case \
        'template stdout escapers match nameref helpers' \
        test_template_stdout_escape_helpers_match_nameref_helpers
    test::run_case \
        '--generate escapes generated HTML values' \
        test_generate_escapes_html_values
    test::run_case \
        '--generate renders image EXIF details' \
        test_generate_renders_exif_details
    test::run_case \
        '--generate reuses cached EXIF details unless forced' \
        test_generate_reuses_cached_exif_details_unless_forced
    test::run_case \
        '--generate metadata escapes JSON and custom tarball suffix' \
        test_generate_metadata_escapes_json_and_custom_tarball_suffix
    test::run_case \
        '--generate preserves filenames with spaces without reprocessing' \
        test_generate_preserves_space_filename_without_reprocessing
    test::run_case \
        '--generate handles spaces and underscores distinctly' \
        test_generate_handles_space_and_underscore_names_distinctly
    test::run_case \
        '--sync uses config destinations with delete' \
        test_sync_uses_config_destinations_with_delete
    test::run_case \
        '--sync CLI destinations override config without delete' \
        test_sync_cli_destinations_override_config_without_delete
    test::run_case \
        '--sync rejects empty destinations' \
        test_sync_rejects_empty_destinations
    test::run_case \
        '--sync rejects missing dist' \
        test_sync_rejects_missing_dist
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
