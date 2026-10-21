#!/usr/bin/env bash
################################################################################
# <START METADATA>
# @file_name: qb-compile
# @version: 1.2.720
# @project_name: qb-compile
# @brief: This script compiles qbittorrent-nox, Qt6, libtorrent-rasterbar, libtorrent,
# rtorrent, transmission, Python, and deluge from source based on user-defined options.
#
# ```bash
# Compilation Options:
#  --boost                   : Compile Boost (useful for compiling other components on older systems)
#  --deluge                  : Compile Deluge (currently a placeholder)
#  --cmake                   : Compile CMake (useful for compiling other components on older systems)
#  --gcc                     : Compile GCC (useful for compiling other components on older systems)
#  --intel-media-driver      : Compile Intel Media Driver (for hardware acceleration)
#  --libtorrent-rasterbar    : Compile libtorrent-rasterbar (required for qBittorrent)
#  --rasterbar-version       : Specify a custom libtorrent-rasterbar version (e.g., 2.0.13) instead of latest
#  --libtorrent              : Compile libtorrent (for rTorrent)
#  --libtorrent-version      : Specify a custom libtorrent version (e.g., 0.13.8) instead of latest
#  --python                  : Compile Python 3.11.5 & 3.13.5 and create .deb packages (skips native OS versions)
#  --python3-libtorrent      : Compile Python3 libtorrent bindings
#  --qbittorrent             : Compile qBittorrent (requires libtorrent. flags libtorrent-rasterbar automatically)
#  --qt6                     : Compile Qt6 libraries (required for qBittorrent 5.0.0+)
#  --rtorrent                : Compile rTorrent (requires libtorrent)
#  --rtorrent-version        : Specify a custom rTorrent version (e.g., 0.9.8) instead of latest
#  --transmission            : Compile Transmission
#  --xmlrpc-c                : Compile xmlrpc-c (required for rTorrent)
# General Options:
#  -tmp, --temp_dir          : Specify a temporary directory for compilation (default: /opt/qb-compile/builds)
#  -lp, --list-packages      : View compiled .deb and binary files
#  -h, --help                : Display this help message
#  -i, --install             : Install a compiled package from the packaged directory
#  -u, --update              : Update the script
#  -v, --version             : Get the latest version of the script (and update if necessary)
# ```
#
# Notes:
# - This script requires root privileges to run.
# - The compiled binaries will be located in the current directory. (`cd` into the directory where you run this script)
# - The script will output the MD5 checksums of the compiled binaries and packages.
# - The script creates .deb packages for Python, libtorrent-rasterbar, python3-libtorrent, and transmission.
# - The script will rename the final binary with version details.
# - The script will log output to `/opt/qb-compile/logs/compilation.log`
# - The script will exit with an error message if any step fails.
# - The script is designed to be run in a Debian-based environment. (Debian 11, 12, 13, Ubuntu 22.04)
# - When compiling qBittorrent, it will automatically compile libtorrent-rasterbar if not already compiled.
# - When compiling Transmission, it will force the use of Qt5 if the OS is Ubuntu 22.04 (Jammy).
# - Python compilation skips versions native to OS: Python 3.11 on Debian 12, Python 3.13 on Debian 13.
# - The script uses mflibs for logging and status reporting.
# - To install:
# ```bash
# sudo mkdir -p /opt/qb-compile
# sudo git clone https://github.com/QuickBox/qb-compile.git /opt/qb-compile
# sudo chmod +x /opt/qb-compile/qb-compile.sh
# sudo /opt/qb-compile/qb-compile.sh --help
# ```
#
# @save_tasks:
#  automated_versioning: true
#  automated_documentation: true
#
# @build_tasks:
#  automated_comment_strip: true
#  automated_encryption: false
#
# @dependencies:
#  - build-essential
#  - autoconf
#  - autoconf-archive
#  - cmake
#  - git
#  - subversion
#  - ninja-build
#  - patchelf
#  - pkg-config
#  - libboost-dev
#  - libssl-dev
#  - libx11-xcb-dev
#  - zlib1g-dev
#  - jq
#  - curl
#  - dpkg-dev
#  - debhelper
#  - fakeroot
#  - screen
#  - unzip
#
# @authors:
#  Jason Matthews (JMSolo) | Weston Hall (PersonaKlutz)
#
# @license: MIT (Included in LICENSE)
# Copyright (C) 2019-2024, QuickBox.IO
# All rights reserved.
# <END METADATA>
################################################################################
# shellcheck disable=SC1090,SC1091,SC2249,SC2312
################################################################################

################################################################################
# @description: Function to initialize the environment
# @noargs
# @global: script_name
# @return: Imports mflibs and sets up the environment
# @example: qbcompile::environment::init
# @break
# shellcheck disable=SC1091,SC2154
################################################################################
qbcompile::environment::init() {
  if [[ -f "/opt/mflibs/src/init.sh" && -f "/opt/qb-compile/src/init.sh" ]]; then
    mkdir -p "/opt/qb-compile/logs/"
    declare -xg mflibs_log_location="/opt/${script_name}/logs/compilation.log"
    if [[ ! -f /opt/mflibs/src/custom/qbcompile.sh ]]; then
      # Create the qbcompile.sh file in the custom directory
      mkdir -p /opt/mflibs/src/custom
      cp -f "/opt/qb-compile/src/config/mflibs/qbcompile.sh" /opt/mflibs/src/custom/qbcompile.sh
      # Source the autocomplete script
      [[ -f "/etc/bash_completion.d/qb-compile" ]] && source "/etc/bash_completion.d/qb-compile"
      # Ensure qbcompile.sh is executable
      chmod +x /opt/mflibs/src/custom/qbcompile.sh
      chmod +x "$(find /opt/mflibs/src/ -type f -name "init.sh")" 2>/dev/null
      find /opt/mflibs/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    fi
    find /opt/qb-compile/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    . "/opt/mflibs/src/init.sh"
    . "/opt/qb-compile/src/init.sh"
    #. "/opt/qb-compile/src/context/qb-compile-essentials.sh"
    [[ " ${MFLIBS_LOADED[*]} " =~ verbose ]] && mflibs::import verbose
    mflibs::import shell,status,log,info,qbcompile
    qbcompile::import help, \
      download,essentials,get,update,view, \
      compile-boost,compile-cmake,compile-deluge,compile-gcc,compile-intel-media-drivers, \
      compile-libcurl,compile-libtorrent,compile-libtorrent-rasterbar,compile-python, \
      compile-python3-libtorrent,compile-qbittorrent,compile-qt6,compile-rtorrent, \
      compile-transmission,compile-xmlrpc-c
    # Create a temporary directory for .deb file storage
    mkdir -p /opt/qb-compile/packaged/
    # Declare the temporary directory
    declare -xg deb_storage="/opt/qb-compile/packaged"
  else
    qbcompile::libs::update
    [[ ! -f "/opt/mflibs/src/init.sh" ]] && { echo -ne "\033[38;5;203merror\e[0m[1]: mflibs not readable\n" >&2 && exit 1; }
  fi
}

################################################################################
# @description: Function to parse command-line arguments
# @noargs
# @output: Sets global variables based on arguments
# @example: qbcompile::parse_arguments "$@"
# @break
################################################################################
qbcompile::parse_arguments() {
  # Initialize flags
  declare -xg maintainer="JMSolo@quickbox"       # maintainer name
  declare -xg compile_cmake=false                # flag for compiling CMake
  declare -xg compile_gcc=false                  # flag for compiling GCC
  declare -xg compile_intel_media_drivers=false  # flag for compiling Intel Media Driver
  declare -xg install_python=false               # flag for compiling Python
  declare -xg compile_python3_libtorrent=false   # flag for compiling Python3 libtorrent
  declare -xg compile_qt6=false                  # flag for compiling Qt6
  declare -xg compile_qbittorrent=false          # flag for compiling qbittorrent
  declare -xg compile_libtorrent_rasterbar=false # flag for compiling libtorrent-rasterbar
  declare -xg compile_libtorrent=false           # flag for compiling libtorrent
  declare -xg compile_rtorrent=false             # flag for compiling rtorrent
  declare -xg compile_transmission=false         # flag for compiling transmission
  declare -xg compile_xmlrpc=false               # flag for compiling xmlrpc-c
  declare -xg compile_deluge=false               # Placeholder
  declare -xg temp_dir                           # temporary directory for compilation
  declare -xg view_compiled_info=false           # flag for viewing compiled info
  declare -xg skip_checks=false                  # flag for skipping checks
  declare -xgi skip_compilation_processes=0      # flag for skipping compilation processes
  declare -xg custom_rtorrent_version=""         # custom version for rtorrent
  declare -xg custom_libtorrent_version=""       # custom version for libtorrent
  declare -xg custom_libtorrent_rasterbar_version="" # custom version for libtorrent-rasterbar
  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --boost)
      compile_boost=true
      shift
      ;;
    --cmake)
      compile_cmake=true
      shift
      ;;
    --gcc)
      compile_gcc=true
      shift
      ;;
    --intel-media-driver)
      compile_intel_media_drivers=true
      shift
      ;;
    --libtorrent)
      compile_libtorrent=true
      shift
      ;;
    --libtorrent-rasterbar)
      compile_libtorrent_rasterbar=true
      shift
      ;;
    --python)
      install_python=true
      shift
      ;;
    --python-version)
      shift
      declare -xg preferred_python_version="$1"
      shift
      ;;
    --python3-libtorrent)
      compile_python3_libtorrent=true
      shift
      ;;
    --qbittorrent)
      compile_libtorrent_rasterbar=true # libtorrent-rasterbar is a requirement for qbittorrent
      #compile_qt6=true
      compile_qbittorrent=true
      shift
      ;;
    --qt6)
      compile_qt6=true
      shift
      ;;
    --rtorrent)
      compile_xmlrpc=true     # xmlrpc-c is a requirement for rtorrent
      compile_libtorrent=true # libtorrent is a requirement for rtorrent
      compile_rtorrent=true
      shift
      ;;
    --rtorrent-version)
      shift
      custom_rtorrent_version="$1"
      shift
      ;;
    --libtorrent-version)
      shift
      custom_libtorrent_version="$1"
      shift
      ;;
    --rasterbar-version)
      shift
      custom_libtorrent_rasterbar_version="$1"
      shift
      ;;
    --branch)
      shift
      declare -xg preferred_branch="$1"
      shift
      ;;
    --patch)
      declare -xg apply_patch=true
      shift
      ;;
    --transmission)
      #compile_qt6=true
      compile_transmission=true
      shift
      ;;
    --xmlrpc-c)
      compile_xmlrpc=true
      shift
      ;;
    --deluge)
      compile_deluge=true
      shift
      ;;
    -lp | --list-packages)
      skip_checks=true
      view_compiled_info=true
      shift
      ;;
    -tmp | --temp_dir)
      shift
      temp_dir="$1"
      shift
      ;;
    -i | --install)
      packages=("boost" "cmake" "gcc" "libtorrent-rakshasa" "libtorrent-rasterbar" "qbittorrent" "qt6" "rtorrent" "transmission" "xmlrpc-c")
      mflibs::shell::text::blue "Select a package to install by entering its corresponding number:"
      # Display the list of packages with numbering
      for i in "${!packages[@]}"; do
        echo "$((i + 1)). ${packages[${i}]}"
      done
      # Prompt user to select a package by number
      read -rp "$(tput setaf 7)Enter the number of the package to install: $(tput sgr0)" selection
      # Validate selection
      if [[ ! "${selection}" =~ ^[0-9]+$ ]] || ((selection < 1 || selection > ${#packages[@]})); then
        mflibs::shell::text::red "Invalid selection. Please enter a valid number."
        exit 1
      fi
      # Map selection to package name
      package="${packages[$((selection - 1))]}"
      package_path="/opt/qb-compile/packaged/${codename}/binary-amd64/${package}"
      # Define package filename patterns based on selected package
      case "${package}" in
      boost) filename_patterns=("libboost*.deb") ;;
      cmake) filename_patterns=("cmake_*.deb") ;;
      deluge) filename_patterns=("deluge_*.deb") ;;
      gcc) filename_patterns=("gcc_*.deb") ;;
      libtorrent-rakshasa)
        qbcompile::get::libtorrent_version 2>&1
        filename_patterns=("libtorrent${libtorrent_compact_version}_*.deb")
        ;;
      libtorrent-rasterbar)
        # Handle multiple packages for libtorrent-rasterbar
        filename_patterns=("libtorrent-rasterbar_*.deb" "python3-libtorrent_*.deb")
        ;;
      qbittorrent) filename_patterns=("qbittorrent-nox_*.deb") ;;
      qt6) filename_patterns=("libqt6essentials-dev_*.deb") ;;
      rtorrent) filename_patterns=("rtorrent_*.deb") ;;
      transmission) filename_patterns=("transmission_*.deb") ;;
      xmlrpc-c) filename_patterns=("xmlrpc-c_*.deb") ;;
      *)
        mflibs::shell::text::red "Error: Invalid package selected."
        exit 1
        ;;
      esac
      # Find the package files using find for each pattern
      package_files=()
      for pattern in "${filename_patterns[@]}"; do
        while IFS= read -r -d '' file; do
          package_files+=("${file}")
        done < <(find "${package_path}" -type f -name "${pattern}" -print0 2>/dev/null)
      done
      # Check if any package files were found
      if [[ ${#package_files[@]} -eq 0 ]]; then
        mflibs::shell::text::red "Error: ${package} package not found in ${package_path}."
        exit 1
      fi
      # Install the found packages
      mflibs::shell::text::blue "Installing ${package}..."
      for package_file in "${package_files[@]}"; do
        mflibs::log "Installing ${package_file}..."
        dpkg -i --force-overwrite "${package_file}"
      done
      exit 0
      ;;
    -h | --help)
      skip_checks=true
      qbcompile::help
      exit 0
      ;;
    -u | --update)
      qbcompile::update
      if [[ ${qbcompile_version_check} -eq 1 ]]; then
        unset latest_version script_version && return
      else
        exit 0
      fi
      ;;
    -v | --version)
      skip_checks=true
      declare -xgi qbcompile_version_check=1
      qbcompile::get::latest_version
      unset latest_version script_version && exit 0
      ;;
    *)
      exec "${script_dir}/src/config/help.sh"
      exit 1
      ;;
    esac
  done
}

################################################################################
# Main function
################################################################################
qbcompile::main() {
  qbcompile::check::root
  qbcompile::detect::os_version
  qbcompile::parse_arguments "$@"
  [[ ${skip_checks} == false ]] && qbcompile::install::dependencies
  [[ ${compile_boost} == true ]] && qbcompile::compile::boost
  [[ ${compile_cmake} == true ]] && qbcompile::compile::cmake
  [[ ${compile_gcc} == true ]] && qbcompile::compile::gcc
  [[ ${install_python} == true ]] && qbcompile::compile::python
  # If the flag is set, view compiled info
  [[ ${view_compiled_info} == true ]] && qbcompile::view::compiled_info && exit 0
  # Compile selected components
  [[ ${compile_python3_libtorrent} == true ]] && qbcompile::compile::python3_libtorrent
  [[ ${compile_libtorrent_rasterbar} == true ]] && qbcompile::compile::libtorrent_rasterbar
  [[ ${compile_xmlrpc} == true ]] && qbcompile::compile::xmlrpc
  [[ ${compile_libtorrent} == true ]] && qbcompile::compile::libtorrent
  [[ ${compile_rtorrent} == true ]] && qbcompile::compile::rtorrent
  [[ ${compile_qt6} == true ]] && qbcompile::compile::qt6
  [[ ${compile_qbittorrent} == true ]] && qbcompile::compile::qbittorrent
  [[ ${compile_transmission} == true ]] && qbcompile::compile::transmission
  [[ ${compile_deluge} == true ]] && qbcompile::compile::deluge
  [[ ${compile_intel_media_drivers} == true ]] && qbcompile::compile::intel_media_drivers
  qbcompile::rename::binary
  [[ ${skip_compilation_processes} -eq 0 ]] && qbcompile::cleaup::temp
  qbcompile::completion::show
}

################################################################################
# Initialize the environment
################################################################################
qbcompile::environment::init
# Run the main function with provided arguments
qbcompile::main "$@"
################################################################################
