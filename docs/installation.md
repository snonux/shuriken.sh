# Installation

## Requirements

* **Bash 5.1 or newer.** shuriken uses features that require it and exits with
  an error on older Bash.
* **ImageMagick.** The script prefers the modern `magick` command and falls back
  to `convert` / `identify` when only the legacy tools are present.
* **rsync** (only needed for `shuriken --sync`).

## Build and install from a source checkout

```sh
just build
sudo just install
```

`just install` installs:

* `shuriken` to `/usr/bin`,
* templates to `/usr/share/shuriken/templates/default` and static assets to
  `/usr/share/shuriken/assets`,
* the default config to `/etc/default/shuriken`.

## Packaging / staging overrides

Override install paths with `DESTDIR`, `PREFIX`, `BINDIR`, `DATADIR`, or
`SYSCONFDIR` when packaging or staging an install:

```sh
DESTDIR="$PWD/pkg" PREFIX=/usr just install
DESTDIR="$PWD/pkg" PREFIX=/usr just deinstall
```

`just uninstall` is an alias for `just deinstall`.

Defaults: `PREFIX=/usr`, `BINDIR=$PREFIX/bin`, `DATADIR=$PREFIX/share`,
`SYSCONFDIR=/etc/default`.

## The generated `bin/shuriken` artifact

`bin/shuriken` is a committed generated artifact kept in sync with
`src/shuriken.sh` for compatibility with existing checkouts and packaging. Its
source of truth is `src/shuriken.sh` rendered through the `VERSION` and
`LIB_SOURCES` values in `Justfile`.

* Run `just build` after changing `src/shuriken.sh` or any `src/lib/*.source.sh`
  file, and keep `bin/shuriken` synchronized.
* Run `just check-generated` to verify that the tracked script has not drifted.
  `just test` and `just install` run that drift check before rebuilding, so a
  stale committed output is never silently hidden.

## Running from a checkout (no install)

You can run `./bin/shuriken` directly from a source checkout. The stock default
template directory resolves to the installed location when it exists, and
otherwise falls back to the source tree's `share/templates/default`. Likewise
the bundled favicon falls back to `assets/site/favicon.ico`.