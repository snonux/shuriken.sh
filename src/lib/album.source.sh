# Album coordinator: ties together the image pipeline (image-pipeline.source.sh),
# page rendering and parallel orchestration (album-render.source.sh) and the EXIF
# caching / metadata / dry-run plumbing (album-metadata.source.sh) into the
# high-level generate / refresh-splash / dry-run flows the CLI actions call. All
# library modules are sourced before anything runs, so the helpers used here are
# defined regardless of file order.

copy_site_favicon() {
    local asset_dir
    local favicon_src

    # Use the configured favicon when set, otherwise the bundled default. Either
    # way it is published as favicon.ico (the name the templates link to).
    if [ -n "${FAVICON:-}" ]; then
        favicon_src="$FAVICON"
    else
        asset_dir=$(resolve_default_asset_dir)
        favicon_src="$asset_dir/favicon.ico"
    fi

    if [ ! -r "$favicon_src" ]; then
        config_error "favicon file $favicon_src must be readable"
        return 1
    fi

    log_verbose "Copying favicon to $(_display_path "$DIST_DIR/favicon.ico")"
    cp "$favicon_src" "$DIST_DIR/favicon.ico"
}

prepare_generation_site_assets() {
    copy_site_favicon
}

clear_rendered_html() {
    find "$DIST_DIR" -type f -name '*.html' -delete
}

create_generation_archive() {
    local -r tarball_name="$1"; shift

    if [ "$TARBALL_INCLUDE" = yes ]; then
        tarball "$tarball_name"
    fi
}

# Aggregate EXIF stats and render the stats page plus the per-camera pages into
# the dist root (html_dir and backhref are '.', matching render_album_pages).
# Run after the album pages so the per-photo identify cache is already warm.
generate_stats_pages() {
    log_verbose 'Stats page enabled; collecting EXIF stats'
    collect_photo_exif_stats
    # Keep the album root uncluttered: the stats overview is stats/index.html and
    # every filter mini-album lives under stats/<pagebase>/ (see render_filter_pages).
    render_stats_page stats .. index
    render_filter_pages
}

generate() {
    local tarball_name=''

    if [ "$TARBALL_INCLUDE" = yes ]; then
        tarball_name=$(generated_tarball_name)
        log_verbose \
            "Tarball enabled; planned archive:" \
            "$(_display_path "$DIST_DIR/$tarball_name")"
    else
        log_verbose 'Tarball disabled; no archive will be created'
    fi

    if [ "$SHURIKEN_FORCE_GENERATE" = yes ]; then
        clear_exif_cache
    fi
    prepare_generation_photo_assets
    prepare_generation_site_assets
    clear_rendered_html
    render_album_pages 'photos' '.' 'thumbs' 'blurs' '.' "$tarball_name"
    if [ "$STATS_PAGE" = yes ]; then
        generate_stats_pages
    fi
    create_generation_archive "$tarball_name"
    write_generation_metadata "$tarball_name"
}

refresh_splash() {
    local restore_errexit=no
    local -i status=0
    local tmp_html
    local tmp_path

    tmp_path=$(mktemp "$DIST_DIR/.index.html.XXXXXX")
    tmp_html=$(basename "$tmp_path")

    if [[ "$-" == *e* ]]; then
        restore_errexit=yes
        set +e
    fi
    (
        set -e
        render_album_splash_page 'photos' '.' 'blurs' '.' "$tmp_html"
    )
    status=$?
    if [ "$restore_errexit" = yes ]; then
        set -e
    fi
    if (( status != 0 )); then
        rm -f "$DIST_DIR/$tmp_html"
        return "$status"
    fi

    restore_errexit=no
    if [[ "$-" == *e* ]]; then
        restore_errexit=yes
        set +e
    fi
    (
        set -e
        prepare_generation_site_assets
    )
    status=$?
    if [ "$restore_errexit" = yes ]; then
        set -e
    fi
    if (( status != 0 )); then
        rm -f "$DIST_DIR/$tmp_html"
        return "$status"
    fi

    mv "$DIST_DIR/$tmp_html" "$DIST_DIR/index.html"
    log_info "Refreshed splash page $(_display_path "$DIST_DIR/index.html")"
}
