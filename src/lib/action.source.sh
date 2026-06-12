run_simple_action() {
    case "$SHURIKEN_CLI_ACTION" in
        --version)
            if [[ -n "$SHURIKEN_CLI_CONFIG_FILE" \
                || "$SHURIKEN_CLI_HAS_CONFIG_OVERRIDES" = 'yes' \
                || "$SHURIKEN_FORCE_GENERATE" = yes ]]; then
                usage
                exit 1
            fi

            printf 'This is Shuriken Version %s\n' "$VERSION"
            ;;
        --init)
            if [[ -n "$SHURIKEN_CLI_CONFIG_FILE" \
                || "$SHURIKEN_CLI_HAS_CONFIG_OVERRIDES" = 'yes' \
                || "$SHURIKEN_FORCE_GENERATE" = yes ]]; then
                usage
                exit 1
            fi

            init_config
            ;;
    esac
}

load_configured_action() {
    local -r rc_file="$1"; shift
    local -i status=0

    if [ ! -f "$rc_file" ]; then
        missing_config "$rc_file"
    fi

    # shellcheck source=/dev/null
    source "$rc_file"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    apply_config_defaults
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    apply_template_dir_default
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    apply_cli_overrides
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    SHURIKEN_CONFIG_SOURCE="$rc_file"
    export SHURIKEN_CONFIG_SOURCE
}

log_configured_action() {
    local -r rc_file="$1"; shift

    if [ "$SHURIKEN_CLI_ACTION" = --print-config ]; then
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
    log_verbose "Effective force generation setting: $SHURIKEN_FORCE_GENERATE"
}

run_configured_action() {
    local rc_file
    local -i status=0

    if [[ "$SHURIKEN_FORCE_GENERATE" = yes \
        && "$SHURIKEN_CLI_ACTION" != --generate ]]; then
        usage
        exit 1
    fi

    rc_file="$(resolve_config_file "$SHURIKEN_CLI_CONFIG_FILE")"
    load_configured_action "$rc_file"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    log_configured_action "$rc_file"

    case "$SHURIKEN_CLI_ACTION" in
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
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

            generate_staged
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        --refresh-splash)
            validate_refresh_splash_config
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

            refresh_splash
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        --sync)
            validate_sync_config
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

            sync_dist
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        --dry-run)
            validate_generation_config no
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

            dry_run
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        --print-config)
            validate_print_config
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

            print_config
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
    esac
}

run_action() {
    local -i status=0

    case "$SHURIKEN_CLI_ACTION" in
        --version|--init)
            run_simple_action
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        --clean|--generate|--refresh-splash|--sync|--dry-run|--print-config)
            run_configured_action
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}
