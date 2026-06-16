# Startup wiring: the CLI usage/help text plus the shared config-array parser.
# Logging utilities now live in logging.source.sh and path resolution in
# paths.source.sh (split out by task jn0). resolve_config_array stays here
# because it is the shared "array or scalar config" parser used by the config
# modules. All library modules are sourced before any code runs, so definition
# order does not affect availability.

usage() {
    cat - <<USAGE >&2
    Usage:
    $0 --generate [--config PATH] [OPTIONS]
    $0 --refresh-splash [--config PATH] [OPTIONS]
    $0 --sync [--config PATH] [OPTIONS]
    $0 --dry-run [--config PATH] [OPTIONS]
    $0 --print-config [--config PATH] [OPTIONS]
    $0 --clean [--config PATH] [OPTIONS]
    $0 --version
    $0 --init

    Options:
    --config PATH
    --incoming PATH
    --dist PATH
    --template PATH
    --favicon PATH
    --title TEXT
    --height VALUE
    --thumbheight VALUE
    --maxpreviews N
    --image-jobs N
    --random-seed VALUE
    --splash
    --no-splash
    --stats
    --no-stats
    --shuffle
    --no-shuffle
    --tarball
    --no-tarball
    --force
    --sync-destination DEST
    --sync-delete
    --no-sync-delete
    --verbose
    --quiet
USAGE
}

# Read a configuration value into the named array, accepting both Bash array
# and whitespace-separated scalar declarations of the same variable.
# This is shared by resolve_tar_opts and resolve_sync_destinations so the
# "array or scalar config" parsing lives in exactly one place.
#
# Arguments:
#   $1  name of the source config variable (e.g. TAR_OPTS)
#   $2  name of the destination array variable (nameref)
# Returns:
#   0 if the variable was declared (the destination may still be empty),
#   1 if the variable was not declared at all (lets callers apply defaults).
resolve_config_array() {
    local -r config_var="$1"; shift
    local -n config_array_ref="$1"; shift
    local config_decl

    config_array_ref=()

    # declare -p fails when the variable was never set; callers use the
    # non-zero return to distinguish "unset" from "set but empty".
    if ! config_decl=$(declare -p "$config_var" 2>/dev/null); then
        return 1
    fi

    case "$config_decl" in
        declare\ -a*\ "$config_var"=*)
            # Already a real array: copy it element by element.
            local -n config_source_ref="$config_var"
            # shellcheck disable=SC2034
            config_array_ref=("${config_source_ref[@]}")
            ;;
        *)
            # Scalar string: word-split it into the destination array.
            local -n config_scalar_ref="$config_var"
            if [ -n "${config_scalar_ref:-}" ]; then
                # shellcheck disable=SC2034
                read -r -a config_array_ref <<< "$config_scalar_ref"
            fi
            ;;
    esac
}
