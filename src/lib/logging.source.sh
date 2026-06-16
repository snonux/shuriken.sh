# Output/logging utilities. Split out of bootstrap.source.sh (task jn0) so the
# "how do we print to the user" concern lives apart from startup wiring and path
# resolution. These helpers read the SHURIKEN_OUTPUT_MODE global and are called
# from nearly every other module, so this file is kept early in LIB_SOURCES.
# All library modules are sourced before any code runs, so definition order does
# not affect availability.

output_is_quiet() {
    [ "$SHURIKEN_OUTPUT_MODE" = quiet ]
}

output_is_verbose() {
    [ "$SHURIKEN_OUTPUT_MODE" = verbose ]
}

log_info() {
    if ! output_is_quiet; then
        printf '%s\n' "$*"
    fi
}

log_verbose() {
    if output_is_verbose; then
        printf 'Verbose: %s\n' "$*"
    fi
}

log_warning() {
    printf 'WARNING: %s\n' "$*" >&2
}
