# Generation metadata: collect a snapshot of the run (generator version, source
# and generated file counts, effective settings) and serialise it to the
# dist/shuriken.json sidecar. Moved out of album-metadata.source.sh (task 6r0):
# describing the generation run is its own concern, distinct from the EXIF
# presentation that stays in the album module. The collector depends on the file
# counters (count_files / count_incoming_images / count_tree_files, now in
# image.source.sh), current_timestamp_iso (template.source.sh) and the JSON
# helpers (_json_string / _json_bool, template.source.sh); all are sourced before
# this module, and these are runtime calls anyway, so source order documents the
# dependency without affecting availability. Behaviour and signatures are
# unchanged by the move.

_collect_generation_metadata() {
    local -r tarball_file="$1"; shift

    declare -gA _GENERATION_METADATA=()
    _GENERATION_METADATA["generator_name"]='shuriken'
    _GENERATION_METADATA["generator_version"]="$VERSION"
    _GENERATION_METADATA["generated_at"]=$(current_timestamp_iso)
    _GENERATION_METADATA["config_source"]="$SHURIKEN_CONFIG_SOURCE"
    _GENERATION_METADATA["template_name"]=$(basename "$TEMPLATE_DIR")
    _GENERATION_METADATA["template_directory"]="$TEMPLATE_DIR"
    _GENERATION_METADATA["source_incoming_dir"]="$INCOMING_DIR"
    _GENERATION_METADATA["source_image_count"]=$(count_incoming_images)
    _GENERATION_METADATA["generated_photo_count"]=$(count_files "$DIST_DIR/photos")
    _GENERATION_METADATA["generated_thumb_count"]=$(count_files "$DIST_DIR/thumbs")
    _GENERATION_METADATA["generated_html_count"]=$(
        count_tree_files "$DIST_DIR" '*.html'
    )
    _GENERATION_METADATA["tarball_included"]="$TARBALL_INCLUDE"
    _GENERATION_METADATA["tarball_file"]="$tarball_file"
    _GENERATION_METADATA["settings_title"]="$TITLE"
    _GENERATION_METADATA["settings_height"]="$HEIGHT"
    _GENERATION_METADATA["settings_thumbheight"]="$THUMBHEIGHT"
    _GENERATION_METADATA["settings_maxpreviews"]="$MAXPREVIEWS"
    _GENERATION_METADATA["settings_subdivide_percent"]="$THUMB_SUBDIVIDE_PERCENT"
    _GENERATION_METADATA["settings_feature_percent"]="$THUMB_FEATURE_PERCENT"
    _GENERATION_METADATA["settings_image_jobs"]="$IMAGE_JOBS"
    _GENERATION_METADATA["settings_random_seed"]="$RANDOM_SEED"
    _GENERATION_METADATA["settings_shuffle"]="$SHUFFLE"
    _GENERATION_METADATA["settings_splash_page"]="$SPLASH_PAGE"
    _GENERATION_METADATA["settings_stats_page"]="$STATS_PAGE"
    _GENERATION_METADATA["settings_original_basepath"]="$ORIGINAL_BASEPATH"
}

_generation_metadata_json() {
    printf '{\n'
    printf '  "generator": {\n'
    printf '    "name": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["generator_name"]}")"
    printf '    "version": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["generator_version"]}")"
    printf '  },\n'
    printf '  "generated_at": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["generated_at"]}")"
    printf '  "config_source": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["config_source"]}")"
    printf '  "template": {\n'
    printf '    "name": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["template_name"]}")"
    printf '    "directory": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["template_directory"]}")"
    printf '  },\n'
    printf '  "source": {\n'
    printf '    "incoming_dir": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["source_incoming_dir"]}")"
    printf '    "image_count": %s\n' \
        "${_GENERATION_METADATA["source_image_count"]}"
    printf '  },\n'
    printf '  "generated": {\n'
    printf '    "photo_count": %s,\n' \
        "${_GENERATION_METADATA["generated_photo_count"]}"
    printf '    "thumb_count": %s,\n' \
        "${_GENERATION_METADATA["generated_thumb_count"]}"
    printf '    "html_count": %s\n' \
        "${_GENERATION_METADATA["generated_html_count"]}"
    printf '  },\n'
    printf '  "tarball": {\n'
    printf '    "included": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["tarball_included"]}")"
    printf '    "file": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["tarball_file"]}")"
    printf '  },\n'
    printf '  "settings": {\n'
    printf '    "title": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_title"]}")"
    printf '    "height": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_height"]}")"
    printf '    "thumbheight": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_thumbheight"]}")"
    printf '    "maxpreviews": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_maxpreviews"]}")"
    printf '    "subdivide_percent": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_subdivide_percent"]}")"
    printf '    "feature_percent": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_feature_percent"]}")"
    printf '    "image_jobs": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_image_jobs"]}")"
    printf '    "random_seed": %s,\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_random_seed"]}")"
    printf '    "shuffle": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_shuffle"]}")"
    printf '    "splash_page": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_splash_page"]}")"
    printf '    "stats_page": %s,\n' \
        "$(_json_bool "${_GENERATION_METADATA["settings_stats_page"]}")"
    printf '    "original_basepath": %s\n' \
        "$(_json_string "${_GENERATION_METADATA["settings_original_basepath"]}")"
    printf '  }\n'
    printf '}\n'
}

write_generation_metadata() {
    local -r tarball_file="$1"; shift

    _collect_generation_metadata "$tarball_file"
    {
        _generation_metadata_json
    } > "$DIST_DIR/shuriken.json"
}
