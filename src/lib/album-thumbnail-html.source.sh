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
