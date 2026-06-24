# Album EXIF presentation: turn a photo's parsed EXIF values into the per-photo
# details table and hover tooltip the album pages render. This module now holds
# ONLY the EXIF presentation concern -- the file counting, tarball naming,
# generation-metadata/JSON, dry-run and cache-lifecycle helpers that used to live
# here were split out into their own modules (task 6r0): counting -> image, tarball
# naming -> archive, generation metadata -> generation-metadata, dry-run -> dry-run,
# clear_exif_cache -> metadata-cache.
#
# The EXIF identify cache primitive (cached_photo_identify_output and its
# private helpers photo_cache_signature / print_cached_photo_identify_output)
# was promoted to the shared metadata-cache.source.sh module (task pn0): it is a
# low-level metadata primitive consumed by both this album module and the stats
# aggregator, so it no longer belongs to album internals. The helpers below call
# cached_photo_identify_output through that shared module.

photo_exif_details_html() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    # exif_values is filled via the shared parser and iterated below.
    # shellcheck disable=SC2034
    local -A exif_values=()
    local key
    local key_html
    local value
    local value_html
    local -i exif_count=0

    # Parse via the single canonical reader/parser (task 8r0) instead of a
    # private exif: regex loop. The parser also yields a synthetic __geometry key
    # from the native Geometry line; the details table only shows real exif: tags
    # (rendered with their historical "exif:" label prefix), so __geometry is
    # skipped explicitly below.
    _photo_exif_values_to exif_values "$photo" "$photo_path"

    for key in "${!exif_values[@]}"; do
        if [ "$key" = '__geometry' ]; then
            continue
        fi
        value="${exif_values[$key]}"
        key_html=$(html_escape "exif:$key")
        value_html=$(html_escape "$value")

        if (( exif_count == 0 )); then
            printf '<table class="details">\n'
            printf '<tbody>\n'
        fi

        printf '<tr><th>%s</th><td>%s</td></tr>\n' \
            "$key_html" \
            "$value_html"
        (( ++exif_count ))
    done

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

# Fill the caller's associative array with a photo's parsed EXIF values. Thin
# wrapper that pairs the shared cache reader with the shared stream parser
# (photo_exif_values_to, promoted to metadata-cache.source.sh in task 8r0): it
# reads the cached identify output for this photo and pipes it through the one
# canonical parser. The parser also captures a __geometry key, which album code
# simply ignores.
_photo_exif_values_to() {
    local -r target_array="$1"; shift
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift

    photo_exif_values_to "$target_array" \
        < <(cached_photo_identify_output "$photo" "$photo_path")
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
    # Dedup the manufacturer prefix via the shared helper (task mn0) so this
    # tooltip and the stats leaderboard derive identical camera labels.
    camera=$(camera_label_from_make_model "$make" "$model")

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
