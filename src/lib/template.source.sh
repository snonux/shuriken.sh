_html_escape() {
    local text="$1"; shift

    text=${text//&/\&amp;}
    text=${text//</\&lt;}
    text=${text//>/\&gt;}
    text=${text//\"/\&quot;}
    text=${text//\'/\&#39;}

    printf '%s\n' "$text"
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
    local text="$1"; shift

    text=${text//\\/\\\\}
    text=${text//&/\\000026}
    text=${text//</\\00003c}
    text=${text//>/\\00003e}
    text=${text//\"/\\000022}
    text=${text//\'/\\000027}

    printf '%s\n' "$text"
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
    local -r final_dist="${PHOTOALBUM_FINAL_DIST_DIR:-}"

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

    if [ -z "$PHOTOALBUM_CURRENT_DATE_TEXT" ]; then
        if random_seed_is_set; then
            PHOTOALBUM_CURRENT_DATE_TEXT='Thu Jan  1 00:00:00 UTC 1970'
        else
            PHOTOALBUM_CURRENT_DATE_TEXT=$(command date)
        fi
    fi

    output_ref="$PHOTOALBUM_CURRENT_DATE_TEXT"
}

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

validate_template_context() {
    local -r template_name="$1"; shift
    local -r context_name="$1"; shift
    local -n context_ref="$context_name"
    local -a required_vars=(html_dir)

    case "$template_name" in
        footer)
            required_vars+=(backhref tarball_name)
            ;;
        header)
            required_vars+=(
                backhref
                background_image
                blurs_dir
                show_header_bar
            )
            ;;
        next)
            required_vars+=(next prev)
            ;;
        prev)
            required_vars+=(prev)
            ;;
        preview)
            required_vars+=(
                animation_class
                backhref
                page_num
                photo
                preview_num
                thumbs_dir
            )
            ;;
        redirect)
            required_vars+=(redirect_page)
            ;;
        splash)
            required_vars+=(
                backhref
                background_image
                blurs_dir
                enter_page
                photo
                photos_dir
            )
            ;;
        details)
            required_vars+=(
                animation_class
                backhref
                exif_details
                page_num
                photo
                photos_dir
                preview_num
            )
            ;;
        view)
            required_vars+=(
                animation_class
                backhref
                page_num
                photo
                photos_dir
                preview_num
            )
            ;;
    esac

    require_template_context_vars "$template_name" "$context_name" \
        "${required_vars[@]}"
}

source_template_file() {
    local -r template_path="$1"; shift
    local -r output_path="$1"; shift
    local context_file
    local -i status=0

    context_file=$(mktemp)
    {
        serialize_template_render_context
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
    serialize_template_render_var \
        render_animation_class_html "$render_animation_class_html"
    serialize_template_render_var render_backhref_css "$render_backhref_css"
    serialize_template_render_var render_backhref_html "$render_backhref_html"
    serialize_template_render_var \
        render_background_image_css "$render_background_image_css"
    serialize_template_render_var render_blurs_dir_css "$render_blurs_dir_css"
    serialize_template_render_var \
        render_current_date_text "$render_current_date_text"
    serialize_template_render_var render_enter_page_html "$render_enter_page_html"
    serialize_template_render_var \
        render_exif_details_html "$render_exif_details_html"
    serialize_template_render_var render_height_html "$render_height_html"
    serialize_template_render_var render_html_dir_html "$render_html_dir_html"
    serialize_template_render_var \
        render_maxpreviews_html "$render_maxpreviews_html"
    serialize_template_render_var render_next_html "$render_next_html"
    serialize_template_render_var \
        render_original_basepath_is_set "$render_original_basepath_is_set"
    serialize_template_render_var \
        render_original_basepath_html "$render_original_basepath_html"
    serialize_template_render_var render_page_num_html "$render_page_num_html"
    serialize_template_render_var render_photo_html "$render_photo_html"
    serialize_template_render_var render_photos_dir_html "$render_photos_dir_html"
    serialize_template_render_var render_prev_html "$render_prev_html"
    serialize_template_render_var \
        render_preview_num_html "$render_preview_num_html"
    serialize_template_render_var \
        render_redirect_page_html "$render_redirect_page_html"
    serialize_template_render_var render_show_header_bar "$render_show_header_bar"
    serialize_template_render_var render_tarball_include "$render_tarball_include"
    serialize_template_render_var \
        render_tarball_name_html "$render_tarball_name_html"
    serialize_template_render_var render_thumbheight_html "$render_thumbheight_html"
    serialize_template_render_var render_thumbs_dir_html "$render_thumbs_dir_html"
    serialize_template_render_var render_title_html "$render_title_html"
    serialize_template_render_var render_view_next_html "$render_view_next_html"
    serialize_template_render_var render_view_prev_html "$render_view_prev_html"
}

prepare_template_render_vars() {
    local -r context_name="$1"; shift
    local context_value

    template_context_value_to context_value "$context_name" animation_class
    html_escape_to render_animation_class_html "$context_value"
    template_context_value_to context_value "$context_name" backhref
    css_string_escape_to render_backhref_css "$context_value"
    html_escape_to render_backhref_html "$context_value"
    template_context_value_to context_value "$context_name" background_image
    css_string_escape_to render_background_image_css "$context_value"
    template_context_value_to context_value "$context_name" blurs_dir
    css_string_escape_to render_blurs_dir_css "$context_value"
    current_date_text_to context_value
    html_escape_to render_current_date_text "$context_value"
    template_context_value_to context_value "$context_name" enter_page
    html_escape_to render_enter_page_html "$context_value"
    template_context_value_to render_exif_details_html \
        "$context_name" exif_details
    html_escape_to render_height_html "${HEIGHT:-}"
    html_escape_to render_html_dir_html "$render_html_dir"
    html_escape_to render_maxpreviews_html "${MAXPREVIEWS:-}"
    template_context_value_to context_value "$context_name" next
    html_escape_to render_next_html "$context_value"
    if [ -n "${ORIGINAL_BASEPATH:-}" ]; then
        render_original_basepath_is_set='yes'
    else
        render_original_basepath_is_set='no'
    fi
    html_escape_to render_original_basepath_html "${ORIGINAL_BASEPATH:-}"
    template_context_value_to context_value "$context_name" page_num
    html_escape_to render_page_num_html "$context_value"
    template_context_value_to context_value "$context_name" photo
    html_escape_to render_photo_html "$context_value"
    template_context_value_to context_value "$context_name" photos_dir
    html_escape_to render_photos_dir_html "$context_value"
    template_context_value_to context_value "$context_name" prev
    html_escape_to render_prev_html "$context_value"
    template_context_value_to render_preview_num "$context_name" preview_num
    html_escape_to render_preview_num_html "$render_preview_num"
    template_context_value_to context_value "$context_name" redirect_page
    html_escape_to render_redirect_page_html "$context_value"
    template_context_value_to render_show_header_bar \
        "$context_name" show_header_bar
    render_tarball_include="${TARBALL_INCLUDE:-no}"
    template_context_value_to context_value "$context_name" tarball_name
    html_escape_to render_tarball_name_html "$context_value"
    html_escape_to render_thumbheight_html "${THUMBHEIGHT:-}"
    template_context_value_to context_value "$context_name" thumbs_dir
    html_escape_to render_thumbs_dir_html "$context_value"
    html_escape_to render_title_html "${TITLE:-}"

    if [ -n "$render_preview_num" ]; then
        html_escape_to render_view_next_html "$(( render_preview_num + 1 ))"
        html_escape_to render_view_prev_html "$(( render_preview_num - 1 ))"
    else
        render_view_next_html=''
        render_view_prev_html=''
    fi
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
    local render_animation_class_html
    local render_backhref_css
    local render_backhref_html
    local render_background_image_css
    local render_blurs_dir_css
    local render_current_date_text
    local render_enter_page_html
    local render_exif_details_html
    local render_height_html
    local render_html_dir
    local render_html_dir_html
    local render_maxpreviews_html
    local render_next_html
    local render_original_basepath_is_set
    local render_original_basepath_html
    local render_page_num_html
    local render_photo_html
    local render_photos_dir_html
    local render_prev_html
    local render_preview_num
    local render_preview_num_html
    local render_redirect_page_html
    local render_show_header_bar
    local render_tarball_include
    local render_tarball_name_html
    local render_thumbheight_html
    local render_thumbs_dir_html
    local render_title_html
    local render_view_next_html
    local render_view_prev_html

    render_html_dir=$(template_context_value "$context_name" html_dir)
    dist_html="$DIST_DIR/$render_html_dir"

    log_info "Rendering $template_name template into $(_display_path "$dist_html")/$html"

    mkdir -p "$dist_html"
    prepare_template_render_vars "$context_name"
    source_template_file "$template_path" "$dist_html/$html"
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
