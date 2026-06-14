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

    # Parse TAR_OPTS (array or scalar) via the shared config-array helper,
    # then fall back to a plain "-c" whenever no options were configured,
    # whether TAR_OPTS was unset or set to an empty value.
    resolve_config_array TAR_OPTS options_ref

    if (( ${#options_ref[@]} == 0 )); then
        # shellcheck disable=SC2034
        options_ref=(-c)
    fi
}
