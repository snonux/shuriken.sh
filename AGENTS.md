# Agent Guidance

For Bash changes in this repository, load and follow the
`bash-best-practices` skill before editing. Keep changes focused, preserve the
public `shuriken` CLI, and run the project checks before committing.

`src/shuriken.sh` is the source for the generated `bin/shuriken` script. If
the source changes, run `just build` and keep `bin/shuriken` synchronized.

Expected checks for Bash changes:

- `just test`
- `just shellcheck`
- `just check-generated`
- `git diff --check`

## Manual visual testing

To eyeball generated output (thumbnail grid, tile subdivision, splash, stats),
regenerate the real `irregular.ninja` album with the freshly built binary and
template, then open it in Firefox:

```sh
just build
cd ~/git/irregular.ninja/irregular.ninja
/path/to/shuriken.sh/bin/shuriken --generate \
    --template /path/to/shuriken.sh/share/templates/default
firefox "file://$PWD/dist/index.html"
```

Use the in-tree `bin/shuriken` and `share/templates/default` (not the installed
copies) so local changes are exercised. Existing thumbnails/blurs are reused, so
only the HTML is re-rendered. This regenerates locally only — do **not** run
`shuriken --sync` / `just sync` unless explicitly asked, since it publishes to
the live web servers (`irregular.ninja` syncs to fishfinger + blowfish).

## W3C validation (HTML + CSS)

Generated pages must stay W3C-conformant. **Every page of a given kind is
template-generated and structurally identical, so validate ONE page per kind —
never scan all sub-pages.** A full album is ~10k+ HTML files; bulk-validating
them wastes time, hammers the public service, and can fill a tmpfs (a stray
multi-GB validator log once exhausted RAM and broke the build).

The page kinds (one representative each, from a generated `dist/`):

- `index.html` — splash
- `page-1.html` — preview overview grid (tiles / 2x2 features / subdivisions)
- `1-1.html` — photo view page
- `1-1-details.html` — details page
- `1-0.html` — navigation redirect
- `stats/index.html` — stats overview
- `stats/<camera-or-filter>/index.html` — a stats mini-album gallery
- `stats/<camera-or-filter>/1.html` — a mini-album view page

### Live service — https://validator.w3.org/

HTML, per representative page (the Nu checker that backs validator.w3.org):

```sh
curl -sS -H "Content-Type: text/html; charset=utf-8" --data-binary @page-1.html \
    "https://validator.w3.org/nu/?out=json"
```

CSS is identical across pages, so validate the stylesheet once with the W3C CSS
validator (Jigsaw). Extract the inline `<style>` block to a file, then:

```sh
curl -sS 'https://jigsaw.w3.org/css-validator/validator' \
    -F "file=@album.css;type=text/css" -F profile=css3 -F output=json -F warning=no
```

Both should report zero errors (`messages[].type=="error"` for HTML;
`cssvalidation.result.errorcount` for CSS).

### Local Nu engine (offline, no rate limits)

`vnu.jar` is the exact same checker the W3C site runs, so prefer it for repeated
runs. Download once and validate the representative pages (it checks inline CSS
too with `--also-check-css`):

```sh
curl -sSL -o /tmp/vnu.jar \
    https://github.com/validator/validator/releases/download/latest/vnu.jar
java -jar /tmp/vnu.jar --also-check-css --errors-only \
    index.html page-1.html 1-1.html 1-1-details.html 1-0.html \
    stats/index.html stats/<camera>/index.html stats/<camera>/1.html
```

No output and exit 0 means all clean. Pass individual files (one per kind) — do
**not** point it at a whole `dist/` directory.
