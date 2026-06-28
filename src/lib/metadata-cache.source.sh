# Shared EXIF identify cache primitive. Promoted out of album-metadata.source.sh
# (task pn0) because the cached `identify -verbose` reader is a low-level
# metadata primitive consumed by BOTH the album (tooltips, details tables) and
# the stats aggregator (leaderboard tallies). Keeping it inside the album module
# forced stats to reach across a module boundary into album internals; moving it
# here gives both consumers a shared, stable dependency that is sourced before
# either of them (see LIB_SOURCES in the Justfile, ordered right after
# metadata-label.source.sh, the sibling shared metadata helper). All library
# modules are sourced before any code runs, so source order documents the
# dependency, it does not affect availability. Behaviour and signatures are
# unchanged by the move.

# The volatile EXIF cache directory: ./cache/exif parallel to ./dist. Computed
# once here (task pr0) from working_dir() (the parent of DIST_DIR) so the path is
# defined in exactly ONE place. It was previously recomputed inline -- byte for
# byte identically -- in both cached_photo_identify_output (read/write) and
# clear_exif_cache (remove for --force/--clean); a single source for it keeps
# those two in lockstep so the reader and the cleaner can never drift apart and
# point at different directories. The path is deliberately a sibling of DIST_DIR
# (working_dir()/cache/exif): the staging dir is a sibling of the final dist, so
# this resolves to the working dir in both staging and direct contexts, lives
# outside dist (surviving a fresh/cleared dist and never deployed), and lets an
# unchanged photo skip the slow `identify -verbose` on every regenerate.
# printf (no echo) keeps it safe under `set -euo pipefail`.
exif_cache_dir() {
    printf '%s\n' "$(working_dir)/cache/exif"
}

# Build the cache signature line ("<photo>:<size>:<mtime>") used to decide
# whether a cache entry is still valid for the source file. Kept private to this
# module alongside its only consumers, plus the stats test that pre-seeds caches.
photo_cache_signature() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local stat_output

    stat_output=$(stat -c '%s:%Y' "$photo_path")
    printf '%s:%s\n' "$photo" "$stat_output"
}

# Print a cache file's payload (everything after the leading signature line).
print_cached_photo_identify_output() {
    local -r cache_file="$1"; shift
    local line
    local skipped_signature=no

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skipped_signature" = no ]; then
            skipped_signature=yes
            continue
        fi
        printf '%s\n' "$line"
    done < "$cache_file"
}

# Return cached ImageMagick `identify -verbose` output for a photo, rebuilding
# the cache when missing or stale. Public shared primitive: album-metadata and
# stats-aggregate both call this rather than running identify themselves.
cached_photo_identify_output() {
    local -r photo="$1"; shift
    local -r photo_path="$1"; shift
    local cache_dir
    local cache_file
    local cached_signature=''
    local current_signature
    local identify_status

    # Resolve the volatile EXIF cache dir via the shared exif_cache_dir() helper
    # (see its definition above for why it sits parallel to ./dist and survives a
    # cleared dist) so the reader/writer here and clear_exif_cache below always
    # agree on the same directory.
    cache_dir="$(exif_cache_dir)"
    cache_file="$cache_dir/$photo.txt"
    current_signature=$(photo_cache_signature "$photo" "$photo_path")

    # Reuse the cache when its signature still matches the source file. --force
    # is handled once up front by clear_exif_cache (which empties this directory),
    # so the first call per photo then rebuilds it and the rest of the run reuses
    # it -- exactly one identify per photo even under force.
    if [ -f "$cache_file" ]; then
        IFS= read -r cached_signature < "$cache_file" || true
        if [ "$cached_signature" = "$current_signature" ]; then
            print_cached_photo_identify_output "$cache_file"
            return
        fi
    fi

    mkdir -p "$cache_dir"
    printf '%s\n' "$current_signature" > "$cache_file"

    # Capture the identify exit status instead of swallowing it with `|| true`.
    # Errors are still hidden from stdout (so a corrupt photo does not pollute
    # the EXIF output), but a non-zero status now drives a warning + no-cache
    # rather than silently leaving a signature-only cache entry behind.
    identify_status=0
    imagemagick_identify -verbose "$photo_path" >> "$cache_file" 2>/dev/null \
        || identify_status=$?

    if [ "$identify_status" -ne 0 ]; then
        # Failed identify (corrupt photo, timeout, missing binary, ...): warn
        # naming the photo and remove the cache file. Removing it is essential:
        # a file holding only the signature line is a valid-looking cache hit,
        # so the next run would silently reuse the empty result forever -- never
        # retrying identify and never warning again (the original data-loss bug).
        # Deleting it makes the next run retry and warn.
        #
        # We deliberately do NOT abort: this runs inside backgrounded render jobs
        # under `set -euo pipefail`, and one unreadable photo must not kill the
        # whole generation. The photo still renders, just with empty tooltip and
        # stats, now accompanied by a warning.
        rm -f "$cache_file"
        log_warning \
            "could not read EXIF for $photo (ImageMagick identify failed);" \
            "tooltip/stats will be missing"
        return 0
    fi

    print_cached_photo_identify_output "$cache_file"
}

# Canonical `identify -verbose` stream parser. Reads an identify stream from
# stdin and fills the caller-provided associative array (by nameref) with one
# entry per recognised field. Promoted here (task 8r0) from three near-identical
# copies that had already drifted -- album-metadata had two exif:-only loops and
# stats-aggregate added a native Geometry path. This single definition is a
# strict superset of all three: it lives next to cached_photo_identify_output so
# both the album (tooltips, details tables) and the stats aggregator share one
# regex and one set of key conventions, isolating any future identify-format
# drift to one place.
#
# Keys produced:
#   - exif:* lines -> stored under the bare tag name (e.g. "Make", "FNumber"),
#     i.e. WITHOUT the leading "exif:" -- callers that want the prefixed label
#     (the details table) re-add it. This matches the historical album and stats
#     array keys exactly.
#   - the native Geometry line ("WxH+x+y") -> stored under the synthetic key
#     "__geometry"; stats reads this for dimension tallies, album ignores it.
#
# Reads from stdin (not from a photo path) so it composes with the cache layer:
# stats pipes a fixture or cache stream straight in, while album wraps it with
# `photo_exif_values_to ref < <(cached_photo_identify_output ...)`.
photo_exif_values_to() {
    local -n output_ref="$1"; shift
    local line

    output_ref=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$ ]]; then
            # output_ref writes to the caller-provided associative array.
            # shellcheck disable=SC2034
            output_ref["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*Geometry:[[:space:]]*(.*)$ ]]; then
            # __geometry is a literal array key, not a variable; --check-sourced
            # nameref aliasing across modules misreads it (SC2154). SC2034 covers
            # the caller-owned array write.
            # shellcheck disable=SC2034,SC2154
            output_ref[__geometry]="${BASH_REMATCH[1]}"
        fi
    done
}

# Empty the volatile EXIF cache (./cache/exif, parallel to ./dist) so a --force
# run re-runs `identify` from scratch. Done once up front; the cache then
# repopulates and is reused for the rest of the run (one identify per photo).
# Moved here from album-metadata.source.sh (task 6r0): clearing the cache is the
# lifecycle counterpart of cached_photo_identify_output above, so the cache's
# creation and destruction now live in the same module.
clear_exif_cache() {
    local -r cache_dir="$(exif_cache_dir)"

    log_verbose "Force generation; clearing EXIF cache $cache_dir"
    rm -rf "$cache_dir"
}
