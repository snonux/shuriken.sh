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

# Emit the effective config as a re-sourceable block, driven by CONFIG_SPECS
# (task mr0): the field set and their print order are the registry order, and
# each field's print_kind facet selects scalar (%s=%q) vs array (%s=( ... ))
# output. This replaces the hand-kept print list that had to stay in lockstep
# with apply_config_defaults. CONFIG_SOURCE is printed first and is NOT a
# registry entry: it is the resolved config path, not a config variable.
#
# The two array fields are not plain shell variables at print time -- they are
# normalised through resolve_tar_opts / resolve_sync_destinations (which fill an
# unset/empty array with its default) -- so the loop dispatches array fields to
# those resolved local copies rather than reading the raw global.
print_config() {
    local -a tar_opts=()
    local -a sync_destinations=()
    local spec
    local -a fields=()
    local name print_kind

    resolve_tar_opts tar_opts
    resolve_sync_destinations sync_destinations

    print_shell_assignment CONFIG_SOURCE "$SHURIKEN_CONFIG_SOURCE"

    for spec in "${CONFIG_SPECS[@]}"; do
        config_spec_split "$spec" fields
        name="${fields[0]}"
        print_kind="${fields[5]}"

        case "$print_kind" in
            scalar)
                print_shell_assignment "$name" "${!name}"
                ;;
            array)
                case "$name" in
                    TAR_OPTS)
                        print_shell_array_assignment TAR_OPTS \
                            "${tar_opts[@]}"
                        ;;
                    SYNC_DESTINATIONS)
                        print_shell_array_assignment SYNC_DESTINATIONS \
                            "${sync_destinations[@]}"
                        ;;
                esac
                ;;
        esac
    done
}
