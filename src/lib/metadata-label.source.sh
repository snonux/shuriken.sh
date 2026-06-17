# Shared EXIF metadata label helpers. Extracted (task mn0) so the rule for
# turning a camera's Make + Model into one human-readable label lives in a
# single place instead of being duplicated in album-metadata.source.sh's
# tooltip builder and stats-aggregate.source.sh's leaderboard tally. This file
# is sourced before both callers (see LIB_SOURCES in the Justfile). All library
# modules are sourced before any code runs, so definition order only documents
# the dependency, it does not affect availability.

# Join a camera's EXIF Make + Model into one label, avoiding a duplicated
# manufacturer prefix. Many cameras already repeat the make inside the model
# (e.g. Make="Canon", Model="Canon EOS 5D"), so when the model equals the make
# or starts with "<make> " we keep the model alone ("Canon EOS 5D" rather than
# "Canon Canon EOS 5D"). Either field may be empty: an empty model yields the
# make, an empty make yields the model, and both empty yields an empty string.
camera_label_from_make_model() {
    local -r make="$1"; shift
    local -r model="$1"; shift

    if [ -z "$model" ]; then
        printf '%s' "$make"
        return
    fi
    if [ -z "$make" ]; then
        printf '%s' "$model"
        return
    fi
    case "$model" in
        "$make"|"$make "*) printf '%s' "$model" ;;
        *) printf '%s %s' "$make" "$model" ;;
    esac
}
