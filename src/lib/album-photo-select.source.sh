# Album photo listing and random selection. Split out of
# album-render.source.sh (task ar0) so the "which photos are in this album, in
# what order, and which one do we pick for a background/splash" concern lives
# apart from the page orchestration, the tile-layout deciders and the thumbnail
# HTML. This is selection POLICY (shuffle/sort/chronological, splash-requires-a-
# blur, seeded random pick) and changes for different reasons than the
# rendering plumbing.
#
# These helpers are called by the orchestrator (album-render.source.sh) and by
# the per-page render jobs at runtime; all libs are sourced before any code runs,
# so availability does not depend on source order.

# Main album display order, in precedence order (task 8v0):
#   1. CHRONOLOGICAL_ORDER=yes -> chronological_photo_files (EXIF date taken,
#      ascending, falling back to mtime for photos without one).
#   2. otherwise -> the historical maybe_shuffle path (seeded/random SHUFFLE, or
#      plain filename sort when SHUFFLE=no).
# CHRONOLOGICAL_ORDER therefore takes precedence over SHUFFLE when both are
# set: a chronological album is meant to read as a timeline, so an enabled
# shuffle must not silently re-scramble it. This is deliberately a config-level
# choice rather than an error, so flipping SHUFFLE on/off (e.g. via the CLI
# flags) while experimenting does not require also touching
# CHRONOLOGICAL_ORDER. Unlike the other photo listings this one keeps its own
# find rather than using list_photos (photo-list.source.sh): both order modes
# need the raw filename list before applying their own ordering, not a plain
# sort. Uses $FIND (compat.source.sh) since -printf is a GNU-only action.
album_photo_files() {
    local -r photos_dir="$1"; shift

    if [ "$CHRONOLOGICAL_ORDER" = yes ]; then
        chronological_photo_files "$photos_dir"
        return
    fi

    "$FIND" "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
        | maybe_shuffle
}

# Build the sort key chronological_photo_files uses to order one photo: a
# tab-separated "<group>\t<time>\t<photo>" line consumed by a plain lexicographic
# sort (see chronological_photo_files). EXIF reads always target the INCOMING_DIR
# original (matching photo_exif_tooltip_text/photo_exif_details_html), not the
# resized DIST_DIR copy, so ordering and tooltip/details agree about a photo's
# taken time and both share the same identify cache entry.
#
#   group  0 when photo_date_taken (album-metadata.source.sh) found a real EXIF
#          date, 1 otherwise. Group 0 always sorts before group 1, so photos
#          with a genuine timestamp are never displaced by an approximate
#          fallback for photos that lack one.
#   time   the EXIF date normalized from "YYYY:MM:DD HH:MM:SS" to a 14-digit
#          "YYYYMMDDHHMMSS" string (colons/space just stripped -- the calendar
#          substrings are untouched, so this stays safe even though the EXIF
#          string is not `date -d`-parseable, see docs/stats-exif-audit.md) for
#          group 0, or the INCOMING_DIR file's mtime (compat.source.sh $STAT,
#          zero-padded so it sorts lexicographically) for group 1. Fixed width
#          within each group keeps a plain sort numerically correct.
#   photo  final tiebreaker so photos sharing a timestamp (e.g. burst shots) or
#          missing both an EXIF date and a readable mtime still sort in a
#          stable, reproducible order across regenerations of the same
#          incoming set.
chronological_sort_key_for_photo() {
    local -r photo="$1"; shift
    local date_time
    local mtime

    date_time=$(photo_date_taken "$photo" "$INCOMING_DIR/$photo")
    if [[ "$date_time" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
        printf '0\t%s%s%s%s%s%s\t%s\n' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}" \
            "$photo"
        return
    fi

    # No usable EXIF date-taken (missing tag or a malformed value): fall back to
    # the source file's mtime so ordering still reflects "roughly when this
    # photo appeared" rather than an arbitrary readdir order, and stays fully
    # deterministic across runs. A missing/unreadable source file (should not
    # happen; INCOMING_DIR is validated before generation) reads as mtime 0 so
    # this never aborts the render.
    mtime=$("$STAT" -c '%Y' "$INCOMING_DIR/$photo" 2>/dev/null) || mtime=0
    printf '1\t%020d\t%s\n' "$mtime" "$photo"
}

# Chronological ordering for CHRONOLOGICAL_ORDER=yes: every photo in
# DIST_DIR/photos_dir, ordered ascending by chronological_sort_key_for_photo.
# Explicit tab delimiter (rather than plain whitespace splitting) so a filename
# containing a space (e.g. the "04 filename with spaces.jpg" test fixture) stays
# one field instead of fracturing the sort/cut boundaries.
chronological_photo_files() {
    local -r photos_dir="$1"; shift

    "$FIND" "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
        | while IFS= read -r photo; do
            chronological_sort_key_for_photo "$photo"
        done \
        | sort -t $'\t' -k1,1 -k2,2 \
        | cut -f3-
}

# Pagination single source of truth (task nr0): how many preview pages a given
# number of album photos splits into, with at most MAXPREVIEWS photos per page.
# album_page_records below realises exactly this many records by grouping the
# actual (shuffled) photo list, and the dry-run plan calls this helper to predict
# the page count from the incoming-image tally WITHOUT enumerating dist files. So
# the preview and a real --generate can never disagree on the page count: both
# express "ceil(image_count / MAXPREVIEWS)" through this one definition. An empty
# album yields 0 pages.
album_page_count_for_image_count() {
    local -ri image_count="$1"; shift

    if (( image_count <= 0 )); then
        printf '0\n'
        return
    fi
    printf '%d\n' "$(( (image_count + MAXPREVIEWS - 1) / MAXPREVIEWS ))"
}

# Group the album's photos into pages of at most MAXPREVIEWS, in their final
# (shuffled/sorted) order. The result is emitted one line per page as a
# tab-separated record "<page_num>\t<photo>\t<photo>..." so the caller can walk
# pages without keeping every page in memory at once. Order is fully
# deterministic (album_photo_files already applies the seeded shuffle), so the
# downstream parallelism only changes timing, never which photo lands where. The
# number of records produced here equals album_page_count_for_image_count of the
# photo count (same MAXPREVIEWS-per-page grouping); see that helper.
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
