#!/usr/bin/env bash
set -euo pipefail

# shuriken (c) 2011 - 2014, 2022 by Paul Buetow
# https://codeberg.org/snonux/shuriken.sh

declare -r VERSION='SHURIKENVERSION'
declare -r DEFAULTRC="${SHURIKEN_DEFAULT_RC:-/etc/default/shuriken}"
declare -r PACKAGED_TEMPLATE_DIR='/usr/share/shuriken/templates/default'
declare -r PACKAGED_ASSET_DIR='/usr/share/shuriken/assets'
DEFAULT_TEMPLATE_DIR="${SHURIKEN_DEFAULT_TEMPLATE_DIR:-$PACKAGED_TEMPLATE_DIR}"
declare -r DEFAULT_TEMPLATE_DIR
DEFAULT_ASSET_DIR="${SHURIKEN_DEFAULT_ASSET_DIR:-$PACKAGED_ASSET_DIR}"
declare -r DEFAULT_ASSET_DIR
SHURIKEN_OUTPUT_MODE="${SHURIKEN_OUTPUT_MODE:-normal}"
SHURIKEN_ACTIVE_GENERATION_PID=''
SHURIKEN_FORCE_GENERATE="${SHURIKEN_FORCE_GENERATE:-no}"
SHURIKEN_CURRENT_DATE_TEXT=''

declare -ra CLI_CONFIG_OVERRIDE_TARGETS=(
    INCOMING_DIR
    DIST_DIR
    TEMPLATE_DIR
    TITLE
    HEIGHT
    THUMBHEIGHT
    MAXPREVIEWS
    IMAGE_JOBS
    RANDOM_SEED
    SHUFFLE
    SPLASH_PAGE
    SYNC_DELETE
    TARBALL_INCLUDE
)
declare -Ar CLI_OPTION_KIND=(
    [--config]=value
    [--incoming]=value
    [--dist]=value
    [--template]=value
    [--title]=value
    [--height]=value
    [--thumbheight]=value
    [--maxpreviews]=value
    [--image-jobs]=value
    [--random-seed]=value
    [--shuffle]=flag
    [--no-shuffle]=flag
    [--splash]=flag
    [--no-splash]=flag
    [--tarball]=flag
    [--no-tarball]=flag
    [--force]=flag
    [--sync-delete]=flag
    [--no-sync-delete]=flag
    [--sync-destination]=value
    [--verbose]=output
    [--quiet]=output
    [--version]=action
    [--init]=action
    [--clean]=action
    [--generate]=action
    [--refresh-splash]=action
    [--sync]=action
    [--dry-run]=action
    [--print-config]=action
)
declare -Ar CLI_OPTION_TARGET=(
    [--config]=config_file
    [--verbose]=SHURIKEN_OUTPUT_MODE
    [--quiet]=SHURIKEN_OUTPUT_MODE
    [--force]=SHURIKEN_FORCE_GENERATE
)
declare -Ar CLI_OPTION_VALUE=(
    [--shuffle]=yes
    [--no-shuffle]=no
    [--splash]=yes
    [--no-splash]=no
    [--tarball]=yes
    [--no-tarball]=no
    [--force]=yes
    [--sync-delete]=yes
    [--no-sync-delete]=no
    [--verbose]=verbose
    [--quiet]=quiet
)
declare -Ar CLI_OPTION_CONFIG_TARGET=(
    [--incoming]=INCOMING_DIR
    [--dist]=DIST_DIR
    [--template]=TEMPLATE_DIR
    [--title]=TITLE
    [--height]=HEIGHT
    [--thumbheight]=THUMBHEIGHT
    [--maxpreviews]=MAXPREVIEWS
    [--image-jobs]=IMAGE_JOBS
    [--random-seed]=RANDOM_SEED
    [--shuffle]=SHUFFLE
    [--no-shuffle]=SHUFFLE
    [--splash]=SPLASH_PAGE
    [--no-splash]=SPLASH_PAGE
    [--tarball]=TARBALL_INCLUDE
    [--no-tarball]=TARBALL_INCLUDE
    [--sync-delete]=SYNC_DELETE
    [--no-sync-delete]=SYNC_DELETE
)
declare -Ar CLI_OPTION_ARGUMENT=(
    [--config]=path
    [--sync-destination]=destination
)

SHURIKEN_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
declare -r SHURIKEN_SOURCE_DIR

# SHURIKEN_LIB_SOURCES_BEGIN
# shellcheck source=src/lib/bootstrap.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/bootstrap.source.sh"
# shellcheck source=src/lib/system.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/system.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/template.source.sh"
# shellcheck source=src/lib/image.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/image.source.sh"
# shellcheck source=src/lib/album.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album.source.sh"
# shellcheck source=src/lib/config.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.source.sh"
# shellcheck source=src/lib/action.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/action.source.sh"
# SHURIKEN_LIB_SOURCES_END

main() {
    local action=''
    local config_file=''
    local has_config_overrides='no'
    local -A cli_overrides=()
    local -a cli_sync_destinations=()

    if (( $# == 0 )); then
        usage
        exit 1
    fi

    parse_cli_arguments "$@"
    run_action
}

main "$@"
