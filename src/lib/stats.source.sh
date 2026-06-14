# Stats aggregation for the album stats page (feature plan:
# /home/paul/.pi/plans/shuriken-stats-site.md, field audit:
# docs/stats-exif-audit.md). This module turns the per-photo
# `identify -verbose` output that album.source.sh already caches into
# aggregated, photographer-friendly counters.
#
# Scope: aggregation only. Rendering (stats.tmpl / camera.tmpl) lives in the
# sibling tasks pm0/rm0/um0; this module just fills the data structures they
# read.
#
# ----------------------------------------------------------------------------
# Public API / handoff contract
# ----------------------------------------------------------------------------
# collect_photo_exif_stats iterates the album's photos and fills these globals
# (all declared with `declare -gA` so the render tasks can read them after the
# call without namerefs):
#
#   STATS_CAMERAS[<camera label>]      = count          (camera leaderboard)
#   STATS_CAMERA_SLUGS[<camera label>] = slug            (camera-<slug>.html)
#   STATS_CAMERA_PHOTOS[<slug>]        = newline-separated photo filenames
#   STATS_LENSES[<lens model>]         = count           (sparse; may be empty)
#   STATS_YEARS[<YYYY>]                = count
#   STATS_MONTHS[<01..12>]             = count
#   STATS_APERTURE[<bucket>]           = count           (e.g. "f/2.8")
#   STATS_SHUTTER[<bucket>]            = count           (e.g. "1/250s")
#   STATS_ISO[<bucket>]                = count           (e.g. "400")
#   STATS_FOCAL[<bucket>]              = count           (e.g. "35-70mm")
#   STATS_MEGAPIXELS[<bucket>]         = count           (e.g. "10-20MP")
#   STATS_ASPECT[<bucket>]             = count           (e.g. "3:2")
#   STATS_ORIENTATION[<bucket>]        = count           (Landscape/Portrait/Square)
#   STATS_FORMAT[<bucket>]             = count           (JPEG/PNG/WEBP/GIF)
#   STATS_EXPOSURE_PROGRAM[<label>]    = count           (decoded enum)
#   STATS_METERING[<label>]            = count           (decoded enum)
#   STATS_WHITE_BALANCE[<label>]       = count           (Auto/Manual)
#   STATS_FLASH[<label>]               = count           (Fired/Did not fire; sparse)
#   STATS_TOTALS[photos]               = number of photos seen
#
# The render tasks should treat every per-category array as possibly empty
# (sparse data) and only render a section when it has entries. STATS_TOTALS
# gives the denominator for percentages.

# Reset every stats global to an empty associative array. Called at the start of
# collect_photo_exif_stats so repeated invocations (e.g. tests, --refresh) do
# not accumulate stale counts.
reset_photo_exif_stats() {
    declare -gA STATS_CAMERAS=()
    declare -gA STATS_CAMERA_SLUGS=()
    declare -gA STATS_CAMERA_PHOTOS=()
    declare -gA STATS_LENSES=()
    declare -gA STATS_YEARS=()
    declare -gA STATS_MONTHS=()
    declare -gA STATS_APERTURE=()
    declare -gA STATS_SHUTTER=()
    declare -gA STATS_ISO=()
    declare -gA STATS_FOCAL=()
    declare -gA STATS_MEGAPIXELS=()
    declare -gA STATS_ASPECT=()
    declare -gA STATS_ORIENTATION=()
    declare -gA STATS_FORMAT=()
    declare -gA STATS_EXPOSURE_PROGRAM=()
    declare -gA STATS_METERING=()
    declare -gA STATS_WHITE_BALANCE=()
    declare -gA STATS_FLASH=()
    declare -gA STATS_TOTALS=()
    STATS_TOTALS[photos]=0
    # Reverse map slug -> owning camera label, used to keep camera-<slug>.html
    # filenames unique when two distinct labels sanitize to the same slug.
    declare -gA STATS_SLUG_OWNERS=()
}

# Decode an EXIF rational ("num/den") to a decimal with `scale` digits.
# Guards den == 0 and tolerates plain decimals (some tools write "0.5"). Prints
# nothing for unparseable input so callers can skip it. The audit lists this as
# shared work for FNumber/FocalLength/ExposureTime.
_stats_rational_to_decimal() {
    local -r value="$1"; shift
    local -r scale="${1:-2}"

    if [[ "$value" =~ ^([0-9]+)/([0-9]+)$ ]]; then
        local -r num="${BASH_REMATCH[1]}"
        local -r den="${BASH_REMATCH[2]}"
        if (( den == 0 )); then
            return
        fi
        awk -v n="$num" -v d="$den" -v s="$scale" \
            'BEGIN { printf "%.*f", s, n / d }'
        return
    fi
    # Already a bare decimal/integer: echo it back so buckets can use it.
    if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$value"
    fi
}

# Bucket an f-number (decimal) to the nearest standard aperture stop, matching
# the boundaries in the plan (≤f/1.8 ... ≥f/22). The decimal is compared with
# awk so we avoid bash integer-only math on fractional stops.
_stats_aperture_bucket() {
    local -r fnum="$1"; shift

    awk -v f="$fnum" 'BEGIN {
        if (f <= 1.8) { print "f/1.8 or wider"; }
        else if (f <= 2.2) { print "f/2"; }
        else if (f <= 3.2) { print "f/2.8"; }
        else if (f <= 4.5) { print "f/4"; }
        else if (f <= 6.7) { print "f/5.6"; }
        else if (f <= 9.5) { print "f/8"; }
        else if (f <= 13) { print "f/11"; }
        else if (f <= 19) { print "f/16"; }
        else { print "f/22 or narrower"; }
    }'
}

# Bucket a shutter speed (already normalized to seconds) into the plan's ranges.
# Faster shutters are smaller numbers, so the ladder runs from short to long.
_stats_shutter_bucket() {
    local -r seconds="$1"; shift

    awk -v s="$seconds" 'BEGIN {
        if (s <= 1/4000) { print "1/4000s or faster"; }
        else if (s <= 1/2000) { print "1/2000s"; }
        else if (s <= 1/1000) { print "1/1000s"; }
        else if (s <= 1/500) { print "1/500s"; }
        else if (s <= 1/250) { print "1/250s"; }
        else if (s <= 1/125) { print "1/125s"; }
        else if (s <= 1/60) { print "1/60s"; }
        else if (s <= 1/30) { print "1/30s"; }
        else if (s <= 1/15) { print "1/15s"; }
        else if (s <= 1/8) { print "1/8s"; }
        else if (s <= 1/4) { print "1/4s"; }
        else if (s <= 1/2) { print "1/2s"; }
        else if (s <= 1) { print "1s"; }
        else { print "longer than 1s"; }
    }'
}

# Bucket an integer ISO to the next standard value at or above it. Plain integer
# per the audit; uses bash arithmetic since ISO is always an integer.
_stats_iso_bucket() {
    local -ri iso="$1"

    if (( iso <= 50 )); then printf '50'
    elif (( iso <= 100 )); then printf '100'
    elif (( iso <= 200 )); then printf '200'
    elif (( iso <= 400 )); then printf '400'
    elif (( iso <= 800 )); then printf '800'
    elif (( iso <= 1600 )); then printf '1600'
    elif (( iso <= 3200 )); then printf '3200'
    elif (( iso <= 6400 )); then printf '6400'
    elif (( iso <= 12800 )); then printf '12800'
    elif (( iso <= 25600 )); then printf '25600'
    else printf 'over 25600'
    fi
}

# Bucket a focal length (decimal mm) by the plan's lens ranges. Labelled as
# physical focal length, not 35mm-equivalent, per the audit.
_stats_focal_bucket() {
    local -r mm="$1"; shift

    awk -v m="$mm" 'BEGIN {
        if (m < 24) { print "under 24mm"; }
        else if (m < 35) { print "24-35mm"; }
        else if (m < 70) { print "35-70mm"; }
        else if (m < 135) { print "70-135mm"; }
        else if (m <= 200) { print "135-200mm"; }
        else { print "over 200mm"; }
    }'
}

# Bucket megapixels (W*H/1e6) by the plan's ranges.
_stats_megapixels_bucket() {
    local -r mp="$1"; shift

    awk -v p="$mp" 'BEGIN {
        if (p < 2) { print "under 2MP"; }
        else if (p < 5) { print "2-5MP"; }
        else if (p < 10) { print "5-10MP"; }
        else if (p < 20) { print "10-20MP"; }
        else if (p < 40) { print "20-40MP"; }
        else if (p <= 80) { print "40-80MP"; }
        else { print "over 80MP"; }
    }'
}

# Reduce W:H by GCD and match common photographic aspect ratios. The audit
# recommends deriving this from Geometry rather than EXIF.
_stats_aspect_bucket() {
    local -ri width="$1"; shift
    local -ri height="$1"; shift
    local -i a="$width"
    local -i b="$height"
    local -i t

    if (( width <= 0 || height <= 0 )); then
        return
    fi
    while (( b != 0 )); do
        t=$b
        b=$(( a % b ))
        a=$t
    done
    case "$(( width / a )):$(( height / a ))" in
        3:2|2:3) printf '3:2' ;;
        4:3|3:4) printf '4:3' ;;
        16:9|9:16) printf '16:9' ;;
        1:1) printf '1:1' ;;
        5:4|4:5) printf '5:4' ;;
        *) printf 'other' ;;
    esac
}

# Orientation from width vs height. The audit prefers this over the native
# Orientation rotation flag, which is frequently absent or already baked in.
_stats_orientation_bucket() {
    local -ri width="$1"; shift
    local -ri height="$1"; shift

    if (( width > height )); then printf 'Landscape'
    elif (( height > width )); then printf 'Portrait'
    else printf 'Square'
    fi
}

# Decode the ExposureProgram enum (0-8) to a friendly label. ImageMagick emits
# the bare integer; the audit supplies this map.
_stats_exposure_program_label() {
    case "$1" in
        1) printf 'Manual' ;;
        2) printf 'Program AE' ;;
        3) printf 'Aperture priority' ;;
        4) printf 'Shutter priority' ;;
        5) printf 'Creative' ;;
        6) printf 'Action' ;;
        7) printf 'Portrait' ;;
        8) printf 'Landscape' ;;
        *) printf 'Not defined' ;;
    esac
}

# Decode the MeteringMode enum to a friendly label per the audit's map.
_stats_metering_label() {
    case "$1" in
        1) printf 'Average' ;;
        2) printf 'Center-weighted' ;;
        3) printf 'Spot' ;;
        4) printf 'Multi-spot' ;;
        5) printf 'Multi-segment' ;;
        6) printf 'Partial' ;;
        255) printf 'Other' ;;
        *) printf 'Unknown' ;;
    esac
}

# Standard EXIF WhiteBalance is only a 2-value enum (0 Auto, 1 Manual); the
# richer presets live in MakerNotes and are not exposed by identify (audit).
_stats_white_balance_label() {
    case "$1" in
        0) printf 'Auto' ;;
        1) printf 'Manual' ;;
        *) return ;;
    esac
}

# Decode the EXIF Flash bitmask: bit 0 indicates the flash fired. The audit
# warns this tag is frequently missing, so callers must tolerate absence.
_stats_flash_label() {
    local -ri flash="$1"

    if (( flash & 1 )); then printf 'Flash fired'
    else printf 'No flash'
    fi
}

# Build a filename-safe slug for camera-<slug>.html. Lowercase, non-alphanumeric
# runs collapsed to a single dash, leading/trailing dashes trimmed.
_stats_slug() {
    local slug="${1,,}"

    slug="${slug//[^a-z0-9]/-}"
    while [[ "$slug" == *--* ]]; do
        slug="${slug//--/-}"
    done
    slug="${slug#-}"
    slug="${slug%-}"
    printf '%s' "$slug"
}

# Join Make + Model into a single camera label, reusing the same dedup logic as
# album.source.sh's tooltip builder (handles "Model already includes Make").
_stats_camera_label() {
    local -r make="$1"; shift
    local -r model="$1"; shift

    if [ -z "$model" ]; then
        printf '%s' "$make"
        return
    fi
    if [ -z "$make" ]; then
        printf '%s' "$model"
        return
    fi
    case "$model" in
        "$make"|"$make "*) printf '%s' "$model" ;;
        *) printf '%s %s' "$make" "$model" ;;
    esac
}

# Resolve a unique camera-page slug for a label into the named output variable.
# A label keeps the slug it was first assigned (idempotent on re-encounter).
# Distinct labels whose sanitized slug collides (e.g. two models differing only
# in punctuation, or an all-symbol label that slugs to empty) get a numeric
# suffix so each camera maps to its own camera-<slug>.html and its own
# STATS_CAMERA_PHOTOS list. Uses a nameref output (not command substitution) so
# its mutation of STATS_SLUG_OWNERS persists in the caller's shell.
_stats_resolve_camera_slug() {
    local -n slug_out_ref="$1"; shift
    local -r label="$1"; shift
    local base
    local -i suffix=2

    if [ -n "${STATS_CAMERA_SLUGS["$label"]:-}" ]; then
        slug_out_ref="${STATS_CAMERA_SLUGS["$label"]}"
        return
    fi
    base=$(_stats_slug "$label")
    if [ -z "$base" ]; then
        base=camera
    fi
    slug_out_ref="$base"
    while [ -n "${STATS_SLUG_OWNERS["$slug_out_ref"]:-}" ] \
        && [ "${STATS_SLUG_OWNERS["$slug_out_ref"]}" != "$label" ]; do
        slug_out_ref="${base}-${suffix}"
        (( ++suffix ))
    done
    STATS_SLUG_OWNERS["$slug_out_ref"]="$label"
}

# Increment STATS_CAMERAS for a photo and record it on the per-camera list so
# um0 can render camera-<slug>.html. Skips photos with no Make/Model at all.
_stats_record_camera() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local label
    local slug

    label=$(_stats_camera_label "${values_ref[Make]:-}" "${values_ref[Model]:-}")
    if [ -z "$label" ]; then
        return
    fi
    _stats_resolve_camera_slug slug "$label"
    STATS_CAMERAS["$label"]=$(( ${STATS_CAMERAS["$label"]:-0} + 1 ))
    STATS_CAMERA_SLUGS["$label"]="$slug"
    if [ -n "${STATS_CAMERA_PHOTOS["$slug"]:-}" ]; then
        STATS_CAMERA_PHOTOS["$slug"]+=$'\n'"$photo"
    else
        STATS_CAMERA_PHOTOS["$slug"]="$photo"
    fi
    if [ -n "${values_ref[LensModel]:-}" ]; then
        STATS_LENSES["${values_ref[LensModel]}"]=$((
            ${STATS_LENSES["${values_ref[LensModel]}"]:-0} + 1 ))
    fi
}

# Record year and month counters from DateTimeOriginal ("YYYY:MM:DD HH:MM:SS").
# Parsed by substring per the audit: the colons in the date part are not
# standard, so this must not be fed to `date -d`. Falls back to the digitized /
# plain DateTime tags.
_stats_record_datetime() {
    local -n values_ref="$1"; shift
    local raw=''
    local key

    for key in DateTimeOriginal DateTimeDigitized DateTime; do
        if [ -n "${values_ref[$key]:-}" ]; then
            raw="${values_ref[$key]}"
            break
        fi
    done
    if [[ ! "$raw" =~ ^([0-9]{4}):([0-9]{2}): ]]; then
        return
    fi
    local -r year="${BASH_REMATCH[1]}"
    local -r month="${BASH_REMATCH[2]}"
    STATS_YEARS["$year"]=$(( ${STATS_YEARS["$year"]:-0} + 1 ))
    STATS_MONTHS["$month"]=$(( ${STATS_MONTHS["$month"]:-0} + 1 ))
}

# Record the aperture, shutter, ISO and focal-length histograms. Each uses the
# fallback tag order the audit recommends and the rational decoder for the
# fiddly fields. Missing/unparseable values are simply skipped.
_stats_record_exposure() {
    local -n values_ref="$1"; shift
    local decimal
    local raw

    raw="${values_ref[FNumber]:-}"
    decimal=$(_stats_rational_to_decimal "$raw")
    if [ -n "$decimal" ]; then
        _stats_bump STATS_APERTURE "$(_stats_aperture_bucket "$decimal")"
    fi

    raw="${values_ref[ExposureTime]:-}"
    decimal=$(_stats_rational_to_decimal "$raw" 6)
    if [ -n "$decimal" ]; then
        _stats_bump STATS_SHUTTER "$(_stats_shutter_bucket "$decimal")"
    fi

    # ISO fallback order mirrors album.source.sh's tooltip builder
    # (ISOSpeedRatings -> PhotographicSensitivity -> ISO) so a photo carrying
    # several ISO tags buckets the same value it shows in its tooltip.
    raw="${values_ref[ISOSpeedRatings]:-${values_ref[PhotographicSensitivity]:-${values_ref[ISO]:-}}}"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        _stats_bump STATS_ISO "$(_stats_iso_bucket "$raw")"
    fi

    raw="${values_ref[FocalLength]:-}"
    decimal=$(_stats_rational_to_decimal "$raw")
    if [ -n "$decimal" ]; then
        _stats_bump STATS_FOCAL "$(_stats_focal_bucket "$decimal")"
    fi
}

# Record the decoded enum stats (exposure program, metering, white balance,
# flash). Each is skipped when the tag is absent or decodes to nothing.
_stats_record_enums() {
    local -n values_ref="$1"; shift
    local label

    if [ -n "${values_ref[ExposureProgram]:-}" ]; then
        label=$(_stats_exposure_program_label "${values_ref[ExposureProgram]}")
        _stats_bump STATS_EXPOSURE_PROGRAM "$label"
    fi
    if [ -n "${values_ref[MeteringMode]:-}" ]; then
        label=$(_stats_metering_label "${values_ref[MeteringMode]}")
        _stats_bump STATS_METERING "$label"
    fi
    if [ -n "${values_ref[WhiteBalance]:-}" ]; then
        label=$(_stats_white_balance_label "${values_ref[WhiteBalance]}")
        if [ -n "$label" ]; then
            _stats_bump STATS_WHITE_BALANCE "$label"
        fi
    fi
    if [[ "${values_ref[Flash]:-}" =~ ^[0-9]+$ ]]; then
        _stats_bump STATS_FLASH "$(_stats_flash_label "${values_ref[Flash]}")"
    fi
}

# Record dimension stats (megapixels, aspect ratio, orientation) from the native
# Geometry field. Geometry is "WxH+x+y"; the leading WxH is what we need. These
# are native fields, not exif: lines, so they come from the separate native
# parser path in _stats_parse_identify_stream.
_stats_record_dimensions() {
    local -n values_ref="$1"; shift
    local mp

    if [[ ! "${values_ref[__geometry]:-}" =~ ^([0-9]+)x([0-9]+) ]]; then
        return
    fi
    local -ri width="${BASH_REMATCH[1]}"
    local -ri height="${BASH_REMATCH[2]}"

    mp=$(awk -v w="$width" -v h="$height" 'BEGIN { printf "%.4f", w * h / 1000000 }')
    _stats_bump STATS_MEGAPIXELS "$(_stats_megapixels_bucket "$mp")"
    _stats_bump STATS_ASPECT "$(_stats_aspect_bucket "$width" "$height")"
    _stats_bump STATS_ORIENTATION "$(_stats_orientation_bucket "$width" "$height")"
}

# Record the file-format breakdown. The audit's cheapest path keys off the file
# extension (no identify parsing), so this maps the extension to a format label.
# This trusts the extension over actual content: a misnamed file (e.g. a PNG
# named .jpg) is counted by its name. Unrecognized extensions fall into 'other'.
_stats_record_format() {
    local -r photo="$1"; shift
    local extension="${photo##*.}"

    if [[ "$photo" != *.* ]]; then
        return
    fi
    case "${extension,,}" in
        jpg|jpeg) _stats_bump STATS_FORMAT 'JPEG' ;;
        png) _stats_bump STATS_FORMAT 'PNG' ;;
        webp) _stats_bump STATS_FORMAT 'WEBP' ;;
        gif) _stats_bump STATS_FORMAT 'GIF' ;;
        *) _stats_bump STATS_FORMAT 'other' ;;
    esac
}

# Increment a counter in the named global associative array. Centralizes the
# "create-or-add-one" idiom and skips empty keys so unparseable buckets do not
# create blank entries.
_stats_bump() {
    local -n array_ref="$1"; shift
    local -r key="$1"; shift

    if [ -z "$key" ]; then
        return
    fi
    array_ref["$key"]=$(( ${array_ref["$key"]:-0} + 1 ))
}

# Parse one photo's `identify -verbose` stream into an associative array. The
# current album.source.sh regex only captures exif: lines, but the audit needs
# the native Geometry field for dimensions, so this adds a second match path
# storing it under the synthetic key __geometry.
_stats_parse_identify_stream() {
    local -n values_ref="$1"; shift
    local line

    values_ref=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$ ]]; then
            values_ref["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*Geometry:[[:space:]]*(.*)$ ]]; then
            values_ref[__geometry]="${BASH_REMATCH[1]}"
        fi
    done
}

# Aggregate a single photo: parse its identify stream (from stdin) and update
# every counter. Split out from collect_photo_exif_stats so tests can feed a
# synthetic fixture without stubbing the cache layer.
accumulate_photo_stats() {
    local -r photo="$1"; shift
    # exif_values is filled and read through the nameref helpers below.
    # shellcheck disable=SC2034
    local -A exif_values=()

    _stats_parse_identify_stream exif_values
    STATS_TOTALS[photos]=$(( STATS_TOTALS[photos] + 1 ))
    _stats_record_camera exif_values "$photo"
    _stats_record_datetime exif_values
    _stats_record_exposure exif_values
    _stats_record_enums exif_values
    _stats_record_dimensions exif_values
    _stats_record_format "$photo"
}

# Iterate the album's incoming photos, read each one's cached identify output via
# album.source.sh's cache helper, and aggregate it into the STATS_* globals.
# This is the entry point the render tasks call before reading the counters.
collect_photo_exif_stats() {
    local photo

    reset_photo_exif_stats
    while IFS= read -r photo; do
        accumulate_photo_stats "$photo" \
            < <(cached_photo_identify_output "$photo" "$INCOMING_DIR/$photo")
    done < <(incoming_image_files)
}

# ----------------------------------------------------------------------------
# Rendering (task pm0)
# ----------------------------------------------------------------------------
# render_stats_page turns the STATS_* globals filled by the aggregation above
# into a static stats.html. The page is variable-length (each category may be
# empty, sparse, or large) which does not fit the fixed field-spec template
# engine cleanly, so we follow the same approach view/details pages use for
# their dynamic EXIF table: build the whole body as an HTML string here, hand it
# to stats.tmpl through the raw context field stats_body, and let the engine wrap
# it with the shared header/footer chrome. Bars are plain CSS (width as a percent
# of the section's top bucket) so the output stays JavaScript-free.

# Print the largest counter in the named stats array, or 0 when it is empty.
# Used to scale each section's bars relative to its own busiest bucket.
_stats_max_count() {
    local -n counts_ref="$1"; shift
    local key
    local -i max=0

    for key in "${!counts_ref[@]}"; do
        if (( counts_ref[$key] > max )); then
            max=${counts_ref[$key]}
        fi
    done
    printf '%d' "$max"
}

# Print the integer percentage count/total (0 when total is 0). awk keeps the
# rounding off bash integer math; STATS_TOTALS[photos] is the denominator.
_stats_percent() {
    local -ri count="$1"; shift
    local -ri total="$1"; shift

    if (( total <= 0 )); then
        printf '0'
        return
    fi
    awk -v c="$count" -v t="$total" 'BEGIN { printf "%.0f", 100 * c / t }'
}

# Emit one bar-chart <li>: an already-escaped label, a CSS-width bar scaled to
# the section maximum, and the count plus its share of all photos. Callers escape
# labels themselves because some come from EXIF (camera/lens) and some are
# trusted bucket names we build internally.
_stats_bar_row() {
    local -r label_html="$1"; shift
    local -ri count="$1"; shift
    local -ri total="$1"; shift
    local -ri max="$1"; shift
    local -i width=0

    if (( max > 0 )); then
        width=$(( 100 * count / max ))
    fi
    printf '    <li>'
    printf '<span class="stats-label">%s</span>' "$label_html"
    printf '<span class="stats-bar-track">'
    printf '<span class="stats-bar-fill" style="width:%d%%"></span></span>' \
        "$width"
    printf '<span class="stats-count">%d (%s%%)</span>' \
        "$count" "$(_stats_percent "$count" "$total")"
    printf '</li>\n'
}

# Open a <section> with an escaped heading and the <ul> bar container. Split from
# the row emitters so every section shares identical chrome.
_stats_section_open() {
    local -r heading="$1"; shift
    local heading_html

    heading_html=$(_html_escape "$heading")
    printf '<section class="stats-section">\n'
    printf '<h2>%s</h2>\n' "$heading_html"
    printf '<ul class="stats-bars">\n'
}

_stats_section_close() {
    printf '</ul>\n</section>\n'
}

# Render the camera leaderboard: one bar per camera, sorted by count descending,
# each label linking to camera-<slug>.html (built by sibling task um0). Camera
# labels come from EXIF, so the label text is HTML-escaped; the slug is filename
# -safe by construction. Skipped entirely when no camera data was collected.
_stats_render_camera_section() {
    local -ri total="$1"; shift
    local label
    local label_html
    local link_html
    local slug
    local -i max

    if (( ${#STATS_CAMERAS[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count STATS_CAMERAS)
    _stats_section_open 'Camera leaderboard'
    while IFS= read -r label; do
        label_html=$(_html_escape "$label")
        slug="${STATS_CAMERA_SLUGS[$label]}"
        link_html=$(printf '<a href="camera-%s.html">%s</a>' \
            "$slug" "$label_html")
        _stats_bar_row "$link_html" "${STATS_CAMERAS[$label]}" "$total" "$max"
    done < <(_stats_keys_by_count_desc STATS_CAMERAS)
    _stats_section_close
}

# Print an array's keys ordered by descending count (ties broken by key) so the
# busiest bucket leads. Used for the leaderboard and other count-ranked sections.
_stats_keys_by_count_desc() {
    local -n counts_ref="$1"; shift
    local key

    for key in "${!counts_ref[@]}"; do
        printf '%d\t%s\n' "${counts_ref[$key]}" "$key"
    done | sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
}

# Render a histogram section using an explicit bucket order (e.g. apertures from
# wide to narrow) rather than count ranking, so the axis reads naturally. Only
# buckets that actually occurred are emitted, and the whole section is skipped
# when none did. Bucket labels are internal/trusted but still escaped for safety.
_stats_render_ordered_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local bucket
    local label_html
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading"
    for bucket in "$@"; do
        if [ -z "${counts_ref[$bucket]:-}" ]; then
            continue
        fi
        label_html=$(_html_escape "$bucket")
        _stats_bar_row "$label_html" "${counts_ref[$bucket]}" "$total" "$max"
    done
    _stats_section_close
}

# Render a section ranked by count (cameras aside). Used where there is no
# natural axis order: years, lenses, and the decoded enum categories.
_stats_render_ranked_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local key
    local label_html
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading"
    while IFS= read -r key; do
        label_html=$(_html_escape "$key")
        _stats_bar_row "$label_html" "${counts_ref[$key]}" "$total" "$max"
    done < <(_stats_keys_by_count_desc "$array_name")
    _stats_section_close
}

# Render the temporal sections. Years rank by count; months walk Jan..Dec in
# calendar order using human month names for the labels.
_stats_render_temporal_sections() {
    local -ri total="$1"; shift

    _stats_render_ranked_section 'Photos per year' STATS_YEARS "$total"
    _stats_render_month_section "$total"
}

# Render the per-month histogram in calendar order. The aggregator keys months
# by zero-padded number (01..12); this maps each to its English name so the axis
# is readable, and reuses the ordered-section omit-when-empty behaviour inline.
_stats_render_month_section() {
    local -ri total="$1"; shift
    local -ra month_names=(
        '' January February March April May June July August
        September October November December )
    local -i month
    local key
    local -i max

    if (( ${#STATS_MONTHS[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count STATS_MONTHS)
    _stats_section_open 'Photos per month'
    for (( month = 1; month <= 12; month++ )); do
        key=$(printf '%02d' "$month")
        if [ -z "${STATS_MONTHS[$key]:-}" ]; then
            continue
        fi
        _stats_bar_row "${month_names[$month]}" \
            "${STATS_MONTHS[$key]}" "$total" "$max"
    done
    _stats_section_close
}

# Render the exposure histograms in photographer-friendly axis order (the same
# bucket ladders the aggregator's *_bucket helpers produce).
_stats_render_exposure_sections() {
    local -ri total="$1"; shift

    _stats_render_ordered_section 'Aperture' STATS_APERTURE "$total" \
        'f/1.8 or wider' 'f/2' 'f/2.8' 'f/4' 'f/5.6' 'f/8' 'f/11' 'f/16' \
        'f/22 or narrower'
    _stats_render_ordered_section 'Shutter speed' STATS_SHUTTER "$total" \
        '1/4000s or faster' '1/2000s' '1/1000s' '1/500s' '1/250s' '1/125s' \
        '1/60s' '1/30s' '1/15s' '1/8s' '1/4s' '1/2s' '1s' 'longer than 1s'
    _stats_render_ordered_section 'ISO' STATS_ISO "$total" \
        '50' '100' '200' '400' '800' '1600' '3200' '6400' '12800' '25600' \
        'over 25600'
    _stats_render_ordered_section 'Focal length' STATS_FOCAL "$total" \
        'under 24mm' '24-35mm' '35-70mm' '70-135mm' '135-200mm' 'over 200mm'
}

# Render the dimension histograms (megapixels, aspect ratio, orientation) and
# the file-format breakdown, each in its natural axis order.
_stats_render_dimension_sections() {
    local -ri total="$1"; shift

    _stats_render_ordered_section 'Megapixels' STATS_MEGAPIXELS "$total" \
        'under 2MP' '2-5MP' '5-10MP' '10-20MP' '20-40MP' '40-80MP' 'over 80MP'
    _stats_render_ordered_section 'Aspect ratio' STATS_ASPECT "$total" \
        '3:2' '4:3' '16:9' '1:1' '5:4' 'other'
    _stats_render_ordered_section 'Orientation' STATS_ORIENTATION "$total" \
        'Landscape' 'Portrait' 'Square'
    _stats_render_ordered_section 'File format' STATS_FORMAT "$total" \
        'JPEG' 'PNG' 'WEBP' 'GIF' 'other'
}

# Render the decoded enum sections and the (sparse) lens leaderboard. All rank by
# count and self-skip when empty, so absent tags simply omit their section.
_stats_render_enum_sections() {
    local -ri total="$1"; shift

    _stats_render_ranked_section 'Lenses' STATS_LENSES "$total"
    _stats_render_ranked_section 'Exposure program' \
        STATS_EXPOSURE_PROGRAM "$total"
    _stats_render_ranked_section 'Metering mode' STATS_METERING "$total"
    _stats_render_ranked_section 'White balance' STATS_WHITE_BALANCE "$total"
    _stats_render_ranked_section 'Flash' STATS_FLASH "$total"
}

# Assemble the full stats body from every section in display order. Returns the
# HTML on stdout; render_stats_page captures it into the stats_body context var.
_stats_build_body() {
    local -ri total="${STATS_TOTALS[photos]:-0}"

    printf '<p class="stats-total">%d photos analysed.</p>\n' "$total"
    _stats_render_camera_section "$total"
    _stats_render_temporal_sections "$total"
    _stats_render_exposure_sections "$total"
    _stats_render_dimension_sections "$total"
    _stats_render_enum_sections "$total"
}

# Public render entry point (handoff for task rm0). Builds the body from the
# already-populated STATS_* globals and renders stats.html via the template
# engine, wrapping the body with the shared header/footer the way view/details
# pages do. Call collect_photo_exif_stats first to fill the globals.
#   render_stats_page <html_dir> <backhref> [page_name]
# html_dir is the dist-relative output directory (top-level album: "."),
# backhref is the relative path back to the album root ("." for a top-level
# stats.html), and page_name defaults to "stats" -> stats.html.
render_stats_page() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_name="${1:-stats}"
    local stats_body

    stats_body=$(_stats_build_body)
    template header "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir '' \
        background_image '' \
        show_header_bar 'yes'
    template stats "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        stats_body "$stats_body"
    template footer "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        tarball_name ''
}
