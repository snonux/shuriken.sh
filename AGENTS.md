# Agent Guidance

For Bash changes in this repository, load and follow the
`bash-best-practices` skill before editing. Keep changes focused, preserve the
public `photoalbum` CLI, and run the project checks before committing.

`src/photoalbum.sh` is the source for the generated `bin/photoalbum` script. If
the source changes, run `just build` and keep `bin/photoalbum` synchronized.

Expected checks for Bash changes:

- `just test`
- `just shellcheck`
- `just check-generated`
- `git diff --check`
