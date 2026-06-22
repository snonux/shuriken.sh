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
`shuriken --sync` / `just sync`, which would publish to the live web servers.
