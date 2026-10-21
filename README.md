# qb-compile

qb-compile is the set of scripts QuickBox uses to build, from source, the `.deb` packages and static binaries that QuickBox installs. The results are published in the public [`QuickBox/compiled-packages`](https://github.com/QuickBox/compiled-packages) repository, organised per distro codename.

It is a single Bash entrypoint (`qb-compile.sh`) that detects the distro, installs the build dependencies for the modules you ask for, compiles them, and packages the result. You can use it to reproduce a published package, to build for a distro we do not publish, or to audit exactly how a package was made.

## Supported systems

| Distro | Codename | Architecture |
|--------|----------|--------------|
| Debian 11 | `bullseye` | amd64 |
| Debian 12 | `bookworm` | amd64 |
| Debian 13 | `trixie` | amd64 |
| Ubuntu 22.04 | `jammy` | amd64 |
| Ubuntu 24.04 | `noble` | amd64 |

The codename is read from `/etc/os-release`. Each module carries its own per-codename handling (toolchain, library names, patches). arm64 is not supported.

## What it builds

| Module | Flag | Output |
|--------|------|--------|
| qBittorrent-nox | `--qbittorrent` | `.deb` and a static binary (builds libtorrent-rasterbar first) |
| Qt6 | `--qt6` | `.deb` (qtbase, qttools, qt5compat, qtsvg, qttranslations) |
| libtorrent-rasterbar | `--libtorrent-rasterbar` | `.deb` |
| Python 3 libtorrent bindings | `--python3-libtorrent` | `.deb` |
| libtorrent (rakshasa) | `--libtorrent` | `.deb` |
| xmlrpc-c | `--xmlrpc-c` | `.deb` |
| rTorrent | `--rtorrent` | `.deb` (builds xmlrpc-c and libtorrent first) |
| Transmission | `--transmission` | `.deb` |
| Deluge (headless) | `--deluge` | `.deb` |
| Python 3.11.5 and 3.13.5 | `--python` | `.deb` pair; skips the version the distro already ships |
| Boost | `--boost` | `.deb` |
| CMake | `--cmake` | `.deb` |
| GCC | `--gcc` | `.deb` (for older distros that need a newer toolchain) |
| Intel Media Driver | `--intel-media-driver` | `.deb`; deprecated, built only when asked for explicitly |

## Requirements

- A clean Debian or Ubuntu system from the table above. Use a disposable VM or container per codename: the build installs many `-dev` packages and several modules install into `/usr/local`.
- Root privileges.
- Network access for source downloads and for `apt`.
- Enough CPU, RAM and disk for the module you build. Qt6 and GCC are the heaviest.
- The tools below are installed automatically when needed: `build-essential`, `autoconf`, `autoconf-archive`, `cmake`, `git`, `subversion`, `ninja-build`, `patchelf`, `pkg-config`, `libssl-dev`, `libx11-xcb-dev`, `zlib1g-dev`, `jq`, `curl`, `dpkg-dev`, `debhelper`, `fakeroot`, `screen`, `unzip`.

qb-compile also needs [`mflibs`](https://github.com/QuickBox/mflibs), the Bash helper library it uses for logging and terminal output. `deploy.sh` installs it to `/opt/mflibs` if it is missing. See [Network access](#network-access).

## Quick start

Download the deploy script, read it, then run it as root:

```bash
curl -fsSL -o /tmp/qb-compile-deploy.sh https://raw.githubusercontent.com/QuickBox/qb-compile/main/deploy.sh
less /tmp/qb-compile-deploy.sh
sudo bash /tmp/qb-compile-deploy.sh
```

This installs qb-compile to `/opt/qb-compile`, installs `mflibs` to `/opt/mflibs` if it is missing, symlinks `/usr/local/bin/qb-compile`, and installs shell completion.

Then build something:

```bash
sudo qb-compile --help
sudo qb-compile --qbittorrent --rasterbar-version 2.0.14
sudo qb-compile --list-packages
```

## Command reference

Compilation options:

| Flag | Meaning |
|------|---------|
| `--boost` | Compile Boost |
| `--cmake` | Compile CMake |
| `--gcc` | Compile GCC |
| `--deluge` | Compile Deluge (headless) |
| `--intel-media-driver` | Compile Intel Media Driver (deprecated, on request only) |
| `--libtorrent` | Compile libtorrent (rakshasa), for rTorrent |
| `--libtorrent-version <version>` | Use this libtorrent version instead of the latest |
| `--libtorrent-rasterbar` | Compile libtorrent-rasterbar |
| `--rasterbar-version <version>` | Use this libtorrent-rasterbar version instead of the pinned default (currently 2.0.14) |
| `--python` | Compile Python 3.11.5 and 3.13.5 (skips versions native to the distro) |
| `--python-version <version>` | Prefer this Python version (legacy option) |
| `--python3-libtorrent` | Compile the Python 3 libtorrent bindings |
| `--qbittorrent` | Compile qBittorrent-nox (also builds libtorrent-rasterbar) |
| `--qt6` | Compile Qt6 (needed by qBittorrent 5.0.0 and newer on Debian 11, which has no Qt6 package) |
| `--rtorrent` | Compile rTorrent (also builds xmlrpc-c and libtorrent) |
| `--rtorrent-version <version>` | Use this rTorrent version instead of the latest |
| `--transmission` | Compile Transmission |
| `--xmlrpc-c` | Compile xmlrpc-c |
| `--branch <name>` | Build libtorrent (rakshasa) from this git branch |
| `--patch` | Apply the epoll file-descriptor race fix to libtorrent (rakshasa) before building it |

General options:

| Flag | Meaning |
|------|---------|
| `-tmp`, `--temp_dir <path>` | Build directory (default `/opt/qb-compile/builds`) |
| `-lp`, `--list-packages` | List built `.deb` and binary files with size and MD5; builds nothing |
| `-i`, `--install` | Pick a built package from a numbered list and install it with `dpkg -i` |
| `-u`, `--update` | Update qb-compile itself |
| `-v`, `--version` | Check the latest qb-compile version and update if a newer one exists |
| `-h`, `--help` | Show help |

Flags can be combined; modules run in a fixed order, not the order you type them:

```bash
sudo qb-compile --qbittorrent --rtorrent --transmission
```

If a matching artifact already exists, the module is skipped. Temporary build directories are cleaned up afterwards.

### Pin stable versions

The newest upstream tag is not always one you can link against.

- qBittorrent links against libtorrent-rasterbar 2.0.x. The newest `2.1.x` tags are upstream's development branch and fail to link. qb-compile pins the 2.0.x default; override it with `--rasterbar-version`.
- For rTorrent, build only versions rakshasa marks stable in the release notes, with matching libtorrent and rTorrent versions:

  ```bash
  sudo qb-compile --rtorrent --rtorrent-version 0.16.11 --libtorrent-version 0.16.11
  ```

- libtorrent 0.16 runs libcurl on its network thread, and the libcurl that Ubuntu 22.04 (7.81.0) and Ubuntu 24.04 (8.5.0) ship makes it abort. On those two releases the 0.16 build links a private static libcurl into `libtorrent.so`, from a signature-verified curl.se release pinned in `qbcompile::get::libcurl_version`. Its symbols stay private, the system `libcurl4` package is left alone, and the libtorrent and rTorrent packages of that pair move to a new build revision together. A new pin raises `libcurl_generation` there, which moves both packages to a new revision again.

### Build parallelism

Every module routes its job count through `qbcompile::build::jobs` in `src/context/essentials.sh`, so a run never uses every core. The default leaves about 25% of cores free (8 cores gives 6 jobs, 16 gives 12). To set a hard value:

```bash
sudo QBCOMPILE_MAX_JOBS=4 qb-compile --qbittorrent
```

## Building a single package

Pass only the module's flag. Dependencies that the module needs are built automatically:

```bash
sudo qb-compile --transmission              # one .deb
sudo qb-compile --rtorrent                  # xmlrpc-c, libtorrent and rTorrent
sudo qb-compile --qbittorrent               # libtorrent-rasterbar and qBittorrent-nox
```

Follow a running build with `screen -r <module>_compile` (for example `screen -r rtorrent_compile`), or read `/opt/qb-compile/logs/`.

## Output layout

```
/opt/qb-compile/packaged/<codename>/
    binary-amd64/<package>/<name>.deb
    static-binary/<category>/<binary>
/opt/qb-compile/logs/*.log
```

`<codename>` is the distro you built on (`bookworm`, `noble`, ...). This is the same layout `compiled-packages` uses per distro.

## Relationship to compiled-packages

[`QuickBox/compiled-packages`](https://github.com/QuickBox/compiled-packages) holds the packages QuickBox publishes and installs, plus `packages.lst`, an index of them. Those packages are produced with the scripts in this repository, run on a clean machine of each target distro. The index is generated from the built `.deb` files rather than edited by hand.

Each `packages.lst` row is `CODENAME CATEGORY PACKAGE VERSION FILENAME MD5`. `CATEGORY` is the `binary-amd64/<category>` directory, `PACKAGE` and `VERSION` come from the `.deb` control file (the Debian build revision is stripped from `VERSION`), and `MD5` is the file checksum. Only `binary-amd64` debs are indexed; static binaries are not.

Maintainers build merged changes on a clean machine of each distro and publish the results to compiled-packages.

## Network access

`deploy.sh`, `--update` and `--version` download qb-compile (and `deploy.sh` also downloads mflibs) straight from GitHub as branch archives, for example `https://github.com/QuickBox/qb-compile/archive/main.zip`. No account, token or key is needed. `--version` reads the version from `qb-compile.sh` on the same branch.

To use a fork, a different branch or a tag, set these variables (as root, for example `sudo QBCOMPILE_REPO=you/qb-compile QBCOMPILE_REF=my-branch qb-compile --update`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `QBCOMPILE_REPO` | `QuickBox/qb-compile` | GitHub repository (`owner/name`) used by `deploy.sh`, `--update` and `--version` |
| `QBCOMPILE_REF` | `main` | Branch or tag of that repository |
| `MFLIBS_REPO` | `QuickBox/mflibs` | GitHub repository for mflibs |
| `MFLIBS_REF` | `main` | Branch or tag of that repository |

Sources for each module are downloaded directly from their upstream projects (GitHub, release tarballs). Version discovery uses the public GitHub API, which is rate-limited for anonymous callers.

## Repository layout

```
qb-compile.sh                      Entrypoint: argument parsing and orchestration
deploy.sh                          Installs qb-compile to /opt/qb-compile
src/
  init.sh                          Base environment and the qbcompile::import loader
  config/
    help.sh                        --help text
    bash_completion.d/qb-compile   Shell completion for all flags
    mflibs/qbcompile.sh            Output helpers loaded into mflibs
  context/
    download.sh                    Download helpers
    essentials.sh                  Root check, OS detection, dependency install, cleanup, build-job cap
    get.sh                         Version discovery
    update.sh                      Self-update
    view.sh                        Artifact listing with sizes and MD5
  modules/<name>/compile-<name>.sh One build module per package
developer_resources/               Maintainer tooling (see its README)
```

## Troubleshooting

- List what has been built: `qb-compile --list-packages`.
- Inspect logs: `ls /opt/qb-compile/logs`, or attach with `screen -r <module>_compile`.
- Broken dependencies: qb-compile runs `apt-get --fix-broken install` when it detects them; fix your apt sources and run it again.
- A build that cannot link libtorrent-rasterbar is usually a 2.1.x tag; pin 2.0.x as described above.

## Community and support

Questions, help and general discussion happen on the [QuickBox Discord](https://discord.gg/mca7RSv5pa). Use GitHub issues for bugs and feature requests so they can be tracked.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE). The software qb-compile builds is distributed under its own upstream licenses.
