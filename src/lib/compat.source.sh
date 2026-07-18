# Cross-platform tool resolution and runtime compatibility guard.
#
# shuriken relies on GNU-only extensions of four standard Unix tools -- find
# -printf, stat -c, cp -a, and sort -R (see the "Platform compatibility"
# section of README.md). Those extensions are not supported by the BSD
# variants of the same tools shipped with macOS and FreeBSD. Rather than being
# Linux-only, shuriken resolves each of the four tools to a variable (FIND,
# STAT, CP, SORT) once at startup: on Linux the plain command is already GNU,
# and on macOS/FreeBSD the GNU version is normally installed side-by-side
# under a "g" prefix (gfind, gstat, gcp, gsort, via Homebrew/pkg -- see
# README.md) to avoid clobbering the system tools. This mirrors the
# $SED/$GREP/$DATE tool-selection variables in the sibling gemtexter project
# (github.com/snonux/gemtexter). Every call site elsewhere in the codebase
# that depends on the GNU-only behavior uses these variables instead of the
# bare command name; call sites that only need POSIX-portable behavior are
# left as plain "find"/"sort"/etc and are unaffected by any of this.
#
# require_gnu_tools (called from main, after CLI parsing and before
# run_action) verifies the resolved tools are genuinely GNU before any real
# work begins, so a misconfigured host fails fast with a clear error instead
# of failing confusingly deep inside generation.

# Resolve the binary name for a single bare coreutils/findutils tool name:
# the GNU-prefixed variant (e.g. "gfind" for "find") if one is on PATH,
# otherwise the bare name unchanged. On Linux a "g"-prefixed sibling is not
# normally installed, so this resolves to the bare (already-GNU) name; on
# macOS/FreeBSD it picks up the Homebrew/pkg-installed GNU version. No uname
# check is needed: preferring the g-prefixed binary when present is correct
# on every platform.
resolve_gnu_tool() {
    local -r bare_name="$1"

    if command -v "g$bare_name" >/dev/null 2>&1; then
        printf '%s\n' "g$bare_name"
    else
        printf '%s\n' "$bare_name"
    fi
}

FIND=$(resolve_gnu_tool find)
STAT=$(resolve_gnu_tool stat)
CP=$(resolve_gnu_tool cp)
SORT=$(resolve_gnu_tool sort)
readonly FIND STAT CP SORT

# Quick preflight: confirm each resolved tool self-reports as GNU before
# running the (slower) behavioral probes in require_gnu_tools. This gives a
# fast, specific error on a genuine BSD/macOS host that has no g-prefixed
# tools installed at all, naming exactly which tool and pointing at the
# README install instructions, rather than only failing on the deeper
# behavioral probe below. A tool whose --version output happens to lie (or
# omit a version string) still falls through to the behavioral probe, which
# is authoritative.
verify_gnu_tool_versions() {
    local -r tool="$1"
    local -r label="$2"
    local version_output

    version_output=$("$tool" --version 2>/dev/null || true)
    if [[ "$version_output" != *GNU* ]]; then
        printf 'ERROR: "%s" (%s) does not report itself as GNU.\n' \
            "$tool" "$label" >&2
        printf 'ERROR: Install GNU coreutils/findutils -- see the\n' >&2
        printf 'ERROR: "Platform compatibility" section of README.md.\n' >&2
        return 1
    fi
}

# Runtime compatibility guard: verify the resolved tools (FIND/STAT/CP/SORT)
# actually behave like the GNU variants shuriken depends on. Each probe
# exercises the exact GNU-only behavior the codebase relies on (rather than
# parsing --help/--version text, which is unstable across implementations),
# so a tool that merely claims to be GNU but lacks the feature still fails
# here. Called from main, after CLI parsing and before run_action, so the
# check runs before any real work begins.
require_gnu_tools() {
    local probe_dir

    verify_gnu_tool_versions "$FIND" find || return 1
    verify_gnu_tool_versions "$STAT" stat || return 1
    verify_gnu_tool_versions "$CP" cp || return 1
    verify_gnu_tool_versions "$SORT" sort || return 1

    probe_dir=$(mktemp -d 2>/dev/null) || return 1
    # shellcheck disable=SC2064 # expand probe_dir now, clean up on any return
    trap "rm -rf '$probe_dir'" RETURN

    probe_gnu_tool_behavior "$probe_dir"
}

# The behavioral half of require_gnu_tools, split out to keep each function
# under ~30 lines (per repo convention): probes FIND/STAT/CP/SORT's actual
# GNU-only behavior in a throwaway temp dir and reports via
# report_gnu_tool_failure on the first failure.
probe_gnu_tool_behavior() {
    local -r probe_dir="$1"; shift
    local probe_out
    local failed=''

    # GNU find supports the -printf action; BSD/macOS find does not.
    probe_out=$("$FIND" "$probe_dir" -maxdepth 0 -printf '%f\n' 2>/dev/null) \
        && [ -n "$probe_out" ] || failed='find (missing the -printf action)'

    # GNU stat uses -c FORMAT; BSD/macOS stat uses -f and rejects -c.
    if [ -z "$failed" ]; then
        printf 'probe\n' > "$probe_dir/file"
        probe_out=$("$STAT" -c '%s' "$probe_dir/file" 2>/dev/null) \
            && [[ "$probe_out" =~ ^[0-9]+$ ]] \
            || failed='stat (missing the -c option)'
    fi

    # GNU cp supports the -a archive flag; minimal/older BSD cp variants lack it.
    if [ -z "$failed" ]; then
        mkdir "$probe_dir/src"
        printf 'x\n' > "$probe_dir/src/inner"
        if ! "$CP" -a "$probe_dir/src" "$probe_dir/dest" 2>/dev/null \
            || [ ! -f "$probe_dir/dest/inner" ]; then
            failed='cp (missing the -a option)'
        fi
    fi

    # GNU sort supports -R (random shuffle); BSD sort lacks it.
    if [ -z "$failed" ]; then
        probe_out=$(printf 'a\nb\nc\n' | "$SORT" -R 2>/dev/null) \
            && [ -n "$probe_out" ] || failed='sort (missing the -R option)'
    fi

    [ -z "$failed" ] || report_gnu_tool_failure "$failed"
}

# Shared error reporter for require_gnu_tools/probe_gnu_tool_behavior: prints
# the clear "install GNU tools" message naming the offending tool/feature and
# returns 1 (never exits directly, so callers stay in control of unwinding).
report_gnu_tool_failure() {
    local -r failed="$1"; shift

    printf 'ERROR: shuriken requires the GNU versions of the standard Unix\n' >&2
    printf 'ERROR: tools (GNU coreutils/findutils). Non-GNU or unsupported: %s\n' \
        "$failed" >&2
    printf 'ERROR: On macOS/FreeBSD, install GNU coreutils/findutils (see the\n' >&2
    printf 'ERROR: "Platform compatibility" section of README.md) and retry.\n' >&2
    return 1
}
