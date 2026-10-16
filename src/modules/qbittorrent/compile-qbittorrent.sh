#!/usr/bin/env bash
################################################################################
# @file_name: compile-qbittorrent
# @version: 1.0.6
# @project_name: qb-compile
# @description: Compilation script for qbittorrent-nox for qb-compile
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
# shellcheck disable=SC1090,SC2154
################################################################################

################################################################################
# @description: Function to compile qbittorrent-nox
# @noargs
# @example: qbcompile::compile::qbittorrent
# @break
################################################################################
qbcompile::compile::qbittorrent() {
  declare -xg deb_storage="/opt/qb-compile/packaged"
  declare -xg mflibs_log_location="/opt/qb-compile/logs/qbittorrent_compile.log"
  # Move any existing logs to numbered backups
  if [[ -f "${mflibs_log_location}" ]]; then
    mflibs::shell::text::yellow "Moving existing log file to backup..."
    if [[ ! -f "${mflibs_log_location}.001" ]]; then
      mv "${mflibs_log_location}" "${mflibs_log_location}.001" 2>/dev/null
    else
      for log in "${mflibs_log_location}".{001..500}; do
        [[ -f "${log}" ]] && mv "${log}" "${log%.*}".{001..500} 2>/dev/null
      done
    fi
  fi
  # Create a new log file
  touch "${mflibs_log_location}"
  # Create a screen session for the compilation process log
  sudo screen -dmS qbittorrent_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "qBittorrent compilation log: "
  mflibs::shell::text::cyan "screen -r qbittorrent_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating qBittorrent compilation..."
  cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to the temp directory." && exit 1; }
  # Define storage paths
  declare -xg qbittorrent_deb_storage libtorrent_rasterbar_deb_storage libtorrent_rasterbar_deb_file
  qbittorrent_deb_storage="${deb_storage}/${codename}/binary-amd64/qbittorrent"
  mkdir -p "${qbittorrent_deb_storage}"
  libtorrent_rasterbar_deb_storage="${deb_storage}/${codename}/binary-amd64/libtorrent-rasterbar"
  libtorrent_rasterbar_deb_file="$(find "${libtorrent_rasterbar_deb_storage}" -maxdepth 1 -type f -name "libtorrent-rasterbar*.deb" | head -n 1)"
  # Check for libtorrent-rasterbar .deb file
  [[ ! -f "${libtorrent_rasterbar_deb_file}" ]] && mflibs::shell::text::red "No libtorrent-rasterbar .deb file found. Please compile it first: ${script_name} --libtorrent-rasterbar" && exit 1
  # Check if libtorrent-rasterbar package is installed
  if ! dpkg -l | grep -q "^ii.*libtorrent-rasterbar"; then
    mflibs::shell::text::blue "Installing libtorrent-rasterbar package..."
    qbcompile::verify::deb "${libtorrent_rasterbar_deb_file}"
    dpkg -i "${libtorrent_rasterbar_deb_file}" || { mflibs::shell::text::red "Failed to install libtorrent-rasterbar." && exit 1; }
    sudo ldconfig
  else
    mflibs::shell::text::green "libtorrent-rasterbar is already installed."
  fi
  # Get libtorrent-rasterbar version from the installed package
  mflibs::shell::text::blue "Detecting libtorrent-rasterbar version..."
  libtorrent_version=$(dpkg-query -W -f='${Version}' libtorrent-rasterbar 2>/dev/null)
  if [[ -z "${libtorrent_version}" ]]; then
    mflibs::shell::text::red "ERROR: libtorrent-rasterbar package not found!"
    exit 1
  fi
  mflibs::shell::text::cyan "Detected libtorrent-rasterbar version: ${libtorrent_version}"
  if [[ ${libtorrent_version} == 2.* ]]; then
    # Strip off any `-*build*` suffixes for the build version
    libtorrent_rasterbar_build_version="lt$(echo "${libtorrent_version}" | cut -d'-' -f1)"
  elif [[ ${libtorrent_version} == 1.* ]]; then
    libtorrent_rasterbar_build_version="lt$(echo "${libtorrent_version}" | cut -d'-' -f1)"
  else
    mflibs::shell::text::red "libtorrent-rasterbar version is not 1.x or 2.x: ${libtorrent_version}"
    exit 1
  fi
  # Download qBittorrent tarball
  qbcompile::download::qbittorrent_tarball
  declare -xg qbittorrent_deb_file="${qbittorrent_deb_storage}/qbittorrent-nox_${qbittorrent_version}-${libtorrent_rasterbar_build_version}-1build1_amd64.deb"
  # Qt lockstep: the binary bakes a runpath to the Qt it links, and the manifest's top
  # qt6 row is what installs alongside it. So the INSTALLED libqt6essentials-dev must be
  # the PACKAGED one (same version) before configuring. Gating on "installed at all"
  # left an older Qt from a prior round in place and linked the client against it.
  local qt6_deb_storage qt6_packaged_deb qt6_packaged_version qt6_installed_version
  qt6_deb_storage="${deb_storage}/${codename}/binary-amd64/qt6"
  qt6_packaged_deb="$(find "${qt6_deb_storage}" -maxdepth 1 -type f -name 'libqt6essentials-dev*.deb' 2>/dev/null | sort -V | tail -n 1)"
  if [[ -f "${qt6_packaged_deb}" ]]; then
    qt6_packaged_version="$(dpkg-deb -f "${qt6_packaged_deb}" Version 2>/dev/null)"
    qt6_installed_version="$(dpkg-query -W -f='${Version}' libqt6essentials-dev 2>/dev/null || true)"
    if [[ -n "${qt6_packaged_version}" && "${qt6_packaged_version}" != "${qt6_installed_version}" ]]; then
      mflibs::shell::text::blue "Installing packaged qt6 ${qt6_packaged_version} (installed: ${qt6_installed_version:-none}) for the qBittorrent build..."
      qbcompile::verify::deb "${qt6_packaged_deb}"
      dpkg -i --force-overwrite "${qt6_packaged_deb}" || { mflibs::shell::text::red "Failed to install qt6." && exit 1; }
      sudo ldconfig
    fi
  fi
  declare -xgi skip_compilation_processes=0
  # Find and set Qt6 Config path
  local qt6_config
  # Always prioritize /usr/local first (for custom-compiled Qt6), then fall back to /usr (system Qt6)
  qt6_config=$(find /usr/local -name Qt6Config.cmake 2>/dev/null | head -n 1)
  if [[ -z "${qt6_config}" ]]; then
    qt6_config=$(find /usr -name Qt6Config.cmake 2>/dev/null | head -n 1)
  fi
  # Validate that Qt6Config.cmake was found
  if [[ -z "${qt6_config}" ]]; then
    mflibs::shell::text::red "Qt6Config.cmake not found. Please compile Qt6 first using: ${script_name} --qt6"
    exit 1
  fi
  mflibs::shell::text::blue "Using Qt6 from: ${qt6_config%/*}"
  export DQt6_DIR="${qt6_config%/*}"
  # Begin CMake configuration
  mflibs::shell::text::blue "Configuring qBittorrent build..."
  if [[ "${codename}" == "bullseye" ]]; then
    qbcompile::get::qt_version 2>/dev/null
    # Detect installed custom GCC in /usr/local/gcc-* directories
    local custom_gcc_path
    custom_gcc_path=$(find /usr/local -maxdepth 1 -type d -name 'gcc-*' 2>/dev/null | sort -V | tail -n 1)
    if [[ -n "${custom_gcc_path}" && -x "${custom_gcc_path}/bin/g++" ]]; then
      local gcc_version_detected
      gcc_version_detected=$(basename "${custom_gcc_path}" | sed 's/gcc-//')
      mflibs::shell::text::blue "Using custom GCC ${gcc_version_detected} at ${custom_gcc_path}"
      export CC="${custom_gcc_path}/bin/gcc"
      export CXX="${custom_gcc_path}/bin/g++"
      export GCC_LIB_PATH="${custom_gcc_path}/lib64"
      export LD_LIBRARY_PATH="/usr/local/Qt-${qt_latest_version}/lib:${custom_gcc_path}/lib64:/usr/local/openssl/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
    else
      mflibs::shell::text::yellow "No custom GCC found in /usr/local, using system GCC"
      export CC="/usr/bin/gcc"
      export CXX="/usr/bin/g++"
      export LD_LIBRARY_PATH="/usr/local/Qt-${qt_latest_version}/lib:/usr/local/openssl/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
    fi
    # Define paths
    export QT_PREFIX_PATH="/usr/local/Qt-${qt_latest_version}"
    export Qt6_DIR="${DQt6_DIR}"
    # Set Environment for Boost
    export BOOST_ROOT="/usr/lib/cmake"
    export CXXFLAGS="${CXXFLAGS} -D_GLIBCXX_USE_CXX11_ABI=1"
    export CFLAGS="${CFLAGS} -D_GLIBCXX_USE_CXX11_ABI=1"
    export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}:/usr/lib/cmake:/usr/local/Qt-${qt_latest_version}:/usr/local/Qt-${qt_latest_version}/lib/cmake/Qt6Core5Compat"
    export OPENSSL_ROOT_DIR="/usr/local/openssl"
    # Run configuration
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="${BOOST_ROOT}:/usr/local/Qt-${qt_latest_version}:/usr/local/Qt-${qt_latest_version}/lib/cmake/Qt6Core5Compat" \
      -DQt6_DIR="/usr/local/Qt-${qt_latest_version}/lib/cmake/Qt6" \
      -DOPENSSL_ROOT_DIR="/usr/local/openssl" \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DGUI=OFF \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  else
    # Get the system's multiarch triplet (should already be set from earlier, but ensure it's available)
    TRIPLET="${TRIPLET:-$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)}"
    # Find the actual installed libtorrent-rasterbar library
    LIBTORRENT_LIB="$(find /usr/lib/"${TRIPLET}" -name 'libtorrent-rasterbar.so.*' -type f 2>/dev/null | head -n 1)"
    if [[ -z "${LIBTORRENT_LIB}" ]]; then
      mflibs::shell::text::red "ERROR: No libtorrent-rasterbar library found in /usr/lib/${TRIPLET}"
      mflibs::shell::text::red "Please compile libtorrent-rasterbar first using: ${script_name} --libtorrent-rasterbar"
      exit 1
    fi
    mflibs::shell::text::blue "Found libtorrent-rasterbar library: ${LIBTORRENT_LIB}"
    export CMAKE_PREFIX_PATH="${DQt6_DIR}:/usr/lib/${TRIPLET}/cmake"
    export LD_LIBRARY_PATH="/usr/lib/${TRIPLET}:${LD_LIBRARY_PATH}"
    export PKG_CONFIG_PATH="/usr/lib/${TRIPLET}/pkgconfig:${PKG_CONFIG_PATH}"
    export LDFLAGS="-L/usr/lib/${TRIPLET} -Wl,-rpath,/usr/lib/${TRIPLET}"
    # Force C++11 ABI to match libtorrent-rasterbar
    export CXXFLAGS="${CXXFLAGS} -D_GLIBCXX_USE_CXX11_ABI=1"
    mflibs::shell::text::blue "Configuring qBittorrent with custom libtorrent-rasterbar (using C++11 ABI)..."
    sudo cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DGUI=OFF \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DQt6_DIR="${DQt6_DIR}" \
      -DCMAKE_PREFIX_PATH="${DQt6_DIR}:/usr/lib/${TRIPLET}/cmake" \
      -DCMAKE_LIBRARY_PATH="/usr/lib/${TRIPLET}" \
      -DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1" \
      -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib/${TRIPLET} -Wl,-rpath,/usr/lib/${TRIPLET}" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L/usr/lib/${TRIPLET} -Wl,-rpath,/usr/lib/${TRIPLET}" \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  fi
  [[ ${cfg_rc:-1} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure qBittorrent with cmake." && exit 1; }
  # Compile qBittorrent
  mflibs::shell::text::blue "Building qbittorrent-nox version ${qbittorrent_version}..."
  qbcompile::build::status &
  status_pid=$!
  sudo cmake --build build --target install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to compile qBittorrent." && exit 1; }
  # Package setup for Debian
  package_dir="${temp_dir:-/opt/qb-compile/builds}/qbittorrent-package"
  mkdir -p "${package_dir}/DEBIAN" "${package_dir}"
  # Install built files to package directory
  sudo DESTDIR="${package_dir}" cmake --install build 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install qBittorrent." && exit 1; }
  # Calculate Installed Size in KB (integer only)
  installed_size=$(du -sk "${package_dir}" | awk '{print $1}')
  # Create control file for .deb package
  cat <<EOF | sudo tee "${package_dir}/DEBIAN/control" >/dev/null
Package: qbittorrent-nox
Version: ${qbittorrent_version}-${libtorrent_rasterbar_build_version}build1
Section: net
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: qbittorrent-nox - BitTorrent client without GUI. Compiled to work with libtorrent-rasterbar ${libtorrent_rasterbar_build_version}.
Depends: libtorrent-rasterbar
Installed-Size: ${installed_size}
EOF
  # Build .deb package
  qbcompile::verify::payload "${package_dir}" "qBittorrent" "qbittorrent-nox"
  mflibs::shell::text::blue "Creating .deb package for qBittorrent..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${package_dir}" "${qbittorrent_deb_file}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create .deb package for qBittorrent." && exit 1; }
  qbcompile::verify::deb "${qbittorrent_deb_file}"
  # Log MD5 checksum of the package
  if [[ -f "${qbittorrent_deb_file}" ]]; then
    declare -xg qbittorrent_deb_md5_hash
    qbittorrent_deb_md5_hash=$(md5sum "${qbittorrent_deb_file}" | awk '{ print $1 }')
    mflibs::shell::text::green "MD5 checksum of the created package: ${qbittorrent_deb_md5_hash}"
  else
    mflibs::shell::text::red "No .deb file found for qBittorrent." && exit 1
  fi
  # Update local package repository index
  qbcompile::update_repo_index "${qbittorrent_deb_storage}" "qbittorrent-nox" "${qbittorrent_version}" "qbittorrent"
  # Cleanup package directory
  sudo rm -rf "${package_dir}"
  # The build path must produce the package; a module that ends without it is an
  # error, not a silent success.
  if [[ ! -f "${qbittorrent_deb_file}" ]]; then
    mflibs::shell::text::red "qBittorrent build produced no package: ${qbittorrent_deb_file}" && exit 1
  fi
  cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to the temp directory." && exit 1; }
  # Close the screen session
  screen -S qbittorrent_compile -X quit >/dev/null
}
