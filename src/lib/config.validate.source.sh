config_error() {
    local -r message="$1"; shift

    printf 'ERROR: %s\n' "$message" >&2
    return 1
}

require_config_var() {
    local -r name="$1"; shift

    if [ -z "${!name+x}" ] || [ -z "${!name}" ]; then
        config_error "$name must be set in shuriken configuration"
        return 1
    fi
}

validate_positive_integer_config_var() {
    local -r name="$1"; shift
    local -r value="${!name}"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
        config_error "$name must be a positive integer"
        return 1
    fi
}

validate_optional_positive_integer_config_var() {
    local -r name="$1"; shift

    if [ -n "${!name:-}" ]; then
        validate_positive_integer_config_var "$name" || return
    fi
}

validate_yes_no_config_var() {
    local -r name="$1"; shift
    local -r value="${!name}"

    case "$value" in
        yes|no)
            ;;
        *)
            config_error "$name must be yes or no"
            return 1
            ;;
    esac
}

validate_dist_dir() {
    local existing_parent

    if [ -e "$DIST_DIR" ]; then
        if [ ! -d "$DIST_DIR" ]; then
            config_error "DIST_DIR $DIST_DIR must be a directory"
            return 1
        fi
        if [[ ! -w "$DIST_DIR" || ! -x "$DIST_DIR" ]]; then
            config_error "DIST_DIR $DIST_DIR must be writable"
            return 1
        fi

        return
    fi

    existing_parent=$(existing_parent_dir "$DIST_DIR")

    if [ ! -d "$existing_parent" ]; then
        config_error "DIST_DIR parent $existing_parent must be a directory"
        return 1
    fi
    if [[ ! -w "$existing_parent" || ! -x "$existing_parent" ]]; then
        config_error "DIST_DIR parent $existing_parent must be writable"
        return 1
    fi
}

validate_template_dir_access() {
    if [[ ! -d "$TEMPLATE_DIR" || ! -r "$TEMPLATE_DIR" \
        || ! -x "$TEMPLATE_DIR" ]]; then
        config_error "TEMPLATE_DIR $TEMPLATE_DIR must be a readable directory"
        return 1
    fi
}

validate_template_file() {
    local -r template_name="$1"; shift

    if [ ! -r "$TEMPLATE_DIR/$template_name.tmpl" ]; then
        config_error \
            "template file $TEMPLATE_DIR/$template_name.tmpl must be readable"
        return 1
    fi
}

validate_template_dir() {
    local template_name
    local -a required_templates=(
        details
        footer
        header
        next
        prev
        preview
        redirect
        view
    )

    validate_template_dir_access || return

    if [ "$SPLASH_PAGE" = yes ]; then
        required_templates+=(splash)
    fi

    for template_name in "${required_templates[@]}"; do
        validate_template_file "$template_name" || return
    done
}

validate_refresh_splash_config() {
    local required_var
    local -a required_vars=(
        TITLE
        DIST_DIR
        TEMPLATE_DIR
    )

    for required_var in "${required_vars[@]}"; do
        require_config_var "$required_var" || return
    done

    validate_yes_no_config_var SPLASH_PAGE || return

    if [ "$SPLASH_PAGE" != yes ]; then
        config_error 'SPLASH_PAGE must be yes to refresh the splash page'
        return 1
    fi

    validate_dist_dir || return

    validate_template_dir_access || return
    validate_template_file splash || return

    if [ ! -d "$DIST_DIR/photos" ]; then
        config_error "DIST_DIR photos directory $DIST_DIR/photos must exist"
        return 1
    fi

    if [ ! -d "$DIST_DIR/blurs" ]; then
        config_error "DIST_DIR blurs directory $DIST_DIR/blurs must exist"
        return 1
    fi
}

validate_imagemagick() {
    # Reuse the canonical detection in resolve_imagemagick_command instead of
    # duplicating the magick/convert probing here. Its own error message is
    # suppressed so we report the failure through config_error, keeping the
    # validation output consistent (single "ERROR: ..." line, return code 1).
    # imagemagick_command is a nameref output filled by the resolver; we only
    # care about the exit status here, not the resolved command.
    # shellcheck disable=SC2034
    local -a imagemagick_command=()

    if resolve_imagemagick_command convert imagemagick_command 2>/dev/null; then
        return
    fi

    config_error 'ImageMagick is required; install magick or convert'
    return 1
}

validate_common_config() {
    local required_var
    local -a required_vars=(
        TITLE
        THUMBHEIGHT
        MAXPREVIEWS
        IMAGE_JOBS
        INCOMING_DIR
        DIST_DIR
        TEMPLATE_DIR
    )

    for required_var in "${required_vars[@]}"; do
        require_config_var "$required_var" || return
    done

    validate_optional_positive_integer_config_var HEIGHT || return
    validate_positive_integer_config_var THUMBHEIGHT || return
    validate_positive_integer_config_var MAXPREVIEWS || return
    validate_positive_integer_config_var IMAGE_JOBS || return
    validate_positive_integer_config_var IMAGEMAGICK_TIMEOUT || return
    validate_positive_integer_config_var TAR_TIMEOUT || return
    validate_yes_no_config_var SHUFFLE || return
    validate_yes_no_config_var SPLASH_PAGE || return
    validate_yes_no_config_var STATS_PAGE || return
    validate_yes_no_config_var TARBALL_INCLUDE || return
    validate_favicon_config || return
}

# A custom FAVICON (when set) must be a readable file; empty means the bundled
# default favicon is used.
validate_favicon_config() {
    if [ -z "${FAVICON:-}" ]; then
        return
    fi
    if [ ! -f "$FAVICON" ] || [ ! -r "$FAVICON" ]; then
        config_error "FAVICON file $FAVICON must be a readable file"
        return 1
    fi
}

validate_generation_config() {
    local -r require_imagemagick="${1:-yes}"

    validate_common_config || return

    if [ ! -d "$INCOMING_DIR" ]; then
        config_error "You have to create $INCOMING_DIR first"
        return 1
    fi
    if [[ ! -r "$INCOMING_DIR" || ! -x "$INCOMING_DIR" ]]; then
        config_error "INCOMING_DIR $INCOMING_DIR must be readable"
        return 1
    fi

    validate_dist_dir || return
    validate_template_dir || return
    if [ "$require_imagemagick" = yes ]; then
        validate_imagemagick || return
    fi
}

validate_print_config() {
    # Passed by name to resolve_tar_opts.
    # shellcheck disable=SC2034
    local -a tar_opts=()
    local -a sync_destinations=()

    validate_common_config || return
    resolve_tar_opts tar_opts
    resolve_sync_destinations sync_destinations
    validate_yes_no_config_var SYNC_DELETE || return
}

validate_sync_destinations() {
    local -a sync_destinations=()

    resolve_sync_destinations sync_destinations

    if (( ${#sync_destinations[@]} == 0 )); then
        config_error 'SYNC_DESTINATIONS must contain at least one destination'
        return 1
    fi
}

validate_rsync() {
    if command -v rsync >/dev/null 2>&1; then
        return
    fi

    config_error 'rsync is required to sync generated output'
    return 1
}

validate_sync_config() {
    require_config_var DIST_DIR || return
    validate_yes_no_config_var SYNC_DELETE || return
    validate_sync_destinations || return

    if [[ ! -d "$DIST_DIR" || ! -r "$DIST_DIR" || ! -x "$DIST_DIR" ]]; then
        config_error "DIST_DIR $DIST_DIR must be a readable directory"
        return 1
    fi

    validate_rsync || return
}
