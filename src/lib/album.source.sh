album_photo_files() {
    local -r photos_dir="$1"; shift

    find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
        | maybe_shuffle
}

start_preview_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_name="$1"; shift
    local -r header_bar="$1"; shift
    local background_image

    background_image=$(randomphoto "$photos_dir" "$page_name")
    template header "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$blurs_dir" \
        background_image "$background_image" \
        show_header_bar "$header_bar"
}

finish_preview_page() {
    local -r page_name="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift

    template footer "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        tarball_name "$tarball_name"
}

finish_preview_page_with_next() {
    local -r page_name="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r next_page="$1"; shift
    local -r prev_page="$1"; shift

    template next "$page_name.html" \
        html_dir "$html_dir" \
        next "$next_page" \
        prev "$prev_page"
    finish_preview_page "$page_name" "$html_dir" "$backhref" "$tarball_name"
}

render_previous_page_link() {
    local -r page_name="$1"; shift
    local -r html_dir="$1"; shift
    local -r prev_page="$1"; shift

    template prev "$page_name.html" \
        html_dir "$html_dir" \
        prev "$prev_page"
}

render_preview_thumbnail() {
    local -r page_name="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local animation_class

    animation_class=$(random_animation_css_class slow "$photo_file")
    template preview "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        thumbs_dir "$thumbs_dir" \
        page_num "$page_num" \
        preview_num "$preview_num" \
        photo "$photo_file" \
        animation_class "$animation_class"
}

render_view_page() {
    local -r html_dir="$1"; shift
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local animation_class

    template header "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$blurs_dir" \
        background_image "$photo_file" \
        show_header_bar 'no'

    animation_class=$(random_animation_css_class fast "$photo_file")
    template view "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        photos_dir "$photos_dir" \
        page_num "$page_num" \
        preview_num "$preview_num" \
        photo "$photo_file" \
        animation_class "$animation_class"
    template footer "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        tarball_name "$tarball_name"
}

photo_cache_signature() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local stat_output

    stat_output=$(stat -c '%s:%Y' "$photo_path")
    printf '%s:%s\n' "$photo" "$stat_output"
}

print_cached_photo_identify_output() {
    local -r cache_file="$1"; shift
    local line
    local skipped_signature=no

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skipped_signature" = no ]; then
            skipped_signature=yes
            continue
        fi
        printf '%s\n' "$line"
    done < "$cache_file"
}

cached_photo_identify_output() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local cache_dir
    local cache_file
    local cached_signature=''
    local current_signature

    cache_dir="$DIST_DIR/.shuriken-cache/exif"
    cache_file="$cache_dir/$photo.txt"
    current_signature=$(photo_cache_signature "$photo" "$photo_path")

    if [ -f "$cache_file" ]; then
        IFS= read -r cached_signature < "$cache_file" || true
        if [ "$cached_signature" = "$current_signature" ]; then
            print_cached_photo_identify_output "$cache_file"
            return
        fi
    fi

    mkdir -p "$cache_dir"
    printf '%s\n' "$current_signature" > "$cache_file"
    imagemagick_identify -verbose "$photo_path" >> "$cache_file" 2>/dev/null \
        || true
    print_cached_photo_identify_output "$cache_file"
}

photo_exif_details_html() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local key
    local key_html
    local line
    local value
    local value_html
    local -i exif_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$ ]]; then
            key="exif:${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            key_html=$(_html_escape "$key")
            value_html=$(_html_escape "$value")

            if (( exif_count == 0 )); then
                printf '<table class="details">\n'
                printf '<tbody>\n'
            fi

            printf '<tr><th>%s</th><td>%s</td></tr>\n' \
                "$key_html" \
                "$value_html"
            (( ++exif_count ))
        fi
    done < <(cached_photo_identify_output "$photo" "$photo_path")

    if (( exif_count == 0 )); then
        printf '<p class="details-empty">No EXIF details available.</p>\n'
        return
    fi

    printf '</tbody>\n'
    printf '</table>\n'
}

_first_exif_value_to() {
    local -n output_ref="$1"; shift
    local -n exif_ref="$1"; shift
    local key

    output_ref=''
    for key in "$@"; do
        if [ -n "${exif_ref[$key]:-}" ]; then
            # shellcheck disable=SC2034
            output_ref="${exif_ref[$key]}"
            return
        fi
    done
}

_photo_exif_values_to() {
    local -n output_ref="$1"; shift
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local line

    output_ref=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$ ]]; then
            # output_ref writes to the caller-provided associative array.
            # shellcheck disable=SC2034
            output_ref["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done < <(cached_photo_identify_output "$photo" "$photo_path")
}

_photo_exif_tooltip_text_from_values() {
    local -r exif_name="$1"; shift
    local -n values_ref="$exif_name"
    local aperture
    local camera
    local date_time
    local iso
    local key
    local make
    local model
    local separator=''
    local shutter_speed
    local -a tooltip_parts=()

    make="${values_ref[Make]:-}"
    model="${values_ref[Model]:-}"
    camera="$make"
    if [ -n "$model" ]; then
        if [ -n "$make" ]; then
            case "$model" in
                "$make"|"$make "*)
                    camera="$model"
                    ;;
                *)
                    camera="$make $model"
                    ;;
            esac
        else
            camera="$model"
        fi
    fi

    _first_exif_value_to aperture "$exif_name" FNumber ApertureValue
    _first_exif_value_to iso "$exif_name" \
        ISOSpeedRatings PhotographicSensitivity ISO
    _first_exif_value_to shutter_speed "$exif_name" \
        ExposureTime ShutterSpeedValue
    _first_exif_value_to date_time "$exif_name" \
        DateTimeOriginal DateTimeDigitized DateTime

    if [ -n "$camera" ]; then
        tooltip_parts+=("Camera: $camera")
    fi
    if [ -n "$aperture" ]; then
        tooltip_parts+=("Aperture: $aperture")
    fi
    if [ -n "$iso" ]; then
        tooltip_parts+=("ISO: $iso")
    fi
    if [ -n "$shutter_speed" ]; then
        tooltip_parts+=("Shutter speed: $shutter_speed")
    fi
    if [ -n "$date_time" ]; then
        tooltip_parts+=("Taken: $date_time")
    fi

    for key in "${tooltip_parts[@]}"; do
        printf '%s%s' "$separator" "$key"
        separator='; '
    done
    if (( ${#tooltip_parts[@]} > 0 )); then
        printf '\n'
    fi
}

photo_exif_tooltip_text() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    # exif_values is populated and read through nameref helpers.
    # shellcheck disable=SC2034
    local -A exif_values=()

    _photo_exif_values_to exif_values "$photo" "$photo_path"
    _photo_exif_tooltip_text_from_values exif_values
}

render_details_page() {
    local -r html_dir="$1"; shift
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local animation_class
    local exif_details_html
    local exif_tooltip_text

    template header "$page_num-$preview_num-details.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$blurs_dir" \
        background_image "$photo_file" \
        show_header_bar 'no'

    animation_class=$(random_animation_css_class fast "$photo_file")
    exif_details_html=$(
        photo_exif_details_html "$photo_file" "$INCOMING_DIR/$photo_file"
    )
    exif_tooltip_text=$(
        photo_exif_tooltip_text "$photo_file" "$INCOMING_DIR/$photo_file"
    )
    template details "$page_num-$preview_num-details.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        photos_dir "$photos_dir" \
        page_num "$page_num" \
        preview_num "$preview_num" \
        photo "$photo_file" \
        animation_class "$animation_class" \
        exif_details "$exif_details_html" \
        exif_tooltip "$exif_tooltip_text"
    template footer "$page_num-$preview_num-details.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        tarball_name "$tarball_name"
}

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

render_album_page_thumbnail() {
    local -r page_name="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo="$1"; shift

    render_preview_thumbnail \
        "$page_name" \
        "$html_dir" \
        "$thumbs_dir" \
        "$backhref" \
        "$page_num" \
        "$preview_num" \
        "$photo"
}

render_photo_view_and_details() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo="$1"; shift

    render_view_page \
        "$html_dir" \
        "$photos_dir" \
        "$blurs_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_num" \
        "$preview_num" \
        "$photo"
    render_details_page \
        "$html_dir" \
        "$photos_dir" \
        "$blurs_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_num" \
        "$preview_num" \
        "$photo"
}

record_rendered_view_page() {
    # shellcheck disable=SC2178
    local -n view_pages_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n last_views_ref="$1"; shift
    local -r page="$1"; shift
    local -r preview="$1"; shift

    if [ -z "${last_views_ref[$page]+set}" ]; then
        view_pages_ref+=("$page")
    fi
    last_views_ref["$page"]="$preview"
}

render_view_redirects() {
    local -r html_dir="$1"; shift
    # shellcheck disable=SC2178
    local -n view_pages_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n last_views_ref="$1"; shift
    local lastview
    local max_page
    local nextredirect
    local page
    local prevredirect

    if (( ${#view_pages_ref[@]} == 0 )); then
        return
    fi

    max_page=${view_pages_ref[$(( ${#view_pages_ref[@]} - 1 ))]}

    for page in "${view_pages_ref[@]}"; do
        lastview=${last_views_ref[$page]}
        prevredirect="${page}-0"
        nextredirect="${page}-$(( lastview + 1 ))"

        template redirect "$prevredirect.html" \
            html_dir "$html_dir" \
            redirect_page "$(( page - 1 ))-${MAXPREVIEWS}"
        template redirect "$prevredirect-details.html" \
            html_dir "$html_dir" \
            redirect_page "$(( page - 1 ))-${MAXPREVIEWS}-details"

        if (( page == max_page )); then
            template redirect "0-$MAXPREVIEWS.html" \
                html_dir "$html_dir" \
                redirect_page "${page}-$lastview"
            template redirect "0-$MAXPREVIEWS-details.html" \
                html_dir "$html_dir" \
                redirect_page "${page}-$lastview-details"
            template redirect "$nextredirect.html" \
                html_dir "$html_dir" \
                redirect_page '1-1'
            template redirect "$nextredirect-details.html" \
                html_dir "$html_dir" \
                redirect_page '1-1-details'
        else
            template redirect "$nextredirect.html" \
                html_dir "$html_dir" \
                redirect_page "$(( page + 1 ))-1"
            template redirect "$nextredirect-details.html" \
                html_dir "$html_dir" \
                redirect_page "$(( page + 1 ))-1-details"
        fi
    done
}

render_album_index_redirect() {
    local -r html_dir="$1"; shift

    template 'redirect' 'index.html' \
        html_dir "$html_dir" \
        redirect_page 'page-1'
}

render_album_splash_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local html='index.html'
    local photo

    if (( $# > 0 )); then
        html="$1"
        shift
    fi

    photo=$(random_splash_photo "$photos_dir" "$blurs_dir")
    template 'splash' "$html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$blurs_dir" \
        background_image "$photo" \
        photos_dir "$photos_dir" \
        photo "$photo" \
        enter_page 'page-1'
}

render_album_index() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift

    if [ "$SPLASH_PAGE" = yes ]; then
        render_album_splash_page "$photos_dir" "$html_dir" "$blurs_dir" \
            "$backhref"
    else
        render_album_index_redirect "$html_dir"
    fi
}

album_page_name() {
    local -r page_num="$1"; shift

    printf 'page-%s\n' "$page_num"
}

advance_album_preview_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    # shellcheck disable=SC2178
    local -n page_name_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n prev_page_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n page_num_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n preview_num_ref="$1"; shift
    local next_page_name

    next_page_name=$(album_page_name "$(( page_num_ref + 1 ))")
    finish_preview_page_with_next \
        "$page_name_ref" \
        "$html_dir" \
        "$backhref" \
        "$tarball_name" \
        "$next_page_name" \
        "${prev_page_ref:-}"

    prev_page_ref="$page_name_ref"
    (( ++page_num_ref ))
    # shellcheck disable=SC2034
    preview_num_ref=1
    page_name_ref=$(album_page_name "$page_num_ref")

    start_preview_page \
        "$photos_dir" \
        "$html_dir" \
        "$blurs_dir" \
        "$backhref" \
        "$page_name_ref" \
        'no'
    render_previous_page_link "$page_name_ref" "$html_dir" "$prev_page_ref"
}

queue_album_view_render_job() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo="$1"; shift
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_statuses_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot and assigned below.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_labels_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_job_slot \
        render_job_pids_ref \
        render_job_statuses_ref \
        render_job_labels_ref \
        render_failed_ref
    render_photo_view_and_details \
        "$photos_dir" \
        "$blurs_dir" \
        "$html_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_num" \
        "$preview_num" \
        "$photo" &
    render_job_pids_ref+=("$!")
    render_job_labels_ref["$!"]="template render job for photo $photo"
}

wait_for_album_view_render_jobs() {
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # Passed by name to wait_for_template_render_jobs.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_statuses_ref="$1"; shift
    # Passed by name to wait_for_template_render_jobs.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_labels_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_jobs \
        render_job_pids_ref \
        render_job_statuses_ref \
        render_job_labels_ref \
        render_failed_ref
    if (( render_failed_ref != 0 )); then
        return 1
    fi
}

render_album_pages() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift

    local name
    local photo
    # Passed by name to advance_album_preview_page.
    # shellcheck disable=SC2034
    local prev
    local -i i=0
    local -i num=1
    # Passed by name to queue_album_view_render_job.
    # shellcheck disable=SC2034
    local -i render_failed=0
    # Passed by name to queue_album_view_render_job.
    # shellcheck disable=SC2034
    local -a render_job_pids=()
    # Passed by name to queue_album_view_render_job.
    # shellcheck disable=SC2034
    local -A render_job_labels=()
    # Passed by name to queue_album_view_render_job.
    # shellcheck disable=SC2034
    local -A render_job_statuses=()
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -A rendered_last_views=()
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -a rendered_view_pages=()

    name=$(album_page_name "$num")

    start_preview_page \
        "$photos_dir" "$html_dir" "$blurs_dir" "$backhref" "$name" 'yes'

    while IFS= read -r photo; do
        (( ++i ))

        if (( i > MAXPREVIEWS )); then
            advance_album_preview_page \
                "$photos_dir" \
                "$html_dir" \
                "$blurs_dir" \
                "$backhref" \
                "$tarball_name" \
                name \
                prev \
                num \
                i
        fi

        render_album_page_thumbnail \
            "$name" \
            "$html_dir" \
            "$thumbs_dir" \
            "$backhref" \
            "$num" \
            "$i" \
            "$photo"
        queue_album_view_render_job \
            "$photos_dir" \
            "$blurs_dir" \
            "$html_dir" \
            "$backhref" \
            "$tarball_name" \
            "$num" \
            "$i" \
            "$photo" \
            render_job_pids \
            render_job_statuses \
            render_job_labels \
            render_failed
        record_rendered_view_page rendered_view_pages rendered_last_views \
            "$num" "$i"
    done < <(album_photo_files "$photos_dir")

    finish_preview_page "$name" "$html_dir" "$backhref" "$tarball_name"
    if ! wait_for_album_view_render_jobs \
        render_job_pids \
        render_job_statuses \
        render_job_labels \
        render_failed; then
        return 1
    fi
    render_view_redirects "$html_dir" rendered_view_pages rendered_last_views
    render_album_index "$photos_dir" "$html_dir" "$blurs_dir" "$backhref"
}

splash_photo_files() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local photo

    while IFS= read -r photo; do
        if [ -f "$DIST_DIR/$blurs_dir/$photo" ]; then
            printf '%s\n' "$photo"
        fi
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )
}

random_splash_photo() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -i index
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(splash_photo_files "$photos_dir" "$blurs_dir")

    if (( ${#photos[@]} == 0 )); then
        printf 'ERROR: No splash photos found in %s with matching blurs in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" \
            "$(_display_path "$DIST_DIR/$blurs_dir")" >&2
        return 1
    fi

    index=$(random_index "photo:$photos_dir:splash" "${#photos[@]}")
    printf '%s\n' "${photos[index]}"
}

randomphoto() {
    local -r photos_dir="$1"; shift
    local -r context="${1:-$photos_dir}"
    local -i index
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )

    if (( ${#photos[@]} == 0 )); then
        printf 'ERROR: No photos found in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" >&2
        return 1
    fi

    index=$(random_index "photo:$photos_dir:$context" "${#photos[@]}")
    printf '%s\n' "${photos[index]}"
}

count_files() {
    local -r dir="$1"; shift
    local -r name="${1:-}"; shift || true

    if [ ! -d "$dir" ]; then
        printf '0\n'
        return
    fi

    if [ -n "$name" ]; then
        find "$dir" -maxdepth 1 -type f -name "$name" | wc -l
    else
        find "$dir" -maxdepth 1 -type f | wc -l
    fi
}

count_incoming_images() {
    incoming_image_files | wc -l
}

tarball_name_plan() {
    local base

    base=$(basename "$INCOMING_DIR")
    printf '%s-<timestamp>%s\n' "$base" "$TARBALL_SUFFIX"
}

generated_tarball_name() {
    local base
    local timestamp

    base=$(basename "$INCOMING_DIR")
    timestamp=$(current_timestamp_slug)
    printf '%s-%s%s\n' "$base" "$timestamp" "$TARBALL_SUFFIX"
}

count_tree_files() {
    local -r dir="$1"; shift
    local -r name="$1"; shift

    if [ ! -d "$dir" ]; then
        printf '0\n'
        return
    fi

    find "$dir" -type f -name "$name" | wc -l
}

_collect_generation_metadata() {
    local -r tarball_file="$1"; shift

    declare -gA _GENERATION_METADATA=()
    _GENERATION_METADATA["generator_name"]='shuriken'
    _GENERATION_METADATA["generator_version"]="$VERSION"
    _GENERATION_METADATA["generated_at"]=$(current_timestamp_iso)
    _GENERATION_METADATA["config_source"]="$SHURIKEN_CONFIG_SOURCE"
    _GENERATION_METADATA["template_name"]=$(basename "$TEMPLATE_DIR")
    _GENERATION_METADATA["template_directory"]="$TEMPLATE_DIR"
    _GENERATION_METADATA["source_incoming_dir"]="$INCOMING_DIR"
    _GENERATION_METADATA["source_image_count"]=$(count_incoming_images)
    _GENERATION_METADATA["generated_photo_count"]=$(count_files "$DIST_DIR/photos")
    _GENERATION_METADATA["generated_thumb_count"]=$(count_files "$DIST_DIR/thumbs")
    _GENERATION_METADATA["generated_html_count"]=$(
        count_tree_files "$DIST_DIR" '*.html'
    )
    _GENERATION_METADATA["tarball_included"]="$TARBALL_INCLUDE"
    _GENERATION_METADATA["tarball_file"]="$tarball_file"
    _GENERATION_METADATA["settings_title"]="$TITLE"
    _GENERATION_METADATA["settings_height"]="$HEIGHT"
    _GENERATION_METADATA["settings_thumbheight"]="$THUMBHEIGHT"
    _GENERATION_METADATA["settings_maxpreviews"]="$MAXPREVIEWS"
    _GENERATION_METADATA["settings_image_jobs"]="$IMAGE_JOBS"
    _GENERATION_METADATA["settings_random_seed"]="$RANDOM_SEED"
    _GENERATION_METADATA["settings_shuffle"]="$SHUFFLE"
    _GENERATION_METADATA["settings_splash_page"]="$SPLASH_PAGE"
    _GENERATION_METADATA["settings_stats_page"]="$STATS_PAGE"
    _GENERATION_METADATA["settings_original_basepath"]="$ORIGINAL_BASEPATH"
}

_generation_metadata_json() {
    printf '{\n'
    printf '  "generator": {\n'
    printf '    "name": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["generator_name"]}")"
    printf '    "version": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["generator_version"]}")"
    printf '  },\n'
    printf '  "generated_at": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["generated_at"]}")"
    printf '  "config_source": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["config_source"]}")"
    printf '  "template": {\n'
    printf '    "name": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["template_name"]}")"
    printf '    "directory": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["template_directory"]}")"
    printf '  },\n'
    printf '  "source": {\n'
    printf '    "incoming_dir": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["source_incoming_dir"]}")"
    printf '    "image_count": %s\n' \
        "${_GENERATION_METADATA["source_image_count"]}"
    printf '  },\n'
    printf '  "generated": {\n'
    printf '    "photo_count": %s,\n' \
        "${_GENERATION_METADATA["generated_photo_count"]}"
    printf '    "thumb_count": %s,\n' \
        "${_GENERATION_METADATA["generated_thumb_count"]}"
    printf '    "html_count": %s\n' \
        "${_GENERATION_METADATA["generated_html_count"]}"
    printf '  },\n'
    printf '  "tarball": {\n'
    printf '    "included": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["tarball_included"]}")"
    printf '    "file": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["tarball_file"]}")"
    printf '  },\n'
    printf '  "settings": {\n'
    printf '    "title": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_title"]}")"
    printf '    "height": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_height"]}")"
    printf '    "thumbheight": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_thumbheight"]}")"
    printf '    "maxpreviews": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_maxpreviews"]}")"
    printf '    "image_jobs": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_image_jobs"]}")"
    printf '    "random_seed": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_random_seed"]}")"
    printf '    "shuffle": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_shuffle"]}")"
    printf '    "splash_page": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_splash_page"]}")"
    printf '    "stats_page": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_stats_page"]}")"
    printf '    "original_basepath": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_original_basepath"]}")"
    printf '  }\n'
    printf '}\n'
}

write_generation_metadata() {
    local -r tarball_file="$1"; shift

    _collect_generation_metadata "$tarball_file"
    {
        _generation_metadata_json
    } > "$DIST_DIR/shuriken.json"
}

prepare_generation_photo_assets() {
    warn_unsupported_incoming_files
    mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos
    create_all_photo_derivatives 'photos' 'thumbs' 'blurs'
}

copy_site_favicon() {
    local asset_dir
    local favicon_src

    asset_dir=$(resolve_default_asset_dir)
    favicon_src="$asset_dir/favicon.ico"

    if [ ! -r "$favicon_src" ]; then
        config_error "favicon file $favicon_src must be readable"
        return 1
    fi

    log_verbose "Copying favicon to $(_display_path "$DIST_DIR/favicon.ico")"
    cp "$favicon_src" "$DIST_DIR/favicon.ico"
}

prepare_generation_site_assets() {
    copy_site_favicon
}

clear_rendered_html() {
    find "$DIST_DIR" -type f -name '*.html' -delete
}

create_generation_archive() {
    local -r tarball_name="$1"; shift

    if [ "$TARBALL_INCLUDE" = yes ]; then
        tarball "$tarball_name"
    fi
}

# Aggregate EXIF stats and render the stats page plus the per-camera pages into
# the dist root (html_dir and backhref are '.', matching render_album_pages).
# Run after the album pages so the per-photo identify cache is already warm.
generate_stats_pages() {
    log_verbose 'Stats page enabled; collecting EXIF stats'
    collect_photo_exif_stats
    render_stats_page . .
    render_camera_pages . .
}

generate() {
    local tarball_name=''

    if [ "$TARBALL_INCLUDE" = yes ]; then
        tarball_name=$(generated_tarball_name)
        log_verbose \
            "Tarball enabled; planned archive:" \
            "$(_display_path "$DIST_DIR/$tarball_name")"
    else
        log_verbose 'Tarball disabled; no archive will be created'
    fi

    prepare_generation_photo_assets
    prepare_generation_site_assets
    clear_rendered_html
    render_album_pages 'photos' '.' 'thumbs' 'blurs' '.' "$tarball_name"
    if [ "$STATS_PAGE" = yes ]; then
        generate_stats_pages
    fi
    create_generation_archive "$tarball_name"
    write_generation_metadata "$tarball_name"
}

refresh_splash() {
    local restore_errexit=no
    local -i status=0
    local tmp_html
    local tmp_path

    tmp_path=$(mktemp "$DIST_DIR/.index.html.XXXXXX")
    tmp_html=$(basename "$tmp_path")

    if [[ "$-" == *e* ]]; then
        restore_errexit=yes
        set +e
    fi
    (
        set -e
        render_album_splash_page 'photos' '.' 'blurs' '.' "$tmp_html"
    )
    status=$?
    if [ "$restore_errexit" = yes ]; then
        set -e
    fi
    if (( status != 0 )); then
        rm -f "$DIST_DIR/$tmp_html"
        return "$status"
    fi

    restore_errexit=no
    if [[ "$-" == *e* ]]; then
        restore_errexit=yes
        set +e
    fi
    (
        set -e
        prepare_generation_site_assets
    )
    status=$?
    if [ "$restore_errexit" = yes ]; then
        set -e
    fi
    if (( status != 0 )); then
        rm -f "$DIST_DIR/$tmp_html"
        return "$status"
    fi

    mv "$DIST_DIR/$tmp_html" "$DIST_DIR/index.html"
    log_info "Refreshed splash page $(_display_path "$DIST_DIR/index.html")"
}

dry_run() {
    # shellcheck disable=SC2034
    local -A dry_run_plan=()

    collect_dry_run_plan dry_run_plan
    print_dry_run_plan dry_run_plan
}

collect_dry_run_page_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"
    local -r image_count="$1"; shift
    local -i page_count=0
    local -i redirect_count=0

    plan_ref["html_index_count"]=1
    plan_ref["page_count"]=0
    plan_ref["redirect_count"]=0
    plan_ref["details_count"]=0

    if (( image_count > 0 )); then
        page_count=$(( (image_count + MAXPREVIEWS - 1) / MAXPREVIEWS ))
        redirect_count=$(( page_count * 4 + 2 ))
        plan_ref["details_count"]="$image_count"
        plan_ref["page_count"]="$page_count"
        plan_ref["redirect_count"]="$redirect_count"
    fi
}

collect_dry_run_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"
    local -i image_count=0

    image_count=$(count_incoming_images)
    plan_ref=()
    plan_ref["config_source"]="$SHURIKEN_CONFIG_SOURCE"
    plan_ref["incoming_dir"]="$INCOMING_DIR"
    plan_ref["dist_dir"]="$DIST_DIR"
    plan_ref["template_dir"]="$TEMPLATE_DIR"
    plan_ref["title"]="$TITLE"
    plan_ref["height"]="$HEIGHT"
    plan_ref["thumbheight"]="$THUMBHEIGHT"
    plan_ref["maxpreviews"]="$MAXPREVIEWS"
    plan_ref["image_jobs"]="$IMAGE_JOBS"
    plan_ref["random_seed"]="$RANDOM_SEED"
    plan_ref["shuffle"]="$SHUFFLE"
    plan_ref["splash_page"]="$SPLASH_PAGE"
    plan_ref["stats_page"]="$STATS_PAGE"
    plan_ref["image_count"]="$image_count"
    plan_ref["tarball_include"]="$TARBALL_INCLUDE"
    plan_ref["tarball_name_plan"]='not planned'

    if [ "$TARBALL_INCLUDE" = yes ]; then
        plan_ref["tarball_name_plan"]=$(tarball_name_plan)
    fi

    collect_dry_run_page_plan "$plan_name" "$image_count"
}

print_dry_run_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"

    printf 'Dry run: no files will be written.\n'
    printf 'Config source: %s\n' "${plan_ref["config_source"]}"
    printf 'Incoming directory: %s\n' "${plan_ref["incoming_dir"]}"
    printf 'Output directory: %s\n' "${plan_ref["dist_dir"]}"
    printf 'Template directory: %s\n' "${plan_ref["template_dir"]}"
    printf 'Title: %s\n' "${plan_ref["title"]}"
    printf 'Height: %s\n' "${plan_ref["height"]}"
    printf 'Thumb height: %s\n' "${plan_ref["thumbheight"]}"
    printf 'Max previews per page: %s\n' "${plan_ref["maxpreviews"]}"
    printf 'Image jobs: %s\n' "${plan_ref["image_jobs"]}"
    printf 'Random seed: %s\n' "${plan_ref["random_seed"]}"
    printf 'Shuffle: %s\n' "${plan_ref["shuffle"]}"
    printf 'Splash page: %s\n' "${plan_ref["splash_page"]}"
    printf 'Stats page: %s\n' "${plan_ref["stats_page"]}"
    printf 'Image count: %s\n' "${plan_ref["image_count"]}"
    printf 'Tarball setting: %s\n' "${plan_ref["tarball_include"]}"
    printf 'Tarball name plan: %s\n' "${plan_ref["tarball_name_plan"]}"

    printf 'Planned directories:\n'
    printf '  %s\n' "${plan_ref["dist_dir"]}"
    printf '  %s/photos\n' "${plan_ref["dist_dir"]}"
    printf '  %s/thumbs\n' "${plan_ref["dist_dir"]}"
    printf '  %s/blurs\n' "${plan_ref["dist_dir"]}"

    printf 'Planned generated files:\n'
    if [ "${plan_ref["splash_page"]}" = yes ]; then
        printf '  %s/index.html (%s splash page)\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["html_index_count"]}"
    else
        printf '  %s/index.html (%s album index redirect)\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["html_index_count"]}"
    fi
    printf '  %s/favicon.ico\n' "${plan_ref["dist_dir"]}"
    printf '  %s/shuriken.json\n' "${plan_ref["dist_dir"]}"
    printf '  %s/photos/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/thumbs/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/blurs/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/page-*.html (%s preview pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["page_count"]}"
    printf '  %s/[page]-[image].html (%s view pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/[page]-[image]-details.html (%s details pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["details_count"]}"
    printf '  %s/[redirect].html (%s navigation redirects)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["redirect_count"]}"
    if [ "${plan_ref["stats_page"]}" = yes ]; then
        # The exact camera-page count needs EXIF aggregation, which dry-run
        # does not perform, so list them as a wildcard.
        printf '  %s/stats.html (EXIF stats page)\n' "${plan_ref["dist_dir"]}"
        printf '  %s/camera-*.html (per-camera pages)\n' \
            "${plan_ref["dist_dir"]}"
    fi
    if [ "${plan_ref["tarball_include"]}" = yes ]; then
        printf '  %s/%s\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["tarball_name_plan"]}"
    fi
}
