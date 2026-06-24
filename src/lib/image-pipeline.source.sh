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
    local photo

    # Throttled background job pool (max IMAGE_JOBS concurrent), addressed by the
    # single handle "image_jobs". job_pool_wait returns 1 if any job failed.
    job_pool_init image_jobs

    while IFS= read -r photo; do
        job_pool_submit image_jobs "image derivative job for photo $photo" \
            create_photo_derivatives "$photos_dir" "$thumbs_dir" "$blurs_dir" \
            "$photo"
    done < <(list_photos "$photos_dir")

    job_pool_wait image_jobs
}

prepare_generation_photo_assets() {
    warn_unsupported_incoming_files
    mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos
    create_all_photo_derivatives 'photos' 'thumbs' 'blurs'
}
