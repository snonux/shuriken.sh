# Maps each album photo filename to its view-page basename ("<page>-<preview>")
# as assigned during render_album_pages. The stats filter mini-albums read this
# so each view page can link "Details" to the album's own details page for the
# photo. Declared globally so it always exists for callers even when no album
# was rendered.
declare -gA ALBUM_VIEW_PAGE_BY_PHOTO=()

album_photo_files() {
    local -r photos_dir="$1"; shift

    find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
        | maybe_shuffle
}

start_preview_page() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_name="$1"; shift
    local -r header_bar="$1"; shift
    local background_image

    background_image=$(randomphoto "$photos_dir" "$page_name")
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
    local -i preview_num=0
    local photo

    start_preview_page \
        "$photos_dir" "$html_dir" "$blurs_dir" "$backhref" "$page_name" \
        "$header_bar"
    if [ -n "$prev_page" ]; then
        render_previous_page_link "$page_name" "$html_dir" "$prev_page"
    fi

    # Batch all of this page's thumbnails into ONE template call. Building the
    # markup in bash and emitting it via the raw "preview_thumbs" field collapses
    # what used to be N "template preview" renders (one env -i bash per
    # thumbnail) into a single previewpage render per page.
    local preview_thumbs=''
    for photo in "$@"; do
        (( ++preview_num ))
        append_preview_thumbnail preview_thumbs \
            "$thumbs_dir" "$backhref" "$page_num" "$preview_num" "$photo"
    done
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

# Enqueue one complete preview page as a background render job, throttled to
# IMAGE_JOBS via the shared template render job pool. Mirrors
# queue_album_view_render_job: wait for a free slot, background the whole-page
# assembly, then track its pid/label so a failed job flips render_failed and
# makes generation fail loudly. The page's photos are passed as trailing
# positional args; the background subshell forks a private copy of them, so the
# caller is free to reuse its per-page accumulator for the next page.
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
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_statuses_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot and assigned below.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_labels_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift
    # Remaining positional args ("$@") are this page's photos in order.

    wait_for_template_render_job_slot \
        render_job_pids_ref \
        render_job_statuses_ref \
        render_job_labels_ref \
        render_failed_ref
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
        "$@" &
    render_job_pids_ref+=("$!")
    render_job_labels_ref["$!"]="template render job for preview $page_name"
}

# Append one thumbnail's markup to a page's accumulating thumbnail-grid buffer.
# Produces exactly the bytes the old per-thumbnail preview.tmpl emitted (the
# <a name=... href=...><img class='thumb <anim>' .../></a> block), so batching
# all thumbnails into one previewpage render stays byte-identical. Every
# interpolated value is HTML-escaped like the template's context_html fields; the
# seeded "slow" animation class is preserved exactly. Blocks are separated by a
# newline; the previewpage template adds the single trailing newline, matching
# the old N sequential renders.
append_preview_thumbnail() {
    local -n buffer_ref="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local animation_class
    local block

    animation_class=$(random_animation_css_class slow "$photo_file")
    block=$(build_preview_thumbnail \
        "$thumbs_dir" "$backhref" "$page_num" "$preview_num" "$photo_file" \
        "$animation_class")
    if [ -z "$buffer_ref" ]; then
        buffer_ref="$block"
    else
        buffer_ref+=$'\n'"$block"
    fi
}

# Render the HTML for a single preview thumbnail (HTML-escaping every value the
# way preview.tmpl's context_html fields did). Returned without a trailing
# newline so callers control separators.
build_preview_thumbnail() {
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r page_num="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local -r animation_class="$1"; shift
    local photo_html
    local anim_html
    local backhref_html
    local thumbs_dir_html

    photo_html=$(_html_escape "$photo_file")
    anim_html=$(_html_escape "$animation_class")
    backhref_html=$(_html_escape "$backhref")
    thumbs_dir_html=$(_html_escape "$thumbs_dir")
    printf '<a name=%s href=%s>\n' \
        "'$photo_html'" "'$page_num-$preview_num.html'"
    printf "  <img class='thumb %s' src='%s/%s/%s' />\n</a>" \
        "$anim_html" "$backhref_html" "$thumbs_dir_html" "$photo_html"
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
    # Render job pool, throttled to IMAGE_JOBS by the job-pool helpers.
    # shellcheck disable=SC2034
    local -a render_job_pids=()
    # shellcheck disable=SC2034
    local -A render_job_statuses=()
    # shellcheck disable=SC2034
    local -A render_job_labels=()
    local -i render_failed=0

    if (( ${#view_pages_ref[@]} == 0 )); then
        return
    fi

    max_page=${view_pages_ref[$(( ${#view_pages_ref[@]} - 1 ))]}

    for page in "${view_pages_ref[@]}"; do
        wait_for_template_render_job_slot \
            render_job_pids render_job_statuses render_job_labels render_failed
        render_page_view_redirects \
            "$html_dir" "$page" "${redirect_last_views_ref[$page]}" \
            "$max_page" &
        render_job_pids+=("$!")
        # shellcheck disable=SC2034
        render_job_labels["$!"]="template render job for redirect page $page"
    done

    wait_for_template_render_jobs \
        render_job_pids render_job_statuses render_job_labels render_failed
    if (( render_failed != 0 )); then
        return 1
    fi
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
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_statuses_ref="$1"; shift
    # Passed by name to wait_for_template_render_job_slot and assigned below.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_labels_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_job_slot \
        render_job_pids_ref \
        render_job_statuses_ref \
        render_job_labels_ref \
        render_failed_ref
    render_photo_view_and_details \
        "$photos_dir" \
        "$blurs_dir" \
        "$html_dir" \
        "$backhref" \
        "$tarball_name" \
        "$page_num" \
        "$preview_num" \
        "$photo" &
    render_job_pids_ref+=("$!")
    render_job_labels_ref["$!"]="template render job for photo $photo"
}

wait_for_album_view_render_jobs() {
    # shellcheck disable=SC2178
    local -n render_job_pids_ref="$1"; shift
    # Passed by name to wait_for_template_render_jobs.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_statuses_ref="$1"; shift
    # Passed by name to wait_for_template_render_jobs.
    # shellcheck disable=SC2034,SC2178
    local -n render_job_labels_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n render_failed_ref="$1"; shift

    wait_for_template_render_jobs \
        render_job_pids_ref \
        render_job_statuses_ref \
        render_job_labels_ref \
        render_failed_ref
    if (( render_failed_ref != 0 )); then
        return 1
    fi
}

# Group the album's photos into pages of at most MAXPREVIEWS, in their final
# (shuffled/sorted) order. The result is emitted one line per page as a
# tab-separated record "<page_num>\t<photo>\t<photo>..." so the caller can walk
# pages without keeping every page in memory at once. Order is fully
# deterministic (album_photo_files already applies the seeded shuffle), so the
# downstream parallelism only changes timing, never which photo lands where.
album_page_records() {
    local -r photos_dir="$1"; shift
    local photo
    local -i num=1
    local -i count=0
    local line=''

    while IFS= read -r photo; do
        if (( count == MAXPREVIEWS )); then
            printf '%d\t%s\n' "$num" "$line"
            (( ++num ))
            count=0
            line=''
        fi
        if (( count == 0 )); then
            line="$photo"
        else
            line="$line"$'\t'"$photo"
        fi
        (( ++count ))
    done < <(album_photo_files "$photos_dir")

    if (( count > 0 )); then
        printf '%d\t%s\n' "$num" "$line"
    fi
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
    local -r pids_name="$1"; shift
    local -r statuses_name="$1"; shift
    local -r labels_name="$1"; shift
    local -r failed_name="$1"; shift
    local -r view_pages_name="$1"; shift
    local -r last_views_name="$1"; shift

    queue_album_view_render_job \
        "$photos_dir" "$blurs_dir" "$html_dir" "$backhref" "$tarball_name" \
        "$page_num" "$preview_num" "$photo" \
        "$pids_name" "$statuses_name" "$labels_name" "$failed_name"
    record_rendered_view_page "$view_pages_name" "$last_views_name" \
        "$page_num" "$preview_num"
    # Read later by the stats filter mini-albums (render_filter_pages) for
    # their Details links; shellcheck cannot see that cross-function use.
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
    # Passed by name to the render-pool helpers below.
    # shellcheck disable=SC2034
    local -i render_failed=0
    # shellcheck disable=SC2034
    local -a render_job_pids=()
    # shellcheck disable=SC2034
    local -A render_job_labels=()
    # shellcheck disable=SC2034
    local -A render_job_statuses=()
    # Passed by name to record_rendered_view_page and render_view_redirects.
    # shellcheck disable=SC2034
    local -A rendered_last_views=()
    # shellcheck disable=SC2034
    local -a rendered_view_pages=()
    local -a page_photos=()
    local -a page_records=()

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
                render_job_pids render_job_statuses render_job_labels \
                render_failed rendered_view_pages rendered_last_views
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
            render_job_pids render_job_statuses render_job_labels \
            render_failed \
            "${page_photos[@]}"

        prev_name="$name"
    done

    if ! wait_for_album_view_render_jobs \
        render_job_pids \
        render_job_statuses \
        render_job_labels \
        render_failed; then
        return 1
    fi
    render_view_redirects "$html_dir" rendered_view_pages rendered_last_views
    render_album_index "$photos_dir" "$html_dir" "$blurs_dir" "$backhref"
}

splash_photo_files() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local photo

    while IFS= read -r photo; do
        if [ -f "$DIST_DIR/$blurs_dir/$photo" ]; then
            printf '%s\n' "$photo"
        fi
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )
}

random_splash_photo() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -i index
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(splash_photo_files "$photos_dir" "$blurs_dir")

    if (( ${#photos[@]} == 0 )); then
        printf 'ERROR: No splash photos found in %s with matching blurs in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" \
            "$(_display_path "$DIST_DIR/$blurs_dir")" >&2
        return 1
    fi

    index=$(random_index "photo:$photos_dir:splash" "${#photos[@]}")
    printf '%s\n' "${photos[index]}"
}

randomphoto() {
    local -r photos_dir="$1"; shift
    local -r context="${1:-$photos_dir}"
    local -i index
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )

    if (( ${#photos[@]} == 0 )); then
        printf 'ERROR: No photos found in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" >&2
        return 1
    fi

    index=$(random_index "photo:$photos_dir:$context" "${#photos[@]}")
    printf '%s\n' "${photos[index]}"
}
