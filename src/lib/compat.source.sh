# Runtime compatibility guard: verify the standard Unix tools shuriken shells
# out to are the GNU variants. shuriken relies on GNU-only extensions -- find
# -printf, stat -c, cp -a, and sort -R -- that the BSD tools shipped with macOS
# and BSD systems do not provide (see the "Platform compatibility" section of
# README.md). require_gnu_tools probes each feature in a throwaway temp dir and
# exits with a clear error naming the offending tool if any probe fails, so the
# check runs before any real work begins (it is called from main, after CLI
# parsing and before run_action).
#
# The probes intentionally exercise the exact GNU-only behavior the codebase
# depends on rather than parsing --help text (which is unstable across
# implementations), so a tool that lacks the feature fails the probe regardless
# of its version string.

require_gnu_tools() {
    local probe_dir
    local probe_out
    local failed=''

    probe_dir=$(mktemp -d 2>/dev/null) || return 1
    # shellcheck disable=SC2064 # expand probe_dir now, clean up on any return
    trap "rm -rf '$probe_dir'" RETURN

    # GNU find supports the -printf action; BSD/macOS find does not.
    probe_out=$(find "$probe_dir" -maxdepth 0 -printf '%f\n' 2>/dev/null) \
        && [ -n "$probe_out" ] || failed='find (missing the -printf action)'

    # GNU stat uses -c FORMAT; BSD/macOS stat uses -f and rejects -c.
    if [ -z "$failed" ]; then
        printf 'probe\n' > "$probe_dir/file"
        probe_out=$(stat -c '%s' "$probe_dir/file" 2>/dev/null) \
            && [[ "$probe_out" =~ ^[0-9]+$ ]] \
            || failed='stat (missing the -c option)'
    fi

    # GNU cp supports the -a archive flag; minimal/older BSD cp variants lack it.
    if [ -z "$failed" ]; then
        mkdir "$probe_dir/src"
        printf 'x\n' > "$probe_dir/src/inner"
        if ! cp -a "$probe_dir/src" "$probe_dir/dest" 2>/dev/null \
            || [ ! -f "$probe_dir/dest/inner" ]; then
            failed='cp (missing the -a option)'
        fi
    fi

    # GNU sort supports -R (random shuffle); BSD sort lacks it.
    if [ -z "$failed" ]; then
        probe_out=$(printf 'a\nb\nc\n' | sort -R 2>/dev/null) \
            && [ -n "$probe_out" ] || failed='sort (missing the -R option)'
    fi

    if [ -n "$failed" ]; then
        printf 'ERROR: shuriken requires the GNU versions of the standard Unix\n' >&2
        printf 'ERROR: tools (GNU coreutils/findutils). Non-GNU or unsupported: %s\n' \
            "$failed" >&2
        printf 'ERROR: shuriken is Linux-only and will not run on macOS or BSD.\n' >&2
        return 1
    fi

    return 0
}
