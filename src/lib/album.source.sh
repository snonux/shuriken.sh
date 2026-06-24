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
    local -i status=0
    local tmp_html
    local tmp_path

    tmp_path=$(mktemp "$DIST_DIR/.index.html.XXXXXX")
    tmp_html=$(basename "$tmp_path")

    # Single cleanup point for the mktemp'd staging file, registered right after
    # mktemp so a signal between here and the final mv cannot leak it. Note that
    # --clean only sweeps .shuriken.*-prefixed artifacts, so it would NOT catch
    # this .index.html.XXXXXX file; the trap is the only thing that removes it on
    # interruption. We mirror source_template_file's idiom: RETURN covers both
    # normal and error returns (errexit unwinds through it) and the terminating
    # signals are trapped too, because a RETURN trap alone does not fire when a
    # signal kills the shell with its default disposition. The trap MUST be set
    # in refresh_splash's own body (a RETURN trap is not function-scoped unless
    # functrace is enabled). The handler clears ALL of these traps (including
    # itself) so a lingering RETURN trap cannot fire again on an enclosing
    # function's return against the now out-of-scope $tmp_html local. The
    # successful path below clears the trap before the mv so the file we just
    # renamed into place is not removed on return.
    trap 'rm -f "$DIST_DIR/$tmp_html"; trap - INT TERM HUP RETURN' RETURN INT TERM HUP

    # Render the splash page and copy site assets in errexit subshells, then
    # capture each subshell's status to decide whether to abort.
    #
    # The subshell MUST run as a standalone command (not inside an "if"/"||"
    # condition): bash ignores an inner "set -e" whenever a compound command is
    # part of a condition or &&/|| list, which would let render_album_splash_page
    # sail past a failing "photo=$(random_splash_photo ...)" instead of failing.
    # So we localize "set +e" around the bare subshell purely to stop the
    # parent's errexit from aborting before we can read $? and clean up.
    #
    # This is the project's canonical "localized set +e for expected failures"
    # idiom (see bash-best-practices). It replaces the old, fragile variant that
    # string-tested $- ("[[ $- == *e* ]]") to remember whether errexit had been
    # on: refresh_splash always runs under the top-level "set -euo pipefail", so
    # errexit is unconditionally restored with a plain "set -e" afterwards.
    status=0
    set +e
    ( set -e; render_album_splash_page 'photos' '.' 'blurs' '.' "$tmp_html" )
    status=$?
    set -e
    if (( status != 0 )); then
        return "$status"
    fi

    status=0
    set +e
    ( set -e; prepare_generation_site_assets )
    status=$?
    set -e
    if (( status != 0 )); then
        return "$status"
    fi

    # Promote the rendered temp file to index.html. Clear the cleanup trap first
    # so the RETURN handler does not delete the file we just moved into place.
    trap - RETURN INT TERM HUP
    mv "$DIST_DIR/$tmp_html" "$DIST_DIR/index.html"
    log_info "Refreshed splash page $(_display_path "$DIST_DIR/index.html")"
}
