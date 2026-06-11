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
