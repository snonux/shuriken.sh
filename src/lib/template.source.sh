_html_escape() {
    local -r text="$1"; shift
    local escaped_text

    html_escape_to escaped_text "$text"
    printf '%s\n' "$escaped_text"
}

html_escape_to() {
    local -n output_ref="$1"; shift
    local text="$1"; shift

    text=${text//&/\&amp;}
    text=${text//</\&lt;}
    text=${text//>/\&gt;}
    text=${text//\"/\&quot;}
    text=${text//\'/\&#39;}

    output_ref="$text"
}

_css_string_escape() {
    local -r text="$1"; shift
    local escaped_text

    css_string_escape_to escaped_text "$text"
    printf '%s\n' "$escaped_text"
}

css_string_escape_to() {
    local -n output_ref="$1"; shift
    local text="$1"; shift

    text=${text//\\/\\\\}
    text=${text//&/\\000026}
    text=${text//</\\00003c}
    text=${text//>/\\00003e}
    text=${text//\"/\\000022}
    text=${text//\'/\\000027}

    output_ref="$text"
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
    local -r final_dist="${SHURIKEN_FINAL_DIST_DIR:-}"

    if [[ -n "$final_dist" && "$path" == "$DIST_DIR"* ]]; then
        printf '%s%s\n' "$final_dist" "${path#"$DIST_DIR"}"
    else
        printf '%s\n' "$path"
    fi
}

current_date_text() {
    if random_seed_is_set; then
        printf 'Thu Jan  1 00:00:00 UTC 1970\n'
    else
        command date
    fi
}

current_date_text_to() {
    local -n output_ref="$1"; shift

    if [ -z "$SHURIKEN_CURRENT_DATE_TEXT" ]; then
        if random_seed_is_set; then
            SHURIKEN_CURRENT_DATE_TEXT='Thu Jan  1 00:00:00 UTC 1970'
        else
            SHURIKEN_CURRENT_DATE_TEXT=$(command date)
        fi
    fi

    output_ref="$SHURIKEN_CURRENT_DATE_TEXT"
}

declare -ra TEMPLATE_RENDER_FIELD_SPECS=(
    'render_animation_class_html|context_html|animation_class|animation_class|preview details view'
    'render_backhref_css|context_css|backhref|backhref|header splash'
    'render_backhref_html|context_html|backhref|backhref|footer header preview splash details view stats camera'
    'render_background_image_css|context_css|background_image|background_image|header splash'
    'render_blurs_dir_css|context_css|blurs_dir|blurs_dir|header splash'
    'render_camera_name_html|context_html|camera_name|camera_name|camera'
    'render_cameraview_body_html|context_raw|cameraview_body|cameraview_body|cameraview'
    'render_camera_thumbs_html|context_raw|camera_thumbs|camera_thumbs|camera'
    'render_current_date_text|current_date_html|||'
    'render_enter_page_html|context_html|enter_page|enter_page|splash'
    'render_exif_details_html|context_raw|exif_details|exif_details|details'
    'render_exif_tooltip_html|context_html|exif_tooltip|exif_tooltip|details view'
    'render_height_html|config_html|HEIGHT||'
    'render_html_dir_html|context_html|html_dir|html_dir|*'
    'render_maxpreviews_html|config_html|MAXPREVIEWS||'
    'render_next_html|context_html|next|next|next'
    'render_original_basepath_is_set|original_basepath_is_set|||'
    'render_original_basepath_html|config_html|ORIGINAL_BASEPATH||'
    'render_page_num_html|context_html|page_num|page_num|preview details view'
    'render_photo_html|context_html|photo|photo|preview splash details view'
    'render_photos_dir_html|context_html|photos_dir|photos_dir|splash details view'
    'render_prev_html|context_html|prev|prev|prev'
    'render_preview_num_html|context_html|preview_num|preview_num|preview details view'
    'render_redirect_page_html|context_html|redirect_page|redirect_page|redirect'
    'render_show_header_bar|context_raw|show_header_bar|show_header_bar|header'
    'render_stats_body_html|context_raw|stats_body|stats_body|stats'
    'render_stats_page_html|config_html|STATS_PAGE||'
    'render_tarball_include|tarball_include|||'
    'render_tarball_name_html|context_html|tarball_name|tarball_name|footer'
    'render_thumbheight_html|config_html|THUMBHEIGHT||'
    'render_thumbs_dir_html|context_html|thumbs_dir|thumbs_dir|preview'
    'render_title_html|config_html|TITLE||'
    'render_view_next_html|preview_num_next_html|preview_num||'
    'render_view_prev_html|preview_num_prev_html|preview_num||'
)

current_timestamp_slug() {
    if random_seed_is_set; then
        printf '1970-01-01-000000\n'
    else
        command date +'%Y-%m-%d-%H%M%S'
    fi
}

current_timestamp_iso() {
    if random_seed_is_set; then
        printf '1970-01-01T00:00:00Z\n'
    else
        command date -u +'%Y-%m-%dT%H:%M:%SZ'
    fi
}

template_context_value() {
    # shellcheck disable=SC2178
    local -n context_ref="$1"; shift
    local -r name="$1"; shift

    printf '%s\n' "${context_ref[$name]:-}"
}

template_context_value_to() {
    local -n output_ref="$1"; shift
    # shellcheck disable=SC2178
    local -n context_ref="$1"; shift
    local -r name="$1"; shift

    # shellcheck disable=SC2034
    output_ref="${context_ref[$name]:-}"
}

require_template_context_vars() {
    local -r template_name="$1"; shift
    # shellcheck disable=SC2178
    local -n context_ref="$1"; shift
    local name

    for name in "$@"; do
        if [ -z "${context_ref[$name]+x}" ]; then
            config_error "template $template_name requires render variable $name"
            return 1
        fi
    done
}

template_render_field_is_required_for() {
    local -r template_name="$1"; shift
    local -r required_template_names="$1"; shift

    case "$required_template_names" in
        '*')
            return 0
            ;;
        '')
            return 1
            ;;
        *)
            [[ " $required_template_names " == *" $template_name "* ]]
            ;;
    esac
}

template_required_context_vars_to() {
    # shellcheck disable=SC2178
    local -n required_vars_ref="$1"; shift
    local -r template_name="$1"; shift
    local -A required_var_seen=()
    local field_spec
    local _kind
    local _render_var
    local required_context_var
    local required_template_names
    local _source_name

    required_vars_ref=()

    for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
        IFS='|' read -r _render_var _kind _source_name \
            required_context_var required_template_names <<< "$field_spec"

        if [ -n "$required_context_var" ] \
            && template_render_field_is_required_for \
                "$template_name" "$required_template_names" \
            && [ -z "${required_var_seen[$required_context_var]+x}" ]; then
            required_vars_ref+=("$required_context_var")
            required_var_seen["$required_context_var"]=yes
        fi
    done
}

template_required_context_vars() {
    local -r template_name="$1"; shift
    local -a required_vars=()

    template_required_context_vars_to required_vars "$template_name"
    if (( ${#required_vars[@]} > 0 )); then
        printf '%s\n' "${required_vars[@]}"
    fi
}

validate_template_context() {
    local -r template_name="$1"; shift
    local -r context_name="$1"; shift
    local -i status=0
    local -a required_vars=()

    template_required_context_vars_to required_vars "$template_name"
    require_template_context_vars "$template_name" "$context_name" \
        "${required_vars[@]}"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}

source_template_file() {
    local -r template_path="$1"; shift
    local -r output_path="$1"; shift
    local -r render_vars_name="$1"; shift
    local context_file
    local sig
    local -i status=0

    context_file=$(mktemp)
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    # Single cleanup point for the BASH_ENV context tempfile. The traps MUST be
    # registered here in source_template_file's own body (not in a helper): a
    # RETURN trap is not function-scoped unless functrace is enabled, so a trap
    # set inside a helper would fire when that helper returns and delete the file
    # before the render even runs.
    #
    # The RETURN trap covers normal and error returns (errexit unwinds through
    # it) and clears ALL of these traps, including itself, so a lingering RETURN
    # trap cannot fire again on an enclosing function's return against the now
    # out-of-scope context_file local (which would trip set -u).
    #
    # A RETURN trap alone does NOT fire when a signal terminates the shell with
    # its default disposition. source_template_file also runs in backgrounded
    # render subshells (see queue_album_view_render_job) that get SIGTERM'd by
    # terminate_active_generation on interrupt, so we additionally trap the
    # terminating signals: each handler removes the file, clears the traps and
    # re-raises the original signal so the process still exits with that signal's
    # default disposition.
    #
    # SIGKILL cannot be trapped, so a KILL escalation may still leak a file that
    # the OS tmp reaper later clears; that is the only unavoidable residual case.
    trap 'rm -f "$context_file"; trap - INT TERM HUP RETURN' RETURN
    for sig in INT TERM HUP; do
        # $sig is intentionally expanded now (so each handler re-raises its own
        # signal); $context_file and $BASHPID are escaped to expand when the trap
        # runs. We re-raise to $BASHPID, not $$: source_template_file commonly
        # runs in backgrounded render subshells where $$ is the main shuriken
        # PID, so kill -s $sig $$ would terminate the main shell (mid-cleanup,
        # after its own staging traps were cleared) instead of this subshell.
        # $BASHPID is the current (sub)shell's real PID and equals $$ in the
        # foreground case, so it is correct everywhere.
        # shellcheck disable=SC2064
        trap "rm -f \"\$context_file\"; trap - INT TERM HUP RETURN; \
            kill -s $sig \"\$BASHPID\"" "$sig"
    done

    # Build the BASH_ENV context file directly in the current shell. The .tmpl
    # is run via "env -i bash" with BASH_ENV pointing at this file, so the file
    # only needs the render_* variable assignments the template references plus a
    # trailing "unset BASH_ENV" (so the template's own children do not re-source
    # it). We deliberately avoid the old "declare -f | bash" approach: that
    # dumped all ~5000 lines of shuriken functions into a fresh bash subprocess
    # per page just to run serialize_template_render_context. Calling that
    # serializer in-process and redirecting its %q-quoted output is identical in
    # result but skips the function dump and subprocess spawn on every page.
    # Status-test the serializer with "if" so a failure returns normally through
    # the RETURN trap above (which removes the partial context file) instead of
    # letting errexit tear the shell down without running the trap. The serializer
    # returns its own non-zero status explicitly, so this works even when
    # source_template_file itself runs inside a status-tested ("if template ...")
    # call chain where bash would otherwise suppress an inner errexit abort.
    if serialize_template_render_context "$render_vars_name" \
        > "$context_file"; then
        status=0
    else
        status=$?
    fi
    if (( status != 0 )); then
        return "$status"
    fi

    # Appended only after the render vars serialized cleanly so the template's
    # own child shells do not re-source this BASH_ENV context file.
    printf 'unset BASH_ENV\n' >> "$context_file"

    if env -i PATH="$PATH" BASH_ENV="$context_file" \
        bash -euo pipefail -- "$template_path" >> "$output_path"; then
        status=0
    else
        status=$?
    fi
    if (( status != 0 )); then
        return "$status"
    fi
}

parse_template_context() {
    local -r template_name="$1"; shift
    local -n context_ref="$1"; shift
    local context_key
    local context_value

    while (( $# > 0 )); do
        if (( $# < 2 )); then
            config_error "template $template_name render context is incomplete"
            return 1
        fi

        context_key="$1"
        context_value="$2"
        shift 2

        if [[ ! "$context_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            config_error \
                "template $template_name render variable $context_key is invalid"
            return 1
        fi

        # shellcheck disable=SC2034
        context_ref["$context_key"]="$context_value"
    done
}

serialize_template_render_var() {
    local -r name="$1"; shift
    local -r value="$1"; shift

    printf '%s=%q\n' "$name" "$value"
}

# Emit "render_var=value" assignments (one per template field) on stdout, each
# %q-quoted via serialize_template_render_var so the values survive being
# re-sourced by "env -i bash". Runs in the current shell (called by
# source_template_file) reading the caller's render_vars associative array by
# name and the top-level TEMPLATE_RENDER_FIELD_SPECS constant.
#
# Returns the status of the failing write explicitly rather than relying on
# errexit: source_template_file (and its production callers) may run inside an
# "if"/status-tested context where bash suppresses a called function's own
# errexit, so an explicit non-zero return is the only reliable failure signal.
serialize_template_render_context() {
    local -r render_vars_name="$1"; shift
    # shellcheck disable=SC2178
    local -n render_vars_ref="$render_vars_name"
    local field_spec
    local _kind
    local render_var
    local _required_context_var
    local _required_templates
    local _source_name
    local -i status=0

    for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
        IFS='|' read -r render_var _kind _source_name \
            _required_context_var _required_templates <<< "$field_spec"
        serialize_template_render_var \
            "$render_var" "${render_vars_ref[$render_var]}"
        status=$?
        if (( status != 0 )); then
            return "$status"
        fi
    done
}

prepare_template_render_vars() {
    local -r render_vars_name="$1"; shift
    local -r context_name="$1"; shift
    # shellcheck disable=SC2178
    local -n render_vars_ref="$render_vars_name"
    local context_value
    local field_spec
    local kind
    local render_value
    local render_var
    local _required_context_var
    local _required_templates
    local source_name

    render_vars_ref=()

    for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
        IFS='|' read -r render_var kind source_name \
            _required_context_var _required_templates <<< "$field_spec"

        case "$kind" in
            context_css)
                template_context_value_to \
                    context_value "$context_name" "$source_name"
                css_string_escape_to render_value "$context_value"
                ;;
            context_html)
                template_context_value_to \
                    context_value "$context_name" "$source_name"
                html_escape_to render_value "$context_value"
                ;;
            context_raw)
                template_context_value_to \
                    render_value "$context_name" "$source_name"
                ;;
            current_date_html)
                current_date_text_to context_value
                html_escape_to render_value "$context_value"
                ;;
            config_html)
                case "$source_name" in
                    HEIGHT)
                        context_value="$HEIGHT"
                        ;;
                    MAXPREVIEWS)
                        # Refresh-only configs do not require generation
                        # sizing fields; render absent values as empty.
                        context_value="${MAXPREVIEWS:-}"
                        ;;
                    ORIGINAL_BASEPATH)
                        context_value="$ORIGINAL_BASEPATH"
                        ;;
                    STATS_PAGE)
                        # Always defaulted by apply_config_defaults; degrade to
                        # "no" (link hidden) if somehow unset so the header bar
                        # never references a stats page that was not generated.
                        context_value="${STATS_PAGE:-no}"
                        ;;
                    THUMBHEIGHT)
                        # Refresh-only configs do not require generation
                        # sizing fields; render absent values as empty.
                        context_value="${THUMBHEIGHT:-}"
                        ;;
                    TITLE)
                        context_value="$TITLE"
                        ;;
                    *)
                        config_error \
                            "unknown template render config $source_name"
                        return 1
                        ;;
                esac
                html_escape_to render_value "$context_value"
                ;;
            original_basepath_is_set)
                if [ -n "$ORIGINAL_BASEPATH" ]; then
                    render_value='yes'
                else
                    render_value='no'
                fi
                ;;
            preview_num_next_html)
                template_context_value_to \
                    context_value "$context_name" "$source_name"
                if [ -n "$context_value" ]; then
                    html_escape_to render_value "$(( context_value + 1 ))"
                else
                    render_value=''
                fi
                ;;
            preview_num_prev_html)
                template_context_value_to \
                    context_value "$context_name" "$source_name"
                if [ -n "$context_value" ]; then
                    html_escape_to render_value "$(( context_value - 1 ))"
                else
                    render_value=''
                fi
                ;;
            tarball_include)
                render_value="$TARBALL_INCLUDE"
                ;;
            *)
                config_error "unknown template render field kind $kind"
                return 1
                ;;
        esac

        render_vars_ref["$render_var"]="$render_value"
    done
}

validate_template_render_request() {
    local -r template_name="$1"; shift
    local -r context_name="$1"; shift
    local -r template_path="$TEMPLATE_DIR/$template_name.tmpl"
    local -i status=0

    if [ ! -r "$template_path" ]; then
        config_error "template file $template_path must be readable"
        return 1
    fi

    validate_template_context "$template_name" "$context_name"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}

render_template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    local -r context_name="$1"; shift
    local -r template_path="$TEMPLATE_DIR/$template_name.tmpl"
    local dist_html
    local html_dir
    local -i status=0
    # Passed by name to prepare_template_render_vars and source_template_file.
    # shellcheck disable=SC2034
    local -A render_vars=()

    html_dir=$(template_context_value "$context_name" html_dir)
    dist_html="$DIST_DIR/$html_dir"

    log_info \
        "Rendering $template_name template into $(_display_path "$dist_html")/$html"

    mkdir -p "$dist_html"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    prepare_template_render_vars render_vars "$context_name"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    source_template_file "$template_path" "$dist_html/$html" render_vars
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}

template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    local -i status=0
    # shellcheck disable=SC2034
    local -A render_context=()

    parse_template_context "$template_name" render_context "$@"
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    validate_template_render_request "$template_name" render_context
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi

    render_template "$template_name" "$html" render_context
    status=$?
    if (( status != 0 )); then
        return "$status"
    fi
}
