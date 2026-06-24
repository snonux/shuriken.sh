# Album thumbnail-grid tile layout / subdivision. Split out of
# album-render.source.sh (task ar0) so the "how do consecutive thumbnails get
# grouped into tiles" concern (feature 2x2 hero tiles, subdivided multi-thumb
# tiles, plain squares) lives apart from the page orchestration and the raw
# thumbnail HTML. These deciders change for visual/CSS reasons, independent of
# the job plumbing or the photo-selection policy.
#
# tile_layout_for rolls the seeded random layout for the next tile;
# build_tile_block / build_subdivided_tile emit the chosen tile's markup. They
# call build_preview_thumbnail (album-thumbnail-html.source.sh) at runtime, and
# are themselves driven by append_preview_grid there; all libs are sourced
# before any code runs, so the cross-module calls resolve regardless of source
# order.

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
