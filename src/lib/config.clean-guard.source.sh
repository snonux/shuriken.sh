# Destructive --clean path guard. Extracted from config.validate.source.sh
# (task tr0) so the safety-critical "refuse to rm -rf a dangerous DIST_DIR"
# policy lives in one isolated module with its own test surface, instead of
# being buried among the generic config validators.
#
# This module owns the single source of truth for the dangerous-path blocklist
# (the filesystem root, well-known system trees, HOME, and the current working
# directory) plus the canonicalization needed to apply it safely. It is kept
# separate because a regression here is catastrophic (it gates an unconditional
# rm -rf), so the policy and its guard tests deserve a dedicated home.
#
# It still leans on the generic helpers in config.validate.source.sh
# (require_config_var, config_error, validate_dist_dir); all libs are sourced
# before any code runs, so those call sites resolve at runtime regardless of
# module order.

# Resolve DIST_DIR to a canonical absolute path so the --clean guard cannot be
# bypassed via "." / trailing slashes / symlinks / relative paths. The directory
# itself may not exist yet (cleaning a stale config), so when it is missing we
# resolve its existing parent and append the basename. Output is printed; the
# caller captures it. Returns non-zero only if even the parent cannot resolve.
resolve_dist_dir_path() {
    local -r target_dir="$1"; shift
    local parent base

    if [ -d "$target_dir" ]; then
        ( cd "$target_dir" && pwd -P ) && return
        return 1
    fi

    # DIST_DIR does not exist: canonicalize the deepest existing ancestor and
    # re-attach the remaining path so symlinked parents are still resolved.
    parent=$(existing_parent_dir "$target_dir")
    base=${target_dir#"$parent"}
    base=${base#/}
    parent=$( cd "$parent" && pwd -P ) || return 1
    if [ -n "$base" ]; then
        printf '%s/%s\n' "$parent" "$base"
    else
        printf '%s\n' "$parent"
    fi
}

# Guard for the destructive --clean action: refuse to "rm -rf" DIST_DIR when it
# resolves to an empty value or a clearly dangerous location (filesystem root,
# the user's HOME, the current working directory, or a well-known system tree).
# This is the single place where the dangerous-path policy lives so it stays in
# sync. NOTE (ln0): this only guards against deleting the wrong tree; leftover
# staging artifacts are a separate concern handled by task ln0.
validate_clean_dist_dir() {
    local resolved home_resolved cwd_resolved
    local -a forbidden=(
        / /home /root /tmp /usr /etc /var /bin /sbin /lib /boot /opt
    )
    local entry

    require_config_var DIST_DIR || return

    # Reuse the shared DIST_DIR sanity checks (must be a directory, writable,
    # parent writable) before applying the destructive-path policy.
    validate_dist_dir || return

    resolved=$(resolve_dist_dir_path "$DIST_DIR") || {
        config_error "DIST_DIR $DIST_DIR could not be resolved"
        return 1
    }

    if [ -z "$resolved" ]; then
        config_error 'refusing to clean an empty DIST_DIR'
        return 1
    fi

    # Reject the filesystem root and well-known system directories outright.
    for entry in "${forbidden[@]}"; do
        if [ "$resolved" = "$entry" ]; then
            config_error \
                "refusing to clean DIST_DIR $resolved (dangerous path)"
            return 1
        fi
    done

    # Reject HOME and the current working directory themselves (deleting either
    # would be catastrophic and is never the intended DIST_DIR).
    if [ -n "${HOME:-}" ]; then
        home_resolved=$( cd "$HOME" 2>/dev/null && pwd -P ) || home_resolved=''
        if [ -n "$home_resolved" ] && [ "$resolved" = "$home_resolved" ]; then
            config_error \
                "refusing to clean DIST_DIR $resolved (is HOME)"
            return 1
        fi
    fi

    cwd_resolved=$(pwd -P)
    if [ "$resolved" = "$cwd_resolved" ]; then
        config_error \
            "refusing to clean DIST_DIR $resolved (is current directory)"
        return 1
    fi
}
