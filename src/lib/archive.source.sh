# Tarball creation plus the naming helpers that decide what the archive file is
# called. The naming helpers (tarball_name_plan / generated_tarball_name) were
# moved here from album-metadata.source.sh (task 6r0): naming the archive is part
# of this module's tarball concern, alongside tarball() which writes it. The
# planned-name variant is consumed by the dry-run preview; the generated variant
# (with a real timestamp slug) is consumed by the album coordinator when it
# actually creates the archive. Behaviour and signatures are unchanged.

# Print the tarball name as it will appear in the dry-run plan: the incoming
# directory's basename, a literal "<timestamp>" placeholder, and the suffix.
tarball_name_plan() {
    local base

    base=$(basename "$INCOMING_DIR")
    printf '%s-<timestamp>%s\n' "$base" "$TARBALL_SUFFIX"
}

# Print the real tarball name used at generation time: the incoming directory's
# basename, the current timestamp slug, and the configured suffix.
generated_tarball_name() {
    local base
    local timestamp

    base=$(basename "$INCOMING_DIR")
    timestamp=$(current_timestamp_slug)
    printf '%s-%s%s\n' "$base" "$timestamp" "$TARBALL_SUFFIX"
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

    # Parse TAR_OPTS (array or scalar) via the shared config-array helper,
    # then fall back to a plain "-c" whenever no options were configured,
    # whether TAR_OPTS was unset or set to an empty value.
    # The helper returns non-zero when TAR_OPTS was never declared; we ignore
    # that here (|| true) because the empty-array fallback below covers the
    # unset case, and the bare non-zero return would otherwise trip set -e.
    resolve_config_array TAR_OPTS options_ref || true

    if (( ${#options_ref[@]} == 0 )); then
        # shellcheck disable=SC2034
        options_ref=(-c)
    fi
}
