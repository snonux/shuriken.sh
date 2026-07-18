# shuriken

<img src="assets/docs/shuriken-logo.svg" alt="Shuriken logo" width="160">

shuriken is a Bash script for Unix-like operating systems (such as Linux) that
generates static web photo albums. The resulting album is pure HTML+CSS — no
JavaScript.

## Platform compatibility

shuriken relies on **GNU** versions of four standard Unix tools: it uses the
GNU-only extensions `find -printf`, `stat -c`, `cp -a`, and `sort -R`, which
are not supported by the BSD variants of those tools shipped with macOS and
FreeBSD. shuriken runs on Linux, macOS, and FreeBSD: at startup it resolves
each of the four tools to whichever binary is actually GNU, preferring a
`g`-prefixed sibling (`gfind`, `gstat`, `gcp`, `gsort`) over the plain name
when one is on `PATH` (mirroring the tool-selection variables used by the
sibling [gemtexter](https://codeberg.org/snonux/gemtexter) project). On Linux
the plain names are already GNU, so nothing extra is required. On macOS and
FreeBSD you must install GNU coreutils/findutils first — shuriken verifies at
startup that the resolved tools are genuinely GNU and exits with a clear error
naming the missing tool otherwise, rather than failing confusingly deep inside
generation.

### Installing GNU coreutils on macOS

Via [Homebrew](https://brew.sh):

```sh
brew install coreutils findutils
```

Homebrew installs these under their GNU names prefixed with `g`
(`gstat`, `gcp`, `gsort` from `coreutils`; `gfind` from `findutils`) so they
do not clobber the system BSD tools of the same bare name; shuriken picks them
up automatically. (`brew install gnu-sed grep` are not required by shuriken
today, but are commonly installed alongside for other GNU-reliant scripts.)

### Installing GNU coreutils on FreeBSD

Via `pkg`:

```sh
pkg install coreutils findutils
```

This installs the GNU tools under their `g`-prefixed names (`gstat`, `gcp`,
`gsort`, `gfind`) alongside the base-system BSD tools, which shuriken picks up
automatically. (`pkg install gsed gnugrep` are not required by shuriken today
but provide `gsed`/`ggrep` for other GNU-reliant scripts.)

## Example site

[irregular.ninja](https://irregular.ninja) is a live photo album built with
shuriken. Its source — including the `shuriken.conf`, templates, and publish
setup — lives at
[codeberg.org/snonux/irregular.ninja](https://codeberg.org/snonux/irregular.ninja)
and works as a ready-to-read sample configuration for all of shuriken's
features.

## Quick start

```sh
just build            # build ./bin/shuriken from src/
sudo just install     # install command, templates, and default config
shuriken --init       # creates ./shuriken.conf in the current directory
```

Edit `shuriken.conf` and point `INCOMING_DIR` at a directory of photos, then:

```sh
shuriken --dry-run    # preview the planned generation (writes nothing)
shuriken --generate   # build the album into ./dist (DIST_DIR)
shuriken --sync       # publish ./dist to the configured remote hosts
shuriken --clean      # remove ./dist and leftover staging dirs
```

ImageMagick (`magick` or `convert`) and Bash 5.1 or newer are required.
GNU coreutils/findutils (`find`, `stat`, `cp`, and `sort`) are also required;
on Linux the default tools already are GNU, on macOS/FreeBSD install the
`g`-prefixed GNU versions first (see *Platform compatibility* above).

## Main flags

| Flag | Purpose |
| --- | --- |
| `--init` | Create `./shuriken.conf` from the default config (refuses to overwrite). |
| `--generate` | Build the static album. |
| `--force` | With `--generate`: rebuild all image artifacts and re-read every EXIF tag from scratch. |
| `--dry-run` | Load config + overrides, validate, and print the plan without writing output or running ImageMagick/tar. |
| `--print-config` | Print the effective configuration as shell assignments. |
| `--refresh-splash` | Rewrite only the root splash page of an already generated album. |
| `--sync` | Publish `DIST_DIR/` to configured rsync destinations. |
| `--clean` | Remove `DIST_DIR` and leftover `.shuriken.*.staging`/`.backup` dirs. |
| `--version` | Print the program version. |
| `--config PATH` | Select the config file to use (default: `./shuriken.conf`). |

Common per-run overrides (see the full reference table in [docs/usage.md](docs/usage.md)):

`--incoming`, `--dist`, `--template`, `--title`, `--height`, `--thumbheight`,
`--maxpreviews`, `--image-jobs`, `--random-seed`,
`--chronological`/`--no-chronological`, `--shuffle`/`--no-shuffle`,
`--splash`/`--no-splash`, `--details`/`--no-details`, `--stats`/`--no-stats`,
`--tarball`/`--no-tarball`, `--favicon`, `--source-url`, `--sync-destination`,
`--sync-delete`/`--no-sync-delete`, `--quiet`, `--verbose`.

Feature toggles at a glance:

* **Splash page** (`SPLASH_PAGE=yes`, the default): the root `index.html` is a
  no-JavaScript splash page using a random album photo. `--no-splash` restores a
  top-level redirect to `page-1.html`.
* **Details pages** (`DETAILS_PAGE=yes`, the default): every photo gets a
  `*-details.html` EXIF summary page linked from its normal view page.
  `--no-details` skips these pages and removes their "Details" links (from the
  normal view pages and, when stats are enabled, the stats filter mini-albums)
  without affecting EXIF tooltips or the stats site itself.
* **Stats site** (`STATS_PAGE=no`, the default): set `--stats` to generate a
  no-JavaScript EXIF stats site under `stats/` (camera leaderboard, shooting
  dates, exposure/dimension/format breakdowns), with each bucket as its own
  clickable filter mini-album.
* **Reproducible builds**: set `RANDOM_SEED` (or `--random-seed VALUE`) to make
  splash/background picks, animation classes, timestamps, and shuffle order
  repeatable.
* **Chronological order** (`CHRONOLOGICAL_ORDER=no`, the default): set to
  `yes` (or pass `--chronological`) to order the main album's photos by EXIF
  date taken instead of filename/shuffle order, falling back to source mtime
  for photos with no usable EXIF date. Takes precedence over `SHUFFLE` when
  both are enabled.

## Documentation

The quick start above is all you need for a first album. Detailed reference:

* [docs/installation.md](docs/installation.md) — build, install, paths, packaging overrides, requirements.
* [docs/usage.md](docs/usage.md) — full CLI reference: every action, `--config`, the override-option table, output flags.
* [docs/configuration.md](docs/configuration.md) — the config file format, every variable, defaults, and validation rules.
* [docs/generation.md](docs/generation.md) — how generation works: artifact reuse, the EXIF cache, `--force`, splash/details/stats pages, `--refresh-splash`, reproducibility, parallelism/timeouts, `shuriken.json`, favicon, source URL.
* [docs/publishing.md](docs/publishing.md) — publishing with `--sync`, `SYNC_DESTINATIONS`, `SYNC_DELETE`, and the rsync command.
* [docs/templates.md](docs/templates.md) — HTML template layout and customization.
* [docs/stats-exif-audit.md](docs/stats-exif-audit.md) — EXIF field coverage audit behind the stats site (historical design record).