wait_for_parallel_job_pid() {
    local -r pid="$1"; shift
    local -r job_statuses_name="$1"; shift
    local -n status_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n job_statuses_ref="$job_statuses_name"
    local -i wait_status=0

    if [ -n "${job_statuses_ref[$pid]+x}" ]; then
        # shellcheck disable=SC2034
        status_ref="${job_statuses_ref[$pid]}"
        unset "job_statuses_ref[$pid]"
        return
    fi

    set +e
    wait "$pid"
    wait_status=$?
    set -e

    # shellcheck disable=SC2034
    status_ref="$wait_status"
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

log_parallel_job_failure() {
    local -r pid="$1"; shift
    local -r status="$1"; shift
    local -r job_labels_name="$1"; shift
    # shellcheck disable=SC2178
    local -n job_labels_ref="$job_labels_name"
    local label

    label="${job_labels_ref[$pid]:-pid $pid}"
    printf 'ERROR: parallel job failed (%s): %s\n' "$status" "$label" >&2
}

finish_parallel_job() {
    local -r pid="$1"; shift
    local -r status="$1"; shift
    local -r job_labels_name="$1"; shift
    local -n failed_target_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n job_labels_ref="$job_labels_name"

    if (( status != 0 )); then
        # shellcheck disable=SC2034
        failed_target_ref=1
        log_parallel_job_failure "$pid" "$status" "$job_labels_name"
    fi

    unset "job_labels_ref[$pid]"
}

reap_finished_parallel_jobs() {
    local -r job_pids_name="$1"; shift
    local -r job_statuses_name="$1"; shift
    local -r job_labels_name="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"
    local -n failed_ref="$1"; shift
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

        wait_for_parallel_job_pid "$pid" "$job_statuses_name" status
        finish_parallel_job "$pid" "$status" "$job_labels_name" failed_ref
    done

    job_pids_ref=("${remaining_pids[@]}")
}

wait_for_next_parallel_job() {
    local -r job_pids_name="$1"; shift
    local -r job_statuses_name="$1"; shift
    local -r job_labels_name="$1"; shift
    local -r failed_name="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"
    # shellcheck disable=SC2178
    local -n job_statuses_ref="$job_statuses_name"
    local completed_pid=''
    local -i status=0

    set +e
    wait -n -p completed_pid "${job_pids_ref[@]}"
    status=$?
    set -e

    if [ -n "$completed_pid" ]; then
        job_statuses_ref["$completed_pid"]="$status"
    fi

    reap_finished_parallel_jobs \
        "$job_pids_name" \
        "$job_statuses_name" \
        "$job_labels_name" \
        "$failed_name"
}

wait_for_parallel_job_slot() {
    local -r job_pids_name="$1"; shift
    local -r job_statuses_name="$1"; shift
    local -r job_labels_name="$1"; shift
    local -r failed_name="$1"; shift
    local -r max_jobs="$1"; shift
    # shellcheck disable=SC2178
    local -n job_pids_ref="$job_pids_name"

    while (( ${#job_pids_ref[@]} >= max_jobs )); do
        wait_for_next_parallel_job \
            "$job_pids_name" \
            "$job_statuses_name" \
            "$job_labels_name" \
            "$failed_name"
    done
}

wait_for_parallel_jobs() {
    # shellcheck disable=SC2178
    local -n job_pids_ref="$1"; shift
    local -r job_statuses_name="$1"; shift
    local -r job_labels_name="$1"; shift
    local -n failed_ref="$1"; shift
    local -i status=0

    : "$failed_ref"
    while (( ${#job_pids_ref[@]} > 0 )); do
        wait_for_parallel_job_pid \
            "${job_pids_ref[0]}" \
            "$job_statuses_name" \
            status
        finish_parallel_job \
            "${job_pids_ref[0]}" \
            "$status" \
            "$job_labels_name" \
            failed_ref
        job_pids_ref=("${job_pids_ref[@]:1}")
    done
}

wait_for_image_job_slot() {
    local -r image_job_pids_name="$1"; shift
    local -r image_job_statuses_name="$1"; shift
    local -r image_job_labels_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_job_slot \
        "$image_job_pids_name" \
        "$image_job_statuses_name" \
        "$image_job_labels_name" \
        "$failed_name" \
        "$IMAGE_JOBS"
}

wait_for_image_jobs() {
    local -r image_job_pids_name="$1"; shift
    local -r image_job_statuses_name="$1"; shift
    local -r image_job_labels_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_jobs \
        "$image_job_pids_name" \
        "$image_job_statuses_name" \
        "$image_job_labels_name" \
        "$failed_name"
}

wait_for_template_render_job_slot() {
    local -r render_job_pids_name="$1"; shift
    local -r render_job_statuses_name="$1"; shift
    local -r render_job_labels_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_job_slot \
        "$render_job_pids_name" \
        "$render_job_statuses_name" \
        "$render_job_labels_name" \
        "$failed_name" \
        "$IMAGE_JOBS"
}

wait_for_template_render_jobs() {
    local -r render_job_pids_name="$1"; shift
    local -r render_job_statuses_name="$1"; shift
    local -r render_job_labels_name="$1"; shift
    local -r failed_name="$1"; shift

    wait_for_parallel_jobs \
        "$render_job_pids_name" \
        "$render_job_statuses_name" \
        "$render_job_labels_name" \
        "$failed_name"
}
