# Generation

This page describes how `shuriken --generate` works and the features that
affect its output.

## Artifact reuse and incremental generation

Normal generation preserves reusable generated artifacts from the previous
`DIST_DIR` while still rerendering HTML, random splash/background choices,
animation classes, timestamps, and shuffled preview order. Existing scaled
photos, thumbnails, and blurs are reused from the previous output when the
source image is unchanged.

## The EXIF cache

The per-photo EXIF `identify` output is cached in a separate `cache/exif/`
directory created next to `DIST_DIR` (i.e. parallel to `dist/` in the working
directory — the path is `$(dirname "$DIST_DIR")/cache/exif`). Each cache entry
records a `<photo>:<size>:<mtime>` signature so it is reused only while the
source file is unchanged.

This cache is volatile and safe to delete, is **not** part of the published
output (it is never written into `DIST_DIR`, so `--sync` does not deploy it),
and persists across runs even if `DIST_DIR` is removed or rebuilt. Because
reading EXIF from full-size originals is the slowest part of generation, keeping
this cache makes regenerating an album dramatically faster: an unchanged photo
skips `identify` entirely.

* `--clean` removes `DIST_DIR` (and any leftover staging directories) but leaves
  `cache/` in place; delete `cache/` by hand to force a full EXIF rebuild on the
  next run.
* `--force` (with `--generate`) clears `cache/` once up front, then repopulates
  it during the run, so there is still exactly one `identify` per photo even
  under force.

## Splash page

By default the generated root `index.html` is a no-JavaScript splash page using
a randomly selected album photo. Set `SPLASH_PAGE=no` or pass `--no-splash` to
restore the top-level redirect to `page-1.html`.

To quickly pick a new random splash photo for an already generated album, run
`shuriken --refresh-splash`. This rewrites `DIST_DIR/index.html` (and re-copies
the site favicon) using the existing `photos` and `blurs` output, so it avoids
reprocessing images and rerendering album pages. It requires `SPLASH_PAGE=yes`;
pass `--random-seed VALUE` when you need a repeatable pick.

## Stats site

`shuriken` can also generate a no-JavaScript stats site with EXIF-derived
insights (camera leaderboard, shooting dates, exposure, dimension, format, and
decoded-enum breakdowns), reachable from the `Stats` link in the page header
bar. This is off by default; set `STATS_PAGE=yes` or pass `--stats` to enable it.

Every row on the stats overview is clickable: each bucket (each camera, ISO,
year, aperture, orientation, …) is its own filter "mini-album" — a gallery of
just the matching photos with view pages whose previous/next cycle within that
filter.

To keep the album root uncluttered, all of this lives under a `stats/`
subdirectory: the overview is `stats/index.html` and each mini-album is its own
directory `stats/<filter>/` (gallery `index.html` plus numbered view pages). Only
the main album sits in `DIST_DIR` itself. The mini-album pages reuse the album's
shared `photos/`, `thumbs/`, and `blurs/` assets (only the HTML is per-filter)
and are rendered in parallel honouring `IMAGE_JOBS`. Set `STATS_PAGE=no` or pass
`--no-stats` (the default) to skip the whole `stats/` tree and hide the link.

See [stats-exif-audit.md](stats-exif-audit.md) for the EXIF field coverage
analysis behind these categories.

## Reproducibility

By default, splash and background photos, animation classes, generated
timestamps, and `--shuffle` preview order remain non-deterministic. Set
`RANDOM_SEED` in the config, or pass `--random-seed VALUE`, to make those
choices repeatable for stable tests or reproducible album builds. Use the same
seed and inputs to produce the same HTML.

## Parallelism and timeouts

ImageMagick photo processing and per-photo HTML template rendering run in
parallel. The default is `IMAGE_JOBS=3`. Set `IMAGE_JOBS` in the config, or pass
`--image-jobs N`, to tune the number of concurrent image and template jobs.

Each ImageMagick command is bounded by `IMAGEMAGICK_TIMEOUT=60` seconds, and
tarball creation is bounded by `TAR_TIMEOUT=120` seconds. Set either config
value to a positive integer to adjust the limit for large images or archives.

## Generation metadata (`shuriken.json`)

Successful generation writes `shuriken.json` into the output directory. This
metadata records:

* the generator name and version, and a generation timestamp;
* the config source and template name/directory;
* the source `INCOMING_DIR` and source image count;
* generated photo, thumbnail, and HTML file counts;
* tarball status (included + file);
* effective settings (title, height, thumbheight, maxpreviews, image jobs,
  random seed, shuffle, splash page, stats page, original basepath) useful for
  debugging a published album.

## Favicon

Generation writes `favicon.ico` into the output directory and the default
templates link to it. By default this is the bundled shuriken favicon; set
`FAVICON` in the config or pass `--favicon PATH` to publish your own favicon
file instead (it is copied in as `favicon.ico`).

## Source URL

The page header bar links to the project source ("Site generated … with
`<URL>`"). This defaults to the shuriken.sh repository; set `SOURCE_URL` in
the config or pass `--source-url URL` to point it at your own album's repository
instead. The displayed link text is the URL with its scheme removed.