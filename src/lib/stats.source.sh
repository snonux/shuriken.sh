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
# It also fills the filter mini-album maps (see reset_photo_exif_stats):
# STATS_FILTER_PHOTOS / STATS_FILTER_TITLE keyed by a unique "pagebase", and
# STATS_FILTER_PAGEBASE mapping "<prefix>\x1f<label>" -> pagebase so the stats
# rows can link to each bucket's mini-album.
#
# The render side should treat every per-category array as possibly empty
# (sparse data) and only render a section when it has entries. STATS_TOTALS
# gives the denominator for percentages.

# Reset every stats global to an empty associative array. Called at the start of
# collect_photo_exif_stats so repeated invocations (e.g. tests, --refresh) do
# not accumulate stale counts.
reset_photo_exif_stats() {
    declare -gA STATS_CAMERAS=()
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
    # Every tallied bucket (across all categories) becomes a clickable filter
    # mini-album. These map a unique, filename-safe "pagebase" (e.g. iso-400,
    # camera-canon-eos-r5, year-2023) to that bucket's data:
    #   STATS_FILTER_PHOTOS[pagebase]   = newline-separated photo list
    #   STATS_FILTER_TITLE[pagebase]    = human heading for the gallery page
    #   STATS_FILTER_OWNER[pagebase]    = catkey owning the pagebase (collisions)
    #   STATS_FILTER_PAGEBASE[catkey]   = pagebase for a "<prefix>\x1f<label>"
    # so the bar rows can link to the matching mini-album.
    declare -gA STATS_FILTER_PHOTOS=()
    declare -gA STATS_FILTER_TITLE=()
    declare -gA STATS_FILTER_OWNER=()
    declare -gA STATS_FILTER_PAGEBASE=()
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

# Tally a photo's camera (Make+Model) and, when present, its lens into their
# leaderboard counts and filter mini-albums. Skips photos with no Make/Model.
_stats_record_camera() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local label

    label=$(_stats_camera_label "${values_ref[Make]:-}" "${values_ref[Model]:-}")
    _stats_tally STATS_CAMERAS camera "$label" "$label" "$photo"
    if [ -n "${values_ref[LensModel]:-}" ]; then
        _stats_tally STATS_LENSES lens \
            "${values_ref[LensModel]}" "Lens ${values_ref[LensModel]}" "$photo"
    fi
}

# Record year and month counters from DateTimeOriginal ("YYYY:MM:DD HH:MM:SS").
# Parsed by substring per the audit: the colons in the date part are not
# standard, so this must not be fed to `date -d`. Falls back to the digitized /
# plain DateTime tags.
_stats_record_datetime() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local raw=''
    local key
    local -ra month_names=( '' January February March April May June July
        August September October November December )

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
    _stats_tally STATS_YEARS year "$year" "Year $year" "$photo"
    _stats_tally STATS_MONTHS month "$month" \
        "${month_names[10#$month]:-Month $month}" "$photo"
}

# Record the aperture, shutter, ISO and focal-length histograms. Each uses the
# fallback tag order the audit recommends and the rational decoder for the
# fiddly fields. Missing/unparseable values are simply skipped.
_stats_record_exposure() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local decimal raw bucket

    raw="${values_ref[FNumber]:-}"
    decimal=$(_stats_rational_to_decimal "$raw")
    if [ -n "$decimal" ]; then
        bucket=$(_stats_aperture_bucket "$decimal")
        _stats_tally STATS_APERTURE aperture "$bucket" "Aperture $bucket" "$photo"
    fi

    raw="${values_ref[ExposureTime]:-}"
    decimal=$(_stats_rational_to_decimal "$raw" 6)
    if [ -n "$decimal" ]; then
        bucket=$(_stats_shutter_bucket "$decimal")
        _stats_tally STATS_SHUTTER shutter "$bucket" "Shutter $bucket" "$photo"
    fi

    # ISO fallback order mirrors album.source.sh's tooltip builder
    # (ISOSpeedRatings -> PhotographicSensitivity -> ISO) so a photo carrying
    # several ISO tags buckets the same value it shows in its tooltip.
    raw="${values_ref[ISOSpeedRatings]:-${values_ref[PhotographicSensitivity]:-${values_ref[ISO]:-}}}"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        bucket=$(_stats_iso_bucket "$raw")
        _stats_tally STATS_ISO iso "$bucket" "ISO $bucket" "$photo"
    fi

    raw="${values_ref[FocalLength]:-}"
    decimal=$(_stats_rational_to_decimal "$raw")
    if [ -n "$decimal" ]; then
        bucket=$(_stats_focal_bucket "$decimal")
        _stats_tally STATS_FOCAL focal "$bucket" "Focal length $bucket" "$photo"
    fi
}

# Record the decoded enum stats (exposure program, metering, white balance,
# flash). Each is skipped when the tag is absent or decodes to nothing (empty
# labels are dropped by _stats_tally).
_stats_record_enums() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local label

    if [ -n "${values_ref[ExposureProgram]:-}" ]; then
        label=$(_stats_exposure_program_label "${values_ref[ExposureProgram]}")
        _stats_tally STATS_EXPOSURE_PROGRAM exposure-program \
            "$label" "Exposure program $label" "$photo"
    fi
    if [ -n "${values_ref[MeteringMode]:-}" ]; then
        label=$(_stats_metering_label "${values_ref[MeteringMode]}")
        _stats_tally STATS_METERING metering "$label" "Metering $label" "$photo"
    fi
    if [ -n "${values_ref[WhiteBalance]:-}" ]; then
        label=$(_stats_white_balance_label "${values_ref[WhiteBalance]}")
        _stats_tally STATS_WHITE_BALANCE white-balance \
            "$label" "White balance $label" "$photo"
    fi
    if [[ "${values_ref[Flash]:-}" =~ ^[0-9]+$ ]]; then
        label=$(_stats_flash_label "${values_ref[Flash]}")
        _stats_tally STATS_FLASH flash "$label" "Flash $label" "$photo"
    fi
}

# Record dimension stats (megapixels, aspect ratio, orientation) from the native
# Geometry field. Geometry is "WxH+x+y"; the leading WxH is what we need. These
# are native fields, not exif: lines, so they come from the separate native
# parser path in _stats_parse_identify_stream.
_stats_record_dimensions() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local mp bucket

    if [[ ! "${values_ref[__geometry]:-}" =~ ^([0-9]+)x([0-9]+) ]]; then
        return
    fi
    local -ri width="${BASH_REMATCH[1]}"
    local -ri height="${BASH_REMATCH[2]}"

    mp=$(awk -v w="$width" -v h="$height" 'BEGIN { printf "%.4f", w * h / 1000000 }')
    bucket=$(_stats_megapixels_bucket "$mp")
    _stats_tally STATS_MEGAPIXELS megapixels "$bucket" "Megapixels $bucket" "$photo"
    bucket=$(_stats_aspect_bucket "$width" "$height")
    _stats_tally STATS_ASPECT aspect "$bucket" "Aspect ratio $bucket" "$photo"
    bucket=$(_stats_orientation_bucket "$width" "$height")
    _stats_tally STATS_ORIENTATION orientation "$bucket" "$bucket" "$photo"
}

# Record the file-format breakdown. The audit's cheapest path keys off the file
# extension (no identify parsing), so this maps the extension to a format label.
# This trusts the extension over actual content: a misnamed file (e.g. a PNG
# named .jpg) is counted by its name. Unrecognized extensions fall into 'other'.
_stats_record_format() {
    local -r photo="$1"; shift
    local extension="${photo##*.}"
    local label

    if [[ "$photo" != *.* ]]; then
        return
    fi
    case "${extension,,}" in
        jpg|jpeg) label=JPEG ;;
        png) label=PNG ;;
        webp) label=WEBP ;;
        gif) label=GIF ;;
        *) label=other ;;
    esac
    _stats_tally STATS_FORMAT format "$label" "$label" "$photo"
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

# Field separator used inside STATS_FILTER_PAGEBASE keys ("<prefix>\x1f<label>").
# A control char that cannot appear in a prefix or an EXIF label.
declare -gr STATS_FILTER_KEYSEP=$'\x1f'

# Resolve the unique, filename-safe pagebase for a (prefix, label) filter into
# the named output variable, caching it so repeated tallies reuse it. Distinct
# labels in the same category whose slug collides (e.g. two camera models
# differing only in punctuation) get a numeric suffix. Uses a nameref output --
# not command substitution -- so the STATS_FILTER_OWNER/PAGEBASE mutations
# persist in the caller's shell.
_stats_resolve_filter_pagebase() {
    local -n pagebase_out_ref="$1"; shift
    local -r prefix="$1"; shift
    local -r label="$1"; shift
    local -r catkey="$prefix$STATS_FILTER_KEYSEP$label"
    local base slug
    local -i suffix=2

    if [ -n "${STATS_FILTER_PAGEBASE[$catkey]:-}" ]; then
        pagebase_out_ref="${STATS_FILTER_PAGEBASE[$catkey]}"
        return
    fi
    slug=$(_stats_slug "$label")
    if [ -z "$slug" ]; then
        slug=other
    fi
    base="$prefix-$slug"
    pagebase_out_ref="$base"
    while [ -n "${STATS_FILTER_OWNER[$pagebase_out_ref]:-}" ] \
        && [ "${STATS_FILTER_OWNER[$pagebase_out_ref]}" != "$catkey" ]; do
        pagebase_out_ref="$base-$suffix"
        (( ++suffix ))
    done
    STATS_FILTER_OWNER["$pagebase_out_ref"]="$catkey"
    STATS_FILTER_PAGEBASE["$catkey"]="$pagebase_out_ref"
}

# Tally one photo into a bucket: bump the category count AND record the photo on
# the bucket's filter mini-album (keyed by a unique pagebase). prefix namespaces
# the pagebase per category, label is the bucket key (also the count-array key),
# and title is the gallery heading shown for that bucket. Skips empty labels.
_stats_tally() {
    local -r count_array="$1"; shift
    local -r prefix="$1"; shift
    local -r label="$1"; shift
    local -r title="$1"; shift
    local -r photo="$1"; shift
    local pagebase

    if [ -z "$label" ]; then
        return
    fi
    _stats_bump "$count_array" "$label"
    _stats_resolve_filter_pagebase pagebase "$prefix" "$label"
    if [ -n "${STATS_FILTER_PHOTOS[$pagebase]:-}" ]; then
        STATS_FILTER_PHOTOS["$pagebase"]+=$'\n'"$photo"
    else
        STATS_FILTER_PHOTOS["$pagebase"]="$photo"
        STATS_FILTER_TITLE["$pagebase"]="$title"
    fi
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
    _stats_record_datetime exif_values "$photo"
    _stats_record_exposure exif_values "$photo"
    _stats_record_enums exif_values "$photo"
    _stats_record_dimensions exif_values "$photo"
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
# the row emitters so every section shares identical chrome. An optional second
# argument adds an extra CSS class to the <ul> (e.g. the leaderboard uses it to
# space out and separate its rows of long, wrapping camera names).
_stats_section_open() {
    local -r heading="$1"; shift
    local -r list_class="${1:-}"
    local heading_html
    local ul_class='stats-bars'

    if [ -n "$list_class" ]; then
        ul_class+=" $list_class"
    fi
    heading_html=$(_html_escape "$heading")
    printf '<section class="stats-section">\n'
    printf '<h2>%s</h2>\n' "$heading_html"
    printf '<ul class="%s">\n' "$ul_class"
}

_stats_section_close() {
    printf '</ul>\n</section>\n'
}

# Wrap an escaped label in a link to its filter mini-album. Every tallied bucket
# has a pagebase recorded in STATS_FILTER_PAGEBASE during aggregation, keyed by
# "<prefix>\x1f<label>"; if one is (unexpectedly) absent, the plain label is
# returned so the row still renders. The stats page and the filter pages share
# the dist root, so the href is just "<pagebase>.html".
_stats_filter_link() {
    local -r prefix="$1"; shift
    local -r label="$1"; shift
    local -r label_html="$1"; shift
    local -r catkey="$prefix$STATS_FILTER_KEYSEP$label"
    local pagebase

    pagebase="${STATS_FILTER_PAGEBASE[$catkey]:-}"
    if [ -n "$pagebase" ]; then
        printf '<a href="%s.html">%s</a>' "$pagebase" "$label_html"
    else
        printf '%s' "$label_html"
    fi
}

# Render the camera leaderboard: one bar per camera, sorted by count descending,
# each label linking to its camera mini-album. Camera labels come from EXIF, so
# the text is HTML-escaped. Skipped entirely when no camera data was collected.
_stats_render_camera_section() {
    local -ri total="$1"; shift
    local label
    local row_html
    local -i max

    if (( ${#STATS_CAMERAS[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count STATS_CAMERAS)
    _stats_section_open 'Camera leaderboard' 'stats-leaderboard'
    while IFS= read -r label; do
        row_html=$(_stats_filter_link camera "$label" "$(_html_escape "$label")")
        _stats_bar_row "$row_html" "${STATS_CAMERAS[$label]}" "$total" "$max"
    done < <(_stats_keys_by_count_desc STATS_CAMERAS)
    _stats_section_close
}

# Print an array's keys ordered by descending count (ties broken by key) so the
# busiest bucket leads. Used for the leaderboard and other count-ranked sections.
# LC_ALL=C pins the tie-break collation so the generated page is byte-identical
# across locales/machines (reproducible static output).
_stats_keys_by_count_desc() {
    local -n counts_ref="$1"; shift
    local key

    for key in "${!counts_ref[@]}"; do
        printf '%d\t%s\n' "${counts_ref[$key]}" "$key"
    done | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
}

# Render a histogram section using an explicit bucket order (e.g. apertures from
# wide to narrow) rather than count ranking, so the axis reads naturally. Only
# buckets that actually occurred are emitted, and the whole section is skipped
# when none did. Bucket labels are internal/trusted but still escaped for safety.
_stats_render_ordered_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -r prefix="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local bucket
    local row_html
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
        row_html=$(_stats_filter_link "$prefix" "$bucket" "$(_html_escape "$bucket")")
        _stats_bar_row "$row_html" "${counts_ref[$bucket]}" "$total" "$max"
    done
    _stats_section_close
}

# Render a section ranked by count (cameras aside). Used where there is no
# natural axis order: years, lenses, and the decoded enum categories.
_stats_render_ranked_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -r prefix="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local key
    local row_html
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading"
    while IFS= read -r key; do
        row_html=$(_stats_filter_link "$prefix" "$key" "$(_html_escape "$key")")
        _stats_bar_row "$row_html" "${counts_ref[$key]}" "$total" "$max"
    done < <(_stats_keys_by_count_desc "$array_name")
    _stats_section_close
}

# Render the temporal sections. Years rank by count; months walk Jan..Dec in
# calendar order using human month names for the labels.
_stats_render_temporal_sections() {
    local -ri total="$1"; shift

    _stats_render_ranked_section 'Photos per year' STATS_YEARS year "$total"
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
        _stats_bar_row \
            "$(_stats_filter_link month "$key" "${month_names[$month]}")" \
            "${STATS_MONTHS[$key]}" "$total" "$max"
    done
    _stats_section_close
}

# Render the exposure histograms in photographer-friendly axis order (the same
# bucket ladders the aggregator's *_bucket helpers produce).
_stats_render_exposure_sections() {
    local -ri total="$1"; shift

    _stats_render_ordered_section 'Aperture' STATS_APERTURE aperture "$total" \
        'f/1.8 or wider' 'f/2' 'f/2.8' 'f/4' 'f/5.6' 'f/8' 'f/11' 'f/16' \
        'f/22 or narrower'
    _stats_render_ordered_section 'Shutter speed' STATS_SHUTTER shutter "$total" \
        '1/4000s or faster' '1/2000s' '1/1000s' '1/500s' '1/250s' '1/125s' \
        '1/60s' '1/30s' '1/15s' '1/8s' '1/4s' '1/2s' '1s' 'longer than 1s'
    _stats_render_ordered_section 'ISO' STATS_ISO iso "$total" \
        '50' '100' '200' '400' '800' '1600' '3200' '6400' '12800' '25600' \
        'over 25600'
    _stats_render_ordered_section 'Focal length' STATS_FOCAL focal "$total" \
        'under 24mm' '24-35mm' '35-70mm' '70-135mm' '135-200mm' 'over 200mm'
}

# Render the dimension histograms (megapixels, aspect ratio, orientation) and
# the file-format breakdown, each in its natural axis order.
_stats_render_dimension_sections() {
    local -ri total="$1"; shift

    _stats_render_ordered_section 'Megapixels' STATS_MEGAPIXELS megapixels \
        "$total" \
        'under 2MP' '2-5MP' '5-10MP' '10-20MP' '20-40MP' '40-80MP' 'over 80MP'
    _stats_render_ordered_section 'Aspect ratio' STATS_ASPECT aspect "$total" \
        '3:2' '4:3' '16:9' '1:1' '5:4' 'other'
    _stats_render_ordered_section 'Orientation' STATS_ORIENTATION orientation \
        "$total" 'Landscape' 'Portrait' 'Square'
    _stats_render_ordered_section 'File format' STATS_FORMAT format "$total" \
        'JPEG' 'PNG' 'WEBP' 'GIF' 'other'
}

# Render the decoded enum sections and the (sparse) lens leaderboard. All rank by
# count and self-skip when empty, so absent tags simply omit their section.
_stats_render_enum_sections() {
    local -ri total="$1"; shift

    _stats_render_ranked_section 'Lenses' STATS_LENSES lens "$total"
    _stats_render_ranked_section 'Exposure program' \
        STATS_EXPOSURE_PROGRAM exposure-program "$total"
    _stats_render_ranked_section 'Metering mode' STATS_METERING metering "$total"
    _stats_render_ranked_section 'White balance' STATS_WHITE_BALANCE \
        white-balance "$total"
    _stats_render_ranked_section 'Flash' STATS_FLASH flash "$total"
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
# Pick a seeded-random photo for a stats/camera page's blurred background, the
# same way the album preview pages do. The context seeds the choice so each page
# gets a stable (per RANDOM_SEED) but varied background. Degrades to an empty
# string (plain black background) when no photos exist, e.g. unit tests that
# render the page without a populated photos directory.
_stats_random_background() {
    local -r context="$1"; shift

    randomphoto "$STATS_PHOTOS_DIR" "$context" 2>/dev/null || true
}

render_stats_page() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_name="${1:-stats}"
    local stats_body
    local background_image

    stats_body=$(_stats_build_body)
    background_image=$(_stats_random_background "$page_name.html")
    template header "$page_name.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$STATS_BLURS_DIR" \
        background_image "$background_image" \
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

# ----------------------------------------------------------------------------
# Filter mini-album pages
# ----------------------------------------------------------------------------
# Every tallied bucket (camera, lens, year, month, aperture, ISO, ...) becomes a
# clickable, self-contained mini album. render_filter_pages turns each pagebase
# in STATS_FILTER_PHOTOS into a gallery (<pagebase>.html, a thumbnail grid) plus
# one view page per photo (<pagebase>--<index>.html) whose prev/next cycle only
# within that filter. The "--<index>" suffix cannot collide with another gallery
# name because a pagebase never contains "--". All pages reuse the album's shared
# photos/thumbs/blurs assets (only the HTML differs); view pages link "Details"
# to the album's own details page via ALBUM_VIEW_PAGE_BY_PHOTO. Pages render in
# parallel through the shared job pool, throttled to IMAGE_JOBS. The galleries
# reuse camera.tmpl and the view pages reuse cameraview.tmpl.

# Dist-relative subdirectories holding the shared full-size images, thumbnails
# and blurred backgrounds, matching the literals generate() passes to
# render_album_pages so filter pages reuse the same asset files.
declare -gr STATS_PHOTOS_DIR='photos'
declare -gr STATS_THUMBS_DIR='thumbs'
declare -gr STATS_BLURS_DIR='blurs'

# Emit one thumbnail anchor for a filter gallery: a thumb image (from thumbs/)
# linking to this filter's view page for that photo (<pagebase>--<index>.html).
# The photo filename is HTML-escaped; the pagebase and index are filename-safe.
_stats_filter_thumbnail() {
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -ri index="$1"; shift
    local -r photo="$1"; shift
    local photo_html
    local animation_class

    photo_html=$(_html_escape "$photo")
    # Same seeded animation the album thumbnail uses for this photo.
    animation_class=$(random_animation_css_class slow "$photo")
    printf '        <a name="%s" href="%s/%s--%d.html">' \
        "$photo_html" "$backhref_html" "$pagebase" "$index"
    printf '<img class="thumb %s" src="%s/%s/%s" /></a>\n' \
        "$animation_class" "$backhref_html" "$STATS_THUMBS_DIR" "$photo_html"
}

# Build the full thumbnail grid for one filter from its newline-separated photo
# list, preserving aggregation (encounter) order for deterministic output.
_stats_build_filter_thumbs() {
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -r photos="$1"; shift
    local photo
    local -i index=0

    while IFS= read -r photo; do
        if [ -n "$photo" ]; then
            (( ++index ))
            _stats_filter_thumbnail "$backhref_html" "$pagebase" "$index" "$photo"
        fi
    done <<< "$photos"
}

# Render a filter gallery page (<pagebase>.html): header + camera.tmpl (heading +
# pre-built thumbnail grid) + footer. camera.tmpl is reused for every filter; the
# heading is the bucket's title (camera name, "ISO 400", "Year 2023", ...).
_stats_render_filter_gallery() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local thumbs
    local background_image
    local -r page="$pagebase.html"
    local -r title="${STATS_FILTER_TITLE[$pagebase]:-}"

    thumbs=$(_stats_build_filter_thumbs \
        "$backhref_html" "$pagebase" "${STATS_FILTER_PHOTOS[$pagebase]}")
    background_image=$(_stats_random_background "$page")
    template header "$page" \
        html_dir "$html_dir" backhref "$backhref" \
        blurs_dir "$STATS_BLURS_DIR" background_image "$background_image" \
        show_header_bar 'yes'
    template camera "$page" \
        html_dir "$html_dir" backhref "$backhref" \
        camera_name "$title" camera_thumbs "$thumbs"
    template footer "$page" \
        html_dir "$html_dir" backhref "$backhref" tarball_name ''
}

# Render one filter view page (<pagebase>--<index>.html): header + cameraview
# body + footer, with prev/next cycling within the filter.
_stats_render_filter_view_page() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -r photo="$1"; shift
    local -ri index="$1"; shift
    local -ri prev="$1"; shift
    local -ri next="$1"; shift
    local body
    local background_image
    local -r page="$pagebase--$index.html"

    body=$(_stats_build_filterview_body \
        "$backhref_html" "$pagebase" "$photo" "$prev" "$next")
    background_image=$(_stats_random_background "$page")
    template header "$page" \
        html_dir "$html_dir" backhref "$backhref" \
        blurs_dir "$STATS_BLURS_DIR" background_image "$background_image" \
        show_header_bar 'no'
    template cameraview "$page" \
        html_dir "$html_dir" backhref "$backhref" cameraview_body "$body"
    template footer "$page" \
        html_dir "$html_dir" backhref "$backhref" tarball_name ''
}

# Build a filter view page body: the photo (linked to the filter's next photo)
# plus a navigator whose prev/next cycle within the filter, a link back to the
# gallery, an optional Details link to the album's details page, and a direct
# image link.
_stats_build_filterview_body() {
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -r photo="$1"; shift
    local -ri prev="$1"; shift
    local -ri next="$1"; shift
    local photo_html
    local animation_class
    local tooltip
    local tooltip_attr=''
    local view_page
    local details_link=''

    photo_html=$(_html_escape "$photo")
    animation_class=$(random_animation_css_class fast "$photo")
    tooltip=$(photo_exif_tooltip_text "$photo" "$INCOMING_DIR/$photo")
    if [ -n "$tooltip" ]; then
        tooltip_attr=" title=\"$(_html_escape "$tooltip")\""
    fi
    view_page="${ALBUM_VIEW_PAGE_BY_PHOTO[$photo]:-}"
    if [ -n "$view_page" ]; then
        details_link=$(printf ' <a href="%s/%s-details.html">Details</a> |' \
            "$backhref_html" "$view_page")
    fi
    _stats_print_filterview_body "$backhref_html" "$pagebase" "$photo_html" \
        "$animation_class" "$tooltip_attr" "$details_link" "$prev" "$next"
}

# Emit the filter view page markup. Split out so _stats_build_filterview_body
# stays focused on assembling the pieces.
_stats_print_filterview_body() {
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -r photo_html="$1"; shift
    local -r animation_class="$1"; shift
    local -r tooltip_attr="$1"; shift
    local -r details_link="$1"; shift
    local -ri prev="$1"; shift
    local -ri next="$1"; shift

    cat <<END
<div class='view'>
    <a href="$backhref_html/$pagebase--$next.html">
        <img class='view $animation_class' border='0' src='$backhref_html/$STATS_PHOTOS_DIR/$photo_html'$tooltip_attr />
    </a>
    <div class="navigator">
        <a href="$backhref_html/$pagebase--$prev.html" class="arrow">&lArr;</a>
        <a href="$backhref_html/$pagebase.html">Gallery</a> |$details_link
        <a href="$backhref_html/$STATS_PHOTOS_DIR/$photo_html">Direct link</a>
        <a href="$backhref_html/$pagebase--$next.html" class="arrow">&rArr;</a>
    </div>
</div>
END
}

# Enqueue one filter's mini-album (gallery + a view page per photo) onto the
# shared render job pool, waiting for a free slot (<= IMAGE_JOBS) before each
# background render so parallelism follows the configured IMAGE_JOBS.
_stats_enqueue_filter_album() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r backhref_html="$1"; shift
    local -r pagebase="$1"; shift
    local -r pids_name="$1"; shift
    local -r statuses_name="$1"; shift
    local -r labels_name="$1"; shift
    local -r failed_name="$1"; shift
    # shellcheck disable=SC2178
    local -n pids_ref="$pids_name"
    # shellcheck disable=SC2178
    local -n labels_ref="$labels_name"
    local photo
    local -a photo_list=()
    local -i i n

    while IFS= read -r photo; do
        [ -n "$photo" ] && photo_list+=("$photo")
    done <<< "${STATS_FILTER_PHOTOS[$pagebase]}"
    n=${#photo_list[@]}

    wait_for_template_render_job_slot \
        "$pids_name" "$statuses_name" "$labels_name" "$failed_name"
    _stats_render_filter_gallery \
        "$html_dir" "$backhref" "$backhref_html" "$pagebase" &
    pids_ref+=("$!")
    labels_ref["$!"]="filter gallery $pagebase"

    for (( i = 1; i <= n; i++ )); do
        wait_for_template_render_job_slot \
            "$pids_name" "$statuses_name" "$labels_name" "$failed_name"
        _stats_render_filter_view_page \
            "$html_dir" "$backhref" "$backhref_html" "$pagebase" \
            "${photo_list[i - 1]}" "$i" \
            "$(( i == 1 ? n : i - 1 ))" "$(( i == n ? 1 : i + 1 ))" &
        pids_ref+=("$!")
        labels_ref["$!"]="filter view $pagebase--$i"
    done
}

# Public entry point: render every filter mini-album in parallel. Call
# collect_photo_exif_stats first to fill STATS_FILTER_PHOTOS. html_dir is the
# dist-relative output dir ("." for a top-level album) and backhref the relative
# path back to the album root ("."), the same values render_stats_page uses.
# Pagebases are walked in LC_ALL=C order for reproducible enqueue order.
render_filter_pages() {
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local backhref_html
    local pagebase
    # Render job pool, throttled to IMAGE_JOBS by the job-pool helpers.
    local -a render_job_pids=()
    # shellcheck disable=SC2034
    local -A render_job_statuses=()
    # shellcheck disable=SC2034
    local -A render_job_labels=()
    local -i render_failed=0

    if (( ${#STATS_FILTER_PHOTOS[@]} == 0 )); then
        return
    fi
    backhref_html=$(_html_escape "$backhref")
    while IFS= read -r pagebase; do
        _stats_enqueue_filter_album \
            "$html_dir" "$backhref" "$backhref_html" "$pagebase" \
            render_job_pids render_job_statuses render_job_labels render_failed
    done < <(printf '%s\n' "${!STATS_FILTER_PHOTOS[@]}" | LC_ALL=C sort)
    wait_for_template_render_jobs \
        render_job_pids render_job_statuses render_job_labels render_failed
    if (( render_failed != 0 )); then
        return 1
    fi
}
