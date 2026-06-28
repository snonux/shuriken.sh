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
        # Predict the page and redirect counts from the SAME helpers a real
        # --generate uses (task nr0), so the preview can't drift from the actual
        # output. album_page_count_for_image_count (album-photo-select) owns the
        # MAXPREVIEWS-per-page grouping that album_page_records realises, and
        # album_redirect_count_for_page_count (album-render) owns the per-page +
        # last-page redirect tally that render_page_view_redirects emits. No dist
        # files are touched here, so dry-run stays side-effect free.
        page_count=$(album_page_count_for_image_count "$image_count")
        redirect_count=$(album_redirect_count_for_page_count "$page_count")
        plan_ref["details_count"]="$image_count"
        plan_ref["page_count"]="$page_count"
        plan_ref["redirect_count"]="$redirect_count"
    fi
}

# Gather every value the dry-run plan reports into an associative array, then
# hand it to print_dry_run_plan.
#
# Deliberately NOT derived from CONFIG_SPECS (task mr0, consumer 6). CONFIG_SPECS
# stays the single source of truth for the config SCHEMA (defaults, CLI,
# validation, print_config formatting), and the config VALUES read below
# ($INCOMING_DIR, $TITLE, $SPLASH_PAGE, ...) are the canonical globals
# apply_config_defaults already fills from the registry -- so there is no second
# source of truth for any config fact. But the plan is bespoke human-facing prose
# that interleaves config with NON-config: derived/computed values (the image,
# page, redirect and details counts, the planned tarball name, the index-page
# count) and whole non-config sections ("Planned directories:", "Planned
# generated files:") that have no registry entry. It also reports only a curated
# subset of fields, each with its own label and several with bespoke conditional
# rendering (splash-vs-redirect index line, stats/tarball blocks). Forcing this
# through a registry facet would need per-line label + format encoding plus markers
# for the non-config lines, contorting the schema for no DRY benefit (each label
# appears once). So presentation stays hand-written here; the dry-run plan tests
# assert the output byte-for-byte.
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

# Print the scalar settings block (config source through tarball name plan).
# Takes the plan array NAME and re-binds its own nameref so callers stay simple.
_print_dry_run_settings() {
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
}

# Print the planned directories and generated-files listing (index/favicon/json,
# image dirs, page/view/details/redirect counts, optional stats + tarball lines).
_print_dry_run_files() {
    local -r plan_name="$1"; shift
    # shellcheck disable=SC2178
    local -n plan_ref="$plan_name"

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

# Thin orchestrator: print the settings block then the planned files listing.
# Output is byte-identical to the previous single-function version.
print_dry_run_plan() {
    local -r plan_name="$1"; shift

    _print_dry_run_settings "$plan_name"
    _print_dry_run_files "$plan_name"
}
