# Per-filter mini-album page rendering. Split out of stats.source.sh (task cn0)
# so this concern is separate from the EXIF aggregation (stats-aggregate.source.sh)
# and the stats overview page (stats-render.source.sh). Every tallied bucket
# becomes a clickable mini album under dist/stats/<pagebase>/. This module reads
# the STATS_FILTER_* globals filled by collect_photo_exif_stats and resolves each
# photo's album view page through the album_view_page_for_photo accessor (task
# pn0) instead of indexing the album's private ALBUM_VIEW_PAGE_BY_PHOTO global,
# so stats stays decoupled from album-internal page naming/caching. All libs are
# sourced before run so cross-module references resolve.

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
# to the album's own details page via the album_view_page_for_photo accessor.
# Pages render in
# parallel through the shared job pool, throttled to IMAGE_JOBS. The galleries
# reuse camera.tmpl and the view pages reuse cameraview.tmpl.

# Dist-relative subdirectories holding the shared full-size images, thumbnails
# and blurred backgrounds, matching the literals generate() passes to
# render_album_pages so filter pages reuse the same asset files.
declare -gr STATS_PHOTOS_DIR='photos'
declare -gr STATS_THUMBS_DIR='thumbs'
declare -gr STATS_BLURS_DIR='blurs'
# Everything stats-related lives under this dist subdirectory so the album root
# only holds the main album: the stats overview is stats/index.html and each
# filter mini-album is stats/<pagebase>/ (gallery index.html + view pages
# <index>.html). This keeps the file count in any single directory bounded.
declare -gr STATS_DIR='stats'
# Relative path from a filter mini-album page (dist/stats/<pagebase>/...) back to
# the album root (dist/), used for shared assets and album links.
declare -gr STATS_FILTER_BACKHREF='../..'

# Emit one thumbnail anchor for a filter gallery: a thumb image (from thumbs/)
# linking to this filter's view page for that photo (<pagebase>--<index>.html).
# The photo filename is HTML-escaped; the pagebase and index are filename-safe.
_stats_filter_thumbnail() {
    local -r backhref_html="$1"; shift
    local -ri index="$1"; shift
    local -r photo="$1"; shift
    local photo_html
    local animation_class

    photo_html=$(_html_escape "$photo")
    # Same seeded animation the album thumbnail uses for this photo.
    animation_class=$(random_animation_css_class slow "$photo")
    # The view page sits in the same directory as this gallery, so link to it by
    # bare index; the thumbnail image lives at the album root via backhref.
    printf '        <a name="%s" href="%d.html">' "$photo_html" "$index"
    printf '<img class="thumb %s" src="%s/%s/%s" /></a>\n' \
        "$animation_class" "$backhref_html" "$STATS_THUMBS_DIR" "$photo_html"
}

# Build the full thumbnail grid for one filter from its newline-separated photo
# list, preserving aggregation (encounter) order for deterministic output.
_stats_build_filter_thumbs() {
    local -r backhref_html="$1"; shift
    local -r photos="$1"; shift
    local photo
    local -i index=0

    while IFS= read -r photo; do
        if [ -n "$photo" ]; then
            (( ++index ))
            _stats_filter_thumbnail "$backhref_html" "$index" "$photo"
        fi
    done <<< "$photos"
}

# Render a filter gallery page (<pagebase>.html): header + camera.tmpl (heading +
# pre-built thumbnail grid) + footer. camera.tmpl is reused for every filter; the
# heading is the bucket's title (camera name, "ISO 400", "Year 2023", ...).
# Each filter mini-album lives in its own directory stats/<pagebase>/, so the
# gallery is index.html and the view pages are <index>.html. backhref is fixed
# (../.. back to the album root). camera.tmpl/cameraview.tmpl are reused.
_stats_render_filter_gallery() {
    local -r pagebase="$1"; shift
    local thumbs
    local background_image
    local -r html_dir="$STATS_DIR/$pagebase"
    local -r backhref="$STATS_FILTER_BACKHREF"
    local -r backhref_html="$STATS_FILTER_BACKHREF"
    local -r title="${STATS_FILTER_TITLE[$pagebase]:-}"

    thumbs=$(_stats_build_filter_thumbs \
        "$backhref_html" "${STATS_FILTER_PHOTOS[$pagebase]}")
    # Background fits the category: a random photo from this filter's own set,
    # mirroring how the album preview pages pick a random album photo.
    background_image=$(_stats_pick_background \
        "$pagebase" "${STATS_FILTER_PHOTOS[$pagebase]}")
    template header index.html \
        html_dir "$html_dir" backhref "$backhref" \
        blurs_dir "$STATS_BLURS_DIR" background_image "$background_image" \
        show_header_bar 'yes'
    template camera index.html \
        html_dir "$html_dir" backhref "$backhref" \
        camera_name "$title" camera_thumbs "$thumbs"
    template footer index.html \
        html_dir "$html_dir" backhref "$backhref" tarball_name ''
}

# Render one filter view page (<pagebase>--<index>.html): header + cameraview
# body + footer, with prev/next cycling within the filter.
_stats_render_filter_view_page() {
    local -r pagebase="$1"; shift
    local -r photo="$1"; shift
    local -ri index="$1"; shift
    local -ri prev="$1"; shift
    local -ri next="$1"; shift
    local body
    local background_image
    local -r html_dir="$STATS_DIR/$pagebase"
    local -r backhref="$STATS_FILTER_BACKHREF"
    local -r page="$index.html"

    body=$(_stats_build_filterview_body \
        "$STATS_FILTER_BACKHREF" "$photo" "$prev" "$next")
    # The view page's blurred background is the photo it shows, exactly like the
    # album view pages.
    background_image="$photo"
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
    view_page=$(album_view_page_for_photo "$photo")
    if [ -n "$view_page" ]; then
        details_link=$(printf ' <a href="%s/%s-details.html">Details</a> |' \
            "$backhref_html" "$view_page")
    fi
    _stats_print_filterview_body "$backhref_html" "$photo_html" \
        "$animation_class" "$tooltip_attr" "$details_link" "$prev" "$next"
}

# Emit the filter view page markup. Split out so _stats_build_filterview_body
# stays focused on assembling the pieces.
# The prev/next/gallery links are same-directory (this view page lives in the
# filter's own stats/<pagebase>/ dir); the image, details, and direct links go
# back to the album root via backhref.
_stats_print_filterview_body() {
    local -r backhref_html="$1"; shift
    local -r photo_html="$1"; shift
    local -r animation_class="$1"; shift
    local -r tooltip_attr="$1"; shift
    local -r details_link="$1"; shift
    local -ri prev="$1"; shift
    local -ri next="$1"; shift

    cat <<END
<div class='view'>
    <a href="$next.html">
        <img class='view $animation_class' border='0' src='$backhref_html/$STATS_PHOTOS_DIR/$photo_html'$tooltip_attr />
    </a>
    <div class="navigator">
        <a href="$prev.html" class="arrow">&lArr;</a>
        <a href="index.html">Gallery</a> |$details_link
        <a href="$backhref_html/$STATS_PHOTOS_DIR/$photo_html">Direct link</a>
        <a href="$next.html" class="arrow">&rArr;</a>
    </div>
</div>
END
}

# Enqueue one filter's mini-album (gallery + a view page per photo) onto the
# shared render job pool, waiting for a free slot (<= IMAGE_JOBS) before each
# background render so parallelism follows the configured IMAGE_JOBS.
_stats_enqueue_filter_album() {
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
    _stats_render_filter_gallery "$pagebase" &
    pids_ref+=("$!")
    labels_ref["$!"]="filter gallery $pagebase"

    for (( i = 1; i <= n; i++ )); do
        wait_for_template_render_job_slot \
            "$pids_name" "$statuses_name" "$labels_name" "$failed_name"
        _stats_render_filter_view_page \
            "$pagebase" "${photo_list[i - 1]}" "$i" \
            "$(( i == 1 ? n : i - 1 ))" "$(( i == n ? 1 : i + 1 ))" &
        pids_ref+=("$!")
        labels_ref["$!"]="filter view $pagebase/$i"
    done
}

# Public entry point: render every filter mini-album in parallel. Call
# collect_photo_exif_stats first to fill STATS_FILTER_PHOTOS. html_dir is the
# dist-relative output dir ("." for a top-level album) and backhref the relative
# path back to the album root ("."), the same values render_stats_page uses.
# Pagebases are walked in LC_ALL=C order for reproducible enqueue order.
# Render every filter mini-album under dist/stats/<pagebase>/ in parallel. Each
# mini-album's location and backhref are fixed by the layout (see STATS_DIR /
# STATS_FILTER_BACKHREF), so no path arguments are needed. Call
# collect_photo_exif_stats first to fill STATS_FILTER_PHOTOS.
render_filter_pages() {
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
    while IFS= read -r pagebase; do
        _stats_enqueue_filter_album "$pagebase" \
            render_job_pids render_job_statuses render_job_labels render_failed
    done < <(printf '%s\n' "${!STATS_FILTER_PHOTOS[@]}" | LC_ALL=C sort)
    wait_for_template_render_jobs \
        render_job_pids render_job_statuses render_job_labels render_failed
    if (( render_failed != 0 )); then
        return 1
    fi
}
