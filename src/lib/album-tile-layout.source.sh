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

# The valid subdivided-tile layout name for a given photo count (2..4); used when
# a split leaves a smaller-but-still-subdivided remainder. A count of 1 is a
# plain single and never asks here.
_grid_subdivide_layout_for() {
    case "$1" in
        2) printf 'two_wide\n' ;;
        3) printf 'squares_wide_top\n' ;;
        *) printf 'quad\n' ;;
    esac
}

# Snap a page's tiles onto a grid-cell total that is a multiple of 12 so the
# fixed 2/3/4/6-column overview grid (all divisors of 12) forms a COMPLETE
# rectangle at every breakpoint -- no ragged, cut-off last row at any window
# width. The cell footprint is 4 for a 2x2 "feature" tile and 1 for every other
# tile, so a page's natural total is rarely a multiple of 12.
#
# Two levers reach the nearest reachable multiple of 12, both keeping the SAME
# photos in the SAME order (so per-photo preview numbers / view-page links never
# change), only their visual grouping shifts:
#   - PREFERRED, round up: split subdivided tiles into singles (+1 cell per photo
#     peeled). Abundant on a normal album (many subdivided tiles) and needs no
#     adjacency, so this is the reliable lever.
#   - FALLBACK, round down: merge adjacent single tiles into two-up tiles (-1 cell
#     per merge). Used when there are too few subdivided cells to round up (e.g. a
#     single-heavy page, or THUMB_SUBDIVIDE_PERCENT=0).
# Left untouched when the page has fewer than 12 cells (a tiny stats mini-album or
# the album's short final page) or neither lever can reach a multiple of 12.
# Operates in place on the parallel layout/start/count arrays passed by name.
# The three array arguments are the NAMES of the caller's parallel arrays (passed
# as strings and forwarded by name to the chosen lever helper). We bind only
# read-only local namerefs here (uniquely named so they never alias a caller's
# nameref of the same name -- bash would treat that as a circular reference).
_align_page_tiles_to_grid() {
    local -r layouts_name="$1"; shift
    local -r starts_name="$1"; shift
    local -r counts_name="$1"; shift
    local -ri total_cells="$1"; shift

    local -ri remainder=$(( total_cells % 12 ))
    if (( total_cells < 12 || remainder == 0 )); then
        return
    fi

    # How many extra cells splitting every subdivided tile fully could yield.
    # shellcheck disable=SC2178
    local -n align_layouts="$layouts_name"
    # shellcheck disable=SC2178
    local -n align_counts="$counts_name"
    local -i capacity_up=0 i
    for (( i = 0; i < ${#align_layouts[@]}; i++ )); do
        if [ "${align_layouts[i]}" != single ] \
            && [ "${align_layouts[i]}" != feature ] \
            && (( align_counts[i] >= 2 )); then
            capacity_up=$(( capacity_up + align_counts[i] - 1 ))
        fi
    done

    if (( capacity_up >= 12 - remainder )); then
        _grid_split_subdivides_to_add \
            "$layouts_name" "$starts_name" "$counts_name" "$(( 12 - remainder ))"
    else
        _grid_merge_singles_to_remove \
            "$layouts_name" "$starts_name" "$counts_name" "$remainder"
    fi
}

# Round a page UP to the next multiple of 12 by peeling `to_add` photos off
# subdivided tiles into trailing singles (each peel: +1 cell, photos preserved in
# order). Peeling the tail of a subdivide keeps both pieces contiguous, so the
# kept remainder (a smaller subdivide, or a single when only one photo is left)
# and the peeled singles stay in photo order. Rebuilds the arrays in place.
_grid_split_subdivides_to_add() {
    # shellcheck disable=SC2178
    local -n split_layouts="$1"; shift
    # shellcheck disable=SC2178
    local -n split_starts="$1"; shift
    # shellcheck disable=SC2178
    local -n split_counts="$1"; shift
    local -i to_add="$1"; shift

    local -a new_layouts=() new_starts=() new_counts=()
    local -i i p peel keep start cnt
    for (( i = 0; i < ${#split_layouts[@]}; i++ )); do
        start=${split_starts[i]}
        cnt=${split_counts[i]}
        if (( to_add > 0 )) && [ "${split_layouts[i]}" != single ] \
            && [ "${split_layouts[i]}" != feature ] && (( cnt >= 2 )); then
            peel=$(( to_add < cnt - 1 ? to_add : cnt - 1 ))
            keep=$(( cnt - peel ))
            if (( keep == 1 )); then
                new_layouts+=(single)
            else
                new_layouts+=("$(_grid_subdivide_layout_for "$keep")")
            fi
            new_starts+=("$start")
            new_counts+=("$keep")
            for (( p = 0; p < peel; p++ )); do
                new_layouts+=(single)
                new_starts+=("$(( start + keep + p ))")
                new_counts+=(1)
            done
            to_add=$(( to_add - peel ))
        else
            new_layouts+=("${split_layouts[i]}")
            new_starts+=("$start")
            new_counts+=("$cnt")
        fi
    done

    split_layouts=("${new_layouts[@]}")
    split_starts=("${new_starts[@]}")
    split_counts=("${new_counts[@]}")
}

# Round a page DOWN to the previous multiple of 12 by merging `to_remove` pairs of
# adjacent single tiles into two-up "two_wide" tiles (each merge: -1 cell). Walks
# right-to-left building a reversed result, then un-reverses it. Decrements use
# assignment ("k=$(( k - 1 ))"), never a bare "(( --k ))": under set -euo pipefail
# an arithmetic command whose result is 0 (e.g. --k reaching 0) returns status 1
# and would abort the whole generate; an assignment always returns 0.
_grid_merge_singles_to_remove() {
    # shellcheck disable=SC2178
    local -n merge_layouts="$1"; shift
    # shellcheck disable=SC2178
    local -n merge_starts="$1"; shift
    # shellcheck disable=SC2178
    local -n merge_counts="$1"; shift
    local -i merges_left="$1"; shift

    local -a new_layouts=() new_starts=() new_counts=()
    local -i k=${#merge_layouts[@]} j
    while (( k > 0 )); do
        k=$(( k - 1 ))
        if (( merges_left > 0 && k > 0 )) \
            && [ "${merge_layouts[k]}" = single ] \
            && [ "${merge_layouts[k - 1]}" = single ]; then
            new_layouts+=(two_wide)
            new_starts+=("${merge_starts[k - 1]}")
            new_counts+=(2)
            merges_left=$(( merges_left - 1 ))
            k=$(( k - 1 ))
        else
            new_layouts+=("${merge_layouts[k]}")
            new_starts+=("${merge_starts[k]}")
            new_counts+=("${merge_counts[k]}")
        fi
    done

    merge_layouts=() merge_starts=() merge_counts=()
    j=${#new_layouts[@]}
    while (( j > 0 )); do
        j=$(( j - 1 ))
        merge_layouts+=("${new_layouts[j]}")
        merge_starts+=("${new_starts[j]}")
        merge_counts+=("${new_counts[j]}")
    done
}

# Build the tile layout for the album's SHORT final page (a leftover handful of
# photos that can't tile into a clean rectangle). Subdividing/featuring such a
# page can drop its cell count below 12, where it can't be aligned to a multiple
# of 12 and so is ragged at some breakpoints. Instead lay it out as plain singles
# (one cell each) and then:
#   - count >= 12: merge down to the nearest multiple of 12 -> a flush grid;
#   - count < 12 : make every tile a full-row "fill" banner -> a flush filmstrip
#     (one photo -> one clean full-width closer; a few photos -> stacked banners).
# Either way the page is a complete set of full rows at 2/3/4/6 columns. Writes
# the parallel layout/start/count arrays named by $1/$2/$3 in place.
_build_final_page_tiles() {
    local -r layouts_name="$1"; shift
    local -r starts_name="$1"; shift
    local -r counts_name="$1"; shift
    local -ri photo_count="$1"; shift

    # shellcheck disable=SC2178
    local -n final_layouts="$layouts_name"
    # shellcheck disable=SC2178
    local -n final_starts="$starts_name"
    # shellcheck disable=SC2178
    local -n final_counts="$counts_name"
    local -i p

    final_layouts=()
    final_starts=()
    final_counts=()
    for (( p = 0; p < photo_count; p++ )); do
        final_layouts+=(single)
        final_starts+=("$p")
        final_counts+=(1)
    done

    if (( photo_count >= 12 )); then
        _grid_merge_singles_to_remove \
            "$layouts_name" "$starts_name" "$counts_name" "$(( photo_count % 12 ))"
    else
        for (( p = 0; p < photo_count; p++ )); do
            final_layouts[p]=fill
        done
    fi
}

# Render one tile's markup (no trailing newline). A "single" tile is the plain
# square thumbnail, byte-identical to the previous per-thumbnail output. A
# "feature" tile is the same single thumbnail but with the 'feature' anchor class
# that makes CSS span it across a 2x2 block. A "fill" tile is one thumbnail with
# the 'fill-row' anchor class that spans the WHOLE row (grid-column: 1 / -1) at
# any breakpoint -- used for the leftover photo on the album's short final page so
# its bottom edge is flush instead of an orphaned corner. Any other layout is a
# subdivided tile. The tile's photos are the trailing args and their preview
# numbers run from start_preview upward.
build_tile_block() {
    local -r thumbs_dir="$1"; shift
    local -r backhref="$1"; shift
    local -r href_prefix="$1"; shift
    local -r layout="$1"; shift
    local -ri start_preview="$1"; shift
    local -a photos=("$@")
    local animation_class

    case "$layout" in
        single|feature|fill)
            animation_class=$(random_animation_css_class slow "${photos[0]}")
            # 'single' -> no anchor class (legacy output); 'feature' -> the
            # 'feature' anchor class CSS spans a 2x2 block; 'fill' -> the
            # 'fill-row' anchor class spans the whole row at any column count.
            local anchor_class=''
            case "$layout" in
                feature) anchor_class='feature' ;;
                fill) anchor_class='fill-row' ;;
            esac
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
