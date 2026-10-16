#!/usr/bin/env bash
################################################################################
# @file_name: compile-cmake
# @version: 1.0.5
# @project_name: qb-compile
# @description: Compilation script for CMake for qb-compile
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
# @description: Function to compile and install CMake from source and create a .deb package
# @noargs
# @example: qbcompile::compile::cmake
# @break
################################################################################
qbcompile::compile::cmake() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/cmake_compile.log"
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
  sudo screen -dmS cmake_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "CMake compilation log: "
  mflibs::shell::text::cyan "screen -r cmake_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating CMake compilation..."
  # Define CMake version and source URL
  qbcompile::get::cmake_version
  declare -xg cmake_source_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}.tar.gz"
  # Create storage directories
  declare -xg cmake_deb_storage
  cmake_deb_storage="${deb_storage}/${codename}/binary-amd64/cmake"
  mkdir -p "${cmake_deb_storage}"
  # Check if the .deb file already exists
  declare -xg cmake_deb_file
  cmake_deb_file="${cmake_deb_storage}/cmake_${cmake_version}-1build1_amd64.deb"
  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${cmake_deb_file}"; then
    declare -xgi skip_compilation_processes=0
    # Close the screen session
    screen -S cmake_compile -X quit >/dev/null
  else
    declare -xgi skip_compilation_processes=0
    # Navigate to the temporary directory
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to enter temp directory." && exit 1; }
    # Clean previous attempts and download the source tarball
    [[ -d cmake ]] && rm -rf cmake-*
    mflibs::shell::text::blue "Downloading CMake source..."
    wget "${cmake_source_url}" -O "cmake-${cmake_version}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download CMake source." && exit 1; }
    mflibs::log "tar -xvf cmake-${cmake_version}.tar.gz" || { mflibs::shell::text::red "Failed to extract CMake source." && exit 1; }
    cd "cmake-${cmake_version}" || { mflibs::shell::text::red "Failed to enter CMake source directory." && exit 1; }
    if [[ "${codename}" == "bullseye" ]]; then
      # Get GCC version for Debian Bullseye
      qbcompile::get::gcc_version 2>/dev/null
      export CC="/usr/local/gcc-${gcc_version}/bin/gcc"
      export CXX="/usr/local/gcc-${gcc_version}/bin/g++"
      #export CXXFLAGS="-std=c++11 -L/usr/local/gcc-${gcc_version}/lib64"
      export LDFLAGS="-L/usr/local/gcc-${gcc_version}/lib64"
      export PATH="/usr/local/gcc-${gcc_version}/bin:${PATH}"
      # Set environment variables for GCC
      export LIBRARY_PATH="/usr/local/gcc-${gcc_version}/lib64:${LIBRARY_PATH}"
      export LD_LIBRARY_PATH="/usr/local/gcc-${gcc_version}/lib64:${LD_LIBRARY_PATH}"
      # Check if GCC is already configured
      if [[ -f "/etc/ld.so.conf.d/gcc-${gcc_version}.conf" ]]; then
        mflibs::shell::text::blue "GCC ${gcc_version} already configured."
      else
        echo "/usr/local/gcc-${gcc_version}/lib64" | sudo tee "/etc/ld.so.conf.d/gcc-${gcc_version}.conf" >/dev/null
        # Update library cache
        sudo ldconfig
      fi
    fi
    # Bootstrap the CMake build
    mflibs::shell::text::blue "Configuring CMake build version ${cmake_version} (bootstrap)..."
    ./bootstrap --prefix=/usr/local --system-curl 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure CMake build." && exit 1; }
    # Directly invoke the install target, bypassing any progress tracking in the build
    mflibs::shell::text::blue "Installing CMake into temporary directory for packaging..."
    install_dir="${temp_dir:-/opt/qb-compile/builds}/cmake_install"
    mkdir -p "${install_dir}"
    set_nproc="$(qbcompile::build::jobs)"
    #qbcompile::build::status &
    #status_pid=$!
    if [[ "${codename}" == "bullseye" ]]; then
      sudo LD_LIBRARY_PATH=/usr/local/gcc-"${gcc_version}"/lib64 make -j"${set_nproc}" install DESTDIR="${install_dir}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    else
      sudo make -j"${set_nproc}" install DESTDIR="${install_dir}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    fi
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install CMake." && exit 1; }
    # Wait for the background process to finish
    #wait "${status_pid}"
    # Calculate Installed Size in KB (integer only)
    installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
    # Ensure the installation directory exists before copying
    if [[ -d "${install_dir}" ]]; then
      # Package everything into a .deb package
      package_dir="${temp_dir:-/opt/qb-compile/builds}/cmake_package"
      mkdir -p "${package_dir}/DEBIAN"
      mkdir -p "${package_dir}/usr/local"
      # Copy installed files directly into /usr/local in package directory
      cp -r "${install_dir}/usr/local/"* "${package_dir}/usr/local/"

      # Create control file for dpkg-deb
      cat <<EOF >"${package_dir}/DEBIAN/control"
Package: cmake
Version: ${cmake_version}-1build1
Section: devel
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: CMake build management tool
Installed-Size: ${installed_size}
Depends: libssl-dev
EOF
      # Build the .deb package
      qbcompile::verify::payload "${package_dir}" "CMake" "cmake"
      mflibs::shell::text::blue "Packaging CMake..."
      qbcompile::dpkg-deb::status &
      status_pid=$!
      dpkg-deb --build "${package_dir}" "${cmake_deb_storage}/cmake_${cmake_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      rc=${PIPESTATUS[0]}
      # Wait for the background process to finish
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create CMake .deb package." && exit 1; }
    else
      mflibs::shell::text::red "Installation directory not found, aborting package creation."
      exit 1
    fi
    # Get the .deb package name
    declare -xg cmake_deb_file
    cmake_deb_file=$(find "${cmake_deb_storage}/" -maxdepth 1 -type f -name "cmake*.deb" | head -n 1)
    # Check if the .deb file exists
    [[ -z ${cmake_deb_file} ]] && mflibs::shell::text::red "No .deb file found for CMake." && exit 1
    # Redeclare the variable with the new path
    cmake_deb_file="${cmake_deb_storage}/$(basename "${cmake_deb_file}")"
    qbcompile::verify::deb "${cmake_deb_file}"
    # Calculate the MD5 checksum of the .deb file
    declare -xg cmake_md5_hash
    cmake_md5_hash=$(md5sum "${cmake_deb_file}" | awk '{ print $1 }')
    # Output the MD5 hash
    mflibs::shell::text::green "MD5 checksum of the created package: ${cmake_md5_hash}"
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to temp directory." && exit 1; }
    mflibs::shell::text::green "Successfully compiled and packaged CMake version ${cmake_version}."
  fi
  # Close the screen session
  screen -S cmake_compile -X quit >/dev/null
}
