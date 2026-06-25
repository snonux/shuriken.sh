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
append_preview_grid() {
    local -n buffer_ref="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    # 'yes' only for the main album's LAST page: when such a page cannot be
    # aligned to a multiple of 12 (a short final page with a leftover photo), its
    # final single tile is widened to span the whole row so the bottom stays
    # flush. Callers that must not do this (stats mini-albums) pass 'no'.
    local -r fill_last="$1"; shift
    local -a photos=("$@")
    local -i i=0
    local -i count
    local -i total_cells=0
    local layout
    local block
    # Cap the big 2x2 feature tiles at this many per page; once reached, later
    # tiles are no longer offered the "feature" layout (they fall back to
    # subdivided/single), so a page never gets crowded with hero tiles.
    local -ri max_features=2
    local -i features_used=0
    # Parallel records of the page's tiles: layout, the first photo's 0-based
    # index, and how many photos the tile spans.
    local -a tile_layouts=()
    local -a tile_starts=()
    local -a tile_counts=()
    local -i t

    # Pass 1: decide every tile (deterministic, seeded off each tile's first photo
    # name). A 2x2 feature occupies 4 grid cells; every other tile occupies 1.
    while (( i < ${#photos[@]} )); do
        read -r layout count < <(
            tile_layout_for "$(( ${#photos[@]} - i ))" "${photos[i]}" \
                "$(( features_used < max_features ? 1 : 0 ))"
        )
        if [ "$layout" = feature ]; then
            (( ++features_used ))
            (( total_cells += 4 ))
        else
            (( ++total_cells ))
        fi
        tile_layouts+=("$layout")
        tile_starts+=("$i")
        tile_counts+=("$count")
        (( i += count ))
    done

    # Pass 2: force the cell total onto a multiple of 12 so the grid is flush at
    # every column breakpoint (no-op for tiny pages / too-few-singles -- see the
    # helper). Per-photo preview numbers are preserved.
    _align_page_tiles_to_grid \
        tile_layouts tile_starts tile_counts "$total_cells"

    # Pass 2b: if this is the album's last page and it still could not be aligned
    # to a multiple of 12 (a short final page), widen its final single tile to a
    # full-row "fill" tile so the bottom edge is flush at every breakpoint instead
    # of an orphaned corner. Recompute the post-alignment cell total first.
    if [ "$fill_last" = yes ] && (( ${#tile_layouts[@]} > 0 )); then
        local -i aligned_cells=0
        for (( t = 0; t < ${#tile_layouts[@]}; t++ )); do
            if [ "${tile_layouts[t]}" = feature ]; then
                (( aligned_cells += 4 ))
            else
                (( ++aligned_cells ))
            fi
        done
        local -i last=$(( ${#tile_layouts[@]} - 1 ))
        if (( aligned_cells % 12 != 0 )) && [ "${tile_layouts[last]}" = single ]; then
            tile_layouts[last]=fill
        fi
    fi

    # Pass 3: emit the tile blocks in order.
    for (( t = 0; t < ${#tile_layouts[@]}; t++ )); do
        block=$(build_tile_block \
            "$thumbs_dir" "$backhref" "$href_prefix" "${tile_layouts[t]}" \
            "$(( tile_starts[t] + 1 ))" \
            "${photos[@]:${tile_starts[t]}:${tile_counts[t]}}")
        if [ -z "$buffer_ref" ]; then
            buffer_ref="$block"
        else
            buffer_ref+=$'\n'"$block"
        fi
    done
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
