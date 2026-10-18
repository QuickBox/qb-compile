# Contributing to qb-compile

Issues and pull requests are welcome. qb-compile builds the packages published in [`QuickBox/compiled-packages`](https://github.com/QuickBox/compiled-packages), so changes here directly affect what QuickBox users install. Please keep that in mind and test accordingly.

## Reporting bugs and asking for features

Not sure whether it is a bug, or want to talk an idea through first? Ask on the [QuickBox Discord](https://discord.gg/mca7RSv5pa).

Open an issue and include:

- the distro and codename (`cat /etc/os-release`)
- the exact command you ran
- the relevant part of `/opt/qb-compile/logs/` (strip anything private)
- the qb-compile version (`qb-compile --version`)

## Security reports

Do not open a public issue or post in Discord about a security problem. Email echo@quickbox.io with `[Security]` at the start of the subject line, and describe the problem and how to reproduce it. We will reply and coordinate a fix with you.

## Making a change

1. Fork the repository and create a branch.
2. Make the change. Keep it focused; one fix or feature per pull request.
3. Test it on a clean VM or container of each distro the change can affect (`bullseye`, `bookworm`, `trixie`, `jammy`, `noble`). A build that works on your daily-driver machine proves little, because installed development packages can hide missing dependencies. Say in the pull request which distros you tested.
4. Run `bash -n` and `shellcheck` on every script you touched.
5. Open the pull request and describe what changed and why.

Pull requests change the build scripts only. The packages and `packages.lst` in compiled-packages are built and published by QuickBox maintainers from merged changes, so do not open pull requests with built packages.

## Code conventions

- Bash with `set -Eeuo pipefail` discipline, quoted variables (`"${var}"`), and `local` for function variables.
- Functions are namespaced `qbcompile::<context>::<action>`.
- Each script starts with a metadata header (`@file_name`, `@version`, `@description`, `@license`). Bump `@version` when you change a file.
- Make scripts safe to re-run: a second run must not break or duplicate the first.
- Source downloads should come from the upstream project. Prefer pinned, verified versions over "latest" where a newer release is known to break linking.
- Keep comments that explain why the code does something; leave out comments about how you debugged it.

## Adding a module

A module is one directory under `src/modules/` with one script, `compile-<name>.sh`, that defines `qbcompile::compile::<name>`.

1. Copy a small existing module, such as `src/modules/cmake/compile-cmake.sh`, as the starting point.
2. Resolve the version through a `qbcompile::get::<name>_version` function in `src/context/get.sh`.
3. Build into a package directory, write the Debian control file, run `dpkg-deb --build`, and put the result under `${deb_storage}/${codename}/binary-amd64/<name>/`. Skip the build if a matching artifact already exists, using `qbcompile::check_existing_deb_or_binary`.
4. Route parallel jobs through `qbcompile::build::jobs` so a build never uses every core.
5. Wire it up:
   - add a flag to `qbcompile::parse_arguments` and a call in `qbcompile::main` in `qb-compile.sh`
   - add the module to the `qbcompile::import` list in `qb-compile.sh`
   - install its extra build dependencies in `qbcompile::install::dependencies` (`src/context/essentials.sh`)
   - add the flag to the help text (`src/config/help.sh`) and to shell completion (`src/config/bash_completion.d/qb-compile`)
   - document it in the README tables
6. Build it on every supported codename and report the results in your pull request.

## Commits

Use conventional commits: `type(scope): description`, where the type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, or `style`, and the scope is the module or area (for example `fix(rtorrent): ...`). Keep the subject short and use a few plain bullets in the body if more detail helps.

## License

By contributing you agree that your contribution is licensed under the MIT License in [LICENSE](LICENSE).
