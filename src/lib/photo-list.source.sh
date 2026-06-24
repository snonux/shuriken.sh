# Shared photo listing and random-pick primitives (task br0). Several modules
# need the same two low-level operations: "list the files in a dist photos
# directory, sorted" and "pick one seeded-random entry from a list". Before this
# module they were re-implemented in album-photo-select, image-pipeline and
# stats-render, each with the same find|sort idiom and the same collect /
# empty-check / random_index / print dance. Centralising them here removes that
# duplication while keeping behaviour identical at every call site.
#
# Home rationale: the consumers live in three otherwise-unrelated subsystems
# (album rendering, the image pipeline, the stats pages), so the helpers do not
# belong to any one of them -- putting them in, say, album-photo-select would
# make image-pipeline depend on album code. This small low-level module depends
# only on random_index (random.source.sh), _display_path (template.source.sh)
# and the $DIST_DIR global, so it is sourced early -- after random/template but
# before image-pipeline / album-* / stats-* -- so every definition precedes its
# uses. All libs are sourced before any code runs.

# List the regular files directly inside "$DIST_DIR/<dir>", one basename per
# line, sorted. This is the canonical replacement for the recurring
#   find "$DIST_DIR/<dir>" -maxdepth 1 -type f -printf '%f\n' | sort
# idiom. Stderr is left untouched so callers keep full control: a caller that
# wants the find error on a missing directory gets it, and one that wants it
# suppressed (the stats background loader) adds its own 2>/dev/null. This is the
# SORTED listing; album_photo_files deliberately keeps its own maybe_shuffle
# variant because the album's display order is the configurable shuffle, not a
# plain sort.
list_photos() {
    local -r photos_dir="$1"; shift

    find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' | sort
}

# Pick one seeded-random entry from an already-collected list, addressed by
# nameref, and print it WITHOUT a trailing newline. The namespace seeds the
# choice so a given RANDOM_SEED yields a stable pick. Returns 1 (printing
# nothing) when the list is empty, leaving the empty/error policy to the caller.
# This is the shared core of pick_random_photo / random_splash_photo /
# _stats_random_background / _stats_pick_background, so the random_index call
# (and thus selection determinism) lives in exactly one place. Each caller keeps
# its own namespace string, so seeding is unchanged from the former inline code.
_pick_random_from_list() {
    local -r namespace="$1"; shift
    local -n _list_ref="$1"; shift
    local -i index

    if (( ${#_list_ref[@]} == 0 )); then
        return 1
    fi
    index=$(random_index "$namespace" "${#_list_ref[@]}")
    printf '%s' "${_list_ref[index]}"
}

# Pick one seeded-random photo from the sorted listing of "$DIST_DIR/<dir>".
# This is the canonical "random photo" picker (formerly album-render's
# randomphoto): it prints the chosen basename followed by a newline, and on an
# empty directory emits an error and returns 1. The selection namespace is
# "photo:<dir>:<ctx>" (ctx defaults to the directory name), matching the
# historical context exactly so determinism is unchanged.
pick_random_photo() {
    local -r photos_dir="$1"; shift
    local -r context="${1:-$photos_dir}"
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(list_photos "$photos_dir")

    if (( ${#photos[@]} == 0 )); then
        printf 'ERROR: No photos found in %s\n' \
            "$(_display_path "$DIST_DIR/$photos_dir")" >&2
        return 1
    fi

    _pick_random_from_list "photo:$photos_dir:$context" photos
    printf '\n'
}
