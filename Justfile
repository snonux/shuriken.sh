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

build:
    mkdir -p ./bin
    sed "s/PHOTOALBUMVERSION/{{VERSION}}/" \
        "src/{{NAME}}.sh" > "./bin/{{NAME}}"
    chmod 0755 "./bin/{{NAME}}"

test: build
    bash ./tests/cli.sh

install: build
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
    rm -rf ./bin

shellcheck:
    # SC1090: ShellCheck can't follow non-constant source.
    # SC2001: See if you can use ${variable//search/replace} instead.
    # SC2010: Don't use ls | grep. Use a glob or a for loop.
    # SC2012: Use find instead of ls for unusual filenames.
    # SC2103: Use a subshell to avoid having to cd back.
    # SC2155: Declare and assign separately to avoid masking return values.
    # SC2164: Use 'cd ... || exit' or 'cd ... || return'.
    # SC2207: Prefer mapfile or read -a to split command output.
    shellcheck \
        --exclude SC1090 \
        --exclude SC2001 \
        --exclude SC2010 \
        --exclude SC2012 \
        --exclude SC2103 \
        --exclude SC2155 \
        --exclude SC2164 \
        --exclude SC2207 \
        ./src/photoalbum.sh \
        ./tests/cli.sh \
        ./tests/helpers.sh
