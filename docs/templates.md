# HTML templates

Templates live under `share/templates/default` in the source tree and under the
installed template directory (`/usr/share/shuriken/templates/default`) after
installation.

The stock default resolves to the installed template directory when it exists,
and otherwise falls back to the source tree's `share/templates/default` when
running from a checkout. Copy and edit templates, then point `TEMPLATE_DIR` or
`--template PATH` at the customized directory.

## Required templates

A template directory must contain these `.tmpl` files (validated before
generation):

`details`, `footer`, `header`, `next`, `prev`, `preview`, `previewpage`,
`redirect`, `view`.

When `SPLASH_PAGE=yes`, the `splash` template is also required.

## Stats templates

The stats site adds two more templates, `camera.tmpl` and `cameraview.tmpl`
(per-camera mini-album), plus `stats.tmpl` for the overview page. These are only
used when `STATS_PAGE=yes`.

## Header bar and footer

* The page **header bar** (`header.tmpl`) renders the "Site generated … with
  `<SOURCE_URL>`" link and, when `STATS_PAGE=yes`, the `Stats` navigation
  link.
* The page **footer** (`footer.tmpl`) renders the "Download all photos in
  original size" tarball link, shown only when `TARBALL_INCLUDE=yes`.