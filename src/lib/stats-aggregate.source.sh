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
#   STATS_YEARS[<YYYY>]                = count
#   STATS_MONTHS[<01..12>]             = count
#   STATS_MEGAPIXELS[<bucket>]         = count           (e.g. "10-20MP")
#   STATS_ASPECT[<bucket>]             = count           (e.g. "3:2")
#   STATS_ORIENTATION[<bucket>]        = count           (Landscape/Portrait/Square)
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
#                  ranked  - count-desc bars (camera leaderboard, years).
#                  ordered - fixed bucket-ladder order from
#                            STATS_CATEGORY_BUCKETS (megapixels wide->narrow, ...).
#                  month   - calendar Jan..Dec order with English month names.
#   list_class   optional extra <ul> CSS class for the 'ranked' kind. The camera
#                leaderboard passes 'stats-leaderboard' (data-only difference, so
#                no separate camera render kind); other ranked categories omit it.
#
# The array order IS the overview/body display order, so it must reproduce the
# historical _stats_build_body sequence exactly (camera, year, month, then the
# dimension histograms). The per-category record functions stay grouped by EXIF
# source affinity (one datetime parser fills year+month, one dimension parser
# fills three histograms) and are dispatched from STATS_RECORD_FUNCTIONS below;
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
    'STATS_MEGAPIXELS|megapixels|Megapixels|ordered'
    'STATS_ASPECT|aspect|Aspect ratio|ordered'
    'STATS_ORIENTATION|orientation|Orientation|ordered'
)

# Bucket ladders for the 'ordered' categories, keyed by their count_array name.
# Tab-delimited because the bucket labels themselves contain spaces and slashes
# (but never tabs). These reproduce the photographer-friendly axis order the
# aggregator's *_bucket helpers emit, so the histogram axes read naturally
# regardless of how many photos landed in each bucket.
declare -gA STATS_CATEGORY_BUCKETS=(
    [STATS_MEGAPIXELS]=$'under 2MP\t2-5MP\t5-10MP\t10-20MP\t20-40MP\t40-80MP\tover 80MP'
    [STATS_ASPECT]=$'3:2\t4:3\t16:9\t1:1\t5:4\tother'
    [STATS_ORIENTATION]=$'Landscape\tPortrait\tSquare'
)

# The per-photo record functions, dispatched in order by accumulate_photo_stats.
# Each is grouped by EXIF source affinity (so one identify parse fills several
# related categories) and tallies into the STATS_* arrays named in
# STATS_CATEGORIES. Each takes the parsed values array plus the photo path.
# -g so the dispatch list survives a function-scoped source (see STATS_CATEGORIES).
declare -gra STATS_RECORD_FUNCTIONS=(
    _stats_record_camera
    _stats_record_datetime
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

# Tally a photo's camera (Make+Model) into the camera leaderboard count and
# filter mini-album. Skips photos with no Make/Model. The Make+Model dedup now
# lives in camera_label_from_make_model (metadata-label.source.sh, task mn0),
# shared with the album tooltip builder.
_stats_record_camera() {
    local -n values_ref="$1"; shift
    local -r photo="$1"; shift
    local label

    label=$(camera_label_from_make_model \
        "${values_ref[Make]:-}" "${values_ref[Model]:-}")
    _stats_tally STATS_CAMERAS camera "$label" "$label" "$photo"
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
# first field names that category's count array (STATS_CAMERAS, STATS_YEARS, ...).
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
    local -i value
    local -i max=0

    for key in "${!_stats_counts_ref[@]}"; do
        # Read the value through a quoted ${assoc[$key]} expansion FIRST, then
        # compare. Do NOT write "(( _stats_counts_ref[key] > max ))": inside an
        # arithmetic context an associative subscript is itself arithmetic-
        # evaluated, so a string key (e.g. "sony") resolves to an unset var -> 0,
        # i.e. it would always read index 0 and report max 0 (broken zero-width
        # bars). The string-keyed expansion below is the only correct read.
        value=${_stats_counts_ref[$key]}
        if (( value > max )); then
            max=$value
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
