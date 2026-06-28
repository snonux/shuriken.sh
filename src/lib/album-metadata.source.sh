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

# output_ref is a string nameref here. Other modules (e.g.
# metadata-cache.source.sh) reuse the name "output_ref" as an associative array,
# so --check-sourced cross-file nameref aliasing misreports each string write as
# an array assignment (SC2178). Both writes below are correct string nameref
# assignments, so SC2178 is suppressed at each one.
_first_exif_value_to() {
    # shellcheck disable=SC2178
    local -n output_ref="$1"; shift
    local -n exif_ref="$1"; shift
    local key

    # shellcheck disable=SC2178
    output_ref=''
    for key in "$@"; do
        if [ -n "${exif_ref[$key]:-}" ]; then
            # shellcheck disable=SC2034,SC2178
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

# Build the ordered "Label: value" tooltip parts from a parsed EXIF values map.
# Reads the values map by NAME (exif_name) and appends to the parts array passed
# by NAME (parts_name); only present fields are added, preserving the original
# Camera/Aperture/ISO/Shutter speed/Taken order. The nameref names are unique so
# they cannot collide with the caller's own variable names.
_collect_exif_tooltip_parts() {
    local -r exif_name="$1"; shift
    local -r parts_name="$1"; shift
    # shellcheck disable=SC2178
    local -n collect_parts_ref="$parts_name"
    local -n collect_values_ref="$exif_name"
    local aperture
    local camera
    local date_time
    local iso
    local make
    local model
    local shutter_speed

    make="${collect_values_ref[Make]:-}"
    model="${collect_values_ref[Model]:-}"
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
        collect_parts_ref+=("Camera: $camera")
    fi
    if [ -n "$aperture" ]; then
        collect_parts_ref+=("Aperture: $aperture")
    fi
    if [ -n "$iso" ]; then
        collect_parts_ref+=("ISO: $iso")
    fi
    if [ -n "$shutter_speed" ]; then
        collect_parts_ref+=("Shutter speed: $shutter_speed")
    fi
    if [ -n "$date_time" ]; then
        collect_parts_ref+=("Taken: $date_time")
    fi
}

# Print the collected tooltip parts joined by "; ", with a trailing newline only
# when at least one part exists (so an EXIF-less photo prints nothing). Reads the
# parts array by NAME.
_emit_exif_tooltip_parts() {
    local -r parts_name="$1"; shift
    local -n emit_parts_ref="$parts_name"
    local key
    local separator=''

    for key in "${emit_parts_ref[@]}"; do
        printf '%s%s' "$separator" "$key"
        separator='; '
    done
    if (( ${#emit_parts_ref[@]} > 0 )); then
        printf '\n'
    fi
}

# Thin orchestrator: collect the EXIF tooltip parts from a parsed values map,
# then emit them. Output is byte-identical to the previous single function.
_photo_exif_tooltip_text_from_values() {
    local -r exif_name="$1"; shift
    # Populated by _collect_exif_tooltip_parts via nameref; shellcheck cannot see
    # that cross-function write.
    # shellcheck disable=SC2034
    local -a tooltip_parts=()

    _collect_exif_tooltip_parts "$exif_name" tooltip_parts
    _emit_exif_tooltip_parts tooltip_parts
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
