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
