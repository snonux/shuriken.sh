existing_parent_dir() {
    local -r path="$1"; shift
    local existing_parent

    existing_parent=$(dirname "$path")

    while [ ! -e "$existing_parent" ]; do
        existing_parent=$(dirname "$existing_parent")
    done

    printf '%s\n' "$existing_parent"
}

# The generation "working" directory: the parent of DIST_DIR. Several DIST_DIR
# derived paths hang off this single parent -- the staging/backup sibling dirs
# (config.staging, action) and the volatile EXIF cache (metadata-cache) all live
# beside the final dist. Centralised here (task pr0), next to existing_parent_dir
# (the other DIST_DIR-parent resolver), so the plain `dirname "$DIST_DIR"` is
# computed in exactly one place instead of being recomputed at each call site.
# Plain dirname (NOT existing_parent_dir): callers that previously inlined
# `dirname "$DIST_DIR"` get a byte-identical result, including any trailing-slash
# or relative-vs-absolute behaviour dirname already produced. printf (no echo) so
# it stays safe under `set -euo pipefail`.
working_dir() {
    printf '%s\n' "$(dirname "$DIST_DIR")"
}

resolve_config_file() {
    local -r config_file="${1:-}"

    if [ -n "$config_file" ]; then
        printf '%s\n' "$config_file"
    else
        printf '%s\n' ./shuriken.conf
    fi
}

missing_config() {
    local -r config_file="$1"; shift

    printf 'Error: Can not find config file %s\n' "$config_file" >&2
    printf 'Run shuriken --init to create ./shuriken.conf.\n' >&2
    exit 1
}

apply_config_defaults() {
    # Empty FAVICON means use the bundled default favicon; otherwise it is a path
    # to a custom favicon file copied into the album as favicon.ico.
    FAVICON="${FAVICON:-}"
    HEIGHT="${HEIGHT:-}"
    IMAGE_JOBS="${IMAGE_JOBS:-3}"
    IMAGEMAGICK_TIMEOUT="${IMAGEMAGICK_TIMEOUT:-60}"
    ORIGINAL_BASEPATH="${ORIGINAL_BASEPATH:-}"
    RANDOM_SEED="${RANDOM_SEED:-}"
    SHUFFLE="${SHUFFLE:-no}"
    # SOURCE_URL is the project/source link shown in the page header bar ("Site
    # generated ... with <SOURCE_URL>"). Defaults to the shuriken.sh repo;
    # override it per site (e.g. to the album's own repo) via config or
    # --source-url. The header bar derives the displayed text from the URL itself.
    SOURCE_URL="${SOURCE_URL:-https://codeberg.org/snonux/shuriken.sh}"
    SPLASH_PAGE="${SPLASH_PAGE:-yes}"
    STATS_PAGE="${STATS_PAGE:-no}"
    # Optional with a default (unlike the required THUMBHEIGHT): the percent
    # chance a preview tile is subdivided into smaller thumbnails, and the
    # percent chance it becomes a large 2x2 "feature" tile. 0 disables either.
    THUMB_SUBDIVIDE_PERCENT="${THUMB_SUBDIVIDE_PERCENT:-30}"
    THUMB_FEATURE_PERCENT="${THUMB_FEATURE_PERCENT:-10}"
    SYNC_DELETE="${SYNC_DELETE:-yes}"
    # Per-destination rsync timeout (seconds), mirroring TAR_TIMEOUT/
    # IMAGEMAGICK_TIMEOUT. Each destination in sync_dist is wrapped in
    # run_with_timeout so a hung/unreachable mirror cannot block the whole sync.
    SYNC_TIMEOUT="${SYNC_TIMEOUT:-300}"
    # Default 'yes': a tarball of the incoming dir is included in the dist unless
    # disabled. This must match the documented default in shuriken.default.conf
    # (TARBALL_INCLUDE=yes) -- it previously drifted to 'no' here. 'yes' is the
    # original, authoritative default (tarball inclusion was on from the start).
    TARBALL_INCLUDE="${TARBALL_INCLUDE:-yes}"
    TARBALL_SUFFIX="${TARBALL_SUFFIX:-.tar}"
    TAR_TIMEOUT="${TAR_TIMEOUT:-120}"
    if ! declare -p TAR_OPTS >/dev/null 2>&1; then
        TAR_OPTS=(-c)
    fi
    if ! declare -p SYNC_DESTINATIONS >/dev/null 2>&1; then
        SYNC_DESTINATIONS=()
    fi
}
