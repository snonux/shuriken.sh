# Configuration

The config file is a Bash file sourced by shuriken. `shuriken --init` creates
`./shuriken.conf` from the default config; edit it and override any of the
variables below. Command-line options (see [usage.md](usage.md)) override config
values for the current run.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `TITLE` | `A simple Shuriken` | Album title. |
| `HEIGHT` | `1200` | Scaled photo height in pixels. Leave unset to keep original size. Optional positive integer. |
| `THUMBHEIGHT` | `300` | Thumbnail height in pixels. Positive integer. |
| `MAXPREVIEWS` | `40` | Maximum previews per page. Positive integer. |
| `THUMB_SUBDIVIDE_PERCENT` | `30` | Percent chance (0-100) that a preview tile is subdivided into smaller thumbnails (2x2 quad, two stacked wide strips, or two squares plus one wide strip on top/bottom). Each sub-thumbnail is its own clickable photo. `0` disables it. |
| `THUMB_FEATURE_PERCENT` | `10` | Percent chance (0-100) that a preview tile is a large "feature" tile: a single photo spanning a 2x2 block of the overview grid. Rolled before the subdivision chance. `0` disables it. |
| `IMAGE_JOBS` | `3` | Parallel jobs for image processing and HTML template rendering. Positive integer. |
| `IMAGEMAGICK_TIMEOUT` | `60` | Per-ImageMagick-command timeout in seconds. Positive integer. |
| `TAR_TIMEOUT` | `120` | Tarball creation timeout in seconds. Positive integer. |
| `SHUFFLE` | `no` | Randomly shuffle all previews. `yes`/`no`. |
| `SPLASH_PAGE` | `yes` | Generate a splash landing page at `index.html`. `yes`/`no`. |
| `STATS_PAGE` | `no` | Generate the EXIF stats site under `stats/`. `yes`/`no`. |
| `RANDOM_SEED` | _(unset)_ | Any non-empty value makes splash/background picks, animation classes, timestamps, and shuffle order repeatable. |
| `INCOMING_DIR` | `$(pwd)/incoming` | Directory containing source photos (full path). |
| `DIST_DIR` | `$(pwd)/dist` | Output directory (full path). |
| `TEMPLATE_DIR` | `/usr/share/shuriken/templates/default` | Template directory. Falls back to the source tree's `share/templates/default` when running from a checkout. |
| `FAVICON` | _(unset = bundled default)_ | Custom favicon, published as `favicon.ico`. Must be a readable file when set. |
| `SOURCE_URL` | `https://codeberg.org/snonux/shuriken.sh` | Project/source link shown in the page header bar. |
| `TARBALL_INCLUDE` | `yes` (in `--init` config) | Include a `.tar` of the incoming dir in the dist. `yes`/`no`. |
| `TARBALL_SUFFIX` | `.tar` | Suffix for the generated tarball. |
| `TAR_OPTS` | `(-c)` | Tar options as a Bash array (or whitespace-separated scalar). |
| `SYNC_DELETE` | `yes` | Pass `--delete` to rsync on `--sync`. `yes`/`no`. |
| `SYNC_DESTINATIONS` | `()` | Bash array of rsync destinations. See [publishing.md](publishing.md). |
| `ORIGINAL_BASEPATH` | _(unset)_ | Recorded in `shuriken.json` for debugging a published album. |

> Note on `TARBALL_INCLUDE`: the bundled `shuriken.default.conf` sets it to
> `yes`, so a freshly `--init`'d config enables the tarball. The runtime default
> applied when a config file leaves it unset is `no`.

## Supported source images

Only regular files found directly in `INCOMING_DIR` (not in subdirectories) with
supported image extensions are processed as album images. Supported extensions
are `jpg`, `jpeg`, `png`, `webp`, and `gif`, matched case-insensitively. Other
files, such as `.txt` or `.md` notes, are ignored with a warning so generation
can continue.

## Validation

`shuriken` validates the loaded config and command-line overrides before acting.
The checks (details in `src/lib/config.validate.source.sh`):

* **Required values** are set: `TITLE`, `THUMBHEIGHT`, `MAXPREVIEWS`,
  `IMAGE_JOBS`, `INCOMING_DIR`, `DIST_DIR`, `TEMPLATE_DIR`.
* **Positive integers**: `THUMBHEIGHT`, `MAXPREVIEWS`, `IMAGE_JOBS`,
  `IMAGEMAGICK_TIMEOUT`, `TAR_TIMEOUT`; `HEIGHT` is an optional positive integer.
* **Percentage (0-100 integer)**: `THUMB_SUBDIVIDE_PERCENT`,
  `THUMB_FEATURE_PERCENT`.
* **`yes`/`no` settings**: `SHUFFLE`, `SPLASH_PAGE`, `STATS_PAGE`,
  `TARBALL_INCLUDE`, `SYNC_DELETE` (where applicable).
* **Readable input**: `INCOMING_DIR` must be a readable directory; `TEMPLATE_DIR`
  must be a readable directory containing the required templates (plus `splash`
  when `SPLASH_PAGE=yes`).
* **Writable output**: `DIST_DIR` (or its nearest existing parent) must be
  writable.
* **ImageMagick** availability (`magick` or `convert`).
* **`FAVICON`**, when set, must be a readable file.
* **`--clean`** additionally refuses to delete dangerous paths (filesystem root,
  `HOME`, the current directory, well-known system trees) after resolving
  `DIST_DIR` canonically.
* **`--sync`** requires at least one destination and rsync.

Generation stops before writing album output when validation fails.

## `--print-config` output format

`--print-config` writes stable shell-style assignments to stdout in this order:

`CONFIG_SOURCE`, `INCOMING_DIR`, `DIST_DIR`, `TEMPLATE_DIR`, `FAVICON`,
`SOURCE_URL`, `TITLE`, `HEIGHT`, `THUMBHEIGHT`, `MAXPREVIEWS`,
`THUMB_SUBDIVIDE_PERCENT`, `THUMB_FEATURE_PERCENT`, `IMAGE_JOBS`,
`IMAGEMAGICK_TIMEOUT`, `RANDOM_SEED`, `SHUFFLE`, `SPLASH_PAGE`, `STATS_PAGE`,
`TARBALL_INCLUDE`, `TARBALL_SUFFIX`, `TAR_TIMEOUT`, `TAR_OPTS`, `SYNC_DELETE`,
`SYNC_DESTINATIONS`, `ORIGINAL_BASEPATH`.

Scalar values use Bash `%q` quoting; `TAR_OPTS` and `SYNC_DESTINATIONS` are
normalized to Bash array assignments, so the output can be parsed by shell
tooling. `--quiet` does not suppress this output, and `--verbose` does not add
human-readable diagnostics to it.