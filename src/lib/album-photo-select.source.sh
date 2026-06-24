# Album photo listing and random selection. Split out of
# album-render.source.sh (task ar0) so the "which photos are in this album, in
# what order, and which one do we pick for a background/splash" concern lives
# apart from the page orchestration, the tile-layout deciders and the thumbnail
# HTML. This is selection POLICY (shuffle/sort, splash-requires-a-blur, seeded
# random pick) and changes for different reasons than the rendering plumbing.
#
# These helpers are called by the orchestrator (album-render.source.sh) and by
# the per-page render jobs at runtime; all libs are sourced before any code runs,
# so availability does not depend on source order.

# Unlike the other photo listings this one keeps its own find rather than using
# list_photos (photo-list.source.sh): it pipes through maybe_shuffle, not sort,
# because the album's display order is the configurable (seeded) shuffle, not a
# plain sort.
album_photo_files() {
    local -r photos_dir="$1"; shift

    find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
        | maybe_shuffle
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

# Splash candidates: the album's photos (sorted) that also have a matching blur,
# since the splash page renders a blurred background. Lists via the shared
# list_photos (photo-list.source.sh) and filters to those with a blur present.
splash_photo_files() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local photo

    while IFS= read -r photo; do
        if [ -f "$DIST_DIR/$blurs_dir/$photo" ]; then
            printf '%s\n' "$photo"
        fi
    done < <(list_photos "$photos_dir")
}

# Pick a seeded-random splash photo: one of the album's photos that also has a
# matching blur. Shares the selection core (_pick_random_from_list,
# photo-list.source.sh) with the other pickers; only the candidate list (splash
# photos, not all photos), the "photo:<dir>:splash" namespace and the
# splash-specific empty error are particular to splash selection. Output and
# determinism are unchanged from the former inline implementation.
random_splash_photo() {
    local -r photos_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(splash_photo_files "$photos_dir" "$blurs_dir")

    if ! _pick_random_from_list "photo:$photos_dir:splash" photos; then
        printf 'ERROR: No splash photos found in %s with matching blurs in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" \
            "$(_display_path "$DIST_DIR/$blurs_dir")" >&2
        return 1
    fi
    printf '\n'
}
