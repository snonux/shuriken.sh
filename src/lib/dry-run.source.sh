# Dry-run plan: describe what a generation run WOULD produce (directories, page
# and redirect counts, the planned tarball name) without writing anything. Moved
# out of album-metadata.source.sh (task 6r0): previewing a run is its own concern,
# distinct from the EXIF presentation that stays in the album module. The plan
# depends on count_incoming_images (image.source.sh) for the image tally and
# tarball_name_plan (archive.source.sh) for the planned archive name; both are
# sourced before this module and called at runtime, so source order documents the
# dependency without affecting availability. dry_run is the CLI entry point wired
# up from action.source.sh. Behaviour and signatures are unchanged by the move.

dry_run() {
    # shellcheck disable=SC2034
    local -A dry_run_plan=()

    collect_dry_run_plan dry_run_plan
    print_dry_run_plan dry_run_plan
}

collect_dry_run_page_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"
    local -r image_count="$1"; shift
    local -i page_count=0
    local -i redirect_count=0

    plan_ref["html_index_count"]=1
    plan_ref["page_count"]=0
    plan_ref["redirect_count"]=0
    plan_ref["details_count"]=0

    if (( image_count > 0 )); then
        page_count=$(( (image_count + MAXPREVIEWS - 1) / MAXPREVIEWS ))
        redirect_count=$(( page_count * 4 + 2 ))
        plan_ref["details_count"]="$image_count"
        plan_ref["page_count"]="$page_count"
        plan_ref["redirect_count"]="$redirect_count"
    fi
}

collect_dry_run_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"
    local -i image_count=0

    image_count=$(count_incoming_images)
    plan_ref=()
    plan_ref["config_source"]="$SHURIKEN_CONFIG_SOURCE"
    plan_ref["incoming_dir"]="$INCOMING_DIR"
    plan_ref["dist_dir"]="$DIST_DIR"
    plan_ref["template_dir"]="$TEMPLATE_DIR"
    plan_ref["title"]="$TITLE"
    plan_ref["height"]="$HEIGHT"
    plan_ref["thumbheight"]="$THUMBHEIGHT"
    plan_ref["maxpreviews"]="$MAXPREVIEWS"
    plan_ref["subdivide_percent"]="$THUMB_SUBDIVIDE_PERCENT"
    plan_ref["feature_percent"]="$THUMB_FEATURE_PERCENT"
    plan_ref["image_jobs"]="$IMAGE_JOBS"
    plan_ref["random_seed"]="$RANDOM_SEED"
    plan_ref["shuffle"]="$SHUFFLE"
    plan_ref["splash_page"]="$SPLASH_PAGE"
    plan_ref["stats_page"]="$STATS_PAGE"
    plan_ref["image_count"]="$image_count"
    plan_ref["tarball_include"]="$TARBALL_INCLUDE"
    plan_ref["tarball_name_plan"]='not planned'

    if [ "$TARBALL_INCLUDE" = yes ]; then
        plan_ref["tarball_name_plan"]=$(tarball_name_plan)
    fi

    collect_dry_run_page_plan "$plan_name" "$image_count"
}

print_dry_run_plan() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"

    printf 'Dry run: no files will be written.\n'
    printf 'Config source: %s\n' "${plan_ref["config_source"]}"
    printf 'Incoming directory: %s\n' "${plan_ref["incoming_dir"]}"
    printf 'Output directory: %s\n' "${plan_ref["dist_dir"]}"
    printf 'Template directory: %s\n' "${plan_ref["template_dir"]}"
    printf 'Title: %s\n' "${plan_ref["title"]}"
    printf 'Height: %s\n' "${plan_ref["height"]}"
    printf 'Thumb height: %s\n' "${plan_ref["thumbheight"]}"
    printf 'Max previews per page: %s\n' "${plan_ref["maxpreviews"]}"
    printf 'Subdivide percent: %s\n' "${plan_ref["subdivide_percent"]}"
    printf 'Feature percent: %s\n' "${plan_ref["feature_percent"]}"
    printf 'Image jobs: %s\n' "${plan_ref["image_jobs"]}"
    printf 'Random seed: %s\n' "${plan_ref["random_seed"]}"
    printf 'Shuffle: %s\n' "${plan_ref["shuffle"]}"
    printf 'Splash page: %s\n' "${plan_ref["splash_page"]}"
    printf 'Stats page: %s\n' "${plan_ref["stats_page"]}"
    printf 'Image count: %s\n' "${plan_ref["image_count"]}"
    printf 'Tarball setting: %s\n' "${plan_ref["tarball_include"]}"
    printf 'Tarball name plan: %s\n' "${plan_ref["tarball_name_plan"]}"

    printf 'Planned directories:\n'
    printf '  %s\n' "${plan_ref["dist_dir"]}"
    printf '  %s/photos\n' "${plan_ref["dist_dir"]}"
    printf '  %s/thumbs\n' "${plan_ref["dist_dir"]}"
    printf '  %s/blurs\n' "${plan_ref["dist_dir"]}"

    printf 'Planned generated files:\n'
    if [ "${plan_ref["splash_page"]}" = yes ]; then
        printf '  %s/index.html (%s splash page)\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["html_index_count"]}"
    else
        printf '  %s/index.html (%s album index redirect)\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["html_index_count"]}"
    fi
    printf '  %s/favicon.ico\n' "${plan_ref["dist_dir"]}"
    printf '  %s/shuriken.json\n' "${plan_ref["dist_dir"]}"
    printf '  %s/photos/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/thumbs/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/blurs/* (%s image files)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/page-*.html (%s preview pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["page_count"]}"
    printf '  %s/[page]-[image].html (%s view pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["image_count"]}"
    printf '  %s/[page]-[image]-details.html (%s details pages)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["details_count"]}"
    printf '  %s/[redirect].html (%s navigation redirects)\n' \
        "${plan_ref["dist_dir"]}" "${plan_ref["redirect_count"]}"
    if [ "${plan_ref["stats_page"]}" = yes ]; then
        # The exact filter mini-album set needs EXIF aggregation, which dry-run
        # does not perform, so list them as a wildcard under stats/.
        printf '  %s/stats/index.html (EXIF stats page)\n' \
            "${plan_ref["dist_dir"]}"
        printf '  %s/stats/*/ (filter mini-albums)\n' \
            "${plan_ref["dist_dir"]}"
    fi
    if [ "${plan_ref["tarball_include"]}" = yes ]; then
        printf '  %s/%s\n' \
            "${plan_ref["dist_dir"]}" "${plan_ref["tarball_name_plan"]}"
    fi
}
