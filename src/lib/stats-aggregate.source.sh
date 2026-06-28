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
# (all declared with `declare -gA`). They are this module's PRIVATE backing
# store: the reader modules (stats-render.source.sh, stats-filter-album.source.sh)
# do NOT index them directly -- they go through the accessor functions at the end
# of this file (stats_total_photos, stats_filter_pagebase, stats_filter_title,
# stats_filter_photos, stats_filter_count, stats_filter_pagebases, and the
# stats_category_* count accessors). That keeps the readers decoupled from the
# key conventions used below. The arrays filled here are:
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

# ----------------------------------------------------------------------------
# Category registry (single source of truth, task en0)
# ----------------------------------------------------------------------------
# STATS_CATEGORIES is the one place a stats category is defined. Each entry is a
# '|'-delimited spec (same encoding as template.source.sh's
# TEMPLATE_RENDER_FIELD_SPECS) holding everything the generic reset, recording
# dispatch and render loops need:
#
#   count_array|prefix|heading|render_kind[|list_class]
#
#   count_array  the STATS_* associative array holding this category's counts;
#                also the array reset_photo_exif_stats clears each run.
#   prefix       the namespace passed to _stats_tally / _stats_filter_link (and
#                the filter-page slug prefix, e.g. "iso" -> iso-400).
#   heading      the <h2> shown on the overview (and the per-section title).
#   render_kind  how the overview renders this category's bars; resolved by name
#                to a _stats_render_section__<render_kind> handler (declare -F
#                dispatch in stats-render.source.sh):
#                  ranked  - count-desc bars (camera leaderboard, years, lenses,
#                            decoded enums).
#                  ordered - fixed bucket-ladder order from
#                            STATS_CATEGORY_BUCKETS (apertures wide->narrow, ...).
#                  month   - calendar Jan..Dec order with English month names.
#   list_class   optional extra <ul> CSS class for the 'ranked' kind. The camera
#                leaderboard passes 'stats-leaderboard' (data-only difference, so
#                no separate camera render kind); other ranked categories omit it.
#
# The array order IS the overview/body display order, so it must reproduce the
# historical _stats_build_body sequence exactly (camera, year, month, the four
# exposure histograms, the dimension+format histograms, then the enum/lens
# ranked sections). The per-category record functions stay grouped by EXIF
# source affinity (one datetime parser fills year+month, one exposure parser
# fills four histograms) and are dispatched from STATS_RECORD_FUNCTIONS below;
# they tally into the array named here. Adding a category now means: append one
# STATS_CATEGORIES entry (+ a STATS_CATEGORY_BUCKETS row for an ordered ladder)
# and make some record function tally into its array -- no edits to the reset,
# the body builder, or a per-category render branch.
# Declared -g so it survives being sourced from inside a function (the test
# harness sources the lib via test::source_shuriken_lib); a plain `declare -r`
# would be function-local and vanish on return.
declare -gra STATS_CATEGORIES=(
    'STATS_CAMERAS|camera|Camera leaderboard|ranked|stats-leaderboard'
    'STATS_YEARS|year|Photos per year|ranked'
    'STATS_MONTHS|month|Photos per month|month'
    'STATS_APERTURE|aperture|Aperture|ordered'
    'STATS_SHUTTER|shutter|Shutter speed|ordered'
    'STATS_ISO|iso|ISO|ordered'
    'STATS_FOCAL|focal|Focal length|ordered'
    'STATS_MEGAPIXELS|megapixels|Megapixels|ordered'
    'STATS_ASPECT|aspect|Aspect ratio|ordered'
    'STATS_ORIENTATION|orientation|Orientation|ordered'
    'STATS_FORMAT|format|File format|ordered'
    'STATS_LENSES|lens|Lenses|ranked'
    'STATS_EXPOSURE_PROGRAM|exposure-program|Exposure program|ranked'
    'STATS_METERING|metering|Metering mode|ranked'
    'STATS_WHITE_BALANCE|white-balance|White balance|ranked'
    'STATS_FLASH|flash|Flash|ranked'
)

# Bucket ladders for the 'ordered' categories, keyed by their count_array name.
# Tab-delimited because the bucket labels themselves contain spaces and slashes
# (but never tabs). These reproduce the photographer-friendly axis order the
# aggregator's *_bucket helpers emit, so the histogram axes read naturally
# regardless of how many photos landed in each bucket.
declare -gA STATS_CATEGORY_BUCKETS=(
    [STATS_APERTURE]=$'f/1.8 or wider\tf/2\tf/2.8\tf/4\tf/5.6\tf/8\tf/11\tf/16\tf/22 or narrower'
    [STATS_SHUTTER]=$'1/4000s or faster\t1/2000s\t1/1000s\t1/500s\t1/250s\t1/125s\t1/60s\t1/30s\t1/15s\t1/8s\t1/4s\t1/2s\t1s\tlonger than 1s'
    [STATS_ISO]=$'50\t100\t200\t400\t800\t1600\t3200\t6400\t12800\t25600\tover 25600'
    [STATS_FOCAL]=$'under 24mm\t24-35mm\t35-70mm\t70-135mm\t135-200mm\tover 200mm'
    [STATS_MEGAPIXELS]=$'under 2MP\t2-5MP\t5-10MP\t10-20MP\t20-40MP\t40-80MP\tover 80MP'
    [STATS_ASPECT]=$'3:2\t4:3\t16:9\t1:1\t5:4\tother'
    [STATS_ORIENTATION]=$'Landscape\tPortrait\tSquare'
    [STATS_FORMAT]=$'JPEG\tPNG\tWEBP\tGIF\tother'
)

# The per-photo record functions, dispatched in order by accumulate_photo_stats.
# Each is grouped by EXIF source affinity (so one identify parse fills several
# related categories) and tallies into the STATS_* arrays named in
# STATS_CATEGORIES. _stats_record_format takes only the photo path (no EXIF
# values), so accumulate_photo_stats special-cases it; the rest take the parsed
# values array plus the photo path.
# -g so the dispatch list survives a function-scoped source (see STATS_CATEGORIES).
declare -gra STATS_RECORD_FUNCTIONS=(
    _stats_record_camera
    _stats_record_datetime
    _stats_record_exposure
    _stats_record_enums
    _stats_record_dimensions
)

# Print the count_array name for each registry entry, in display order. Used by
# the generic reset and any consumer that needs to walk every category's array.
_stats_category_arrays() {
    local spec
    for spec in "${STATS_CATEGORIES[@]}"; do
        printf '%s\n' "${spec%%|*}"
    done
}

# Reset every stats global to an empty associative array. Called at the start of
# collect_photo_exif_stats so repeated invocations (e.g. tests, --refresh) do
# not accumulate stale counts. The per-category count arrays are cleared by
# iterating STATS_CATEGORIES so a new category needs no edit here.
reset_photo_exif_stats() {
    local array_name
    while IFS= read -r array_name; do
        declare -gA "$array_name=()"
    done < <(_stats_category_arrays)
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
    # Cached background photo list (filled lazily by _stats_random_background);
    # cleared so a fresh generation rescans the (possibly changed) photos dir.
    declare -ga STATS_BG_PHOTOS=()
    STATS_BG_PHOTOS_LOADED=''
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

# Tally a photo's camera (Make+Model) and, when present, its lens into their
# leaderboard counts and filter mini-albums. Skips photos with no Make/Model.
# The Make+Model dedup now lives in camera_label_from_make_model
# (metadata-label.source.sh, task mn0), shared with the album tooltip builder.
_stats_record_camera() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local label

    label=$(camera_label_from_make_model \
        "${values_ref[Make]:-}" "${values_ref[Model]:-}")
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
# are native fields, not exif: lines, so they come from the native Geometry
# (__geometry) path in the shared photo_exif_values_to parser.
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

# Aggregate a single photo: parse its identify stream (from stdin) and update
# every counter. Split out from collect_photo_exif_stats so tests can feed a
# synthetic fixture without stubbing the cache layer.
accumulate_photo_stats() {
    local -r photo="$1"; shift
    # exif_values is filled and read through the nameref helpers below.
    # shellcheck disable=SC2034
    local -A exif_values=()
    local record_fn

    # Parse the identify stream from stdin via the single canonical parser
    # (photo_exif_values_to, promoted to metadata-cache.source.sh in task 8r0).
    # It captures both exif: tags and the native Geometry line under __geometry,
    # which _stats_record_dimensions consumes.
    photo_exif_values_to exif_values
    STATS_TOTALS[photos]=$(( STATS_TOTALS[photos] + 1 ))
    # Dispatch the EXIF-driven recorders from the registry list so categories are
    # not hardcoded here. Each takes the parsed values array plus the photo path.
    for record_fn in "${STATS_RECORD_FUNCTIONS[@]}"; do
        "$record_fn" exif_values "$photo"
    done
    # _stats_record_format keys off the file extension only (no EXIF parse), so
    # it runs separately with just the photo path -- kept last to preserve the
    # historical tally order.
    _stats_record_format "$photo"
}

# Iterate the album's incoming photos, read each one's cached identify output via
# the shared metadata-cache.source.sh primitive (task pn0), and aggregate it into
# the STATS_* globals.
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
# Public read API (task or0)
# ----------------------------------------------------------------------------
# The STATS_* maps above are this module's PRIVATE backing store. The reader
# modules (stats-render.source.sh, stats-filter-album.source.sh) must NOT index
# them directly: they call the accessors below instead. Keeping the maps private
# behind documented functions decouples the readers from the aggregator's key
# conventions (the "<prefix>\x1f<label>" pagebase keys, the per-category count
# arrays, the photos-total counter), so a change to how a key is built or a map
# is named stays contained in this module -- mirroring album-render's
# ALBUM_VIEW_PAGE_BY_PHOTO / album_view_page_for_photo split.

# Print the number of photos analysed (the percentage/scale denominator), or 0
# before any aggregation ran. Encapsulates STATS_TOTALS[photos]; matches the
# render side's former "${STATS_TOTALS[photos]:-0}" missing-key default.
stats_total_photos() {
    printf '%d' "${STATS_TOTALS[photos]:-0}"
}

# Print the filename-safe pagebase for a (prefix, label) filter bucket, or the
# empty string when that bucket was never tallied. Encapsulates both the
# STATS_FILTER_KEYSEP catkey encoding and the STATS_FILTER_PAGEBASE map, so the
# stats overview can link each bar to its mini-album without knowing how keys are
# built. Matches the former "${STATS_FILTER_PAGEBASE[$catkey]:-}" lookup.
stats_filter_pagebase() {
    local -r prefix="$1"; shift
    local -r label="$1"; shift
    local -r catkey="$prefix$STATS_FILTER_KEYSEP$label"

    printf '%s' "${STATS_FILTER_PAGEBASE[$catkey]:-}"
}

# Print the human gallery heading recorded for a filter pagebase, or the empty
# string when unknown. Encapsulates STATS_FILTER_TITLE; matches the filter
# module's former "${STATS_FILTER_TITLE[$pagebase]:-}" lookup.
stats_filter_title() {
    local -r pagebase="$1"; shift

    printf '%s' "${STATS_FILTER_TITLE[$pagebase]:-}"
}

# Print the newline-separated photo list recorded for a filter pagebase.
# Encapsulates STATS_FILTER_PHOTOS for the per-pagebase read sites. Callers that
# always pass a known pagebase relied on the bare "${STATS_FILTER_PHOTOS[...]}"
# (no :- default); under set -u an unknown pagebase would have errored, so this
# preserves that by also using the bare lookup.
stats_filter_photos() {
    local -r pagebase="$1"; shift

    printf '%s' "${STATS_FILTER_PHOTOS[$pagebase]}"
}

# Print the number of filter mini-albums tallied (0 when none). Encapsulates the
# "${#STATS_FILTER_PHOTOS[@]}" size read render_filter_pages uses to skip work
# when there is nothing to render.
stats_filter_count() {
    printf '%d' "${#STATS_FILTER_PHOTOS[@]}"
}

# Print every filter pagebase, one per line, in LC_ALL=C-sorted order so the
# enqueue order is reproducible. Encapsulates the "${!STATS_FILTER_PHOTOS[@]}"
# key enumeration; the sort is pinned here (not in the caller) so the order is
# owned alongside the data, and reproduces render_filter_pages's former
# "printf ... "${!STATS_FILTER_PHOTOS[@]}" | LC_ALL=C sort" exactly.
stats_filter_pagebases() {
    printf '%s\n' "${!STATS_FILTER_PHOTOS[@]}" | LC_ALL=C sort
}

# ----------------------------------------------------------------------------
# Per-category count accessors (task or0)
# ----------------------------------------------------------------------------
# The stats overview renders each category from its STATS_CATEGORIES spec, whose
# first field names that category's count array (STATS_CAMERAS, STATS_ISO, ...).
# The render handlers used to nameref that array directly; they now ask the
# aggregator through these accessors, so the count arrays stay private here.
# array_name is the registry's count_array field (a trusted internal name); the
# accessors index it via a local nameref.

# Print the count stored for one bucket key, or the empty string when the bucket
# never occurred. Mirrors the render side's former "${counts_ref[$key]:-}" lookup
# so an absent bucket reads as empty (skipped) and a present one reads as its
# positive count.
stats_category_count() {
    local -n _stats_counts_ref="$1"; shift
    local -r key="$1"; shift

    printf '%s' "${_stats_counts_ref[$key]:-}"
}

# Print the number of buckets that occurred in a category's count array (0 when
# empty). Encapsulates the "${#counts_ref[@]}" size read the render handlers use
# to skip an empty category's whole section.
stats_category_size() {
    local -n _stats_counts_ref="$1"; shift

    printf '%d' "${#_stats_counts_ref[@]}"
}

# Print the largest count in a category's array, or 0 when it is empty. Used to
# scale each section's bars relative to its own busiest bucket. Encapsulates the
# render side's former _stats_max_count loop over the array's values.
stats_category_max() {
    local -n _stats_counts_ref="$1"; shift
    local key
    local -i max=0

    for key in "${!_stats_counts_ref[@]}"; do
        if (( _stats_counts_ref[key] > max )); then
            max=${_stats_counts_ref[$key]}
        fi
    done
    printf '%d' "$max"
}

# Print a category's bucket keys ordered by descending count (ties broken by key)
# so the busiest bucket leads. Encapsulates the render side's former
# _stats_keys_by_count_desc. LC_ALL=C pins the tie-break collation so the
# generated page is byte-identical across locales/machines.
stats_category_keys_by_count_desc() {
    local -n _stats_counts_ref="$1"; shift
    local key

    for key in "${!_stats_counts_ref[@]}"; do
        printf '%d\t%s\n' "${_stats_counts_ref[$key]}" "$key"
    done | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
}
