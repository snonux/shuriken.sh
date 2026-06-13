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
