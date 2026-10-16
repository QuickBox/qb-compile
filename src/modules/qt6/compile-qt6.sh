#!/usr/bin/env bash
################################################################################
# @file_name: compile-qt6
# @version: 1.0.6
# @project_name: qb-compile
# @description: Compilation script for Qt6 libraries for qb-compile
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
# @description: Function to compile the specified Qt6 modules and package them into one .deb
# This includes: qtbase, qttools, qtsvg, qttranslations as part of a single package.
# @noargs
# @example: qbcompile::compile::qt6
# @break
################################################################################
qbcompile::compile::qt6() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/qt6_compile.log"
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
  sudo screen -dmS qt6_compile bash -c "tail -f ${mflibs_log_location}"
  # Show screen message
  mflibs::shell::text::white::sl "Qt6 compilation log: "
  mflibs::shell::text::cyan "screen -r qt6_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating Qt6 compilation..."
  mflibs::shell::text::cyan "Modules: qtbase, qttools, qt5compat, qtsvg, qttranslations"
  # Create storage directories
  declare -xg qt6_deb_storage
  qt6_deb_storage="${deb_storage}/${codename}/binary-amd64/qt6"
  mkdir -p "${qt6_deb_storage}"
  if [[ "${codename}" == "bullseye" ]]; then
    # Set environment variables for Qt6 build
    export LLVM_DIR="/usr/lib/llvm-14/cmake"
    export LDFLAGS="-L/usr/lib/llvm-14/lib -Wl,-rpath,/usr/lib/llvm-14/lib"
    export LIBRARY_PATH="/usr/lib/llvm-14/lib:${LIBRARY_PATH}"
  fi
  mflibs::log "apt-get -y install libclang-dev clang-14 llvm-14 llvm-14-dev libclang-14-dev libclang-cpp14-dev" || fix_broken_install
  qbcompile::get::qt_latest_release
  # Get libtorrent-rasterbar version
  if [[ $(dpkg-query -W -f='${Version}' libtorrent-rasterbar) == 2.* ]]; then
    libtorrent_rasterbar_build_version=2
  elif [[ $(dpkg-query -W -f='${Version}' libtorrent-rasterbar) == 1.* ]]; then
    libtorrent_rasterbar_build_version=1
  else
    mflibs::shell::text::red "libtorrent-rasterbar not found or version is not 1.x or 2.x."
    exit 1
  fi
  # Check if the .deb file already exists
  declare -xg qt6_deb_file
  qt6_deb_file="${qt6_deb_storage}/libqt6essentials-dev_${qt_latest_version}-${libtorrent_rasterbar_build_version}build1_amd64.deb"
  # Call the check_existing_deb_or_binary function to decide whether to recompile
  if ! qbcompile::check_existing_deb_or_binary "${qt6_deb_file}"; then
    # User chose to skip compilation, or file doesn't exist.
    declare -xgi skip_compilation_processes=0
    # Close the screen session
    screen -S qt6_compile -X quit >/dev/null
  else
    # If the file exists and user chose to recompile, proceed with the compilation
    declare -xgi skip_compilation_processes=0
    if [[ "${codename}" == "bullseye" ]]; then
      # Set up environment variables for bullseye
      qbcompile::get::gcc_version 2>/dev/null
      export LIBRARY_PATH="/usr/lib/llvm-14/lib:/usr/local/gcc-${gcc_version}/lib64:${LIBRARY_PATH}"
      export LD_LIBRARY_PATH="/usr/lib/llvm-14/lib:/usr/local/gcc-${gcc_version}/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
      export CMAKE_LIBRARY_PATH="/usr/local/openssl/lib64:/usr/lib/x86_64-linux-gnu:/usr/lib:/usr/lib/llvm-14/lib:${CMAKE_LIBRARY_PATH}"
      export PATH="/usr/local/gcc-${gcc_version}/bin:/opt/qb-compile/builds/qt-everywhere-src-${qt_latest_version}/qtbase/build/bin:/usr/lib/llvm-14/bin:${PATH}"
      export CC="/usr/local/gcc-${gcc_version}/bin/gcc"
      export CXX="/usr/local/gcc-${gcc_version}/bin/g++"
      export LLVM_DIR="/usr/lib/llvm-14"
    fi
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to enter temp directory." && exit 1; }
    [[ -d "qt-everywhere-src-${qt_latest_version}" ]] && rm -rf "qt-everywhere-src-${qt_latest_version}"
    mflibs::shell::text::blue "Extracting Qt6 source tarball..."
    mflibs::log "tar -xf qt-everywhere-src-${qt_latest_version}.tar.xz" || { mflibs::shell::text::red "Failed to extract Qt6 source tarball." && exit 1; }
    # Run root-level configure from the Qt root directory
    cd "qt-everywhere-src-${qt_latest_version}" || { mflibs::shell::text::red "Failed to enter Qt6 source directory." && exit 1; }
    local qt6_config
    qt6_config=$(find "/opt/qb-compile/builds/qt-everywhere-src-${qt_latest_version}" -name Qt6Config.cmake | head -n 1)
    export CMAKE_PREFIX_PATH="${qt6_config%/*}" # Set CMAKE_PREFIX_PATH to the directory containing Qt6Config.cmake
    # Run the root-level configure script to set the modules
    mflibs::shell::text::blue "Running root-level configure script..."
    sudo ./configure -top-level \
      -DQT_BUILD_SUBMODULES="qtbase;qttools;qt5compat;qtsvg;qttranslations" \
      -opensource \
      -confirm-license \
      -release \
      -no-feature-relocatable \
      -D_GLIBCXX_USE_CXX11_ABI=1 \
      -qt-zlib \
      -qt-libpng \
      -qt-libjpeg \
      -nomake tests \
      -nomake examples \
      -skip qt3d \
      -skip qtactiveqt \
      -skip qtcanvaspainter \
      -skip qtcharts \
      -skip qtcoap \
      -skip qtconnectivity \
      -skip qtdatavis3d \
      -skip qtdeclarative \
      -skip qtdoc \
      -skip qtgraphs \
      -skip qtgrpc \
      -skip qthttpserver \
      -skip qtimageformats \
      -skip qtlanguageserver \
      -skip qtlocation \
      -skip qtlottie \
      -skip qtmqtt \
      -skip qtmultimedia \
      -skip qtnetworkauth \
      -skip qtopcua \
      -skip qtpositioning \
      -skip qtquick3d \
      -skip qtquick3dphysics \
      -skip qtquickeffectmaker \
      -skip qtquicktimeline \
      -skip qtremoteobjects \
      -skip qtscxml \
      -skip qtsensors \
      -skip qtserialbus \
      -skip qtserialport \
      -skip qtshadertools \
      -skip qtspeech \
      -skip qtvirtualkeyboard \
      -skip qtwayland \
      -skip qtwebchannel \
      -skip qtwebengine \
      -skip qtwebsockets \
      -skip qtwebview \
      2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure Qt6 from root." && exit 1; }
    # Build the configured modules
    mflibs::shell::text::blue "Building selected Qt6 modules (qtbase, qttools, qt5compat, qtsvg, qttranslations)..."
    # Start background monitoring of compilation status
    qbcompile::build::status &
    status_pid=$!
    #if [[ "${codename}" == "bullseye" ]]; then
    #	sudo LD_LIBRARY_PATH="/usr/local/gcc-${gcc_version}/lib64:${LD_LIBRARY_PATH}" cmake --build . --parallel "$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null || { mflibs::shell::text::red "Failed to compile Qt6." && exit 1; }
    #else
    sudo cmake --build . --parallel "$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    rc=${PIPESTATUS[0]}
    #fi
    # Wait for the background process to finish
    wait "${status_pid}"
    kill "${status_pid}" >/dev/null 2>&1 || true
    [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to compile Qt6." && exit 1; }
    # Install the full build into a temp directory for packaging
    install_dir="${temp_dir:-/opt/qb-compile/builds}/qt6_install/usr/local"
    mkdir -p "${install_dir}"
    mflibs::shell::text::blue "Installing all selected modules into ${install_dir}..."
    sudo cmake --install . 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to install Qt6." && exit 1; }
    # Copy to the build install directory
    cp -rf "/usr/local/Qt-${qt_latest_version}" "${install_dir}"
    # Calculate Installed Size in KB (integer only)
    installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
    # Ensure the installation directory exists before copying
    if [[ -d "${install_dir}" ]]; then
      # Package everything into one .deb
      package_dir="${temp_dir:-/opt/qb-compile/builds}/qt6_package"
      mkdir -p "${package_dir}/DEBIAN"
      mkdir -p "${package_dir}/usr/local"
      mflibs::shell::text::blue "Correcting directory structure before packaging..."
      mv "${install_dir}/Qt-${qt_latest_version}" "${package_dir}/usr/local/Qt-${qt_latest_version}" || { mflibs::shell::text::red "Failed to move installation files to correct directory." && exit 1; }
      # Create control file for dpkg-deb
      cat <<EOF >"${package_dir}/DEBIAN/control"
Package: libqt6essentials-dev
Version: ${qt_latest_version}-${libtorrent_rasterbar_build_version}build1
Section: libs
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: Qt6 development libraries including qtbase, qttools, qt5compat, qtsvg, qttranslations. Compiled to work with libtorrent-rasterbar ${libtorrent_rasterbar_build_version}.
Installed-Size: ${installed_size}
EOF
      # Build the .deb package
      mflibs::shell::text::blue "Packaging libqt6essentials-dev..."
      qbcompile::verify::payload "${package_dir}" "libqt6essentials-dev" "libQt6Core.so*"
      # Start background monitoring of compilation status
      qbcompile::dpkg-deb::status &
      status_pid=$!
      dpkg-deb --build "${package_dir}" "${qt6_deb_storage}/libqt6essentials-dev_${qt_latest_version}-${libtorrent_rasterbar_build_version}build1_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
      rc=${PIPESTATUS[0]}
      # Wait for the background process to finish
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create libqt6essentials-dev .deb package." && exit 1; }
    else
      mflibs::shell::text::red "Installation directory not found, aborting package creation."
      exit 1
    fi
    # Get the .deb package name
    declare -xg qt6_deb_file
    qt6_deb_file=$(find "${qt6_deb_storage}/" -maxdepth 1 -type f -name "libqt6essentials-dev*.deb" | head -n 1)
    # Check if the .deb file exists
    [[ -z ${qt6_deb_file} ]] && mflibs::shell::text::red "No .deb file found for Qt6." && exit 1
    # Redeclare the variable with the new path
    qt6_deb_file="${qt6_deb_storage}/$(basename "${qt6_deb_file}")"
    qbcompile::verify::deb "${qt6_deb_file}"
    # Calculate the MD5 checksum of the .deb file
    declare -xg qt6_deb_md5_hash
    qt6_deb_md5_hash=$(md5sum "${qt6_deb_file}" | awk '{ print $1 }')
    # Output the MD5 hash
    mflibs::shell::text::green "MD5 checksum of the created package: ${qt6_deb_md5_hash}"
    # Update local package repository index
    qbcompile::update_repo_index "${qt6_deb_storage}" "libqt6essentials-dev" "${qt_latest_version}" "qt6"
    cd "${temp_dir:-/opt/qb-compile/builds}" || { mflibs::shell::text::red "Failed to return to temp directory." && exit 1; }
  fi
  # Close the screen session
  screen -S qt6_compile -X quit >/dev/null
}
