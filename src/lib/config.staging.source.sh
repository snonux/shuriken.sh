generation_staging_dir() {
    local -r final_dist="$1"; shift
    local final_base
    local staging_parent

    final_base=$(basename "$final_dist")
    staging_parent=$(existing_parent_dir "$final_dist")

    mktemp -d "$staging_parent/.shuriken.$final_base.staging.XXXXXX"
}

prepare_generation_staging_dir() {
    local -r final_dist="$1"; shift
    local -r staging_dir="$1"; shift
    local cache_dir

    if [ "$SHURIKEN_FORCE_GENERATE" = yes ]; then
        log_verbose 'Force generation enabled; not reusing existing output cache'
        return
    fi

    for cache_dir in photos thumbs blurs .shuriken-cache; do
        if [ -d "$final_dist/$cache_dir" ]; then
            if ! mkdir -p "$staging_dir/$cache_dir"; then
                return 1
            fi
            if ! cp -a "$final_dist/$cache_dir/." "$staging_dir/$cache_dir/"; then
                return 1
            fi
        fi
    done
}

cleanup_generation_staging_dir() {
    if [ -n "${SHURIKEN_ACTIVE_STAGING_DIR:-}" ]; then
        rm -rf "$SHURIKEN_ACTIVE_STAGING_DIR"
        SHURIKEN_ACTIVE_STAGING_DIR=''
    fi
}

terminate_process_tree() {
    local -r signal="$1"; shift
    local -r pid="$1"; shift
    local child

    if [ -z "$pid" ]; then
        return
    fi

    while IFS= read -r child; do
        if [ -n "$child" ]; then
            terminate_process_tree "$signal" "$child"
        fi
    done < <(pgrep -P "$pid" 2>/dev/null || true)

    kill "-$signal" "$pid" 2>/dev/null || true
}

wait_for_process_exit() {
    local -r pid="$1"; shift
    local -i attempts=0

    while kill -0 "$pid" 2>/dev/null; do
        if (( attempts >= 20 )); then
            return 1
        fi
        (( ++attempts ))
        sleep 0.05
    done
}

terminate_active_generation() {
    local -r pid="${SHURIKEN_ACTIVE_GENERATION_PID:-}"

    if [ -z "$pid" ]; then
        return
    fi

    terminate_process_tree TERM "$pid"
    if ! wait_for_process_exit "$pid"; then
        terminate_process_tree KILL "$pid"
    fi
    wait "$pid" 2>/dev/null || true
    SHURIKEN_ACTIVE_GENERATION_PID=''
}

handle_generation_staging_signal() {
    local -r status="$1"; shift

    clear_generation_staging_traps
    terminate_active_generation
    cleanup_generation_staging_dir
    exit "$status"
}

clear_generation_staging_traps() {
    trap - EXIT INT TERM HUP PIPE
}

ignore_generation_staging_interrupts() {
    trap '' INT TERM HUP PIPE
}

replace_dist_with_staging() {
    local -r staging_dir="$1"; shift
    local -r final_dist="$1"; shift
    local backup_dist=''
    local backup_parent=''
    local final_base
    local final_parent
    local staging_parent
    local -i status=0

    final_base=$(basename "$final_dist")
    final_parent=$(dirname "$final_dist")
    staging_parent=$(existing_parent_dir "$final_dist")

    if ! mkdir -p "$final_parent"; then
        return 1
    fi

    if [ -e "$final_dist" ]; then
        if ! backup_parent=$(
            mktemp -d "$staging_parent/.shuriken.$final_base.backup.XXXXXX"
        ); then
            return 1
        fi
        backup_dist="$backup_parent/dist"

        if ! mv "$final_dist" "$backup_dist"; then
            rm -rf "$backup_parent"
            return 1
        fi
    fi

    if mv "$staging_dir" "$final_dist"; then
        if [ -n "$backup_parent" ]; then
            rm -rf "$backup_parent"
        fi
        return 0
    else
        status=$?
    fi

    if [ -n "$backup_dist" ] && [ -e "$backup_dist" ]; then
        if [ -e "$final_dist" ] && ! rm -rf "$final_dist"; then
            printf 'ERROR: Failed to restore %s from %s\n' \
                "$final_dist" "$backup_dist" >&2
            return "$status"
        fi
        if ! mv "$backup_dist" "$final_dist"; then
            printf 'ERROR: Failed to restore %s from %s\n' \
                "$final_dist" "$backup_dist" >&2
            return "$status"
        fi
        rm -rf "$backup_parent"
    fi

    return "$status"
}

generate_staged() {
    local -r final_dist="$DIST_DIR"
    local staging_dir
    local -i status=0

    staging_dir=$(generation_staging_dir "$final_dist")
    log_verbose "Effective output directory: $final_dist"
    log_verbose "Generation staging directory: $staging_dir"
    SHURIKEN_ACTIVE_STAGING_DIR="$staging_dir"
    trap cleanup_generation_staging_dir EXIT
    trap 'handle_generation_staging_signal 130' INT
    trap 'handle_generation_staging_signal 143' TERM
    trap 'handle_generation_staging_signal 129' HUP
    trap 'handle_generation_staging_signal 141' PIPE

    if ! prepare_generation_staging_dir "$final_dist" "$staging_dir"; then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return 1
    fi

    set +e
    (
        set -e
        SHURIKEN_FINAL_DIST_DIR="$final_dist"
        export SHURIKEN_FINAL_DIST_DIR
        DIST_DIR="$staging_dir" generate
    ) &
    SHURIKEN_ACTIVE_GENERATION_PID=$!
    wait "$SHURIKEN_ACTIVE_GENERATION_PID"
    status=$?
    SHURIKEN_ACTIVE_GENERATION_PID=''
    set -e

    if (( status != 0 )); then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return "$status"
    fi

    ignore_generation_staging_interrupts
    set +e
    replace_dist_with_staging "$staging_dir" "$final_dist"
    status=$?
    set -e

    if (( status != 0 )); then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return "$status"
    fi

    SHURIKEN_ACTIVE_STAGING_DIR=''
    clear_generation_staging_traps
}
