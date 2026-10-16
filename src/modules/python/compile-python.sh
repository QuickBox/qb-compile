#!/usr/bin/env bash
################################################################################
# @file_name: compile-python
# @version: 1.0.8
# @project_name: qb-compile
# @description: Compilation script for Python in qb-compile
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
# @description: Compile Python 3.11.5 and 3.13.5 and create .deb packages
# @noargs
# @example: qbcompile::compile::python
# @break
################################################################################
qbcompile::compile::python() {
  declare -ga python_dependencies=("libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libcairo2-dev" "libgirepository1.0-dev" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "liblzma-dev" "python3" "python3-apt" "python3-software-properties" "python3-wheel" "python3-psutil" "python3-pip" "python3-dev" "python3-all-dev" "python3-docopt" "python3-setuptools" "python3-venv")
  # Debian 13 (trixie) removed python3-software-properties; avoid attempting to install it
  if [[ ${distro} == "debian" && ${codename} == "trixie" ]]; then
    declare -a _filtered_pydeps
    for depend in "${python_dependencies[@]}"; do
      if [[ "${depend}" == "python3-software-properties" ]]; then
        continue
      fi
      _filtered_pydeps+=("${depend}")
    done
    python_dependencies=("${_filtered_pydeps[@]}")
    unset _filtered_pydeps
  fi
  # Install dependencies
  declare depend install
  declare -a depend_list
  declare -ga install_list
  for depend in "${python_dependencies[@]}"; do
    if [[ $(dpkg-query -W -f='${Status}' "${depend}" 2>/dev/null | grep -c "ok installed") != "1" ]]; then
      depend_list+=("${depend}")
    fi
  done
  [[ -n ${depend_list[*]} ]] && mflibs::shell::text::white::sl "installing python dependencies: "
  for install in "${depend_list[@]}"; do
    if [[ ${install} == "${depend_list[0]}" ]]; then
      mflibs::shell::text::white::sl "${install} "
    else
      mflibs::shell::text::white::sl "| ${install} "
    fi
    mflibs::log "apt-get -y install ${install} --allow-unauthenticated" || { mflibs::status::kill "$(mflibs::shell::text::red "error installing ${install} dependency")" 2; }
    install_list+=("${install}")
  done
  unset depend depend_list install
  # ---------- Helpers ----------
  _pep668_flag_for() {
    local py="${1:-python3}"
    local platlib
    platlib="$(
      "${py}" - <<'PY'
import sysconfig, sys
try:
    print(sysconfig.get_path("platlib"))
except Exception:
    sys.exit(1)
PY
    )" || return 1
    [[ -f "${platlib%/}/EXTERNALLY-MANAGED" ]] && echo "--break-system-packages" && return 0
    return 1
  }
  # Does this pip support a specific CLI option? (e.g., --root-user-action)
  _pip_supports_opt() {
    local py="$1" opt="$2"
    "${py}" -m pip --help 2>&1 | grep -q -- "${opt}"
  }
  # ========================= Python 3.11.5 Compilation & Packaging =========================
  # Skip on Debian 12 (bookworm) where Python 3.11 is the default
  if [[ ${codename} != "bookworm" ]]; then
    declare -xg mflibs_log_location_311="/opt/qb-compile/logs/python3.11_compile.log"
    # Rotate logs
    if [[ -f "${mflibs_log_location_311}" ]]; then
      mflibs::shell::text::yellow "Moving existing Python 3.11 log file to backup..."
      if [[ ! -f "${mflibs_log_location_311}.001" ]]; then
        mv "${mflibs_log_location_311}" "${mflibs_log_location_311}.001" 2>/dev/null
      else
        for log in "${mflibs_log_location_311}".{001..500}; do
          [[ -f "${log}" ]] && mv "${log}" "${log%.*}".{001..500} 2>/dev/null
        done
      fi
    fi
    : >"${mflibs_log_location_311}"
    # Tail
    sudo screen -dmS python311_compile bash -c "tail -f ${mflibs_log_location_311}"
    mflibs::shell::misc::nl
    mflibs::shell::text::white::sl "Python 3.11.5 compilation log: "
    mflibs::shell::text::cyan "screen -r python311_compile"
    mflibs::shell::misc::nl
    mflibs::shell::text::blue "Initiating Python 3.11.5 compilation..."
    # Storage
    declare -xg python311_deb_storage
    python311_deb_storage="${deb_storage}/${codename}/binary-amd64/python"
    mkdir -p "${python311_deb_storage}"
    # Artifact
    declare -xg python311_version="3.11.5"
    declare -xg python311_deb_file
    python311_deb_file="${python311_deb_storage}/python311_${python311_version}-1build1_amd64.deb"
    if ! qbcompile::check_existing_deb_or_binary "${python311_deb_file}"; then
      screen -S python311_compile -X quit >/dev/null
    else
      # Dirs
      BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
      SRC_DIR_311="${BUILD_ROOT}/Python-3.11.5"
      package_dir_311="${BUILD_ROOT}/python3.11-package"
      ARCH="$(dpkg --print-architecture)"
      mkdir -p "${BUILD_ROOT}"
      rm -rf "${SRC_DIR_311}" "${package_dir_311}"
      mkdir -p "${package_dir_311}/DEBIAN"
      # Download and extract
      mflibs::shell::text::blue "Downloading Python 3.11.5..."
      cd "${BUILD_ROOT}" || {
        mflibs::shell::text::red "Failed to enter ${BUILD_ROOT}"
        exit 1
      }
      wget -q "https://www.python.org/ftp/python/3.11.5/Python-3.11.5.tgz" 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      mflibs::log "tar xvf Python-3.11.5.tgz" 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      cd "${SRC_DIR_311}" || {
        mflibs::shell::text::red "Failed to enter ${SRC_DIR_311}"
        exit 1
      }
      # Configure
      mflibs::shell::text::blue "Configuring Python 3.11.5..."
      ./configure --prefix=/usr/local \
        --enable-optimizations \
        --with-ensurepip=install \
        --enable-shared \
        LDFLAGS="-Wl,-rpath=/usr/local/lib" \
        2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to configure Python 3.11.5"
        exit 1
      }
      # Build
      mflibs::shell::text::blue "Building Python 3.11.5..."
      qbcompile::build::status &
      status_pid=$!
      jobs="$(qbcompile::build::jobs)"
      ((jobs < 1)) && jobs=1
      make -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      rc=${PIPESTATUS[0]}
      if [[ ${rc} -ne 0 ]]; then
        # The PGO profile run from --enable-optimizations can fail on a single environment-specific
        # test (e.g. test_generators on some gcc builds) and abort the whole build. Retry once
        # WITHOUT PGO so we still produce a working (un-profiled) interpreter.
        mflibs::shell::text::yellow "Optimized (PGO) build failed; retrying Python 3.11.5 without --enable-optimizations..."
        make clean 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null || true
        ./configure --prefix=/usr/local \
          --with-ensurepip=install \
          --enable-shared \
          LDFLAGS="-Wl,-rpath=/usr/local/lib" \
          2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
        make -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
        rc=${PIPESTATUS[0]}
      fi
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to build Python 3.11.5"
        exit 1
      }
      # Install into package root
      mflibs::shell::text::blue "Installing Python 3.11.5 into package directory..."
      make DESTDIR="${package_dir_311}" altinstall 2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to install Python 3.11.5"
        exit 1
      }
      # Create symlinks for lsb_release if available
      if [[ -f "/usr/share/pyshared/lsb_release.py" && ! -f "${package_dir_311}/usr/local/lib/python3.11/site-packages/lsb_release.py" ]]; then
        mkdir -p "${package_dir_311}/usr/local/lib/python3.11/site-packages"
        ln -s "/usr/share/pyshared/lsb_release.py" "${package_dir_311}/usr/local/lib/python3.11/site-packages/lsb_release.py"
      fi
      # Determine runtime dependencies based on codename
      case "${codename}" in
      bullseye)
        ssl_dep="libssl1.1"
        ;;
      jammy)
        ssl_dep="libssl3"
        ;;
      trixie)
        ssl_dep="libssl3t64"
        ;;
      noble)
        ssl_dep="libssl3t64"
        ;;
      *)
        ssl_dep="libssl3"
        ;;
      esac
      installed_size=$(du -sk "${package_dir_311}" | awk '{print $1}')
      cat >"${package_dir_311}/DEBIAN/control" <<EOF
Package: python311
Version: ${python311_version}-1build1
Section: python
Priority: optional
Architecture: ${ARCH}
Maintainer: ${maintainer}
Depends: libc6, libexpat1, libffi8 | libffi7, ${ssl_dep}, zlib1g, libbz2-1.0, libreadline8 | libreadline7, libsqlite3-0, libncursesw6 | libncursesw5, liblzma5, tk
Description: Python 3.11.5 - High-level programming language (version 3.11)
 Python is a high-level, interactive, object-oriented language.
 This package contains Python 3.11.5 runtime and libraries.
Installed-Size: ${installed_size}
EOF
      # Build .deb
      qbcompile::verify::payload "${package_dir_311}" "Python 3.11" "python3.11"
      mflibs::shell::text::blue "Creating .deb package for Python 3.11.5..."
      qbcompile::dpkg-deb::status &
      status_pid=$!
      dpkg-deb --build "${package_dir_311}" "${python311_deb_file}" \
        2>&1 | sudo tee -a "${mflibs_log_location_311}" >/dev/null
      rc=${PIPESTATUS[0]}
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to create Python 3.11 .deb package"
        exit 1
      }
      qbcompile::verify::deb "${python311_deb_file}"
      if [[ -f "${python311_deb_file}" ]]; then
        declare -xg python311_md5_hash
        python311_md5_hash=$(md5sum "${python311_deb_file}" | awk '{ print $1 }')
        mflibs::shell::text::green "Python 3.11 package created successfully!"
        mflibs::shell::text::green "MD5: ${python311_md5_hash}"
      else
        mflibs::shell::text::red "No .deb file found for Python 3.11."
        exit 1
      fi
      # Cleanup. cd out first so the shell's CWD is not left inside a dir this
      # removes (which would break the next module's clone/build).
      cd "${BUILD_ROOT}" || true
      rm -rf "${SRC_DIR_311}" "${package_dir_311}" "${BUILD_ROOT}/Python-3.11.5.tgz"
      screen -S python311_compile -X quit >/dev/null
    fi
  fi
  # ========================= Python 3.13.5 Compilation & Packaging =========================
  # Skip on Debian 13 (trixie) where Python 3.13 is the default
  if [[ ${codename} != "trixie" ]]; then
    declare -xg mflibs_log_location_313="/opt/qb-compile/logs/python3.13_compile.log"
    # Rotate logs
    if [[ -f "${mflibs_log_location_313}" ]]; then
      mflibs::shell::text::yellow "Moving existing Python 3.13 log file to backup..."
      if [[ ! -f "${mflibs_log_location_313}.001" ]]; then
        mv "${mflibs_log_location_313}" "${mflibs_log_location_313}.001" 2>/dev/null
      else
        for log in "${mflibs_log_location_313}".{001..500}; do
          [[ -f "${log}" ]] && mv "${log}" "${log%.*}".{001..500} 2>/dev/null
        done
      fi
    fi
    : >"${mflibs_log_location_313}"
    # Tail
    sudo screen -dmS python313_compile bash -c "tail -f ${mflibs_log_location_313}"
    mflibs::shell::misc::nl
    mflibs::shell::text::white::sl "Python 3.13.5 compilation log: "
    mflibs::shell::text::cyan "screen -r python313_compile"
    mflibs::shell::misc::nl
    mflibs::shell::text::blue "Initiating Python 3.13.5 compilation..."
    # Storage
    declare -xg python313_deb_storage
    python313_deb_storage="${deb_storage}/${codename}/binary-amd64/python"
    mkdir -p "${python313_deb_storage}"
    # Artifact
    declare -xg python313_version="3.13.5"
    declare -xg python313_deb_file
    python313_deb_file="${python313_deb_storage}/python313_${python313_version}-1build1_amd64.deb"
    if ! qbcompile::check_existing_deb_or_binary "${python313_deb_file}"; then
      screen -S python313_compile -X quit >/dev/null
    else
      # Dirs
      BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
      SRC_DIR_313="${BUILD_ROOT}/Python-3.13.5"
      package_dir_313="${BUILD_ROOT}/python3.13-package"
      ARCH="$(dpkg --print-architecture)"
      mkdir -p "${BUILD_ROOT}"
      rm -rf "${SRC_DIR_313}" "${package_dir_313}"
      mkdir -p "${package_dir_313}/DEBIAN"
      # Download and extract
      mflibs::shell::text::blue "Downloading Python 3.13.5..."
      cd "${BUILD_ROOT}" || {
        mflibs::shell::text::red "Failed to enter ${BUILD_ROOT}"
        exit 1
      }
      wget -q "https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tgz" 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      mflibs::log "tar xvf Python-3.13.5.tgz" 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      cd "${SRC_DIR_313}" || {
        mflibs::shell::text::red "Failed to enter ${SRC_DIR_313}"
        exit 1
      }
      # Configure
      mflibs::shell::text::blue "Configuring Python 3.13.5..."
      ./configure --prefix=/usr/local \
        --enable-optimizations \
        --with-ensurepip=install \
        --enable-shared \
        LDFLAGS="-Wl,-rpath=/usr/local/lib" \
        2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to configure Python 3.13.5"
        exit 1
      }
      # Build
      mflibs::shell::text::blue "Building Python 3.13.5..."
      qbcompile::build::status &
      status_pid=$!
      jobs="$(qbcompile::build::jobs)"
      ((jobs < 1)) && jobs=1
      make -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      rc=${PIPESTATUS[0]}
      if [[ ${rc} -ne 0 ]]; then
        # The PGO profile run from --enable-optimizations can fail on a single environment-specific
        # test (e.g. test_generators on some gcc builds) and abort the whole build. Retry once
        # WITHOUT PGO so we still produce a working (un-profiled) interpreter.
        mflibs::shell::text::yellow "Optimized (PGO) build failed; retrying Python 3.13.5 without --enable-optimizations..."
        make clean 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null || true
        ./configure --prefix=/usr/local \
          --with-ensurepip=install \
          --enable-shared \
          LDFLAGS="-Wl,-rpath=/usr/local/lib" \
          2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
        make -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
        rc=${PIPESTATUS[0]}
      fi
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to build Python 3.13.5"
        exit 1
      }
      # Install into package root
      mflibs::shell::text::blue "Installing Python 3.13.5 into package directory..."
      make DESTDIR="${package_dir_313}" altinstall 2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      [[ ${PIPESTATUS[0]} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to install Python 3.13.5"
        exit 1
      }
      # Create symlinks for lsb_release if available
      if [[ -f "/usr/share/pyshared/lsb_release.py" && ! -f "${package_dir_313}/usr/local/lib/python3.13/site-packages/lsb_release.py" ]]; then
        mkdir -p "${package_dir_313}/usr/local/lib/python3.13/site-packages"
        ln -s "/usr/share/pyshared/lsb_release.py" "${package_dir_313}/usr/local/lib/python3.13/site-packages/lsb_release.py"
      fi
      # Determine runtime dependencies based on codename
      case "${codename}" in
      bullseye)
        ssl_dep="libssl1.1"
        ;;
      jammy)
        ssl_dep="libssl3"
        ;;
      bookworm)
        ssl_dep="libssl3"
        ;;
      noble)
        ssl_dep="libssl3t64"
        ;;
      *)
        ssl_dep="libssl3t64"
        ;;
      esac
      installed_size=$(du -sk "${package_dir_313}" | awk '{print $1}')
      cat >"${package_dir_313}/DEBIAN/control" <<EOF
Package: python313
Version: ${python313_version}-1build1
Section: python
Priority: optional
Architecture: ${ARCH}
Maintainer: ${maintainer}
Depends: libc6, libexpat1, libffi8 | libffi7, ${ssl_dep}, zlib1g, libbz2-1.0, libreadline8 | libreadline7, libsqlite3-0, libncursesw6 | libncursesw5, liblzma5, tk
Description: Python 3.13.5 - High-level programming language (version 3.13)
 Python is a high-level, interactive, object-oriented language.
 This package contains Python 3.13.5 runtime and libraries.
Installed-Size: ${installed_size}
EOF
      # Build .deb
      qbcompile::verify::payload "${package_dir_313}" "Python 3.13" "python3.13"
      mflibs::shell::text::blue "Creating .deb package for Python 3.13.5..."
      qbcompile::dpkg-deb::status &
      status_pid=$!
      dpkg-deb --build "${package_dir_313}" "${python313_deb_file}" \
        2>&1 | sudo tee -a "${mflibs_log_location_313}" >/dev/null
      rc=${PIPESTATUS[0]}
      wait "${status_pid}"
      kill "${status_pid}" >/dev/null 2>&1 || true
      [[ ${rc} -eq 0 ]] || {
        mflibs::shell::text::red "Failed to create Python 3.13 .deb package"
        exit 1
      }
      qbcompile::verify::deb "${python313_deb_file}"
      if [[ -f "${python313_deb_file}" ]]; then
        declare -xg python313_md5_hash
        python313_md5_hash=$(md5sum "${python313_deb_file}" | awk '{ print $1 }')
        mflibs::shell::text::green "Python 3.13 package created successfully!"
        mflibs::shell::text::green "MD5: ${python313_md5_hash}"
      else
        mflibs::shell::text::red "No .deb file found for Python 3.13."
        exit 1
      fi
      # Cleanup. cd out first so the shell's CWD is not left inside a dir this
      # removes (which would break the next module's clone/build).
      cd "${BUILD_ROOT}" || true
      rm -rf "${SRC_DIR_313}" "${package_dir_313}" "${BUILD_ROOT}/Python-3.13.5.tgz"
      screen -S python313_compile -X quit >/dev/null
    fi
  fi
  # ========================= Post-Compilation: Pip & Module Management =========================
  mflibs::shell::text::white "Checking Python installations and configuring pip..."
  python_version="python3"
  # Set version variables if Python binaries exist (from .deb install or compilation)
  [[ -x /usr/local/bin/python3.11 && ${codename} != "bookworm" ]] && python_311_version="python3.11"
  [[ -x /usr/local/bin/python3.13 && ${codename} != "trixie" ]] && python_313_version="python3.13"
  # ---------- Common pip options ----------
  # Base options: safe for very old pip (no --root-user-action here)
  local pip_common_base="--upgrade --exists-action s --disable-pip-version-check --no-cache-dir --no-input"
  export PIP_BREAK_SYSTEM_PACKAGES=1
  # PEP 668 flags per interpreter
  local pip_flag_sys="" pip_flag_311="" pip_flag_313=""
  pip_flag_sys="$(_pep668_flag_for python3 || true)"
  [[ -x /usr/local/bin/python3.11 ]] && pip_flag_311="$(_pep668_flag_for /usr/local/bin/python3.11 || true)"
  [[ -x /usr/local/bin/python3.13 ]] && pip_flag_313="$(_pep668_flag_for /usr/local/bin/python3.13 || true)"
  # ---------- Pip bootstrap / sync for 3.11 (if available) ----------
  if [[ -n ${python_311_version} ]]; then
    # Phase 0: upgrade core tools with legacy-safe flags first
    mflibs::log "${python_311_version} -m pip install ${pip_common_base} pip>=23.1 setuptools wheel ${pip_flag_311}" || true
    # Add --root-user-action if supported now
    local pip_common_311="${pip_common_base}"
    _pip_supports_opt "${python_311_version}" "--root-user-action" && pip_common_311+=" --root-user-action=ignore"
    ${python_311_version} -m pip freeze >/tmp/pip_requirements_311.txt 2>/dev/null || true
    grep -vE '^(pip|setuptools|wheel)===' /tmp/pip_requirements_311.txt >/tmp/pip_requirements_311_nopip.txt 2>/dev/null || true
    mflibs::log "${python_311_version} -m pip install -r /tmp/pip_requirements_311_nopip.txt --extra-index-url https://www.piwheels.org/simple ${pip_common_311} ${pip_flag_311}" || true
  fi
  # ---------- Pip bootstrap / sync for 3.13 (if available) ----------
  if [[ -n ${python_313_version} ]]; then
    # Phase 0: upgrade core tools with legacy-safe flags first
    mflibs::log "${python_313_version} -m pip install ${pip_common_base} pip>=23.1 setuptools wheel ${pip_flag_313}" || true
    # Add --root-user-action if supported now
    local pip_common_313="${pip_common_base}"
    _pip_supports_opt "${python_313_version}" "--root-user-action" && pip_common_313+=" --root-user-action=ignore"
    ${python_313_version} -m pip freeze >/tmp/pip_requirements_313.txt 2>/dev/null || true
    grep -vE '^(pip|setuptools|wheel)===' /tmp/pip_requirements_313.txt >/tmp/pip_requirements_313_nopip.txt 2>/dev/null || true
    mflibs::log "${python_313_version} -m pip install -r /tmp/pip_requirements_313_nopip.txt --extra-index-url https://www.piwheels.org/simple ${pip_common_313} ${pip_flag_313}" || true
  fi
  # ---------- Pip sync for system python3 (NEVER upgrade pip) ----------
  mflibs::log "${python_version} -m pip freeze > /tmp/pip_requirements.txt" || true
  grep -vE '^(pip|setuptools|wheel)===' /tmp/pip_requirements.txt >/tmp/pip_requirements_nopip.txt 2>/dev/null || true
  local pip_common_sys="${pip_common_base}"
  mflibs::log "${python_version} -m pip install -r /tmp/pip_requirements_nopip.txt --extra-index-url https://www.piwheels.org/simple ${pip_common_sys} ${pip_flag_sys}" || true
  # Ensure baseline modules on all Python installations
  python_module_list=("pip" "wheel" "idna" "setuptools" "docopt" "virtualenv" "distro" "flit")
  for module in "${python_module_list[@]}"; do
    if [[ "${module}" == "pip" ]]; then
      # Handle pip specially - upgrade it on altinstall versions
      if [[ -n ${python_311_version} ]]; then
        local pip_common_311="${pip_common_base}"
        _pip_supports_opt "${python_311_version}" "--root-user-action" && pip_common_311+=" --root-user-action=ignore"
        mflibs::log "${python_311_version} -m pip install ${pip_common_311} pip ${pip_flag_311}" || true
      fi
      if [[ -n ${python_313_version} ]]; then
        local pip_common_313="${pip_common_base}"
        _pip_supports_opt "${python_313_version}" "--root-user-action" && pip_common_313+=" --root-user-action=ignore"
        mflibs::log "${python_313_version} -m pip install ${pip_common_313} pip ${pip_flag_313}" || true
      fi
      continue
    fi
    # Check if module is installed, install if missing
    python_module_installed=$(${python_version} -m pip list 2>/dev/null | grep -F "${module}" | sed 's/ [0-9.]*//g' | head -1)
    if [[ -z ${python_module_installed} ]]; then
      local pip_common_sys="${pip_common_base}"
      mflibs::log "${python_version} -m pip install ${pip_common_sys} ${module} ${pip_flag_sys}" || true
    fi
    # Install on Python 3.11 if available
    if [[ -n ${python_311_version} ]]; then
      python_module_installed=$(${python_311_version} -m pip list 2>/dev/null | grep -F "${module}" | sed 's/ [0-9.]*//g' | head -1)
      if [[ -z ${python_module_installed} ]]; then
        local pip_common_311="${pip_common_base}"
        _pip_supports_opt "${python_311_version}" "--root-user-action" && pip_common_311+=" --root-user-action=ignore"
        mflibs::log "${python_311_version} -m pip install ${pip_common_311} ${module} ${pip_flag_311}" || true
      fi
    fi
    # Install on Python 3.13 if available
    if [[ -n ${python_313_version} ]]; then
      python_module_installed=$(${python_313_version} -m pip list 2>/dev/null | grep -F "${module}" | sed 's/ [0-9.]*//g' | head -1)
      if [[ -z ${python_module_installed} ]]; then
        local pip_common_313="${pip_common_base}"
        _pip_supports_opt "${python_313_version}" "--root-user-action" && pip_common_313+=" --root-user-action=ignore"
        mflibs::log "${python_313_version} -m pip install ${pip_common_313} ${module} ${pip_flag_313}" || true
      fi
    fi
  done
  unset python_version python_311_version python_313_version python_module_installed python_module_list module \
    pip_common_base pip_flag_sys pip_flag_311 pip_flag_313
  mflibs::shell::text::green "Python compilation and configuration complete!"
}
