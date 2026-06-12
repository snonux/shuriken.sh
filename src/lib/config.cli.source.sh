cli_option_property() {
    local -r option="$1"; shift
    local -r property="$1"; shift
    local spec
    local field
    local -a fields=()

    spec="${CLI_OPTION_SPEC[$option]:-}"
    read -r -a fields <<< "$spec"

    for field in "${fields[@]}"; do
        case "$field" in
            "$property="*)
                printf '%s\n' "${field#*=}"
                return
                ;;
        esac
    done
}

option_value() {
    local -r option="$1"; shift
    local argument

    argument=$(cli_option_property "$option" argument)
    argument="${argument:-value}"

    if (( $# == 0 )) || [ -z "$1" ]; then
        printf 'Error: %s requires a %s\n' "$option" "$argument" >&2
        usage
        exit 1
    fi

    printf '%s\n' "$1"
}

apply_cli_override() {
    local -r config_target="$1"; shift

    if [[ -v "SHURIKEN_CLI_OVERRIDES[$config_target]" ]]; then
        printf -v "$config_target" '%s' \
            "${SHURIKEN_CLI_OVERRIDES[$config_target]}"
    fi
}

apply_cli_overrides() {
    local config_target

    for config_target in "${CLI_CONFIG_OVERRIDE_TARGETS[@]}"; do
        apply_cli_override "$config_target"
    done

    if (( ${#SHURIKEN_CLI_SYNC_DESTINATIONS[@]} > 0 )); then
        SYNC_DESTINATIONS=("${SHURIKEN_CLI_SYNC_DESTINATIONS[@]}")
    fi
}

set_cli_option_value() {
    local -r option="$1"; shift
    local -r value="$1"; shift
    local append_target
    local config_target
    local target

    append_target=$(cli_option_property "$option" append)
    if [ -n "$append_target" ]; then
        local -n append_ref="$append_target"

        append_ref+=("$value")
        SHURIKEN_CLI_HAS_CONFIG_OVERRIDES='yes'
        return
    fi

    config_target=$(cli_option_property "$option" config)
    if [ -n "$config_target" ]; then
        SHURIKEN_CLI_OVERRIDES["$config_target"]="$value"
        SHURIKEN_CLI_HAS_CONFIG_OVERRIDES='yes'
        return
    fi

    target=$(cli_option_property "$option" target)
    printf -v "$target" '%s' "$value"
}

set_cli_constant_option() {
    local -r option="$1"; shift
    local config_target
    local target
    local value

    value=$(cli_option_property "$option" value)
    config_target=$(cli_option_property "$option" config)
    if [ -n "$config_target" ]; then
        SHURIKEN_CLI_OVERRIDES["$config_target"]="$value"
        SHURIKEN_CLI_HAS_CONFIG_OVERRIDES='yes'
        return
    fi

    target=$(cli_option_property "$option" target)
    printf -v "$target" '%s' "$value"
}

set_cli_action() {
    local -r selected_action="$1"; shift

    if [ -n "$SHURIKEN_CLI_ACTION" ]; then
        usage
        exit 1
    fi

    SHURIKEN_CLI_ACTION="$selected_action"
}

parse_cli_arguments() {
    local option_arg
    local option
    local option_kind

    while (( $# > 0 )); do
        option="$1"
        shift

        option_kind=$(cli_option_property "$option" kind)
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
