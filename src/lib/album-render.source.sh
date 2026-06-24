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
    # The main album's view pages are "<page_num>-<preview_num>.html", so the
    # shared grid builder gets "<page_num>-" as the href prefix.
    append_preview_grid preview_thumbs \
        "$thumbs_dir" "$backhref" "$page_num-" "$@"
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

# Build a whole thumbnail-grid buffer by walking a list of photos and grouping
# them into tiles. Most tiles are a single square thumbnail, but (controlled by
# THUMB_FEATURE_PERCENT / THUMB_SUBDIVIDE_PERCENT) some become a 2x2 feature tile
# or are subdivided into several smaller thumbnails. Each photo keeps its 1-based
# position as its preview number (tiling only groups CONSECUTIVE photos visually,
# never reorders them), so the view-page links stay correct. The view-page link
# is "${href_prefix}${preview_num}.html": the main album passes "<page_num>-"; the
# stats mini-albums pass "" (their view pages are bare "<index>.html"). This is
# the single shared grid builder for both the main preview pages and the stats
# mini-album galleries. Tile blocks are separated by a single newline; the
# template adds the trailing newline.
append_preview_grid() {
    local -n buffer_ref="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -a photos=("$@")
    local -i i=0
    local -i count
    local layout
    local block
    # Cap the big 2x2 feature tiles at this many per page; once reached, later
    # tiles are no longer offered the "feature" layout (they fall back to
    # subdivided/single), so a page never gets crowded with hero tiles.
    local -ri max_features=2
    local -i features_used=0

    while (( i < ${#photos[@]} )); do
        # Decide this tile's layout from the photos still available; the first
        # photo's name is the seeded-random context so the choice is stable.
        # Features are only offered until the per-page cap is reached.
        read -r layout count < <(
            tile_layout_for "$(( ${#photos[@]} - i ))" "${photos[i]}" \
                "$(( features_used < max_features ? 1 : 0 ))"
        )
        if [ "$layout" = feature ]; then
            (( ++features_used ))
        fi
        block=$(build_tile_block \
            "$thumbs_dir" "$backhref" "$href_prefix" "$layout" "$(( i + 1 ))" \
            "${photos[@]:i:count}")
        if [ -z "$buffer_ref" ]; then
            buffer_ref="$block"
        else
            buffer_ref+=$'\n'"$block"
        fi
        (( i += count ))
    done
}

# Decide the layout for the next tile, printing "<layout> <photo-count>". When
# feature_allowed is non-zero each tile rolls first for a "feature" (one photo
# blown up to a 2x2 hero tile) with THUMB_FEATURE_PERCENT probability; the caller
# clears feature_allowed once a page has reached its per-page feature-tile cap
# (see append_preview_grid). Otherwise the tile rolls for a subdivision with
# THUMB_SUBDIVIDE_PERCENT probability (only into a layout that fits the photos
# still remaining on the page); failing both it is a single square thumbnail. The
# feature and subdivide rolls use independent seeded random_index namespaces, so
# builds stay reproducible when RANDOM_SEED is set.
tile_layout_for() {
    local -ri remaining="$1"; shift
    local -r context="$1"; shift
    local -ri feature_allowed="$1"; shift
    local -a names=(two_wide)
    local -a counts=(2)
    local -i roll choice

    # A feature tile always fits (it consumes a single photo), so roll for it
    # first -- but only while the page has not used its one allowed feature.
    # THUMB_FEATURE_PERCENT == 0 disables it (the roll can never be < 0).
    if (( feature_allowed )); then
        roll=$(random_index "feature:$context" 100)
        if (( roll < THUMB_FEATURE_PERCENT )); then
            printf 'feature 1\n'
            return
        fi
    fi

    # A single tile when subdivision is disabled, too few photos remain to fill
    # even the smallest subdivided layout (two_wide needs 2), or the roll misses.
    if (( remaining < 2 || THUMB_SUBDIVIDE_PERCENT == 0 )); then
        printf 'single 1\n'
        return
    fi
    roll=$(random_index "subdivide:$context" 100)
    if (( roll >= THUMB_SUBDIVIDE_PERCENT )); then
        printf 'single 1\n'
        return
    fi

    # Offer only the subdivision layouts that fit the remaining photo count.
    if (( remaining >= 3 )); then
        names+=(squares_wide_top squares_wide_bottom)
        counts+=(3 3)
    fi
    if (( remaining >= 4 )); then
        names+=(quad)
        counts+=(4)
    fi

    choice=$(random_index "sublayout:$context" "${#names[@]}")
    printf '%s %s\n' "${names[choice]}" "${counts[choice]}"
}

# Render one tile's markup (no trailing newline). A "single" tile is the plain
# square thumbnail, byte-identical to the previous per-thumbnail output. A
# "feature" tile is the same single thumbnail but with the 'feature' anchor class
# that makes CSS span it across a 2x2 block. Any other layout is a subdivided
# tile. The tile's photos are the trailing args and their preview numbers run
# from start_preview upward.
build_tile_block() {
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -r layout="$1"; shift
    local -ri start_preview="$1"; shift
    local -a photos=("$@")
    local animation_class

    case "$layout" in
        single|feature)
            animation_class=$(random_animation_css_class slow "${photos[0]}")
            # 'single' -> no anchor class (legacy output); 'feature' -> the
            # 'feature' anchor class CSS spans across a 2x2 grid block.
            local anchor_class=''
            if [ "$layout" = feature ]; then
                anchor_class='feature'
            fi
            build_preview_thumbnail \
                "$thumbs_dir" "$backhref" "$href_prefix" "$start_preview" \
                "${photos[0]}" "$animation_class" thumb "$anchor_class"
            return
            ;;
    esac
    build_subdivided_tile \
        "$thumbs_dir" "$backhref" "$href_prefix" "$layout" "$start_preview" \
        "${photos[@]}"
}

# Emit a subdivided tile: a <div class='tile'> wrapping the smaller
# sub-thumbnails (class 'subthumb'). Each sub-thumbnail is still its own
# clickable photo/view page; only its size and (for the full-width strip) an
# extra 'wide' anchor class differ from a normal square thumbnail. The anchor
# ORDER encodes the layout for the CSS grid's auto-placement:
#   two_wide            -> two full-width strips (both 'wide'), stacked
#   squares_wide_top    -> strip first (top row), then two squares (bottom row)
#   squares_wide_bottom -> two squares first (top row), then strip (bottom row)
#   quad                -> four squares (2x2)
build_subdivided_tile() {
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -r layout="$1"; shift
    local -ri start_preview="$1"; shift
    local -a photos=("$@")
    local -a anchor_classes
    local -i k
    local animation_class

    case "$layout" in
        two_wide)            anchor_classes=(wide wide) ;;
        squares_wide_top)    anchor_classes=(wide '' '') ;;
        squares_wide_bottom) anchor_classes=('' '' wide) ;;
        quad)                anchor_classes=('' '' '' '') ;;
    esac

    printf "<div class='tile'>\n"
    for (( k = 0; k < ${#photos[@]}; k++ )); do
        animation_class=$(random_animation_css_class slow "${photos[k]}")
        build_preview_thumbnail \
            "$thumbs_dir" "$backhref" "$href_prefix" "$(( start_preview + k ))" \
            "${photos[k]}" "$animation_class" subthumb "${anchor_classes[k]:-}"
        printf '\n'
    done
    printf '</div>'
}

# Render the HTML for a single preview thumbnail (HTML-escaping every value the
# way preview.tmpl's context_html fields did). Returned without a trailing
# newline so callers control separators. The view-page link is
# "${href_prefix}${preview_num}.html", so the main album passes "<page_num>-" and
# the stats mini-albums (whose view pages are bare "<index>.html") pass "" -- the
# only thing that differs between the two grids, keeping one shared builder.
# img_class defaults to 'thumb' (the full square); subdivided tiles pass
# 'subthumb'. anchor_class is an optional extra class on the <a> ('wide' marks the
# full-width strip inside a subdivided tile, 'feature' a 2x2 hero tile); when empty
# the <a> has no class attribute, keeping the single-tile output byte-identical to
# before.
build_preview_thumbnail() {
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -r preview_num="$1"; shift
    local -r photo_file="$1"; shift
    local -r animation_class="$1"; shift
    local -r img_class="${1:-thumb}"
    local -r anchor_class="${2:-}"
    local photo_html
    local anim_html
    local backhref_html
    local thumbs_dir_html
    local anchor_class_html

    photo_html=$(_html_escape "$photo_file")
    anim_html=$(_html_escape "$animation_class")
    backhref_html=$(_html_escape "$backhref")
    thumbs_dir_html=$(_html_escape "$thumbs_dir")
    if [ -n "$anchor_class" ]; then
        anchor_class_html=$(_html_escape "$anchor_class")
        printf '<a id=%s class=%s href=%s>\n' \
            "'$photo_html'" "'$anchor_class_html'" \
            "'${href_prefix}${preview_num}.html'"
    else
        printf '<a id=%s href=%s>\n' \
            "'$photo_html'" "'${href_prefix}${preview_num}.html'"
    fi
    printf "  <img class='%s %s' alt='%s' src='%s/%s/%s'>\n</a>" \
        "$img_class" "$anim_html" "$photo_html" "$backhref_html" \
        "$thumbs_dir_html" "$photo_html"
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
