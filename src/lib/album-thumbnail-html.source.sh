# Album thumbnail HTML. Split out of album-render.source.sh (task ar0) so the
# "what markup does one thumbnail / a whole grid emit" concern lives apart from
# the tile-layout deciders (album-tile-layout.source.sh), the page orchestration
# and the photo-selection policy. This markup changes for HTML/CSS reasons
# (escaping, classes, link shape), independent of how tiles are grouped or how
# jobs are wired.
#
# append_preview_grid walks a photo list into tiles by calling tile_layout_for /
# build_tile_block (album-tile-layout.source.sh); build_preview_thumbnail emits
# one thumbnail's <a>/<img>. All libs are sourced before any code runs, so the
# calls between this module and album-tile-layout resolve regardless of source
# order.

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
#
# Three passes: (1) decide the whole page's tiles, recording each tile's layout,
# first-photo index and photo count and accumulating the grid-cell footprint;
# (2) snap that cell total onto a multiple of 12 (_align_page_tiles_to_grid) so
# the fixed 2/3/4/6-column grid is a complete rectangle -- a flush last row -- at
# every width; (3) emit the (possibly merged) tiles. Splitting decide-from-emit
# is what lets pass 2 adjust the layout before any HTML is built.
# Pass 1 + pass 2 for a normal (non-short-final) page: roll the photo list into
# tiles, then align the cell total to a multiple of 12. Reads the photos array by
# NAME (photos_name) and fills the three parallel tile arrays (layouts/starts/
# counts) by NAME -- the names are unique so they cannot collide with the caller's
# locals. Self-contained pass-1 state (features_used, total_cells) stays local
# here; only the aligned tile arrays escape. Identical tile decisions to the old
# inline code, so the flush-grid layout is unchanged.
_roll_and_align_page_tiles() {
    local -r photos_name="$1"; shift
    local -r layouts_name="$1"; shift
    local -r starts_name="$1"; shift
    local -r counts_name="$1"; shift
    local -n roll_photos_ref="$photos_name"
    # shellcheck disable=SC2178
    local -n roll_layouts_ref="$layouts_name"
    # shellcheck disable=SC2178
    local -n roll_starts_ref="$starts_name"
    # shellcheck disable=SC2178
    local -n roll_counts_ref="$counts_name"
    local -i i=0
    local -i count
    local -i total_cells=0
    local layout
    # Cap the big 2x2 feature tiles at this many per page; once reached, later
    # tiles are no longer offered the "feature" layout (they fall back to
    # subdivided/single), so a page never gets crowded with hero tiles.
    local -ri max_features=2
    local -i features_used=0
    # A 2x2 feature spans TWO grid rows, so one placed near the bottom of a page
    # leaves an L-shaped gap that grid-auto-flow: dense cannot backfill (nothing
    # follows it) -- a broken, cut-off corner at some breakpoints. Keep features
    # out of the last feature_tail_margin photos so a feature always sits in the
    # upper rows with enough following 1-cell tiles to complete its rows at every
    # column count. This also disables features on pages too short to host one
    # safely (a feature needs >= feature_tail_margin photos after it).
    local -ri feature_tail_margin=16

    # Pass 1: decide every tile (deterministic, seeded off each tile's first
    # photo name). A 2x2 feature occupies 4 grid cells; every other tile 1.
    while (( i < ${#roll_photos_ref[@]} )); do
        read -r layout count < <(
            tile_layout_for "$(( ${#roll_photos_ref[@]} - i ))" \
                "${roll_photos_ref[i]}" \
                "$(( features_used < max_features \
                    && i + feature_tail_margin < ${#roll_photos_ref[@]} ? 1 : 0 ))"
        )
        if [ "$layout" = feature ]; then
            (( ++features_used ))
            (( total_cells += 4 ))
        else
            (( ++total_cells ))
        fi
        roll_layouts_ref+=("$layout")
        roll_starts_ref+=("$i")
        roll_counts_ref+=("$count")
        (( i += count ))
    done

    # Pass 2: force the cell total onto a multiple of 12 so the grid is flush
    # at every column breakpoint. Per-photo preview numbers are preserved.
    _align_page_tiles_to_grid \
        "$layouts_name" "$starts_name" "$counts_name" "$total_cells"
}

# Pass 3: emit the decided tile blocks in order into the buffer (passed by NAME).
# Tile blocks are separated by a single newline; the first block is assigned, the
# rest appended -- byte-identical to the old inline emit loop.
_emit_page_tiles() {
    local -r buffer_name="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -r photos_name="$1"; shift
    local -r layouts_name="$1"; shift
    local -r starts_name="$1"; shift
    local -r counts_name="$1"; shift
    local -n emit_buffer_ref="$buffer_name"
    local -n emit_photos_ref="$photos_name"
    local -n emit_layouts_ref="$layouts_name"
    local -n emit_starts_ref="$starts_name"
    local -n emit_counts_ref="$counts_name"
    local block
    local -i t

    for (( t = 0; t < ${#emit_layouts_ref[@]}; t++ )); do
        block=$(build_tile_block \
            "$thumbs_dir" "$backhref" "$href_prefix" "${emit_layouts_ref[t]}" \
            "$(( emit_starts_ref[t] + 1 ))" \
            "${emit_photos_ref[@]:${emit_starts_ref[t]}:${emit_counts_ref[t]}}")
        if [ -z "$emit_buffer_ref" ]; then
            emit_buffer_ref="$block"
        else
            emit_buffer_ref+=$'\n'"$block"
        fi
    done
}

append_preview_grid() {
    local -r buffer_name="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    # 'yes' only for the main album's LAST page: when such a page cannot be
    # aligned to a multiple of 12 (a short final page with a leftover photo), its
    # final single tile is widened to span the whole row so the bottom stays
    # flush. Callers that must not do this (stats mini-albums) pass 'no'.
    local -r fill_last="$1"; shift
    local -a photos=("$@")
    # Parallel records of the page's tiles: layout, the first photo's 0-based
    # index, and how many photos the tile spans. Filled and read by the tile
    # helpers below via nameref, which shellcheck cannot see from here.
    # shellcheck disable=SC2034
    local -a tile_layouts=()
    # shellcheck disable=SC2034
    local -a tile_starts=()
    # shellcheck disable=SC2034
    local -a tile_counts=()

    # A SHORT final page (the album's last page with too few photos to tile into
    # a clean rectangle) is built by a dedicated all-singles helper that is
    # guaranteed flush at every breakpoint; subdividing/featuring it could drop
    # the cell count below 12 where it can't be aligned. Longer pages (including a
    # full final page) use the normal roll-and-align path, which is flush.
    local -ri short_final_page_max=24
    if [ "$fill_last" = yes ] && (( ${#photos[@]} < short_final_page_max )); then
        _build_final_page_tiles \
            tile_layouts tile_starts tile_counts "${#photos[@]}"
    else
        _roll_and_align_page_tiles \
            photos tile_layouts tile_starts tile_counts
    fi

    # Pass 3: emit the (possibly merged) tiles into the caller's buffer.
    _emit_page_tiles \
        "$buffer_name" "$thumbs_dir" "$backhref" "$href_prefix" \
        photos tile_layouts tile_starts tile_counts
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

    photo_html=$(html_escape "$photo_file")
    anim_html=$(html_escape "$animation_class")
    backhref_html=$(html_escape "$backhref")
    thumbs_dir_html=$(html_escape "$thumbs_dir")
    if [ -n "$anchor_class" ]; then
        anchor_class_html=$(html_escape "$anchor_class")
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
