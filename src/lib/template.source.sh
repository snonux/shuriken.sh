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
    'render_backhref_html|context_html|backhref|backhref|footer header preview splash details view'
    'render_background_image_css|context_css|background_image|background_image|header splash'
    'render_blurs_dir_css|context_css|blurs_dir|blurs_dir|header splash'
    'render_current_date_text|current_date_html|||'
    'render_enter_page_html|context_html|enter_page|enter_page|splash'
    'render_exif_details_html|context_raw|exif_details|exif_details|details'
    'render_exif_tooltip_html|context_html|exif_tooltip|exif_tooltip|details'
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
    local -n context_ref="$1"; shift
    local -r name="$1"; shift

    printf '%s\n' "${context_ref[$name]:-}"
}

template_context_value_to() {
    local -n output_ref="$1"; shift
    local -n context_ref="$1"; shift
    local -r name="$1"; shift

    # shellcheck disable=SC2034
    output_ref="${context_ref[$name]:-}"
}

require_template_context_vars() {
    local -r template_name="$1"; shift
    local -n context_ref="$1"; shift
    local name
    local -i missing=0

    for name in "$@"; do
        if [ -z "${context_ref[$name]+x}" ]; then
            config_error "template $template_name requires render variable $name"
            missing=1
        fi
    done

    return "$missing"
}

template_render_field_is_required_for() {
    local -r template_name="$1"; shift
    local -r required_templates="$1"; shift

    case "$required_templates" in
        '*')
            return 0
            ;;
        '')
            return 1
            ;;
        *)
            [[ " $required_templates " == *" $template_name "* ]]
            ;;
    esac
}

template_required_context_vars_to() {
    local -n required_vars_ref="$1"; shift
    local -r template_name="$1"; shift
    local -A required_var_seen=()
    local field_spec
    local _kind
    local _render_var
    local required_context_var
    local required_templates
    local _source_name

    required_vars_ref=()

    for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
        IFS='|' read -r _render_var _kind _source_name \
            required_context_var required_templates <<< "$field_spec"

        if [ -n "$required_context_var" ] \
            && template_render_field_is_required_for \
                "$template_name" "$required_templates" \
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
    local -a required_vars=()

    template_required_context_vars_to required_vars "$template_name"
    require_template_context_vars "$template_name" "$context_name" \
        "${required_vars[@]}"
}

source_template_file() {
    local -r template_path="$1"; shift
    local -r output_path="$1"; shift
    local -r render_vars_name="$1"; shift
    local context_file
    local -i status=0

    context_file=$(mktemp)
    {
        serialize_template_render_context "$render_vars_name"
        printf 'unset BASH_ENV\n'
    } > "$context_file"

    if env -i PATH="$PATH" BASH_ENV="$context_file" \
        bash -euo pipefail -- "$template_path" >> "$output_path"; then
        rm -f "$context_file"
    else
        status=$?
        rm -f "$context_file"
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

serialize_template_render_context() {
    local -r render_vars_name="$1"; shift
    local -n render_vars_ref="$render_vars_name"
    local field_spec
    local _kind
    local render_var
    local _required_context_var
    local _required_templates
    local _source_name

    for field_spec in "${TEMPLATE_RENDER_FIELD_SPECS[@]}"; do
        IFS='|' read -r render_var _kind _source_name \
            _required_context_var _required_templates <<< "$field_spec"
        serialize_template_render_var \
            "$render_var" "${render_vars_ref[$render_var]}"
    done
}

prepare_template_render_vars() {
    local -r render_vars_name="$1"; shift
    local -r context_name="$1"; shift
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
                        context_value="${HEIGHT:-}"
                        ;;
                    MAXPREVIEWS)
                        context_value="${MAXPREVIEWS:-}"
                        ;;
                    ORIGINAL_BASEPATH)
                        context_value="${ORIGINAL_BASEPATH:-}"
                        ;;
                    THUMBHEIGHT)
                        context_value="${THUMBHEIGHT:-}"
                        ;;
                    TITLE)
                        context_value="${TITLE:-}"
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
                if [ -n "${ORIGINAL_BASEPATH:-}" ]; then
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
                render_value="${TARBALL_INCLUDE:-no}"
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

    if [ ! -r "$template_path" ]; then
        config_error "template file $template_path must be readable"
        return 1
    fi

    validate_template_context "$template_name" "$context_name"
}

render_template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    local -r context_name="$1"; shift
    local -r template_path="$TEMPLATE_DIR/$template_name.tmpl"
    local dist_html
    local html_dir
    # Passed by name to prepare_template_render_vars and source_template_file.
    # shellcheck disable=SC2034
    local -A render_vars=()

    html_dir=$(template_context_value "$context_name" html_dir)
    dist_html="$DIST_DIR/$html_dir"

    log_info \
        "Rendering $template_name template into $(_display_path "$dist_html")/$html"

    mkdir -p "$dist_html"
    prepare_template_render_vars render_vars "$context_name"
    source_template_file "$template_path" "$dist_html/$html" render_vars
}

template() {
    local -r template_name="$1"; shift
    local -r html="$1"; shift
    # shellcheck disable=SC2034
    local -A render_context=()

    parse_template_context "$template_name" render_context "$@"
    validate_template_render_request "$template_name" render_context
    render_template "$template_name" "$html" render_context
}
