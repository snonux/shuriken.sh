# shuriken

<img src="assets/docs/shuriken-logo.svg" alt="Shuriken logo" width="160">

shuriken is a Bash script for Unix-like operating systems (such as Linux) that
generates static web photo albums. The resulting album is pure HTML+CSS — no
JavaScript.

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
`--maxpreviews`, `--image-jobs`, `--random-seed`, `--shuffle`/`--no-shuffle`,
`--splash`/`--no-splash`, `--stats`/`--no-stats`, `--tarball`/`--no-tarball`,
`--favicon`, `--source-url`, `--sync-destination`, `--sync-delete`/`--no-sync-delete`,
`--quiet`, `--verbose`.

Feature toggles at a glance:

* **Splash page** (`SPLASH_PAGE=yes`, the default): the root `index.html` is a
  no-JavaScript splash page using a random album photo. `--no-splash` restores a
  top-level redirect to `page-1.html`.
* **Stats site** (`STATS_PAGE=no`, the default): set `--stats` to generate a
  no-JavaScript EXIF stats site under `stats/` (camera leaderboard, shooting
  dates, exposure/dimension/format breakdowns), with each bucket as its own
  clickable filter mini-album.
* **Reproducible builds**: set `RANDOM_SEED` (or `--random-seed VALUE`) to make
  splash/background picks, animation classes, timestamps, and shuffle order
  repeatable.

## Documentation

The quick start above is all you need for a first album. Detailed reference:

* [docs/installation.md](docs/installation.md) — build, install, paths, packaging overrides, requirements.
* [docs/usage.md](docs/usage.md) — full CLI reference: every action, `--config`, the override-option table, output flags.
* [docs/configuration.md](docs/configuration.md) — the config file format, every variable, defaults, and validation rules.
* [docs/generation.md](docs/generation.md) — how generation works: artifact reuse, the EXIF cache, `--force`, splash/stats pages, `--refresh-splash`, reproducibility, parallelism/timeouts, `shuriken.json`, favicon, source URL.
* [docs/publishing.md](docs/publishing.md) — publishing with `--sync`, `SYNC_DESTINATIONS`, `SYNC_DELETE`, and the rsync command.
* [docs/templates.md](docs/templates.md) — HTML template layout and customization.
* [docs/stats-exif-audit.md](docs/stats-exif-audit.md) — EXIF field coverage audit behind the stats site (historical design record).