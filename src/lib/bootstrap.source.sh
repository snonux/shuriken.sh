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
    --title TEXT
    --height VALUE
    --thumbheight VALUE
    --maxpreviews N
    --image-jobs N
    --random-seed VALUE
    --splash
    --no-splash
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

output_is_quiet() {
    [ "$PHOTOALBUM_OUTPUT_MODE" = quiet ]
}

output_is_verbose() {
    [ "$PHOTOALBUM_OUTPUT_MODE" = verbose ]
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

resolve_default_rc_file() {
    local source_root

    if [ -f "$DEFAULTRC" ]; then
        printf '%s\n' "$DEFAULTRC"
        return
    fi

    source_root=$(resolve_source_root)

    if [ -n "$source_root" ]; then
        printf '%s\n' "$source_root/src/photoalbum.default.conf"
        return
    fi

    printf '%s\n' "$DEFAULTRC"
}

resolve_source_root() {
    local script_dir
    local source_root

    script_dir="$PHOTOALBUM_SOURCE_DIR"
    source_root=$(cd "$script_dir/.." && pwd)

    if [[ -f "$source_root/src/photoalbum.default.conf" \
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
    local -r rc_file=photoalbum.conf
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
        && "$default_rc_file" = "$source_root/src/photoalbum.default.conf" ]]; then
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
