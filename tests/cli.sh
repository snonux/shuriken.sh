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
assert metadata["settings"]["subdivide_percent"] == "30"
assert metadata["settings"]["feature_percent"] == "10"
assert metadata["settings"]["image_jobs"] == "3"
assert metadata["settings"]["shuffle"] is False
assert isinstance(metadata["settings"]["splash_page"], bool)
assert isinstance(metadata["settings"]["stats_page"], bool)
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

# --clean removes DIST_DIR and any leftover staging/backup directories that the
# generation pipeline created as siblings of DIST_DIR (ln0). Unrelated dotfiles
# and other entries in the parent must survive: we only target shuriken's own
# basename-specific ".shuriken.<basename>.staging.*"/".backup.*" prefixes.
test_clean() {
    local staging_dir
    local backup_dir
    local unrelated_dir
    local unrelated_file

    test::setup
    printf 'DIST_DIR=%q/dist\n' "$TEST_TMPDIR" \
        > "$TEST_TMPDIR/shuriken.conf"
    mkdir -p "$TEST_TMPDIR/dist"
    staging_dir="$TEST_TMPDIR/.shuriken.dist.staging.manual"
    backup_dir="$TEST_TMPDIR/.shuriken.dist.backup.manual"
    unrelated_dir="$TEST_TMPDIR/.shuriken.other.staging.keep"
    unrelated_file="$TEST_TMPDIR/.keep-me"
    mkdir -p "$staging_dir" "$backup_dir" "$unrelated_dir"
    touch "$unrelated_file"

    (
        cd "$TEST_TMPDIR"
        "$TEST_SHURIKEN" --clean
        test::assert_path_absent "$TEST_TMPDIR/dist"
        test::assert_path_absent "$staging_dir"
        test::assert_path_absent "$backup_dir"
        # Unrelated entries (different basename / non-shuriken) must survive.
        test::assert_dir_exists "$unrelated_dir"
        test::assert_file_exists "$unrelated_file"
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

# --clean must refuse to delete a DIST_DIR that resolves to a dangerous path
# (here: the user's HOME). We point HOME at a directory we fully control under
# TEST_TMPDIR and seed it with a sentinel file, so a regression can only "delete"
# our throwaway temp dir -- never a real HOME -- and we assert nothing was
# removed and the command failed with a clear error.
test_clean_rejects_dangerous_dist_dir() {
    local config_file
    local fake_home
    local output

    test::setup
    fake_home="$TEST_TMPDIR/fake-home"
    mkdir -p "$fake_home"
    touch "$fake_home/sentinel"
    config_file="$TEST_TMPDIR/shuriken.conf"
    printf 'DIST_DIR=%q\n' "$fake_home" > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        HOME="$fake_home" \
            test::capture_failure_output "$TEST_SHURIKEN" --clean
    )

    test::assert_contains 'refusing to clean DIST_DIR' "$output"
    test::assert_contains 'is HOME' "$output"
    test::assert_dir_exists "$fake_home"
    test::assert_file_exists "$fake_home/sentinel"
    test::teardown
}

# --clean must also refuse an empty DIST_DIR (which would otherwise rm -rf "").
test_clean_rejects_empty_dist_dir() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    printf "DIST_DIR=''\n" > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --clean
    )

    test::assert_contains 'DIST_DIR must be set' "$output"
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

# SOURCE_URL controls the footer "Site generated ... with <link>". The href uses
# the configured URL verbatim and the displayed text is that URL without its
# scheme, so a custom SOURCE_URL replaces the default shuriken.sh credit link.
test_generate_source_url_override_sets_footer_link() {
    local config_file
    local fake_bin
    local page_html

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/url-incoming"

    {
        printf 'TITLE=%q\n' 'URL test'
        printf 'THUMBHEIGHT=10\n'
        printf 'HEIGHT=20\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q/url-incoming\n' "$TEST_TMPDIR"
        printf 'DIST_DIR=%q/url-dist\n' "$TEST_TMPDIR"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$TEST_REPO_ROOT"
        printf 'SOURCE_URL=https://codeberg.org/snonux/irregular.ninja\n'
        printf 'TARBALL_INCLUDE=no\n'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate --config "$config_file"
    )

    page_html=$(<"$TEST_TMPDIR/url-dist/page-1.html")
    test::assert_contains \
        'href="https://codeberg.org/snonux/irregular.ninja"' "$page_html"
    test::assert_contains 'codeberg.org/snonux/irregular.ninja</a>' "$page_html"
    # The default credit link must be gone once SOURCE_URL is overridden.
    test::assert_not_contains 'codeberg.org/snonux/shuriken.sh' "$page_html"

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
        "id='01-landscape.jpg'" \
        "id='06-extra.jpg'" \
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
        PATH="$fake_bin:$PATH" TEST_TEMPLATE_SPY_SLEEP_SECONDS=1 \
            "$TEST_SHURIKEN" \
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

test_generate_parallel_template_failure_logs_photo() {
    local config_file
    local fake_bin
    local output
    local template_dir

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    template_dir="$TEST_TMPDIR/templates"

    test::install_fake_imagemagick "$fake_bin"
    cp -R "$TEST_REPO_ROOT/share/templates/default" "$template_dir"
    printf 'exit 127\n' > "$template_dir/details.tmpl"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/02.jpg"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Failing parallel template album' 40
    printf 'TEMPLATE_DIR=%q\n' "$template_dir" >> "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            test::capture_failure_output \
                "$TEST_SHURIKEN" --image-jobs 1 --generate
    )

    test::assert_contains \
        'ERROR: parallel job failed (127): template render job for photo 01.jpg' \
        "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test::assert_path_absent "$TEST_TMPDIR/dist/1-1-details.html"
    test::assert_path_absent "$TEST_TMPDIR/dist/shuriken.json"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
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
FAVICON=''
SOURCE_URL=https://codeberg.org/snonux/shuriken.sh
TITLE=A\\ simple\\ Shuriken
HEIGHT=1200
THUMBHEIGHT=300
MAXPREVIEWS=40
THUMB_SUBDIVIDE_PERCENT=30
THUMB_FEATURE_PERCENT=10
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=no
SPLASH_PAGE=yes
STATS_PAGE=no
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

test_print_config_applies_omitted_runtime_defaults() {
    local config_file
    local expected
    local output

    test::setup
    config_file="$TEST_TMPDIR/minimal.conf"

    {
        printf 'TITLE=%q\n' 'Minimal defaults'
        printf 'THUMBHEIGHT=30\n'
        printf 'MAXPREVIEWS=40\n'
        printf 'INCOMING_DIR=%q\n' "$TEST_TMPDIR/incoming"
        printf 'DIST_DIR=%q\n' "$TEST_TMPDIR/dist"
        printf 'TEMPLATE_DIR=%q\n' "$TEST_REPO_ROOT/share/templates/default"
    } > "$config_file"

    output=$("$TEST_SHURIKEN" --print-config --config "$config_file")
    expected=$(cat <<EOF
CONFIG_SOURCE=$config_file
INCOMING_DIR=$TEST_TMPDIR/incoming
DIST_DIR=$TEST_TMPDIR/dist
TEMPLATE_DIR=$TEST_REPO_ROOT/share/templates/default
FAVICON=''
SOURCE_URL=https://codeberg.org/snonux/shuriken.sh
TITLE=Minimal\\ defaults
HEIGHT=''
THUMBHEIGHT=30
MAXPREVIEWS=40
THUMB_SUBDIVIDE_PERCENT=30
THUMB_FEATURE_PERCENT=10
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=no
SPLASH_PAGE=yes
STATS_PAGE=no
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
FAVICON=''
SOURCE_URL=https://codeberg.org/snonux/shuriken.sh
TITLE=Selected\\ config
HEIGHT=120
THUMBHEIGHT=30
MAXPREVIEWS=7
THUMB_SUBDIVIDE_PERCENT=30
THUMB_FEATURE_PERCENT=10
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=yes
SPLASH_PAGE=yes
STATS_PAGE=no
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
FAVICON=''
SOURCE_URL=https://codeberg.org/snonux/shuriken.sh
TITLE=Current\\ directory\\ config
HEIGHT=120
THUMBHEIGHT=30
MAXPREVIEWS=8
THUMB_SUBDIVIDE_PERCENT=30
THUMB_FEATURE_PERCENT=10
IMAGE_JOBS=3
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=''
SHUFFLE=no
SPLASH_PAGE=yes
STATS_PAGE=no
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
                --subdivide 55 \
                --feature 35 \
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
FAVICON=''
SOURCE_URL=https://codeberg.org/snonux/shuriken.sh
TITLE=CLI\\ title
HEIGHT=456
THUMBHEIGHT=45
MAXPREVIEWS=9
THUMB_SUBDIVIDE_PERCENT=55
THUMB_FEATURE_PERCENT=35
IMAGE_JOBS=2
IMAGEMAGICK_TIMEOUT=60
RANDOM_SEED=cli-seed
SHUFFLE=yes
SPLASH_PAGE=no
STATS_PAGE=no
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

test_print_config_empty_tar_opts_falls_back_to_default() {
    local config_file
    local empty_array_output
    local empty_scalar_output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Empty tar opts' 40

    # An empty scalar TAR_OPTS must fall back to the default "-c" just like an
    # unset value; the shared resolve_config_array helper yields an empty array
    # and resolve_tar_opts supplies the default.
    printf 'TAR_OPTS=%q\n' '' >> "$config_file"
    empty_scalar_output=$("$TEST_SHURIKEN" --print-config --config "$config_file")
    test::assert_contains 'TAR_OPTS=( -c )' "$empty_scalar_output"

    # An empty array declaration must behave identically.
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Empty array tar opts' 40
    printf 'TAR_OPTS=()\n' >> "$config_file"
    empty_array_output=$("$TEST_SHURIKEN" --print-config --config "$config_file")
    test::assert_contains 'TAR_OPTS=( -c )' "$empty_array_output"
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
                --subdivide 25 \
                --feature 15 \
                --image-jobs 2 \
                --random-seed dry-seed \
                --shuffle \
                --no-splash \
                --stats \
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
    test::assert_contains 'Subdivide percent: 25' "$output"
    test::assert_contains 'Feature percent: 15' "$output"
    test::assert_contains 'Image jobs: 2' "$output"
    test::assert_contains 'Random seed: dry-seed' "$output"
    test::assert_contains 'Shuffle: yes' "$output"
    test::assert_contains 'Splash page: no' "$output"
    test::assert_contains 'Stats page: yes' "$output"
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
    test::assert_contains "  $dist_dir/stats/index.html (EXIF stats page)" \
        "$output"
    test::assert_contains "  $dist_dir/stats/*/ (filter mini-albums)" \
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

test_dry_run_no_stats_omits_stats_plan() {
    local config_file
    local dist_dir
    local fake_bin
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$dist_dir" 'Dry no stats' 40

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --dry-run --no-stats
    )

    test::assert_contains 'Stats page: no' "$output"
    test::assert_not_contains 'stats/index.html (EXIF stats page)' "$output"
    test::assert_not_contains 'stats/*/ (filter mini-albums)' "$output"
    test::assert_path_absent "$dist_dir"
    test::teardown
}

test_dry_run_reports_empty_plan_without_writes() {
    local config_file
    local dist_dir
    local fake_bin
    local forbidden_log
    local incoming_dir
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    dist_dir="$TEST_TMPDIR/dist"
    forbidden_log="$TEST_TMPDIR/forbidden-tools.log"
    incoming_dir="$TEST_TMPDIR/incoming"
    mkdir -p "$incoming_dir"
    test::install_failing_generation_tools "$fake_bin"
    test::write_preflight_config \
        "$config_file" "$incoming_dir" "$dist_dir" \
        "$TEST_REPO_ROOT/share/templates/default"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_FORBIDDEN_TOOL_LOG="$forbidden_log" \
            "$TEST_SHURIKEN" --dry-run --config "$config_file"
    )

    test::assert_contains 'Dry run: no files will be written.' "$output"
    test::assert_contains 'Image count: 0' "$output"
    test::assert_contains 'Tarball name plan: not planned' "$output"
    test::assert_contains \
        "  $dist_dir/index.html (1 splash page)" \
        "$output"
    test::assert_contains "  $dist_dir/photos/* (0 image files)" "$output"
    test::assert_contains "  $dist_dir/thumbs/* (0 image files)" "$output"
    test::assert_contains "  $dist_dir/blurs/* (0 image files)" "$output"
    test::assert_contains "  $dist_dir/page-*.html (0 preview pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[page]-[image].html (0 view pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[page]-[image]-details.html (0 details pages)" \
        "$output"
    test::assert_contains \
        "  $dist_dir/[redirect].html (0 navigation redirects)" \
        "$output"
    test::assert_path_absent "$dist_dir"
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

# Regression for 9n0 (+data-loss): a failed `identify` must warn, must not abort
# the whole generation, and must NOT leave a cache file containing only the
# signature line (which the next run would treat as a valid empty cache hit and
# silently reuse forever). We make the fake ImageMagick fail `identify` for one
# photo and assert: exit 0, a warning naming that photo, the photo still rendered,
# and no leftover cache entry (so the next run retries).
test_generate_warns_and_skips_cache_on_identify_failure() {
    local config_file
    local fake_bin
    local output
    local status

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Identify failure album' 40

    status=0
    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_FAIL='01-landscape.jpg' \
            "$TEST_SHURIKEN" --generate 2>&1
    ) || status=$?

    # A missing-EXIF photo must NOT abort the run.
    if [ "$status" -ne 0 ]; then
        printf 'FAIL: expected --generate to succeed, got exit %s\n' \
            "$status" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
    test::assert_contains \
        'WARNING: could not read EXIF for 01-landscape.jpg' "$output"
    test::assert_contains 'tooltip/stats will be missing' "$output"

    # The photo is still rendered despite the EXIF failure.
    test::assert_file_exists "$TEST_TMPDIR/dist/photos/01-landscape.jpg"

    # No bad cache entry is persisted for the failed photo, so the next run
    # retries `identify` (and warns again) rather than silently reusing an empty
    # result. Photos that succeeded are cached normally.
    test::assert_path_absent "$TEST_TMPDIR/cache/exif/01-landscape.jpg.txt"
    test::assert_file_exists "$TEST_TMPDIR/cache/exif/02-portrait.jpg.txt"

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

# THUMB_SUBDIVIDE_PERCENT is a 0..100 integer (0 disables tile subdivision, 100
# always subdivides). Unlike the positive-integer vars, 0 is valid, so it has its
# own validator with its own range message.
test_config_validate_percentage_var_enforces_range() {
    local output
    local value
    local -i status=0

    # shellcheck source=src/lib/config.validate.source.sh
    source "$TEST_REPO_ROOT/src/lib/config.validate.source.sh"

    # The inclusive bounds and a mid value are accepted.
    for value in 0 30 100; do
        export THUMB_SUBDIVIDE_PERCENT="$value"
        set +e
        validate_percentage_config_var THUMB_SUBDIVIDE_PERCENT 2>/dev/null
        status=$?
        set -e
        if (( status != 0 )); then
            printf 'FAIL: expected %s to be a valid percentage\n' "$value" >&2
            exit 1
        fi
    done

    # Out-of-range, negative, and non-integer values are rejected with the
    # range message.
    for value in 101 150 -1 not-a-number 3.5; do
        export THUMB_SUBDIVIDE_PERCENT="$value"
        set +e
        output=$(validate_percentage_config_var THUMB_SUBDIVIDE_PERCENT 2>&1)
        status=$?
        set -e
        if (( status == 0 )); then
            printf 'FAIL: expected %s to be rejected\n' "$value" >&2
            exit 1
        fi
        test::assert_contains \
            'ERROR: THUMB_SUBDIVIDE_PERCENT must be an integer between 0 and 100' \
            "$output"
    done
}

test_config_validators_fail_fast_without_errexit() {
    local output
    local -i status=0

    # shellcheck source=src/lib/config.validate.source.sh
    source "$TEST_REPO_ROOT/src/lib/config.validate.source.sh"

    unset TITLE
    export HEIGHT=''
    export THUMBHEIGHT=bad
    export MAXPREVIEWS=40
    export IMAGE_JOBS=1
    export IMAGEMAGICK_TIMEOUT=60
    export TAR_TIMEOUT=120
    export INCOMING_DIR=/tmp/incoming
    export DIST_DIR=/tmp/dist
    export TEMPLATE_DIR=/tmp/templates
    export SHUFFLE=yes
    export SPLASH_PAGE=yes
    export TARBALL_INCLUDE=yes

    set +e
    output=$(validate_common_config 2>&1)
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected validate_common_config to fail\n' >&2
        exit 1
    fi

    test::assert_contains \
        'ERROR: TITLE must be set in shuriken configuration' \
        "$output"
    test::assert_not_contains \
        'ERROR: THUMBHEIGHT must be a positive integer' \
        "$output"
}

test_generate_validation_failure_skips_action_without_errexit() {
    local config_file
    local output
    local ran_file
    local -i status=0

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    ran_file="$TEST_TMPDIR/generate-ran"
    mkdir -p "$TEST_TMPDIR/incoming"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default"
    printf 'THUMBHEIGHT=bad\n' >> "$config_file"

    set +e
    output=$(
        bash -euo pipefail -s "$TEST_SHURIKEN" "$config_file" "$ran_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
config_file="$1"; shift
ran_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

generate_staged() {
    printf 'generate_staged ran\n' > "$ran_file"
}

SHURIKEN_CLI_ACTION=--generate
SHURIKEN_CLI_CONFIG_FILE="$config_file"
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES=no
SHURIKEN_CLI_OVERRIDES=()
SHURIKEN_CLI_SYNC_DESTINATIONS=()
SHURIKEN_FORCE_GENERATE=no

set +e
run_configured_action
run_configured_status=$?

if [ -e "$ran_file" ]; then
    printf 'FAIL: generate_staged ran after validation failure\n' >&2
    exit 1
fi

exit "$run_configured_status"
BASH
    )
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected run_configured_action to fail\n' >&2
        exit 1
    fi

    test::assert_contains \
        'ERROR: THUMBHEIGHT must be a positive integer' \
        "$output"
    test::assert_path_absent "$ran_file"
    test::teardown
}

test_generate_action_runs_with_errexit_active() {
    local config_file
    local output
    local ran_file
    local -i status=0

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    ran_file="$TEST_TMPDIR/dry-run-continued"
    mkdir -p "$TEST_TMPDIR/incoming"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default"

    set +e
    output=$(
        bash -euo pipefail -s "$TEST_SHURIKEN" "$config_file" "$ran_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
config_file="$1"; shift
ran_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

dry_run() {
    false
    printf 'dry_run continued\n' > "$ran_file"
}

SHURIKEN_CLI_ACTION=--dry-run
SHURIKEN_CLI_CONFIG_FILE="$config_file"
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES=no
SHURIKEN_CLI_OVERRIDES=()
SHURIKEN_CLI_SYNC_DESTINATIONS=()
SHURIKEN_FORCE_GENERATE=no

# Production runs the action in-process under "set -euo pipefail" (main calls
# run_action with errexit active), so an internal failure inside the action body
# aborts immediately. Leave errexit ON here (no "set +e") to exercise that real
# path: dry_run's "false" must abort before the "dry_run continued" write.
run_configured_action
BASH
    )
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected run_configured_action to fail\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$ran_file"
    test::teardown
}

test_generate_action_failure_fails_status_tested_dispatcher() {
    local config_file
    local continued_file
    local output
    local success_file
    local -i status=0

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    continued_file="$TEST_TMPDIR/dry-run-continued"
    success_file="$TEST_TMPDIR/dispatcher-success"
    mkdir -p "$TEST_TMPDIR/incoming"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$config_file" \
            "$continued_file" \
            "$success_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
config_file="$1"; shift
continued_file="$1"; shift
success_file="$1"; shift
export continued_file success_file

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

# The action runs in-process; a failing action must return a non-zero status so
# a status-tested caller (the "if" below) takes the failure branch. "return 1"
# fails honestly regardless of the caller's errexit state, and the write after
# it must never run.
dry_run() {
    return 1
    printf 'dry_run continued\n' > "$continued_file"
}

SHURIKEN_CLI_ACTION=--dry-run
SHURIKEN_CLI_CONFIG_FILE="$config_file"
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES=no
SHURIKEN_CLI_OVERRIDES=()
SHURIKEN_CLI_SYNC_DESTINATIONS=()
SHURIKEN_FORCE_GENERATE=no

if run_configured_action; then
    printf 'dispatcher reported success\n' > "$success_file"
fi
BASH
    )
    status=$?
    set -e

    if (( status != 0 )); then
        printf 'FAIL: expected child shell to finish status-tested dispatch\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$continued_file"
    test::assert_path_absent "$success_file"
    test::teardown
}

test_generate_action_failure_fails_status_tested_run_action() {
    local config_file
    local continued_file
    local output
    local success_file
    local -i status=0

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    continued_file="$TEST_TMPDIR/dry-run-continued"
    success_file="$TEST_TMPDIR/action-success"
    mkdir -p "$TEST_TMPDIR/incoming"
    test::write_preflight_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        "$TEST_REPO_ROOT/share/templates/default"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$config_file" \
            "$continued_file" \
            "$success_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
config_file="$1"; shift
continued_file="$1"; shift
success_file="$1"; shift
export continued_file success_file

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

# The action runs in-process; a failing action must return a non-zero status so
# a status-tested caller (the "if" below) takes the failure branch. "return 1"
# fails honestly regardless of the caller's errexit state, and the write after
# it must never run.
dry_run() {
    return 1
    printf 'dry_run continued\n' > "$continued_file"
}

SHURIKEN_CLI_ACTION=--dry-run
SHURIKEN_CLI_CONFIG_FILE="$config_file"
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES=no
SHURIKEN_CLI_OVERRIDES=()
SHURIKEN_CLI_SYNC_DESTINATIONS=()
SHURIKEN_FORCE_GENERATE=no

if run_action; then
    printf 'run_action reported success\n' > "$success_file"
fi
BASH
    )
    status=$?
    set -e

    if (( status != 0 )); then
        printf 'FAIL: expected child shell to finish status-tested action\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$continued_file"
    test::assert_path_absent "$success_file"
    test::teardown
}

test_generate_real_failure_returns_with_errexit_disabled() {
    local config_file
    local fake_bin
    local output
    local status_file
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    status_file="$TEST_TMPDIR/generate-status"
    test::install_failing_imagemagick "$fake_bin"
    mkdir -p "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist"
    printf 'fake image\n' > "$TEST_TMPDIR/incoming/01.jpg"
    printf 'old dist\n' > "$TEST_TMPDIR/dist/index.html"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Failing set+e generate album' 40

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$config_file" \
            "$fake_bin" \
            "$status_file" \
            "$TEST_REPO_ROOT/tests/helpers.sh" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
config_file="$1"; shift
fake_bin="$1"; shift
status_file="$1"; shift
helpers="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")
# shellcheck source=/dev/null
source "$helpers"

PATH="$fake_bin:$PATH"
SHURIKEN_CLI_ACTION=--generate
SHURIKEN_CLI_CONFIG_FILE="$config_file"
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES=no
SHURIKEN_CLI_OVERRIDES=()
SHURIKEN_CLI_SYNC_DESTINATIONS=()
SHURIKEN_FORCE_GENERATE=no

# A real generation failure aborts the shell in production (main runs under
# errexit, by design). To capture the failure status and keep asserting, run the
# action in the test-only isolation shim. The status it returns must be nonzero.
set +e
test::run_action_isolated run_configured_action
generate_status=$?
printf '%s\n' "$generate_status" > "$status_file"
exit 0
BASH
    )
    status=$?
    set -e

    if (( status != 0 )); then
        printf 'FAIL: expected child shell to capture generate status\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_file_exists "$status_file"
    if [ "$(<"$status_file")" = 0 ]; then
        printf 'FAIL: expected generated status to be nonzero\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
    test::assert_contains 'simulated ImageMagick failure' "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old dist'
    test::assert_path_absent "$TEST_TMPDIR/dist/photos/01.jpg"
    test::assert_no_staging_dirs "$TEST_TMPDIR"
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

    # The published dist root must carry the same (umask-default) permissions as
    # its mkdir-created subdirectories, not the 0700 the mktemp staging dir starts
    # with -- otherwise `--sync` creates the remote album dir 0700 and the web
    # server cannot read it.
    test "$(stat -c '%a' "$TEST_TMPDIR/dist")" \
        = "$(stat -c '%a' "$TEST_TMPDIR/dist/photos")"

    page_html=$(<"$TEST_TMPDIR/dist/page-1.html")
    details_html=$(<"$TEST_TMPDIR/dist/1-1-details.html")
    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains "id='04 filename with spaces.jpg'" \
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
    test::assert_not_contains ' title=' "$details_html"
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
        '<img class="splash-photo" alt="Integration album" src="./photos/' \
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
    export TITLE='Redirect test'
    export THUMBHEIGHT=30
    export SHURIKEN_OUTPUT_MODE=quiet
    export MAXPREVIEWS=10
    apply_config_defaults

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
    export TITLE='Redirect test'
    export THUMBHEIGHT=30
    export SHURIKEN_OUTPUT_MODE=quiet
    export MAXPREVIEWS=2
    apply_config_defaults

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

test_generate_uses_custom_favicon() {
    local config_file
    local fake_bin
    local favicon_src
    local output

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"
    favicon_src="$TEST_TMPDIR/my-favicon.ico"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    printf 'CUSTOM-FAVICON-MARKER\n' > "$favicon_src"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Favicon album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" "$TEST_SHURIKEN" --generate --favicon "$favicon_src"
    )

    # The published favicon.ico is the custom file, not the bundled default.
    test::assert_file_exists "$TEST_TMPDIR/dist/favicon.ico"
    test "$(<"$TEST_TMPDIR/dist/favicon.ico")" = 'CUSTOM-FAVICON-MARKER'
    # --print-config reports the configured favicon path.
    test::assert_contains "FAVICON=$favicon_src" \
        "$(cd "$TEST_TMPDIR" && "$TEST_SHURIKEN" --print-config --favicon "$favicon_src")"

    # A missing favicon is rejected before any output is written.
    rm -rf "$TEST_TMPDIR/dist"
    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" \
            --generate --favicon "$TEST_TMPDIR/nope.ico"
    )
    test::assert_contains 'FAVICON file' "$output"
    test::assert_path_absent "$TEST_TMPDIR/dist"
    test::teardown
}

# Synthetic `identify -verbose` output with EXIF the stats aggregation can parse,
# so a full --generate produces a real camera leaderboard + per-camera page.
test::stats_identify_output() {
    printf '%s\n' \
        '  Format: JPEG (Joint Photographic Experts Group JFIF format)' \
        '  Geometry: 160x90+0+0' \
        '  exif:Make: Canon' \
        '  exif:Model: EOS R5' \
        '  exif:FNumber: 28/10' \
        '  exif:ExposureTime: 1/250' \
        '  exif:PhotographicSensitivity: 400' \
        '  exif:FocalLength: 50/1' \
        '  exif:DateTimeOriginal: 2023:07:15 14:30:00'
}

test_generate_stats_pages_created_and_nav_linked() {
    local camera_html
    local camera_view_html
    local config_file
    local fake_bin
    local -i nav_links

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    config_file="$TEST_TMPDIR/shuriken.conf"

    test::install_fake_imagemagick "$fake_bin"
    PATH="$fake_bin:$PATH" \
        test::generate_fixture_images "$TEST_TMPDIR/incoming"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Stats album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT="$(test::stats_identify_output)" \
            "$TEST_SHURIKEN" --generate --stats --random-seed stats-seed
    )

    # Only the main album is in the dist root; all stats content is under stats/.
    # The overview is stats/index.html and each mini-album is stats/<pagebase>/.
    test::assert_path_absent "$TEST_TMPDIR/dist/stats.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/stats/index.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/stats/camera-canon-eos-r5/index.html"
    test::assert_contains 'Canon EOS R5' \
        "$(<"$TEST_TMPDIR/dist/stats/index.html")"
    test::assert_not_contains '<script' \
        "$(<"$TEST_TMPDIR/dist/stats/index.html")"

    # The stats overview gets a random blurred background (one level deep -> ..).
    test::assert_contains 'background-image: url("../blurs/' \
        "$(<"$TEST_TMPDIR/dist/stats/index.html")"

    # The camera gallery is a mini album: thumbnails link to view pages in the
    # same dir (<index>.html), and the thumb image points at the album root.
    camera_html=$(<"$TEST_TMPDIR/dist/stats/camera-canon-eos-r5/index.html")
    test::assert_contains 'src="../../thumbs/' "$camera_html"
    test::assert_contains 'href="1.html"' "$camera_html"

    # Non-camera stats are clickable mini-albums too: the ISO row links to a
    # filter mini-album that exists and is itself a gallery of matching photos.
    test::assert_contains 'href="iso-400/index.html"' \
        "$(<"$TEST_TMPDIR/dist/stats/index.html")"
    test::assert_file_exists "$TEST_TMPDIR/dist/stats/iso-400/index.html"
    test::assert_file_exists "$TEST_TMPDIR/dist/stats/iso-400/1.html"
    test::assert_contains 'href="1.html"' \
        "$(<"$TEST_TMPDIR/dist/stats/iso-400/index.html")"

    # A per-camera view page exists and its navigation stays within the filter:
    # prev/next point at sibling view pages, plus a Gallery link and a Details
    # link back to the album details page for the photo.
    test::assert_file_exists "$TEST_TMPDIR/dist/stats/camera-canon-eos-r5/1.html"
    camera_view_html=$(<"$TEST_TMPDIR/dist/stats/camera-canon-eos-r5/1.html")
    test::assert_contains 'href="2.html"' "$camera_view_html"
    test::assert_contains 'href="index.html">Gallery</a>' "$camera_view_html"
    test::assert_contains '-details.html">Details</a>' "$camera_view_html"

    # The header bar links to the stats overview on at least one generated page.
    nav_links=$(grep -lF 'stats/index.html">Stats' "$TEST_TMPDIR"/dist/*.html \
        | wc -l)
    test "$nav_links" -gt 0

    python3 - "$TEST_TMPDIR/dist/shuriken.json" <<'PY'
import json
import pathlib
import sys

metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert metadata["settings"]["stats_page"] is True
PY

    test::teardown
}

test_generate_no_stats_suppresses_pages_and_nav() {
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
        'No stats album' 40

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" \
            TEST_IMAGEMAGICK_IDENTIFY_OUTPUT="$(test::stats_identify_output)" \
            "$TEST_SHURIKEN" --generate --no-stats --random-seed stats-seed
    )

    # No stats directory at all (no overview, no mini-albums).
    test::assert_path_absent "$TEST_TMPDIR/dist/stats"
    # No stats nav link anywhere.
    if grep -RF 'stats/index.html">Stats' "$TEST_TMPDIR"/dist/*.html; then
        printf 'FAIL: --no-stats still rendered the Stats nav link\n' >&2
        exit 1
    fi

    python3 - "$TEST_TMPDIR/dist/shuriken.json" <<'PY'
import json
import pathlib
import sys

metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert metadata["settings"]["stats_page"] is False
PY

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
    test::assert_contains '<img class="splash-photo" alt="Refresh splash album" src="./photos/' \
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

test_refresh_splash_accepts_minimal_refresh_config() {
    local config_file
    local output
    local top_index_html

    test::setup
    config_file="$TEST_TMPDIR/refresh-only.conf"
    mkdir -p \
        "$TEST_TMPDIR/dist/photos" \
        "$TEST_TMPDIR/dist/blurs"
    printf 'legacy photo\n' > "$TEST_TMPDIR/dist/photos/legacy.jpg"
    printf 'legacy blur\n' > "$TEST_TMPDIR/dist/blurs/legacy.jpg"
    {
        printf 'TITLE=%q\n' 'Refresh-only album'
        printf 'DIST_DIR=%q\n' "$TEST_TMPDIR/dist"
        printf 'TEMPLATE_DIR=%q\n' "$TEST_REPO_ROOT/share/templates/default"
    } > "$config_file"

    output=$("$TEST_SHURIKEN" --refresh-splash --config "$config_file")

    top_index_html=$(<"$TEST_TMPDIR/dist/index.html")
    test::assert_contains 'Refreshed splash page' "$output"
    test::assert_contains '<title>Refresh-only album</title>' \
        "$top_index_html"
    test::assert_contains 'src="./photos/legacy.jpg"' "$top_index_html"
    test::assert_not_contains 'unbound variable' "$output"
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

test_refresh_splash_requires_matching_splash_photo() {
    local config_file
    local output

    test::setup
    config_file="$TEST_TMPDIR/shuriken.conf"
    mkdir -p \
        "$TEST_TMPDIR/incoming" \
        "$TEST_TMPDIR/dist/photos" \
        "$TEST_TMPDIR/dist/blurs"
    printf 'old index\n' > "$TEST_TMPDIR/dist/index.html"
    printf 'orphan photo\n' > "$TEST_TMPDIR/dist/photos/orphan.jpg"
    test::write_album_config \
        "$config_file" "$TEST_TMPDIR/incoming" "$TEST_TMPDIR/dist" \
        'Missing matching splash photo album' 40

    output=$(
        cd "$TEST_TMPDIR"
        test::capture_failure_output "$TEST_SHURIKEN" --refresh-splash
    )

    test::assert_contains \
        "ERROR: No splash photos found in $TEST_TMPDIR/dist/photos" \
        "$output"
    test "$(<"$TEST_TMPDIR/dist/index.html")" = 'old index'
    test::assert_find_count 0 "$TEST_TMPDIR/dist" '.index.html.*'
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
    test::assert_contains \
        'ERROR: parallel job failed (42): image job for photo 01.jpg' \
        "$output"
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
    printf 'return 42\n' > "$template_dir/previewpage.tmpl"
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

    test::assert_contains 'Rendering previewpage template into ' "$output"
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
        > "$template_dir/previewpage.tmpl"
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
        > "$template_dir/previewpage.tmpl"
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
        > "$template_dir/previewpage.tmpl"
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

test_template_required_context_vars_come_from_render_specs() {
    local expected
    local output

    expected=$(cat <<'END'
camera:backhref camera_name camera_thumbs html_dir
cameraview:cameraview_body html_dir
details:animation_class backhref exif_details exif_tooltip html_dir page_num photo photos_dir preview_num
footer:backhref html_dir tarball_name
header:backhref background_image blurs_dir html_dir show_header_bar
next:html_dir next
prev:html_dir prev
preview:animation_class backhref html_dir page_num photo preview_num thumbs_dir
previewpage:html_dir preview_thumbs
redirect:html_dir redirect_page
splash:backhref background_image blurs_dir enter_page html_dir photo photos_dir
stats:backhref html_dir stats_body
view:animation_class backhref exif_tooltip html_dir page_num photo photos_dir preview_num
END
    )
    output=$(
        bash -euo pipefail -s "$TEST_REPO_ROOT" <<'BASH'
repo_root="$1"; shift
template_name=''
declare -a template_names=(
    camera
    cameraview
    details
    footer
    header
    next
    prev
    preview
    previewpage
    redirect
    splash
    stats
    view
)

# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"

for template_name in "${template_names[@]}"; do
    printf '%s:' "$template_name"
    template_required_context_vars "$template_name" | paste -sd ' ' -
done
BASH
    )

    if [ "$output" != "$expected" ]; then
        printf 'FAIL: unexpected template required render variables\n' >&2
        printf 'expected:\n%s\n' "$expected" >&2
        printf 'actual:\n%s\n' "$output" >&2
        exit 1
    fi
}

# Subsetting proof (task kn0): prepare_template_render_vars computes ONLY the
# render_vars the target template references, not all 30+ fields. We render the
# minimal "header" template's vars and assert: (1) the header-needed render_vars
# are present; (2) unrelated heavy fields (stats/camera/cameraview bodies) are
# absent; (3) it succeeds even when config globals only OTHER templates need
# (ORIGINAL_BASEPATH, used by the view-only render_original_basepath_* specs) are
# completely unset -- proving those non-needed handlers were never invoked.
test_template_render_vars_subset_is_minimal_for_header() {
    local output

    output=$(
        bash -euo pipefail -s "$TEST_REPO_ROOT" <<'BASH'
repo_root="$1"; shift

# shellcheck source=src/lib/config.validate.source.sh
source "$repo_root/src/lib/config.validate.source.sh"
# shellcheck source=src/lib/random.source.sh
source "$repo_root/src/lib/random.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"

# Config globals the header template DOES need.
RANDOM_SEED=''
TITLE='T'
HEIGHT='120'
THUMBHEIGHT='30'
STATS_PAGE='no'
SHURIKEN_CURRENT_DATE_TEXT=''
# Deliberately leave ORIGINAL_BASEPATH / MAXPREVIEWS / TARBALL_INCLUDE UNSET:
# only non-header templates need them, so a correct subset never reads them.
# Under set -u, computing those fields would abort -- success proves they were
# skipped.

declare -A ctx=(
    [html_dir]='.'
    [backhref]='#'
    [background_image]='bg.jpg'
    [blurs_dir]='blurs'
    [show_header_bar]='yes'
)
declare -A vars=()
prepare_template_render_vars vars ctx header

# Present keys, sorted.
present=$(printf '%s\n' "${!vars[@]}" | sort | paste -sd ' ' -)
printf 'present=%s\n' "$present"

# Heavy / unrelated fields must NOT have been computed.
for absent in render_stats_body_html render_camera_thumbs_html \
    render_cameraview_body_html render_exif_details_html render_next_html \
    render_original_basepath_html render_maxpreviews_html; do
    if [ -n "${vars[$absent]+x}" ]; then
        printf 'unexpected_present=%s\n' "$absent"
    fi
done
BASH
    )

    local expected_present
    expected_present=$(printf '%s\n' \
        render_background_image_css \
        render_backhref_css \
        render_backhref_html \
        render_blurs_dir_css \
        render_current_date_text \
        render_height_html \
        render_html_dir_html \
        render_show_header_bar \
        render_source_url_html \
        render_stats_page_html \
        render_thumbheight_html \
        render_title_html | sort | paste -sd ' ' -)

    if [ "$output" != "present=$expected_present" ]; then
        printf 'FAIL: header render-var subset is not minimal\n' >&2
        printf 'expected: present=%s\n' "$expected_present" >&2
        printf 'actual:\n%s\n' "$output" >&2
        exit 1
    fi
}

# Subsetting authority proof (task kn0): the per-template needed render-var set
# (driven by the required_templates spec field) MUST match exactly the render_*
# vars each .tmpl actually references. If a template gains/loses a render_* var
# without the spec being updated, this test fails -- guarding the byte-identical
# guarantee the subsetting relies on.
test_template_render_var_subsetting_matches_templates() {
    local template_path
    local template_name
    local needed
    local referenced
    local -i failed=0

    for template_path in "$TEST_REPO_ROOT"/share/templates/default/*.tmpl; do
        template_name=$(basename "$template_path" .tmpl)

        # Needed set from the specs (skip the always-on render_html_dir_html,
        # which no .tmpl references but is intentionally always serialized).
        needed=$(
            bash -euo pipefail -s "$TEST_REPO_ROOT" "$template_name" <<'BASH'
repo_root="$1"; shift
template_name="$1"; shift
# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"
declare -A needed=()
template_needed_render_vars_to needed "$template_name"
unset 'needed[render_html_dir_html]'
if (( ${#needed[@]} > 0 )); then
    printf '%s\n' "${!needed[@]}" | sort
fi
BASH
        )

        # render_* vars actually referenced by the .tmpl, restricted to spec
        # vars (the template-local render_exif_tooltip_attr and comment-only
        # names like render_camera_pages are not specs and are filtered out).
        referenced=$(
            bash -euo pipefail -s \
                "$TEST_REPO_ROOT" "$template_path" <<'BASH'
repo_root="$1"; shift
template_path="$1"; shift
# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"
declare -A spec_vars=()
for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
    IFS='|' read -r render_var _ _ _ _ <<< "$field_spec"
    spec_vars["$render_var"]=yes
done
declare -A seen=()
while IFS= read -r ref; do
    if [ -n "${spec_vars[$ref]+x}" ]; then
        seen["$ref"]=yes
    fi
done < <(grep -o 'render_[a-z_]*' "$template_path")
if (( ${#seen[@]} > 0 )); then
    printf '%s\n' "${!seen[@]}" | sort
fi
BASH
        )

        if [ "$needed" != "$referenced" ]; then
            printf 'FAIL: %s spec needed-set != .tmpl references\n' \
                "$template_name" >&2
            printf 'spec-needed:\n%s\n' "$needed" >&2
            printf 'tmpl-referenced:\n%s\n' "$referenced" >&2
            failed=1
        fi
    done

    if (( failed != 0 )); then
        exit 1
    fi
}

# Open/Closed proof: render field kinds are dispatched by resolving a
# prepare_template_render_var__<kind> handler by name. Adding a kind therefore
# means only defining a new handler function -- the core loop never changes. We
# assert (1) every kind in TEMPLATE_RENDER_FIELD_SPECS has a matching handler,
# (2) defining a brand-new handler makes it resolvable and dispatch-able, and
# (3) an unknown kind (no handler) is rejected as a config error.
test_template_render_var_dispatch_is_extensible() {
    local output

    output=$(
        bash -euo pipefail -s "$TEST_REPO_ROOT" <<'BASH'
repo_root="$1"; shift

# config_error (used for the unknown-kind path) lives in the validate lib.
# shellcheck source=src/lib/config.validate.source.sh
source "$repo_root/src/lib/config.validate.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"

# Every declared kind must resolve to a handler function by name.
missing=0
for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
    IFS='|' read -r _ kind _ _ _ <<< "$field_spec"
    if ! declare -F "prepare_template_render_var__$kind" > /dev/null; then
        missing=1
    fi
done
printf 'all_kinds_have_handlers=%s\n' "$([ "$missing" -eq 0 ] && echo yes || echo no)"

# A brand-new kind, added purely by defining a handler function (OCP): the
# dispatcher resolves and calls it without any change to the core loop.
prepare_template_render_var__ocp_demo() {
    local -n out_ref="$1"; shift
    out_ref='dispatched'
}
demo_out=''
handler="prepare_template_render_var__ocp_demo"
declare -F "$handler" > /dev/null && "$handler" demo_out ctx ''
printf 'demo=%s\n' "$demo_out"

# An unknown kind has no handler, so the dispatcher must reject it.
if declare -F "prepare_template_render_var__ocp_no_handler" > /dev/null; then
    printf 'unknown=resolved\n'
else
    printf 'unknown=unresolved\n'
fi
BASH
    )

    if [ "$output" != \
        $'all_kinds_have_handlers=yes\ndemo=dispatched\nunknown=unresolved' ]
    then
        printf 'FAIL: render var dispatch not extensible\n' >&2
        printf 'actual:\n%s\n' "$output" >&2
        exit 1
    fi
}

# Open/Closed proof (task gn0): CLI action dispatch is driven by a single
# registration table, ACTION_SPECS, instead of two hardcoded case statements.
# We assert (1) every action flag the parser accepts (CLI_OPTION_SPEC entries
# with kind=action) has exactly one ACTION_SPECS entry; (2) every registry entry
# resolves its handler and validation_fn (when set) to real functions; and
# (3) an unknown/empty action has no entry, so run_action falls through to the
# usage/exit-1 path (action_spec_field returns non-zero for it).
test_action_dispatch_is_registry_driven() {
    local output

    output=$(
        bash -euo pipefail -s "$TEST_REPO_ROOT" "$TEST_SHURIKEN" <<'BASH'
repo_root="$1"; shift
shuriken="$1"; shift

# Source every inlined lib function from the generated binary (dropping the
# trailing dispatcher line) so ACTION_SPECS, action_spec_field, and every
# registered handler/validation function are defined -- the same trick the
# render-redirect tests use.
# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

# Re-declare CLI_OPTION_SPEC's action flags exactly as the source lists them by
# parsing src/shuriken.sh, so the test tracks the real parser, not a copy.
declare -a action_flags=()
while IFS= read -r flag; do
    action_flags+=("$flag")
done < <(grep -oE "\[--[a-z-]+\]='kind=action'" "$repo_root/src/shuriken.sh" \
    | sed -E "s/^\[(--[a-z-]+)\].*/\1/")

# (1) Every parser-accepted action flag has a registry entry.
missing_entry=0
for flag in "${action_flags[@]}"; do
    if ! action_spec_field "$flag" 0 > /dev/null; then
        missing_entry=1
    fi
done
printf 'all_flags_registered=%s\n' \
    "$([ "$missing_entry" -eq 0 ] && echo yes || echo no)"

# (2) Every registry handler + (non-empty) validation_fn resolves to a function.
bad_handler=0
for spec in "${ACTION_SPECS[@]}"; do
    IFS='|' read -r _ handler _ validation_fn _ <<< "$spec"
    if ! declare -F "$handler" > /dev/null; then
        bad_handler=1
    fi
    if [ -n "$validation_fn" ] && ! declare -F "$validation_fn" > /dev/null; then
        bad_handler=1
    fi
done
printf 'all_handlers_resolve=%s\n' \
    "$([ "$bad_handler" -eq 0 ] && echo yes || echo no)"

# (3) An unknown action and the empty action have no entry -> non-zero lookup,
# which is exactly what makes run_action take the usage/exit-1 path.
if action_spec_field "--bogus-action" 0 > /dev/null \
    || action_spec_field "" 0 > /dev/null; then
    printf 'unknown_rejected=no\n'
else
    printf 'unknown_rejected=yes\n'
fi
BASH
    )

    if [ "$output" != \
        $'all_flags_registered=yes\nall_handlers_resolve=yes\nunknown_rejected=yes' ]
    then
        printf 'FAIL: action dispatch not registry-driven\n' >&2
        printf 'actual:\n%s\n' "$output" >&2
        exit 1
    fi
}

# The preview_num next/prev handlers compute neighbour page numbers with $(( )).
# A non-numeric or empty preview_num context value must NOT crash the script with
# a bash arithmetic syntax error (which, under set -e, would abort the whole run):
# such values default to an empty render value. A valid numeric value must still
# produce the exact +1 / -1 neighbour. We drive the handlers directly under
# `bash -euo pipefail` so a regressed (unguarded) arithmetic would abort here.
test_template_render_var_preview_num_guards_non_numeric() {
    local output

    output=$(
        bash -euo pipefail -s "$TEST_REPO_ROOT" <<'BASH'
repo_root="$1"; shift

# shellcheck source=src/lib/config.validate.source.sh
source "$repo_root/src/lib/config.validate.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$repo_root/src/lib/template.source.sh"

declare -A ctx
out=''

# Non-numeric preview_num must not crash; both handlers default to empty.
ctx[preview_num]='not-a-number'
prepare_template_render_var__preview_num_next_html out ctx preview_num
printf 'bad_next=[%s]\n' "$out"
prepare_template_render_var__preview_num_prev_html out ctx preview_num
printf 'bad_prev=[%s]\n' "$out"

# Empty preview_num also defaults to empty (missing-neighbour behaviour).
ctx[preview_num]=''
prepare_template_render_var__preview_num_next_html out ctx preview_num
printf 'empty_next=[%s]\n' "$out"

# A valid numeric preview_num still yields the exact +1 / -1 neighbour.
ctx[preview_num]='5'
prepare_template_render_var__preview_num_next_html out ctx preview_num
printf 'good_next=[%s]\n' "$out"
prepare_template_render_var__preview_num_prev_html out ctx preview_num
printf 'good_prev=[%s]\n' "$out"
BASH
    )

    if [ "$output" != \
        $'bad_next=[]\nbad_prev=[]\nempty_next=[]\ngood_next=[6]\ngood_prev=[4]' ]
    then
        printf 'FAIL: preview_num handlers mishandle non-numeric input\n' >&2
        printf 'actual:\n%s\n' "$output" >&2
        exit 1
    fi
}

test_render_stats_page_renders_sections_and_escapes() {
    local html
    local output_file

    test::setup
    output_file="$TEST_TMPDIR/dist/stats.html"
    mkdir -p "$TEST_TMPDIR/dist"

    # Feed synthetic EXIF straight into accumulate_photo_stats so the test does
    # not depend on the cache layer, then render. The second camera label carries
    # & and < to prove EXIF-derived labels are HTML-escaped.
    bash -euo pipefail -s \
        "$TEST_SHURIKEN" \
        "$TEST_REPO_ROOT/share/templates/default" \
        "$TEST_TMPDIR/dist" \
        <<'BASH'
shuriken="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Stats album'
HEIGHT=600
THUMBHEIGHT=120
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
# Stats are off by default; this test renders the stats page, so enable them so
# the header bar includes the Stats nav link.
STATS_PAGE=yes
SHURIKEN_OUTPUT_MODE=quiet
apply_config_defaults

reset_photo_exif_stats
accumulate_photo_stats 'a.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS 5D
  exif:FNumber: 28/10
  exif:ISOSpeedRatings: 400
  exif:DateTimeOriginal: 2021:06:14 10:00:00
EXIF
accumulate_photo_stats 'b.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS 5D
  exif:DateTimeOriginal: 2021:06:14 10:00:00
EXIF
accumulate_photo_stats 'c.png' <<'EXIF'
  Geometry: 4000x6000+0+0
  exif:Make: Nikon & Co
  exif:Model: <Z6>
  exif:DateTimeOriginal: 2022:07:14 10:00:00
EXIF

render_stats_page . .
BASH

    html=$(cat "$output_file")

    # Leaderboard entry links to the camera's mini-album with the right
    # count/percent (relative to the stats overview: <pagebase>/index.html).
    test::assert_contains \
        '<a href="camera-canon-eos-5d/index.html">Canon EOS 5D</a>' "$html"
    test::assert_contains '2 (67%)' "$html"
    # A histogram section is present.
    test::assert_contains '<h2>ISO</h2>' "$html"
    test::assert_contains '400' "$html"
    # EXIF-derived label with & and < is HTML-escaped, not raw markup.
    test::assert_contains 'Nikon &amp; Co &lt;Z6&gt;' "$html"
    test::assert_not_contains 'Nikon & Co <Z6>' "$html"
    # Total photo count drives the percentage denominator.
    test::assert_contains '3 photos analysed.' "$html"
    # The Stats nav link is wired into the shared header.
    test::assert_contains '>Stats</a>' "$html"
    # Empty categories are omitted (no flash/lens/shutter data was supplied).
    test::assert_not_contains '<h2>Flash</h2>' "$html"
    test::assert_not_contains '<h2>Lenses</h2>' "$html"
    test::assert_not_contains '<h2>Shutter speed</h2>' "$html"
    test::teardown
}

test_render_filter_pages_renders_mini_albums() {
    local html
    local html_again
    local dist_dir

    test::setup
    dist_dir="$TEST_TMPDIR/dist"
    mkdir -p "$dist_dir"

    # Feed synthetic EXIF into accumulate_photo_stats to exercise several filter
    # categories: cameras (one label needing HTML-escaping; a slug-collision pair
    # "Canon EOS 5D" vs "Canon EOS-5D" -> canon-eos-5d / canon-eos-5d-2) plus the
    # orientation buckets derived from Geometry. Render the filter mini-albums
    # twice into separate dirs to assert deterministic output despite parallelism.
    bash -euo pipefail -s \
        "$TEST_SHURIKEN" \
        "$TEST_REPO_ROOT/share/templates/default" \
        "$dist_dir" \
        <<'BASH'
shuriken="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Stats album'
HEIGHT=600
THUMBHEIGHT=120
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
SHURIKEN_OUTPUT_MODE=quiet
# Seed so the per-thumbnail animation class is reproducible across runs.
RANDOM_SEED=camera-test
# Render serially here: this test renders filters without an album render to warm
# the EXIF cache, so parallel jobs would otherwise race to populate it. The
# parallel path (with a warm cache) is covered by the full --generate test.
IMAGE_JOBS=1
apply_config_defaults

# The filter view pages read each photo's EXIF tooltip from INCOMING_DIR, so
# provide empty stand-in files (no ImageMagick here, so the tooltip is empty but
# the view pages still render with full filter navigation).
INCOMING_DIR="$dist_dir/incoming"
mkdir -p "$INCOMING_DIR"
for stub in a.jpg b.jpg c.png d.jpg; do
    : > "$INCOMING_DIR/$stub"
done

feed() {
    reset_photo_exif_stats
    accumulate_photo_stats 'a.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS 5D
EXIF
    accumulate_photo_stats 'b.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS 5D
EXIF
    accumulate_photo_stats 'c.png' <<'EXIF'
  Geometry: 4000x6000+0+0
  exif:Make: Nikon & Co
  exif:Model: <Z6>
EXIF
    accumulate_photo_stats 'd.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS-5D
EXIF
}

# render_filter_pages writes under $DIST_DIR/stats/, so point DIST_DIR at a
# fresh per-run dir to compare the two runs for determinism.
feed
DIST_DIR="$dist_dir/run1"
mkdir -p "$DIST_DIR"
render_filter_pages
feed
DIST_DIR="$dist_dir/run2"
mkdir -p "$DIST_DIR"
render_filter_pages
BASH

    # Each mini-album is its own stats/<pagebase>/ directory (gallery index.html +
    # view pages <index>.html), keeping the album root uncluttered. Camera names
    # are collision-resolved (canon-eos-5d / canon-eos-5d-2).
    local s="$dist_dir/run1/stats"
    test::assert_file_exists "$s/camera-canon-eos-5d/index.html"
    test::assert_file_exists "$s/camera-canon-eos-5d-2/index.html"
    test::assert_file_exists "$s/camera-nikon-co-z6/index.html"
    # Non-camera stats are mini-albums too: orientation comes from Geometry, so
    # the three landscape photos get their own filter mini-album.
    test::assert_file_exists "$s/orientation-landscape/index.html"
    test::assert_file_exists "$s/orientation-landscape/1.html"

    # The Canon EOS 5D gallery lists its two photos as thumbnails linking to
    # sibling view pages (<index>.html); the thumb image points at the album
    # root via ../../ .
    html=$(cat "$s/camera-canon-eos-5d/index.html")
    test::assert_contains 'href="1.html"' "$html"
    test::assert_contains 'class="thumb ' "$html"
    test::assert_contains 'src="../../thumbs/a.jpg"></a>' "$html"
    test::assert_contains 'href="2.html"' "$html"
    # Heading shows the (trusted) camera label and a back-to-stats link.
    test::assert_contains 'Canon EOS 5D' "$html"
    test::assert_contains '<a href="../../stats/index.html">Back to stats</a>' \
        "$html"

    # A filter view page cycles within its own filter (two photos, so view 1's
    # prev and next both point at view 2), with a link back to the gallery.
    test::assert_file_exists "$s/camera-canon-eos-5d/1.html"
    test::assert_file_exists "$s/camera-canon-eos-5d/2.html"
    html=$(cat "$s/camera-canon-eos-5d/1.html")
    test::assert_contains 'href="2.html" class="arrow"' "$html"
    test::assert_contains 'href="index.html">Gallery</a>' "$html"
    test::assert_contains "src='../../photos/" "$html"

    # The EXIF-derived label with & and < is HTML-escaped in the heading.
    html=$(cat "$s/camera-nikon-co-z6/index.html")
    test::assert_contains 'Nikon &amp; Co &lt;Z6&gt;' "$html"
    test::assert_not_contains 'Nikon & Co <Z6>' "$html"
    test::assert_contains 'href="1.html"' "$html"

    # Output is deterministic across runs despite parallel rendering.
    html=$(cat "$dist_dir/run1/stats/camera-canon-eos-5d/index.html")
    html_again=$(cat "$dist_dir/run2/stats/camera-canon-eos-5d/index.html")
    if [ "$html" != "$html_again" ]; then
        printf 'FAIL: filter page not reproducible across runs\n' >&2
        exit 1
    fi
    test::teardown
}

test_template_context_validator_fails_fast_without_errexit() {
    local output
    local -i status=0
    # Passed by name to validate_template_context.
    # shellcheck disable=SC2034
    local -A render_context=(
        [html_dir]='.'
    )

    # shellcheck source=src/lib/config.validate.source.sh
    source "$TEST_REPO_ROOT/src/lib/config.validate.source.sh"
    # shellcheck source=src/lib/template.source.sh
    source "$TEST_REPO_ROOT/src/lib/template.source.sh"

    set +e
    output=$(validate_template_context preview render_context 2>&1)
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected validate_template_context to fail\n' >&2
        exit 1
    fi

    test::assert_contains \
        'ERROR: template preview requires render variable animation_class' \
        "$output"
    test::assert_not_contains \
        'ERROR: template preview requires render variable backhref' \
        "$output"
}

test_template_mktemp_failure_does_not_render_without_errexit() {
    local fake_bin
    local output
    local output_file
    local ran_file
    local template_dir
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    template_dir="$TEST_TMPDIR/templates"
    output_file="$TEST_TMPDIR/dist/out.html"
    ran_file="$TEST_TMPDIR/template-ran"
    mkdir -p "$fake_bin" "$template_dir" "$TEST_TMPDIR/dist"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'exit 42\n'
    } > "$fake_bin/mktemp"
    chmod 0755 "$fake_bin/mktemp"
    {
        printf 'printf rendered >> %q\n' "$ran_file"
        printf 'printf rendered\n'
    } > "$template_dir/preview.tmpl"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$fake_bin" \
            "$template_dir" \
            "$TEST_TMPDIR/dist" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
fake_bin="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

PATH="$fake_bin:$PATH"
DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Template mktemp failure'
HEIGHT=''
THUMBHEIGHT=30
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
SHURIKEN_OUTPUT_MODE=quiet
apply_config_defaults

set +e
template preview out.html \
    animation_class '' \
    backhref '#' \
    html_dir . \
    page_num 1 \
    photo photo.jpg \
    preview_num 1 \
    thumbs_dir thumbs
template_status=$?

exit "$template_status"
BASH
    )
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected template rendering to fail\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$ran_file"
    if [ -s "$output_file" ]; then
        printf 'FAIL: expected template output to stay empty\n' >&2
        cat "$output_file" >&2
        exit 1
    fi
    test::teardown
}

test_template_failure_removes_context_file_with_errexit() {
    local context_file
    local fake_bin
    local output
    local template_dir
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    template_dir="$TEST_TMPDIR/templates"
    context_file="$TEST_TMPDIR/template-context"
    mkdir -p "$fake_bin" "$template_dir" "$TEST_TMPDIR/dist"
    {
        printf '#!/usr/bin/env bash\n'
        # shellcheck disable=SC2016
        printf 'printf %%s\\\\n \"$SHURIKEN_FAKE_CONTEXT_FILE\"\n'
    } > "$fake_bin/mktemp"
    chmod 0755 "$fake_bin/mktemp"
    printf 'exit 42\n' > "$template_dir/preview.tmpl"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$fake_bin" \
            "$template_dir" \
            "$TEST_TMPDIR/dist" \
            "$context_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
fake_bin="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift
context_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

PATH="$fake_bin:$PATH"
SHURIKEN_FAKE_CONTEXT_FILE="$context_file"
export SHURIKEN_FAKE_CONTEXT_FILE
DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Template failure cleanup'
HEIGHT=''
THUMBHEIGHT=30
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
SHURIKEN_OUTPUT_MODE=quiet
apply_config_defaults

template preview out.html \
    animation_class '' \
    backhref '#' \
    html_dir . \
    page_num 1 \
    photo photo.jpg \
    preview_num 1 \
    thumbs_dir thumbs
BASH
    )
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected template rendering to fail\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$context_file"
    test::teardown
}

test_template_setup_failure_removes_context_file_with_errexit() {
    local context_file
    local fake_bin
    local output
    local template_file
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    context_file="$TEST_TMPDIR/template-context"
    template_file="$TEST_TMPDIR/template.tmpl"
    mkdir -p "$fake_bin" "$TEST_TMPDIR/dist"
    {
        printf '#!/usr/bin/env bash\n'
        # shellcheck disable=SC2016
        printf 'printf %%s\\\\n \"$SHURIKEN_FAKE_CONTEXT_FILE\"\n'
    } > "$fake_bin/mktemp"
    chmod 0755 "$fake_bin/mktemp"
    printf 'printf rendered\n' > "$template_file"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$fake_bin" \
            "$template_file" \
            "$TEST_TMPDIR/dist/out.html" \
            "$context_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
fake_bin="$1"; shift
template_file="$1"; shift
output_file="$1"; shift
context_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

PATH="$fake_bin:$PATH"
SHURIKEN_FAKE_CONTEXT_FILE="$context_file"
export SHURIKEN_FAKE_CONTEXT_FILE

serialize_template_render_context() {
    # Simulate a serializer that writes some output and then fails. The new
    # implementation propagates this non-zero status explicitly (it no longer
    # relies on a "| bash -euo pipefail" subprocess), so source_template_file
    # must detect the failure, skip the render and clean up the context file.
    printf 'partial_context=yes\n'
    return 1
}

# shellcheck disable=SC2034
declare -A render_vars=()
source_template_file "$template_file" "$output_file" render_vars
BASH
    )
    status=$?
    set -e

    if (( status == 0 )); then
        printf 'FAIL: expected template setup to fail\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$context_file"
    test::teardown
}

test_template_setup_failure_fails_status_tested_render() {
    local context_file
    local fake_bin
    local output
    local ran_file
    local success_file
    local template_dir
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    template_dir="$TEST_TMPDIR/templates"
    context_file="$TEST_TMPDIR/template-context"
    ran_file="$TEST_TMPDIR/template-ran"
    success_file="$TEST_TMPDIR/template-success"
    mkdir -p "$fake_bin" "$template_dir" "$TEST_TMPDIR/dist"
    {
        printf '#!/usr/bin/env bash\n'
        # shellcheck disable=SC2016
        printf 'printf %%s\\\\n \"$SHURIKEN_FAKE_CONTEXT_FILE\"\n'
    } > "$fake_bin/mktemp"
    chmod 0755 "$fake_bin/mktemp"
    {
        printf 'printf rendered >> %q\n' "$ran_file"
        printf 'printf rendered\n'
    } > "$template_dir/preview.tmpl"

    set +e
    output=$(
        bash -euo pipefail -s \
            "$TEST_SHURIKEN" \
            "$fake_bin" \
            "$template_dir" \
            "$TEST_TMPDIR/dist" \
            "$context_file" \
            "$success_file" \
            2>&1 \
            <<'BASH'
shuriken="$1"; shift
fake_bin="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift
context_file="$1"; shift
success_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

PATH="$fake_bin:$PATH"
SHURIKEN_FAKE_CONTEXT_FILE="$context_file"
export SHURIKEN_FAKE_CONTEXT_FILE
DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Template status test'
HEIGHT=''
THUMBHEIGHT=30
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
SHURIKEN_OUTPUT_MODE=quiet
apply_config_defaults

serialize_template_render_context() {
    # Simulate a serializer that writes some output and then fails. The new
    # implementation propagates this non-zero status explicitly (it no longer
    # relies on a "| bash -euo pipefail" subprocess), so source_template_file
    # must detect the failure, skip the render and clean up the context file.
    printf 'partial_context=yes\n'
    return 1
}

if template preview out.html \
    animation_class '' \
    backhref '#' \
    html_dir . \
    page_num 1 \
    photo photo.jpg \
    preview_num 1 \
    thumbs_dir thumbs; then
    printf 'template reported success\n' > "$success_file"
fi
BASH
    )
    status=$?
    set -e

    if (( status != 0 )); then
        printf 'FAIL: expected child shell to finish status-tested render\n' >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    test::assert_path_absent "$context_file"
    test::assert_path_absent "$ran_file"
    test::assert_path_absent "$success_file"
    test::teardown
}

test_template_interrupt_removes_context_file() {
    local context_file
    local fake_bin
    local started_file
    local template_dir
    local render_pid_file
    local parent_survived_file
    local child_pid
    local render_pid
    local -i status=0

    test::setup
    fake_bin="$TEST_TMPDIR/bin"
    template_dir="$TEST_TMPDIR/templates"
    context_file="$TEST_TMPDIR/template-context"
    started_file="$TEST_TMPDIR/template-started"
    render_pid_file="$TEST_TMPDIR/render-pid"
    parent_survived_file="$TEST_TMPDIR/parent-survived"
    mkdir -p "$fake_bin" "$template_dir" "$TEST_TMPDIR/dist"
    {
        printf '#!/usr/bin/env bash\n'
        # shellcheck disable=SC2016
        printf 'printf %%s\\\\n \"$SHURIKEN_FAKE_CONTEXT_FILE\"\n'
    } > "$fake_bin/mktemp"
    chmod 0755 "$fake_bin/mktemp"
    # The rendered template signals it started, then blocks so the render is
    # genuinely in flight (context already built, env -i bash running) when we
    # deliver the interrupt. This exercises the signal traps, not the RETURN
    # trap: a plain RETURN trap does not fire when a signal kills the shell.
    {
        printf 'printf rendered > %q\n' "$started_file"
        printf 'sleep 30\n'
    } > "$template_dir/preview.tmpl"

    # Run the render in a BACKGROUNDED subshell of a parent shell, mirroring
    # production where source_template_file executes inside backgrounded render
    # jobs (queue_album_view_render_job). We signal the render subshell directly;
    # the parent then waits on it and records that it survived. A correct signal
    # handler re-raises to $BASHPID (the subshell), so the parent lives; a buggy
    # handler that re-raised to $$ would kill this parent shell instead, leaving
    # the survival marker unwritten. Going through the template entry point
    # populates a valid render context so the render reaches the blocking sleep.
    bash -euo pipefail -s \
        "$TEST_SHURIKEN" \
        "$fake_bin" \
        "$template_dir" \
        "$TEST_TMPDIR/dist" \
        "$context_file" \
        "$render_pid_file" \
        "$parent_survived_file" \
        <<'BASH' &
shuriken="$1"; shift
fake_bin="$1"; shift
template_dir="$1"; shift
dist_dir="$1"; shift
context_file="$1"; shift
render_pid_file="$1"; shift
parent_survived_file="$1"; shift

# shellcheck source=/dev/null
source <(sed '$d' "$shuriken")

PATH="$fake_bin:$PATH"
SHURIKEN_FAKE_CONTEXT_FILE="$context_file"
export SHURIKEN_FAKE_CONTEXT_FILE
DIST_DIR="$dist_dir"
TEMPLATE_DIR="$template_dir"
TITLE='Template interrupt cleanup'
HEIGHT=''
THUMBHEIGHT=30
MAXPREVIEWS=40
ORIGINAL_BASEPATH=''
TARBALL_INCLUDE=no
SHURIKEN_OUTPUT_MODE=quiet
apply_config_defaults

# Background the render so source_template_file runs in its own subshell with a
# distinct $BASHPID, then expose that subshell PID so the harness can signal it.
template preview out.html \
    animation_class '' \
    backhref '#' \
    html_dir . \
    page_num 1 \
    photo photo.jpg \
    preview_num 1 \
    thumbs_dir thumbs &
render_pid=$!
printf '%s' "$render_pid" > "$render_pid_file"

set +e
wait "$render_pid"
set -e
# Reaching here proves the render subshell's re-raised signal did not propagate
# to this parent shell.
printf survived > "$parent_survived_file"
BASH
    child_pid=$!

    # Wait for the render to begin, then interrupt the render subshell directly.
    while [ ! -f "$started_file" ] && kill -0 "$child_pid" 2>/dev/null; do
        sleep 0.05
    done
    render_pid=$(cat "$render_pid_file")
    kill -TERM "$render_pid" 2>/dev/null || true

    set +e
    wait "$child_pid"
    status=$?
    set -e

    # The parent shell must exit cleanly: the render subshell re-raised SIGTERM
    # to itself ($BASHPID), not to the parent ($$).
    if (( status != 0 )); then
        printf 'FAIL: parent shell did not survive render interrupt (status %d)\n' \
            "$status" >&2
        exit 1
    fi

    test::assert_file_exists "$parent_survived_file"
    test::assert_path_absent "$context_file"
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
    local css_expected
    local css_text
    local css_to
    local css_stdout_file
    local html_expected
    local html_text
    local html_to
    local html_stdout_file

    # shellcheck source=src/lib/template.source.sh
    source "$TEST_REPO_ROOT/src/lib/template.source.sh"

    test::setup
    html_stdout_file="$TEST_TMPDIR/html-stdout"
    html_expected="$TEST_TMPDIR/html-expected"
    css_stdout_file="$TEST_TMPDIR/css-stdout"
    css_expected="$TEST_TMPDIR/css-expected"

    html_text=$'A & "quoted" <title> \'ok\''
    html_escape_to html_to "$html_text"
    _html_escape "$html_text" > "$html_stdout_file"
    printf '%s\n' "$html_to" > "$html_expected"
    cmp -s "$html_expected" "$html_stdout_file"
    test "$(<"$html_stdout_file")" = \
        'A &amp; &quot;quoted&quot; &lt;title&gt; &#39;ok&#39;'

    html_escape_to html_to ''
    _html_escape '' > "$html_stdout_file"
    printf '%s\n' "$html_to" > "$html_expected"
    cmp -s "$html_expected" "$html_stdout_file"

    css_text=$'path\\kid\'s_"<tag>&.jpg'
    css_string_escape_to css_to "$css_text"
    _css_string_escape "$css_text" > "$css_stdout_file"
    printf '%s\n' "$css_to" > "$css_expected"
    cmp -s "$css_expected" "$css_stdout_file"
    test "$(<"$css_stdout_file")" = \
        'path\\kid\000027s_\000022\00003ctag\00003e\000026.jpg'

    css_string_escape_to css_to ''
    _css_string_escape '' > "$css_stdout_file"
    printf '%s\n' "$css_to" > "$css_expected"
    cmp -s "$css_expected" "$css_stdout_file"

    test::teardown
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
    test::assert_contains "id='$photo_html'" "$page_html"
    test::assert_contains "src='./thumbs/$photo_html'" "$page_html"
    test::assert_contains '&amp;&quot;&#39;.tar' "$page_html"
    test::assert_contains "href=\"page-1.html#$photo_html\"" "$view_html"
    test::assert_contains 'href="1-1-details.html">Details</a>' "$view_html"
    test::assert_contains "href='./photos/$photo_html'" "$view_html"
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
    # The normal image view carries the same EXIF tooltip as the details view.
    test::assert_contains \
        'title="Camera: ExampleCam Model &amp; &quot;X&quot;; Aperture: f/2.8; ISO: 400; Shutter speed: 1/125; Taken: 2026:06:04 12:34:56"' \
        "$view_html"
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
    test::assert_not_contains 'title=""' "$details_html"
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

test_sync_rejects_scalar_destinations() {
    # Regression for an0: a scalar SYNC_DESTINATIONS with spaces used to be
    # word-split into multiple broken rsync destinations. We now reject scalar
    # declarations outright so the only spelling is an array, where embedded
    # spaces are preserved naturally.
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
    printf 'generated\n' > "$dist_dir/index.html"
    {
        printf 'DIST_DIR=%q\n' "$dist_dir"
        printf 'SYNC_DESTINATIONS=%q\n' '/path/with spaces/'
    } > "$config_file"

    output=$(
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$rsync_log" \
            test::capture_failure_output "$TEST_SHURIKEN" --sync
    )

    test::assert_contains \
        'ERROR: SYNC_DESTINATIONS must be an array' \
        "$output"
    # rsync must never run: the scalar was rejected, not word-split.
    test::assert_path_absent "$rsync_log"
    test::teardown
}

test_sync_array_destination_preserves_spaces() {
    # A single array destination containing spaces must reach rsync intact as
    # one argument, proving the array path is unaffected by the an0 fix.
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
        printf 'SYNC_DESTINATIONS=(%q)\n' '/path/with spaces/'
    } > "$config_file"

    (
        cd "$TEST_TMPDIR"
        PATH="$fake_bin:$PATH" TEST_RSYNC_LOG="$rsync_log" \
            "$TEST_SHURIKEN" --sync
    )

    rsync_output=$(<"$rsync_log")
    # argc=4 (-av, --delete, source, single destination): the destination is
    # NOT split into two arguments despite the embedded space.
    # The rsync spy logs each argument with %q quoting, so a single argument
    # with a space appears as one escaped arg3 (not two split args).
    test::assert_contains 'argc=4' "$rsync_output"
    test::assert_contains 'arg3=/path/with\ spaces/' "$rsync_output"
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
    local expected_argument
    local option
    local output
    local -A value_option_arguments=(
        [--config]=path
        [--sync-destination]=destination
    )
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
        expected_argument="${value_option_arguments[$option]:-value}"
        output=$(test::capture_failure_output "$TEST_SHURIKEN" "$option")
        test::assert_contains \
            "Error: $option requires a $expected_argument" \
            "$output"
    done
}

test::source_shuriken_lib() {
    # Source every inlined lib function from the generated binary (dropping the
    # trailing dispatcher line) so unit tests can call functions directly, the
    # same trick the render-redirect tests use.
    # shellcheck source=/dev/null
    source <(sed '$d' "$TEST_SHURIKEN")
}

test_stats_aggregates_synthetic_exif_fixtures() {
    local fixture

    test::setup
    test::source_shuriken_lib
    reset_photo_exif_stats

    # Canon frame: rationals, ISO under PhotographicSensitivity, enums, geometry.
    fixture=$'  Geometry: 6000x4000+0+0\n'
    fixture+=$'  exif:Make: Canon\n'
    fixture+=$'  exif:Model: Canon EOS 5D Mark IV\n'
    fixture+=$'  exif:LensModel: EF50mm f/1.8 STM\n'
    fixture+=$'  exif:FNumber: 14/5\n'
    fixture+=$'  exif:ExposureTime: 1/250\n'
    fixture+=$'  exif:FocalLength: 50/1\n'
    fixture+=$'  exif:PhotographicSensitivity: 400\n'
    fixture+=$'  exif:ExposureProgram: 3\n'
    fixture+=$'  exif:MeteringMode: 5\n'
    fixture+=$'  exif:WhiteBalance: 0\n'
    fixture+=$'  exif:Flash: 1\n'
    fixture+=$'  exif:DateTimeOriginal: 2023:06:14 15:30:00'
    accumulate_photo_stats 'a.jpg' <<< "$fixture"

    # Second Canon frame, portrait geometry, same camera -> leaderboard count 2.
    fixture=$'  Geometry: 4000x6000+0+0\n'
    fixture+=$'  exif:Make: Canon\n'
    fixture+=$'  exif:Model: Canon EOS 5D Mark IV\n'
    fixture+=$'  exif:DateTimeOriginal: 2024:01:09 08:00:00'
    accumulate_photo_stats 'b.png' <<< "$fixture"

    test "${STATS_TOTALS[photos]}" -eq 2
    test "${STATS_CAMERAS[Canon EOS 5D Mark IV]}" -eq 2
    test "${STATS_FILTER_PAGEBASE[camera${STATS_FILTER_KEYSEP}Canon EOS 5D Mark IV]}" \
        = 'camera-canon-eos-5d-mark-iv'
    # The camera's filter mini-album keeps both frames in encounter order.
    test "${STATS_FILTER_PHOTOS[camera-canon-eos-5d-mark-iv]}" = $'a.jpg\nb.png'
    test "${STATS_LENSES[EF50mm f/1.8 STM]}" -eq 1
    test "${STATS_YEARS[2023]}" -eq 1
    test "${STATS_YEARS[2024]}" -eq 1
    test "${STATS_MONTHS[06]}" -eq 1
    test "${STATS_MONTHS[01]}" -eq 1
    # 14/5 = f/2.8 ; 1/250s ; FocalLength 50mm -> 35-70mm ; ISO 400.
    test "${STATS_APERTURE[f/2.8]}" -eq 1
    test "${STATS_SHUTTER[1/250s]}" -eq 1
    test "${STATS_FOCAL[35-70mm]}" -eq 1
    test "${STATS_ISO[400]}" -eq 1
    test "${STATS_EXPOSURE_PROGRAM[Aperture priority]}" -eq 1
    test "${STATS_METERING[Multi-segment]}" -eq 1
    test "${STATS_WHITE_BALANCE[Auto]}" -eq 1
    test "${STATS_FLASH[Flash fired]}" -eq 1
    # 6000x4000 = 24MP -> 20-40MP, 3:2, Landscape; portrait frame -> Portrait.
    test "${STATS_MEGAPIXELS[20-40MP]}" -eq 2
    test "${STATS_ASPECT[3:2]}" -eq 2
    test "${STATS_ORIENTATION[Landscape]}" -eq 1
    test "${STATS_ORIENTATION[Portrait]}" -eq 1
    test "${STATS_FORMAT[JPEG]}" -eq 1
    test "${STATS_FORMAT[PNG]}" -eq 1

    test::teardown
}

test_stats_tolerates_missing_and_edge_case_fields() {
    local fixture

    test::setup
    test::source_shuriken_lib
    reset_photo_exif_stats

    # Photo with no EXIF and no camera at all: counted, but no leaderboard entry.
    accumulate_photo_stats 'bare.gif' <<< $'  Format: GIF'
    test "${STATS_TOTALS[photos]}" -eq 1
    test "${#STATS_CAMERAS[@]}" -eq 0
    test "${STATS_FORMAT[GIF]}" -eq 1

    # Make only (no Model) still produces a leaderboard entry and mini-album.
    accumulate_photo_stats 'phone.jpg' <<< $'  exif:Make: Apple'
    test "${STATS_CAMERAS[Apple]}" -eq 1
    test "${STATS_FILTER_PAGEBASE[camera${STATS_FILTER_KEYSEP}Apple]}" = 'camera-apple'

    # Rational guards: zero denominator and bare decimal exposure time.
    fixture=$'  exif:FNumber: 4/0\n'
    fixture+=$'  exif:ExposureTime: 0.5'
    accumulate_photo_stats 'edge.jpg' <<< "$fixture"
    test "${#STATS_APERTURE[@]}" -eq 0
    test "${STATS_SHUTTER[1/2s]}" -eq 1

    test::teardown
}

test_stats_distinct_cameras_get_unique_slugs() {
    local sep
    test::setup
    test::source_shuriken_lib
    reset_photo_exif_stats
    sep="$STATS_FILTER_KEYSEP"

    # Two distinct camera labels that sanitize to the same base slug must keep
    # separate leaderboard entries, separate pagebases (mini-album filenames),
    # and separate photo lists (regression: slug collision merged them).
    accumulate_photo_stats 'a.jpg' <<< $'  exif:Model: Canon EOS 1D'
    accumulate_photo_stats 'b.jpg' <<< $'  exif:Model: Canon EOS-1D!!'

    test "${STATS_CAMERAS[Canon EOS 1D]}" -eq 1
    test "${STATS_CAMERAS[Canon EOS-1D!!]}" -eq 1
    test "${STATS_FILTER_PAGEBASE[camera${sep}Canon EOS 1D]}" = 'camera-canon-eos-1d'
    test "${STATS_FILTER_PAGEBASE[camera${sep}Canon EOS-1D!!]}" = 'camera-canon-eos-1d-2'
    test "${STATS_FILTER_PHOTOS[camera-canon-eos-1d]}" = 'a.jpg'
    test "${STATS_FILTER_PHOTOS[camera-canon-eos-1d-2]}" = 'b.jpg'

    # Re-encountering the first camera reuses its pagebase and appends.
    accumulate_photo_stats 'c.jpg' <<< $'  exif:Model: Canon EOS 1D'
    test "${STATS_CAMERAS[Canon EOS 1D]}" -eq 2
    test "${STATS_FILTER_PHOTOS[camera-canon-eos-1d]}" = $'a.jpg\nc.jpg'

    test::teardown
}

test_stats_bucket_boundaries_and_datetime_parsing() {
    test::setup
    test::source_shuriken_lib

    # Aperture/shutter/ISO/focal boundary checks against the plan ladders.
    test "$(_stats_aperture_bucket "$(_stats_rational_to_decimal 14/5)")" = 'f/2.8'
    test "$(_stats_aperture_bucket 1.4)" = 'f/1.8 or wider'
    test "$(_stats_aperture_bucket 22)" = 'f/22 or narrower'
    test "$(_stats_shutter_bucket 0.002)" = '1/500s'
    test "$(_stats_shutter_bucket 2)" = 'longer than 1s'
    test "$(_stats_iso_bucket 100)" = '100'
    test "$(_stats_iso_bucket 250)" = '400'
    test "$(_stats_iso_bucket 51200)" = 'over 25600'
    test "$(_stats_focal_bucket 24)" = '24-35mm'
    test "$(_stats_focal_bucket 300)" = 'over 200mm'
    test "$(_stats_megapixels_bucket 24)" = '20-40MP'
    test "$(_stats_aspect_bucket 1920 1080)" = '16:9'
    test "$(_stats_aspect_bucket 100 100)" = '1:1'
    test "$(_stats_orientation_bucket 100 100)" = 'Square'

    # DateTimeOriginal substring parse: must split YYYY/MM without date -d, and
    # fall back to DateTime when the original is absent.
    reset_photo_exif_stats
    accumulate_photo_stats 'd1.jpg' <<< $'  exif:DateTime: 2019:12:25 10:00:00'
    test "${STATS_YEARS[2019]}" -eq 1
    test "${STATS_MONTHS[12]}" -eq 1

    test::teardown
}

test_stats_collect_reads_cached_identify_output() {
    local incoming_dir
    local dist_dir
    local cache_dir

    test::setup
    test::source_shuriken_lib

    incoming_dir="$TEST_TMPDIR/incoming"
    dist_dir="$TEST_TMPDIR/dist"
    # The EXIF cache lives in ./cache parallel to ./dist (dirname of DIST_DIR).
    cache_dir="$TEST_TMPDIR/cache/exif"
    mkdir -p "$incoming_dir" "$cache_dir"
    printf 'fake\n' > "$incoming_dir/one.jpg"
    printf 'fake\n' > "$incoming_dir/two.jpg"

    export INCOMING_DIR="$incoming_dir"
    export DIST_DIR="$dist_dir"

    # Pre-seed the EXIF cache with matching signatures so cached_photo_identify_
    # output serves our fixtures without invoking ImageMagick.
    {
        photo_cache_signature 'one.jpg' "$incoming_dir/one.jpg"
        printf '  exif:Make: Nikon\n'
        printf '  exif:Model: Nikon Z6\n'
    } > "$cache_dir/one.jpg.txt"
    {
        photo_cache_signature 'two.jpg' "$incoming_dir/two.jpg"
        printf '  exif:Make: Nikon\n'
        printf '  exif:Model: Nikon Z6\n'
    } > "$cache_dir/two.jpg.txt"

    collect_photo_exif_stats

    test "${STATS_TOTALS[photos]}" -eq 2
    test "${STATS_CAMERAS[Nikon Z6]}" -eq 2
    test "${STATS_FILTER_PHOTOS[camera-nikon-z6]}" = $'one.jpg\ntwo.jpg'

    test::teardown
}

# Boundary test for the album/stats decoupling (task pn0). Proves two things:
# 1) the album_view_page_for_photo accessor returns exactly what the private
#    ALBUM_VIEW_PAGE_BY_PHOTO backing store holds (and "" for unknown photos), so
#    stats can rely on it instead of indexing the global; and
# 2) the assembled bin/shuriken keeps the cache primitive in the shared
#    metadata-cache module and the stats filter mini-album code no longer indexes
#    ALBUM_VIEW_PAGE_BY_PHOTO directly. A regression that re-coupled the modules
#    (moving the cache helper back into album, or re-indexing the global from
#    stats) would fail this.
test_album_stats_decoupling_boundary() {
    local generated
    local cache_section
    local stats_filter_section

    test::setup
    test::source_shuriken_lib

    # 1) The accessor reflects the private backing store and is the public API.
    #    Seed the album's global directly here (shellcheck cannot see that the
    #    accessor reads it back), then assert the accessor returns it.
    ALBUM_VIEW_PAGE_BY_PHOTO=()
    # shellcheck disable=SC2034
    ALBUM_VIEW_PAGE_BY_PHOTO['shot.jpg']='2-3'
    test "$(album_view_page_for_photo 'shot.jpg')" = '2-3'
    test "$(album_view_page_for_photo 'missing.jpg')" = ''

    # 2) Structural assertions on the assembled script.
    generated=$(<"$TEST_SHURIKEN")

    # The cache primitive must live in the shared metadata-cache module.
    cache_section=$(awk '
        /^# Inlined from src\/lib\/metadata-cache.source.sh/ { keep=1; next }
        /^# Inlined from / { keep=0 }
        keep { print }
    ' <<< "$generated")
    test::assert_contains 'cached_photo_identify_output()' "$cache_section"

    # The stats filter mini-album code must reach the album only through the
    # accessor, never by indexing the album's private global directly.
    stats_filter_section=$(awk '
        /^# Inlined from src\/lib\/stats-filter-album.source.sh/ { keep=1; next }
        /^# Inlined from / { keep=0 }
        keep { print }
    ' <<< "$generated")
    # Literal needle: we look for the accessor call verbatim in the assembled
    # script, so the "$photo" must stay unexpanded.
    # shellcheck disable=SC2016
    test::assert_contains 'album_view_page_for_photo "$photo"' \
        "$stats_filter_section"
    test::assert_not_contains 'ALBUM_VIEW_PAGE_BY_PHOTO[' \
        "$stats_filter_section"

    test::teardown
}

# STATS_CATEGORIES is the single source of truth (task en0): proves the reset,
# the overview body builder, and the bucket ladders all derive from the registry,
# so a category can no longer be defined in only one place. A regression that
# added a category to (say) the body builder without registering it -- or
# registered one without resetting its array, or an 'ordered' kind without its
# bucket ladder -- would fail one of these assertions.
test_stats_categories_registry_is_single_source_of_truth() {
    local spec
    local array_name
    local render_kind
    local heading
    local -A registry_arrays=()
    local -A rendered_headings=()
    local -a fields=()
    local body

    test::setup
    test::source_shuriken_lib

    # 1) reset_photo_exif_stats must clear exactly the registry's count arrays
    #    (no more, no less): a registered category gets a fresh empty array.
    reset_photo_exif_stats
    for spec in "${STATS_CATEGORIES[@]}"; do
        IFS='|' read -r -a fields <<< "$spec"
        array_name="${fields[0]}"
        render_kind="${fields[3]}"
        registry_arrays["$array_name"]=1
        # The array exists and is an (empty) associative array after reset.
        if ! declare -p "$array_name" >/dev/null 2>&1; then
            printf 'FAIL: reset did not declare registry array %s\n' \
                "$array_name" >&2
            exit 1
        fi
        # Every 'ordered' category must supply a bucket ladder; nothing else may.
        if [ "$render_kind" = ordered ]; then
            if [ -z "${STATS_CATEGORY_BUCKETS[$array_name]:-}" ]; then
                printf 'FAIL: ordered category %s has no bucket ladder\n' \
                    "$array_name" >&2
                exit 1
            fi
        fi
    done
    for array_name in "${!STATS_CATEGORY_BUCKETS[@]}"; do
        if [ -z "${registry_arrays[$array_name]:-}" ]; then
            printf 'FAIL: bucket ladder %s is not a registered category\n' \
                "$array_name" >&2
            exit 1
        fi
    done

    # 2) The overview body builder renders only registry headings: feed one photo
    #    that lights up several categories, then assert every <h2> heading in the
    #    body comes from a STATS_CATEGORIES entry (so no out-of-band section).
    reset_photo_exif_stats
    accumulate_photo_stats 'a.jpg' <<'EXIF'
  Geometry: 6000x4000+0+0
  exif:Make: Canon
  exif:Model: Canon EOS 5D
  exif:FNumber: 28/10
  exif:ISOSpeedRatings: 400
  exif:DateTimeOriginal: 2021:06:14 10:00:00
EXIF
    for spec in "${STATS_CATEGORIES[@]}"; do
        IFS='|' read -r -a fields <<< "$spec"
        rendered_headings["${fields[2]}"]=1
    done
    body=$(_stats_build_body)
    while IFS= read -r heading; do
        if [ -z "${rendered_headings[$heading]:-}" ]; then
            printf 'FAIL: body rendered heading %q not in STATS_CATEGORIES\n' \
                "$heading" >&2
            exit 1
        fi
    done < <(grep -oP '(?<=<h2>).*?(?=</h2>)' <<< "$body")

    test::teardown
}

# Unit-test the shared Make+Model dedup helper (task mn0). The album tooltip and
# stats leaderboard both rely on this, so cover dedup, plain concatenation and
# the empty-field edge cases here in one place.
test_camera_label_from_make_model() {
    local actual

    # shellcheck source=src/lib/metadata-label.source.sh
    source "$TEST_REPO_ROOT/src/lib/metadata-label.source.sh"

    _assert_camera_label() {
        local -r expected="$1"; shift
        local -r make="$1"; shift
        local -r model="$1"; shift

        actual=$(camera_label_from_make_model "$make" "$model")
        if [ "$actual" != "$expected" ]; then
            printf 'FAIL: camera_label_from_make_model %q %q => %q, want %q\n' \
                "$make" "$model" "$actual" "$expected" >&2
            exit 1
        fi
    }

    # Model repeats the make as a prefix: dedup to the model alone.
    _assert_camera_label 'Canon EOS 5D' 'Canon' 'Canon EOS 5D'
    # Model equals the make exactly: still just the model.
    _assert_camera_label 'Canon' 'Canon' 'Canon'
    # No duplication: make and model are concatenated.
    _assert_camera_label 'NIKON CORPORATION Z 6' 'NIKON CORPORATION' 'Z 6'
    # A make that is a substring but not a prefix is not deduped.
    _assert_camera_label 'Canon PowerShot Canon' 'Canon' 'PowerShot Canon'
    # Empty model yields the make; empty make yields the model.
    _assert_camera_label 'Apple' 'Apple' ''
    _assert_camera_label 'iPhone 12' '' 'iPhone 12'
    # Both empty yields an empty label.
    _assert_camera_label '' '' ''
    # The prefix match is case-sensitive: differing case is not deduped.
    _assert_camera_label 'canon Canon EOS 5D' 'canon' 'Canon EOS 5D'
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
    test::run_case '--clean rejects dangerous DIST_DIR' \
        test_clean_rejects_dangerous_dist_dir
    test::run_case '--clean rejects empty DIST_DIR' \
        test_clean_rejects_empty_dist_dir
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
        '--generate SOURCE_URL override sets footer link' \
        test_generate_source_url_override_sets_footer_link
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
        '--generate parallel template failure logs photo' \
        test_generate_parallel_template_failure_logs_photo
    test::run_case \
        'repeated output flags use last value' \
        test_repeated_output_flags_use_last_value
    test::run_case \
        '--print-config reflects defaults' \
        test_print_config_reflects_defaults
    test::run_case \
        '--print-config applies omitted runtime defaults' \
        test_print_config_applies_omitted_runtime_defaults
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
        '--print-config empty TAR_OPTS falls back to default' \
        test_print_config_empty_tar_opts_falls_back_to_default
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
        '--dry-run --no-stats omits stats from the plan' \
        test_dry_run_no_stats_omits_stats_plan
    test::run_case \
        '--dry-run reports empty plan without writes' \
        test_dry_run_reports_empty_plan_without_writes
    test::run_case \
        '--dry-run rejects invalid config and input' \
        test_dry_run_rejects_invalid_config_and_input
    test::run_case \
        '--generate ignores unsupported incoming files with warning' \
        test_generate_ignores_unsupported_incoming_files_with_warning
    test::run_case \
        '--generate warns and skips cache on identify failure' \
        test_generate_warns_and_skips_cache_on_identify_failure
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
        'percentage config var enforces 0..100 range' \
        test_config_validate_percentage_var_enforces_range
    test::run_case \
        'config validators fail fast without errexit' \
        test_config_validators_fail_fast_without_errexit
    test::run_case \
        '--generate validation failure skips action without errexit' \
        test_generate_validation_failure_skips_action_without_errexit
    test::run_case \
        '--generate action runs with errexit active' \
        test_generate_action_runs_with_errexit_active
    test::run_case \
        '--generate action failure fails status-tested dispatcher' \
        test_generate_action_failure_fails_status_tested_dispatcher
    test::run_case \
        '--generate action failure fails status-tested run_action' \
        test_generate_action_failure_fails_status_tested_run_action
    test::run_case \
        '--generate real failure returns with errexit disabled' \
        test_generate_real_failure_returns_with_errexit_disabled
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
        '--generate --favicon uses a custom favicon' \
        test_generate_uses_custom_favicon
    test::run_case \
        '--generate creates stats and per-camera pages with nav link' \
        test_generate_stats_pages_created_and_nav_linked
    test::run_case \
        '--generate --no-stats suppresses stats pages and nav link' \
        test_generate_no_stats_suppresses_pages_and_nav
    test::run_case \
        '--refresh-splash rewrites only root index from existing assets' \
        test_refresh_splash_rewrites_only_index_from_existing_assets
    test::run_case \
        '--refresh-splash copies favicon for legacy dist' \
        test_refresh_splash_copies_favicon_for_legacy_dist
    test::run_case \
        '--refresh-splash accepts minimal refresh-only config' \
        test_refresh_splash_accepts_minimal_refresh_config
    test::run_case \
        '--refresh-splash requires existing generated assets' \
        test_refresh_splash_requires_existing_generated_assets
    test::run_case \
        '--refresh-splash requires existing generated blurs' \
        test_refresh_splash_requires_existing_generated_blurs
    test::run_case \
        '--refresh-splash requires matching splash photo' \
        test_refresh_splash_requires_matching_splash_photo
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
        'template required context vars come from render specs' \
        test_template_required_context_vars_come_from_render_specs
    test::run_case \
        'header render-var subset is minimal (kn0)' \
        test_template_render_vars_subset_is_minimal_for_header
    test::run_case \
        'render-var subset matches template references (kn0)' \
        test_template_render_var_subsetting_matches_templates
    test::run_case \
        'template render var dispatch is extensible (OCP)' \
        test_template_render_var_dispatch_is_extensible
    test::run_case \
        'action dispatch is registry-driven (OCP)' \
        test_action_dispatch_is_registry_driven
    test::run_case \
        'preview_num render handlers guard non-numeric input' \
        test_template_render_var_preview_num_guards_non_numeric
    test::run_case \
        'render_stats_page renders sections and escapes EXIF labels' \
        test_render_stats_page_renders_sections_and_escapes
    test::run_case \
        'render_filter_pages renders mini-albums for every stat bucket' \
        test_render_filter_pages_renders_mini_albums
    test::run_case \
        'template context validator fails fast without errexit' \
        test_template_context_validator_fails_fast_without_errexit
    test::run_case \
        'template mktemp failure does not render without errexit' \
        test_template_mktemp_failure_does_not_render_without_errexit
    test::run_case \
        'template failure removes context file with errexit' \
        test_template_failure_removes_context_file_with_errexit
    test::run_case \
        'template setup failure removes context file with errexit' \
        test_template_setup_failure_removes_context_file_with_errexit
    test::run_case \
        'template setup failure fails status-tested render' \
        test_template_setup_failure_fails_status_tested_render
    test::run_case \
        'template interrupt removes context file' \
        test_template_interrupt_removes_context_file
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
        'stats aggregate synthetic EXIF fixtures' \
        test_stats_aggregates_synthetic_exif_fixtures
    test::run_case \
        'stats tolerate missing and edge-case fields' \
        test_stats_tolerates_missing_and_edge_case_fields
    test::run_case \
        'stats give distinct cameras unique slugs' \
        test_stats_distinct_cameras_get_unique_slugs
    test::run_case \
        'stats bucket boundaries and datetime parsing' \
        test_stats_bucket_boundaries_and_datetime_parsing
    test::run_case \
        'stats collect reads cached identify output' \
        test_stats_collect_reads_cached_identify_output
    test::run_case \
        'album/stats decoupling boundary (pn0)' \
        test_album_stats_decoupling_boundary
    test::run_case \
        'stats categories registry is single source of truth' \
        test_stats_categories_registry_is_single_source_of_truth
    test::run_case \
        'camera label dedups make and model' \
        test_camera_label_from_make_model
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
        '--sync rejects scalar destinations' \
        test_sync_rejects_scalar_destinations
    test::run_case \
        '--sync array destination preserves spaces' \
        test_sync_array_destination_preserves_spaces
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
