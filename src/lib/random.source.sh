random_seed_is_set() {
    [ -n "$RANDOM_SEED" ]
}

deterministic_index() {
    local -r namespace="$1"; shift
    local -r count="$1"; shift
    local checksum

    checksum=$(printf '%s' "${RANDOM_SEED}:$namespace" | cksum)
    checksum=${checksum%% *}

    printf '%s\n' $(( checksum % count ))
}

random_index() {
    local -r namespace="$1"; shift
    local -r count="$1"; shift

    if random_seed_is_set; then
        deterministic_index "$namespace" "$count"
    else
        printf '%s\n' $(( RANDOM % count ))
    fi
}

random_animation_css_class() {
    local -r speed="$1"; shift
    local -r context="${1:-$speed}"
    local -i index
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

    index=$(random_index "animation:$speed:$context" "${#classes[@]}")
    printf '%s\n' "${classes[index]}"
}

deterministic_shuffle() {
    local checksum
    local line

    while IFS= read -r line; do
        checksum=$(printf '%s' "${RANDOM_SEED}:shuffle:$line" | cksum)
        checksum=${checksum%% *}
        printf '%010u\t%s\n' "$checksum" "$line"
    done | sort -n -k1,1 -k2,2 | cut -f2-
}

maybe_shuffle() {
    if [ "$SHUFFLE" = yes ]; then
        if random_seed_is_set; then
            deterministic_shuffle
        else
            sort -R
        fi
    else
        sort
    fi
}
