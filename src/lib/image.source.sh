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
        scale_photo "$photo" &
        image_job_pids+=("$!")
        # Read through a nameref in the job-pool helpers.
        # shellcheck disable=SC2034
        image_job_labels["$!"]="image job for photo $photo"
    done < <(incoming_image_files)

    wait_for_image_jobs \
        image_job_pids \
        image_job_statuses \
        image_job_labels \
        failed
    if (( failed != 0 )); then
        return 1
    fi
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
