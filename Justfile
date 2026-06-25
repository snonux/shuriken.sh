set shell := ["bash", "-euo", "pipefail", "-c"]

NAME := "shuriken"
VERSION := "0.11.4"
DESTDIR := env_var_or_default("DESTDIR", "")
PREFIX := env_var_or_default("PREFIX", "/usr")
BINDIR := env_var_or_default("BINDIR", PREFIX + "/bin")
DATADIR := env_var_or_default("DATADIR", PREFIX + "/share")
SYSCONFDIR := env_var_or_default("SYSCONFDIR", "/etc/default")
LIB_SOURCES := "src/lib/logging.source.sh src/lib/compat.source.sh src/lib/bootstrap.source.sh src/lib/paths.source.sh src/lib/imagemagick.source.sh src/lib/process.source.sh src/lib/archive.source.sh src/lib/template.source.sh src/lib/job-pool.source.sh src/lib/image.source.sh src/lib/random.source.sh src/lib/photo-list.source.sh src/lib/metadata-label.source.sh src/lib/metadata-cache.source.sh src/lib/image-pipeline.source.sh src/lib/album-metadata.source.sh src/lib/generation-metadata.source.sh src/lib/dry-run.source.sh src/lib/album-tile-layout.source.sh src/lib/album-thumbnail-html.source.sh src/lib/album-photo-select.source.sh src/lib/album-render.source.sh src/lib/album.source.sh src/lib/stats-aggregate.source.sh src/lib/stats-render.source.sh src/lib/stats-filter-album.source.sh src/lib/config.source.sh src/lib/config.print.source.sh src/lib/config.sync.source.sh src/lib/config.staging.source.sh src/lib/config.validate.source.sh src/lib/config.cli.source.sh src/lib/action.source.sh"

default: build

all: build

version:
    printf '%s\n' "{{VERSION}}"

[script]
_render-shuriken:
    _render_lib_sources() {
        local lib_source
        local line

        for lib_source in {{LIB_SOURCES}}; do
            printf '\n# Inlined from %s\n' "$lib_source"
            while IFS= read -r line; do
                line=${line//SHURIKENVERSION/{{VERSION}}}
                printf '%s\n' "$line"
            done < "$lib_source"
        done
    }

    _render_shuriken() {
        local in_lib_sources=no
        local line

        while IFS= read -r line; do
            case "$line" in
                '# SHURIKEN_LIB_SOURCES_BEGIN')
                    printf '%s\n' "$line"
                    _render_lib_sources
                    in_lib_sources=yes
                    ;;
                '# SHURIKEN_LIB_SOURCES_END')
                    in_lib_sources=no
                    printf '\n%s\n' "$line"
                    ;;
                *)
                    if [ "$in_lib_sources" = no ]; then
                        line=${line//SHURIKENVERSION/{{VERSION}}}
                        printf '%s\n' "$line"
                    fi
                    ;;
            esac
        done < "src/{{NAME}}.sh"
    }

    _render_shuriken

[script]
build:
    mkdir -p ./bin
    generated=$(mktemp "./bin/.{{NAME}}.XXXXXX")
    trap 'rm -f "$generated"' EXIT

    {{quote(just_executable())}} \
        --quiet \
        --justfile {{quote(justfile())}} \
        --set NAME {{quote(NAME)}} \
        --set VERSION {{quote(VERSION)}} \
        --set LIB_SOURCES {{quote(LIB_SOURCES)}} \
        _render-shuriken > "$generated"
    chmod 0755 "$generated"
    if [ -f "./bin/{{NAME}}" ] && cmp -s "$generated" "./bin/{{NAME}}"; then
        chmod 0755 "./bin/{{NAME}}"
        rm -f "$generated"
    else
        mv "$generated" "./bin/{{NAME}}"
    fi

[script]
check-generated:
    generated=$(mktemp)
    trap 'rm -f "$generated"' EXIT

    {{quote(just_executable())}} \
        --quiet \
        --justfile {{quote(justfile())}} \
        --set NAME {{quote(NAME)}} \
        --set VERSION {{quote(VERSION)}} \
        --set LIB_SOURCES {{quote(LIB_SOURCES)}} \
        _render-shuriken > "$generated"
    chmod 0755 "$generated"
    if [ ! -f "./bin/{{NAME}}" ]; then
        printf '%s\n' \
            "ERROR: ./bin/{{NAME}} is missing; run 'just build'." >&2
        exit 1
    fi
    if [ ! -x "./bin/{{NAME}}" ]; then
        printf '%s\n' \
            "ERROR: ./bin/{{NAME}} is not executable; run 'just build'." >&2
        exit 1
    fi
    if ! cmp -s "$generated" "./bin/{{NAME}}"; then
        printf '%s\n' \
            "ERROR: ./bin/{{NAME}} is stale; run 'just build'." >&2
        diff -u "./bin/{{NAME}}" "$generated" || true
        exit 1
    fi

test: check-generated build
    bash ./tests/cli.sh

install: check-generated build
    install -d "{{DESTDIR}}{{BINDIR}}"
    install -m 0755 "./bin/{{NAME}}" "{{DESTDIR}}{{BINDIR}}/{{NAME}}"
    install -d "{{DESTDIR}}{{DATADIR}}/{{NAME}}"
    rm -rf "{{DESTDIR}}{{DATADIR}}/{{NAME}}/templates"
    cp -R ./share/templates "{{DESTDIR}}{{DATADIR}}/{{NAME}}/"
    rm -rf "{{DESTDIR}}{{DATADIR}}/{{NAME}}/assets"
    cp -R ./assets/site "{{DESTDIR}}{{DATADIR}}/{{NAME}}/assets"
    install -d "{{DESTDIR}}{{SYSCONFDIR}}"
    install -m 0644 \
        ./src/shuriken.default.conf \
        "{{DESTDIR}}{{SYSCONFDIR}}/{{NAME}}"

deinstall:
    rm -f "{{DESTDIR}}{{BINDIR}}/{{NAME}}"
    rm -rf "{{DESTDIR}}{{DATADIR}}/{{NAME}}"
    rm -f "{{DESTDIR}}{{SYSCONFDIR}}/{{NAME}}"

uninstall: deinstall

clean:
    find ./bin -maxdepth 1 -type f -name '.{{NAME}}.*' -delete \
        2>/dev/null || true

shellcheck:
    shellcheck \
        --external-sources \
        --check-sourced \
        ./src/shuriken.sh \
        ./tests/cli.sh \
        ./tests/helpers.sh
