resolve_sync_destinations() {
    # destinations_ref is a nameref output filled by resolve_config_array.
    # shellcheck disable=SC2034
    local -n destinations_ref="$1"; shift

    # Parse SYNC_DESTINATIONS (array or scalar) via the shared config-array
    # helper. Unlike TAR_OPTS there is no default: an unset or empty value
    # simply yields an empty destinations array for callers to validate.
    # The helper returns non-zero when SYNC_DESTINATIONS was never declared;
    # we ignore that (|| true) since the already-empty array is exactly the
    # desired result, and the bare non-zero return would otherwise trip set -e.
    resolve_config_array SYNC_DESTINATIONS destinations_ref || true
}

sync_dist() {
    local destination
    local -a rsync_args=(-av)
    local -a sync_destinations=()

    resolve_sync_destinations sync_destinations

    if [ "$SYNC_DELETE" = yes ]; then
        rsync_args+=(--delete)
    fi

    for destination in "${sync_destinations[@]}"; do
        log_info "Syncing $DIST_DIR/ to $destination"
        rsync "${rsync_args[@]}" "$DIST_DIR/" "$destination"
    done
}
