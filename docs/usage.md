# CLI reference

```
shuriken --init
shuriken --generate [--config PATH] [OPTIONS]
shuriken --refresh-splash [--config PATH] [OPTIONS]
shuriken --sync [--config PATH] [OPTIONS]
shuriken --dry-run [--config PATH] [OPTIONS]
shuriken --print-config [--config PATH] [OPTIONS]
shuriken --clean [--config PATH] [OPTIONS]
shuriken --version
```

## Actions

* `--init` creates `./shuriken.conf` in the current working directory from the
  default config. It refuses to overwrite an existing file. `--init` is a
  non-config action: it rejects `--config`, any config override, and `--force`.
* `--generate` builds the static album.
* `--force` (only valid with `--generate`) rebuilds from scratch instead of
  reusing cached scaled photos, thumbnails, blurs, or EXIF data from the existing
  output. Using `--force` with any other action is a usage error.
* `--refresh-splash` rewrites only the generated root splash page. Requires
  `SPLASH_PAGE=yes`.
* `--sync` publishes the generated output directory to configured rsync
  destinations. See [publishing.md](publishing.md).
* `--dry-run` loads the config and overrides, validates the planned generation,
  and prints the effective paths, image count, tarball plan, and generated file
  plan without writing output or running ImageMagick or tar. Its tarball filename
  uses `<timestamp>` as a placeholder so the output is stable.
* `--print-config` loads the config and overrides, validates basic config values,
  and prints the effective configuration without writing output, running
  ImageMagick, running tar, cleaning, or initializing. See
  [configuration.md](configuration.md) for the output format.
* `--clean` removes the configured output directory and any leftover
  `.shuriken.*.staging`/`.backup` directories the generation pipeline created as
  siblings of `DIST_DIR` (e.g. from an interrupted run). It accepts the same
  override options as the other actions, but only `--dist` changes what it
  removes. `--clean` leaves the EXIF `cache/` in place; delete `cache/` by hand
  to force a full EXIF rebuild on the next run.
* `--version` prints the program version.

## `--config PATH`

`--config PATH` selects the config file for **any config-backed action**:
`--generate`, `--refresh-splash`, `--sync`, `--dry-run`, `--print-config`, and
`--clean`. (`--init` and `--version` never load a config and reject `--config`.)

When `--config PATH` is not provided, those actions read `./shuriken.conf`. If
the file is missing, run `shuriken --init` first.

`--dry-run`, `--print-config`, and `--refresh-splash` accept the same override
options as `--generate`.

## Config-value override options

These long options override config values for the current run. Each pairs with a
config variable documented in [configuration.md](configuration.md).

| Option | Config value |
| --- | --- |
| `--incoming PATH` | `INCOMING_DIR` |
| `--dist PATH` | `DIST_DIR` |
| `--template PATH` | `TEMPLATE_DIR` |
| `--favicon PATH` | `FAVICON` |
| `--source-url URL` | `SOURCE_URL` |
| `--title TEXT` | `TITLE` |
| `--height VALUE` | `HEIGHT` |
| `--thumbheight VALUE` | `THUMBHEIGHT` |
| `--maxpreviews N` | `MAXPREVIEWS` |
| `--subdivide PERCENT` | `THUMB_SUBDIVIDE_PERCENT` |
| `--image-jobs N` | `IMAGE_JOBS` |
| `--random-seed VALUE` | `RANDOM_SEED` |
| `--shuffle` | `SHUFFLE=yes` |
| `--no-shuffle` | `SHUFFLE=no` |
| `--splash` | `SPLASH_PAGE=yes` |
| `--no-splash` | `SPLASH_PAGE=no` |
| `--stats` | `STATS_PAGE=yes` |
| `--no-stats` | `STATS_PAGE=no` |
| `--tarball` | `TARBALL_INCLUDE=yes` |
| `--no-tarball` | `TARBALL_INCLUDE=no` |
| `--sync-delete` | `SYNC_DELETE=yes` |
| `--no-sync-delete` | `SYNC_DELETE=no` |

Pass `--sync-destination DEST` one or more times with `--sync` to override the
configured sync destinations for that run.

## Output flags

Output is human-readable by default and reports routine generation progress.

* `--quiet` suppresses routine progress while still writing errors to stderr.
* `--verbose` adds extra diagnostics, including the selected config file,
  effective paths, skipped existing files, staging output directory, and tarball
  decisions.
* If `--quiet` and `--verbose` are repeated or combined, the last output flag
  wins. `--quiet` does not suppress `--print-config` output, and `--verbose`
  does not add human-readable diagnostics to it.

## Validation before generation

Before generating, shuriken validates the loaded config and command-line
overrides: required values, positive-integer settings, `yes`/`no` settings,
readable input and template directories, a writable output location, and
ImageMagick availability. Generation stops before writing album output when
validation fails. See [configuration.md](configuration.md) for the details.