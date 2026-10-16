#!/usr/bin/env bash
################################################################################
# @file_name: compile-transmission
# @version: 1.0.12
# @project_name: qb-compile
# @description: Compilation script for Transmission for qb-compile
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
# shellcheck disable=SC1090,SC1091,SC2154,SC2312
################################################################################

################################################################################
# @description: Function to compile Transmission with all components and create a .deb package
# @noargs
# @example: qbcompile::compile::transmission
# @break
################################################################################
qbcompile::compile::transmission() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/transmission_compile.log"
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
  sudo screen -dmS transmission_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "Transmission compilation log: "
  mflibs::shell::text::cyan "screen -r transmission_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating compilation for Transmission..."
  # Create storage directories
  declare -xg transmission_deb_storage
  transmission_deb_storage="${deb_storage}/${codename}/binary-amd64/transmission"
  mkdir -p "${transmission_deb_storage}"
  cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to enter temp directory." && exit 1; }
  # Get the latest stable version of Transmission
  if ! qbcompile::get::transmission_version || [[ -z ${transmission_version} ]]; then
    mflibs::shell::text::red "Failed to get the latest stable version of Transmission." && exit 1
  fi
  # Check if the .deb file already exists
  declare -xg transmission_deb_file
  transmission_deb_file="${transmission_deb_storage}/transmission_${transmission_version}-1build1+allmods_amd64.deb"
  if ! qbcompile::check_existing_deb_or_binary "${transmission_deb_file}"; then
    declare -xgi skip_compilation_processes=0
    # Close the screen session
    screen -S transmission_compile -X quit >/dev/null
  else
    declare -xgi skip_compilation_processes=0
    # Install dependencies for GTK, Qt6, Daemon, CLI, and Web components
    mflibs::shell::text::blue "Installing Transmission compilation dependencies..."
    if [[ "${codename}" == "trixie" ]]; then
      # Debian 13 needs additional or updated packages
      mflibs::log "apt-get install -y libgtkmm-4.0-dev libgtkmm-3.0-dev libgtk-4-dev libcurl4-openssl-dev libssl-dev libevent-dev libminiupnpc-dev libnatpmp-dev libpsl-dev libb64-dev libdeflate-dev libsystemd-dev" || fix_broken_install
    elif [[ "${codename}" != "bullseye" ]]; then
      mflibs::log "apt-get install -y libgtkmm-3.0-dev libgtk-4-dev libcurl4-openssl-dev libssl-dev libevent-dev libminiupnpc-dev libnatpmp-dev libpsl-dev libb64-dev libdeflate-dev libsystemd-dev" || fix_broken_install
    else
      mflibs::log "apt-get install -y libgtkmm-3.0-dev libglibmm-2.4-dev libappindicator3-dev libcurl4-openssl-dev libssl-dev libevent-dev libminiupnpc-dev libnatpmp-dev libpsl-dev libb64-dev libdeflate-dev libsystemd-dev" || fix_broken_install
    fi
    [[ -d "Transmission" ]] && rm -rf "Transmission"
    mflibs::shell::text::blue "Cloning Transmission repository version ${transmission_version}..."
    mflibs::log "git clone https://github.com/transmission/transmission Transmission" || { mflibs::shell::text::red "Failed to clone Transmission repository." && exit 1; }
    cd "Transmission" || { mflibs::shell::text::red "Failed to enter Transmission directory." && exit 1; }
    mflibs::shell::text::blue "Checking out Transmission version ${transmission_version}..."
    mflibs::log "git checkout ${transmission_version}" || { mflibs::shell::text::red "Failed to checkout version ${transmission_version}." && exit 1; }
    mflibs::shell::text::blue "Updating Transmission submodules..."
    mflibs::log "git submodule update --init --recursive" || { mflibs::shell::text::red "Failed to update submodules." && exit 1; }
    # Build current latest stable node from source
    mkdir -p "/opt/qb-compile/builds/npm"
    cd "/opt/qb-compile/builds/npm" || { mflibs::shell::text::red "Failed to enter /opt/qb-compile/builds/npm." && exit 1; }
    local node_version
    node_version="20.18.0"
    # Source nvm environment manually in case it's not already loaded
    export NVM_DIR="${HOME}/.nvm"
    # Load nvm and nvm bash completion
    [[ -s "${NVM_DIR}/nvm.sh" ]] && \. "${NVM_DIR}/nvm.sh"
    [[ -s "${NVM_DIR}/bash_completion" ]] && \. "${NVM_DIR}/bash_completion"
    # Check if nvm is installed, if not install it
    if ! command -v nvm &>/dev/null; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      nvm_rc=("${PIPESTATUS[@]}")
      [[ ${nvm_rc[0]} -eq 0 && ${nvm_rc[1]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install nvm." && exit 1; }
      source "${HOME}/.profile" >/dev/null 2>&1
      # The installer wrote nvm.sh after the initial source above; load it now so nvm is callable
      [[ -s "${NVM_DIR}/nvm.sh" ]] && \. "${NVM_DIR}/nvm.sh"
      [[ -s "${NVM_DIR}/bash_completion" ]] && \. "${NVM_DIR}/bash_completion"
    fi
    # Check if node version is installed, if not install it
    nvm install "${node_version}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install Node.js version ${node_version}." && exit 1; }
    # Set default node version
    nvm use "${node_version}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to set Node.js version ${node_version}." && exit 1; }
    # Skip npm upgrade - use the version that comes with Node 20.18.0 (npm 10.8.2)
    source "${HOME}/.profile" >/dev/null 2>&1
    export PATH="${NVM_DIR}/versions/node/v${node_version}/bin:${PATH}"
    command -v node >/dev/null 2>&1 || { mflibs::shell::text::red "Node is not accessible; check nvm setup." && exit 1; }
    # Make a backup of the original /usr/bin/node
    [[ -f "/usr/bin/node" ]] && sudo mv /usr/bin/node /usr/bin/node.bak
    # Create a symlink to the nvm node binary
    sudo ln -sf "${NVM_DIR}/versions/node/v${node_version}/bin/node" /usr/bin/node
    # Naviagte back to Transmission directory
    cd "${temp_dir:-/opt/qb-compile/builds}/Transmission" || { mflibs::shell::text::red "Failed to enter Transmission directory." && exit 1; }
    mflibs::shell::text::blue "Installing required Qt6 dependencies for Transmission..."
    # Install Qt6 dependencies for qBittorrent 5.0.0+
    qt6_deb_storage="${deb_storage}/${codename}/binary-amd64/qt6"
    qt6_deb_file=$(find "${qt6_deb_storage}/" -maxdepth 1 -type f -name "libqt6essentials-dev*.deb" | head -n 1)
    [[ -z ${qt6_deb_file} ]] && mflibs::shell::text::red "No Qt6 .deb package found." && exit 1
    # Install the Qt6 .deb packages for qBittorrent 5.0.0+ (from qbcompile::compile::qt6)
    qbcompile::verify::deb "${qt6_deb_file}"
    mflibs::log "dpkg -i --force-overwrite ${qt6_deb_file}" || { mflibs::shell::text::red "Failed to install Qt6 base." && exit 1; }
    #echo "/usr/local/qt6/lib" | sudo tee /etc/ld.so.conf.d/qt6.conf
    #sudo ldconfig 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null || { mflibs::shell::text::red "Failed to update ldconfig." && exit 1; }
    # Ensure necessary directory permissions
    mflibs::shell::text::blue "Setting up Transmission Web directories..."
    sudo mkdir -p /usr/local/share/transmission/public_html || { mflibs::shell::text::red "Failed to create /usr/local/share/transmission/public_html." && exit 1; }
    sudo chmod 755 /usr/local/share/transmission/public_html || { mflibs::shell::text::red "Failed to set permissions on /usr/local/share/transmission/public_html." && exit 1; }
    sudo chown root:root /usr/local/share/transmission/public_html || { mflibs::shell::text::red "Failed to set ownership for /usr/local/share/transmission/public_html." && exit 1; }
    # Ensure the source file has proper permissions (Step 1)
    sudo chmod 755 "${temp_dir:-/opt/qb-compile/builds}/Transmission/web/public_html/transmission-app.js.LEGAL.txt" || { mflibs::shell::text::red "Failed to set permissions on transmission-app.js.LEGAL.txt." && exit 1; }
    # Manually copy the file before running make install (Step 2)
    sudo cp "${temp_dir:-/opt/qb-compile/builds}/Transmission/web/public_html/transmission-app.js.LEGAL.txt" /usr/local/share/transmission/public_html/ || { mflibs::shell::text::red "Failed to copy transmission-app.js.LEGAL.txt." && exit 1; }
    # Patch for Trixie miniupnpc API changes (apply directly with sed)
    if [[ "${codename}" == "trixie" ]]; then
      mflibs::shell::text::blue "Applying Trixie miniupnpc API compatibility patch..."
      sed -i 's/UPNP_GetValidIGD(devlist, \&handle->urls, \&handle->data, std::data(lanaddr), std::size(lanaddr) - 1)/UPNP_GetValidIGD(devlist, \&handle->urls, \&handle->data, std::data(lanaddr), std::size(lanaddr) - 1, nullptr, 0)/' \
        "${temp_dir:-/opt/qb-compile/builds}/Transmission/libtransmission/port-forwarding-upnp.cc" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to apply miniupnpc patch." && exit 1; }
    fi
    # Build the Transmission components (daemon, CLI, web, GTK, Qt6)
    mflibs::shell::text::blue "Configuring Transmission build with Qt6..."
    # Set up directories for build and package installation
    install_dir="${temp_dir:-/opt/qb-compile/builds}/transmission_install"
    mkdir -p "${install_dir}"
    # Set environment variables
    if [[ "${codename}" == "trixie" ]]; then
      # Debian 13 Trixie - Transmission doesn't use Boost, remove unnecessary CMake variables
      export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
      export PATH="/usr/local/bin:${PATH}"
      export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"
      cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DENABLE_QT=ON \
        -DENABLE_DAEMON=ON \
        -DENABLE_GTK=ON \
        -DENABLE_CLI=ON \
        -DENABLE_UTILS=ON \
        -DREBUILD_WEB=ON \
        -DENABLE_TESTS=OFF \
        2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure Transmission build." && exit 1; }
    elif [[ "${codename}" == "bullseye" || "${codename}" == "jammy" || "${codename}" == "noble" ]]; then
      qbcompile::get::gcc_version >/dev/null
      qbcompile::get::qt_version 2>/dev/null
      # Resolve the Qt6 that is actually INSTALLED on this box, not the latest online
      # release. get::qt_version reports the newest upstream version (e.g. 6.11.1), but the
      # compiled Qt6 installed here is whatever qbcompile::compile::qt6 built (e.g. 6.8.0).
      # find_package(Qt6) must point at the real directory or CMake falls back to the distro
      # Qt6, whose LinguistTools target references a missing lprodump (breaks Transmission 4.1.x).
      local installed_qt_dir
      installed_qt_dir="$(find /usr/local -maxdepth 1 -type d -name 'Qt-*' 2>/dev/null | sort -V | tail -n1)"
      [[ -z ${installed_qt_dir} ]] && installed_qt_dir="/usr/local/Qt-${qt_latest_version}"
      # Set up environment variables to ensure correct 64-bit libraries are used
      export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${installed_qt_dir}/lib/pkgconfig:${PKG_CONFIG_PATH}"
      export LD_LIBRARY_PATH="/usr/local/lib:${installed_qt_dir}/lib:${LD_LIBRARY_PATH}"
      export PATH="/usr/local/bin:${installed_qt_dir}/bin:${NVM_DIR}/versions/node/v${node_version}/bin:${PATH}"
      #export CC="/usr/local/gcc-${gcc_version}/bin/gcc"
      #export CXX="/usr/local/gcc-${gcc_version}/bin/g++"
      (
        PATH="${NVM_DIR}/versions/node/v${node_version}/bin:${PATH}" cmake -B build -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_PREFIX_PATH="${installed_qt_dir}" \
          -DENABLE_QT=ON \
          -DENABLE_DAEMON=ON \
          -DENABLE_GTK=ON \
          -DENABLE_CLI=ON \
          -DENABLE_UTILS=ON \
          -DREBUILD_WEB=ON \
          -DENABLE_TESTS=OFF \
          2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
        exit "${PIPESTATUS[0]}"
      ) || { mflibs::shell::text::red "Failed to configure Transmission build." && exit 1; }
    else
      export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
      export PATH="/usr/local/bin:${PATH}"
      export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"
      cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DENABLE_QT=ON \
        -DENABLE_DAEMON=ON \
        -DENABLE_GTK=ON \
        -DENABLE_CLI=ON \
        -DENABLE_UTILS=ON \
        -DREBUILD_WEB=ON \
        -DENABLE_TESTS=OFF 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure Transmission build." && exit 1; }
    fi
    mflibs::shell::text::blue "Building Transmission version ${transmission_version} with all components..."
    set_nproc="$(qbcompile::build::jobs)"
    qbcompile::build::status &
    status_pid=$!
    sudo cmake --build build --target install --parallel -j"${set_nproc}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to build Transmission." && exit 1; }
    # Install into a temporary directory
    mflibs::shell::text::blue "Installing Transmission to temporary directory..."
    sudo DESTDIR="${install_dir}" cmake --install build 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install Transmission." && exit 1; }
    # Calculate Installed Size in KB (integer only)
    installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
    # Set up packaging directory structure
    package_dir="${temp_dir:-/opt/qb-compile/builds}/transmission_package"
    mkdir -p "${package_dir}/DEBIAN"
    cp -r "${install_dir}/"* "${package_dir}"
    # Create control file for dpkg-deb
    cat <<EOF >"${package_dir}/DEBIAN/control"
Package: transmission
Version: ${transmission_version}-1build1+allmods
Section: net
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: Transmission - A lightweight BitTorrent client
Installed-Size: ${installed_size}
EOF
    # Build the .deb package
    qbcompile::verify::payload "${package_dir}" "Transmission" "transmission-daemon"
    mflibs::shell::text::blue "Packaging Transmission version ${transmission_version}..."
    qbcompile::dpkg-deb::status &
    status_pid=$!
    dpkg-deb --build "${package_dir}" "${transmission_deb_storage}/transmission_${transmission_version}-1build1+allmods_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create Transmission .deb package." && exit 1; }
    # Verify the .deb package and calculate MD5 checksum
    transmission_deb_file=$(find "${transmission_deb_storage}/" -maxdepth 1 -type f -name "transmission*.deb" | head -n 1)
    [[ -z ${transmission_deb_file} ]] && { mflibs::shell::text::red "No .deb file found for Transmission." && exit 1; }
    qbcompile::verify::deb "${transmission_deb_file}"
    declare -xg transmission_md5_hash
    transmission_md5_hash=$(md5sum "${transmission_deb_file}" | awk '{ print $1 }')
    mflibs::shell::text::green "MD5 checksum of the created Transmission package: ${transmission_md5_hash}"
    # Update local package repository index
    qbcompile::update_repo_index "${transmission_deb_storage}" "transmission" "${transmission_version}" "transmission"
    # Navigate back to original directory
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to the temp directory." && exit 1; }
  fi
  # Close the screen session
  screen -S transmission_compile -X quit >/dev/null
}
