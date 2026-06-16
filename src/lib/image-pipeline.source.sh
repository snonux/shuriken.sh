create_photo_derivatives() {
    local -r photos_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r photo="$1"; shift
    local dirname
    local height

    if [[ -f "$DIST_DIR/$thumbs_dir/$photo" \
        && -f "$DIST_DIR/$blurs_dir/$photo" ]]; then
        log_verbose "Skipped existing thumb and blur" \
            "$(_display_path "$DIST_DIR/$thumbs_dir/$photo") and" \
            "$(_display_path "$DIST_DIR/$blurs_dir/$photo")"
        return
    fi

    dirname="$DIST_DIR/$thumbs_dir"
    mkdir -p "$dirname"
    log_info "Creating thumb $(_display_path "$DIST_DIR/$thumbs_dir/$photo")"
    # Double the height, as CSS scales images based on boxing too.
    height=$(( THUMBHEIGHT * 2 ))
    imagemagick \
        "$DIST_DIR/$photos_dir/$photo" \
        -geometry "x$height" \
        "$DIST_DIR/$thumbs_dir/$photo"

    dirname="$DIST_DIR/$blurs_dir"
    mkdir -p "$dirname"
    log_info "Creating blur $(_display_path "$DIST_DIR/$blurs_dir/$photo")"
    imagemagick \
        "$DIST_DIR/$thumbs_dir/$photo" \
        -flip \
        -blur 0x8 \
        "$DIST_DIR/$blurs_dir/$photo"
}

create_all_photo_derivatives() {
    local -r photos_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -i failed=0
    local -a image_job_pids=()
    # Passed by name to wait_for_image_job_slot and wait_for_image_jobs.
    # shellcheck disable=SC2034
    local -A image_job_labels=()
    # Passed by name to wait_for_image_job_slot and wait_for_image_jobs.
    # shellcheck disable=SC2034
    local -A image_job_statuses=()
    local photo

    while IFS= read -r photo; do
        wait_for_image_job_slot \
            image_job_pids \
            image_job_statuses \
            image_job_labels \
            failed
        create_photo_derivatives "$photos_dir" "$thumbs_dir" "$blurs_dir" \
            "$photo" &
        image_job_pids+=("$!")
        # Read through a nameref in the job-pool helpers.
        # shellcheck disable=SC2034
        image_job_labels["$!"]="image derivative job for photo $photo"
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )

    wait_for_image_jobs \
        image_job_pids \
        image_job_statuses \
        image_job_labels \
        failed
    if (( failed != 0 )); then
        return 1
    fi
}

prepare_generation_photo_assets() {
    warn_unsupported_incoming_files
    mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos
    create_all_photo_derivatives 'photos' 'thumbs' 'blurs'
}
