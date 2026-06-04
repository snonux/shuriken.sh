set shell := ["bash", "-euo", "pipefail", "-c"]

NAME := "photoalbum"
VERSION := "0.6.0"
DESTDIR := env_var_or_default("DESTDIR", "")
PREFIX := env_var_or_default("PREFIX", "/usr")
BINDIR := env_var_or_default("BINDIR", PREFIX + "/bin")
DATADIR := env_var_or_default("DATADIR", PREFIX + "/share")
SYSCONFDIR := env_var_or_default("SYSCONFDIR", "/etc/default")

default: build

all: build

version:
    printf '%s\n' "{{VERSION}}"

[script]
build:
    mkdir -p ./bin
    generated=$(mktemp "./bin/.{{NAME}}.XXXXXX")
    trap 'rm -f "$generated"' EXIT
    sed "s/PHOTOALBUMVERSION/{{VERSION}}/" \
        "src/{{NAME}}.sh" > "$generated"
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
    sed "s/PHOTOALBUMVERSION/{{VERSION}}/" \
        "src/{{NAME}}.sh" > "$generated"
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
        ./src/photoalbum.sh \
        ./tests/cli.sh \
        ./tests/helpers.sh
