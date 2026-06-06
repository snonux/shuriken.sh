# photoalbum

photoalbum is a minimal Bash script for Unix like operating systems (such as Linux) to generate static web photo albums.
The resulting static photo album is pure HTML+CSS (without any JavaScript!).

## Installation

Build and install the command, templates, and default config from a source
checkout with:

```
just build
sudo just install
```

`bin/photoalbum` is a committed generated artifact for compatibility with
existing checkouts and packaging. Its source of truth is `src/photoalbum.sh`
rendered through the `VERSION` value in `Justfile`. Run `just build` after
changing either file, and use `just check-generated` to verify that the tracked
script has not drifted. `just test` and `just install` run that drift check
before rebuilding so stale committed output is not hidden.

`just install` installs `photoalbum` to `/usr/bin`, templates to
`/usr/share/photoalbum/templates`, and the default config to
`/etc/default/photoalbum`. Override paths with `DESTDIR`, `PREFIX`, `BINDIR`,
`DATADIR`, or `SYSCONFDIR` when packaging or staging an install:

```
DESTDIR="$PWD/pkg" PREFIX=/usr just install
DESTDIR="$PWD/pkg" PREFIX=/usr just deinstall
```

`just uninstall` is an alias for `just deinstall`.

ImageMagick must also be installed. The script prefers the
modern `magick` command and falls back to `convert` when needed.

## Usage

```
photoalbum --init
photoalbum --generate [--config PATH] [OPTIONS]
photoalbum --refresh-splash [--config PATH] [OPTIONS]
photoalbum --sync [--config PATH] [OPTIONS]
photoalbum --dry-run [--config PATH] [OPTIONS]
photoalbum --print-config [--config PATH] [OPTIONS]
photoalbum --clean [--config PATH] [OPTIONS]
photoalbum --version
```

* `--init` creates `./photoalbum.conf` in the current working directory from the
  default config. It refuses to overwrite an existing file.
* `--generate` builds the static album.
* `--force` with `--generate` rebuilds from scratch instead of reusing cached
  scaled photos, thumbnails, blurs, or EXIF data from the existing output.
* `--refresh-splash` rewrites only the generated root splash page.
* `--sync` publishes the generated output directory to configured rsync
  destinations.
* `--dry-run` loads the config and overrides, validates the planned generation,
  and prints the effective paths, image count, tarball plan, and generated file
  plan without writing output or running ImageMagick or tar.
* `--print-config` loads the config and overrides, validates basic config values,
  and prints the effective configuration without writing output, running
  ImageMagick, running tar, cleaning, or initializing.
* `--clean` removes the configured output directory.
* `--version` prints the program version.
* `--config PATH` selects the config file for `--generate`,
  `--refresh-splash`, `--dry-run`, `--print-config`, or `--clean`.

When `--config PATH` is not provided, `--generate`, `--dry-run`,
`--print-config`, `--refresh-splash`, and `--clean` read `./photoalbum.conf`.
If the file is missing, run `photoalbum --init` first.

The config file is a Bash file with assignments such as `INCOMING_DIR`,
`DIST_DIR`, `TEMPLATE_DIR`, `TITLE`, `HEIGHT`, `THUMBHEIGHT`, `MAXPREVIEWS`,
`IMAGE_JOBS`, `IMAGEMAGICK_TIMEOUT`, `RANDOM_SEED`, `SHUFFLE`, `SPLASH_PAGE`,
`TARBALL_INCLUDE`, `TAR_TIMEOUT`, `SYNC_DELETE`, and `SYNC_DESTINATIONS`.

Before generating, `photoalbum` validates the loaded config and command-line
overrides. It checks required values, positive integer settings, `yes`/`no`
settings, readable input and template directories, a writable output location,
and ImageMagick availability. Generation stops before writing album output when
validation fails.

Only regular files in `INCOMING_DIR` with supported image extensions are
processed as album images. Supported extensions are `jpg`, `jpeg`, `png`, `webp`,
and `gif`, matched case-insensitively. Other files, such as `.txt` or `.md`
notes, are ignored with a warning so generation can continue.

`--dry-run` reports the same `INCOMING_DIR`, `DIST_DIR`, and `TEMPLATE_DIR`
values that generation would use after applying command-line overrides. Its
tarball filename uses `<timestamp>` as a placeholder so the output is stable.

`--print-config` writes stable shell-style assignments to stdout in this order:
`CONFIG_SOURCE`, `INCOMING_DIR`, `DIST_DIR`, `TEMPLATE_DIR`, `TITLE`, `HEIGHT`,
`THUMBHEIGHT`, `MAXPREVIEWS`, `IMAGE_JOBS`, `IMAGEMAGICK_TIMEOUT`,
`RANDOM_SEED`, `SHUFFLE`, `SPLASH_PAGE`, `TARBALL_INCLUDE`,
`TARBALL_SUFFIX`, `TAR_TIMEOUT`, `TAR_OPTS`, `SYNC_DELETE`,
`SYNC_DESTINATIONS`, and `ORIGINAL_BASEPATH`. Scalar values use Bash `%q`
quoting and `TAR_OPTS` and `SYNC_DESTINATIONS` are normalized to Bash array
assignments, so the output can be parsed by shell tooling. `--quiet` does not
suppress this output, and `--verbose` does not add human-readable diagnostics to
it.

Successful generation writes `photoalbum.json` into the output directory. This
metadata records the generator version and timestamp, config source, template
directory, supported source image and generated file counts, tarball status, and
effective settings useful for debugging a published album.

Normal generation preserves reusable generated artifacts from the previous
`DIST_DIR` while still rerendering HTML, random splash/background choices,
animation classes, timestamps, and shuffled preview order. Existing scaled
photos, thumbnails, blurs, and cached EXIF identify output are reused when the
source image is unchanged. Pass `--force` with `--generate` to skip that cache
copy and rebuild all generated image artifacts and EXIF data from scratch.

The following long options override config values:

| Option | Config value |
| --- | --- |
| `--incoming PATH` | `INCOMING_DIR` |
| `--dist PATH` | `DIST_DIR` |
| `--template PATH` | `TEMPLATE_DIR` |
| `--title TEXT` | `TITLE` |
| `--height VALUE` | `HEIGHT` |
| `--thumbheight VALUE` | `THUMBHEIGHT` |
| `--maxpreviews N` | `MAXPREVIEWS` |
| `--image-jobs N` | `IMAGE_JOBS` |
| `--random-seed VALUE` | `RANDOM_SEED` |
| `--shuffle` | `SHUFFLE=yes` |
| `--no-shuffle` | `SHUFFLE=no` |
| `--splash` | `SPLASH_PAGE=yes` |
| `--no-splash` | `SPLASH_PAGE=no` |
| `--tarball` | `TARBALL_INCLUDE=yes` |
| `--no-tarball` | `TARBALL_INCLUDE=no` |
| `--sync-delete` | `SYNC_DELETE=yes` |
| `--no-sync-delete` | `SYNC_DELETE=no` |

Pass `--sync-destination DEST` one or more times with `--sync` to override the
configured sync destinations for that run.

By default, the generated root `index.html` is a no-JavaScript splash page using
a randomly selected album photo. Set `SPLASH_PAGE=no` or pass `--no-splash` to
restore the top-level redirect to `page-1.html`.

To quickly pick a new random splash photo for an already generated album, run
`photoalbum --refresh-splash`. This rewrites only `DIST_DIR/index.html` using
the existing `photos` and `blurs` output, so it avoids reprocessing images and
rerendering album pages. It requires `SPLASH_PAGE=yes`; pass
`--random-seed VALUE` when you need a repeatable pick.

By default, splash and background photos, animation classes, generated
timestamps, and `--shuffle` preview order remain non-deterministic. Set
`RANDOM_SEED` in the config, or pass `--random-seed VALUE`, to make those
choices repeatable for stable tests or reproducible album builds. Use the same
seed and inputs to produce the same HTML.

To publish generated output, configure destinations and run `photoalbum --sync`:

```
SYNC_DESTINATIONS=(
    admin@fishfinger.buetow.org:/var/www/htdocs/example.org/
    admin@blowfish.buetow.org:/var/www/htdocs/example.org/
)
```

`--sync` runs `rsync -av --delete "$DIST_DIR/" "$destination"` for each
destination by default. The trailing slash on `DIST_DIR/` means the generated
contents are copied into the target directory. Set `SYNC_DELETE=no` or pass
`--no-sync-delete` to omit `--delete`.

`--dry-run`, `--print-config`, and `--refresh-splash` accept the same override
options as `--generate`. `--clean` accepts the same override options, but only
`--dist` changes what it removes.

Output is human-readable by default and reports routine generation progress.
Use `--quiet` to suppress routine progress while still writing errors to stderr.
Use `--verbose` for extra diagnostics, including the selected config file,
effective paths, skipped existing files, staging output directory, and tarball
decisions. If `--quiet` and `--verbose` are repeated or combined, the last output
flag wins.

ImageMagick photo processing runs in parallel. The default is `IMAGE_JOBS=3`.
Set `IMAGE_JOBS` in the config, or pass `--image-jobs N`, to tune the number of
concurrent ImageMagick jobs.

Each ImageMagick command is bounded by `IMAGEMAGICK_TIMEOUT=60` seconds, and
tarball creation is bounded by `TAR_TIMEOUT=120` seconds. Set either config
value to a positive integer to adjust the limit for large images or archives.

## Example usage

1. Run `photoalbum --init`.
2. Edit `photoalbum.conf`. Set `INCOMING_DIR` to the directory containing the
   pictures and adjust `DIST_DIR`, `TITLE`, or template settings as needed.
3. Run `photoalbum --dry-run` to inspect the planned generation.
4. Run `photoalbum --generate` to generate the album.
5. Run `photoalbum --sync` to publish `./dist`, or distribute it manually.
6. Run `photoalbum --clean` to remove the generated output.

## HTML templates

Templates live under `share/templates/default` in the source tree and under the
installed template directory after installation. The stock default resolves to
the installed template directory when it exists, and otherwise falls back to the
source tree's `share/templates/default` when running from a checkout. Copy and
edit templates, then point `TEMPLATE_DIR` or `--template PATH` at the customized
directory.
