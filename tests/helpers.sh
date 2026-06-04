#!/usr/bin/env bash

: "${TEST_REPO_ROOT:=${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"
: "${TEST_PHOTOALBUM:=${PHOTOALBUM:-$TEST_REPO_ROOT/bin/photoalbum}}"
: "${TEST_IMAGEMAGICK:=magick}"
: "${TEST_TMPDIR:=}"

test::setup() {
    TEST_TMPDIR=$(mktemp -d)
}

test::teardown() {
    if [ -n "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
        TEST_TMPDIR=''
    fi
}

test::run_case() {
    local -r description="$1"; shift
    local output_file
    local -i status=0

    output_file=$(mktemp)
    set +e
    ( set -euo pipefail; trap test::teardown EXIT; "$@" ) \
        > "$output_file" 2>&1
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

test::assert_failure() {
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

test::capture_failure_output() {
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

test::assert_contains() {
    local -r needle="$1"; shift
    local -r haystack="$1"; shift

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: expected output to contain $needle" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

test::assert_not_contains() {
    local -r needle="$1"; shift
    local -r haystack="$1"; shift

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL: expected output not to contain $needle" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

test::assert_contains_before() {
    local -r first="$1"; shift
    local -r second="$1"; shift
    local -r haystack="$1"; shift
    local before_first

    before_first="${haystack%%"$first"*}"

    if [[ "$haystack" != *"$first"* \
        || "$haystack" != *"$second"* \
        || "$before_first" == *"$second"* ]]; then
        echo "FAIL: expected $first to appear before $second" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

test::assert_file_exists() {
    local -r path="$1"; shift

    if [ ! -f "$path" ]; then
        echo "FAIL: expected file $path to exist" >&2
        exit 1
    fi
}

test::assert_dir_exists() {
    local -r path="$1"; shift

    if [ ! -d "$path" ]; then
        echo "FAIL: expected directory $path to exist" >&2
        exit 1
    fi
}

test::assert_path_absent() {
    local -r path="$1"; shift

    if [ -e "$path" ]; then
        echo "FAIL: expected $path to be absent" >&2
        exit 1
    fi
}

test::assert_find_count() {
    local -r expected="$1"; shift
    local -r dir="$1"; shift
    local -r name="$1"; shift
    local actual

    actual=$(find "$dir" -maxdepth 1 -type f -name "$name" | wc -l)

    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: expected $expected files matching $name in $dir" >&2
        echo "found $actual" >&2
        exit 1
    fi
}

test::assert_no_staging_dirs() {
    local -r dir="$1"; shift
    local found

    found=$(find "$dir" -type d -name '.photoalbum.*' -print -quit)

    if [ -n "$found" ]; then
        echo "FAIL: expected no staging directories under $dir" >&2
        echo "found $found" >&2
        exit 1
    fi
}

test::run_photoalbum() {
    "$TEST_PHOTOALBUM" "$@" 2>&1
}

test::install_fake_imagemagick() {
    local -r bin_dir="$1"; shift

    mkdir -p "$bin_dir"
    TEST_IMAGEMAGICK="$bin_dir/magick"

    cat > "$bin_dir/magick" <<'MAGICK'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = identify ]; then
    if [ -n "${TEST_IMAGEMAGICK_IDENTIFY_OUTPUT:-}" ]; then
        printf '%s\n' "$TEST_IMAGEMAGICK_IDENTIFY_OUTPUT"
    fi
    exit 0
fi

dest="${@: -1}"
mkdir -p "$(dirname "$dest")"
{
    printf 'fake image\n'
    printf 'args:'
    printf ' %q' "$@"
    printf '\n'
} > "$dest"
MAGICK
    chmod 0755 "$bin_dir/magick"
    cp "$bin_dir/magick" "$bin_dir/convert"
}

test::install_failing_imagemagick() {
    local -r bin_dir="$1"; shift

    mkdir -p "$bin_dir"

    cat > "$bin_dir/magick" <<'MAGICK'
#!/usr/bin/env bash
set -euo pipefail

echo 'simulated ImageMagick failure' >&2
exit 42
MAGICK
    chmod 0755 "$bin_dir/magick"
    cp "$bin_dir/magick" "$bin_dir/convert"
}

test::install_failing_generation_tools() {
    local -r bin_dir="$1"; shift
    local name

    mkdir -p "$bin_dir"

    for name in magick convert tar; do
        cat > "$bin_dir/$name" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${TEST_FORBIDDEN_TOOL_LOG:-}" ]; then
    printf 'called %s\n' "$(basename "$0")" >> "$TEST_FORBIDDEN_TOOL_LOG"
fi
echo "unexpected generation tool invocation: $(basename "$0")" >&2
exit 97
TOOL
        chmod 0755 "$bin_dir/$name"
    done
}

test::install_mv_spy() {
    local -r bin_dir="$1"; shift
    local real_mv

    mkdir -p "$bin_dir"
    real_mv=$(command -v mv)

    cat > "$bin_dir/mv" <<MV
#!/usr/bin/env bash
set -euo pipefail

count=0
if [ -n "\${TEST_MV_COUNT_FILE:-}" ] && [ -f "\$TEST_MV_COUNT_FILE" ]; then
    count=\$(<"\$TEST_MV_COUNT_FILE")
fi
count=\$(( count + 1 ))
if [ -n "\${TEST_MV_COUNT_FILE:-}" ]; then
    printf '%s\n' "\$count" > "\$TEST_MV_COUNT_FILE"
fi

if [[ -n "\${TEST_FAIL_MV_ON:-}" && "\$count" = "\$TEST_FAIL_MV_ON" ]]; then
    echo 'simulated mv failure' >&2
    exit 42
fi

"$real_mv" "\$@"
MV
    chmod 0755 "$bin_dir/mv"
}

test::install_sort_spy() {
    local -r bin_dir="$1"; shift
    local real_sort

    mkdir -p "$bin_dir"
    real_sort=$(command -v sort)

    cat > "$bin_dir/sort" <<SORT
#!/usr/bin/env bash
set -euo pipefail

input_file=\$(mktemp)
cat > "\$input_file"

if [[ -n "\${TEST_SORT_LOG:-}" && " \$* " == *" -R "* ]] \\
    && grep -q '[.]jpg$' "\$input_file"; then
    printf 'photo-shuffle %s\n' "\$*" >> "\$TEST_SORT_LOG"
    tac "\$input_file"
    rm -f "\$input_file"
    exit 0
fi

"$real_sort" "\$@" "\$input_file"
rm -f "\$input_file"
SORT
    chmod 0755 "$bin_dir/sort"
}

test::install_tar_spy() {
    local -r bin_dir="$1"; shift
    local real_tar

    mkdir -p "$bin_dir"
    real_tar=$(command -v tar)

    cat > "$bin_dir/tar" <<TAR
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'argc=%s\n' "\$#"
    i=0
    for arg in "\$@"; do
        printf 'arg%s=%q\n' "\$i" "\$arg"
        i=\$(( i + 1 ))
    done
} >> "\$TEST_TAR_LOG"

"$real_tar" "\$@"
TAR
    chmod 0755 "$bin_dir/tar"
}

test::install_coreutils_without_imagemagick() {
    local -r bin_dir="$1"; shift
    local command_path
    local name
    local -a names=(
        basename
        bash
        date
        dirname
        find
        grep
        mkdir
        mktemp
        rm
        sed
        sort
        tac
        tar
        wc
    )

    mkdir -p "$bin_dir"

    for name in "${names[@]}"; do
        command_path=$(command -v "$name")
        ln -s "$command_path" "$bin_dir/$name"
    done
}

test::generate_fixture_images() {
    local -r incoming_dir="$1"; shift

    mkdir -p "$incoming_dir"
    "$TEST_IMAGEMAGICK" -size 160x90 xc:red \
        "$incoming_dir/01-landscape.jpg"
    "$TEST_IMAGEMAGICK" -size 90x160 xc:blue \
        "$incoming_dir/02-portrait.jpg"
    "$TEST_IMAGEMAGICK" -size 120x120 xc:green \
        "$incoming_dir/03-square.jpg"
    "$TEST_IMAGEMAGICK" -size 100x80 xc:yellow \
        "$incoming_dir/04 filename with spaces.jpg"
    "$TEST_IMAGEMAGICK" -size 140x90 xc:purple \
        "$incoming_dir/05-extra.jpg"
    "$TEST_IMAGEMAGICK" -size 150x90 xc:orange \
        "$incoming_dir/06-extra.jpg"
}

test::write_album_config() {
    local -r config_file="$1"; shift
    local -r incoming_dir="$1"; shift
    local -r dist_dir="$1"; shift
    local -r title="$1"; shift
    local -r maxpreviews="$1"; shift

    {
        printf 'TITLE=%q\n' "$title"
        printf 'THUMBHEIGHT=30\n'
        printf 'HEIGHT=120\n'
        printf 'MAXPREVIEWS=%q\n' "$maxpreviews"
        printf 'INCOMING_DIR=%q\n' "$incoming_dir"
        printf 'DIST_DIR=%q\n' "$dist_dir"
        printf 'TEMPLATE_DIR=%q/share/templates/default\n' "$TEST_REPO_ROOT"
        printf 'SPLASH_PAGE=yes\n'
        printf 'TARBALL_INCLUDE=no\n'
    } > "$config_file"
}
