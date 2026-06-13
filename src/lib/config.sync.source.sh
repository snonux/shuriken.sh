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
