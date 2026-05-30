#!/usr/bin/env bash
set -euo pipefail

# photoalbum (c) 2011 - 2014, 2022 by Paul Buetow
# https://codeberg.org/snonux/photoalbum

declare -r VERSION='PHOTOALBUMVERSION'
declare -r DEFAULTRC='/etc/default/photoalbum'

usage() {
    cat - <<USAGE >&2
    Usage:
    $0 clean|generate|version|makemake [rcfile]
USAGE
}

makemake() {
    [ ! -f ./photoalbumrc ] && cp "$DEFAULTRC" ./photoalbumrc
    cat <<MAKEFILE > ./Makefile
all:
	photoalbum generate photoalbumrc
clean:
	photoalbum clean photoalbumrc
MAKEFILE
    echo 'You may now customize ./photoalbumrc and run make'
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

    echo "Creating tarball $DIST_DIR/$tarball_name from $INCOMING_DIR"
    (
        cd "$(dirname "$INCOMING_DIR")"
        tar "$tar_opts" -f "$DIST_DIR/$tarball_name" "$base"
    )
}

template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    local -r dist_html="$DIST_DIR/$html_dir"

    echo "Generating $dist_html/$html"

    mkdir -p "$dist_html"
    source "$TEMPLATE_DIR/$template_name.tmpl" >> "$dist_html/$html"
}

cleanphotos() {
    local basename
    local photo
    local sub

    while IFS= read -r photo; do
        basename=$(basename "$photo")

        if [ -f "$INCOMING_DIR/$basename" ]; then
            continue
        fi

        echo "Cleaning up $photo"
        for sub in thumbs blurs photos; do
            if [ -f "$DIST_DIR/$sub/$basename" ]; then
                rm -v "$DIST_DIR/$sub/$basename"
            fi
        done
    done < <(find "$DIST_DIR/photos" -maxdepth 1 -type f)
}

scalephotos() {
    local destphoto
    local destphoto_nospace
    local dirname
    local photo

    while IFS= read -r photo; do
        destphoto="$DIST_DIR/photos/$photo"
        destphoto_nospace="${destphoto// /_}"
        dirname=$(dirname "$destphoto")
        mkdir -p "$dirname"

        if [ -f "$destphoto_nospace" ]; then
            echo "Already exists: $destphoto_nospace"
            continue
        fi

        echo "Processing $photo to $destphoto_nospace"
        if [ -n "${HEIGHT:-}" ]; then
            # Scale down size.
            imagemagick \
                -auto-orient \
                -geometry "$HEIGHT" \
                "$INCOMING_DIR/$photo" \
                "$destphoto_nospace"
        else
            # Keep original size.
            imagemagick \
                -auto-orient \
                "$INCOMING_DIR/$photo" \
                "$destphoto_nospace"
        fi
    done < <(
        find "$INCOMING_DIR" -maxdepth 1 -type f -printf '%f\n' \
            | sort
    )
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
            echo "Already exists: $DIST_DIR/$thumbs_dir/$photo and" \
                "$DIST_DIR/$blurs_dir/$photo"
        else
            dirname="$DIST_DIR/$thumbs_dir"
            mkdir -p "$dirname"
            echo "Creating thumb $DIST_DIR/$thumbs_dir/$photo"
            # Double the height, as CSS scales images based on boxing too.
            height=$(( THUMBHEIGHT * 2 ))
            imagemagick \
                -geometry "x$height" \
                "$DIST_DIR/$photos_dir/$photo" \
                "$DIST_DIR/$thumbs_dir/$photo"

            dirname="$DIST_DIR/$blurs_dir"
            mkdir -p "$dirname"
            echo "Creating blur $DIST_DIR/$blurs_dir/$photo"
            imagemagick \
                -flip \
                -blur 0x8 \
                "$DIST_DIR/$thumbs_dir/$photo" \
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
        echo "ERROR: No photos found in $DIST_DIR/$photos_dir" >&2
        return 1
    fi

    printf '%s\n' "${photos[RANDOM % ${#photos[@]}]}"
}

generate() {
    local base
    local html_dir
    local now
    local redirect_page
    local tarball_name=''

    if [ ! -d "$INCOMING_DIR" ]; then
        echo "ERROR: You have to create $INCOMING_DIR first" >&2
        exit 1
    fi

    if [ "${TARBALL_INCLUDE:-no}" = yes ]; then
        base=$(basename "$INCOMING_DIR")
        now=$(date +'%Y-%m-%d-%H%M%S')
        tarball_name="${base}-${now}${TARBALL_SUFFIX:-.tar}"
    fi

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
}

resolve_rc_file() {
    local rc_file="${1:-}"

    if [ -n "$rc_file" ]; then
        printf '%s\n' "$rc_file"
    elif [ -f photoalbumrc ]; then
        printf '%s\n' photoalbumrc
    elif [ -f ~/.photoalbumrc ]; then
        printf '%s\n' ~/.photoalbumrc
    else
        printf '%s\n' "$DEFAULTRC"
    fi
}

apply_config_defaults() {
    HEIGHT="${HEIGHT:-}"
    ORIGINAL_BASEPATH="${ORIGINAL_BASEPATH:-}"
    SHUFFLE="${SHUFFLE:-no}"
    TARBALL_INCLUDE="${TARBALL_INCLUDE:-no}"
    TARBALL_SUFFIX="${TARBALL_SUFFIX:-.tar}"
    TAR_OPTS="${TAR_OPTS:--c}"
}

main() {
    local -r arg1="${1:-}"
    local -r rc_file="$(resolve_rc_file "${2:-}")"

    if [ ! -f "$rc_file" ]; then
        echo "Error: Can not find config file $rc_file" >&2
        exit 1
    fi

    source "$rc_file"
    apply_config_defaults

    case "$arg1" in
        clean)
            if [ -d "$DIST_DIR" ]; then
                rm -rf "$DIST_DIR"
            fi
            ;;
        generate)
            generate
            ;;
        version)
            echo "This is Photoalbum Version $VERSION"
            ;;
        makemake)
            makemake
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
