resolve_sync_destinations() {
    # destinations_ref is a nameref output filled by resolve_config_array.
    # shellcheck disable=SC2034
    local -n destinations_ref="$1"; shift
    local sync_decl

    # A list of rsync destinations is inherently a list, and the only
    # unambiguous spelling is a Bash array: SYNC_DESTINATIONS=( '/path/with
    # spaces/' ) preserves embedded spaces, whereas a scalar string would be
    # word-split (e.g. "/path/with spaces/" -> two broken destinations passed
    # to rsync). So we reject scalar declarations outright instead of silently
    # word-splitting them. (TAR_OPTS deliberately keeps scalar word-splitting:
    # turning "-c -v" into separate options is the desired behaviour there.)
    #
    # declare -p fails only when SYNC_DESTINATIONS was never set; that is a
    # legitimate "unset" case handled by the || true below, so we skip the
    # array-vs-scalar check entirely when the variable does not exist.
    if sync_decl=$(declare -p SYNC_DESTINATIONS 2>/dev/null); then
        case "$sync_decl" in
            declare\ -a*) ;;
            *)
                config_error \
                    'SYNC_DESTINATIONS must be an array, e.g. SYNC_DESTINATIONS=( '\''dest1'\'' '\''dest2'\'' )'
                return 1
                ;;
        esac
    fi

    # Parse SYNC_DESTINATIONS (always an array at this point) via the shared
    # config-array helper. Unlike TAR_OPTS there is no default: an unset or
    # empty value simply yields an empty destinations array for callers to
    # validate. The helper returns non-zero when SYNC_DESTINATIONS was never
    # declared; we ignore that (|| true) since the already-empty array is
    # exactly the desired result, and the bare non-zero return would otherwise
    # trip set -e.
    resolve_config_array SYNC_DESTINATIONS destinations_ref || true
}

sync_dist() {
    local destination
    local -a rsync_args=(-av)
    local -a sync_destinations=()
    local -a succeeded=()
    local -a failed=()
    local -i status=0

    resolve_sync_destinations sync_destinations

    if [ "$SYNC_DELETE" = yes ]; then
        rsync_args+=(--delete)
    fi

    # Mirror to every destination with per-destination isolation: a timeout or
    # rsync error on one mirror must NOT abort the others (under the top-level
    # "set -euo pipefail" a bare failing rsync would otherwise kill the loop and
    # silently skip the remaining destinations). We wrap each rsync in
    # run_with_timeout (SYNC_TIMEOUT) like every other external call, and use the
    # project's localized "set +e" idiom (see refresh_splash / bash-best-
    # practices) to capture each destination's status instead of aborting. The
    # "if ! run_with_timeout ...; then" form is avoided here because its non-zero
    # branch would still leave $? ambiguous for the summary; the explicit status
    # capture keeps the per-destination result unambiguous.
    for destination in "${sync_destinations[@]}"; do
        log_info "Syncing $DIST_DIR/ to $destination"
        set +e
        run_with_timeout "rsync to $destination" "$SYNC_TIMEOUT" \
            rsync "${rsync_args[@]}" "$DIST_DIR/" "$destination"
        status=$?
        set -e
        if (( status == 0 )); then
            succeeded+=("$destination")
        else
            # run_with_timeout already prints a timeout/error line; add a
            # per-destination notice so the operator sees which mirror failed.
            failed+=("$destination")
            log_warning "Sync to $destination failed (status $status)"
        fi
    done

    # Log a clear pass/fail summary and return non-zero if ANY destination
    # failed, while having ATTEMPTED all of them.
    if (( ${#succeeded[@]} > 0 )); then
        log_info "Sync succeeded for: ${succeeded[*]}"
    fi
    if (( ${#failed[@]} > 0 )); then
        log_warning "Sync failed for: ${failed[*]}"
        return 1
    fi
    return 0
}
