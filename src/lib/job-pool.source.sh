wait_for_parallel_job_pid() {
    local -r pid="$1"; shift
    local -i status=0

    set +e
    wait "$pid"
    status=$?
    set -e

    return "$status"
}

parallel_job_pid_is_running() {
    local -r pid="$1"; shift
    local running_pid

    for running_pid in "$@"; do
        if [ "$running_pid" = "$pid" ]; then
            return 0
        fi
    done

    return 1
}

reap_finished_parallel_jobs() {
    local -r job_pids_name="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"
    local -n failed_ref="$1"; shift
    local -i reaped_status="$1"; shift
    local -i has_reaped_status=1
    local -i status=0
    local -a remaining_pids=()
    local -a running_pids=()
    local pid

    mapfile -t running_pids < <(jobs -rp)

    for pid in "${job_pids_ref[@]}"; do
        if parallel_job_pid_is_running "$pid" "${running_pids[@]}"; then
            remaining_pids+=("$pid")
            continue
        fi

        if wait_for_parallel_job_pid "$pid"; then
            status=0
        else
            status=$?
        fi
        if (( status == 127 && has_reaped_status != 0 )); then
            status=$reaped_status
            has_reaped_status=0
        fi

        if (( status != 0 )); then
            failed_ref=1
        fi
    done

    job_pids_ref=("${remaining_pids[@]}")
}

wait_for_next_parallel_job() {
    local -r job_pids_name="$1"; shift
    local -r failed_name="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"
    local -i status=0

    set +e
    wait -n "${job_pids_ref[@]}"
    status=$?
    set -e

    reap_finished_parallel_jobs "$job_pids_name" "$failed_name" "$status"
}

wait_for_parallel_job_slot() {
    local -r job_pids_name="$1"; shift
    local -r failed_name="$1"; shift
    local -r max_jobs="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"

    while (( ${#job_pids_ref[@]} >= max_jobs )); do
        wait_for_next_parallel_job "$job_pids_name" "$failed_name"
    done
}

wait_for_parallel_jobs() {
    # shellcheck disable=SC2178
    local -n job_pids_ref="$1"; shift
    local -n failed_ref="$1"; shift

    : "$failed_ref"
    while (( ${#job_pids_ref[@]} > 0 )); do
        if ! wait_for_parallel_job_pid "${job_pids_ref[0]}"; then
            failed_ref=1
        fi
        job_pids_ref=("${job_pids_ref[@]:1}")
    done
}

wait_for_image_job_slot() {
    local -r image_job_pids_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_job_slot \
        "$image_job_pids_name" \
        "$failed_name" \
        "$IMAGE_JOBS"
}

wait_for_image_jobs() {
    local -r image_job_pids_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_jobs "$image_job_pids_name" "$failed_name"
}

wait_for_template_render_job_slot() {
    local -r render_job_pids_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_job_slot \
        "$render_job_pids_name" \
        "$failed_name" \
        "$IMAGE_JOBS"
}

wait_for_template_render_jobs() {
    local -r render_job_pids_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_jobs "$render_job_pids_name" "$failed_name"
}
