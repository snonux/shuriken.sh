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

# Runs an action function in-process and propagates its exit status.
#
# Shuriken is a single-process CLI, so the action body runs as a plain function
# call in the current shell. An earlier version could serialize 30+ globals plus
# every function definition and pipe them into a fresh "bash -euo pipefail"
# subprocess for isolation. That added real complexity (a hand-maintained list
# of variables to forward) for no benefit here: there is no second process to
# isolate from and nothing the action needs protecting from. Per KISS we dropped
# the subprocess runner and call the action directly. Tests that genuinely need
# subprocess isolation provide their own shim in tests/helpers.sh.
run_configured_action_body() {
    local -r action_name="$1"; shift

    "$action_name" "$@"
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
    log_verbose "Effective favicon: ${FAVICON:-(bundled default)}"
    log_verbose "Effective image jobs: $IMAGE_JOBS"
    log_verbose "Effective ImageMagick timeout: ${IMAGEMAGICK_TIMEOUT}s"
    log_verbose "Effective tar timeout: ${TAR_TIMEOUT}s"
    log_verbose "Effective splash page setting: $SPLASH_PAGE"
    log_verbose "Effective stats page setting: $STATS_PAGE"
    log_verbose "Effective tarball setting: $TARBALL_INCLUDE"
    log_verbose "Effective sync delete setting: $SYNC_DELETE"
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
            # Validate DIST_DIR before any destructive rm -rf. Unlike the bare
            # check that used to live here, validate_clean_dist_dir rejects unset,
            # empty, and dangerous paths (/, HOME, cwd, system dirs) so a
            # misconfigured DIST_DIR can never nuke the wrong tree.
            validate_clean_dist_dir
            status=$?
            if (( status != 0 )); then
                return "$status"
            fi

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

            run_configured_action_body generate_staged
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

            run_configured_action_body refresh_splash
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

            run_configured_action_body sync_dist
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

            run_configured_action_body dry_run
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

            run_configured_action_body print_config
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
