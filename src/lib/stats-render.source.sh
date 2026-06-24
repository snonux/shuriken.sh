# Stats overview page rendering. Split out of stats.source.sh (task cn0) so the
# HTML/layout concern lives apart from the EXIF aggregation/bucketing (now in
# stats-aggregate.source.sh) and the per-filter mini-albums (now in
# stats-filter-album.source.sh). This module reads the STATS_* globals filled by
# collect_photo_exif_stats and turns them into the static stats overview page
# (bar charts, sections, camera leaderboard). All libs are sourced before run,
# so the STATS_* maps and the STATS_*_DIR constants defined in the sibling
# modules are available here at runtime.

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
        # The stats overview lives at stats/index.html and each mini-album at
        # stats/<pagebase>/index.html, so link relative to the overview.
        printf '<a href="%s/index.html">%s</a>' "$pagebase" "$label_html"
    else
        printf '%s' "$label_html"
    fi
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
# wide to narrow) rather than count ranking, so the axis reads naturally. The
# bucket ladder is read from STATS_CATEGORY_BUCKETS[array_name] (tab-delimited).
# Only buckets that actually occurred are emitted, and the whole section is
# skipped when none did. Bucket labels are internal/trusted but still escaped for
# safety.
_stats_render_ordered_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -r prefix="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local bucket
    local row_html
    local -a buckets=()
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    IFS=$'\t' read -r -a buckets <<< "${STATS_CATEGORY_BUCKETS[$array_name]}"
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading"
    for bucket in "${buckets[@]}"; do
        if [ -z "${counts_ref[$bucket]:-}" ]; then
            continue
        fi
        row_html=$(_stats_filter_link "$prefix" "$bucket" "$(_html_escape "$bucket")")
        _stats_bar_row "$row_html" "${counts_ref[$bucket]}" "$total" "$max"
    done
    _stats_section_close
}

# Render a section ranked by count. Used where there is no natural axis order:
# the camera leaderboard, years, lenses, and the decoded enum categories. An
# optional list_class adds an extra CSS class to the <ul> (the camera leaderboard
# passes 'stats-leaderboard' to space out its long, wrapping camera names).
_stats_render_ranked_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -r prefix="$1"; shift
    local -ri total="$1"; shift
    local -r list_class="${1:-}"
    local -n counts_ref="$array_name"
    local key
    local row_html
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading" "$list_class"
    while IFS= read -r key; do
        row_html=$(_stats_filter_link "$prefix" "$key" "$(_html_escape "$key")")
        _stats_bar_row "$row_html" "${counts_ref[$key]}" "$total" "$max"
    done < <(_stats_keys_by_count_desc "$array_name")
    _stats_section_close
}

# Render the per-month histogram in calendar order. The aggregator keys months
# by zero-padded number (01..12); this maps each to its English name so the axis
# is readable, and reuses the ordered-section omit-when-empty behaviour inline.
# Signature matches the other render kinds (heading array_name prefix total) so
# the registry dispatcher can call it uniformly.
_stats_render_month_section() {
    local -r heading="$1"; shift
    local -r array_name="$1"; shift
    local -r prefix="$1"; shift
    local -ri total="$1"; shift
    local -n counts_ref="$array_name"
    local -ra month_names=(
        '' January February March April May June July August
        September October November December )
    local -i month
    local key
    local -i max

    if (( ${#counts_ref[@]} == 0 )); then
        return
    fi
    max=$(_stats_max_count "$array_name")
    _stats_section_open "$heading"
    for (( month = 1; month <= 12; month++ )); do
        key=$(printf '%02d' "$month")
        if [ -z "${counts_ref[$key]:-}" ]; then
            continue
        fi
        _stats_bar_row \
            "$(_stats_filter_link "$prefix" "$key" "${month_names[$month]}")" \
            "${counts_ref[$key]}" "$total" "$max"
    done
    _stats_section_close
}

# Render one category from its registry spec. Dispatches on the spec's
# render_kind to the matching section renderer, all of which self-skip when their
# array is empty. This is the single per-category render path: a new category
# just needs a STATS_CATEGORIES entry (no new render branch here unless it needs
# a brand-new kind).
_stats_render_category() {
    local -r spec="$1"; shift
    local -ri total="$1"; shift
    local -a fields=()

    IFS='|' read -r -a fields <<< "$spec"
    local -r array_name="${fields[0]}"
    local -r prefix="${fields[1]}"
    local -r heading="${fields[2]}"
    local -r render_kind="${fields[3]}"

    case "$render_kind" in
        camera)
            _stats_render_ranked_section "$heading" "$array_name" "$prefix" \
                "$total" stats-leaderboard
            ;;
        ranked)
            _stats_render_ranked_section "$heading" "$array_name" "$prefix" \
                "$total"
            ;;
        ordered)
            _stats_render_ordered_section "$heading" "$array_name" "$prefix" \
                "$total"
            ;;
        month)
            _stats_render_month_section "$heading" "$array_name" "$prefix" \
                "$total"
            ;;
        *)
            printf 'ERROR: unknown stats render kind %q for %s\n' \
                "$render_kind" "$array_name" >&2
            return 1
            ;;
    esac
}

# Assemble the full stats body by iterating STATS_CATEGORIES in registry order
# (which IS the display order). Returns the HTML on stdout; render_stats_page
# captures it into the stats_body context var. Adding a category appends one
# registry entry -- no edit here.
_stats_build_body() {
    local -ri total="${STATS_TOTALS[photos]:-0}"
    local spec

    printf '<p class="stats-total">%d photos analysed.</p>\n' "$total"
    for spec in "${STATS_CATEGORIES[@]}"; do
        _stats_render_category "$spec" "$total"
    done
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
# Load the sorted photo list for blurred backgrounds once into a global. This
# runs for every filter page (thousands of them), so the per-call directory scan
# the picker would otherwise do dominates the build. render_filter_pages loads it
# before forking the render jobs so each background subshell inherits the
# populated array instead of rescanning. The listing reuses the shared
# list_photos (photo-list.source.sh); 2>/dev/null keeps the original behaviour of
# silently yielding an empty list when the photos directory does not exist (e.g.
# unit tests). The STATS_BG_PHOTOS_LOADED guard preserves the once-only caching,
# so there is no per-page re-listing regression.
_stats_load_background_photos() {
    if [ -n "${STATS_BG_PHOTOS_LOADED:-}" ]; then
        return
    fi
    declare -ga STATS_BG_PHOTOS=()
    local photo
    while IFS= read -r photo; do
        STATS_BG_PHOTOS+=("$photo")
    done < <(list_photos "$STATS_PHOTOS_DIR" 2>/dev/null)
    STATS_BG_PHOTOS_LOADED=yes
}

# Pick a seeded-random photo for a stats/camera page's blurred background from
# the cached photo list. Empty (plain black) when no photos exist. Shares the
# selection core (_pick_random_from_list, photo-list.source.sh); the
# "photo:<STATS_PHOTOS_DIR>:<context>" namespace is unchanged so determinism and
# the empty-string-on-empty degradation match the former inline code exactly.
_stats_random_background() {
    local -r context="$1"; shift

    _stats_load_background_photos
    # An empty list is a normal "no background" degrade, not an error: swallow the
    # picker's empty-list status (return 1) so the caller's set -e is unaffected,
    # exactly like the former inline "return" on an empty list.
    _pick_random_from_list "photo:$STATS_PHOTOS_DIR:$context" STATS_BG_PHOTOS \
        || return 0
}

# Pick a seeded-random photo from a newline-separated list (a filter's own
# photos) for a filter gallery's blurred background, so the background fits the
# category. Empty when the list is empty. Shares the selection core
# (_pick_random_from_list, photo-list.source.sh); the "photo:filter:<context>"
# namespace is unchanged so selection is identical to the former inline code.
_stats_pick_background() {
    local -r context="$1"; shift
    local -r photos="$1"; shift
    local -a list=()
    local photo

    while IFS= read -r photo; do
        [ -n "$photo" ] && list+=("$photo")
    done <<< "$photos"
    # Empty list -> no background; swallow the picker's empty status so the
    # caller's set -e is unaffected, matching the former inline "return".
    _pick_random_from_list "photo:filter:$context" list || return 0
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
