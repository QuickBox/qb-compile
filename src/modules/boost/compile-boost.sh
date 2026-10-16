#!/usr/bin/env bash
################################################################################
# @file_name: compile-boost
# @version: 1.0.9
# @project_name: qb-compile
# @description: Compile Boost from source and create a .deb package
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
# @description: Function to compile Boost from source and create a .deb package
# @noargs
# @example: qbcompile::compile::boost
# @break
################################################################################
qbcompile::compile::boost() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/boost_compile.log"
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
  # Live-tail
  sudo screen -dmS boost_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "Boost compilation log: "
  mflibs::shell::text::cyan "screen -r boost_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating boost compilation..."
  # Versions / names (keep consistent as 1.83.0)
  boost_ver="1.83.0"
  boost_dir="boost_1_83_0"
  boost_tar="boost_1_83_0.tar.gz"
  # Storage for the final package
  declare -xg boost_deb_storage
  boost_deb_storage="${deb_storage}/${codename}/binary-amd64/boost"
  mkdir -p "${boost_deb_storage}"
  declare -xg boost_deb_file
  boost_deb_file="${boost_deb_storage}/libboost-dev_${boost_ver}-1build1_amd64.deb"

  # Skip if present and user opts not to rebuild (preserves your prompt behavior)
  if ! qbcompile::check_existing_deb_or_binary "${boost_deb_file}"; then
    screen -S boost_compile -X quit >/dev/null
    return 0
  fi
  # Dirs
  BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
  mkdir -p "${BUILD_ROOT}"
  cd "${BUILD_ROOT}" || {
    mflibs::shell::text::red "Failed to enter ${BUILD_ROOT}"
    exit 1
  }
  rm -rf "${boost_dir}" "${boost_tar}" boost-package
  mflibs::shell::text::blue "Resolving Boost ${boost_ver} source tarball..."
  # ---------------------------------------------------------------------------
  # Download resolution (robust, offline-friendly)
  # Priority:
  #  1) BOOST_TARBALL_FILE (absolute path to tar.gz)
  #  2) Cached file in ${download_dir:-/opt/qb-compile/downloads}
  #  3) Common local paths: /usr/src, /usr/local/src
  #  4) BOOST_TARBALL_URL (explicit URL)
  #  5) Known mirrors (archives, jfrog) via wget, then curl -4 fallback
  # ---------------------------------------------------------------------------
  CACHE_DIR="${download_dir:-/opt/qb-compile/downloads}"
  mkdir -p "${CACHE_DIR}"
  # helper: validate tar.gz is actually a gzip tar
  _qb_validate_tar() {
    tar -tzf "$1" >/dev/null 2>&1
  }
  got_tar=0
  # 1) BOOST_TARBALL_FILE
  if [[ -n "${BOOST_TARBALL_FILE:-}" && -f "${BOOST_TARBALL_FILE}" ]]; then
    mflibs::shell::text::blue "Using BOOST_TARBALL_FILE: ${BOOST_TARBALL_FILE}"
    if _qb_validate_tar "${BOOST_TARBALL_FILE}"; then
      cp -f "${BOOST_TARBALL_FILE}" "${boost_tar}"
      got_tar=1
    else
      mflibs::shell::text::yellow "Provided BOOST_TARBALL_FILE failed tar test; ignoring."
    fi
  fi
  # 2) Cache
  if [[ ${got_tar} -eq 0 && -f "${CACHE_DIR}/${boost_tar}" ]]; then
    mflibs::shell::text::blue "Using cached tarball: ${CACHE_DIR}/${boost_tar}"
    if _qb_validate_tar "${CACHE_DIR}/${boost_tar}"; then
      cp -f "${CACHE_DIR}/${boost_tar}" "${boost_tar}"
      got_tar=1
    else
      mflibs::shell::text::yellow "Cached tarball failed tar test; removing."
      rm -f "${CACHE_DIR}/${boost_tar}"
    fi
  fi
  # 3) Common local paths
  if [[ ${got_tar} -eq 0 ]]; then
    for local_path in "/usr/src/${boost_tar}" "/usr/local/src/${boost_tar}"; do
      if [[ -f "${local_path}" ]]; then
        mflibs::shell::text::blue "Found local tarball: ${local_path}"
        if _qb_validate_tar "${local_path}"; then
          cp -f "${local_path}" "${boost_tar}"
          got_tar=1
          break
        else
          mflibs::shell::text::yellow "Local tarball failed tar test; ignoring: ${local_path}"
        fi
      fi
    done
  fi
  # 4) BOOST_TARBALL_URL
  if [[ ${got_tar} -eq 0 && -n "${BOOST_TARBALL_URL:-}" ]]; then
    mflibs::shell::text::blue "Downloading via BOOST_TARBALL_URL: ${BOOST_TARBALL_URL}"
    # Try wget first, then curl with retries. Silence output to log file instead.
    wget -q -O "${boost_tar}" "${BOOST_TARBALL_URL}" >/dev/null 2>&1 || true
    if [[ ! -s "${boost_tar}" ]]; then
      curl -fL --retry 3 -o "${boost_tar}" "${BOOST_TARBALL_URL}" >/dev/null 2>&1 || true
    fi
    if [[ -s "${boost_tar}" ]]; then
      if _qb_validate_tar "${boost_tar}"; then
        cp -f "${boost_tar}" "${CACHE_DIR}/${boost_tar}" 2>/dev/null || true
        got_tar=1
      else
        rm -f "${boost_tar}"
        mflibs::shell::text::yellow "BOOST_TARBALL_URL did not yield a valid archive."
      fi
    else
      rm -f "${boost_tar}"
      mflibs::shell::text::yellow "BOOST_TARBALL_URL did not yield a valid archive."
    fi
  fi
  # 5) Known mirrors
  if [[ ${got_tar} -eq 0 ]]; then
    mflibs::shell::text::blue "Downloading Boost ${boost_ver}..."
    urls=(
      "https://archives.boost.io/release/${boost_ver}/source/${boost_tar}"
      "https://boostorg.jfrog.io/artifactory/main/release/${boost_ver}/source/${boost_tar}"
    )
    for u in "${urls[@]}"; do
      # Try wget first
      wget -q -O "${boost_tar}" "${u}" >/dev/null 2>&1 || true
      # If wget didn't produce a file, try curl (may prefer IPv6), then curl -4
      if [[ ! -s "${boost_tar}" ]]; then
        curl -fL --retry 3 -o "${boost_tar}" "${u}" >/dev/null 2>&1 || true
      fi
      if [[ ! -s "${boost_tar}" ]]; then
        curl -4 -fL --retry 3 -o "${boost_tar}" "${u}" >/dev/null 2>&1 || true
      fi
      if [[ -s "${boost_tar}" ]] && _qb_validate_tar "${boost_tar}"; then
        mflibs::shell::text::green "Downloaded Boost tarball from: ${u}"
        cp -f "${boost_tar}" "${CACHE_DIR}/${boost_tar}" 2>/dev/null || true
        got_tar=1
        break
      else
        rm -f "${boost_tar}"
        mflibs::shell::text::yellow "No valid content from ${u}; trying next mirror..."
      fi
    done
  fi
  if [[ ${got_tar} -ne 1 ]]; then
    mflibs::shell::text::red "Failed to acquire Boost ${boost_ver} source tarball."
    mflibs::shell::text::yellow "Options:"
    mflibs::shell::text::yellow "  - Place ${boost_tar} in ${CACHE_DIR} and rerun"
    mflibs::shell::text::yellow "  - Set BOOST_TARBALL_FILE=/path/to/${boost_tar}"
    mflibs::shell::text::yellow "  - Set BOOST_TARBALL_URL=https://your.mirror/${boost_tar}"
    exit 1
  fi
  # Extract
  mflibs::shell::text::blue "Extracting Boost..."
  if ! tar -xzf "${boost_tar}"; then
    mflibs::shell::text::red "Failed to extract Boost."
    file "${boost_tar}" || true
    ls -lh "${boost_tar}" || true
    exit 1
  fi
  cd "${boost_dir}" || {
    mflibs::shell::text::red "Failed to change directory to ${boost_dir}."
    exit 1
  }
  # Python selection (Debian 12 -> 3.11, jammy -> 3.10, bullseye -> 3.9), allows override
  if [[ -n "${preferred_python_version:-}" ]]; then
    preferred_python="$(command -v "python${preferred_python_version}" || true)"
    if [[ -z "${preferred_python}" ]]; then
      mflibs::shell::text::red "Error: Python version ${preferred_python_version} not found."
      exit 1
    fi
  else
    case "${codename:-}" in
    bullseye) preferred_python="/usr/bin/python3.9" ;;
    jammy) preferred_python="/usr/bin/python3.10" ;;
    bookworm) preferred_python="/usr/bin/python3.11" ;;
    *) preferred_python="/usr/bin/python3" ;;
    esac
    [[ -x "${preferred_python}" ]] || preferred_python="/usr/bin/python3"
    mflibs::shell::text::yellow "No Python version specified. Defaulting to ${preferred_python}."
  fi
  # Bootstrap with specific libs; we need python library for libtorrent bindings
  mflibs::shell::text::blue "Bootstrapping Boost build..."
  ./bootstrap.sh --with-libraries=headers,python,system,chrono,random --with-python="${preferred_python}" \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to bootstrap Boost."
    exit 1
  fi
  # Build + staged install to package_dir
  qbcompile::get::gcc_version 2>/dev/null || true
  package_dir="${BUILD_ROOT}/boost-package"
  mkdir -p "${package_dir}/DEBIAN" "${package_dir}/usr"
  mflibs::shell::text::blue "Building & installing Boost into package dir..."
  jobs="$(qbcompile::build::jobs)"
  ((jobs < 1)) && jobs=1
  # Determine the multiarch library path (e.g., x86_64-linux-gnu)
  MULTIARCH_TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo 'x86_64-linux-gnu')"
  ./b2 install \
    --prefix="${package_dir}/usr" \
    --libdir="${package_dir}/usr/lib/${MULTIARCH_TRIPLET}" \
    --with-python \
    --with-headers \
    --with-system \
    --with-chrono \
    --with-random \
    threading=multi \
    link=shared \
    cxxflags="-std=c++17 ${gcc_version:+-I/usr/local/gcc-${gcc_version}/include}" \
    -j"${jobs}" \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to install Boost."
    exit 1
  fi
  # Quick sanity: show where python and system libs landed
  mflibs::shell::text::blue "Verifying installed Boost libraries..."
  find "${package_dir}/usr/lib" -maxdepth 3 -type f -name "libboost_*.so*" -printf "  - %P\n" 2>/dev/null | sort || true
  if ! find "${package_dir}/usr/lib" -type f -name "libboost_python*.so*" -print -quit 2>/dev/null | grep -q .; then
    mflibs::shell::text::yellow "Warning: libboost_python*.so not found under ${package_dir}/usr/lib — ensure python component built."
  else
    mflibs::shell::text::green "Found Boost.Python library in multiarch path."
  fi
  # Calculate Installed Size in KB (integer only)
  installed_size=$(du -sk "${package_dir}" | awk '{print $1}')
  # Control file for dpkg-deb (dev-style metapackage for your stack)
  # Add Replaces/Conflicts to ensure we override system boost packages
  cat <<EOF | sudo tee "${package_dir}/DEBIAN/control" >/dev/null
Package: libboost-dev
Version: ${boost_ver}-1build1
Section: libs
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: Boost C++ Libraries ${boost_ver} with Python, System, Chrono, and Random
 Custom compiled Boost libraries for QuickBox compatibility.
 Includes Boost.Python, System, Chrono, and Random components.
Depends: python3, python3-dev
Replaces: libboost-python1.74.0, libboost-python1.81.0, libboost-python1.83.0, libboost-system1.74.0, libboost-system1.81.0, libboost-chrono1.74.0, libboost-chrono1.81.0, libboost-random1.74.0, libboost-random1.81.0
Provides: libboost-python1.74.0, libboost-python1.81.0, libboost-python1.83.0, libboost-system1.74.0, libboost-system1.81.0, libboost-system1.83.0, libboost-chrono1.74.0, libboost-chrono1.81.0, libboost-chrono1.83.0, libboost-random1.74.0, libboost-random1.81.0, libboost-random1.83.0
Installed-Size: ${installed_size}
EOF
  # Create .deb
  qbcompile::verify::payload "${package_dir}" "Boost" "libboost_python*.so*"
  mflibs::shell::text::blue "Creating .deb package for Boost..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${package_dir}" "${boost_deb_file}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  boost_deb_rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  if [[ ${boost_deb_rc} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to create .deb package for Boost."
    exit 1
  fi
  qbcompile::verify::deb "${boost_deb_file}"
  # Cleanup extracted tarball dir (keep package_dir)
  rm -f "${BUILD_ROOT}/${boost_tar}"
  # rm -rf "${BUILD_ROOT:?}/${boost_dir}" # uncomment if you want to clean sources too
  # Verify
  if [[ -f "${boost_deb_file}" ]]; then
    mflibs::shell::text::green "Boost .deb package created successfully: ${boost_deb_file}"
  else
    mflibs::shell::text::red "Boost .deb package creation failed."
    exit 1
  fi
  # Update local package repository index
  qbcompile::update_repo_index "${boost_deb_storage}" "libboost-dev" "${boost_ver}" "boost"
  # Close screen
  screen -S boost_compile -X quit >/dev/null
}

################################################################################
# @description: Function to dynamically get the latest candidate version for libboost[VERSION]-dev
# @noargs
# @example: qbcompile::get::boost_latest_candidate
# @return: Latest available libboost development library package name
# @break
################################################################################
qbcompile::get::boost_latest_candidate() {
  mflibs::shell::text::blue "Finding the latest candidate for libboost version..."
  # Find all libboost packages and filter for the development versions
  declare -xg boost_package current_boost_package #current_boost_version
  boost_package=$(apt-cache search libboost | grep -E 'libboost[0-9]+\.[0-9]+-dev' | awk '{print $1}' | sort -V | tail -n 1)
  current_boost_package="${boost_package}"
  #current_boost_version=$(apt-cache policy "${current_boost_package}" | awk '/Installed:/ {print $2}' | grep -Po '\d+\.\d+')
  if [[ -n ${boost_package} ]]; then
    # Retrieve the candidate version for the latest boost package found
    local candidate_version
    candidate_version=$(apt-cache policy "${boost_package}" | awk '/Candidate:/ {print $2}')
    # Check if the candidate version is valid
    if [[ -n ${candidate_version} && ${candidate_version} != "(none)" ]]; then
      mflibs::shell::text::cyan "Latest candidate version for ${boost_package}: ${candidate_version}"
    else
      mflibs::shell::text::red "No candidate version found for ${boost_package}."
      return 1
    fi
  else
    mflibs::shell::text::red "No libboost development package found."
    return 1
  fi
}

################################################################################
# @description: Check and remove conflicting Boost versions if below a threshold
# @noargs
# @example: qbcompile::check::boost_conflict
# @return: None
# @break
################################################################################
qbcompile::check::boost_conflict() {
  mflibs::shell::text::blue "Checking for conflicting Boost installation..."
  # Ensure we get the current Boost package and installed version correctly
  local conflicting_boost_version
  conflicting_boost_version=$(apt-cache policy "${current_boost_package}" | awk '/Installed:/ {print $2}')
  # Check if conflicting_boost_version is empty or "(none)" indicating the package is not installed
  if [[ -z "${conflicting_boost_version}" || "${conflicting_boost_version}" == "(none)" ]]; then
    mflibs::shell::text::yellow "No libboost package is installed, or version info is unavailable."
    # If the package is not installed, let's proceed with the installation
    return 0
  fi
  # Extract just the version number (e.g., 1.83.0)
  conflicting_boost_version=$(echo "${conflicting_boost_version}" | grep -Po '\d+\.\d+')
  # Compare the versions if conflicting_boost_version is not empty
  if [[ -n "${conflicting_boost_version}" ]] && dpkg --compare-versions "${conflicting_boost_version}" lt "1.76"; then
    mflibs::shell::text::blue "Removing conflicting libboost version: ${conflicting_boost_version}"
    mflibs::log "apt-get remove -y ${current_boost_package}" || fix_broken_install
    mflibs::log "apt-get autoremove -y" || fix_broken_install
    mflibs::log "apt-get autoclean" || fix_broken_install
  else
    mflibs::shell::text::green "libboost version ${conflicting_boost_version} is sufficient."
  fi
}
