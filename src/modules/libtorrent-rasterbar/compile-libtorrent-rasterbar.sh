#!/usr/bin/env bash
################################################################################
# @file_name: compile-libtorrent-rasterbar
# @version: 1.0.8
# @project_name: qb-compile
# @description: Compilation script for libtorrent-rasterbar for qb-compile
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
# @description: Function to compile libtorrent-rasterbar and create a .deb package
# @noargs
# @example: qbcompile::compile::libtorrent_rasterbar
# @break
################################################################################
qbcompile::compile::libtorrent_rasterbar() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/libtorrent-rasterbar_compile.log"
  # Rotate logs
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
  : >"${mflibs_log_location}"
  # Tail
  sudo screen -dmS libtorrent_rasterbar_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "libtorrent-rasterbar compilation log: "
  mflibs::shell::text::cyan "screen -r libtorrent_rasterbar_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating libtorrent-rasterbar compilation..."
  # Storage
  declare -xg libtorrent_rasterbar_deb_storage
  libtorrent_rasterbar_deb_storage="${deb_storage}/${codename}/binary-amd64/libtorrent-rasterbar"
  mkdir -p "${libtorrent_rasterbar_deb_storage}"
  qbcompile::get::libtorrent_rasterbar_version
  if [[ -z "${libtorrent_rasterbar_version:-}" ]]; then
    mflibs::shell::text::red "Failed to determine libtorrent-rasterbar version."
    screen -S libtorrent_rasterbar_compile -X quit >/dev/null
    return 1
  fi
  # Artifact
  declare -xg libtorrent_rasterbar_deb_file
  libtorrent_rasterbar_deb_file="${libtorrent_rasterbar_deb_storage}/libtorrent-rasterbar_${libtorrent_rasterbar_version}-1build1_amd64.deb"
  # Building rasterbar does NOT install it, but the downstream modules require it
  # installed: qt6 gates on `dpkg-query -W libtorrent-rasterbar` and qBittorrent
  # links it. A pinned --rasterbar-version must land the PINNED version, so dpkg -i
  # replaces any other version already present. Used on both the skip and the build
  # paths so the dep is guaranteed installed before qt6/qBittorrent run.
  _install_rasterbar_deb() {
    [[ -f "${libtorrent_rasterbar_deb_file}" ]] || return 0
    qbcompile::verify::deb "${libtorrent_rasterbar_deb_file}"
    mflibs::shell::text::blue "Installing libtorrent-rasterbar ${libtorrent_rasterbar_version} system-wide..."
    dpkg -i "${libtorrent_rasterbar_deb_file}" || { mflibs::shell::text::red "Failed to install libtorrent-rasterbar." && exit 1; }
  }
  if ! qbcompile::check_existing_deb_or_binary "${libtorrent_rasterbar_deb_file}"; then
    _install_rasterbar_deb
    screen -S libtorrent_rasterbar_compile -X quit >/dev/null
    return 0
  fi
  # Dirs
  BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
  SRC_DIR="${BUILD_ROOT}/libtorrent"
  BUILD_DIR="${SRC_DIR}/build"
  package_dir="${BUILD_ROOT}/libtorrent-rasterbar-package"
  ARCH="$(dpkg --print-architecture)"
  TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
  mkdir -p "${BUILD_ROOT}"
  # A preceding module may have left the shell's CWD inside one of the dirs about
  # to be removed; move to a dir that will still exist so the rm does not delete
  # the working directory out from under the later clone/build.
  cd "${BUILD_ROOT}" || { mflibs::shell::text::red "Failed to enter ${BUILD_ROOT}" && exit 1; }
  rm -rf "${SRC_DIR}" "${BUILD_DIR}" "${package_dir}"
  mkdir -p "${package_dir}/DEBIAN"
  # Legacy tuning for bullseye
  if [[ "${codename}" == "bullseye" ]]; then
    qbcompile::get::gcc_version 2>/dev/null
    export LDFLAGS="-L/usr/local/gcc-${gcc_version}/lib64 -latomic"
    export CXXFLAGS="-L/usr/local/gcc-${gcc_version}/lib64 -latomic"
    export LD_LIBRARY_PATH="/usr/local/gcc-${gcc_version}/lib64:/usr/local/openssl/lib64:${LD_LIBRARY_PATH:-}"
    export PATH="/usr/local/gcc-${gcc_version}/bin:/usr/local/openssl/bin:${PATH}"
  fi
  export BOOST_ROOT="/usr"
  # Clone
  mflibs::shell::text::blue "Cloning libtorrent-rasterbar repository..."
  git clone --recurse-submodules https://github.com/arvidn/libtorrent.git "${SRC_DIR}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to clone libtorrent repository."
    exit 1
  fi
  cd "${SRC_DIR}" || {
    mflibs::shell::text::red "Failed to enter libtorrent directory: ${SRC_DIR}"
    exit 1
  }
  mflibs::shell::text::blue "Checking out libtorrent-rasterbar version ${libtorrent_rasterbar_version}..."
  git checkout -f "v${libtorrent_rasterbar_version}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to checkout v${libtorrent_rasterbar_version}"
    exit 1
  fi
  # Configure
  mflibs::shell::text::blue "Configuring libtorrent-rasterbar..."
  if [[ "${codename}" == "bullseye" ]]; then
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DBOOST_ROOT="/usr" \
      -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR:-/usr}" \
      -DCMAKE_CXX_FLAGS="-L/usr/local/gcc-${gcc_version}/lib64 -latomic -D_GLIBCXX_USE_CXX11_ABI=1" \
      -DCMAKE_EXE_LINKER_FLAGS="-L/usr/local/gcc-${gcc_version}/lib64 -Wl,-Bstatic -latomic -Wl,-Bdynamic" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L/usr/local/gcc-${gcc_version}/lib64 -Wl,-Bstatic -latomic -Wl,-Bdynamic" \
      -Dbuild_tests=OFF \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  elif [[ "${codename}" == "bookworm" || "${codename}" == "jammy" ]]; then
    # Debian 12 / Ubuntu 22.04: explicit Boost paths to avoid 1.74/1.83 cmake ambiguity,
    # CXX11 ABI for consistency with qBittorrent build, -O2 to avoid GCC 12 -O3 codegen issues
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=OFF \
      -DBoost_INCLUDE_DIR=/usr/include \
      -DBoost_LIBRARY_DIRS="/usr/lib/${TRIPLET}" \
      -DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1 -O2" \
      -Dbuild_tests=OFF \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  elif [[ "${codename}" == "trixie" ]]; then
    # Debian 13 (Trixie) with CMake 3.31+ requires explicit Boost hints due to deprecated FindBoost
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=OFF \
      -DCMAKE_POLICY_CMP0167=NEW \
      -DBoost_INCLUDE_DIR=/usr/include \
      -DBoost_LIBRARY_DIRS="/usr/lib/${TRIPLET}" \
      -Dbuild_tests=OFF \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  else
    # Fallback for other distros
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DBOOST_ROOT="/usr" \
      -Dbuild_tests=OFF \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  fi
  [[ ${cfg_rc:-1} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure libtorrent-rasterbar." && exit 1; }
  # Build
  mflibs::shell::text::blue "Building libtorrent-rasterbar..."
  qbcompile::build::status &
  status_pid=$!
  jobs="$(qbcompile::build::jobs)"
  ((jobs < 1)) && jobs=1
  cmake --build "${BUILD_DIR}" -- -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to compile libtorrent-rasterbar." && exit 1; }
  # Install into package root
  mflibs::shell::text::blue "Installing files into package directory..."
  sudo DESTDIR="${package_dir}" cmake --install "${BUILD_DIR}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install libtorrent-rasterbar." && exit 1; }
  # Verify shared lib presence
  shopt -s nullglob
  so_candidates=("${package_dir}/usr/lib/${TRIPLET}"/libtorrent-rasterbar.so*)
  shopt -u nullglob
  if [[ ${#so_candidates[@]} -eq 0 ]]; then
    mflibs::shell::text::red "Did not find libtorrent-rasterbar.so* under ${package_dir}/usr/lib/${TRIPLET}"
    find "${package_dir}/usr" -maxdepth 3 -type f -printf '%P\n' 2>/dev/null | sort | sed 's/^/  - /' || true
    exit 1
  fi
  # Move pkg-config if needed
  if [[ -f "${package_dir}/usr/lib/pkgconfig/libtorrent-rasterbar.pc" ]]; then
    mkdir -p "${package_dir}/usr/lib/${TRIPLET}/pkgconfig"
    mv "${package_dir}/usr/lib/pkgconfig/libtorrent-rasterbar.pc" "${package_dir}/usr/lib/${TRIPLET}/pkgconfig/" || true
  fi
  # Control file – runtime deps
  # Boost is header-only for libtorrent (confirmed: ldd shows no boost .so linkage)
  case "${codename}" in
  bullseye)
    ssl_dep="libssl1.1"
    ;;
  jammy | bookworm)
    ssl_dep="libssl3"
    ;;
  trixie)
    ssl_dep="libssl3t64"
    ;;
  *)
    ssl_dep="libssl3"
    ;;
  esac
  installed_size=$(du -sk "${package_dir}" | awk '{print $1}')
  cat <<EOF | sudo tee "${package_dir}/DEBIAN/control" >/dev/null
Package: libtorrent-rasterbar
Version: ${libtorrent_rasterbar_version}-1build1
Section: libs
Priority: optional
Architecture: ${ARCH}
Maintainer: ${maintainer}
Depends: libc6, libstdc++6, ${ssl_dep}
Description: libtorrent-rasterbar - BitTorrent library (shared library)
Installed-Size: ${installed_size}
EOF
  # Build .deb
  qbcompile::verify::payload "${package_dir}" "libtorrent-rasterbar" "libtorrent-rasterbar.so*"
  mflibs::shell::text::blue "Creating .deb package for libtorrent-rasterbar..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${package_dir}" "${libtorrent_rasterbar_deb_file}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create .deb package." && exit 1; }
  if [[ -f "${libtorrent_rasterbar_deb_file}" ]]; then
    declare -xg libtorrent_rasterbar_md5_hash
    libtorrent_rasterbar_md5_hash=$(md5sum "${libtorrent_rasterbar_deb_file}" | awk '{ print $1 }')
    mflibs::shell::text::green "MD5 checksum of the created package: ${libtorrent_rasterbar_md5_hash}"
  else
    mflibs::shell::text::red "No .deb file found."
    exit 1
  fi
  _install_rasterbar_deb
  # Update local package repository index
  qbcompile::update_repo_index "${libtorrent_rasterbar_deb_storage}" "libtorrent-rasterbar" "${libtorrent_rasterbar_version}" "libtorrent-rasterbar"
  screen -S libtorrent_rasterbar_compile -X quit >/dev/null
}
