run_simple_action() {
    case "$action" in
        --version)
            if [[ -n "$config_file" || "$has_config_overrides" = 'yes' \
                || "$PHOTOALBUM_FORCE_GENERATE" = yes ]]; then
                usage
                exit 1
            fi

            printf 'This is Photoalbum Version %s\n' "$VERSION"
            ;;
        --init)
            if [[ -n "$config_file" || "$has_config_overrides" = 'yes' \
                || "$PHOTOALBUM_FORCE_GENERATE" = yes ]]; then
                usage
                exit 1
            fi

            init_config
            ;;
    esac
}

load_configured_action() {
    local -r rc_file="$1"; shift

    if [ ! -f "$rc_file" ]; then
        missing_config "$rc_file"
    fi

    # shellcheck source=/dev/null
    source "$rc_file"
    apply_config_defaults
    apply_template_dir_default
    apply_cli_overrides
    PHOTOALBUM_CONFIG_SOURCE="$rc_file"
    export PHOTOALBUM_CONFIG_SOURCE
}

log_configured_action() {
    local -r rc_file="$1"; shift

    if [ "$action" = --print-config ]; then
        return
    fi

    log_verbose "Selected config file: $rc_file"
    log_verbose "Effective incoming directory: ${INCOMING_DIR:-}"
    log_verbose "Effective output directory: ${DIST_DIR:-}"
    log_verbose "Effective template directory: ${TEMPLATE_DIR:-}"
    log_verbose "Effective image jobs: ${IMAGE_JOBS:-3}"
    log_verbose "Effective ImageMagick timeout: ${IMAGEMAGICK_TIMEOUT:-60}s"
    log_verbose "Effective tar timeout: ${TAR_TIMEOUT:-120}s"
    log_verbose "Effective splash page setting: ${SPLASH_PAGE:-yes}"
    log_verbose "Effective tarball setting: ${TARBALL_INCLUDE:-no}"
    log_verbose "Effective sync delete setting: ${SYNC_DELETE:-yes}"
    log_verbose "Effective force generation setting: $PHOTOALBUM_FORCE_GENERATE"
}

run_configured_action() {
    local rc_file

    if [[ "$PHOTOALBUM_FORCE_GENERATE" = yes && "$action" != --generate ]]; then
        usage
        exit 1
    fi

    rc_file="$(resolve_config_file "$config_file")"
    load_configured_action "$rc_file"
    log_configured_action "$rc_file"

    case "$action" in
        --clean)
            if [ -d "$DIST_DIR" ]; then
                log_info "Cleaning $DIST_DIR"
                rm -rf "$DIST_DIR"
            else
                log_verbose "Output directory does not exist: $DIST_DIR"
            fi
            ;;
        --generate)
            validate_generation_config
            generate_staged
            ;;
        --refresh-splash)
            validate_refresh_splash_config
            refresh_splash
            ;;
        --sync)
            validate_sync_config
            sync_dist
            ;;
        --dry-run)
            validate_generation_config no
            dry_run
            ;;
        --print-config)
            validate_print_config
            print_config
            ;;
    esac
}

run_action() {
    case "$action" in
        --version|--init)
            run_simple_action
            ;;
        --clean|--generate|--refresh-splash|--sync|--dry-run|--print-config)
            run_configured_action
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}
