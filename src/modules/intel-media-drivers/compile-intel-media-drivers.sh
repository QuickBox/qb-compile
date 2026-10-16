#!/usr/bin/env bash
################################################################################
# @file_name: compile-intel-media-drivers
# @version: 1.0.5
# @project_name: qb-compile
# @description: Compilation script for Intel Media Drivers for qb-compile
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
# Bonus Intel-Media-Driver Compilation
# @description: Function to compile Intel Media Driver and create a .deb package
# @noargs
# @example: qbcompile::compile::intel_media_drivers
# @break
################################################################################
qbcompile::compile::intel_media_drivers() {
  declare -xg media_driver_version libva_version gmmlib_version
  media_driver_version="24.3.4"
  libva_version="2.22.0"
  gmmlib_version="22.5.2" # Example GmmLib version; adjust as needed
  declare -xg mflibs_log_location="/opt/qb-compile/logs/intel-media-driver_compile.log"
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
  sudo screen -dmS intel_media_driver_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "Intel Media Driver compilation log: "
  mflibs::shell::text::cyan "screen -r intel_media_driver_compile"
  mflibs::shell::misc::nl

  # Create storage directories for the LibVA and GmmLib .deb packages
  declare -xg libva_deb_storage gmmlib_deb_storage intel_media_driver_deb_storage
  libva_deb_storage="${deb_storage}/${codename}/binary-amd64/libva"
  gmmlib_deb_storage="${deb_storage}/${codename}/binary-amd64/gmmlib"
  intel_media_driver_deb_storage="${deb_storage}/${codename}/binary-amd64/intel-media-driver"
  mkdir -p "${libva_deb_storage}" "${gmmlib_deb_storage}" "${intel_media_driver_deb_storage}"

  # Check if the libva, gmmlib, and Intel Media Driver .deb files already exist
  declare -xg libva_deb_file gmmlib_deb_file intel_media_driver_deb_file
  libva_deb_file="${libva_deb_storage}/libva_${libva_version}-1build1_amd64.deb"
  gmmlib_deb_file="${gmmlib_deb_storage}/gmmlib_${gmmlib_version}-1build1_amd64.deb"
  intel_media_driver_deb_file="${intel_media_driver_deb_storage}/intel-media-driver_${media_driver_version}-1build1_amd64.deb"

  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${libva_deb_file}"; then
    skip_compilation_processes=0
  else
    skip_compilation_processes=0
    # Create workspace and package directories
    libva_package_dir="${temp_dir:-/opt/qb-compile/builds}/libva_package"
    gmmlib_package_dir="${temp_dir:-/opt/qb-compile/builds}/gmmlib_package"
    intel_media_driver_package_dir="${temp_dir:-/opt/qb-compile/builds}/intel_media_driver_package"
    mkdir -p "${temp_dir:-/opt/qb-compile/builds}" "${libva_package_dir}"
    mflibs::shell::text::blue "initiating LibVA, GmmLib, and Intel Media Driver compilation..."
    ######################################################################################################
    # Step 1: Download and build LibVA
    ######################################################################################################
    mflibs::shell::text::blue "Downloading LibVA version ${libva_version}..."
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to navigate to workspace directory." && exit 1; }
    wget -q "https://github.com/intel/libva/archive/refs/tags/${libva_version}.tar.gz" -O "libva-${libva_version}.tar.gz" || { mflibs::shell::text::red "Failed to download LibVA." && exit 1; }
    tar -xf "libva-${libva_version}.tar.gz" || { mflibs::shell::text::red "Failed to extract LibVA." && exit 1; }
    local libva_dir
    libva_dir=$(find "${temp_dir:-/opt/qb-compile/builds}" -type d -name "libva-${libva_version}*")
    mflibs::shell::text::blue "Configuring LibVA..."
    cd "${libva_dir}" || { mflibs::shell::text::red "LibVA directory not found." && exit 1; }
    ./autogen.sh --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to run autogen.sh." && exit 1; }
    mflibs::shell::text::blue "Building LibVA..."
    qbcompile::build::status &
    status_pid=$!
    make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Compilation of LibVA failed." && exit 1; }
    mkdir -p "${libva_package_dir}/libva-${libva_version}/DEBIAN"
    make DESTDIR="${libva_package_dir}/libva-${libva_version}" install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install LibVA to package directory." && exit 1; }
    mflibs::shell::text::blue "Packaging LibVA..."
    local libva_size
    libva_size=$(du -sk "${libva_package_dir}/libva-${libva_version}" | awk '{print $1}')
    cat <<EOF >"${libva_package_dir}/libva-${libva_version}/DEBIAN/control"
Package: libva
Version: ${libva_version}
Section: libs
Priority: optional
Architecture: amd64
Installed-Size: ${libva_size}
Maintainer: Intel
Description: Intel VAAPI Video Acceleration Library
EOF
    qbcompile::verify::payload "${libva_package_dir}/libva-${libva_version}" "LibVA"
    qbcompile::dpkg-deb::status &
    status_pid=$!
    dpkg-deb --build "${libva_package_dir}/libva-${libva_version}" "${libva_deb_storage}/libva_${libva_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to package LibVA as .deb." && exit 1; }
    qbcompile::verify::deb "${libva_deb_storage}/libva_${libva_version}-1build1_amd64.deb"
    local libva_checksum
    libva_checksum=$(md5sum "${libva_deb_storage}/libva_${libva_version}-1build1_amd64.deb" | awk '{print $1}')
    mflibs::shell::text::green "LibVA MD5 checksum: ${libva_checksum}"
    mflibs::shell::misc::nl
  fi

  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${gmmlib_deb_file}"; then
    skip_compilation_processes=0
  else
    skip_compilation_processes=0
    ######################################################################################################
    # Step 2: Download and build GmmLib
    ######################################################################################################
    mflibs::shell::text::blue "Downloading GmmLib version ${gmmlib_version}..."
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to navigate to workspace directory." && exit 1; }
    wget -q "https://github.com/intel/gmmlib/archive/refs/tags/intel-gmmlib-${gmmlib_version}.tar.gz" -O "gmmlib-${gmmlib_version}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download GmmLib." && exit 1; }
    tar -xf "gmmlib-${gmmlib_version}.tar.gz" || { mflibs::shell::text::red "Failed to extract GmmLib." && exit 1; }
    local gmmlib_dir
    gmmlib_dir=$(find "${temp_dir:-/opt/qb-compile/builds}" -type d -name "gmmlib-intel-gmmlib-${gmmlib_version}*")
    mflibs::shell::text::blue "Configuring GmmLib..."
    cd "${gmmlib_dir}" || { mflibs::shell::text::red "GmmLib directory not found." && exit 1; }
    mkdir -p build
    cd build || { mflibs::shell::text::red "Failed to create build directory for GmmLib." && exit 1; }
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "CMake configuration for GmmLib failed." && exit 1; }
    mflibs::shell::text::blue "Building GmmLib..."
    qbcompile::build::status &
    status_pid=$!
    make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Compilation of GmmLib failed." && exit 1; }
    mkdir -p "${gmmlib_package_dir}/gmmlib-${gmmlib_version}/DEBIAN"
    make DESTDIR="${gmmlib_package_dir}/gmmlib-${gmmlib_version}" install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install GmmLib to package directory." && exit 1; }
    mflibs::shell::text::blue "Packaging GmmLib..."
    local gmmlib_size
    gmmlib_size=$(du -sk "${gmmlib_package_dir}/gmmlib-${gmmlib_version}" | awk '{print $1}')
    cat <<EOF >"${gmmlib_package_dir}/gmmlib-${gmmlib_version}/DEBIAN/control"
Package: gmmlib
Version: ${gmmlib_version}
Section: libs
Priority: optional
Architecture: amd64
Installed-Size: ${gmmlib_size}
Maintainer: Intel
Description: Intel Graphics Memory Management Library
EOF
    qbcompile::verify::payload "${gmmlib_package_dir}/gmmlib-${gmmlib_version}" "GmmLib"
    qbcompile::dpkg-deb::status &
    status_pid=$!
    dpkg-deb --build "${gmmlib_package_dir}/gmmlib-${gmmlib_version}" "${gmmlib_deb_storage}/gmmlib_${gmmlib_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to package GmmLib as .deb!" && exit 1; }
    qbcompile::verify::deb "${gmmlib_deb_storage}/gmmlib_${gmmlib_version}-1build1_amd64.deb"
    local gmmlib_checksum
    gmmlib_checksum=$(md5sum "${gmmlib_deb_storage}/gmmlib_${gmmlib_version}-1build1_amd64.deb" | awk '{print $1}')
    mflibs::shell::text::green "GmmLib MD5 checksum: ${gmmlib_checksum}"
    mflibs::shell::misc::nl
  fi

  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${intel_media_driver_deb_file}"; then
    declare -xgi skip_compilation_processes=0
  else
    declare -xgi skip_compilation_processes=0
    ######################################################################################################
    # Step 3: Download and prepare Intel Media Driver
    ######################################################################################################
    mflibs::shell::text::blue "Downloading Intel Media Driver version ${media_driver_version}..."
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to navigate to workspace directory." && exit 1; }
    wget -q "https://github.com/intel/media-driver/archive/refs/tags/intel-media-${media_driver_version}.zip" -O "media-driver.zip" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download Intel Media Driver!" && exit 1; }
    unzip -q "media-driver.zip" -d "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to extract Intel Media Driver!" && exit 1; }
    local media_driver_dir
    media_driver_dir=$(find "${temp_dir:-/opt/qb-compile/builds}" -type d -name "media-driver-intel-media-${media_driver_version}*")
    cd "${media_driver_dir}" || { mflibs::shell::text::red "Intel Media Driver directory not found!" && exit 1; }
    mkdir -p build
    cd build || { mflibs::shell::text::red "Failed to create build directory for Intel Media Driver!" && exit 1; }
    mflibs::shell::text::blue "Configuring Intel Media Driver..."
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr .. 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "CMake configuration for Intel Media Driver failed!" && exit 1; }
    mflibs::shell::text::blue "Building Intel Media Driver..."
    qbcompile::build::status &
    status_pid=$!
    make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Compilation of Intel Media Driver failed!" && exit 1; }
    mkdir -p "${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}/DEBIAN"
    make DESTDIR="${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}" install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install Intel Media Driver to package directory!" && exit 1; }
    mflibs::shell::text::blue "Packaging Intel Media Driver..."
    local media_driver_size
    media_driver_size=$(du -sk "${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}" | awk '{print $1}')
    cat <<EOF >"${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}/DEBIAN/control"
Package: intel-media-driver
Version: ${media_driver_version}
Section: libs
Priority: optional
Architecture: amd64
Installed-Size: ${media_driver_size}
Maintainer: Intel
Description: Intel Media Driver for VAAPI
EOF
    qbcompile::verify::payload "${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}" "Intel Media Driver"
    qbcompile::dpkg-deb::status &
    status_pid=$!
    dpkg-deb --build "${intel_media_driver_package_dir}/intel-media-driver-${media_driver_version}" "${intel_media_driver_deb_storage}/intel-media-driver_${media_driver_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to package Intel Media Driver as .deb!" && exit 1; }
    qbcompile::verify::deb "${intel_media_driver_deb_storage}/intel-media-driver_${media_driver_version}-1build1_amd64.deb"
    local media_driver_checksum
    media_driver_checksum=$(md5sum "${intel_media_driver_deb_storage}/intel-media-driver_${media_driver_version}-1build1_amd64.deb" | awk '{print $1}')
    mflibs::shell::text::green "Intel Media Driver MD5 checksum: ${media_driver_checksum}"
    mflibs::shell::misc::nl
    mflibs::shell::text::green "LibVA, GmmLib, and Intel Media Driver compiled, packaged, and verified successfully!"
    mflibs::shell::misc::nl
  fi
  # Close the screen session
  screen -S intel_media_driver_compile -X quit >/dev/null
}
