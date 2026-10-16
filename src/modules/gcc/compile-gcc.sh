#!/usr/bin/env bash
################################################################################
# @file_name: compile-gcc
# @version: 1.0.5
# @project_name: qb-compile
# @description: Compilation script for GCC for qb-compile
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
# @description: Function to compile and install GCC from source and create a .deb package
# @noargs
# @example: qbcompile::compile::gcc
# @break
################################################################################
qbcompile::compile::gcc() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/gcc_compile.log"
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
  sudo screen -dmS gcc_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "GCC compilation log: "
  mflibs::shell::text::cyan "screen -r gcc_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating GCC compilation..."
  # Define GCC version and source URL
  qbcompile::get::gcc_version
  declare -xg gcc_source_url="https://ftp.gnu.org/gnu/gcc/gcc-${gcc_version}/gcc-${gcc_version}.tar.gz"
  # Create storage directories
  declare -xg gcc_deb_storage
  gcc_deb_storage="${deb_storage}/${codename}/binary-amd64/gcc"
  mkdir -p "${gcc_deb_storage}"
  # Check if the .deb file already exists
  declare -xg gcc_deb_file
  gcc_deb_file="${gcc_deb_storage}/gcc_${gcc_version}-1build1_amd64.deb"
  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${gcc_deb_file}"; then
    declare -xgi skip_compilation_processes=0
    # Close the screen session
    screen -S gcc_compile -X quit >/dev/null
  else
    declare -xgi skip_compilation_processes=0
    # Navigate to the temporary directory
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to enter temp directory." && exit 1; }
    # Clean previous attempts and download the source tarball
    [[ -d gcc ]] && rm -rf gcc-*
    mflibs::shell::text::blue "Downloading GCC source..."
    wget "${gcc_source_url}" -O "gcc-${gcc_version}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download GCC source." && exit 1; }
    mflibs::log "tar -xvf gcc-${gcc_version}.tar.gz" || { mflibs::shell::text::red "Failed to extract GCC source." && exit 1; }
    cd "gcc-${gcc_version}" || { mflibs::shell::text::red "Failed to enter GCC source directory." && exit 1; }
    # Install necessary dependencies
    mflibs::shell::text::blue "Installing dependencies for GCC compilation..."
    mflibs::log "apt-get update" || fix_broken_install
    mflibs::log "apt-get install -y build-essential libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev" || fix_broken_install
    # Create a build directory and configure the build
    mkdir -p build
    cd build || { mflibs::shell::text::red "Failed to create build directory." && exit 1; }
    mflibs::shell::text::blue "Configuring GCC build version ${gcc_version}..."
    # Install GCC in /usr/local/gcc-${gcc_version} to avoid conflict with the system GCC
    ../configure --prefix=/usr/local/gcc-"${gcc_version}" \
      --enable-languages=c,c++ \
      --disable-multilib \
      --with-default-libstdcxx-abi=gcc4-compatible \
      --enable-bootstrap \
      --enable-libatomic \
      --enable-libstdcxx-time=yes \
      --with-system-zlib \
      --enable-threads=posix \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure GCC build." && exit 1; }
    # Compile and build GCC
    set_nproc="$(qbcompile::build::jobs)"
    # Start background monitoring of compilation status
    mflibs::shell::text::blue "Building GCC version ${gcc_version}..."
    qbcompile::build::status &
    status_pid=$!
    sudo make -j"${set_nproc}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    # Wait for the background process to finish
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to compile GCC." && exit 1; }
    # Install the full build into a temporary directory for packaging
    install_dir="${temp_dir:-/opt/qb-compile/builds}/gcc_install"
    mkdir -p "${install_dir}"
    mflibs::shell::text::blue "Installing GCC into ${install_dir}..."
    sudo make install DESTDIR="${install_dir}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install GCC." && exit 1; }
    # Calculate Installed Size in KB (integer only)
    installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
    # Ensure the installation directory exists before copying
    if [[ -d "${install_dir}" ]]; then
      # Package everything into a .deb package
      package_dir="${temp_dir:-/opt/qb-compile/builds}/gcc_package"
      mkdir -p "${package_dir}/DEBIAN"
      mkdir -p "${package_dir}/usr/local/"
      # Copy all the installed files to the package directory
      cp -rf "${install_dir}/usr/local/gcc-${gcc_version}" "${package_dir}/usr/local/"
      # Create control file for dpkg-deb
      cat <<EOF >"${package_dir}/DEBIAN/control"
Package: gcc-${gcc_version}
Version: ${gcc_version}-1build1
Section: devel
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: GNU Compiler Collection (GCC) for C and C++ languages
Installed-Size: ${installed_size}
EOF
      # Build the .deb package
      qbcompile::verify::payload "${package_dir}" "GCC"
      mflibs::shell::text::blue "Packaging GCC..."
      qbcompile::dpkg-deb::status &
      status_pid=$!
      dpkg-deb --build "${package_dir}" "${gcc_deb_storage}/gcc_${gcc_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      rc=${PIPESTATUS[0]}
      # Wait for the background process to finish
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create GCC .deb package." && exit 1; }
    else
      mflibs::shell::text::red "Installation directory not found, aborting package creation."
      exit 1
    fi
    # Get the .deb package name
    declare -xg gcc_deb_file
    gcc_deb_file=$(find "${gcc_deb_storage}/" -maxdepth 1 -type f -name "gcc*.deb" | head -n 1)
    # Check if the .deb file exists
    [[ -z ${gcc_deb_file} ]] && mflibs::shell::text::red "No .deb file found for GCC." && exit 1
    # Redeclare the variable with the new path
    gcc_deb_file="${gcc_deb_storage}/$(basename "${gcc_deb_file}")"
    qbcompile::verify::deb "${gcc_deb_file}"
    # Calculate the MD5 checksum of the .deb file
    declare -xg gcc_md5_hash
    gcc_md5_hash=$(md5sum "${gcc_deb_file}" | awk '{ print $1 }')
    # Output the MD5 hash
    mflibs::shell::text::green "MD5 checksum of the created package: ${gcc_md5_hash}"
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to temp directory." && exit 1; }
    mflibs::shell::text::green "Successfully compiled and packaged GCC version ${gcc_version}."
    # Add the newly installed GCC to alternatives
    mflibs::shell::text::blue "Configuring update-alternatives for GCC..."
    echo "/usr/local/gcc-${gcc_version}/lib64" | sudo tee "/etc/ld.so.conf.d/gcc-${gcc_version}.conf"
    sudo ldconfig
    # Add GCC-${gcc_version} to update-alternatives (sets /usr/bin/gcc to point to /usr/local/gcc-${gcc_version}/bin/gcc)
    #sudo update-alternatives --install /usr/bin/gcc gcc /usr/local/gcc-"${gcc_version}"/bin/gcc 60 \
    #	--slave /usr/bin/g++ g++ /usr/local/gcc-"${gcc_version}"/bin/g++ \
    #	--slave /usr/bin/gcc-ar gcc-ar /usr/local/gcc-"${gcc_version}"/bin/gcc-ar \
    #	--slave /usr/bin/gcc-nm gcc-nm /usr/local/gcc-"${gcc_version}"/bin/gcc-nm \
    #	--slave /usr/bin/gcc-ranlib gcc-ranlib /usr/local/gcc-"${gcc_version}"/bin/gcc-ranlib
    mflibs::shell::text::green "GCC version ${gcc_version} installed and configured."
  fi
  # Close the screen session
  screen -S gcc_compile -X quit >/dev/null
}
