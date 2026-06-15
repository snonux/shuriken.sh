# Stats Page EXIF Field Coverage Audit

Task `nm0` for the stats site feature (see
`/home/paul/.pi/plans/shuriken-stats-site.md`). This document decides which of
the planned stats categories are actually buildable from the EXIF/identify data
that shuriken already extracts, so the downstream tasks (`om0`/`pm0`/`rm0`/`um0`)
do not build dead stats.

## Method

The audit is based on shuriken's **existing extraction code**, not a live photo
library (there is none to point at):

* `src/lib/imagemagick.source.sh` runs `magick identify -verbose <file>` (or
  `convert <file> -verbose info:` when only the legacy `convert` is present).
* `src/lib/album.source.sh` caches that raw output per photo under a volatile
  `./cache/exif/<photo>.txt` (parallel to `./dist`) and parses it.

The parser detail that drives every decision below: shuriken only reads EXIF
through this regex (`photo_exif_details_html`, `_photo_exif_values_to`):

```
^[[:space:]]*exif:([^:]+):[[:space:]]*(.*)$
```

It captures **only lines that begin with `exif:`**. Native `identify` fields
that live outside the `exif:` namespace (`Format`, `Geometry`, `Orientation`,
`Resolution`, `Mime type`, ...) are present in the cached output but are **not**
reachable by the current code and would need a small parser extension.

### What `magick identify -verbose` actually exposes

Confirmed empirically against a synthetic JPEG tagged with exiftool:

```
  Format: JPEG (Joint Photographic Experts Group JFIF format)
  Geometry: 100x100+0+0
  Orientation: BottomRight
    exif:DateTimeOriginal: 2023:06:14 15:30:00
    exif:ExposureProgram: 3
    exif:ExposureTime: 1/250
    exif:FNumber: 14/5
    exif:FocalLength: 50/1
    exif:LensModel: EF50mm f/1.8 STM
    exif:Make: Canon
    exif:MeteringMode: 5
    exif:Model: Canon EOS 5D Mark IV
    exif:PhotographicSensitivity: 400
    exif:Software: Adobe Lightroom
    exif:WhiteBalance: 0
```

Critical observations:

* **Values are raw, not friendly.** ImageMagick does not decode enumerations.
  `ExposureProgram`, `MeteringMode`, `WhiteBalance`, and `Flash` come through as
  bare integers; `FNumber` and `FocalLength` come through as rationals
  (`14/5`, `50/1`). Any human-readable stat must do its own decoding.
* **ISO is named `exif:PhotographicSensitivity`** in modern EXIF, not `ISO` or
  `ISOSpeedRatings`. shuriken's `_first_exif_value_to` already tries all three,
  so the aggregation code should reuse that fallback order.
* **`Flash` only appears as `exif:Flash` when the camera writes the bare EXIF
  Flash tag.** When a tool stores flash state only in MakerNotes or as a
  computed/XMP value, ImageMagick surfaces nothing usable (we observed only
  `xmp:Flash`, which the regex ignores). So Flash is real-but-flaky.
* **`Orientation` is a native field**, not `exif:Orientation`. For orientation
  stats, comparing width vs height from `Geometry` is both reachable and more
  reliable than the rotation flag.

## Per-category verdict

| Category | Source field(s) | Reachable today? | Verdict | Notes / required work |
| --- | --- | --- | --- | --- |
| Camera leaderboard (Make + Model) | `exif:Make`, `exif:Model` | Yes | **Viable** | Reuse the Make/Model joining logic already in `_photo_exif_tooltip_text_from_values` (handles "Model already includes Make"). Slug from sanitized string. |
| Lens model | `exif:LensModel` | Yes | **Conditional** | Often absent on phones/compacts and some bodies. Show only when present; do not assume coverage. |
| Photos per year/month | `exif:DateTimeOriginal` | Yes | **Viable** | Format is `YYYY:MM:DD HH:MM:SS`. Parse with `${var:0:4}` / `:5:2` substrings; do not feed to `date -d` (the colons in the date part are non-standard). Fall back to `DateTimeDigitized`/`DateTime`. |
| Photos per hour-of-day / day-of-week | `exif:DateTimeOriginal` | Yes | **Conditional** | Hour is a substring (`:11:2`). Day-of-week needs a real date conversion; reformat to `YYYY-MM-DD` first, then `date -d`. Slightly more code, still viable. |
| Aperture histogram | `exif:FNumber` (fallback `ApertureValue`) | Yes | **Viable** | Rational `num/den` (`14/5` = f/2.8). Compute the decimal, then bucket to standard stops. `ApertureValue` is APEX, a different scale — prefer `FNumber`. |
| Shutter-speed histogram | `exif:ExposureTime` (fallback `ShutterSpeedValue`) | Yes | **Viable** | Value is usually `1/250` or `1/250` style, sometimes a decimal (`0.5`, `1/1`). Normalize to seconds (`num/den`) before bucketing. `ShutterSpeedValue` is APEX; convert or ignore. |
| ISO histogram | `exif:PhotographicSensitivity` (fallback `ISOSpeedRatings`, `ISO`) | Yes | **Viable** | Plain integer. Bucket to standard values. Use the existing 3-tag fallback order. |
| Exposure program | `exif:ExposureProgram` | Yes | **Viable** | Raw enum integer (0-8). Needs a decode map (0 Not defined, 1 Manual, 2 Program AE, 3 Aperture priority, 4 Shutter priority, 5 Creative, 6 Action, 7 Portrait, 8 Landscape). |
| Flash usage | `exif:Flash` | Sometimes | **Conditional** | Raw bitmask integer; bit 0 = fired. Reachable by the regex *only when* the camera writes the bare EXIF Flash tag; absent for many phone/edited images. Decode `value & 1` for fired/not-fired and tolerate missing data. |
| Megapixels histogram | `Geometry` (native) | No (parser ext.) | **Viable** | Parse `WxH+x+y` from the native `Geometry` line; `MP = W*H/1e6`. Requires extending the parser beyond `exif:` lines (or adding a dedicated native-field reader). |
| Aspect ratio | `Geometry` (native) | No (parser ext.) | **Viable** | Same `WxH` source; reduce by GCD and match common ratios (3:2, 4:3, 16:9, 1:1, 5:4, other). |
| Orientation | `Geometry` (native) | No (parser ext.) | **Viable** | Derive from W vs H (landscape/portrait/square). More reliable than the native `Orientation` rotation flag, which is frequently absent or already baked in. |
| Format breakdown | `Format` (native) or file extension | No (parser ext.) / Yes | **Viable** | The native `Format:` line gives JPEG/PNG/WEBP/GIF. Alternatively reuse `is_supported_image_file` extension logic (`image.source.sh`) with zero identify parsing — cheapest path. |
| Focal length | `exif:FocalLength` | Yes | **Viable** | Rational `50/1` mm. Compute decimal, bucket by range. Note this is the physical focal length, not 35mm-equivalent; label accordingly. |
| White balance | `exif:WhiteBalance` | Yes | **Conditional** | Standard EXIF WhiteBalance is only a 2-value enum: 0 = Auto, 1 = Manual. The richer "Daylight/Cloudy/Tungsten/Flash" breakdown the plan imagines lives in MakerNotes and is **not** exposed by `identify`. Build only Auto-vs-Manual. |
| Metering mode | `exif:MeteringMode` | Yes | **Viable** | Raw enum integer. Decode map (0 Unknown, 1 Average, 2 Center-weighted, 3 Spot, 4 Multi-spot, 5 Multi-segment/Pattern, 6 Partial, 255 Other). |
| Software | `exif:Software` | Yes | **Conditional** | Free-text; values are noisy ("Adobe Lightroom", camera firmware strings, "GIMP 2.10"). Often absent. Useful as a raw top-N list, not a clean enum. |

## Fields ImageMagick does NOT reliably surface

Do not build stats that depend on these from `identify -verbose`:

* **Rich white-balance presets** (Daylight/Cloudy/Tungsten/...): MakerNotes only.
* **Flash detail** beyond fired/not-fired, and Flash at all for many edited or
  phone images.
* **GPS** (already out of scope in the plan, and inconsistently present).
* **Friendly enum names** for any tag — every enumerated value arrives as an
  integer and must be decoded in shuriken.

## Cross-cutting parsing work required

Every viable numeric stat needs a normalization helper. The shared work is:

* **Rational decoder** for `FNumber`, `FocalLength`, `ExposureTime`,
  `ShutterSpeedValue` (`num/den` -> decimal; guard `den == 0`).
* **DateTimeOriginal splitter** for `YYYY:MM:DD HH:MM:SS` (substring extraction;
  reformat before any `date -d` use).
* **Enum decode maps** for `ExposureProgram`, `MeteringMode`, `WhiteBalance`,
  `Flash` (bitmask).
* **Native-field reader**: a second match path for `Format:` and `Geometry:`
  lines, since the current regex is `exif:`-only. The cheapest alternative for
  Format is to skip identify entirely and key off the file extension via the
  existing `is_supported_image_file` logic.
* Reuse `_first_exif_value_to` and its fallback tag orders rather than
  re-deriving them.

## Recommended stat set for v1

Core (reliable, low parsing risk):

1. **Camera leaderboard** (Make + Model), clickable to per-camera pages.
2. **Photos per year** and **photos per month** (from `DateTimeOriginal`).
3. **Aperture** histogram (`FNumber`, rational -> stops).
4. **Shutter speed** histogram (`ExposureTime`, normalized to seconds).
5. **ISO** histogram (`PhotographicSensitivity` w/ fallbacks).
6. **Focal length** histogram (`FocalLength`, rational -> mm buckets).
7. **Format breakdown** (file extension, no identify parsing needed).
8. **Megapixels**, **aspect ratio**, and **orientation** (from `Geometry`,
   needs the native-field parser extension).
9. **Exposure program** and **metering mode** (enum decode).

Include if cheap, but tolerate sparsity (show only when data exists):

* **Lens model** leaderboard (`LensModel`).
* **Photos per hour-of-day / day-of-week** (extra date math).
* **Flash fired vs not fired** (`exif:Flash` bitmask, frequently missing).

Defer / downgrade:

* **White balance** -> ship only **Auto vs Manual**; the preset breakdown is
  not available from `identify`.
* **Software** -> ship as a raw top-N list, not a clean category; treat as
  nice-to-have.

GPS/heatmap and rich white-balance presets stay out (no reliable source).
