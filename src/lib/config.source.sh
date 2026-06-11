print_shell_assignment() {
    local -r name="$1"; shift
    local -r value="$1"; shift

    printf '%s=%q\n' "$name" "$value"
}

print_shell_array_assignment() {
    local -r name="$1"; shift
    local value

    printf '%s=(' "$name"
    for value in "$@"; do
        printf ' %q' "$value"
    done
    printf ' )\n'
}

print_config() {
    local -a tar_opts=()
    local -a sync_destinations=()

    resolve_tar_opts tar_opts
    resolve_sync_destinations sync_destinations

    print_shell_assignment CONFIG_SOURCE "${PHOTOALBUM_CONFIG_SOURCE:-}"
    print_shell_assignment INCOMING_DIR "$INCOMING_DIR"
    print_shell_assignment DIST_DIR "$DIST_DIR"
    print_shell_assignment TEMPLATE_DIR "$TEMPLATE_DIR"
    print_shell_assignment TITLE "$TITLE"
    print_shell_assignment HEIGHT "${HEIGHT:-}"
    print_shell_assignment THUMBHEIGHT "$THUMBHEIGHT"
    print_shell_assignment MAXPREVIEWS "$MAXPREVIEWS"
    print_shell_assignment IMAGE_JOBS "$IMAGE_JOBS"
    print_shell_assignment IMAGEMAGICK_TIMEOUT "$IMAGEMAGICK_TIMEOUT"
    print_shell_assignment RANDOM_SEED "${RANDOM_SEED:-}"
    print_shell_assignment SHUFFLE "${SHUFFLE:-no}"
    print_shell_assignment SPLASH_PAGE "${SPLASH_PAGE:-yes}"
    print_shell_assignment TARBALL_INCLUDE "${TARBALL_INCLUDE:-no}"
    print_shell_assignment TARBALL_SUFFIX "${TARBALL_SUFFIX:-.tar}"
    print_shell_assignment TAR_TIMEOUT "$TAR_TIMEOUT"
    print_shell_array_assignment TAR_OPTS "${tar_opts[@]}"
    print_shell_assignment SYNC_DELETE "${SYNC_DELETE:-yes}"
    print_shell_array_assignment SYNC_DESTINATIONS "${sync_destinations[@]}"
    print_shell_assignment ORIGINAL_BASEPATH "${ORIGINAL_BASEPATH:-}"
}

sync_dist() {
    local destination
    local -a rsync_args=(-av)
    local -a sync_destinations=()

    resolve_sync_destinations sync_destinations

    if [ "${SYNC_DELETE:-yes}" = yes ]; then
        rsync_args+=(--delete)
    fi

    for destination in "${sync_destinations[@]}"; do
        log_info "Syncing $DIST_DIR/ to $destination"
        rsync "${rsync_args[@]}" "$DIST_DIR/" "$destination"
    done
}

existing_parent_dir() {
    local -r path="$1"; shift
    local existing_parent

    existing_parent=$(dirname "$path")

    while [ ! -e "$existing_parent" ]; do
        existing_parent=$(dirname "$existing_parent")
    done

    printf '%s\n' "$existing_parent"
}

generation_staging_dir() {
    local -r final_dist="$1"; shift
    local final_base
    local staging_parent

    final_base=$(basename "$final_dist")
    staging_parent=$(existing_parent_dir "$final_dist")

    mktemp -d "$staging_parent/.photoalbum.$final_base.staging.XXXXXX"
}

prepare_generation_staging_dir() {
    local -r final_dist="$1"; shift
    local -r staging_dir="$1"; shift
    local cache_dir

    if [ "$PHOTOALBUM_FORCE_GENERATE" = yes ]; then
        log_verbose 'Force generation enabled; not reusing existing output cache'
        return
    fi

    for cache_dir in photos thumbs blurs .photoalbum-cache; do
        if [ -d "$final_dist/$cache_dir" ]; then
            if ! mkdir -p "$staging_dir/$cache_dir"; then
                return 1
            fi
            if ! cp -a "$final_dist/$cache_dir/." "$staging_dir/$cache_dir/"; then
                return 1
            fi
        fi
    done
}

cleanup_generation_staging_dir() {
    if [ -n "${PHOTOALBUM_ACTIVE_STAGING_DIR:-}" ]; then
        rm -rf "$PHOTOALBUM_ACTIVE_STAGING_DIR"
        PHOTOALBUM_ACTIVE_STAGING_DIR=''
    fi
}

terminate_process_tree() {
    local -r signal="$1"; shift
    local -r pid="$1"; shift
    local child

    if [ -z "$pid" ]; then
        return
    fi

    while IFS= read -r child; do
        if [ -n "$child" ]; then
            terminate_process_tree "$signal" "$child"
        fi
    done < <(pgrep -P "$pid" 2>/dev/null || true)

    kill "-$signal" "$pid" 2>/dev/null || true
}

wait_for_process_exit() {
    local -r pid="$1"; shift
    local -i attempts=0

    while kill -0 "$pid" 2>/dev/null; do
        if (( attempts >= 20 )); then
            return 1
        fi
        (( ++attempts ))
        sleep 0.05
    done
}

terminate_active_generation() {
    local -r pid="${PHOTOALBUM_ACTIVE_GENERATION_PID:-}"

    if [ -z "$pid" ]; then
        return
    fi

    terminate_process_tree TERM "$pid"
    if ! wait_for_process_exit "$pid"; then
        terminate_process_tree KILL "$pid"
    fi
    wait "$pid" 2>/dev/null || true
    PHOTOALBUM_ACTIVE_GENERATION_PID=''
}

handle_generation_staging_signal() {
    local -r status="$1"; shift

    clear_generation_staging_traps
    terminate_active_generation
    cleanup_generation_staging_dir
    exit "$status"
}

clear_generation_staging_traps() {
    trap - EXIT INT TERM HUP PIPE
}

ignore_generation_staging_interrupts() {
    trap '' INT TERM HUP PIPE
}

replace_dist_with_staging() {
    local -r staging_dir="$1"; shift
    local -r final_dist="$1"; shift
    local backup_dist=''
    local backup_parent=''
    local final_base
    local final_parent
    local staging_parent
    local -i status=0

    final_base=$(basename "$final_dist")
    final_parent=$(dirname "$final_dist")
    staging_parent=$(existing_parent_dir "$final_dist")

    if ! mkdir -p "$final_parent"; then
        return 1
    fi

    if [ -e "$final_dist" ]; then
        if ! backup_parent=$(
            mktemp -d "$staging_parent/.photoalbum.$final_base.backup.XXXXXX"
        ); then
            return 1
        fi
        backup_dist="$backup_parent/dist"

        if ! mv "$final_dist" "$backup_dist"; then
            rm -rf "$backup_parent"
            return 1
        fi
    fi

    if mv "$staging_dir" "$final_dist"; then
        if [ -n "$backup_parent" ]; then
            rm -rf "$backup_parent"
        fi
        return 0
    else
        status=$?
    fi

    if [ -n "$backup_dist" ] && [ -e "$backup_dist" ]; then
        if [ -e "$final_dist" ] && ! rm -rf "$final_dist"; then
            printf 'ERROR: Failed to restore %s from %s\n' \
                "$final_dist" "$backup_dist" >&2
            return "$status"
        fi
        if ! mv "$backup_dist" "$final_dist"; then
            printf 'ERROR: Failed to restore %s from %s\n' \
                "$final_dist" "$backup_dist" >&2
            return "$status"
        fi
        rm -rf "$backup_parent"
    fi

    return "$status"
}

generate_staged() {
    local -r final_dist="$DIST_DIR"
    local staging_dir
    local -i status=0

    staging_dir=$(generation_staging_dir "$final_dist")
    log_verbose "Effective output directory: $final_dist"
    log_verbose "Generation staging directory: $staging_dir"
    PHOTOALBUM_ACTIVE_STAGING_DIR="$staging_dir"
    trap cleanup_generation_staging_dir EXIT
    trap 'handle_generation_staging_signal 130' INT
    trap 'handle_generation_staging_signal 143' TERM
    trap 'handle_generation_staging_signal 129' HUP
    trap 'handle_generation_staging_signal 141' PIPE

    if ! prepare_generation_staging_dir "$final_dist" "$staging_dir"; then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return 1
    fi

    set +e
    (
        set -e
        PHOTOALBUM_FINAL_DIST_DIR="$final_dist"
        export PHOTOALBUM_FINAL_DIST_DIR
        DIST_DIR="$staging_dir" generate
    ) &
    PHOTOALBUM_ACTIVE_GENERATION_PID=$!
    wait "$PHOTOALBUM_ACTIVE_GENERATION_PID"
    status=$?
    PHOTOALBUM_ACTIVE_GENERATION_PID=''
    set -e

    if (( status != 0 )); then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return "$status"
    fi

    ignore_generation_staging_interrupts
    set +e
    replace_dist_with_staging "$staging_dir" "$final_dist"
    status=$?
    set -e

    if (( status != 0 )); then
        cleanup_generation_staging_dir
        clear_generation_staging_traps
        return "$status"
    fi

    PHOTOALBUM_ACTIVE_STAGING_DIR=''
    clear_generation_staging_traps
}

resolve_config_file() {
    local -r config_file="${1:-}"

    if [ -n "$config_file" ]; then
        printf '%s\n' "$config_file"
    else
        printf '%s\n' ./photoalbum.conf
    fi
}

missing_config() {
    local -r config_file="$1"; shift

    printf 'Error: Can not find config file %s\n' "$config_file" >&2
    printf 'Run photoalbum --init to create ./photoalbum.conf.\n' >&2
    exit 1
}

apply_config_defaults() {
    HEIGHT="${HEIGHT:-}"
    IMAGE_JOBS="${IMAGE_JOBS:-3}"
    IMAGEMAGICK_TIMEOUT="${IMAGEMAGICK_TIMEOUT:-60}"
    ORIGINAL_BASEPATH="${ORIGINAL_BASEPATH:-}"
    RANDOM_SEED="${RANDOM_SEED:-}"
    SHUFFLE="${SHUFFLE:-no}"
    SPLASH_PAGE="${SPLASH_PAGE:-yes}"
    SYNC_DELETE="${SYNC_DELETE:-yes}"
    TARBALL_INCLUDE="${TARBALL_INCLUDE:-no}"
    TARBALL_SUFFIX="${TARBALL_SUFFIX:-.tar}"
    TAR_TIMEOUT="${TAR_TIMEOUT:-120}"
    if ! declare -p TAR_OPTS >/dev/null 2>&1; then
        TAR_OPTS=(-c)
    fi
    if ! declare -p SYNC_DESTINATIONS >/dev/null 2>&1; then
        SYNC_DESTINATIONS=()
    fi
}

option_value() {
    local -r option="$1"; shift
    local -r argument="${CLI_OPTION_ARGUMENT[$option]:-value}"

    if (( $# == 0 )) || [ -z "$1" ]; then
        printf 'Error: %s requires a %s\n' "$option" "$argument" >&2
        usage
        exit 1
    fi

    printf '%s\n' "$1"
}

apply_cli_override() {
    local -r config_target="$1"; shift

    if [[ -v "cli_overrides[$config_target]" ]]; then
        printf -v "$config_target" '%s' "${cli_overrides[$config_target]}"
    fi
}

apply_cli_overrides() {
    local config_target

    for config_target in "${CLI_CONFIG_OVERRIDE_TARGETS[@]}"; do
        apply_cli_override "$config_target"
    done

    if (( ${#cli_sync_destinations[@]} > 0 )); then
        SYNC_DESTINATIONS=("${cli_sync_destinations[@]}")
    fi
}

config_error() {
    local -r message="$1"; shift

    printf 'ERROR: %s\n' "$message" >&2
    return 1
}

require_config_var() {
    local -r name="$1"; shift

    if [ -z "${!name+x}" ] || [ -z "${!name}" ]; then
        config_error "$name must be set in photoalbum configuration"
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

set_cli_option_value() {
    local -r option="$1"; shift
    local -r value="$1"; shift
    local config_target

    if [ "$option" = --sync-destination ]; then
        cli_sync_destinations+=("$value")
        has_config_overrides='yes'
        return
    fi

    config_target="${CLI_OPTION_CONFIG_TARGET[$option]:-}"
    if [ -n "$config_target" ]; then
        cli_overrides["$config_target"]="$value"
        has_config_overrides='yes'
        return
    fi

    printf -v "${CLI_OPTION_TARGET[$option]}" '%s' "$value"
}

set_cli_constant_option() {
    local -r option="$1"; shift
    local -r value="${CLI_OPTION_VALUE[$option]}"
    local config_target

    config_target="${CLI_OPTION_CONFIG_TARGET[$option]:-}"
    if [ -n "$config_target" ]; then
        cli_overrides["$config_target"]="$value"
        has_config_overrides='yes'
        return
    fi

    printf -v "${CLI_OPTION_TARGET[$option]}" '%s' "$value"
}

set_cli_action() {
    local -r selected_action="$1"; shift

    if [ -n "$action" ]; then
        usage
        exit 1
    fi

    action="$selected_action"
}

parse_cli_arguments() {
    local option_arg
    local option
    local option_kind

    while (( $# > 0 )); do
        option="$1"
        shift

        option_kind="${CLI_OPTION_KIND[$option]:-}"
        case "$option_kind" in
            value)
                option_arg=$(option_value "$option" "$@")
                set_cli_option_value "$option" "$option_arg"
                shift
                ;;
            flag|output)
                set_cli_constant_option "$option"
                ;;
            action)
                set_cli_action "$option"
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
}
