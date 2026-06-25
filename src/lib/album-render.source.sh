# Album page orchestration. After the ar0 split this module owns only the page
# assembly and the job plumbing: it builds the preview pages, the per-photo
# view/details pages, the navigation redirects and the index/splash, driving the
# job_pool_* pool so pages render in parallel. The three concerns it used to
# bundle now live in siblings, all sourced before this file:
#   - album-tile-layout.source.sh   (tile_layout_for/build_tile_block/...)
#   - album-thumbnail-html.source.sh (build_preview_thumbnail/append_preview_grid)
#   - album-photo-select.source.sh  (album_photo_files/album_page_records/splash)
# The generic "pick one seeded-random photo from a dir" used for page backgrounds
# now comes from the shared pick_random_photo (photo-list.source.sh, task br0).
# This module calls into all of these at runtime; all libs are sourced before any
# code runs, so the cross-module calls resolve regardless of source order.
#
# Maps each album photo filename to its view-page basename ("<page>-<preview>")
# as assigned during render_album_pages. Declared globally so it always exists
# for the accessor even when no album was rendered.
#
# This is the album module's PRIVATE backing store (task pn0). Outside callers
# must NOT index it directly: use the album_view_page_for_photo accessor below.
# Keeping the map private behind a documented function decouples consumers (the
# stats filter mini-albums) from how the album internally names or caches view
# pages, so a change to the page-naming scheme stays contained in this module.
declare -gA ALBUM_VIEW_PAGE_BY_PHOTO=()

# Public album API (task pn0): return the view-page basename for a photo, or the
# empty string when the photo was not rendered into the album. The stats filter
# mini-albums call this to link each photo's "Details" to the album's own
# details page, instead of reaching into ALBUM_VIEW_PAGE_BY_PHOTO directly.
album_view_page_for_photo() {
    local -r photo="$1"; shift

    printf '%s' "${ALBUM_VIEW_PAGE_BY_PHOTO[$photo]:-}"
}

start_preview_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_name="$1"; shift
    local -r header_bar="$1"; shift
    local background_image

    background_image=$(pick_random_photo "$photos_dir" "$page_name")
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

# Assemble one complete preview page (page-N.html) in a single call: header,
# optional previous-page link, every thumbnail in order, then the footer (with
# a next-page link unless this is the last page). The appends to the one page
# file happen here, in sequence, so the per-page ordering is preserved even when
# this whole function runs as one backgrounded render job (parallelism is only
# ACROSS pages, never within a page). The page's photos are the trailing
# positional arguments; each photo's preview index is its 1-based position.
render_full_preview_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_name="$1"; shift
    local -r page_num="$1"; shift
    local -r header_bar="$1"; shift
    local -r prev_page="$1"; shift
    local -r next_page="$1"; shift

    start_preview_page \
        "$photos_dir" "$html_dir" "$blurs_dir" "$backhref" "$page_name" \
        "$header_bar"
    if [ -n "$prev_page" ]; then
        render_previous_page_link "$page_name" "$html_dir" "$prev_page"
    fi

    # Batch all of this page's thumbnails into ONE template call. Building the
    # markup in bash and emitting it via the raw "preview_thumbs" field collapses
    # what used to be N "template preview" renders (one env -i bash per
    # thumbnail) into a single previewpage render per page. append_preview_grid
    # also groups the page's photos into tiles (some subdivided into smaller
    # thumbnails), so the per-page ordering and preview numbering stay here.
    local preview_thumbs=''
    # The album's last page (no "next" link) is the only one allowed to widen a
    # leftover final tile to a full row, so a short final page stays flush.
    local fill_last='no'
    if [ -z "$next_page" ]; then
        fill_last='yes'
    fi
    # The main album's view pages are "<page_num>-<preview_num>.html", so the
    # shared grid builder gets "<page_num>-" as the href prefix.
    append_preview_grid preview_thumbs \
        "$thumbs_dir" "$backhref" "$page_num-" "$fill_last" "$@"
    template previewpage "$page_name.html" \
        html_dir "$html_dir" \
        preview_thumbs "$preview_thumbs"

    if [ -n "$next_page" ]; then
        finish_preview_page_with_next \
            "$page_name" "$html_dir" "$backhref" "$tarball_name" \
            "$next_page" "$prev_page"
    else
        finish_preview_page "$page_name" "$html_dir" "$backhref" "$tarball_name"
    fi
}

# Enqueue one complete preview page as a background render job in the given job
# pool (throttled to IMAGE_JOBS). Mirrors queue_album_view_render_job: job_pool_submit
# waits for a free slot, backgrounds the whole-page assembly, and tracks its
# pid/label so a failed job is reported by job_pool_wait and makes generation
# fail loudly. The page's photos are passed as trailing positional args; the
# background subshell forks a private copy of them, so the caller is free to
# reuse its per-page accumulator for the next page.
queue_preview_page_render_job() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_name="$1"; shift
    local -r page_num="$1"; shift
    local -r header_bar="$1"; shift
    local -r prev_page="$1"; shift
    local -r next_page="$1"; shift
    local -r pool="$1"; shift
    # Remaining positional args ("$@") are this page's photos in order.

    job_pool_submit "$pool" "template render job for preview $page_name" \
        render_full_preview_page \
        "$photos_dir" \
        "$html_dir" \
        "$thumbs_dir" \
        "$blurs_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_name" \
        "$page_num" \
        "$header_bar" \
        "$prev_page" \
        "$next_page" \
        "$@"
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
    local exif_tooltip_text

    template header "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        blurs_dir "$blurs_dir" \
        background_image "$photo_file" \
        show_header_bar 'no'

    animation_class=$(random_animation_css_class fast "$photo_file")
    # Reuse the same EXIF tooltip as the details page so hovering the image in
    # the normal view shows the camera/exposure summary (reads the shared
    # identify cache, so no extra ImageMagick work).
    exif_tooltip_text=$(
        photo_exif_tooltip_text "$photo_file" "$INCOMING_DIR/$photo_file"
    )
    template view "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        photos_dir "$photos_dir" \
        page_num "$page_num" \
        preview_num "$preview_num" \
        photo "$photo_file" \
        animation_class "$animation_class" \
        exif_tooltip "$exif_tooltip_text"
    template footer "$page_num-$preview_num.html" \
        html_dir "$html_dir" \
        backhref "$backhref" \
        tarball_name "$tarball_name"
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

# Render every navigation redirect for a single view page (the prev/next
# wrap-around stubs that bounce N-0 / N-(last+1) to the neighbouring page).
# Each redirect is its own self-contained file (the template overwrites it), so
# this whole group is safe to run as one independent background job; only the
# files for distinct pages are produced here. The wrap-around redirects for the
# very last page (0-MAXPREVIEWS and the loop-to-1 links) are emitted as part of
# that page's group.
render_page_view_redirects() {
    local -r html_dir="$1"; shift
    local -ri page="$1"; shift
    local -ri lastview="$1"; shift
    local -ri max_page="$1"; shift
    local -r prevredirect="${page}-0"
    local -r nextredirect="${page}-$(( lastview + 1 ))"

    template redirect "$prevredirect.html" \
        html_dir "$html_dir" \
        redirect_page "$(( page - 1 ))-${MAXPREVIEWS}"
    template redirect "$prevredirect-details.html" \
        html_dir "$html_dir" \
        redirect_page "$(( page - 1 ))-${MAXPREVIEWS}-details"

    if (( page == max_page )); then
        template redirect "0-$MAXPREVIEWS.html" \
            html_dir "$html_dir" \
            redirect_page "${page}-$lastview"
        template redirect "0-$MAXPREVIEWS-details.html" \
            html_dir "$html_dir" \
            redirect_page "${page}-$lastview-details"
        template redirect "$nextredirect.html" \
            html_dir "$html_dir" \
            redirect_page '1-1'
        template redirect "$nextredirect-details.html" \
            html_dir "$html_dir" \
            redirect_page '1-1-details'
    else
        template redirect "$nextredirect.html" \
            html_dir "$html_dir" \
            redirect_page "$(( page + 1 ))-1"
        template redirect "$nextredirect-details.html" \
            html_dir "$html_dir" \
            redirect_page "$(( page + 1 ))-1-details"
    fi
}

# Render all navigation redirects in parallel, one background job per view page,
# throttled to IMAGE_JOBS via the shared template render job pool. This blocks
# until every redirect is on disk (and fails loudly if any job failed), so
# callers can rely on the redirects existing once it returns -- the redirect
# groups are mutually independent, so only timing changes, not output.
render_view_redirects() {
    local -r html_dir="$1"; shift
    # shellcheck disable=SC2178
    local -n view_pages_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n redirect_last_views_ref="$1"; shift
    local max_page
    local page

    if (( ${#view_pages_ref[@]} == 0 )); then
        return
    fi

    # Render job pool (max IMAGE_JOBS concurrent), addressed by the single handle
    # "render_jobs". job_pool_wait returns 1 if any render job failed.
    job_pool_init render_jobs

    max_page=${view_pages_ref[$(( ${#view_pages_ref[@]} - 1 ))]}

    for page in "${view_pages_ref[@]}"; do
        job_pool_submit render_jobs \
            "template render job for redirect page $page" \
            render_page_view_redirects \
            "$html_dir" "$page" "${redirect_last_views_ref[$page]}" \
            "$max_page"
    done

    job_pool_wait render_jobs
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

    if [ "$SPLASH_PAGE" = yes ]; then
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

queue_album_view_render_job() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo="$1"; shift
    local -r pool="$1"; shift

    job_pool_submit "$pool" "template render job for photo $photo" \
        render_photo_view_and_details \
        "$photos_dir" \
        "$blurs_dir" \
        "$html_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_num" \
        "$preview_num" \
        "$photo"
}

# Per-photo bookkeeping shared by the album loop: queue the view+details render
# job, record the page/preview as a rendered view page (for redirect generation)
# and remember the photo -> view-page mapping for the stats mini-albums. Kept
# separate from the preview-page assembly so each concern stays small.
_album_record_view_photo() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift
    local -ri page_num="$1"; shift
    local -ri preview_num="$1"; shift
    local -r photo="$1"; shift
    local -r pool="$1"; shift
    local -r view_pages_name="$1"; shift
    local -r last_views_name="$1"; shift

    queue_album_view_render_job \
        "$photos_dir" "$blurs_dir" "$html_dir" "$backhref" "$tarball_name" \
        "$page_num" "$preview_num" "$photo" \
        "$pool"
    record_rendered_view_page "$view_pages_name" "$last_views_name" \
        "$page_num" "$preview_num"
    # Read later through the album_view_page_for_photo accessor (e.g. by the
    # stats filter mini-albums for their Details links); shellcheck cannot see
    # that cross-function use.
    # shellcheck disable=SC2034
    ALBUM_VIEW_PAGE_BY_PHOTO["$photo"]="$page_num-$preview_num"
}

render_album_pages() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r tarball_name="$1"; shift

    local header_bar
    local name
    local next_name
    local page_num
    local photo
    local prev_name=''
    local record
    local -i preview_num
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -A rendered_last_views=()
    # shellcheck disable=SC2034
    local -a rendered_view_pages=()
    local -a page_photos=()
    local -a page_records=()

    # Render job pool (max IMAGE_JOBS concurrent), addressed by the single handle
    # "render_jobs". job_pool_wait returns 1 if any render job failed.
    job_pool_init render_jobs

    # Rebuild the photo -> view-page map for this album from scratch so a
    # re-generate (or a smaller incoming set) does not keep stale entries. The
    # per-photo entries are written in _album_record_view_photo, which shellcheck
    # cannot see from here.
    # shellcheck disable=SC2034
    ALBUM_VIEW_PAGE_BY_PHOTO=()

    # Materialise the full deterministic page layout first so each preview page
    # knows up front whether it has a following page (and thus a "next" link).
    mapfile -t page_records < <(album_page_records "$photos_dir")

    for record in "${page_records[@]}"; do
        page_num=${record%%$'\t'*}
        name=$(album_page_name "$page_num")
        # The first page shows the header bar; later pages do not (matches the
        # previous start_preview_page calls).
        if [ -z "$prev_name" ]; then
            header_bar='yes'
        else
            header_bar='no'
        fi

        # Split the tab-separated photo list for this page into an array.
        IFS=$'\t' read -r -a page_photos <<< "${record#*$'\t'}"

        preview_num=0
        for photo in "${page_photos[@]}"; do
            (( ++preview_num ))
            _album_record_view_photo \
                "$photos_dir" "$blurs_dir" "$html_dir" "$backhref" \
                "$tarball_name" "$page_num" "$preview_num" "$photo" \
                render_jobs rendered_view_pages rendered_last_views
        done

        # A page has a "next" link unless it is the last record.
        next_name=''
        if (( page_num < ${#page_records[@]} )); then
            next_name=$(album_page_name "$(( page_num + 1 ))")
        fi
        queue_preview_page_render_job \
            "$photos_dir" "$html_dir" "$thumbs_dir" "$blurs_dir" "$backhref" \
            "$tarball_name" "$name" "$page_num" "$header_bar" \
            "$prev_name" "$next_name" \
            render_jobs \
            "${page_photos[@]}"

        prev_name="$name"
    done

    if ! job_pool_wait render_jobs; then
        return 1
    fi
    render_view_redirects "$html_dir" rendered_view_pages rendered_last_views
    render_album_index "$photos_dir" "$html_dir" "$blurs_dir" "$backhref"
}
