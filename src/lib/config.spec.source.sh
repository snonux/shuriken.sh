# ----------------------------------------------------------------------------
# Config field registry (single source of truth, task mr0)
# ----------------------------------------------------------------------------
# CONFIG_SPECS is the one place a config field's cross-cutting facts are
# declared. Before mr0 the same knowledge (default value, CLI-overridability,
# validation rule, how it prints) was restated in ~6 hand-maintained lists --
# apply_config_defaults, CLI_CONFIG_OVERRIDE_TARGETS, validate_common_config,
# print_config, and parts of log_configured_action / the dry-run plan -- so
# adding or renaming an option was shotgun surgery and the lists drifted (the
# TARBALL_INCLUDE default once flipped to 'no' here while shuriken.default.conf
# still said 'yes', fixed in 7r0). Those consumers now DERIVE from this registry,
# so a field's facts live in exactly one entry.
#
# Each entry is a '|'-delimited spec, the same encoding used by ACTION_SPECS
# (action.source.sh) and TEMPLATE_RENDER_FIELD_SPECS (template.source.sh):
#
#   name|default|has_default|cli_overridable|validation|print_kind
#
#   name            the config variable name (also the env/override key).
#   default         the value apply_config_defaults applies via
#                   VAR="${VAR:-$default}" when has_default=yes. May be empty
#                   (e.g. FAVICON, HEIGHT default to the empty string).
#   has_default     yes -> apply the scalar default above. no -> never apply a
#                   scalar default: either a required var (TITLE, THUMBHEIGHT,
#                   ...) that must be set in the config, or an array
#                   (TAR_OPTS / SYNC_DESTINATIONS) defaulted separately via a
#                   `declare -p` guard in apply_config_defaults.
#   cli_overridable yes -> the field appears in CLI_CONFIG_OVERRIDE_TARGETS, i.e.
#                   a CLI flag (declared in CLI_OPTION_SPEC) can override it. The
#                   rich per-flag table (argument names, flag/value pairs) stays
#                   in CLI_OPTION_SPEC; this facet only drives the override-target
#                   list that used to be a separate hand-kept copy of it.
#   validation      the rule validate_common_config applies. Empty means
#                   validate_common_config does not check this field (SYNC_DELETE,
#                   the timeouts only checked on their own paths, etc. are
#                   validated elsewhere). One of:
#                     required        require_config_var (non-empty)
#                     required-posint require_config_var + positive integer
#                     posint          positive integer (no non-empty requirement)
#                     opt-posint      positive integer only if set (HEIGHT)
#                     percentage      integer 0..100
#                     yesno           literal yes or no
#                     favicon         validate_favicon_config (readable file/empty)
#   print_kind      how print_config emits the field. scalar -> %s=%q. array ->
#                   %s=( ... ) via the resolve_*-fed array printer. Empty means
#                   print_config does not emit it (none today). CONFIG_SOURCE is
#                   printed separately (it is the resolved config path, not a
#                   config variable) and so is not a registry entry.
#
# Entry order is the canonical print order (print_config emits in this order).
# validate_common_config does NOT reuse this order directly: it runs all
# `required*` checks before any kind check (so a missing required var is reported
# before a malformed one -- see test_config_validators_fail_fast_without_errexit),
# which it achieves with two filtered passes over the registry.
#
# Declared -g so it survives being sourced from inside a function (the test
# harness sources the lib via test::source_shuriken_lib); a plain `declare -r`
# would be function-local and vanish on return.
declare -gra CONFIG_SPECS=(
    'INCOMING_DIR||no|yes|required|scalar'
    'DIST_DIR||no|yes|required|scalar'
    'TEMPLATE_DIR||no|yes|required|scalar'
    'FAVICON||yes|yes|favicon|scalar'
    'SOURCE_URL|https://codeberg.org/snonux/shuriken.sh|yes|yes||scalar'
    'TITLE||no|yes|required|scalar'
    'HEIGHT||yes|yes|opt-posint|scalar'
    'THUMBHEIGHT||no|yes|required-posint|scalar'
    'MAXPREVIEWS||no|yes|required-posint|scalar'
    'THUMB_SUBDIVIDE_PERCENT|30|yes|yes|percentage|scalar'
    'THUMB_FEATURE_PERCENT|10|yes|yes|percentage|scalar'
    'IMAGE_JOBS|3|yes|yes|required-posint|scalar'
    'IMAGEMAGICK_TIMEOUT|60|yes|no|posint|scalar'
    'RANDOM_SEED||yes|yes||scalar'
    'SHUFFLE|no|yes|yes|yesno|scalar'
    'SPLASH_PAGE|yes|yes|yes|yesno|scalar'
    'STATS_PAGE|no|yes|yes|yesno|scalar'
    'TARBALL_INCLUDE|yes|yes|yes|yesno|scalar'
    'TARBALL_SUFFIX|.tar|yes|no||scalar'
    'TAR_TIMEOUT|120|yes|no|posint|scalar'
    'TAR_OPTS||no|no||array'
    'SYNC_DELETE|yes|yes|yes||scalar'
    'SYNC_TIMEOUT|300|yes|no|posint|scalar'
    'SYNC_DESTINATIONS||no|no||array'
    'ORIGINAL_BASEPATH||yes|no||scalar'
)

# Split one CONFIG_SPECS entry into the caller's named array (IFS='|' read), the
# same accessor pattern action_spec_field uses for ACTION_SPECS. Field indices:
#   0 name  1 default  2 has_default  3 cli_overridable  4 validation  5 print_kind
config_spec_split() {
    local -r spec="$1"; shift
    # shellcheck disable=SC2178
    local -n fields_ref="$1"; shift

    # fields_ref is a nameref output array filled for the caller; shellcheck
    # cannot see the indirect use through the nameref.
    # shellcheck disable=SC2034
    IFS='|' read -r -a fields_ref <<< "$spec"
}

# Populate CLI_CONFIG_OVERRIDE_TARGETS from the registry: every field marked
# cli_overridable=yes. This is the list apply_cli_overrides iterates to copy
# parsed --flag values onto their config var. Declared (empty) in src/shuriken.sh
# before the libs are sourced; filled here, once CONFIG_SPECS exists. Replaces the
# hand-kept copy of CLI_OPTION_SPEC's config= targets that used to drift (mr0).
# Iteration order is registry order; it is unobservable because each override
# targets a distinct variable, so no field can shadow another.
build_cli_config_override_targets() {
    local spec
    local -a fields=()

    CLI_CONFIG_OVERRIDE_TARGETS=()
    for spec in "${CONFIG_SPECS[@]}"; do
        config_spec_split "$spec" fields
        if [ "${fields[3]}" = yes ]; then
            CLI_CONFIG_OVERRIDE_TARGETS+=("${fields[0]}")
        fi
    done
}

# Build the override-target list at source time so it is ready before any CLI
# parsing. Guarded so sourcing this module without the shuriken.sh-level
# declaration (e.g. a narrowly scoped unit test) is a no-op rather than an error.
if declare -p CLI_CONFIG_OVERRIDE_TARGETS >/dev/null 2>&1; then
    build_cli_config_override_targets
fi
