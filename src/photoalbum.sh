#!/bin/env bash

# photoalbum (c) 2011 - 2014, 2022 by Paul Buetow
# https://codeberg.org/foozone/photoalbum

readonly VERSION='PHOTOALBUMVERSION'
readonly DEFAULTRC='/etc/default/photoalbum'
declare  ARG1="$1"    ; shift
declare  RC_FILE="$1" ; shift

usage () {
    cat - <<USAGE >&2
    Usage: 
    $0 clean|generate|version|makemake [rcfile]
USAGE
}

makemake () {
    [ ! -f ./photoalbumrc ] && cp "$DEFAULTRC" ./photoalbumrc
    cat <<MAKEFILE > ./Makefile
all:
	photoalbum generate photoalbumrc
clean:
	photoalbum clean photoalbumrc
MAKEFILE
    echo 'You may now customize ./photoalbumrc and run make'
}

tarball () {
    # Cleanup tarball from prev run if any
    find "$DIST_DIR" -maxdepth 1 -type f -name \*.tar -delete
    declare base="$(basename "$INCOMING_DIR")"

    echo "Creating tarball $DIST_DIR/$tarball_name from $INCOMING_DIR"
    cd "$(dirname "$INCOMING_DIR")"
    tar "$TAR_OPTS" -f "$DIST_DIR/$tarball_name" "$base"
    cd - &>/dev/null
}

template () {
    declare template="$1" ; shift
    declare html="$1"     ; shift
    declare dist_html="$DIST_DIR/$html_dir"
    echo "Generating $dist_html/$html"

    [ ! -d "$dist_html" ] && mkdir -p "$dist_html"
    source "$TEMPLATE_DIR/$template.tmpl" >> "$dist_html/$html"
}

cleanphotos () {
    find "$DIST_DIR/photos" -maxdepth 1 -type f | while read photo; do
        local basename=$(basename $photo)
        if [ -f "$INCOMING_DIR/$basename" ]; then
            continue
        fi
        echo "Cleaning up $photo"
        for sub in thumbs blurs photos; do
            if [ -f "$DIST_DIR/$sub/$basename" ]; then
                rm -v "$DIST_DIR/$sub/$basename"
            fi
        done
    done
}

scalephotos () {
    cd "$INCOMING_DIR" && find ./ -maxdepth 1 -type f | sort |
    while read -r photo; do
        declare photo="$(sed 's#^\./##' <<< "$photo")"
        declare destphoto="$DIST_DIR/photos/$photo"
        declare destphoto_nospace="${destphoto// /_}"
        declare dirname="$(dirname "$destphoto")"
        [ ! -d "$dirname" ] && mkdir -p "$dirname"

        if [ -f "$destphoto_nospace" ]; then
            echo "Already exists: $destphoto_nospace"
            continue
        fi

        echo "Processing $photo to $destphoto_nospace"
        if [ -n "$HEIGHT" ]; then
            # Scale down size.
            convert -auto-orient -geometry "$HEIGHT" "$photo" "$destphoto_nospace"
        else
            # Keep original size
            convert -auto-orient "$photo" "$destphoto_nospace"
        fi
    done
}

randomphoto () {
    declare photos_dir="$1" ; shift
    basename $(find "$photos_dir" -type f -maxpdeth 1 -mindepth 1 | sort -R | head -n 1)
}

random_animation_css_class () {
    local -r speed="$1"; shift
    cat <<END | grep -v fading | sort -R | head -n 1
animate-fading-$speed
animate-opacity-$speed
animate-top-$speed
animate-left-$speed
animate-right-$speed
animate-bottom-$speed
animate-zoom-$speed
END
}

maybe_shuffle () {
    if [ "$SHUFFLE" = yes ]; then
        sort -R
    else
        sort
    fi
}

albumhtml () {
    declare photos_dir="$1" ; shift
    declare html_dir="$1"   ; shift
    declare thumbs_dir="$1" ; shift
    declare blurs_dir="$1"  ; shift
    export backhref="$1"    ; shift

    declare -i num=1
    declare -i i=0
    declare name="page-$num"

    # Random background image for preview page.
    export background_image="$(randomphoto $photos_dir)"
    export show_header_bar='yes'
    template 'header' "$name.html"

    cd "$DIST_DIR/$photos_dir" && find ./ -type f | maybe_shuffle | sed 's;^\./;;' |
    while read -r photo; do 
        let i++

        if [ "$i" -gt "$MAXPREVIEWS" ]; then
            i=1
            let num++

            declare next="page-$num"
            template next "$name.html"
            template footer "$name.html"

            export prev="$name"
            declare name="$next"

            export background_image="$(randomphoto $photos_dir)"
            export show_header_bar='yes'
            template header "$name.html"
            template prev "$name.html"
        fi

        # Preview page
        export animation_class=$(random_animation_css_class slow)
        template preview "$name.html"

        # View page
        export background_image="$photo"
        export show_header_bar='no'
        template header "$num-$i.html"

        export animation_class=$(random_animation_css_class fast)
        template view "$num-$i.html"
        template footer "$num-$i.html"

        if [[ -f "$DIST_DIR/$thumbs_dir/$photo" && -f "$DIST_DIR/$blurs_dir/$photo" ]]; then 
            echo "Already exists: $DIST_DIR/$thumbs_dir/$photo and $DIST_DIR/$blurs_dir/$photo"
        else
            declare dirname="$DIST_DIR/$thumbs_dir"
            test ! -d "$dirname" && mkdir -p "$dirname"
            echo "Creating thumb $DIST_DIR/$thumbs_dir/$photo"
            # Double the height, as CSS will scale up/down images based on boxing too.
            declare height=$((THUMBHEIGHT * 2))
            convert -geometry "x$height" "$photo" "$DIST_DIR/$thumbs_dir/$photo"

            dirname="$DIST_DIR/$blurs_dir"
            test ! -d "$dirname" && mkdir -p "$dirname"
            echo "Creating blur $DIST_DIR/$blurs_dir/$photo"
            convert -flip -blur 0x8 "$DIST_DIR/$thumbs_dir/$photo" "$DIST_DIR/$blurs_dir/$photo"
        fi
    done

    template footer "$(cd "$DIST_DIR/$html_dir";ls -t page-*.html | head -n 1)"

    cd "$DIST_DIR/$html_dir" && ls | grep '.*\.html$' |
        grep -v page- | cut -d'-' -f1 | uniq |

    while read -r prefix; do 
        declare page="$(ls -t "$prefix"-*.html | head -n 1 | sed 's#\(.*\)-.*.html#\1#')"
        declare lastview="$(ls -t "$prefix"-*.html | head -n 1 | sed 's/.*-\(.*\).html/\1/')"

        declare prevredirect="${page}-0"
        declare nextredirect="${page}-$((lastview+1))"

        declare redirect_page="$(( page-1 ))-${MAXPREVIEWS}"
        template redirect "$prevredirect.html"

        if [ "$lastview" -eq "$MAXPREVIEWS" ]; then
            declare redirect_page="$(( page+1 ))-1"
        else
            declare redirect_page="${page}-$lastview"
            template redirect "0-$MAXPREVIEWS.html"
            redirect_page='1-1'
        fi

        export redirect_page
        template redirect "$nextredirect.html"
    done

    # Create per album index/redirect page
    declare redirect_page='page-1'
    template 'redirect' 'index.html'
}

randomphoto () {
    ls -f "$DIST_DIR/photos/" | sort -R | head -n 1
}

generate () {
    if [ ! -d "$INCOMING_DIR" ]; then
        echo "ERROR: You have to create $INCOMING_DIR first" >&2
        exit 1
    fi

    if [ "$TARBALL_INCLUDE" = yes ]; then
        declare base="$(basename "$INCOMING_DIR")"
        declare now="$(date +'%Y-%m-%d-%H%M%S')"
        declare tarball_name="${base}-${now}$TARBALL_SUFFIX"
    fi

    test ! -d "$DIST_DIR/photos" && mkdir -p "$DIST_DIR/photos"
    cleanphotos
    scalephotos

    find "$DIST_DIR" -type f -name \*.html -delete
    declare -a dirs=( $(find "$DIST_DIR/photos" -mindepth 1 -maxdepth 1 -type d | sort) )

    albumhtml 'photos' 'html' 'thumbs' 'blurs' '..'

    # Create top level index/redirect page
    declare html_dir='./'
    declare redirect_page='./html/index'
    template 'redirect' 'index.html'

    if [ "$TARBALL_INCLUDE" = 'yes' ]; then
        tarball
    fi
}

if [ -z "$RC_FILE" ]; then
    if [ -f photoalbumrc ]; then
        RC_FILE=photoalbumrc
    elif [ -f ~/.photoalbumrc ]; then
        RC_FILE=~/.photoalbumrc
    else
        RC_FILE="$DEFAULTRC"
    fi
fi

if [ ! -f "$RC_FILE" ]; then
    echo "Error: Can not find config file $RC_FILE" >&2
    exit 1
fi

source "$RC_FILE"

case "$ARG1" in
    clean)      [ -d "$DIST_DIR" ] && rm -Rf "$DIST_DIR";;
    generate)   generate;;
    version)    echo "This is Photoalbum Version $VERSION";;
    makemake)   makemake;;
    *)          usage;;
esac

exit 0
