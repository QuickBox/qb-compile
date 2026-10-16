#!/usr/bin/env bash
################################################################################
# @file_name: essentials
# @version: 1.0.12
# @project_name: qb-compile
# @description: Essential functions for qb-compile
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
# shellcheck disable=SC1091,SC2154
################################################################################

################################################################################
# @description: Function to check for root privileges
# @noargs
# @return: 0 if root, 1 if not
# @example: qbcompile::check::root
# @break
################################################################################
qbcompile::check::root() {
  [[ ${EUID} -ne 0 ]] && { mflibs::shell::text::red "Please run as root." && exit 1; }
}

################################################################################
# @description: Compute a safe parallel-build job count that ALWAYS leaves CPU
#   headroom, so a compilation run never pegs the host at 100%. Build servers
#   are often VMs that share a host with other workloads, and a full-nproc build
#   starves them. Default leaves ~25% of cores free (minimum one core), and
#   never uses every core. Override with QBCOMPILE_MAX_JOBS=<n> for a hard value.
# @noargs
# @output: job count (>=1, < nproc when nproc>1)
# @example: make -j"$(qbcompile::build::jobs)"
# @break
################################################################################
qbcompile::build::jobs() {
  local n j
  n="$(nproc 2>/dev/null)"
  [[ ${n} =~ ^[0-9]+$ && ${n} -ge 1 ]] || n=1
  if [[ ${QBCOMPILE_MAX_JOBS:-} =~ ^[0-9]+$ && ${QBCOMPILE_MAX_JOBS} -ge 1 ]]; then
    j="${QBCOMPILE_MAX_JOBS}"
  else
    # leave ~25% headroom (integer): nproc - ceil(nproc/4)
    j=$(( n - (n + 3) / 4 ))
  fi
  (( j < 1 )) && j=1
  (( n > 1 && j >= n )) && j=$(( n - 1 )) # never claim every core
  printf '%s' "${j}"
}

################################################################################
# @description: Function to detect the OS version
# @noargs
# @output: OS version
# @example: qbcompile::detect::os_version
# @break
################################################################################
qbcompile::detect::os_version() {
  declare -xg distro codename #os_type
  # Detect OS version
  . /etc/os-release
  codename="${VERSION_CODENAME}"
  distro="${ID}"
}

################################################################################
# @description: updates essential libraries
# @noargs
# @output: updates mflibs
# @example: qbcompile::libs::update
# @break
################################################################################
# shellcheck disable=2312
################################################################################
qbcompile::libs::update() {
  echo "Updating essential libraries..."
  [[ -d /opt/mflibs ]] && rm -rf /opt/mflibs
  mflibs_base_path="/opt/mflibs"
  rm -rf "${mflibs_base_path}"
  local tmp_dir
  tmp_dir=$(mktemp -d -t mflibsfetch-XXXXXXXX)
  # Fetch the GitHub archive. Set MFLIBS_REPO (owner/name) and MFLIBS_REF (branch or tag) to use a fork.
  curl -fsSL -o "${tmp_dir}/mflibs_repo.zip" "https://github.com/${MFLIBS_REPO:-QuickBox/mflibs}/archive/${MFLIBS_REF:-main}.zip" || {
    mflibs::shell::text::red "error: unable to download mflibs archive." && exit 1
  }
  # Extract contents (GitHub archives hold a single top-level directory)
  unzip -q "${tmp_dir}/mflibs_repo.zip" -d "${tmp_dir}/unpacked"
  mkdir -p "${mflibs_base_path}"
  if ! cp -rf "${tmp_dir}"/unpacked/*/. "${mflibs_base_path}"; then
    mflibs::shell::text::red "error: unable to copy mflibs files." && exit 1
  fi
  if ! rm -rf "${tmp_dir}"; then
    mflibs::shell::text::yellow "warning: unable to remove temporary mflibs directory: ${tmp_dir}"
  fi
  mkdir -p "/opt/qb-compile/logs/" && mkdir -p "/opt/mflibs/logs/"
  chmod +x "$(find /opt/mflibs/src/ -type f -name "init.sh")" 2>/dev/null
  if [[ -f "/opt/mflibs/src/init.sh" ]]; then
    declare -xg mflibs_log_location="/opt/${script_name}/logs/compilation.log"
    # Create the qbcompile.sh file in the custom directory
    mkdir -p /opt/mflibs/src/custom
    cp -f "/opt/qb-compile/src/config/mflibs/qbcompile.sh" /opt/mflibs/src/custom/qbcompile.sh
    # Source the autocomplete script
    [[ -f "/etc/bash_completion.d/qb-compile" ]] && source "/etc/bash_completion.d/qb-compile"
    chmod +x /opt/mflibs/src/custom/qbcompile.sh
    # Ensure all files are executable
    find /opt/mflibs/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    find /opt/qb-compile/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    . "/opt/mflibs/src/init.sh"
    [[ " ${MFLIBS_LOADED[*]} " =~ verbose ]] && mflibs::import verbose
    mflibs::import shell,status,log,info,qbcompile
    # Create a temporary directory for .deb file storage
    mkdir -p /opt/qb-compile/packaged
    # Create the qbcompile bash_completion file in the /etc/bash_completion.d directory
    cp -f "/opt/qb-compile/src/config/bash_completion.d/qb-compile" /etc/bash_completion.d/qb-compile
  else
    printf -- "%s\n" "error: unable to download libraries" && exit 1
  fi
}

################################################################################
# @description: Function to fix broken dependencies
# @noargs
# @output: Attempts to fix broken dependencies
# @example: fix_broken_install
# @break
################################################################################
fix_broken_install() {
  mflibs::shell::text::red "Unmet dependencies detected. Attempting to fix..."
  mflibs::log "apt-get --fix-broken install -y" || { mflibs::shell::text::red "Failed to fix broken dependencies." && exit 1; }
}

################################################################################
# @description: Function to install required dependencies
# @noargs
# @example: qbcompile::install::dependencies
# @break
################################################################################
qbcompile::install::dependencies() {
  # Ensure the temporary directory exists
  if [[ ! -d ${temp_dir} ]]; then
    mflibs::log "mkdir -p ${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to create temporary directory." && exit 1; }
  fi
  mflibs::shell::text::blue "Installing dependencies..."
  mflibs::log "apt-get update -y" || { mflibs::shell::text::red "Failed to update package lists." && exit 1; }
  # Handle environment-specific logic for `bullseye` and `jammy`
  if [[ ${codename} == "jammy" ]]; then
    #mflibs::shell::text::blue "Adding PPA for libboost-latest on Ubuntu Jammy..."
    #mflibs::log "add-apt-repository ppa:mhier/libboost-latest -y" || { mflibs::shell::text::red "Failed to add PPA for libboost-latest." && exit 1; }
    #mflibs::log "apt-get update -y" || { mflibs::shell::text::red "Failed to update package lists after adding PPA." && exit 1; }
    mflibs::shell::text::blue "Installing additional dependencies for Jammy..."
    mflibs::log "apt-get install -y python3 python3-dev python3-numpy python3-setuptools wget tar" || fix_broken_install
  fi
  if [[ ${codename} == "trixie" ]]; then
    mflibs::shell::text::blue "Installing additional dependencies for Trixie..."
    # Note: python3-numpy is intentionally omitted here. Trixie's NumPy 2.x is
    # incompatible with the Boost.Python numpy extension; b2 auto-skips that
    # extension when the numpy headers are absent, and nothing we ship links it.
    mflibs::log "apt-get install -y extrepo python3 python3-dev python3-setuptools wget tar libboost-all-dev" || fix_broken_install
  fi
  if [[ ${codename} == "bookworm" ]]; then
    mflibs::shell::text::blue "Installing additional dependencies for Bookworm..."
    mflibs::log "apt-get install -y python3 python3-dev python3-numpy python3-setuptools wget tar" || fix_broken_install
  fi
  if [[ ${codename} == "bullseye" ]]; then
    mflibs::shell::text::blue "Installing additional dependencies for Bullseye..."
    mflibs::log "apt-get install -y build-essential g++ python3 python3-dev python3-numpy python3-setuptools wget tar libicu-dev" || fix_broken_install
  fi
  if [[ ${codename} == "noble" ]]; then
    mflibs::shell::text::blue "Installing additional dependencies for Noble..."
    mflibs::log "apt-get install -y python3 python3-dev python3-numpy python3-setuptools wget tar libboost-all-dev" || fix_broken_install
  fi
  # Install essential dependencies
  mflibs::log "apt-get install -y \
  build-essential autoconf autoconf-archive cmake git subversion \
  ninja-build patchelf pkg-config libgl1-mesa-dev libxkbcommon-x11-dev \
  libx11-xcb-dev libssl-dev zlib1g-dev jq curl dpkg-dev debhelper fakeroot screen unzip" || fix_broken_install
  # Install additional dependencies for Qt-based applications (qBittorrent 5.0.0+)
  if [[ ${compile_qbittorrent} == true ]]; then
    # On Debian 11 (bullseye), Qt6 is not available in repos; use custom-compiled version at /usr/local/Qt-*
    if [[ ${codename} != "bullseye" ]]; then
      mflibs::log "apt-get install -y clang qt6-base-dev qt6-tools-dev qt6-l10n-tools qt6-base-dev-tools libqt6svg6-dev" || fix_broken_install
    else
      # For bullseye, only install clang as Qt6 is custom-compiled
      mflibs::log "apt-get install -y clang" || fix_broken_install
    fi
  fi
  # Install additional dependencies for Transmission
  if [[ ${compile_transmission} == true ]]; then
    mflibs::log "apt-get install -y libcurl4-openssl-dev libssl-dev libb64-dev libdeflate-dev libevent-dev libminiupnpc-dev libnatpmp-dev libpsl-dev" || fix_broken_install
  fi
  # Install additional dependencies for xmlrpc-c (required for i8 support)
  if [[ ${compile_xmlrpc} == true ]]; then
    # Install libxml2-dev (required for i8 support)
    mflibs::log "apt-get install -y libxml2-dev" || fix_broken_install
    # Install libcurl with fallback (openssl preferred, gnutls fallback for older distros)
    if apt-cache show libcurl4-openssl-dev >/dev/null 2>&1; then
      mflibs::log "apt-get install -y libcurl4-openssl-dev" || fix_broken_install
    elif apt-cache show libcurl4-gnutls-dev >/dev/null 2>&1; then
      mflibs::shell::text::yellow "libcurl4-openssl-dev not available, using libcurl4-gnutls-dev as fallback"
      mflibs::log "apt-get install -y libcurl4-gnutls-dev" || fix_broken_install
    else
      mflibs::shell::text::red "No libcurl*-dev package available; cannot build xmlrpc-c."
      exit 1
    fi
  fi
  # Install additional dependencies for libtorrent (for rTorrent)
  if [[ ${compile_libtorrent} == true ]]; then
    mflibs::log "apt-get install -y autoconf automake libtool pkg-config libssl-dev libcurl4-openssl-dev libcppunit-dev" || fix_broken_install
  fi
  # Install additional dependencies for rTorrent
  if [[ ${compile_rtorrent} == true ]]; then
    mflibs::log "apt-get install -y libsigc++-2.0-dev libxml2-dev libncurses-dev" || fix_broken_install
  fi
  # Continue attempting to fix broken dependencies until resolved
  if dpkg --audit | grep -q "unmet dependencies"; then
    fix_broken_install
  fi
}

################################################################################
# @description: Function to install curl and OpenSSL 3.x on Debian 11 (bullseye)
# @noargs
# @example: install::dependencies::curl_openssl
# @break
################################################################################
install::dependencies::curl_openssl() {
  mflibs::shell::text::blue "Initiating installation of curl and OpenSSL for Debian 11..."
  # Check if we're running on Debian 11 (bullseye)
  declare -xg codename
  codename=$(lsb_release -sc)
  if [[ "${codename}" != "bullseye" ]]; then
    mflibs::shell::text::red "This function is intended for Debian 11 (bullseye) only."
    exit 1
  fi
  # Update package lists
  mflibs::shell::text::blue "Updating package lists..."
  apt-get update -yqq || { mflibs::shell::text::red "Failed to update package lists." && exit 1; }
  # Install dependencies for curl and OpenSSL
  mflibs::shell::text::blue "Installing required dependencies for curl and OpenSSL..."
  mflibs::log "apt-get install -y libcurl4-openssl-dev build-essential zlib1g-dev" || fix_broken_install
  # Get the latest stable OpenSSL release from GitHub
  mflibs::shell::text::blue "Fetching the latest stable OpenSSL release..."
  latest_openssl_release=$(curl -s https://api.github.com/repos/openssl/openssl/releases | jq -r '.[].tag_name' | grep -E '^openssl-[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE 'alpha|beta|rc' | sort -V | tail -n 1)
  if [[ -z "${latest_openssl_release}" ]]; then
    mflibs::shell::text::red "Failed to fetch the latest stable OpenSSL release."
    exit 1
  fi
  mflibs::shell::text::blue "Downloading OpenSSL ${latest_openssl_release} from GitHub..."
  cd /usr/local/src || { mflibs::shell::text::red "Failed to navigate to /usr/local/src." && exit 1; }
  wget "https://github.com/openssl/openssl/archive/refs/tags/${latest_openssl_release}.tar.gz" -O "openssl-${latest_openssl_release}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download OpenSSL source." && exit 1; }
  mflibs::log "tar -zxf openssl-${latest_openssl_release}.tar.gz" || { mflibs::shell::text::red "Failed to extract OpenSSL source." && exit 1; }
  cd "openssl-openssl-${latest_openssl_release#openssl-}" || { mflibs::shell::text::red "Failed to navigate to OpenSSL source directory." && exit 1; }
  # Configure, build, and install OpenSSL
  mflibs::shell::text::blue "Configuring OpenSSL build..."
  ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure OpenSSL build." && exit 1; }
  # Start background monitoring of compilation status
  mflibs::shell::text::blue "Building OpenSSL version ${latest_openssl_release}..."
  qbcompile::build::status &
  status_pid=$!
  sudo make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to build OpenSSL." && exit 1; }
  # Wait for the background process to finish
  wait "${status_pid}"
  # Install OpenSSL
  mflibs::shell::text::blue "Installing OpenSSL..."
  sudo make install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install OpenSSL." && exit 1; }
  # Update OpenSSL library paths and configure the system to use the new version
  mflibs::shell::text::blue "Updating OpenSSL library paths and configuration..."
  echo "/usr/local/openssl/lib64" | sudo tee /etc/ld.so.conf.d/openssl-3.x.conf >/dev/null
  sudo ldconfig -v 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to update OpenSSL library paths." && exit 1; }
  # Link OpenSSL binary
  mflibs::shell::text::blue "Linking OpenSSL binary..."
  sudo ln -sf /usr/local/openssl/bin/openssl /usr/bin/openssl || { mflibs::shell::text::red "Failed to link OpenSSL binary." && exit 1; }
  # Verify installation
  openssl_version=$(openssl version)
  if [[ "${openssl_version}" == "OpenSSL"* ]]; then
    mflibs::shell::text::green "Successfully installed curl and OpenSSL ${openssl_version} for Debian 11 (bullseye)."
  else
    mflibs::shell::text::red "OpenSSL installation failed. Please check logs."
    exit 1
  fi
  # Navigate back to the temporary directory
  cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to navigate to the temporary directory." && exit 1; }
  # Clean up the OpenSSL source directory
  rm -rf "/usr/local/src/openssl-${latest_openssl_release#openssl-}"
}

################################################################################
# @description: Function to check if a .deb or static binary already exists in
# the storage, and prompt the user whether to recompile or not.
# @param: $1 (file_path) - The path to the .deb or binary file to check.
# @output: Prompts the user for yes/no response. Returns 0 for recompile, 1 for skip.
# @example: qbcompile::check_existing_deb_or_binary "/path/to/deb/or/binary"
################################################################################
qbcompile::check_existing_deb_or_binary() {
  local file_path=$1
  # Trim the file path to display only the file name
  file_name=$(basename "${file_path}")
  mflibs::shell::text::blue "Checking if ${file_name} already exists..."
  # Check if the file already exists
  if [[ -f ${file_path} ]]; then
    mflibs::shell::text::yellow "The file '${file_name}' already exists."
    # Prompt the user if they want to recompile
    while true; do
      read -r -p "Do you want to recompile it? (y/n): " response
      case "${response}" in
      [Yy]*)
        return 0 # Recompile
        ;;
      [Nn]*)
        declare -xgi skip_compilation_processes=1
        mflibs::shell::text::yellow "Skipping compilation per request."
        return 1 # Skip compilation
        ;;
      *)
        mflibs::shell::text::red "Please answer yes or no."
        ;;
      esac
    done
  else
    return 0 # Proceed with compilation if the file doesn't exist
  fi
}

################################################################################
# @description: Updates the APT repository index for a given package directory.
#               Creates both Packages (uncompressed) and Packages.gz for full
#               APT compatibility, along with a Release file.
# @param: $1 (repo_dir) - The path to the package repository directory
# @param: $2 (label) - The package label (e.g., "libboost-dev", "deluge-headless")
# @param: $3 (version) - The package version
# @param: $4 (component) - The component name (e.g., "boost", "deluge")
# @example: qbcompile::update_repo_index "/path/to/repo" "libboost-dev" "1.83.0" "boost"
################################################################################
qbcompile::update_repo_index() {
  local repo_dir="$1"
  local label="$2"
  local version="$3"
  local component="$4"
  if [[ ! -d "${repo_dir}" ]]; then
    mflibs::shell::text::yellow "Repository directory not found: ${repo_dir}; skipping index update"
    return 1
  fi
  # Check if there are any .deb files in the directory
  if ! ls -1 "${repo_dir}/"*.deb >/dev/null 2>&1; then
    mflibs::shell::text::yellow "No .deb files found in ${repo_dir}; skipping index update"
    return 1
  fi
  mflibs::shell::text::blue "Updating package repository index in ${repo_dir}..."
  (
    cd "${repo_dir}" || exit 1
    # Generate both Packages (uncompressed) and Packages.gz for APT compatibility
    dpkg-scanpackages . /dev/null >Packages 2>>"${mflibs_log_location:-/dev/null}" || {
      mflibs::shell::text::red "Failed to create Packages in ${repo_dir}"
      exit 1
    }
    gzip -9c <Packages >Packages.gz 2>>"${mflibs_log_location:-/dev/null}" || true
    # Validate Packages file
    if ! grep -qE '^Size: ' Packages 2>/dev/null; then
      mflibs::shell::text::yellow "Warning: Packages missing Size field for ${repo_dir}"
    fi
    # Create Release file
    cat >Release <<RELEASE
Origin: QuickBox.IO
Label: ${label}
Suite: stable
Codename: ${codename:-$(lsb_release -sc 2>/dev/null || echo unknown)}
Version: ${version}
Date: $(date -R)
Architectures: ${ARCH:-$(dpkg --print-architecture)}
Components: ${component}
Description: ${label} ${version} packaged by QuickBox.IO
RELEASE
  ) || return 1
  mflibs::shell::text::green "Repository index updated: ${repo_dir}/Packages"
  return 0
}

################################################################################
# @description: Refuse to package a staging tree that is missing its primary
# build artifact. A pipe to 'tee' masks a failed configure/build/install exit
# code, so a build that produced no binary/library can still reach dpkg-deb and
# yield an empty, broken .deb. Call this immediately before dpkg-deb --build.
# @param: $1 (package_dir) - staging root that will be handed to dpkg-deb --build
# @param: $2 (label) - human-readable package name for the message
# @param: $@ (patterns) - optional find -name globs for the required artifact
#          (e.g. 'qbittorrent-nox', 'libtorrent-rasterbar.so*'). When one or more
#          are given, at least one non-empty match is required. When none are
#          given, at least one non-empty regular file outside DEBIAN/ is required.
# @return: 0 if the payload holds a real artifact, hard-exits 1 otherwise
# @example: qbcompile::verify::payload "${package_dir}" "qBittorrent" 'qbittorrent-nox'
# @break
################################################################################
qbcompile::verify::payload() {
  local package_dir="$1"
  local label="$2"
  shift 2 || true
  if [[ ! -d "${package_dir}" ]]; then
    mflibs::shell::text::red "${label}: staging directory ${package_dir} is missing; refusing to package."
    exit 1
  fi
  local found=""
  if [[ $# -gt 0 ]]; then
    local pattern
    for pattern in "$@"; do
      found=$(find "${package_dir}" -type f -name "${pattern}" ! -empty -print -quit 2>/dev/null || true)
      [[ -n "${found}" ]] && break
    done
    if [[ -z "${found}" ]]; then
      mflibs::shell::text::red "${label}: primary build artifact not found in payload (expected one of: $*)."
      mflibs::shell::text::red "The build almost certainly failed; refusing to create an empty or broken .deb."
      find "${package_dir}" -maxdepth 4 -type f -printf '  - %P\n' 2>/dev/null | sort | head -n 30 || true
      exit 1
    fi
  else
    found=$(find "${package_dir}" -path "${package_dir}/DEBIAN" -prune -o -type f ! -empty -print -quit 2>/dev/null || true)
    if [[ -z "${found}" ]]; then
      mflibs::shell::text::red "${label}: payload holds no build output outside DEBIAN/; refusing to create an empty .deb."
      exit 1
    fi
  fi
  mflibs::shell::text::green "${label}: payload verified (${found#"${package_dir}/"})."
  return 0
}

################################################################################
# @description: Gate module completion on a fully written, readable .deb. A
# consumer that installs the artifact the moment the module returns can catch it
# mid-write; this flushes the file to stable storage and reads the whole archive
# back, so the module cannot report success on a truncated or still-flushing
# package. Call after dpkg-deb --build succeeds, before the module prints its
# success message or returns.
# @param: $1 (deb_file) - path to the freshly built .deb
# @return: 0 when the .deb exists and its data member decompresses cleanly,
#          hard-exits 1 otherwise
# @example: qbcompile::verify::deb "${boost_deb_file}"
# @break
################################################################################
qbcompile::verify::deb() {
  local deb_file="$1"
  if [[ ! -f "${deb_file}" ]]; then
    mflibs::shell::text::red "Package not found after build: ${deb_file}"
    exit 1
  fi
  # Flush the just-written file to stable storage before any consumer reads it.
  sync "${deb_file}" 2>/dev/null || sync
  # Read the entire archive back; a truncated or still-flushing .deb fails here.
  if ! dpkg-deb --fsys-tarfile "${deb_file}" >/dev/null 2>&1; then
    mflibs::shell::text::red "Package failed integrity read (incomplete or corrupt): ${deb_file}"
    exit 1
  fi
  mflibs::shell::text::green "Package integrity verified: ${deb_file##*/}"
  return 0
}

################################################################################
# @description: Validate Python extension .so files for undefined Boost.Python symbols
# @param: $1 path to .so file
# @return: 0 if no problematic undefined symbols found, 1 otherwise
################################################################################
qbcompile::validate::pyext_symbols() {
  local so_file=$1
  [[ -z ${so_file} ]] && return 0
  mflibs::shell::text::blue "Validating python extension symbols for: ${so_file}"
  # Show the NEEDED entries (SONAMEs) for quick context
  mflibs::shell::text::white::sl "NEEDED libs: "
  readelf -d "${so_file}" 2>/dev/null | awk '/NEEDED/ {print "  - " $0}' || true
  # Check for undefined symbols referencing boost::python (mangled) or boost_python
  # Use nm -D to list dynamic symbols and find undefined entries that reference boost
  local undef
  undef=$(nm -D "${so_file}" 2>/dev/null | awk '/ U / && /boost(::|_python)/ {print $0}' || true)
  if [[ -n "${undef}" ]]; then
    mflibs::shell::text::yellow "Detected undefined Boost-related symbols in ${so_file}:"
    echo "  ${undef//$'\n'/  $'\n'}"
    mflibs::shell::text::blue "Installed libboost_python variants (ldconfig -p):"
    ldconfig -p | grep -E 'libboost_python|libboost_python3' || true
    mflibs::shell::text::red "Boost.Python ABI mismatch or missing symbols detected."
    mflibs::shell::text::yellow "Recommendations:"
    mflibs::shell::text::white::sl "  - Rebuild libtorrent/python bindings on the target distro so they link against the system Boost.Python ABI.\n"
    mflibs::shell::text::white::sl "  - Or ensure the exact libboost_python SONAME present at build time is installed on the host.\n"
    mflibs::shell::text::white::sl "  - Helpful diagnostics: readelf -Ws ${so_file} | grep boost ; nm -D /path/to/libboost_python*.so | grep instance_holder\n"
    return 1
  fi
  mflibs::shell::text::green "No undefined Boost.Python symbols detected in ${so_file}."
  return 0
}

################################################################################
# @description: Function to monitor and display the current dpkg status.
# It tracks CPU, memory usage, and shows live stats during the dpkg process.
# The status updates will remain on a single line, cleared before each update.
# @noargs
# @example: qbcompile::dpkg-deb::status
# @break
################################################################################
qbcompile::dpkg-deb::status() {
  retries=0
  max_retries=5 # Allow up to 5 retries before assuming the build is done
  while true; do
    # Get all active 'dpkg-deb' PIDs
    dpkg_deb_pids=$(pgrep -d ' ' -f 'dpkg-deb' || true)
    if [[ -z "${dpkg_deb_pids}" ]]; then
      retries=$((retries + 1))
      if [[ ${retries} -ge ${max_retries} ]]; then
        # Clear the current line and move cursor to the beginning
        tput cr
        tput el
        # The monitor only observes that dpkg-deb is no longer running; it cannot
        # know the real exit status, so this line makes no success claim. The
        # caller checks PIPESTATUS and prints the actual pass/fail result.
        echo -ne "$(tput setaf 7) ~~!~** Packaging process ended **~!~~ $(tput sgr0)"
        sleep 3
        break
      fi
    else
      retries=0
      cpu_sum=0
      mem_sum=0
      # Loop over each 'dpkg-deb' PID to gather CPU and memory usage
      for pid in ${dpkg_deb_pids}; do
        # Get CPU and memory usage for each 'dpkg-deb' PID
        cpu=$(ps -p "${pid}" -o %cpu= | awk '{sum+=$1} END {print sum}')
        mem=$(ps -p "${pid}" -o rss= | awk '{sum+=$1} END {print sum}')
        cpu_sum=$(awk -v c1="${cpu_sum}" -v c2="${cpu}" 'BEGIN {print c1 + c2}')
        mem_sum=$(awk -v m1="${mem_sum}" -v m2="${mem}" 'BEGIN {print m1 + m2}')
      done
      # Convert memory usage to MB
      mem_sum=$(awk -v mem="${mem_sum}" 'BEGIN {print mem / 1024 "MB"}')
      # Clear the current line and move cursor to the beginning
      tput cr
      tput el
      # Display status on the same line
      echo -ne "$(tput setaf 7)Package installation in progress | CPU:$(tput sgr0) $(tput setaf 6)${cpu_sum}% $(tput setaf 7)| Memory:$(tput sgr0) $(tput setaf 6)${mem_sum}$(tput sgr0)"
    fi
    # Sleep for 2 seconds before the next update
    sleep 2
  done
  # Clear the line after the loop ends
  #tput cr
  #tput el
  echo -ne "\n"
}

################################################################################
# @description: Function to rename the final binary with version details
# @noargs
# @example: qbcompile::rename::binary
# @notes: This function renames the compiled binary based on version and architecture.
# Currently, this function is only used for qBittorrent.
# @break
################################################################################
qbcompile::rename::binary() {
  if [[ ${compile_qbittorrent} == true ]]; then
    local architecture
    architecture=$(dpkg --print-architecture) || { mflibs::shell::text::red "Failed to determine system architecture." && exit 1; }
    mflibs::shell::text::cyan "Architecture: ${architecture}"
    mflibs::shell::text::blue "Renaming qBittorrent binary..."
    # Derive the rasterbar version from the INSTALLED package (what the binary linked against),
    # not the latest-tag lookup, so the name always matches the actual linkage (same source as the deb).
    local linked_rasterbar_version
    linked_rasterbar_version=$(dpkg-query -W -f='${Version}' libtorrent-rasterbar 2>/dev/null | cut -d'-' -f1)
    [[ -z ${linked_rasterbar_version} ]] && { mflibs::shell::text::red "libtorrent-rasterbar not installed; cannot derive linked version." && exit 1; }
    declare -xg new_qbittorrent_binary_name="qbittorrent-nox.${qbittorrent_version}_lt${linked_rasterbar_version}.${architecture}"
    mkdir -p "${deb_storage}/${codename}/static-binary/qbittorrent"
    mv "${temp_dir:-/opt/qb-compile/builds}/qBittorrent-${latest_qbittorrent_tag}/build/qbittorrent-nox" "${deb_storage}/${codename}/static-binary/qbittorrent/${new_qbittorrent_binary_name}" || { mflibs::shell::text::red "Failed to rename qbittorrent binary."; }
    mflibs::shell::text::green "Binary renamed to ${new_qbittorrent_binary_name}"
  fi
}

################################################################################
# @description: Function to perform cleanup of temporary directories
# @noargs
# @example: qbcompile::cleaup::temp
# @break
################################################################################
qbcompile::cleaup::temp() {
  mflibs::shell::text::blue "Cleaning up temporary directories..."
  # cd into the dir being emptied (it survives; only its contents are removed) so
  # the shell is never left in a subdirectory that this deletes.
  cd "${temp_dir:-/opt/qb-compile/builds}" || true
  rm -rf "${temp_dir:-/opt/qb-compile/builds}"/* || { mflibs::shell::text::red "Failed to clean up temporary directories." && exit 1; }
}

################################################################################
# @description: Function to show completion messages
# @noargs
# @example: qbcompile::completion::show
# @notes: This function displays the results of the compilation process.
# @break
################################################################################
qbcompile::completion::show() {
  if [[ ${skip_compilation_processes} -eq 0 ]]; then
    mflibs::shell::text::green "
==============================================================
                Compilation completed!
=============================================================="
  fi
  qbcompile::view::compiled_info
}

################################################################################
# @description: Function to monitor and display the current build status.
# It tracks CPU, memory usage, and shows live stats during the build process.
# The status updates will remain on a single line, cleared before each update.
# @noargs
# @example: qbcompile::build::status
# @break
################################################################################
qbcompile::build::status() {
  retries=0
  max_retries=5 # Allow up to 5 retries before assuming the build is done
  while true; do
    # Get all active 'make', 'cmake', 'cc1plus', or 'ninja' PIDs
    make_pids=$(pgrep -d ' ' -f 'make|cmake|cc1plus|ninja' || true)
    if [[ -z "${make_pids}" ]]; then
      retries=$((retries + 1))
      if [[ ${retries} -ge ${max_retries} ]]; then
        # Clear the current line and move cursor to the beginning
        tput cr
        tput el
        # The monitor only observes that the compiler is no longer running; it
        # cannot know the real exit status, so this line makes no success claim.
        # The caller checks PIPESTATUS and prints the actual pass/fail result.
        echo -ne "$(tput setaf 7) ~~!~** Build process ended **~!~~ $(tput sgr0)"
        sleep 3
        break
      fi
    else
      retries=0
      cpu_sum=0
      mem_sum=0
      # Loop over each 'make' PID to gather CPU and memory usage
      for pid in ${make_pids}; do
        # Get CPU and memory usage for each 'make' PID
        cpu=$(ps -p "${pid}" -o %cpu= | awk '{sum+=$1} END {print sum}')
        mem=$(ps -p "${pid}" -o rss= | awk '{sum+=$1} END {print sum}')
        cpu_sum=$(awk -v c1="${cpu_sum}" -v c2="${cpu}" 'BEGIN {print c1 + c2}')
        mem_sum=$(awk -v m1="${mem_sum}" -v m2="${mem}" 'BEGIN {print m1 + m2}')
      done
      # Convert memory usage to MB
      mem_sum=$(awk -v mem="${mem_sum}" 'BEGIN {print mem / 1024 "MB"}')
      # Clear the current line and move cursor to the beginning
      tput cr
      tput el
      # Display status on the same line
      echo -ne "$(tput setaf 7)Build in progress | CPU:$(tput sgr0) $(tput setaf 6)${cpu_sum}% $(tput setaf 7)| Memory:$(tput sgr0) $(tput setaf 6)${mem_sum}$(tput sgr0)"
    fi
    # Sleep for 2 seconds before the next update
    sleep 2
  done
  # Clear the line after the loop ends
  #tput cr
  #tput el
  echo -ne "\n"
}

################################################################################
# @description: Function to monitor and display the current checkinstall status.
# It tracks CPU, memory usage, and shows live stats during the checkinstall process.
# The status updates will remain on a single line, cleared before each update.
# @noargs
# @example: qbcompile::checkinstall::status
# @break
################################################################################
qbcompile::checkinstall::status() {
  retries=0
  max_retries=5 # Allow up to 5 retries before assuming the build is done
  while true; do
    # Get all active 'checkinstall' PIDs
    checkinstall_pids=$(pgrep -d ' ' -f 'checkinstall' || true)
    if [[ -z "${checkinstall_pids}" ]]; then
      retries=$((retries + 1))
      if [[ ${retries} -ge ${max_retries} ]]; then
        # Clear the current line and move cursor to the beginning
        tput cr
        tput el
        # The monitor only observes that checkinstall is no longer running; it
        # cannot know the real exit status, so this line makes no success claim.
        echo -ne "$(tput setaf 7) ~~!~** Package process ended **~!~~ $(tput sgr0)"
        sleep 3
        break
      fi
    else
      retries=0
      cpu_sum=0
      mem_sum=0
      # Loop over each 'checkinstall' PID to gather CPU and memory usage
      for pid in ${checkinstall_pids}; do
        # Get CPU and memory usage for each 'checkinstall' PID
        cpu=$(ps -p "${pid}" -o %cpu= | awk '{sum+=$1} END {print sum}')
        mem=$(ps -p "${pid}" -o rss= | awk '{sum+=$1} END {print sum}')
        cpu_sum=$(awk -v c1="${cpu_sum}" -v c2="${cpu}" 'BEGIN {print c1 + c2}')
        mem_sum=$(awk -v m1="${mem_sum}" -v m2="${mem}" 'BEGIN {print m1 + m2}')
      done
      # Convert memory usage to MB
      mem_sum=$(awk -v mem="${mem_sum}" 'BEGIN {print mem / 1024 "MB"}')
      # Clear the current line and move cursor to the beginning
      tput cr
      tput el
      # Display status on the same line
      echo -ne "$(tput setaf 7)Package creation in progress | CPU:$(tput sgr0) $(tput setaf 6)${cpu_sum}% $(tput setaf 7)| Memory:$(tput sgr0) $(tput setaf 6)${mem_sum}$(tput sgr0)"
    fi
    # Sleep for 2 seconds before the next update
    sleep 2
  done
  # Clear the line after the loop ends
  #tput cr
  #tput el
  echo -ne "\n"
}
