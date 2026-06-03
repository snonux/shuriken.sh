#!/usr/bin/env bash
set -euo pipefail

# photoalbum (c) 2011 - 2014, 2022 by Paul Buetow
# https://codeberg.org/snonux/photoalbum

declare -r VERSION='PHOTOALBUMVERSION'
declare -r DEFAULTRC="${PHOTOALBUM_DEFAULT_RC:-/etc/default/photoalbum}"
PHOTOALBUM_OUTPUT_MODE="${PHOTOALBUM_OUTPUT_MODE:-normal}"

usage() {
    cat - <<USAGE >&2
    Usage:
    $0 --generate [--config PATH] [OPTIONS]
    $0 --dry-run [--config PATH] [OPTIONS]
    $0 --clean [--config PATH] [OPTIONS]
    $0 --version
    $0 --init

    Options:
    --config PATH
    --incoming PATH
    --dist PATH
    --template PATH
    --title TEXT
    --height VALUE
    --thumbheight VALUE
    --maxpreviews N
    --shuffle
    --no-shuffle
    --tarball
    --no-tarball
    --verbose
    --quiet
USAGE
}

output_is_quiet() {
    [ "$PHOTOALBUM_OUTPUT_MODE" = quiet ]
}

output_is_verbose() {
    [ "$PHOTOALBUM_OUTPUT_MODE" = verbose ]
}

log_info() {
    if ! output_is_quiet; then
        printf '%s\n' "$*"
    fi
}

log_verbose() {
    if output_is_verbose; then
        printf 'Verbose: %s\n' "$*"
    fi
}

log_warning() {
    printf 'WARNING: %s\n' "$*" >&2
}

resolve_default_rc_file() {
    local source_root

    if [ -f "$DEFAULTRC" ]; then
        printf '%s\n' "$DEFAULTRC"
        return
    fi

    source_root=$(resolve_source_root)

    if [ -n "$source_root" ]; then
        printf '%s\n' "$source_root/src/photoalbum.default.conf"
        return
    fi

    printf '%s\n' "$DEFAULTRC"
}

resolve_source_root() {
    local script_dir
    local source_root

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    source_root=$(cd "$script_dir/.." && pwd)

    if [[ -f "$source_root/src/photoalbum.default.conf" \
        && -d "$source_root/share/templates/default" ]]; then
        printf '%s\n' "$source_root"
    fi
}

init_config() {
    local -r rc_file=photoalbum.conf
    local default_rc_file
    local source_root
    local source_template_dir

    if [ -f "$rc_file" ]; then
        echo "Error: $rc_file already exists" >&2
        exit 1
    fi

    default_rc_file=$(resolve_default_rc_file)

    if [ ! -f "$default_rc_file" ]; then
        echo "Error: Can not find config file $default_rc_file" >&2
        exit 1
    fi

    cp "$default_rc_file" "$rc_file"

    source_root=$(resolve_source_root)
    if [[ -n "$source_root" \
        && "$default_rc_file" = "$source_root/src/photoalbum.default.conf" ]]; then
        source_template_dir="$source_root/share/templates/default"
        sed -i "s#^TEMPLATE_DIR=.*#TEMPLATE_DIR=$source_template_dir#" \
            "$rc_file"
    fi

    log_info "Created ./$rc_file"
}

imagemagick() {
    if command -v magick >/dev/null 2>&1; then
        magick "$@"
    elif command -v convert >/dev/null 2>&1; then
        convert "$@"
    else
        echo 'ERROR: ImageMagick is required; install magick or convert' >&2
        return 127
    fi
}

tarball() {
    local -r tarball_name="$1"; shift
    local -r tar_opts="${TAR_OPTS:--c}"
    local base

    # Cleanup tarball from prev run if any
    find "$DIST_DIR" -maxdepth 1 -type f -name '*.tar' -delete
    base=$(basename "$INCOMING_DIR")

    log_info "Creating tarball $(_display_path "$DIST_DIR/$tarball_name")" \
        "from $INCOMING_DIR"
    (
        cd "$(dirname "$INCOMING_DIR")"
        tar "$tar_opts" -f "$DIST_DIR/$tarball_name" "$base"
    )
}

_html_escape() {
    local text="$1"; shift

    text=${text//&/\&amp;}
    text=${text//</\&lt;}
    text=${text//>/\&gt;}
    text=${text//\"/\&quot;}
    text=${text//\'/\&#39;}

    printf '%s\n' "$text"
}

_css_string_escape() {
    local text="$1"; shift

    text=${text//\\/\\\\}
    text=${text//&/\\000026}
    text=${text//</\\00003c}
    text=${text//>/\\00003e}
    text=${text//\"/\\000022}
    text=${text//\'/\\000027}

    printf '%s\n' "$text"
}

_json_string_escape() {
    local text="$1"; shift
    local char
    local escaped=''
    local escaped_char
    local -i code
    local -i i
    local LC_ALL=C

    for (( i = 0; i < ${#text}; i++ )); do
        char="${text:i:1}"
        case "$char" in
            $'\\')
                escaped+=$'\\\\'
                ;;
            '"')
                escaped+='\"'
                ;;
            $'\b')
                escaped+='\b'
                ;;
            $'\f')
                escaped+='\f'
                ;;
            $'\n')
                escaped+='\n'
                ;;
            $'\r')
                escaped+='\r'
                ;;
            $'\t')
                escaped+='\t'
                ;;
            *)
                code=$(printf '%d' "'$char")
                if (( code < 32 )); then
                    printf -v escaped_char '\\u%04x' "$code"
                    escaped+="$escaped_char"
                else
                    escaped+="$char"
                fi
                ;;
        esac
    done

    printf '%s\n' "$escaped"
}

_json_string() {
    local -r text="$1"; shift

    printf '"%s"' "$(_json_string_escape "$text")"
}

_json_bool() {
    local -r value="$1"; shift

    case "$value" in
        yes)
            printf 'true'
            ;;
        *)
            printf 'false'
            ;;
    esac
}

_display_path() {
    local -r path="$1"; shift
    local -r final_dist="${PHOTOALBUM_FINAL_DIST_DIR:-}"

    if [[ -n "$final_dist" && "$path" == "$DIST_DIR"* ]]; then
        printf '%s%s\n' "$final_dist" "${path#"$DIST_DIR"}"
    else
        printf '%s\n' "$path"
    fi
}

template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    local -r dist_html="$DIST_DIR/$html_dir"
    local animation_class_html
    local backhref_css
    local backhref_html
    local background_image_css
    local blurs_dir_css
    local height_html
    local html_dir_html
    local maxpreviews_html
    local next_html
    local original_basepath_html
    local photo_html
    local photos_dir_html
    local prev_html
    local redirect_page_html
    local tarball_name_html
    local thumbheight_html
    local thumbs_dir_html
    local title_html

    log_info "Generating $(_display_path "$dist_html")/$html"

    mkdir -p "$dist_html"
    animation_class_html=$(_html_escape "${animation_class:-}")
    backhref_css=$(_css_string_escape "${backhref:-}")
    backhref_html=$(_html_escape "${backhref:-}")
    background_image_css=$(_css_string_escape "${background_image:-}")
    blurs_dir_css=$(_css_string_escape "${blurs_dir:-}")
    height_html=$(_html_escape "${HEIGHT:-}")
    html_dir_html=$(_html_escape "${html_dir:-}")
    maxpreviews_html=$(_html_escape "${MAXPREVIEWS:-}")
    next_html=$(_html_escape "${next:-}")
    original_basepath_html=$(_html_escape "${ORIGINAL_BASEPATH:-}")
    photo_html=$(_html_escape "${photo:-}")
    photos_dir_html=$(_html_escape "${photos_dir:-}")
    prev_html=$(_html_escape "${prev:-}")
    redirect_page_html=$(_html_escape "${redirect_page:-}")
    tarball_name_html=$(_html_escape "${tarball_name:-}")
    thumbheight_html=$(_html_escape "${THUMBHEIGHT:-}")
    thumbs_dir_html=$(_html_escape "${thumbs_dir:-}")
    title_html=$(_html_escape "${TITLE:-}")
    export \
        animation_class_html \
        backhref_css \
        backhref_html \
        background_image_css \
        blurs_dir_css \
        height_html \
        html_dir_html \
        maxpreviews_html \
        next_html \
        original_basepath_html \
        photo_html \
        photos_dir_html \
        prev_html \
        redirect_page_html \
        tarball_name_html \
        thumbheight_html \
        thumbs_dir_html \
        title_html

    source "$TEMPLATE_DIR/$template_name.tmpl" >> "$dist_html/$html"
}

cleanphotos() {
    local basename
    local photo
    local sub

    while IFS= read -r photo; do
        basename=$(basename "$photo")

        if [[ -f "$INCOMING_DIR/$basename" ]] \
            && is_supported_image_file "$basename"; then
            continue
        fi

        log_info "Cleaning up $(_display_path "$photo")"
        for sub in thumbs blurs photos; do
            if [ -f "$DIST_DIR/$sub/$basename" ]; then
                rm -f "$DIST_DIR/$sub/$basename"
                log_info "removed '$(_display_path "$DIST_DIR/$sub/$basename")'"
            fi
        done
    done < <(find "$DIST_DIR/photos" -maxdepth 1 -type f)
}

is_supported_image_file() {
    local -r file="$1"; shift
    local extension

    if [[ "$file" != *.* ]]; then
        return 1
    fi

    extension="${file##*.}"
    extension="${extension,,}"

    case "$extension" in
        gif|jpeg|jpg|png|webp)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

incoming_image_files() {
    local file

    while IFS= read -r file; do
        if is_supported_image_file "$file"; then
            printf '%s\n' "$file"
        fi
    done < <(find "$INCOMING_DIR" -maxdepth 1 -type f -printf '%f\n') \
        | sort
}

warn_unsupported_incoming_files() {
    local file

    while IFS= read -r file; do
        if ! is_supported_image_file "$file"; then
            log_warning "Ignoring unsupported incoming file: $file"
        fi
    done < <(find "$INCOMING_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
}

scalephotos() {
    local destphoto
    local dirname
    local photo

    while IFS= read -r photo; do
        destphoto="$DIST_DIR/photos/$photo"
        dirname=$(dirname "$destphoto")
        mkdir -p "$dirname"

        if [ -f "$destphoto" ]; then
            log_verbose "Skipped existing photo $(_display_path "$destphoto")"
            continue
        fi

        log_info "Processing $photo to $(_display_path "$destphoto")"
        if [ -n "${HEIGHT:-}" ]; then
            # Scale down size.
            imagemagick \
                "$INCOMING_DIR/$photo" \
                -auto-orient \
                -geometry "$HEIGHT" \
                "$destphoto"
        else
            # Keep original size.
            imagemagick \
                "$INCOMING_DIR/$photo" \
                -auto-orient \
                "$destphoto"
        fi
    done < <(incoming_image_files)
}

random_animation_css_class() {
    local -r speed="$1"; shift
    local -a classes=(
        "animate-opacity-$speed"
        "animate-top-$speed"
        "animate-left-$speed"
        "animate-right-$speed"
        "animate-bottom-$speed"
        "animate-zoom-$speed"
        "animate-snap-rotate-$speed"
        "animate-hard-zoom-$speed"
        "animate-slam-left-$speed"
        "animate-slam-right-$speed"
        "animate-flash-in-$speed"
        "animate-invert-pop-$speed"
        "animate-posterize-pop-$speed"
        "animate-skew-snap-$speed"
        "animate-glitch-step-$speed"
    )

    printf '%s\n' "${classes[@]}" | sort -R | sed -n '1p'
}

maybe_shuffle() {
    if [ "${SHUFFLE:-no}" = yes ]; then
        sort -R
    else
        sort
    fi
}

newest_html() {
    local -r pattern="$1"; shift

    find "$DIST_DIR/$html_dir" \
        -maxdepth 1 \
        -name "$pattern" \
        -printf '%T@ %f\n' \
        | sort -nr \
        | sed -n '1{s/^[^ ]* //;p}'
}

albumhtml() {
    local -r photos_dir="$1"; shift
    local -r html_dir="$1"; shift
    local -r thumbs_dir="$1"; shift
    local -r blurs_dir="$1"; shift
    local -r backhref="$1"; shift

    local animation_class
    local background_image
    local dirname
    local height
    local lastview
    local name
    local next
    local nextredirect
    local page
    local photo
    local prev
    local prefix
    local prevredirect
    local redirect_page
    local show_header_bar
    local -i i=0
    local -i num=1

    export backhref
    name="page-$num"

    # Random background image for preview page.
    background_image=$(randomphoto "$photos_dir")
    show_header_bar='yes'
    export background_image show_header_bar
    template 'header' "$name.html"

    while IFS= read -r photo; do
        (( ++i ))

        if (( i > MAXPREVIEWS )); then
            i=1
            (( ++num ))
            next="page-$num"
            prev="${prev:-}"
            export next prev
            template next "$name.html"
            template footer "$name.html"

            prev="$name"
            name="$next"

            background_image=$(randomphoto "$photos_dir")
            show_header_bar='no'
            export background_image prev show_header_bar
            template header "$name.html"
            template prev "$name.html"
        fi

        # Preview page.
        animation_class=$(random_animation_css_class slow)
        export animation_class
        template preview "$name.html"

        # View page.
        background_image="$photo"
        show_header_bar='no'
        export background_image show_header_bar
        template header "$num-$i.html"

        animation_class=$(random_animation_css_class fast)
        export animation_class
        template view "$num-$i.html"
        template footer "$num-$i.html"

        if [[ -f "$DIST_DIR/$thumbs_dir/$photo" \
            && -f "$DIST_DIR/$blurs_dir/$photo" ]]; then
            log_verbose "Skipped existing thumb and blur" \
                "$(_display_path "$DIST_DIR/$thumbs_dir/$photo") and" \
                "$(_display_path "$DIST_DIR/$blurs_dir/$photo")"
        else
            dirname="$DIST_DIR/$thumbs_dir"
            mkdir -p "$dirname"
            log_info "Creating thumb $(_display_path "$DIST_DIR/$thumbs_dir/$photo")"
            # Double the height, as CSS scales images based on boxing too.
            height=$(( THUMBHEIGHT * 2 ))
            imagemagick \
                "$DIST_DIR/$photos_dir/$photo" \
                -geometry "x$height" \
                "$DIST_DIR/$thumbs_dir/$photo"

            dirname="$DIST_DIR/$blurs_dir"
            mkdir -p "$dirname"
            log_info "Creating blur $(_display_path "$DIST_DIR/$blurs_dir/$photo")"
            imagemagick \
                "$DIST_DIR/$thumbs_dir/$photo" \
                -flip \
                -blur 0x8 \
                "$DIST_DIR/$blurs_dir/$photo"
        fi
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | maybe_shuffle
    )

    template footer "$(newest_html 'page-*.html')"

    while IFS= read -r prefix; do
        page=$(newest_html "$prefix-*.html" | sed 's#\(.*\)-.*.html#\1#')
        lastview=$(newest_html "$prefix-*.html" | sed 's/.*-\(.*\).html/\1/')

        prevredirect="${page}-0"
        nextredirect="${page}-$(( lastview + 1 ))"

        redirect_page="$(( page - 1 ))-${MAXPREVIEWS}"
        export redirect_page
        template redirect "$prevredirect.html"

        if (( lastview == MAXPREVIEWS )); then
            redirect_page="$(( page + 1 ))-1"
        else
            redirect_page="${page}-$lastview"
            export redirect_page
            template redirect "0-$MAXPREVIEWS.html"
            redirect_page='1-1'
        fi

        export redirect_page
        template redirect "$nextredirect.html"
    done < <(
        find "$DIST_DIR/$html_dir" \
            -maxdepth 1 \
            -name '*.html' \
            ! -name 'page-*' \
            -printf '%f\n' \
            | cut -d'-' -f1 \
            | sort -u
    )

    # Create per album index/redirect page.
    redirect_page='page-1'
    export redirect_page
    template 'redirect' 'index.html'
}

randomphoto() {
    local -r photos_dir="$1"; shift
    local photo
    local -a photos=()

    while IFS= read -r photo; do
        photos+=("$photo")
    done < <(
        find "$DIST_DIR/$photos_dir" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )

    if (( ${#photos[@]} == 0 )); then
        echo "ERROR: No photos found in" \
            "$(_display_path "$DIST_DIR/$photos_dir")" >&2
        return 1
    fi

    printf '%s\n' "${photos[RANDOM % ${#photos[@]}]}"
}

count_files() {
    local -r dir="$1"; shift
    local -r name="${1:-}"; shift || true

    if [ ! -d "$dir" ]; then
        printf '0\n'
        return
    fi

    if [ -n "$name" ]; then
        find "$dir" -maxdepth 1 -type f -name "$name" | wc -l
    else
        find "$dir" -maxdepth 1 -type f | wc -l
    fi
}

count_incoming_images() {
    incoming_image_files | wc -l
}

tarball_name_plan() {
    local base

    base=$(basename "$INCOMING_DIR")
    printf '%s-<timestamp>%s\n' "$base" "${TARBALL_SUFFIX:-.tar}"
}

generated_tarball_name() {
    local base
    local now

    base=$(basename "$INCOMING_DIR")
    now=$(date +'%Y-%m-%d-%H%M%S')
    printf '%s-%s%s\n' "$base" "$now" "${TARBALL_SUFFIX:-.tar}"
}

count_tree_files() {
    local -r dir="$1"; shift
    local -r name="$1"; shift

    if [ ! -d "$dir" ]; then
        printf '0\n'
        return
    fi

    find "$dir" -type f -name "$name" | wc -l
}

write_generation_metadata() {
    local -r tarball_file="$1"; shift
    local -r generated_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local -r config_source="${PHOTOALBUM_CONFIG_SOURCE:-}"
    local -r template_name=$(basename "$TEMPLATE_DIR")
    local -r source_image_count=$(count_incoming_images)
    local -r generated_photo_count=$(count_files "$DIST_DIR/photos")
    local -r generated_thumb_count=$(count_files "$DIST_DIR/thumbs")
    local -r generated_html_count=$(count_tree_files "$DIST_DIR" '*.html')

    {
        printf '{\n'
        printf '  "generator": {\n'
        printf '    "name": "photoalbum",\n'
        printf '    "version": %s\n' "$(_json_string "$VERSION")"
        printf '  },\n'
        printf '  "generated_at": %s,\n' "$(_json_string "$generated_at")"
        printf '  "config_source": %s,\n' "$(_json_string "$config_source")"
        printf '  "template": {\n'
        printf '    "name": %s,\n' "$(_json_string "$template_name")"
        printf '    "directory": %s\n' "$(_json_string "$TEMPLATE_DIR")"
        printf '  },\n'
        printf '  "source": {\n'
        printf '    "incoming_dir": %s,\n' "$(_json_string "$INCOMING_DIR")"
        printf '    "image_count": %s\n' "$source_image_count"
        printf '  },\n'
        printf '  "generated": {\n'
        printf '    "photo_count": %s,\n' "$generated_photo_count"
        printf '    "thumb_count": %s,\n' "$generated_thumb_count"
        printf '    "html_count": %s\n' "$generated_html_count"
        printf '  },\n'
        printf '  "tarball": {\n'
        printf '    "included": %s,\n' "$(_json_bool "${TARBALL_INCLUDE:-no}")"
        printf '    "file": %s\n' "$(_json_string "$tarball_file")"
        printf '  },\n'
        printf '  "settings": {\n'
        printf '    "title": %s,\n' "$(_json_string "${TITLE:-}")"
        printf '    "height": %s,\n' "$(_json_string "${HEIGHT:-}")"
        printf '    "thumbheight": %s,\n' "$(_json_string "${THUMBHEIGHT:-}")"
        printf '    "maxpreviews": %s,\n' "$(_json_string "${MAXPREVIEWS:-}")"
        printf '    "shuffle": %s,\n' "$(_json_bool "${SHUFFLE:-no}")"
        printf '    "original_basepath": %s\n' \
            "$(_json_string "${ORIGINAL_BASEPATH:-}")"
        printf '  }\n'
        printf '}\n'
    } > "$DIST_DIR/photoalbum.json"
}

generate() {
    local html_dir
    local redirect_page
    local tarball_name=''

    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        tarball_name=$(generated_tarball_name)
        log_verbose \
            "Tarball enabled; planned archive: $(_display_path "$DIST_DIR/$tarball_name")"
    else
        log_verbose 'Tarball disabled; no archive will be created'
    fi

    warn_unsupported_incoming_files
    mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos

    find "$DIST_DIR" -type f -name '*.html' -delete
    albumhtml 'photos' 'html' 'thumbs' 'blurs' '..'

    # Create top level index/redirect page.
    html_dir='./'
    redirect_page='./html/index'
    export redirect_page
    template 'redirect' 'index.html'

    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        tarball "$tarball_name"
    fi

    write_generation_metadata "$tarball_name"
}

dry_run() {
    local -i image_count=0
    local -i html_index_count=1
    local -i page_count=0
    local -i redirect_count=0

    image_count=$(count_incoming_images)

    if (( image_count > 0 )); then
        page_count=$(( (image_count + MAXPREVIEWS - 1) / MAXPREVIEWS ))
        redirect_count=$(( page_count * 2 ))
        if (( image_count % MAXPREVIEWS != 0 )); then
            (( ++redirect_count ))
        fi
    fi

    printf 'Dry run: no files will be written.\n'
    printf 'Config source: %s\n' "${PHOTOALBUM_CONFIG_SOURCE:-}"
    printf 'Incoming directory: %s\n' "$INCOMING_DIR"
    printf 'Output directory: %s\n' "$DIST_DIR"
    printf 'Template directory: %s\n' "$TEMPLATE_DIR"
    printf 'Title: %s\n' "$TITLE"
    printf 'Height: %s\n' "${HEIGHT:-}"
    printf 'Thumb height: %s\n' "$THUMBHEIGHT"
    printf 'Max previews per page: %s\n' "$MAXPREVIEWS"
    printf 'Shuffle: %s\n' "${SHUFFLE:-no}"
    printf 'Image count: %s\n' "$image_count"
    printf 'Tarball setting: %s\n' "${TARBALL_INCLUDE:-no}"
    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        printf 'Tarball name plan: %s\n' "$(tarball_name_plan)"
    else
        printf 'Tarball name plan: not planned\n'
    fi

    printf 'Planned directories:\n'
    printf '  %s\n' "$DIST_DIR"
    printf '  %s/photos\n' "$DIST_DIR"
    printf '  %s/thumbs\n' "$DIST_DIR"
    printf '  %s/blurs\n' "$DIST_DIR"
    printf '  %s/html\n' "$DIST_DIR"

    printf 'Planned generated files:\n'
    printf '  %s/index.html\n' "$DIST_DIR"
    printf '  %s/photoalbum.json\n' "$DIST_DIR"
    printf '  %s/photos/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/thumbs/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/blurs/* (%s image files)\n' "$DIST_DIR" "$image_count"
    printf '  %s/html/page-*.html (%s preview pages)\n' \
        "$DIST_DIR" "$page_count"
    printf '  %s/html/[page]-[image].html (%s view pages)\n' \
        "$DIST_DIR" "$image_count"
    printf '  %s/html/[redirect].html (%s navigation redirects)\n' \
        "$DIST_DIR" "$redirect_count"
    printf '  %s/html/index.html (%s album index redirect)\n' \
        "$DIST_DIR" "$html_index_count"
    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        printf '  %s/%s\n' "$DIST_DIR" "$(tarball_name_plan)"
    fi
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

    for cache_dir in photos thumbs blurs; do
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

clear_generation_staging_traps() {
    trap - EXIT INT TERM
}

ignore_generation_staging_interrupts() {
    trap '' INT TERM
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
            echo "ERROR: Failed to restore $final_dist from $backup_dist" >&2
            return "$status"
        fi
        if ! mv "$backup_dist" "$final_dist"; then
            echo "ERROR: Failed to restore $final_dist from $backup_dist" >&2
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
    trap 'cleanup_generation_staging_dir; exit 130' INT
    trap 'cleanup_generation_staging_dir; exit 143' TERM

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
        DIST_DIR="$staging_dir"
        generate
    )
    status=$?
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

    echo "Error: Can not find config file $config_file" >&2
    echo 'Run photoalbum --init to create ./photoalbum.conf.' >&2
    exit 1
}

apply_config_defaults() {
    HEIGHT="${HEIGHT:-}"
    ORIGINAL_BASEPATH="${ORIGINAL_BASEPATH:-}"
    SHUFFLE="${SHUFFLE:-no}"
    TARBALL_INCLUDE="${TARBALL_INCLUDE:-no}"
    TARBALL_SUFFIX="${TARBALL_SUFFIX:-.tar}"
    TAR_OPTS="${TAR_OPTS:--c}"
}

option_value() {
    local -r option="$1"; shift

    if (( $# == 0 )) || [ -z "$1" ]; then
        echo "Error: $option requires a value" >&2
        usage
        exit 1
    fi

    printf '%s\n' "$1"
}

apply_cli_overrides() {
    if [ -n "$cli_incoming_dir" ]; then
        INCOMING_DIR="$cli_incoming_dir"
    fi
    if [ -n "$cli_dist_dir" ]; then
        DIST_DIR="$cli_dist_dir"
    fi
    if [ -n "$cli_template_dir" ]; then
        TEMPLATE_DIR="$cli_template_dir"
    fi
    if [ -n "$cli_title" ]; then
        TITLE="$cli_title"
    fi
    if [ -n "$cli_height" ]; then
        HEIGHT="$cli_height"
    fi
    if [ -n "$cli_thumbheight" ]; then
        THUMBHEIGHT="$cli_thumbheight"
    fi
    if [ -n "$cli_maxpreviews" ]; then
        MAXPREVIEWS="$cli_maxpreviews"
    fi
    if [ -n "$cli_shuffle" ]; then
        SHUFFLE="$cli_shuffle"
    fi
    if [ -n "$cli_tarball_include" ]; then
        TARBALL_INCLUDE="$cli_tarball_include"
    fi
}

config_error() {
    local -r message="$1"; shift

    echo "ERROR: $message" >&2
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

validate_template_dir() {
    local template_name
    local -a required_templates=(
        footer
        header
        next
        prev
        preview
        redirect
        view
    )

    if [[ ! -d "$TEMPLATE_DIR" || ! -r "$TEMPLATE_DIR" \
        || ! -x "$TEMPLATE_DIR" ]]; then
        config_error "TEMPLATE_DIR $TEMPLATE_DIR must be a readable directory"
    fi

    for template_name in "${required_templates[@]}"; do
        if [ ! -r "$TEMPLATE_DIR/$template_name.tmpl" ]; then
            config_error \
                "template file $TEMPLATE_DIR/$template_name.tmpl must be readable"
        fi
    done
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

validate_generation_config() {
    local -r require_imagemagick="${1:-yes}"
    local required_var
    local -a required_vars=(
        TITLE
        THUMBHEIGHT
        MAXPREVIEWS
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
    validate_yes_no_config_var SHUFFLE
    validate_yes_no_config_var TARBALL_INCLUDE

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

main() {
    local action=''
    local config_file=''
    local has_config_overrides='no'
    local cli_dist_dir=''
    local cli_height=''
    local cli_incoming_dir=''
    local cli_maxpreviews=''
    local cli_shuffle=''
    local cli_tarball_include=''
    local cli_template_dir=''
    local cli_thumbheight=''
    local cli_title=''
    local option
    local rc_file

    if (( $# == 0 )); then
        usage
        exit 1
    fi

    while (( $# > 0 )); do
        option="$1"
        shift

        case "$option" in
            --config)
                if (( $# == 0 )) || [ -z "$1" ]; then
                    echo 'Error: --config requires a path' >&2
                    usage
                    exit 1
                fi

                config_file="$1"
                shift
                ;;
            --incoming)
                cli_incoming_dir=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --dist)
                cli_dist_dir=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --template)
                cli_template_dir=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --title)
                cli_title=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --height)
                cli_height=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --thumbheight)
                cli_thumbheight=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --maxpreviews)
                cli_maxpreviews=$(option_value "$option" "$@")
                has_config_overrides='yes'
                shift
                ;;
            --shuffle)
                cli_shuffle='yes'
                has_config_overrides='yes'
                ;;
            --no-shuffle)
                cli_shuffle='no'
                has_config_overrides='yes'
                ;;
            --tarball)
                cli_tarball_include='yes'
                has_config_overrides='yes'
                ;;
            --no-tarball)
                cli_tarball_include='no'
                has_config_overrides='yes'
                ;;
            --verbose)
                PHOTOALBUM_OUTPUT_MODE=verbose
                ;;
            --quiet)
                PHOTOALBUM_OUTPUT_MODE=quiet
                ;;
            --version|--init|--clean|--generate|--dry-run)
                if [ -n "$action" ]; then
                    usage
                    exit 1
                fi

                action="$option"
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    case "$action" in
        --version)
            if [[ -n "$config_file" || "$has_config_overrides" = 'yes' ]]; then
                usage
                exit 1
            fi

            echo "This is Photoalbum Version $VERSION"
            ;;
        --init)
            if [[ -n "$config_file" || "$has_config_overrides" = 'yes' ]]; then
                usage
                exit 1
            fi

            init_config
            ;;
        --clean|--generate|--dry-run)
            rc_file="$(resolve_config_file "$config_file")"

            if [ ! -f "$rc_file" ]; then
                missing_config "$rc_file"
            fi

            source "$rc_file"
            apply_config_defaults
            apply_cli_overrides
            PHOTOALBUM_CONFIG_SOURCE="$rc_file"
            export PHOTOALBUM_CONFIG_SOURCE
            log_verbose "Selected config file: $rc_file"
            log_verbose "Effective incoming directory: ${INCOMING_DIR:-}"
            log_verbose "Effective output directory: ${DIST_DIR:-}"
            log_verbose "Effective template directory: ${TEMPLATE_DIR:-}"
            log_verbose "Effective tarball setting: ${TARBALL_INCLUDE:-no}"

            case "$action" in
                --clean)
                    if [ -d "$DIST_DIR" ]; then
                        log_info "Cleaning $DIST_DIR"
                        rm -rf "$DIST_DIR"
                    else
                        log_verbose "Output directory does not exist: $DIST_DIR"
                    fi
                    ;;
                --generate)
                    validate_generation_config
                    generate_staged
                    ;;
                --dry-run)
                    validate_generation_config no
                    dry_run
                    ;;
            esac
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
