#!/usr/bin/env bash
set -euo pipefail

# photoalbum (c) 2011 - 2014, 2022 by Paul Buetow
# https://codeberg.org/snonux/shuriken.sh

declare -r VERSION='PHOTOALBUMVERSION'
declare -r DEFAULTRC="${PHOTOALBUM_DEFAULT_RC:-/etc/default/photoalbum}"
declare -r PACKAGED_TEMPLATE_DIR='/usr/share/photoalbum/templates/default'
declare -r PACKAGED_ASSET_DIR='/usr/share/photoalbum/assets'
DEFAULT_TEMPLATE_DIR="${PHOTOALBUM_DEFAULT_TEMPLATE_DIR:-$PACKAGED_TEMPLATE_DIR}"
declare -r DEFAULT_TEMPLATE_DIR
DEFAULT_ASSET_DIR="${PHOTOALBUM_DEFAULT_ASSET_DIR:-$PACKAGED_ASSET_DIR}"
declare -r DEFAULT_ASSET_DIR
PHOTOALBUM_OUTPUT_MODE="${PHOTOALBUM_OUTPUT_MODE:-normal}"
PHOTOALBUM_ACTIVE_GENERATION_PID=''
PHOTOALBUM_FORCE_GENERATE="${PHOTOALBUM_FORCE_GENERATE:-no}"
PHOTOALBUM_CURRENT_DATE_TEXT=''

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
    [--verbose]=PHOTOALBUM_OUTPUT_MODE
    [--quiet]=PHOTOALBUM_OUTPUT_MODE
    [--force]=PHOTOALBUM_FORCE_GENERATE
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

PHOTOALBUM_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
declare -r PHOTOALBUM_SOURCE_DIR

# PHOTOALBUM_LIB_SOURCES_BEGIN
# shellcheck source=src/lib/bootstrap.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/bootstrap.source.sh"
# shellcheck source=src/lib/system.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/system.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/template.source.sh"
# shellcheck source=src/lib/image.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/image.source.sh"
# shellcheck source=src/lib/album.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/album.source.sh"
# shellcheck source=src/lib/config.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/config.source.sh"
# shellcheck source=src/lib/action.source.sh
source "$PHOTOALBUM_SOURCE_DIR/lib/action.source.sh"
# PHOTOALBUM_LIB_SOURCES_END

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
