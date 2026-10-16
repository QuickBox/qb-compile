#!/usr/bin/env bash
################################################################################
# @file_name: compile-xmlrpc-c
# @version: 1.0.6
# @project_name: qb-compile
# @description: Compilation script for xmlrpc-c library for qb-compile
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
# @description: Function to compile xmlrpc-c and create a .deb package
# @noargs
# @example: qbcompile::compile::xmlrpc
# @break
################################################################################
qbcompile::compile::xmlrpc() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/xmlrpc-c_compile.log"
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
  sudo screen -dmS xmlrpc_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "xmlrpc-c compilation log: "
  mflibs::shell::text::cyan "screen -r xmlrpc_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating compilation for xmlrpc-c..."
  # Create storage directories
  declare -xg xmlrpc_c_deb_storage
  xmlrpc_c_deb_storage="${deb_storage}/${codename}/binary-amd64/xmlrpc-c"
  mkdir -p "${xmlrpc_c_deb_storage}"
  # Get the latest version and revision of xmlrpc-c
  if ! qbcompile::get::xmlrpc_c_version || [[ -z ${xmlrpc_c_version} ]]; then
    mflibs::shell::text::red "Failed to get the latest version of xmlrpc-c." && exit 1
  fi
  # Check if the .deb file already exists
  declare -xg xmlrpc_c_deb_file
  xmlrpc_c_deb_file="${xmlrpc_c_deb_storage}/xmlrpc-c_${xmlrpc_c_version}-1build1_amd64.deb"
  if ! qbcompile::check_existing_deb_or_binary "${xmlrpc_c_deb_file}"; then
    declare -xgi skip_compilation_processes=0
    # Close the screen session
    screen -S xmlrpc_compile -X quit >/dev/null
  else
    declare -xgi skip_compilation_processes=0
    # Navigate to the temporary directory
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to enter temp directory." && exit 1; }
    # Clone the xmlrpc-c repository and checkout the latest stable version
    [[ -d xmlrpc-c ]] && rm -rf "${temp_dir:-/opt/qb-compile/builds}/xmlrpc-c"
    if [[ -n ${xmlrpc_c_version} ]]; then
      mflibs::shell::text::blue "Checking out the latest xmlrpc-c version..."
      mflibs::shell::text::cyan "Version: ${xmlrpc_c_version} (Revision: ${xmlrpc_latest_revision})"
      mflibs::log "svn co https://svn.code.sf.net/p/xmlrpc-c/code/advanced@${xmlrpc_latest_revision} ${temp_dir:-/opt/qb-compile/builds}/xmlrpc-c"
    else
      mflibs::shell::text::red "Failed to obtain the latest xmlrpc-c version. Proceeding with a fallback to the advanced branch."
      mflibs::log "svn co https://svn.code.sf.net/p/xmlrpc-c/code/advanced@3173 ${temp_dir:-/opt/qb-compile/builds}/xmlrpc-c"
    fi
    # Enter the xmlrpc-c directory
    cd "${temp_dir:-/opt/qb-compile/builds}/xmlrpc-c" || { mflibs::shell::text::red "Failed to enter xmlrpc-c directory." && exit 1; }
    mflibs::shell::text::blue "Configuring xmlrpc-c with i8 support..."
    ./configure --prefix=/usr --enable-libxml2-backend --disable-wininet-client --disable-libwww-client --libdir=/usr/lib/x86_64-linux-gnu 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure xmlrpc-c." && exit 1; }
    # Build xmlrpc-c
    mflibs::shell::text::blue "Building xmlrpc-c version ${xmlrpc_c_version}..."
    qbcompile::build::status &
    status_pid=$!
    sudo make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to build xmlrpc-c." && exit 1; }
    # Install into a temporary directory for packaging
    install_dir="${temp_dir:-/opt/qb-compile/builds}/xmlrpc_c_install"
    mkdir -p "${install_dir}"
    sudo make install DESTDIR="${install_dir}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install xmlrpc-c." && exit 1; }
    # Set sleep to avoid premature size calculation
    sleep 3
    # Calculate Installed Size in KB (integer only)
    installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
    # Set up packaging directory structure
    package_dir="${temp_dir:-/opt/qb-compile/builds}/xmlrpc_c_package"
    mkdir -p "${package_dir}/DEBIAN"
    mkdir -p "${package_dir}/usr"
    # Copy installed files to package directory
    cp -r "${install_dir}/usr/"* "${package_dir}/usr/"
    # Determine SSL library dependency based on Debian version
    case "${codename}" in
    bullseye)
      ssl_dep="libssl1.1 (>= 1.1.0)"
      ;;
    bookworm | trixie | jammy)
      ssl_dep="libssl3 (>= 3.0.0)"
      ;;
    noble)
      ssl_dep="libssl3t64 (>= 3.0.0)"
      ;;
    *)
      # Fallback: auto-detect installed OpenSSL version
      if dpkg -l | grep -q "^ii.*libssl3"; then
        ssl_dep="libssl3 (>= 3.0.0)"
      elif dpkg -l | grep -q "^ii.*libssl1.1"; then
        ssl_dep="libssl1.1 (>= 1.1.0)"
      else
        ssl_dep="libssl1.1 (>= 1.1.0)"
      fi
      ;;
    esac
    # Create control file for dpkg-deb
    cat <<EOF >"${package_dir}/DEBIAN/control"
Package: xmlrpc-c
Version: ${xmlrpc_c_version}-1build1
Section: libs
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Depends: ${ssl_dep}, libc6 (>= 2.28), libcurl4 (>= 7.16.2), zlib1g (>= 1:1.1.4)
Description: xmlrpc-c library for XML-RPC protocol
 A lightweight RPC library based on XML and HTTP.
 This package provides the core xmlrpc-c library for XML-RPC
 client and server implementations.
Installed-Size: ${installed_size}
EOF
    # Build the .deb package
    qbcompile::verify::payload "${package_dir}" "xmlrpc-c" "libxmlrpc*.so*"
    mflibs::shell::text::blue "Packaging xmlrpc-c version ${xmlrpc_c_version}..."
    qbcompile::dpkg-deb::status &
    status_pid=$!
    dpkg-deb --build "${package_dir}" "${xmlrpc_c_deb_storage}/xmlrpc-c_${xmlrpc_c_version}-1build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create xmlrpc-c .deb package." && exit 1; }
    # Verify and move package
    xmlrpc_c_deb_file=$(find "${xmlrpc_c_deb_storage}/" -maxdepth 1 -type f -name "xmlrpc-c*.deb" | head -n 1)
    [[ -z ${xmlrpc_c_deb_file} ]] && { mflibs::shell::text::red "No .deb file found for xmlrpc-c." && exit 1; }
    qbcompile::verify::deb "${xmlrpc_c_deb_file}"
    # Calculate and display the MD5 checksum of the .deb file
    declare -xg xmlrpc_c_deb_md5_hash
    xmlrpc_c_deb_md5_hash=$(md5sum "${xmlrpc_c_deb_file}" | awk '{ print $1 }')
    mflibs::shell::text::green "MD5 checksum of the xmlrpc-c package: ${xmlrpc_c_deb_md5_hash}"
  fi
  # Close the screen session
  screen -S xmlrpc_compile -X quit >/dev/null
}
