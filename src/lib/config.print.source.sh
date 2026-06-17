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

    print_shell_assignment CONFIG_SOURCE "$SHURIKEN_CONFIG_SOURCE"
    print_shell_assignment INCOMING_DIR "$INCOMING_DIR"
    print_shell_assignment DIST_DIR "$DIST_DIR"
    print_shell_assignment TEMPLATE_DIR "$TEMPLATE_DIR"
    print_shell_assignment FAVICON "$FAVICON"
    print_shell_assignment SOURCE_URL "$SOURCE_URL"
    print_shell_assignment TITLE "$TITLE"
    print_shell_assignment HEIGHT "$HEIGHT"
    print_shell_assignment THUMBHEIGHT "$THUMBHEIGHT"
    print_shell_assignment MAXPREVIEWS "$MAXPREVIEWS"
    print_shell_assignment IMAGE_JOBS "$IMAGE_JOBS"
    print_shell_assignment IMAGEMAGICK_TIMEOUT "$IMAGEMAGICK_TIMEOUT"
    print_shell_assignment RANDOM_SEED "$RANDOM_SEED"
    print_shell_assignment SHUFFLE "$SHUFFLE"
    print_shell_assignment SPLASH_PAGE "$SPLASH_PAGE"
    print_shell_assignment STATS_PAGE "$STATS_PAGE"
    print_shell_assignment TARBALL_INCLUDE "$TARBALL_INCLUDE"
    print_shell_assignment TARBALL_SUFFIX "$TARBALL_SUFFIX"
    print_shell_assignment TAR_TIMEOUT "$TAR_TIMEOUT"
    print_shell_array_assignment TAR_OPTS "${tar_opts[@]}"
    print_shell_assignment SYNC_DELETE "$SYNC_DELETE"
    print_shell_array_assignment SYNC_DESTINATIONS "${sync_destinations[@]}"
    print_shell_assignment ORIGINAL_BASEPATH "$ORIGINAL_BASEPATH"
}
