# ----------------------------------------------------------------------------
# Action registry (single source of truth, task gn0)
# ----------------------------------------------------------------------------
# ACTION_SPECS is the one place a CLI action is declared. Adding an action means
# appending one entry here (plus its handler/validation functions); neither
# run_action nor run_configured_action is touched again (Open/Closed). Each entry
# is a '|'-delimited spec (same encoding as src/shuriken.sh's CLI_OPTION_SPEC and
# stats-aggregate.source.sh's STATS_CATEGORIES):
#
#   flag|handler|requires_config|validation_fn|validation_arg
#
#   flag            the CLI action flag (also the SHURIKEN_CLI_ACTION value).
#   handler         function run to perform the action. For configured actions it
#                   is invoked via run_configured_action_body (in-process, status
#                   propagated); for non-config actions it is called directly.
#   requires_config yes  -> dispatched through run_configured_action: the config
#                          file is resolved/loaded/logged first, then the
#                          validation_fn and handler run.
#                   no   -> dispatched without loading any config (e.g. --version,
#                          --init); these reject any --config/override/--force via
#                          the shared run_unconfigured_action precheck.
#   validation_fn   validation function to run before the handler (empty for none,
#                   e.g. --version prints inline). Its non-zero status aborts the
#                   action before the handler runs, preserving the historical
#                   per-action pre-checks (validate_generation_config, etc.).
#   validation_arg  optional single argument passed to validation_fn (only
#                   --dry-run uses it: "no" tells validate_generation_config to
#                   skip the strict-generation checks).
#
# The array order is the canonical action order. Unknown or empty actions are not
# in the table, so run_action's "no entry" path reproduces the old case "*)" arm
# exactly (usage + exit 1).
# Declared -g so it survives being sourced from inside a function (the test
# harness sources the lib via test::source_shuriken_lib); a plain `declare -r`
# would be function-local and vanish on return.
declare -gra ACTION_SPECS=(
    '--version|action_print_version|no||'
    '--init|init_config|no||'
    '--clean|clean_dist|yes|validate_clean_dist_dir|'
    '--generate|generate_staged|yes|validate_generation_config|'
    '--refresh-splash|refresh_splash|yes|validate_refresh_splash_config|'
    '--sync|sync_dist|yes|validate_sync_config|'
    '--dry-run|dry_run|yes|validate_generation_config|no'
    '--print-config|print_config|yes|validate_print_config|'
)

# Look up a field of an action's registry entry by flag. Prints the requested
# field's value (empty if the action is unknown or the field is empty). Fields
# are addressed by zero-based index into the '|'-delimited spec:
#   0 flag  1 handler  2 requires_config  3 validation_fn  4 validation_arg
action_spec_field() {
    local -r action="$1"; shift
    local -ri field_index="$1"; shift
    local spec
    local -a fields=()

    for spec in "${ACTION_SPECS[@]}"; do
        IFS='|' read -r -a fields <<< "$spec"
        if [ "${fields[0]}" = "$action" ]; then
            printf '%s\n' "${fields[$field_index]:-}"
            return 0
        fi
    done

    return 1
}

# Print the registered handler for an action and the bundled version banner. Kept
# as a named function (not an inline printf) so --version is just another
# registry entry with a handler, like every other action.
action_print_version() {
    printf 'This is Shuriken Version %s\n' "$VERSION"
}

# Run a non-config action (requires_config=no): --version, --init. These never
# load a config, so any --config/override/--force is a usage error (matching the
# historical run_simple_action pre-check that guarded both arms identically).
run_unconfigured_action() {
    local -r action="$1"; shift
    local handler

    if [[ -n "$SHURIKEN_CLI_CONFIG_FILE" \
        || "$SHURIKEN_CLI_HAS_CONFIG_OVERRIDES" = 'yes' \
        || "$SHURIKEN_FORCE_GENERATE" = yes ]]; then
        usage
        exit 1
    fi

    handler=$(action_spec_field "$action" 1)
    "$handler"
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

# Remove leftover generation staging/backup directories for DIST_DIR (ln0).
#
# The generation pipeline (config.staging.source.sh) stages output in sibling
# directories of DIST_DIR named via mktemp templates
# ".shuriken.<basename>.staging.XXXXXX" and ".shuriken.<basename>.backup.XXXXXX"
# in DIST_DIR's parent. A crash or kill can leave these behind, so --clean
# removes them too -- otherwise "clean" would not actually clean all generation
# output (Principle of Least Astonishment).
#
# Safety: callers MUST run validate_clean_dist_dir first so a dangerous DIST_DIR
# aborts before any deletion. We only match shuriken's own, basename-specific
# staging/backup prefixes (never a loose ".shuriken.*" or arbitrary dotfiles),
# derive the parent exactly as the staging code does (dirname "$DIST_DIR"), and
# use nullglob so a missing match never expands to a literal pattern to rm.
clean_generation_staging_artifacts() {
    local final_base final_parent artifact
    local -a artifacts=()

    final_base=$(basename "$DIST_DIR")
    final_parent=$(dirname "$DIST_DIR")

    # nullglob: a non-matching glob expands to nothing rather than to the
    # literal pattern, so we never accidentally rm a path called "*".
    shopt -s nullglob
    artifacts=(
        "$final_parent/.shuriken.$final_base.staging."*
        "$final_parent/.shuriken.$final_base.backup."*
    )
    shopt -u nullglob

    for artifact in "${artifacts[@]}"; do
        if [ -d "$artifact" ]; then
            log_info "Cleaning leftover staging directory $artifact"
            rm -rf "$artifact"
        fi
    done
}

# --clean handler: remove DIST_DIR plus any leftover staging/backup dirs.
#
# Kept as a named handler (referenced from ACTION_SPECS) so --clean dispatches
# exactly like the other configured actions. Its validation (validate_clean_dist_dir,
# declared in the registry) has already run before this is called, so DIST_DIR is
# known safe -- unset, empty, and dangerous paths (/, HOME, cwd, system dirs) were
# rejected before any destructive rm -rf could happen.
clean_dist() {
    if [ -d "$DIST_DIR" ]; then
        log_info "Cleaning $DIST_DIR"
        rm -rf "$DIST_DIR"
    else
        log_verbose "Output directory does not exist: $DIST_DIR"
    fi

    # Also remove any leftover staging/backup directories that the generation
    # pipeline created as siblings of DIST_DIR. This stays behind the
    # validate_clean_dist_dir guard (so a dangerous DIST_DIR aborts before any
    # deletion).
    clean_generation_staging_artifacts
}

# Dispatch a configured action (requires_config=yes) via the registry.
#
# Shared scaffolding for every config-backed action: enforce the force-generate
# guard, resolve/load/log the config, then run the action's registered
# validation_fn and handler looked up in ACTION_SPECS. Adding a configured action
# is a registry entry plus its handler/validation functions -- this dispatcher
# never changes (Open/Closed).
run_configured_action() {
    local -r action="$SHURIKEN_CLI_ACTION"
    local rc_file
    local handler
    local validation_fn
    local validation_arg
    local -i status=0

    # --force only makes sense for --generate; any other configured action with
    # --force set is a usage error (unchanged historical behavior).
    if [[ "$SHURIKEN_FORCE_GENERATE" = yes && "$action" != --generate ]]; then
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

    validation_fn=$(action_spec_field "$action" 3)
    validation_arg=$(action_spec_field "$action" 4)
    if [ -n "$validation_fn" ]; then
        # Pass validation_arg only when present (--dry-run uses "no"); otherwise
        # call with no argument so validators see the same argv as before.
        if [ -n "$validation_arg" ]; then
            "$validation_fn" "$validation_arg"
        else
            "$validation_fn"
        fi
        status=$?
        if (( status != 0 )); then
            return "$status"
        fi
    fi

    handler=$(action_spec_field "$action" 1)
    run_configured_action_body "$handler"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}

# Top-level action dispatcher. Looks the parsed action up in ACTION_SPECS and
# routes it: requires_config=no actions run via run_unconfigured_action, the rest
# via run_configured_action. An unknown or empty action has no registry entry, so
# this reproduces the old case "*)" arm exactly: usage + exit 1.
run_action() {
    local -r action="$SHURIKEN_CLI_ACTION"
    local requires_config
    local -i status=0

    if ! requires_config=$(action_spec_field "$action" 2); then
        usage
        exit 1
    fi

    if [ "$requires_config" = no ]; then
        run_unconfigured_action "$action"
    else
        run_configured_action
    fi
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}
