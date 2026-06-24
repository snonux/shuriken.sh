# Background-job pool, throttled to a fixed number of concurrent children.
#
# A "pool" is encapsulated behind a single handle: a name prefix string. The
# helpers derive the pool's four backing variables from that prefix on demand:
#
#   ${pool}_pids      indexed array  - pids of jobs still being tracked
#   ${pool}_statuses  assoc array    - pid -> exit status, for jobs already
#                                      reaped by `wait -n` but not yet finished
#   ${pool}_labels    assoc array    - pid -> human label, for failure messages
#   ${pool}_failed    integer        - 1 once any job has exited non-zero
#
# Encapsulating the four parallel arrays behind one prefix means callers declare
# and pass a single handle instead of four namerefs (each previously needing its
# own `shellcheck disable=SC2034`). Bash cannot nest indexed arrays inside an
# associative array, so a literal single-variable struct is impossible; a name
# prefix with `declare -g` backing variables is the simplest encoding that keeps
# all four pieces together under one name while staying pure-nameref (no eval).
#
# Public API:
#   job_pool_init <pool>              - create/reset the four backing variables
#   job_pool_submit <pool> <label> <cmd...>
#                                    - block until a slot is free (< IMAGE_JOBS
#                                      running), then background <cmd...> and
#                                      track it under <label>
#   job_pool_wait <pool>             - wait for all remaining jobs; return 1 if
#                                      any job (now or earlier) failed
#
# Throttling is fixed at IMAGE_JOBS (the configured max concurrent jobs); the
# previous per-call max_jobs parameterization was never varied, so it is gone.

# Create or reset a pool's backing variables. `declare -g` makes them globals so
# the derived namerefs in the helpers can see them regardless of the calling
# function's scope; re-running it clears any stale state from a prior pool of the
# same name (e.g. a re-generate).
job_pool_init() {
    local -r pool="$1"; shift

    declare -ga "${pool}_pids=()"
    declare -gA "${pool}_statuses=()"
    declare -gA "${pool}_labels=()"
    declare -gi "${pool}_failed=0"
}

# Reap a single finished pid: record its exit status. If `wait -n` already
# observed this pid (its status is cached in ${pool}_statuses), reuse that;
# otherwise `wait` on it directly. The status is returned through status_ref.
_job_pool_reap_pid() {
    local -r pool="$1"; shift
    local -r pid="$1"; shift
    local -n status_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n statuses_ref="${pool}_statuses"
    local -i wait_status=0

    if [ -n "${statuses_ref[$pid]+x}" ]; then
        # shellcheck disable=SC2034
        status_ref="${statuses_ref[$pid]}"
        unset "statuses_ref[$pid]"
        return
    fi

    set +e
    wait "$pid"
    wait_status=$?
    set -e

    # shellcheck disable=SC2034
    status_ref="$wait_status"
}

# True if pid is among the still-running pids passed as the remaining args.
_job_pool_pid_is_running() {
    local -r pid="$1"; shift
    local running_pid

    for running_pid in "$@"; do
        if [ "$running_pid" = "$pid" ]; then
            return 0
        fi
    done

    return 1
}

# Finalise one reaped pid: on non-zero status flip the pool's failed flag and
# log the job's label, then drop the label entry.
_job_pool_finish_pid() {
    local -r pool="$1"; shift
    local -r pid="$1"; shift
    local -r status="$1"; shift
    # shellcheck disable=SC2178
    local -n labels_ref="${pool}_labels"
    local -n failed_ref="${pool}_failed"
    local label

    if (( status != 0 )); then
        failed_ref=1
        label="${labels_ref[$pid]:-pid $pid}"
        printf 'ERROR: parallel job failed (%s): %s\n' "$status" "$label" >&2
    fi

    unset "labels_ref[$pid]"
}

# Sweep the pool's tracked pids: any that are no longer running get reaped and
# finished; still-running ones are kept for the next sweep.
_job_pool_reap_finished() {
    local -r pool="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="${pool}_pids"
    local -i status=0
    local -a remaining_pids=()
    local -a running_pids=()
    local pid

    mapfile -t running_pids < <(jobs -rp)

    for pid in "${pids_ref[@]}"; do
        if _job_pool_pid_is_running "$pid" "${running_pids[@]}"; then
            remaining_pids+=("$pid")
            continue
        fi

        _job_pool_reap_pid "$pool" "$pid" status
        _job_pool_finish_pid "$pool" "$pid" "$status"
    done

    pids_ref=("${remaining_pids[@]}")
}

# Block until at least one tracked job finishes, then reap every job that is now
# done. `wait -n` returns the first child to exit; its status is cached so the
# subsequent sweep can finish it with the rest.
_job_pool_wait_for_next() {
    local -r pool="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="${pool}_pids"
    # shellcheck disable=SC2178
    local -n statuses_ref="${pool}_statuses"
    local completed_pid=''
    local -i status=0

    set +e
    wait -n -p completed_pid "${pids_ref[@]}"
    status=$?
    set -e

    if [ -n "$completed_pid" ]; then
        statuses_ref["$completed_pid"]="$status"
    fi

    _job_pool_reap_finished "$pool"
}

# Block until the pool has a free slot (fewer than IMAGE_JOBS jobs tracked),
# reaping finished jobs while it waits. Throttles concurrency to IMAGE_JOBS.
_job_pool_wait_for_slot() {
    local -r pool="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="${pool}_pids"

    while (( ${#pids_ref[@]} >= IMAGE_JOBS )); do
        _job_pool_wait_for_next "$pool"
    done
}

# Wait for a free slot, then background <cmd...> and track it under <label> so a
# later failure can be reported against a meaningful name. The whole command
# (and its arguments) runs in the child; the caller is free to reuse its own
# variables for the next submission once this returns.
job_pool_submit() {
    local -r pool="$1"; shift
    local -r label="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="${pool}_pids"
    # shellcheck disable=SC2178
    local -n labels_ref="${pool}_labels"

    _job_pool_wait_for_slot "$pool"
    "$@" &
    pids_ref+=("$!")
    labels_ref["$!"]="$label"
}

# Wait for all remaining jobs to finish, finishing each in turn so a failed
# child flips the pool's failed flag. Returns 1 if any job in the pool's
# lifetime failed, 0 otherwise.
job_pool_wait() {
    local -r pool="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="${pool}_pids"
    local -n failed_ref="${pool}_failed"
    local -i status=0

    while (( ${#pids_ref[@]} > 0 )); do
        _job_pool_reap_pid "$pool" "${pids_ref[0]}" status
        _job_pool_finish_pid "$pool" "${pids_ref[0]}" "$status"
        pids_ref=("${pids_ref[@]:1}")
    done

    if (( failed_ref != 0 )); then
        return 1
    fi
}
