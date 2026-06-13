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
