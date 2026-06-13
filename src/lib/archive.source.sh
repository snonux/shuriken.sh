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
