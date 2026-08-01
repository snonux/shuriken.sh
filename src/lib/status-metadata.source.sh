# Status sidecar: write a small dist/status.json an external monitoring system
# can poll to check the age of the generated album. Unlike the full
# dist/shuriken.json generation manifest (generation-metadata.source.sh), this
# file is intentionally minimal -- just the last-generation timestamp (in both a
# human-readable form and a machine-comparable Unix epoch), the total number of
# source images and their combined byte size -- so a monitor can decide whether
# the page is stale without parsing the whole manifest.
#
# The timestamp mirrors the reproducible-build behaviour of current_timestamp_iso
# (template.source.sh): when RANDOM_SEED is set the timestamp is pinned to the
# Unix epoch (1970-01-01 00:00:00 UTC, epoch 0) so a seeded run stays
# byte-deterministic; otherwise the real current time is used. image_count and
# total_size_bytes are derived from incoming_image_files (image.source.sh) and
# the resolved GNU stat ($STAT, compat.source.sh); both are sourced before this
# module and called at runtime, so source order documents the dependency without
# affecting availability.

# Print the current generation timestamp as "<human_readable>\t<unix_epoch>", a
# single line consumed by _collect_status_metadata. Kept as a named helper so
# the reproducible-vs-real branch is in one place and unit-testable.
_status_timestamp() {
    local human_readable
    local -i epoch=0

    if random_seed_is_set; then
        human_readable='1970-01-01 00:00:00 UTC'
        epoch=0
    else
        human_readable=$(command date -u +'%Y-%m-%d %H:%M:%S UTC')
        epoch=$(command date -u +'%s')
    fi

    printf '%s\t%d\n' "$human_readable" "$epoch"
}

# Total byte size of all supported incoming source images. Uses $STAT (GNU stat,
# compat.source.sh) because BSD stat lacks -c; require_gnu_tools has already
# verified $STAT supports -c before generation runs. Prints 0 when the incoming
# directory has no supported images.
_status_total_image_size() {
    local file
    local -i total=0
    local -i size=0

    while IFS= read -r file; do
        size=$("$STAT" -c '%s' "$INCOMING_DIR/$file")
        # Use assignment form, never a bare "(( total += size ))": under
        # set -euo pipefail an arithmetic command whose result is 0 returns
        # status 1 and would abort the whole generate (see the matching note in
        # album-tile-layout.source.sh). An assignment always returns 0.
        total=$(( total + size ))
    done < <(incoming_image_files)

    printf '%d\n' "$total"
}

# Gather the status snapshot into the _STATUS_METADATA global. Split from the
# serialiser so the collection step is independently testable.
_collect_status_metadata() {
    local ts
    local human_readable
    local epoch

    # Plain assignment (not "local -r ts=$(...)"): a `local` declaration always
    # returns 0, which would mask a failure inside the command substitution
    # under set -e. _status_timestamp is robust today, but this matches the
    # codebase convention of keeping command substitutions subject to errexit.
    ts=$(_status_timestamp)
    human_readable=${ts%%$'\t'*}
    epoch=${ts#*$'\t'}

    declare -gA _STATUS_METADATA=()
    _STATUS_METADATA["generated_at_human_readable"]="$human_readable"
    _STATUS_METADATA["generated_at_unix_epoch"]="$epoch"
    _STATUS_METADATA["image_count"]=$(count_incoming_images)
    _STATUS_METADATA["total_size_bytes"]=$(_status_total_image_size)
}

# Serialise _STATUS_METADATA to the dist/status.json layout:
#   {
#     "generated_at": {
#       "human_readable": "2026-08-01 12:34:56 UTC",
#       "unix_epoch": 1722508496
#     },
#     "image_count": 42,
#     "total_size_bytes": 1234567
#   }
_status_metadata_json() {
    printf '{\n'
    printf '  "generated_at": {\n'
    printf '    "human_readable": %s,\n' \
        "$(json_string "${_STATUS_METADATA["generated_at_human_readable"]}")"
    printf '    "unix_epoch": %s\n' \
        "${_STATUS_METADATA["generated_at_unix_epoch"]}"
    printf '  },\n'
    printf '  "image_count": %s,\n' \
        "${_STATUS_METADATA["image_count"]}"
    printf '  "total_size_bytes": %s\n' \
        "${_STATUS_METADATA["total_size_bytes"]}"
    printf '}\n'
}

# Public entry point: collect the status snapshot and atomically write
# dist/status.json. Called from generate() (and refresh_splash()) alongside
# write_generation_metadata.
write_status_metadata() {
    _collect_status_metadata
    {
        _status_metadata_json
    } > "$DIST_DIR/status.json"
}
