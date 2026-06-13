cleanphotos() {
    local basename
    local photo
    local sub

    while IFS= read -r photo; do
        basename=$(basename "$photo")

        if [[ -f "$INCOMING_DIR/$basename" ]] \
            && is_supported_image_file "$basename"; then
            continue
        fi

        log_info "Cleaning up $(_display_path "$photo")"
        for sub in thumbs blurs photos; do
            if [ -f "$DIST_DIR/$sub/$basename" ]; then
                rm -f "$DIST_DIR/$sub/$basename"
                log_info "removed '$(_display_path "$DIST_DIR/$sub/$basename")'"
            fi
        done
    done < <(find "$DIST_DIR/photos" -maxdepth 1 -type f)
}

is_supported_image_file() {
    local -r file="$1"; shift
    local extension

    if [[ "$file" != *.* ]]; then
        return 1
    fi

    extension="${file##*.}"
    extension="${extension,,}"

    case "$extension" in
        gif|jpeg|jpg|png|webp)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

incoming_image_files() {
    local file

    while IFS= read -r file; do
        if is_supported_image_file "$file"; then
            printf '%s\n' "$file"
        fi
    done < <(find "$INCOMING_DIR" -maxdepth 1 -type f -printf '%f\n') \
        | sort
}

warn_unsupported_incoming_files() {
    local file

    while IFS= read -r file; do
        if ! is_supported_image_file "$file"; then
            log_warning "Ignoring unsupported incoming file: $file"
        fi
    done < <(find "$INCOMING_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
}

scalephotos() {
    local -i failed=0
    local -a image_job_pids=()
    local photo

    while IFS= read -r photo; do
        wait_for_image_job_slot image_job_pids failed
        scale_photo "$photo" &
        image_job_pids+=("$!")
    done < <(incoming_image_files)

    wait_for_image_jobs image_job_pids failed
    if (( failed != 0 )); then
        return 1
    fi
}

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

scale_photo() {
    local -r photo="$1"; shift
    local destphoto
    local dirname

    destphoto="$DIST_DIR/photos/$photo"
    dirname=$(dirname "$destphoto")
    mkdir -p "$dirname"

    if [ -f "$destphoto" ]; then
        log_verbose "Skipped existing photo $(_display_path "$destphoto")"
        return
    fi

    log_info "Processing $photo to $(_display_path "$destphoto")"
    if [ -n "$HEIGHT" ]; then
        # Scale down size.
        imagemagick \
            "$INCOMING_DIR/$photo" \
            -auto-orient \
            -geometry "x${HEIGHT}>" \
            "$destphoto"
    else
        # Keep original size.
        imagemagick \
            "$INCOMING_DIR/$photo" \
            -auto-orient \
            "$destphoto"
    fi
}

random_seed_is_set() {
    [ -n "$RANDOM_SEED" ]
}

deterministic_index() {
    local -r namespace="$1"; shift
    local -r count="$1"; shift
    local checksum

    checksum=$(printf '%s' "${RANDOM_SEED}:$namespace" | cksum)
    checksum=${checksum%% *}

    printf '%s\n' $(( checksum % count ))
}

random_index() {
    local -r namespace="$1"; shift
    local -r count="$1"; shift

    if random_seed_is_set; then
        deterministic_index "$namespace" "$count"
    else
        printf '%s\n' $(( RANDOM % count ))
    fi
}

random_animation_css_class() {
    local -r speed="$1"; shift
    local -r context="${1:-$speed}"
    local -i index
    local -a classes=(
        "animate-opacity-$speed"
        "animate-top-$speed"
        "animate-left-$speed"
        "animate-right-$speed"
        "animate-bottom-$speed"
        "animate-zoom-$speed"
        "animate-snap-rotate-$speed"
        "animate-hard-zoom-$speed"
        "animate-slam-left-$speed"
        "animate-slam-right-$speed"
        "animate-flash-in-$speed"
        "animate-invert-pop-$speed"
        "animate-posterize-pop-$speed"
        "animate-skew-snap-$speed"
        "animate-glitch-step-$speed"
    )

    index=$(random_index "animation:$speed:$context" "${#classes[@]}")
    printf '%s\n' "${classes[index]}"
}

deterministic_shuffle() {
    local checksum
    local line

    while IFS= read -r line; do
        checksum=$(printf '%s' "${RANDOM_SEED}:shuffle:$line" | cksum)
        checksum=${checksum%% *}
        printf '%010u\t%s\n' "$checksum" "$line"
    done | sort -n -k1,1 -k2,2 | cut -f2-
}

maybe_shuffle() {
    if [ "$SHUFFLE" = yes ]; then
        if random_seed_is_set; then
            deterministic_shuffle
        else
            sort -R
        fi
    else
        sort
    fi
}
