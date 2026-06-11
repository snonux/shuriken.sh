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

    cache_dir="$DIST_DIR/.photoalbum-cache/exif"
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

photo_exif_tooltip_text() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local aperture
    local camera
    local date_time
    local iso
    local key
    local line
    local make
    local model
    local separator=''
    local shutter_speed
    local -A exif_values=()
    local -a tooltip_parts=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$ ]]; then
            exif_values["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done < <(cached_photo_identify_output "$photo" "$photo_path")

    make="${exif_values[Make]:-}"
    model="${exif_values[Model]:-}"
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

    _first_exif_value_to aperture exif_values FNumber ApertureValue
    _first_exif_value_to iso exif_values \
        ISOSpeedRatings PhotographicSensitivity ISO
    _first_exif_value_to shutter_speed exif_values \
        ExposureTime ShutterSpeedValue
    _first_exif_value_to date_time exif_values \
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
    local photo

    while IFS= read -r photo; do
        wait_for_image_job_slot image_job_pids failed
        create_photo_derivatives "$photos_dir" "$thumbs_dir" "$blurs_dir" \
            "$photo" &
        image_job_pids+=("$!")
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )

    wait_for_image_jobs image_job_pids failed
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

        if (( page == max_page )); then
            template redirect "0-$MAXPREVIEWS.html" \
                html_dir "$html_dir" \
                redirect_page "${page}-$lastview"
            template redirect "$nextredirect.html" \
                html_dir "$html_dir" \
                redirect_page '1-1'
        else
            template redirect "$nextredirect.html" \
                html_dir "$html_dir" \
                redirect_page "$(( page + 1 ))-1"
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

    if [ "${SPLASH_PAGE:-yes}" = yes ]; then
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
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_job_slot render_job_pids_ref render_failed_ref
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
}

wait_for_album_view_render_jobs() {
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_jobs render_job_pids_ref render_failed_ref
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
            render_failed
        record_rendered_view_page rendered_view_pages rendered_last_views \
            "$num" "$i"
    done < <(album_photo_files "$photos_dir")

    finish_preview_page "$name" "$html_dir" "$backhref" "$tarball_name"
    if ! wait_for_album_view_render_jobs render_job_pids render_failed; then
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
    printf '%s-<timestamp>%s\n' "$base" "${TARBALL_SUFFIX:-.tar}"
}

generated_tarball_name() {
    local base
    local timestamp

    base=$(basename "$INCOMING_DIR")
    timestamp=$(current_timestamp_slug)
    printf '%s-%s%s\n' "$base" "$timestamp" "${TARBALL_SUFFIX:-.tar}"
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

write_generation_metadata() {
    local -r tarball_file="$1"; shift
    local -r generated_at=$(current_timestamp_iso)
    local -r config_source="${PHOTOALBUM_CONFIG_SOURCE:-}"
    local -r template_name=$(basename "$TEMPLATE_DIR")
    local -r source_image_count=$(count_incoming_images)
    local -r generated_photo_count=$(count_files "$DIST_DIR/photos")
    local -r generated_thumb_count=$(count_files "$DIST_DIR/thumbs")
    local -r generated_html_count=$(count_tree_files "$DIST_DIR" '*.html')

    {
        printf '{\n'
        printf '  "generator": {\n'
        printf '    "name": "photoalbum",\n'
        printf '    "version": %s\n' "$(_json_string "$VERSION")"
        printf '  },\n'
        printf '  "generated_at": %s,\n' "$(_json_string "$generated_at")"
        printf '  "config_source": %s,\n' "$(_json_string "$config_source")"
        printf '  "template": {\n'
        printf '    "name": %s,\n' "$(_json_string "$template_name")"
        printf '    "directory": %s\n' "$(_json_string "$TEMPLATE_DIR")"
        printf '  },\n'
        printf '  "source": {\n'
        printf '    "incoming_dir": %s,\n' "$(_json_string "$INCOMING_DIR")"
        printf '    "image_count": %s\n' "$source_image_count"
        printf '  },\n'
        printf '  "generated": {\n'
        printf '    "photo_count": %s,\n' "$generated_photo_count"
        printf '    "thumb_count": %s,\n' "$generated_thumb_count"
        printf '    "html_count": %s\n' "$generated_html_count"
        printf '  },\n'
        printf '  "tarball": {\n'
        printf '    "included": %s,\n' "$(_json_bool "${TARBALL_INCLUDE:-no}")"
        printf '    "file": %s\n' "$(_json_string "$tarball_file")"
        printf '  },\n'
        printf '  "settings": {\n'
        printf '    "title": %s,\n' "$(_json_string "${TITLE:-}")"
        printf '    "height": %s,\n' "$(_json_string "${HEIGHT:-}")"
        printf '    "thumbheight": %s,\n' "$(_json_string "${THUMBHEIGHT:-}")"
        printf '    "maxpreviews": %s,\n' "$(_json_string "${MAXPREVIEWS:-}")"
        printf '    "image_jobs": %s,\n' "$(_json_string "${IMAGE_JOBS:-}")"
        printf '    "random_seed": %s,\n' "$(_json_string "${RANDOM_SEED:-}")"
        printf '    "shuffle": %s,\n' "$(_json_bool "${SHUFFLE:-no}")"
        printf '    "splash_page": %s,\n' "$(_json_bool "${SPLASH_PAGE:-yes}")"
        printf '    "original_basepath": %s\n' \
            "$(_json_string "${ORIGINAL_BASEPATH:-}")"
        printf '  }\n'
        printf '}\n'
    } > "$DIST_DIR/photoalbum.json"
}

prepare_generation_photo_assets() {
    warn_unsupported_incoming_files
    mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos
    create_all_photo_derivatives 'photos' 'thumbs' 'blurs'
}

clear_rendered_html() {
    find "$DIST_DIR" -type f -name '*.html' -delete
}

create_generation_archive() {
    local -r tarball_name="$1"; shift

    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        tarball "$tarball_name"
    fi
}

generate() {
    local tarball_name=''

    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        tarball_name=$(generated_tarball_name)
        log_verbose \
            "Tarball enabled; planned archive:" \
            "$(_display_path "$DIST_DIR/$tarball_name")"
    else
        log_verbose 'Tarball disabled; no archive will be created'
    fi

    prepare_generation_photo_assets
    clear_rendered_html
    render_album_pages 'photos' '.' 'thumbs' 'blurs' '.' "$tarball_name"
    create_generation_archive "$tarball_name"
    write_generation_metadata "$tarball_name"
}

refresh_splash() {
    local tmp_html
    local tmp_path

    tmp_path=$(mktemp "$DIST_DIR/.index.html.XXXXXX")
    tmp_html=$(basename "$tmp_path")

    if render_album_splash_page 'photos' '.' 'blurs' '.' "$tmp_html"; then
        mv "$DIST_DIR/$tmp_html" "$DIST_DIR/index.html"
        log_info "Refreshed splash page $(_display_path "$DIST_DIR/index.html")"
        return
    fi

    rm -f "$DIST_DIR/$tmp_html"
    return 1
}

dry_run() {
    local -i image_count=0
    local -i html_index_count=1
    local -i page_count=0
    local -i redirect_count=0
    local -i details_count=0

    image_count=$(count_incoming_images)

    if (( image_count > 0 )); then
        details_count=$image_count
        page_count=$(( (image_count + MAXPREVIEWS - 1) / MAXPREVIEWS ))
        redirect_count=$(( page_count * 2 + 1 ))
    fi

    printf 'Dry run: no files will be written.\n'
    printf 'Config source: %s\n' "${PHOTOALBUM_CONFIG_SOURCE:-}"
    printf 'Incoming directory: %s\n' "$INCOMING_DIR"
    printf 'Output directory: %s\n' "$DIST_DIR"
    printf 'Template directory: %s\n' "$TEMPLATE_DIR"
    printf 'Title: %s\n' "$TITLE"
    printf 'Height: %s\n' "${HEIGHT:-}"
    printf 'Thumb height: %s\n' "$THUMBHEIGHT"
    printf 'Max previews per page: %s\n' "$MAXPREVIEWS"
    printf 'Image jobs: %s\n' "$IMAGE_JOBS"
    printf 'Random seed: %s\n' "${RANDOM_SEED:-}"
    printf 'Shuffle: %s\n' "${SHUFFLE:-no}"
    printf 'Splash page: %s\n' "${SPLASH_PAGE:-yes}"
    printf 'Image count: %s\n' "$image_count"
    printf 'Tarball setting: %s\n' "${TARBALL_INCLUDE:-no}"
    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        printf 'Tarball name plan: %s\n' "$(tarball_name_plan)"
    else
        printf 'Tarball name plan: not planned\n'
    fi

    printf 'Planned directories:\n'
    printf '  %s\n' "$DIST_DIR"
    printf '  %s/photos\n' "$DIST_DIR"
    printf '  %s/thumbs\n' "$DIST_DIR"
    printf '  %s/blurs\n' "$DIST_DIR"

    printf 'Planned generated files:\n'
    if [ "${SPLASH_PAGE:-yes}" = yes ]; then
        printf '  %s/index.html (%s splash page)\n' \
            "$DIST_DIR" "$html_index_count"
    else
        printf '  %s/index.html (%s album index redirect)\n' \
            "$DIST_DIR" "$html_index_count"
    fi
    printf '  %s/photoalbum.json\n' "$DIST_DIR"
    printf '  %s/photos/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/thumbs/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/blurs/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/page-*.html (%s preview pages)\n' "$DIST_DIR" "$page_count"
    printf '  %s/[page]-[image].html (%s view pages)\n' \
        "$DIST_DIR" "$image_count"
    printf '  %s/[page]-[image]-details.html (%s details pages)\n' \
        "$DIST_DIR" "$details_count"
    printf '  %s/[redirect].html (%s navigation redirects)\n' \
        "$DIST_DIR" "$redirect_count"
    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        printf '  %s/%s\n' "$DIST_DIR" "$(tarball_name_plan)"
    fi
}
