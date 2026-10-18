# Developer resources

Maintainer tooling for qb-compile. None of it is needed to build packages.

## Formatting and version tooling

Scripts in this repository carry a metadata header, and part of it drives automation on save: `@save_tasks` with `automated_versioning: true` makes the tools below bump the file's `@version`.

| Script | Purpose |
|--------|---------|
| `format-bash.sh <file...>` or `--all` | Format Bash files with `shfmt` (2-space indent) and bump the version where enabled. Run it by hand or from an editor task. |
| `quick-format.sh` | Run `format-bash.sh` over the modified and untracked `.sh` files in the working tree. |
| `vscode-formatter.sh <file>` | Single-file variant used by the VS Code run-on-save setting in `.vscode/settings.json`. |
| `onSave` | The original save hook (formatting, version bump, strict-mode checks, and `.github/version.txt`). It takes a file path and the workspace path, both absolute. It rewrites the file after the editor saved it, which can conflict with editors; prefer the scripts above. |
| `onSave-wrapper.sh` | Guard that stops `onSave` from running under other formatter extensions. |

The formatters install `shfmt` if it is missing (via `go install`, falling back to the upstream release binary). They need Bash 4 or newer and `curl`.

If you do not want automatic version bumps, skip these tools: format with `shfmt -i 2 -w <file>` and bump `@version` yourself when you change a file.

Editor setup for VS Code: install the "Bash IDE" (`mads-hartmann.bash-ide-vscode`) and "Run On Save" (`emeraldwalk.RunOnSave`) extensions. The workspace tasks in `.vscode/tasks.json` expose "Format Current Bash File", "Quick Format Modified Bash Files" and "Format All Bash Files".
