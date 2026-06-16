# Path resolution. Split out of bootstrap.source.sh (task jn0) so the install /
# source-root / default-directory discovery and the rc-file/template-dir
# defaulting live apart from startup wiring and logging. These helpers resolve
# where the packaged config, templates and assets live (both when installed and
# when running from a source checkout) and initialise a fresh shuriken.conf.
# All library modules are sourced before any code runs, so definition order does
# not affect availability (e.g. init_config calls log_info from
# logging.source.sh).

resolve_default_rc_file() {
    local source_root

    if [ -f "$DEFAULTRC" ]; then
        printf '%s\n' "$DEFAULTRC"
        return
    fi

    source_root=$(resolve_source_root)

    if [ -n "$source_root" ]; then
        printf '%s\n' "$source_root/src/shuriken.default.conf"
        return
    fi

    printf '%s\n' "$DEFAULTRC"
}

resolve_source_root() {
    local script_dir
    local source_root

    script_dir="$SHURIKEN_SOURCE_DIR"
    source_root=$(cd "$script_dir/.." && pwd)

    if [[ -f "$source_root/src/shuriken.default.conf" \
        && -d "$source_root/share/templates/default" ]]; then
        printf '%s\n' "$source_root"
    fi
}

resolve_default_template_dir() {
    local source_root

    if [ -d "$DEFAULT_TEMPLATE_DIR" ]; then
        printf '%s\n' "$DEFAULT_TEMPLATE_DIR"
        return
    fi

    source_root=$(resolve_source_root)

    if [ -n "$source_root" ]; then
        printf '%s\n' "$source_root/share/templates/default"
        return
    fi

    printf '%s\n' "$DEFAULT_TEMPLATE_DIR"
}

resolve_default_asset_dir() {
    local source_root

    if [ -d "$DEFAULT_ASSET_DIR" ]; then
        printf '%s\n' "$DEFAULT_ASSET_DIR"
        return
    fi

    source_root=$(resolve_source_root)

    if [ -n "$source_root" ]; then
        printf '%s\n' "$source_root/assets/site"
        return
    fi

    printf '%s\n' "$DEFAULT_ASSET_DIR"
}

template_dir_uses_default() {
    if [ -z "${TEMPLATE_DIR+x}" ] || [ -z "$TEMPLATE_DIR" ]; then
        return 1
    fi

    case "$TEMPLATE_DIR" in
        "$PACKAGED_TEMPLATE_DIR"|"$DEFAULT_TEMPLATE_DIR")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

apply_template_dir_default() {
    if template_dir_uses_default; then
        TEMPLATE_DIR=$(resolve_default_template_dir)
    fi
}

init_config() {
    local -r rc_file=shuriken.conf
    local default_rc_file
    local rewritten_rc_file
    local source_root
    local source_template_dir

    if [ -f "$rc_file" ]; then
        printf 'Error: %s already exists\n' "$rc_file" >&2
        exit 1
    fi

    default_rc_file=$(resolve_default_rc_file)

    if [ ! -f "$default_rc_file" ]; then
        printf 'Error: Can not find config file %s\n' "$default_rc_file" >&2
        exit 1
    fi

    cp "$default_rc_file" "$rc_file"

    source_root=$(resolve_source_root)
    if [[ -n "$source_root" \
        && "$default_rc_file" = "$source_root/src/shuriken.default.conf" ]]; then
        source_template_dir="$source_root/share/templates/default"
        rewritten_rc_file=$(mktemp "${rc_file}.XXXXXX")
        if ! awk -v template_dir="$source_template_dir" \
            '/^TEMPLATE_DIR=/ {
                print "TEMPLATE_DIR=" template_dir
                next
            }
            { print }' "$rc_file" > "$rewritten_rc_file"; then
            rm -f "$rewritten_rc_file"
            exit 1
        fi
        cat "$rewritten_rc_file" > "$rc_file"
        rm -f "$rewritten_rc_file"
    fi

    log_info "Created ./$rc_file"
}
