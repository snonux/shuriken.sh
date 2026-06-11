config_error() {
    local -r message="$1"; shift

    printf 'ERROR: %s\n' "$message" >&2
    return 1
}

require_config_var() {
    local -r name="$1"; shift

    if [ -z "${!name+x}" ] || [ -z "${!name}" ]; then
        config_error "$name must be set in shuriken configuration"
    fi
}

validate_positive_integer_config_var() {
    local -r name="$1"; shift
    local -r value="${!name}"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
        config_error "$name must be a positive integer"
    fi
}

validate_optional_positive_integer_config_var() {
    local -r name="$1"; shift

    if [ -n "${!name}" ]; then
        validate_positive_integer_config_var "$name"
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
            ;;
    esac
}

validate_dist_dir() {
    local existing_parent

    if [ -e "$DIST_DIR" ]; then
        if [ ! -d "$DIST_DIR" ]; then
            config_error "DIST_DIR $DIST_DIR must be a directory"
        fi
        if [[ ! -w "$DIST_DIR" || ! -x "$DIST_DIR" ]]; then
            config_error "DIST_DIR $DIST_DIR must be writable"
        fi

        return
    fi

    existing_parent=$(existing_parent_dir "$DIST_DIR")

    if [ ! -d "$existing_parent" ]; then
        config_error "DIST_DIR parent $existing_parent must be a directory"
    fi
    if [[ ! -w "$existing_parent" || ! -x "$existing_parent" ]]; then
        config_error "DIST_DIR parent $existing_parent must be writable"
    fi
}

validate_template_dir_access() {
    if [[ ! -d "$TEMPLATE_DIR" || ! -r "$TEMPLATE_DIR" \
        || ! -x "$TEMPLATE_DIR" ]]; then
        config_error "TEMPLATE_DIR $TEMPLATE_DIR must be a readable directory"
    fi
}

validate_template_file() {
    local -r template_name="$1"; shift

    if [ ! -r "$TEMPLATE_DIR/$template_name.tmpl" ]; then
        config_error \
            "template file $TEMPLATE_DIR/$template_name.tmpl must be readable"
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

    validate_template_dir_access

    if [ "${SPLASH_PAGE:-yes}" = yes ]; then
        required_templates+=(splash)
    fi

    for template_name in "${required_templates[@]}"; do
        validate_template_file "$template_name"
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
        require_config_var "$required_var"
    done

    validate_yes_no_config_var SPLASH_PAGE

    if [ "${SPLASH_PAGE:-yes}" != yes ]; then
        config_error 'SPLASH_PAGE must be yes to refresh the splash page'
    fi

    validate_dist_dir

    validate_template_dir_access
    validate_template_file splash

    if [ ! -d "$DIST_DIR/photos" ]; then
        config_error "DIST_DIR photos directory $DIST_DIR/photos must exist"
    fi

    if [ ! -d "$DIST_DIR/blurs" ]; then
        config_error "DIST_DIR blurs directory $DIST_DIR/blurs must exist"
    fi
}

validate_imagemagick() {
    if command -v magick >/dev/null 2>&1; then
        return
    fi
    if command -v convert >/dev/null 2>&1; then
        return
    fi

    config_error 'ImageMagick is required; install magick or convert'
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
        require_config_var "$required_var"
    done

    validate_optional_positive_integer_config_var HEIGHT
    validate_positive_integer_config_var THUMBHEIGHT
    validate_positive_integer_config_var MAXPREVIEWS
    validate_positive_integer_config_var IMAGE_JOBS
    validate_positive_integer_config_var IMAGEMAGICK_TIMEOUT
    validate_positive_integer_config_var TAR_TIMEOUT
    validate_yes_no_config_var SHUFFLE
    validate_yes_no_config_var SPLASH_PAGE
    validate_yes_no_config_var TARBALL_INCLUDE
}

validate_generation_config() {
    local -r require_imagemagick="${1:-yes}"

    validate_common_config

    if [ ! -d "$INCOMING_DIR" ]; then
        config_error "You have to create $INCOMING_DIR first"
    fi
    if [[ ! -r "$INCOMING_DIR" || ! -x "$INCOMING_DIR" ]]; then
        config_error "INCOMING_DIR $INCOMING_DIR must be readable"
    fi

    validate_dist_dir
    validate_template_dir
    if [ "$require_imagemagick" = yes ]; then
        validate_imagemagick
    fi
}

validate_print_config() {
    local -a tar_opts=()
    local -a sync_destinations=()

    validate_common_config
    resolve_tar_opts tar_opts
    resolve_sync_destinations sync_destinations
    validate_yes_no_config_var SYNC_DELETE
}

validate_sync_destinations() {
    local -a sync_destinations=()

    resolve_sync_destinations sync_destinations

    if (( ${#sync_destinations[@]} == 0 )); then
        config_error 'SYNC_DESTINATIONS must contain at least one destination'
    fi
}

validate_rsync() {
    if command -v rsync >/dev/null 2>&1; then
        return
    fi

    config_error 'rsync is required to sync generated output'
}

validate_sync_config() {
    require_config_var DIST_DIR
    validate_yes_no_config_var SYNC_DELETE
    validate_sync_destinations

    if [[ ! -d "$DIST_DIR" || ! -r "$DIST_DIR" || ! -x "$DIST_DIR" ]]; then
        config_error "DIST_DIR $DIST_DIR must be a readable directory"
    fi

    validate_rsync
}
