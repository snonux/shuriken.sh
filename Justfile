set shell := ["bash", "-euo", "pipefail", "-c"]

NAME := "photoalbum"
VERSION := "0.7.0"
DESTDIR := env_var_or_default("DESTDIR", "")
PREFIX := env_var_or_default("PREFIX", "/usr")
BINDIR := env_var_or_default("BINDIR", PREFIX + "/bin")
DATADIR := env_var_or_default("DATADIR", PREFIX + "/share")
SYSCONFDIR := env_var_or_default("SYSCONFDIR", "/etc/default")
LIB_SOURCES := "src/lib/bootstrap.source.sh src/lib/system.source.sh src/lib/template.source.sh src/lib/image.source.sh src/lib/album.source.sh src/lib/config.source.sh src/lib/action.source.sh"

default: build

all: build

version:
    printf '%s\n' "{{VERSION}}"

[script]
build:
    mkdir -p ./bin
    generated=$(mktemp "./bin/.{{NAME}}.XXXXXX")
    trap 'rm -f "$generated"' EXIT

    render_lib_sources() {
        local lib_source
        local line

        for lib_source in {{LIB_SOURCES}}; do
            printf '\n# Inlined from %s\n' "$lib_source"
            while IFS= read -r line; do
                line=${line//PHOTOALBUMVERSION/{{VERSION}}}
                printf '%s\n' "$line"
            done < "$lib_source"
        done
    }

    render_photoalbum() {
        local in_lib_sources=no
        local line

        while IFS= read -r line; do
            case "$line" in
                '# PHOTOALBUM_LIB_SOURCES_BEGIN')
                    printf '%s\n' "$line"
                    render_lib_sources
                    in_lib_sources=yes
                    ;;
                '# PHOTOALBUM_LIB_SOURCES_END')
                    in_lib_sources=no
                    printf '\n%s\n' "$line"
                    ;;
                *)
                    if [ "$in_lib_sources" = no ]; then
                        line=${line//PHOTOALBUMVERSION/{{VERSION}}}
                        printf '%s\n' "$line"
                    fi
                    ;;
            esac
        done < "src/{{NAME}}.sh"
    }

    render_photoalbum > "$generated"
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

    render_lib_sources() {
        local lib_source
        local line

        for lib_source in {{LIB_SOURCES}}; do
            printf '\n# Inlined from %s\n' "$lib_source"
            while IFS= read -r line; do
                line=${line//PHOTOALBUMVERSION/{{VERSION}}}
                printf '%s\n' "$line"
            done < "$lib_source"
        done
    }

    render_photoalbum() {
        local in_lib_sources=no
        local line

        while IFS= read -r line; do
            case "$line" in
                '# PHOTOALBUM_LIB_SOURCES_BEGIN')
                    printf '%s\n' "$line"
                    render_lib_sources
                    in_lib_sources=yes
                    ;;
                '# PHOTOALBUM_LIB_SOURCES_END')
                    in_lib_sources=no
                    printf '\n%s\n' "$line"
                    ;;
                *)
                    if [ "$in_lib_sources" = no ]; then
                        line=${line//PHOTOALBUMVERSION/{{VERSION}}}
                        printf '%s\n' "$line"
                    fi
                    ;;
            esac
        done < "src/{{NAME}}.sh"
    }

    render_photoalbum > "$generated"
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
    install -d "{{DESTDIR}}{{SYSCONFDIR}}"
    install -m 0644 \
        ./src/photoalbum.default.conf \
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
        ./src/photoalbum.sh \
        ./tests/cli.sh \
        ./tests/helpers.sh
