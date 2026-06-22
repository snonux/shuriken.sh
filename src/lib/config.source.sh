existing_parent_dir() {
    local -r path="$1"; shift
    local existing_parent

    existing_parent=$(dirname "$path")

    while [ ! -e "$existing_parent" ]; do
        existing_parent=$(dirname "$existing_parent")
    done

    printf '%s\n' "$existing_parent"
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
    TARBALL_INCLUDE="${TARBALL_INCLUDE:-no}"
    TARBALL_SUFFIX="${TARBALL_SUFFIX:-.tar}"
    TAR_TIMEOUT="${TAR_TIMEOUT:-120}"
    if ! declare -p TAR_OPTS >/dev/null 2>&1; then
        TAR_OPTS=(-c)
    fi
    if ! declare -p SYNC_DESTINATIONS >/dev/null 2>&1; then
        SYNC_DESTINATIONS=()
    fi
}
