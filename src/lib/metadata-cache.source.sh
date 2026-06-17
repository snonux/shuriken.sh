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

    # Persist the EXIF cache in a volatile ./cache directory parallel to ./dist
    # (the staging dir is a sibling of the final dist, so dirname "$DIST_DIR" is
    # the working dir in both staging and direct contexts). Keeping it outside
    # dist means it survives a fresh/cleared dist and is never deployed, so an
    # unchanged photo skips the slow `identify -verbose` on every regenerate.
    cache_dir="$(dirname "$DIST_DIR")/cache/exif"
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
