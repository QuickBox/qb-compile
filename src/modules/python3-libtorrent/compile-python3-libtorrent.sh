#!/usr/bin/env bash
################################################################################
# @file_name: compile-python3-libtorrent
# @version: 1.0.6
# @project_name: qb-compile
# @description: Compilation script for python3-libtorrent for qb-compile
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
# @description: Build libtorrent Python3 bindings and package as python3-libtorrent
# @noargs
# @example: qbcompile::compile::python3_libtorrent
# @break
################################################################################
qbcompile::compile::python3_libtorrent() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/python3-libtorrent_compile.log"
  # -------------------------
  # 0) Log + live tail
  # -------------------------
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
  sudo screen -dmS python3_libtorrent_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "python3-libtorrent compilation log: "
  mflibs::shell::text::cyan "screen -r python3_libtorrent_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating python3-libtorrent compilation..."
  # -------------------------
  # 1) Version, paths, outputs
  # -------------------------
  declare -xg libtorrent_rasterbar_deb_storage
  libtorrent_rasterbar_deb_storage="${deb_storage}/${codename}/binary-amd64/libtorrent-rasterbar"
  mkdir -p "${libtorrent_rasterbar_deb_storage}"
  qbcompile::get::libtorrent_rasterbar_version
  if [[ -z "${libtorrent_rasterbar_version:-}" ]]; then
    mflibs::shell::text::red "Unable to determine libtorrent version."
    screen -S python3_libtorrent_compile -X quit >/dev/null
    return 1
  fi
  declare -xg python3_libtorrent_deb_file
  python3_libtorrent_deb_file="${libtorrent_rasterbar_deb_storage}/python3-libtorrent_${libtorrent_rasterbar_version}-1build1_amd64.deb"
  # Respect "skip rebuild" policy
  if ! qbcompile::check_existing_deb_or_binary "${python3_libtorrent_deb_file}"; then
    screen -S python3_libtorrent_compile -X quit >/dev/null
    return 0
  fi
  BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
  SRC_DIR="${BUILD_ROOT}/libtorrent-src"
  BUILD_DIR="${BUILD_ROOT}/libtorrent-build-py"
  STAGE_DIR="${BUILD_ROOT}/libtorrent-stage-py"
  PKG_DIR="${BUILD_ROOT}/python3-libtorrent-package"
  ARCH="$(dpkg --print-architecture)"
  TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
  mkdir -p "${BUILD_ROOT}"
  # A preceding module may have left the shell's CWD inside one of the dirs about
  # to be removed; move to a dir that will still exist so the rm does not delete
  # the working directory out from under the later clone/build.
  cd "${BUILD_ROOT}" || { mflibs::shell::text::red "Failed to enter ${BUILD_ROOT}" && exit 1; }
  rm -rf "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" "${PKG_DIR}"
  mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" "${PKG_DIR}/DEBIAN"
  # -------------------------
  # 2) Distro Python + env
  # -------------------------
  if [[ -n "${preferred_python_version:-}" ]]; then
    PY3="$(command -v "python${preferred_python_version}" || true)"
    if [[ -z "${PY3}" ]]; then
      mflibs::shell::text::red "Requested Python ${preferred_python_version} not found."
      exit 1
    fi
  else
    case "${codename:-}" in
    bullseye) PY3="/usr/bin/python3.9" ;;
    jammy) PY3="/usr/bin/python3.10" ;;
    bookworm) PY3="/usr/bin/python3.11" ;;
    noble) PY3="/usr/bin/python3.12" ;;
    trixie) PY3="/usr/bin/python3.13" ;;
    *) PY3="/usr/bin/python3" ;;
    esac
    [[ -x "${PY3}" ]] || PY3="/usr/bin/python3"
  fi
  pyver="$(${PY3} -c 'import sys; print(".".join(map(str,sys.version_info[:2])))')" || {
    mflibs::shell::text::red "Failed to run ${PY3}."
    exit 1
  }
  mflibs::shell::text::blue "Using Python ${pyver} at ${PY3}"
  # Legacy tuning for bullseye (kept)
  if [[ "${codename:-}" == "bullseye" ]]; then
    qbcompile::get::gcc_version 2>/dev/null || true
    export LDFLAGS="-L/usr/local/gcc-${gcc_version:-}/lib64 -latomic"
    export CXXFLAGS="-L/usr/local/gcc-${gcc_version:-}/lib64 -latomic"
    export LD_LIBRARY_PATH="/usr/local/gcc-${gcc_version:-}/lib64:/usr/local/openssl/lib64:${LD_LIBRARY_PATH:-}"
    export PATH="/usr/local/gcc-${gcc_version:-}/bin:/usr/local/openssl/bin:${PATH}"
  fi
  # We link against system Boost (prevents ABI mismatch across hosts)
  export BOOST_ROOT="/usr"
  BOOST_LIBDIR="/usr/lib/${TRIPLET}"
  BOOST_INCLUDEDIR="/usr/include"
  # Make sure system Boost devs exist on the builder (not fatal if already there)
  mflibs::log "apt-get update"
  mflibs::log "DEBIAN_FRONTEND=noninteractive apt-get install -y libboost-python-dev libboost-system-dev libboost-chrono-dev libboost-random-dev" || fix_broken_install
  # -------------------------
  # 3) Fetch source
  # -------------------------
  mflibs::shell::text::blue "Cloning libtorrent v${libtorrent_rasterbar_version}..."
  git clone --recurse-submodules https://github.com/arvidn/libtorrent.git "${SRC_DIR}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to clone libtorrent repository."
    exit 1
  fi
  cd "${SRC_DIR}" || {
    mflibs::shell::text::red "Failed to enter ${SRC_DIR}"
    exit 1
  }
  git checkout -f "v${libtorrent_rasterbar_version}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to checkout v${libtorrent_rasterbar_version}"
    exit 1
  fi
  # -------------------------
  # 4) Configure (bindings only)
  # -------------------------
  mflibs::shell::text::blue "Configuring libtorrent (Python bindings)..."
  if [[ "${codename}" == "bullseye" ]]; then
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DBOOST_ROOT="${BOOST_ROOT}" \
      -DBoost_INCLUDE_DIR="${BOOST_INCLUDEDIR}" \
      -DBoost_LIBRARY_DIRS="${BOOST_LIBDIR}" \
      -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR:-/usr}" \
      -DCMAKE_CXX_FLAGS="-L/usr/local/gcc-${gcc_version:-}/lib64 -latomic -D_GLIBCXX_USE_CXX11_ABI=1" \
      -Dpython-bindings=ON \
      -Dpython-install-system-dir=ON \
      -DPython3_EXECUTABLE="${PY3}" \
      -Dbuild_tests=OFF 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  elif [[ "${codename}" == "bookworm" || "${codename}" == "jammy" || "${codename}" == "noble" ]]; then
    # DBoost_NO_BOOST_CMAKE=ON: bypass system 1.74 cmake config files so FindBoost.cmake
    # follows the libboost_python311.so symlink to 1.83.0 (custom package). Without this,
    # cmake links against 1.74 library while using 1.83 headers → ABI mismatch → undefined symbol.
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DBOOST_ROOT="${BOOST_ROOT}" \
      -DBOOST_INCLUDEDIR="${BOOST_INCLUDEDIR}" \
      -DBOOST_LIBRARYDIR="${BOOST_LIBDIR}" \
      -DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1 -O2" \
      -Dpython-bindings=ON \
      -Dpython-install-system-dir=ON \
      -DPython3_EXECUTABLE="${PY3}" \
      -Dbuild_tests=OFF 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
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
      -DBoost_INCLUDE_DIR="${BOOST_INCLUDEDIR}" \
      -DBoost_LIBRARY_DIRS="${BOOST_LIBDIR}" \
      -Dpython-bindings=ON \
      -Dpython-install-system-dir=ON \
      -DPython3_EXECUTABLE="${PY3}" \
      -Dbuild_tests=OFF 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  else
    # Fallback for other distros
    cmake -S . -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR="lib/${TRIPLET}" \
      -DBUILD_SHARED_LIBS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DBOOST_ROOT="${BOOST_ROOT}" \
      -DBoost_INCLUDE_DIR="${BOOST_INCLUDEDIR}" \
      -DBoost_LIBRARY_DIRS="${BOOST_LIBDIR}" \
      -Dpython-bindings=ON \
      -Dpython-install-system-dir=ON \
      -DPython3_EXECUTABLE="${PY3}" \
      -Dbuild_tests=OFF 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    cfg_rc=${PIPESTATUS[0]}
  fi
  [[ ${cfg_rc:-1} -eq 0 ]] || { mflibs::shell::text::red "Failed to configure python3-libtorrent." && exit 1; }
  # -------------------------
  # 5) Build
  # -------------------------
  mflibs::shell::text::blue "Building python3-libtorrent..."
  qbcompile::build::status &
  status_pid=$!
  jobs="$(qbcompile::build::jobs)"
  ((jobs < 1)) && jobs=1
  cmake --build "${BUILD_DIR}" -- -j"${jobs}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to build python3-libtorrent." && exit 1; }
  # -------------------------
  # 6) Install (for completeness), but don't rely on its path
  # -------------------------
  mflibs::shell::text::blue "Installing (staging) — path may vary on Debian..."
  # Best-effort staging install: the module below is collected directly from the
  # build tree, so a non-zero here is not fatal — but surface it for the log.
  sudo DESTDIR="${STAGE_DIR}" cmake --install "${BUILD_DIR}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || mflibs::shell::text::yellow "Staging install returned non-zero; continuing (module is taken from the build tree)."
  # -------------------------
  # 7) Collect the built module directly from the build tree
  #    (don’t rely on /usr vs /usr/local ambiguity)
  # -------------------------
  mflibs::shell::text::blue "Collecting built Python module from build tree..."
  shopt -s nullglob
  candidates=(
    "${BUILD_DIR}"/bindings/python/*.so
    "${BUILD_DIR}"/bindings/python/*.pyd
    "${BUILD_DIR}"/python-bindings/*.so
    "${BUILD_DIR}"/python/*.so
  )
  shopt -u nullglob
  mod_src=""
  for f in "${candidates[@]}"; do
    [[ -f "${f}" ]] || continue
    # must look like libtorrent*.so
    bn="$(basename "${f}")"
    if [[ "${bn}" == libtorrent*.so || "${bn}" == libtorrent*.pyd ]]; then
      mod_src="${f}"
      break
    fi
  done
  if [[ -z "${mod_src}" ]]; then
    mflibs::shell::text::red "Could not find built libtorrent Python module in ${BUILD_DIR}."
    mflibs::shell::text::yellow "Available files under bindings/python:"
    find "${BUILD_DIR}" -maxdepth 4 -type f -printf '  %P\n' 2>/dev/null | grep -E 'python|binding|libtorrent' || true
    exit 1
  fi
  mflibs::shell::text::green "Found module: ${mod_src}"
  # -------------------------
  # 8) Package assembly under Debian policy path
  # -------------------------
  # Debian policy location for system packages:
  PKG_SITE_DIR="${PKG_DIR}/usr/lib/python3/dist-packages"
  mkdir -p "${PKG_SITE_DIR}"
  install -m 0644 "${mod_src}" "${PKG_SITE_DIR}/"
  # Verify boost_python linkage matches headers (catch 1.74/1.83 mismatch early)
  mflibs::shell::text::blue "Checking shared library linkage..."
  ldd "${mod_src}" 2>&1 | sudo tee -a "${mflibs_log_location}"
  # Quick import test against staged package payload
  mflibs::shell::text::blue "Sanity import test (staged payload)..."
  sudo ldconfig
  LD_LIBRARY_PATH="/usr/lib/${TRIPLET}:${LD_LIBRARY_PATH:-}" \
  PYTHONPATH="${PKG_SITE_DIR}:${PYTHONPATH:-}" \
    "${PY3}" - <<'PY' || {
import importlib
m = importlib.import_module("libtorrent")
print("libtorrent Python OK; version:", getattr(m, "version", "unknown"))
PY
    mflibs::shell::text::red "Python import test failed."
    exit 1
  }
  # -------------------------
  # 9) Control file with correct runtime deps
  # -------------------------
  # Boost runtime deps: python3-libtorrent links against libboost_python at runtime
  # (unlike libtorrent-rasterbar which is boost header-only).
  # bookworm/jammy use the custom libboost-dev 1.83 package; trixie/noble have system 1.83.
  case "${codename}" in
  bullseye)
    ssl_dep="libssl1.1"
    boost_py="libboost-python1.74.0"
    ;;
  jammy | bookworm)
    ssl_dep="libssl3"
    boost_py="libboost-dev (>= 1.83.0)"
    ;;
  trixie | noble)
    ssl_dep="libssl3t64"
    boost_py="libboost-python1.83.0"
    ;;
  *)
    ssl_dep="libssl3"
    boost_py="libboost-python-dev"
    ;;
  esac
  installed_size=$(du -sk "${PKG_DIR}" | awk '{print $1}')
  cat >"${PKG_DIR}/DEBIAN/control" <<EOF
Package: python3-libtorrent
Version: ${libtorrent_rasterbar_version}-1build1
Section: python
Priority: optional
Architecture: ${ARCH}
Maintainer: ${maintainer}
Depends: python3, libc6, libstdc++6, ${ssl_dep}, ${boost_py}, libtorrent-rasterbar (>= ${libtorrent_rasterbar_version}-1build1)
Description: Python 3 bindings for libtorrent-rasterbar
Installed-Size: ${installed_size}
EOF
  # -------------------------
  # 10) Build .deb
  # -------------------------
  qbcompile::verify::payload "${PKG_DIR}" "python3-libtorrent" "libtorrent*.so"
  mflibs::shell::text::blue "Creating .deb package for python3-libtorrent..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${PKG_DIR}" "${python3_libtorrent_deb_file}" \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "Failed to create python3-libtorrent .deb package." && exit 1; }
  qbcompile::verify::deb "${python3_libtorrent_deb_file}"
  if [[ -f "${python3_libtorrent_deb_file}" ]]; then
    declare -xg python3_libtorrent_md5_hash
    python3_libtorrent_md5_hash=$(md5sum "${python3_libtorrent_deb_file}" | awk '{ print $1 }')
    mflibs::shell::text::green "Created: ${python3_libtorrent_deb_file}"
    mflibs::shell::text::green "MD5: ${python3_libtorrent_md5_hash}"
  else
    mflibs::shell::text::red "No .deb file found."
    exit 1
  fi
  # Cleanup (optional). cd out first so the module never returns with the shell's
  # CWD inside a dir it just deleted (which would break the next module's clone).
  cd "${BUILD_ROOT}" || true
  rm -rf "${SRC_DIR}" "${BUILD_DIR}" "${STAGE_DIR}" "${PKG_DIR}"
  screen -S python3_libtorrent_compile -X quit >/dev/null
}
