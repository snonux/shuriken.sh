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
