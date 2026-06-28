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

# Apply the documented defaults for every config field that has one. Driven
# entirely by CONFIG_SPECS (task mr0): each scalar entry with has_default=yes
# gets VAR="${VAR:-$default}" applied, so a field's default value lives in
# exactly one place (the registry) instead of being restated here. This is what
# eliminates the default-drift class of bug (TARBALL_INCLUDE once read 'no' here
# while the registry/default-conf said 'yes', fixed in 7r0): the default and the
# documented value can no longer disagree because they are the same datum.
#
# Notes:
#   - Empty defaults are intentional and applied verbatim (e.g. FAVICON='' means
#     "use the bundled default favicon"; HEIGHT/RANDOM_SEED/ORIGINAL_BASEPATH
#     default to the empty string).
#   - has_default=no scalars (TITLE, THUMBHEIGHT, MAXPREVIEWS, ...) are required
#     and deliberately get no default; validate_common_config rejects them when
#     unset.
#   - The two array fields (TAR_OPTS, SYNC_DESTINATIONS) cannot use the scalar
#     "${VAR:-...}" form, so they keep their `declare -p` guards below. They are
#     marked print_kind=array / has_default=no in the registry so this loop
#     skips them.
apply_config_defaults() {
    local spec
    local -a fields=()
    local name default has_default

    for spec in "${CONFIG_SPECS[@]}"; do
        config_spec_split "$spec" fields
        name="${fields[0]}"
        default="${fields[1]}"
        has_default="${fields[2]}"

        if [ "$has_default" = yes ]; then
            printf -v "$name" '%s' "${!name:-$default}"
        fi
    done

    if ! declare -p TAR_OPTS >/dev/null 2>&1; then
        TAR_OPTS=(-c)
    fi
    if ! declare -p SYNC_DESTINATIONS >/dev/null 2>&1; then
        SYNC_DESTINATIONS=()
    fi
}
