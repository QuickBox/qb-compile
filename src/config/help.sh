#!/usr/bin/env bash
################################################################################
# @file_name: help
# @version: 1.0.9
# @project_name: qb-compile
# @description: Help configuration file for qb-compile script
#
# @author: Jason Matthews (JMSolo)
# @author_contact: v3.quickbox.io
#
# @save_tasks:
#  automated_versioning: true
#  automated_documentation: true
#
# @build_tasks:
#  automated_comment_strip: true
#  automated_encryption: false
#
# @license: MIT (Included in LICENSE)
# Copyright (C) 2026, QuickBox.IO
# All rights reserved.
################################################################################
# shellcheck disable=SC2154
################################################################################

################################################################################
# @description: Function to display the help message
# @noargs
# @example: qbcompile::help
# @break
################################################################################
qbcompile::help() {
  cat <<EOF
Script Name: ${script_name}
Script Path: ${script_path}
Script Symlink: /usr/local/bin/${script_name}
Version: ${script_version}
Usage: ${script_name} [options]

Compilation Options:
  --boost                        : Compile Boost (useful for compiling other components on older systems)
  --branch [branch_name]         : Specify a custom branch for libtorrent (e.g., fix/curl-socket)
  --cmake                        : Compile CMake (useful for compiling other components on older systems)
  --deluge                       : Compile Deluge (currently a placeholder)
  --gcc                          : Compile GCC (useful for compiling other components on older systems)
  --intel-media-driver           : Compile Intel Media Driver (hardware accel) [DEPRECATED / on-request]
  --python                       : Compile Python 3.11.5 & 3.13.5 and create .deb packages (skips versions native to OS)
  --python-version [version]     : Specify the Python version to use (e.g., 3.9, 3.11) - legacy option
  --python3-libtorrent           : Compile Python3 libtorrent
  --libtorrent                   : Compile libtorrent (for rTorrent)
  --libtorrent-version [version] : Specify a custom libtorrent version (e.g., 0.13.8) instead of latest
  --libtorrent-rasterbar         : Compile libtorrent-rasterbar (required for qBittorrent)
  --rasterbar-version [version]  : Specify a custom libtorrent-rasterbar version (e.g., 2.0.13) instead of the pinned 2.0.14 default
  --qbittorrent                  : Compile qBittorrent (requires libtorrent-rasterbar & Qt6. flags 'libtorrent-rasterbar' & 'qt6' automatically)
  --qt6                          : Compile Qt6 libraries (required for qBittorrent 5.0.0+)
  --rtorrent                     : Compile rTorrent (requires libtorrent)
  --rtorrent-version [version]   : Specify a custom rTorrent version (e.g., 0.9.8) instead of latest
  --transmission                 : Compile Transmission
  --xmlrpc-c                     : Compile xmlrpc-c (required for rTorrent)

General Options:
  -tmp, --temp_dir           : Specify a temporary directory for compilation (default: /opt/qb-compile/builds)
  -i, --install              : Install a compiled package
  -lp, --list-packages       : View compiled .deb and binary files and their MD5 checksums
  -h, --help                 : Display this help message
  -u, --update               : Update the script
  -v, --version              : Get the latest version of the script

Notes:
- This script requires root privileges to run.
- The default compilation directory is /opt/qb-compile/builds.
- If the script finds a previous compilation, it will ask if you want to skip the compilation process for that component.
- The script is designed to be run in a Debian-based environment. (Debian 11 || 12 || 13, Ubuntu 22.04 || 24.04)
- The script will output the MD5 checksums of the compiled binaries and packages.
- The script will create .deb packages for Python, libtorrent-rasterbar, python3-libtorrent, libtorrent, qbittorrent, Qt6, and transmission.
- The script will place the .deb packages in /opt/qb-compile/packaged/<codename>/.
- The script will rename the final binary with version details (e.g., qbittorrent-nox.qbit4.3.7_lt1.2.3.amd64).
- The script will log output to /opt/qb-compile/logs/compilation.log
- The script will exit with an error message if any step fails.

Dependencies:
- build-essential
- autoconf
- autoconf-archive
- cmake
- git
- subversion
- ninja-build
- pkg-config
- patchelf
- zlib1g-dev
- jq
- curl
- dpkg-dev
- debhelper
- fakeroot
- screen
- unzip

Examples:
- Compile Boost                                        : ${script_name} --boost
- Specify Custom Branch for source builds              : ${script_name} --branch 'fix/curl-socket'
- Compile CMake                                        : ${script_name} --cmake
- Compile Deluge                                       : ${script_name} --deluge
- Compile GCC                                          : ${script_name} --gcc
- Compile libtorrent-rasterbar                         : ${script_name} --libtorrent-rasterbar -tmp '/opt/qb-compile/builds'
- Compile libtorrent (for rTorrent)                    : ${script_name} --libtorrent --temp_dir '/opt/qb-compile/builds'
- Compile Python3 libtorrent-rasterbar                 : ${script_name} --python3-libtorrent
- Compile Python 3.11.5 & 3.13.5                       : ${script_name} --python
- Compile qBittorrent                                  : ${script_name} --qbittorrent --temp_dir '/opt/qb-compile/builds'
- Compile rTorrent                                     : ${script_name} --rtorrent
- Compile Qt6                                          : ${script_name} --qt6
- Compile Transmission and libtorrent-rasterbar        : ${script_name} --transmission --libtorrent-rasterbar
- Compile XMLRPC-C (for rTorrent)                      : ${script_name} --xmlrpc-c
- Compile multiple components                          : ${script_name} --qbittorrent --rtorrent --transmission
- Compile Intel Media Driver                           : ${script_name} --intel-media-driver
- View compiled .deb and binary files                  : ${script_name} --list-packages
- Install a compiled package                           : ${script_name} -i

Notes & Extras:
- Python compilation automatically skips versions native to the OS (3.11 on Debian 12, 3.13 on Debian 13)
- You can specify the Python version with the '--python-version' flag. (e.g., ${script_name} --libtorrent-rasterbar --python-version '3.11')
  - This is useful if wanting to compile for a non-default Python version.
- You can specify custom versions for libtorrent and rTorrent with version override flags:
  - ${script_name} --rtorrent --rtorrent-version 0.9.8 --libtorrent-version 0.13.8
  - This is useful for compiling specific stable versions instead of the latest available.
  - You can specify a custom branch for libtorrent with the '--branch' flag. (e.g., ${script_name} --libtorrent-version source --branch 'fix/curl-socket')
- The Boost '--boost' flag will compile Boost libraries that are considered stable, and not too far ahead of apt-get versions.
- CPU headroom: builds never use every core (leave ~25% free by default). Set QBCOMPILE_MAX_JOBS=<n> to pin a hard parallel-job count (e.g. QBCOMPILE_MAX_JOBS=4 on a busy host).

EOF
}
