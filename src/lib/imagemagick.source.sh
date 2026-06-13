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
