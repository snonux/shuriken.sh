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

    # Persist the EXIF cache in a volatile ./cache directory parallel to ./dist
    # (the staging dir is a sibling of the final dist, so dirname "$DIST_DIR" is
    # the working dir in both staging and direct contexts). Keeping it outside
    # dist means it survives a fresh/cleared dist and is never deployed, so an
    # unchanged photo skips the slow `identify -verbose` on every regenerate.
    cache_dir="$(dirname "$DIST_DIR")/cache/exif"
    cache_file="$cache_dir/$photo.txt"
    current_signature=$(photo_cache_signature "$photo" "$photo_path")

    # Reuse the cache when its signature still matches the source file. --force
    # is handled once up front by clear_exif_cache (which empties this directory),
    # so the first call per photo then rebuilds it and the rest of the run reuses
    # it -- exactly one identify per photo even under force.
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

# Empty the volatile EXIF cache (./cache/exif, parallel to ./dist) so a --force
# run re-runs `identify` from scratch. Done once up front; the cache then
# repopulates and is reused for the rest of the run (one identify per photo).
clear_exif_cache() {
    local -r cache_dir="$(dirname "$DIST_DIR")/cache/exif"

    log_verbose "Force generation; clearing EXIF cache $cache_dir"
    rm -rf "$cache_dir"
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
        # The exact filter mini-album set needs EXIF aggregation, which dry-run
        # does not perform, so list them as a wildcard under stats/.
        printf '  %s/stats/index.html (EXIF stats page)\n' \
            "${plan_ref["dist_dir"]}"
        printf '  %s/stats/*/ (filter mini-albums)\n' \
            "${plan_ref["dist_dir"]}"
    fi
    if [ "${plan_ref["tarball_include"]}" = yes ]; then
        printf '  %s/%s\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["tarball_name_plan"]}"
    fi
}
