# shellcheck disable=SC2034
resolve_imagemagick_command() {
    local -r operation="$1"; shift
    local -n command_ref="$1"; shift

    command_ref=()

    case "$operation" in
        convert)
            if command -v magick >/dev/null 2>&1; then
                command_ref=(magick)
                return
            fi
            if command -v convert >/dev/null 2>&1; then
                command_ref=(convert)
                return
            fi
            ;;
        identify)
            if command -v magick >/dev/null 2>&1; then
                command_ref=(magick identify)
                return
            fi
            if command -v identify >/dev/null 2>&1; then
                command_ref=(identify)
                return
            fi
            if command -v convert >/dev/null 2>&1; then
                command_ref=(convert)
                return
            fi
            ;;
        *)
            printf 'ERROR: Unknown ImageMagick operation %s\n' \
                "$operation" >&2
            return 1
            ;;
    esac

    printf 'ERROR: ImageMagick is required; install magick or convert\n' >&2
    return 127
}

imagemagick() {
    local -a imagemagick_command=()

    resolve_imagemagick_command convert imagemagick_command || return

    run_with_timeout ImageMagick "$IMAGEMAGICK_TIMEOUT" \
        "${imagemagick_command[@]}" "$@"
}

imagemagick_identify() {
    local -a imagemagick_command=()

    resolve_imagemagick_command identify imagemagick_command || return

    if [ "${imagemagick_command[0]}" = convert ]; then
        if [[ "${1:-}" = '-verbose' && $# -eq 2 ]]; then
            run_with_timeout ImageMagick "$IMAGEMAGICK_TIMEOUT" \
                "${imagemagick_command[@]}" "$2" -verbose info:
        else
            run_with_timeout ImageMagick "$IMAGEMAGICK_TIMEOUT" \
                "${imagemagick_command[@]}" "$@" info:
        fi
        return
    fi

    run_with_timeout ImageMagick "$IMAGEMAGICK_TIMEOUT" \
        "${imagemagick_command[@]}" "$@"
}

run_with_timeout() {
    local -r description="$1"; shift
    local -r seconds="$1"; shift
    local -i status=0

    if ! command -v timeout >/dev/null 2>&1; then
        printf 'ERROR: timeout command is required to run %s\n' \
            "$description" >&2
        return 127
    fi

    if timeout "$seconds" "$@"; then
        return
    else
        status=$?
    fi

    if (( status == 124 )); then
        printf 'ERROR: %s timed out after %s seconds\n' \
            "$description" "$seconds" >&2
    fi

    return "$status"
}

tarball() {
    local -r tarball_name="$1"; shift
    local -r tarball_suffix="$TARBALL_SUFFIX"
    local base
    local old_tarball
    local -a tar_opts=()

    # Cleanup tarballs from previous runs for the configured suffix.
    while IFS= read -r -d '' old_tarball; do
        if [[ "$old_tarball" == *"$tarball_suffix" ]]; then
            rm -f "$old_tarball"
        fi
    done < <(find "$DIST_DIR" -maxdepth 1 -type f -print0)

    base=$(basename "$INCOMING_DIR")
    resolve_tar_opts tar_opts

    log_info "Creating tarball $(_display_path "$DIST_DIR/$tarball_name")" \
        "from $INCOMING_DIR"
    (
        cd "$(dirname "$INCOMING_DIR")"
        run_with_timeout tar "$TAR_TIMEOUT" \
            tar "${tar_opts[@]}" -f "$DIST_DIR/$tarball_name" "$base"
    )
}

resolve_tar_opts() {
    local -n options_ref="$1"; shift
    local tar_opts_decl

    options_ref=()

    if ! tar_opts_decl=$(declare -p TAR_OPTS 2>/dev/null); then
        options_ref=(-c)
        return
    fi

    case "$tar_opts_decl" in
        declare\ -a*\ TAR_OPTS=*)
            options_ref=("${TAR_OPTS[@]}")
            ;;
        *)
            if [ -n "${TAR_OPTS:-}" ]; then
                read -r -a options_ref <<< "$TAR_OPTS"
            fi
            ;;
    esac

    if (( ${#options_ref[@]} == 0 )); then
        options_ref=(-c)
    fi
}

resolve_sync_destinations() {
    local -n destinations_ref="$1"; shift
    local destinations_decl

    destinations_ref=()

    if ! destinations_decl=$(declare -p SYNC_DESTINATIONS 2>/dev/null); then
        return
    fi

    case "$destinations_decl" in
        declare\ -a*\ SYNC_DESTINATIONS=*)
            destinations_ref=("${SYNC_DESTINATIONS[@]}")
            ;;
        *)
            if [ -n "${SYNC_DESTINATIONS:-}" ]; then
                # shellcheck disable=SC2034
                read -r -a destinations_ref <<< "$SYNC_DESTINATIONS"
            fi
            ;;
    esac
}
