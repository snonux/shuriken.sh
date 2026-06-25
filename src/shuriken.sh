#!/usr/bin/env bash
set -euo pipefail

# shuriken (c) 2011 - 2014, 2022, 2025, 2026 by Paul Buetow
# https://codeberg.org/snonux/shuriken.sh

if (( BASH_VERSINFO[0] < 5 \
    || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1) )); then
    printf 'ERROR: shuriken requires Bash 5.1 or newer\n' >&2
    exit 1
fi

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
SHURIKEN_CLI_ACTION=''
SHURIKEN_CLI_CONFIG_FILE=''
SHURIKEN_CLI_HAS_CONFIG_OVERRIDES='no'
declare -A SHURIKEN_CLI_OVERRIDES=()
declare -a SHURIKEN_CLI_SYNC_DESTINATIONS=()

declare -ra CLI_CONFIG_OVERRIDE_TARGETS=(
    INCOMING_DIR
    DIST_DIR
    TEMPLATE_DIR
    FAVICON
    TITLE
    HEIGHT
    THUMBHEIGHT
    MAXPREVIEWS
    THUMB_SUBDIVIDE_PERCENT
    THUMB_FEATURE_PERCENT
    IMAGE_JOBS
    RANDOM_SEED
    SHUFFLE
    SOURCE_URL
    SPLASH_PAGE
    STATS_PAGE
    SYNC_DELETE
    TARBALL_INCLUDE
)
declare -Ar CLI_OPTION_SPEC=(
    [--config]='kind=value target=SHURIKEN_CLI_CONFIG_FILE argument=path'
    [--favicon]='kind=value config=FAVICON argument=path'
    [--source-url]='kind=value config=SOURCE_URL argument=url'
    [--incoming]='kind=value config=INCOMING_DIR'
    [--dist]='kind=value config=DIST_DIR'
    [--template]='kind=value config=TEMPLATE_DIR'
    [--title]='kind=value config=TITLE'
    [--height]='kind=value config=HEIGHT'
    [--thumbheight]='kind=value config=THUMBHEIGHT'
    [--maxpreviews]='kind=value config=MAXPREVIEWS'
    [--subdivide]='kind=value config=THUMB_SUBDIVIDE_PERCENT'
    [--feature]='kind=value config=THUMB_FEATURE_PERCENT'
    [--image-jobs]='kind=value config=IMAGE_JOBS'
    [--random-seed]='kind=value config=RANDOM_SEED'
    [--shuffle]='kind=flag value=yes config=SHUFFLE'
    [--no-shuffle]='kind=flag value=no config=SHUFFLE'
    [--splash]='kind=flag value=yes config=SPLASH_PAGE'
    [--no-splash]='kind=flag value=no config=SPLASH_PAGE'
    [--stats]='kind=flag value=yes config=STATS_PAGE'
    [--no-stats]='kind=flag value=no config=STATS_PAGE'
    [--tarball]='kind=flag value=yes config=TARBALL_INCLUDE'
    [--no-tarball]='kind=flag value=no config=TARBALL_INCLUDE'
    [--force]='kind=flag value=yes target=SHURIKEN_FORCE_GENERATE'
    [--sync-delete]='kind=flag value=yes config=SYNC_DELETE'
    [--no-sync-delete]='kind=flag value=no config=SYNC_DELETE'
    [--sync-destination]='kind=value append=SHURIKEN_CLI_SYNC_DESTINATIONS argument=destination'
    [--verbose]='kind=output value=verbose target=SHURIKEN_OUTPUT_MODE'
    [--quiet]='kind=output value=quiet target=SHURIKEN_OUTPUT_MODE'
    [--version]='kind=action'
    [--init]='kind=action'
    [--clean]='kind=action'
    [--generate]='kind=action'
    [--refresh-splash]='kind=action'
    [--sync]='kind=action'
    [--dry-run]='kind=action'
    [--print-config]='kind=action'
)

SHURIKEN_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
declare -r SHURIKEN_SOURCE_DIR

# SHURIKEN_LIB_SOURCES_BEGIN
# shellcheck source=src/lib/logging.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/logging.source.sh"
# shellcheck source=src/lib/compat.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/compat.source.sh"
# shellcheck source=src/lib/bootstrap.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/bootstrap.source.sh"
# shellcheck source=src/lib/paths.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/paths.source.sh"
# shellcheck source=src/lib/imagemagick.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/imagemagick.source.sh"
# shellcheck source=src/lib/process.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/process.source.sh"
# shellcheck source=src/lib/archive.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/archive.source.sh"
# shellcheck source=src/lib/template.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/template.source.sh"
# shellcheck source=src/lib/job-pool.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/job-pool.source.sh"
# shellcheck source=src/lib/image.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/image.source.sh"
# shellcheck source=src/lib/random.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/random.source.sh"
# shellcheck source=src/lib/photo-list.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/photo-list.source.sh"
# shellcheck source=src/lib/image-pipeline.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/image-pipeline.source.sh"
# shellcheck source=src/lib/album-metadata.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album-metadata.source.sh"
# shellcheck source=src/lib/generation-metadata.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/generation-metadata.source.sh"
# shellcheck source=src/lib/dry-run.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/dry-run.source.sh"
# shellcheck source=src/lib/album-tile-layout.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album-tile-layout.source.sh"
# shellcheck source=src/lib/album-thumbnail-html.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album-thumbnail-html.source.sh"
# shellcheck source=src/lib/album-photo-select.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album-photo-select.source.sh"
# shellcheck source=src/lib/album-render.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album-render.source.sh"
# shellcheck source=src/lib/album.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/album.source.sh"
# shellcheck source=src/lib/config.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.source.sh"
# shellcheck source=src/lib/config.print.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.print.source.sh"
# shellcheck source=src/lib/config.sync.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.sync.source.sh"
# shellcheck source=src/lib/config.staging.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.staging.source.sh"
# shellcheck source=src/lib/config.validate.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.validate.source.sh"
# shellcheck source=src/lib/config.cli.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/config.cli.source.sh"
# shellcheck source=src/lib/action.source.sh
source "$SHURIKEN_SOURCE_DIR/lib/action.source.sh"
# SHURIKEN_LIB_SOURCES_END

main() {
    local -i status=0

    SHURIKEN_CLI_ACTION=''
    SHURIKEN_CLI_CONFIG_FILE=''
    SHURIKEN_CLI_HAS_CONFIG_OVERRIDES='no'
    SHURIKEN_CLI_OVERRIDES=()
    SHURIKEN_CLI_SYNC_DESTINATIONS=()

    if (( $# == 0 )); then
        usage
        exit 1
    fi

    parse_cli_arguments "$@"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    require_gnu_tools
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    run_action
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}

main "$@"
