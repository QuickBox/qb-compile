#!/usr/bin/env bash
################################################################################
# @file_name: compile-deluge
# @version: 1.0.3
# @project_name: qb-compile
# @description: Compilation script for Deluge
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

################################################################################
# @description: Compile Deluge (headless) and package it as a relocatable .deb
# @noargs
# @example: qbcompile::compile::deluge
# @break
################################################################################
# shellcheck disable=SC2120,SC2154
################################################################################
qbcompile::compile::deluge() {

  # -------------------------------------------------------------------------
  # 0. Paths, vars, log setup
  # -------------------------------------------------------------------------
  declare -xg mflibs_log_location="/opt/qb-compile/logs/deluge_compile.log"

  # Rotate old logs
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

  # Live-tail in a detached screen
  sudo screen -dmS deluge_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "Deluge compilation log: "
  mflibs::shell::text::cyan "screen -r deluge_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating compilation for Deluge..."

  # Storage path for finished .deb
  declare -xg deluge_deb_storage
  deluge_deb_storage="${deb_storage}/${codename}/binary-amd64/deluge"
  mkdir -p "${deluge_deb_storage}"

  # -------------------------------------------------------------------------
  # 1. Determine version and .deb target
  # -------------------------------------------------------------------------
  declare -xg deluge_version
  qbcompile::get::deluge_version
  if [[ -z ${deluge_version:-} ]]; then
    mflibs::shell::text::red "Unable to determine Deluge version."
    screen -S deluge_compile -X quit >/dev/null || true
    exit 1
  fi
  declare -xg deluge_deb_file
  deluge_deb_file="${deluge_deb_storage}/deluge-headless_${deluge_version}-1build1_amd64.deb"
  if ! qbcompile::check_existing_deb_or_binary "${deluge_deb_file}"; then
    # User chose not to rebuild / file exists
    screen -S deluge_compile -X quit >/dev/null || true
    return 0
  fi

  # -------------------------------------------------------------------------
  # 2. Build prerequisites
  # -------------------------------------------------------------------------
  BUILD_ROOT="${temp_dir:-/opt/qb-compile/builds}"
  BUILD_DIR="${BUILD_ROOT}/deluge-src-${deluge_version}"
  STAGING_DIR="${BUILD_ROOT}/deluge_package_root"
  ARCH="$(dpkg --print-architecture)"
  rm -rf "${BUILD_DIR}" "${STAGING_DIR}"
  mkdir -p "${BUILD_DIR}" "${STAGING_DIR}"

  mflibs::shell::text::blue "Installing Deluge build/runtime dependencies..."
  # Run apt-get update and install dependencies, logging to the deluge log file
  bash -lc 'apt-get update' >>"${mflibs_log_location}" 2>&1 || fix_broken_install
  # NOTE: intentionally NOT installing python3-libtorrent here; we depend on our own .deb
  # shellcheck disable=SC1004
  bash -lc 'DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git build-essential python3-all python3-dev python3-setuptools intltool closure-compiler \
    python3-twisted python3-openssl python3-pkg-resources python3-chardet python3-xdg \
    python3-rencode python3-six python3-mako python3-setproctitle python3-pil \
    python3-geoip geoip-database' >>"${mflibs_log_location}" 2>&1 || fix_broken_install

  # (No import-time libtorrent check here — keep Deluge build independent of local env)

  # -------------------------------------------------------------------------
  # 3. Clone source & build
  # -------------------------------------------------------------------------
  cd "${BUILD_DIR}" || {
    mflibs::shell::text::red "Failed to change to build directory: ${BUILD_DIR}"
    exit 1
  }
  mflibs::shell::text::blue "Cloning Deluge ${deluge_version}..."
  declare -a _qb_deluge_clone_tags
  if [[ -n "${deluge_tag:-}" ]]; then
    _qb_deluge_clone_tags+=("${deluge_tag}")
  fi
  _qb_deluge_clone_tags+=("deluge-${deluge_version}" "v${deluge_version}" "${deluge_version}")

  declare cloned_tag=""
  # Try tarball downloads first
  for _qb_tag in "${_qb_deluge_clone_tags[@]}"; do
    mflibs::shell::text::blue "Attempting to download Deluge release archive for tag: ${_qb_tag}"
    archive_path="${BUILD_DIR}/deluge-${_qb_tag}.tar.gz"
    if bash -lc "curl -fsSL -o '${archive_path}' 'https://github.com/deluge-torrent/deluge/archive/refs/tags/${_qb_tag}.tar.gz'" >>"${mflibs_log_location}" 2>&1 && [[ -s "${archive_path}" ]]; then
      if tar -xzf "${archive_path}" -C "${BUILD_DIR}" --strip-components=1 2>/dev/null; then
        rm -f "${archive_path}"
        cloned_tag="${_qb_tag}"
        mflibs::shell::text::green "Downloaded and extracted Deluge archive for tag: ${_qb_tag}"
        break
      else
        mflibs::shell::text::yellow "Downloaded archive for ${_qb_tag} but extraction failed; trying next candidate..."
        rm -f "${archive_path}"
      fi
    fi
  done

  # Fallback to git clone
  if [[ -z "${cloned_tag}" ]]; then
    for _qb_tag in "${_qb_deluge_clone_tags[@]}"; do
      mflibs::shell::text::blue "Attempting git clone with tag: ${_qb_tag}"
      # Try a shallow branch clone first for speed
      if git clone --branch "${_qb_tag}" --single-branch --depth 1 https://github.com/deluge-torrent/deluge.git . >>"${mflibs_log_location}" 2>&1; then
        # Ensure tags/history exist so version.py can detect the version
        if git rev-parse --is-shallow-repository >/dev/null 2>&1 && [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
          git fetch --tags origin >>"${mflibs_log_location}" 2>&1 || true
          git fetch --unshallow >>"${mflibs_log_location}" 2>&1 || true
        else
          git fetch --tags origin >>"${mflibs_log_location}" 2>&1 || true
        fi
        cloned_tag="${_qb_tag}"
        break
      fi
      # If shallow clone failed, try a full clone and checkout the tag
      if git clone https://github.com/deluge-torrent/deluge.git . >>"${mflibs_log_location}" 2>&1; then
        git checkout "${_qb_tag}" >>"${mflibs_log_location}" 2>&1 || true
        git fetch --tags origin >>"${mflibs_log_location}" 2>&1 || true
        cloned_tag="${_qb_tag}"
        break
      fi
    done
  fi

  if [[ -z "${cloned_tag}" ]]; then
    mflibs::shell::text::red "Failed to fetch Deluge source. Attempted tags: ${_qb_deluge_clone_tags[*]}"
    exit 1
  fi
  mflibs::shell::text::green "Obtained Deluge source for tag: ${cloned_tag}"

  mflibs::shell::text::blue "Building Deluge..."
  mflibs::shell::text::blue "Preparing build environment for Deluge..."

  # Probe the shipped version machinery. Some release archives lack git metadata
  # and Deluge's version.py will raise ValueError('Cannot find the version number!').
  # In that case create a tiny fallback `version.py` that returns the expected
  # ${deluge_version} so `setup.py` can run in archive-only environments.
  python3 - <<'PY' >>"${mflibs_log_location}" 2>&1
import sys
try:
    import version
    try:
        # match the usual call-site signature used by Deluge
        version.get_version(prefix='deluge-', suffix='.dev0')
        sys.exit(0)
    except Exception:
        sys.exit(2)
except Exception:
    sys.exit(2)
PY
  _qb_probe_rc=$?
  if [[ ${_qb_probe_rc} -ne 0 ]]; then
    mflibs::shell::text::yellow "Deluge source missing version metadata; installing fallback version.py"
    # Back up original if present and not already backed up
    if [[ -f version.py && ! -f version.py.orig ]]; then
      mv version.py version.py.orig 2>>"${mflibs_log_location}" || true
    fi
    cat >version.py <<EOF
def get_version(prefix='', suffix=''):
    return '${deluge_version}'
EOF
    echo "Created fallback version.py returning ${deluge_version}" >>"${mflibs_log_location}" 2>&1 || true
  fi
  # Run the build/install using the (possibly patched) version.py.
  # Use explicit execution (not mflibs::log) so commands actually run and we
  # capture their output in the deluge compile log for diagnostics.
  bash -lc 'python3 setup.py clean -a' >>"${mflibs_log_location}" 2>&1 || true
  bash -lc 'python3 setup.py build' >>"${mflibs_log_location}" 2>&1 || {
    mflibs::shell::text::red "Deluge build failed; see ${mflibs_log_location}"
    exit 1
  }
  mflibs::shell::text::blue "Installing to staging tree..."
  # Ensure staging dir exists and is writable
  mkdir -p "${STAGING_DIR}" >>"${mflibs_log_location}" 2>&1 || {
    mflibs::shell::text::red "Failed to create staging dir ${STAGING_DIR}"
    exit 1
  }
  bash -lc "python3 setup.py install --root='${STAGING_DIR}' --install-layout=deb" >>"${mflibs_log_location}" 2>&1 || {
    mflibs::shell::text::red "Deluge install to staging failed; see ${mflibs_log_location}"
    exit 1
  }
  # Log a short listing of the staging tree so we can confirm what will be packaged.
  mflibs::shell::text::blue "Staging tree top-level after install:"
  (cd "${STAGING_DIR}" && find . -maxdepth 3 -ls 2>>"${mflibs_log_location}") >>"${mflibs_log_location}" 2>&1 || true
  # -------------------------------------------------------------------------
  # 4. Strip GUI bits – headless only
  # -------------------------------------------------------------------------
  rm -f "${STAGING_DIR}/usr/bin/deluge" \
    "${STAGING_DIR}/usr/bin/deluge-gtk" || true
  rm -rf "${STAGING_DIR}"/usr/lib/python3*/dist-packages/deluge/ui/gtk* || true
  rm -f "${STAGING_DIR}/usr/share/applications/deluge.desktop" || true
  rm -f "${STAGING_DIR}/usr/share/icons/hicolor"/*/apps/deluge.png || true

  # -------------------------------------------------------------------------
  # 5. Debian control metadata
  # -------------------------------------------------------------------------
  mkdir -p "${STAGING_DIR}/DEBIAN"
  installed_size=$(du -sk "${STAGING_DIR}" | awk '{print $1}')

  # Tie Deluge explicitly to our python3-libtorrent & libtorrent-rasterbar packages
  # so Boost/Python ABI always matches across bullseye/bookworm/jammy.
  cat >"${STAGING_DIR}/DEBIAN/control" <<CONTROL
Package: deluge-headless
Version: ${deluge_version}-1build1
Architecture: ${ARCH}
Maintainer: ${maintainer}
Section: net
Priority: optional
Depends: python3 (>= 3.6), \
 python3-libtorrent (>= ${libtorrent_rasterbar_version:-1.2.0}-1build1), \
 libtorrent-rasterbar (>= ${libtorrent_rasterbar_version:-1.2.0}-1build1), \
 python3-twisted (>= 17.1), python3-openssl, python3-pkg-resources, python3-chardet, python3-xdg, \
 python3-rencode, python3-six, python3-mako, python3-setproctitle, python3-pil, \
 python3-geoip, geoip-database
Installed-Size: ${installed_size}
Description: Deluge BitTorrent client (daemon, web UI & console) — headless build
 Deluge is a full-featured BitTorrent client using libtorrent-rasterbar.
 .
 This build provides only the daemon, Web UI and console interfaces,
 suitable for headless servers. The GTK desktop UI has been removed.
CONTROL

  # -------------------------------------------------------------------------
  # 6. Build .deb & move into storage
  # -------------------------------------------------------------------------
  mflibs::shell::text::blue "Packaging .deb..."
  # Refuse to package an empty staging tree (e.g. a failed `setup.py install`).
  qbcompile::verify::payload "${STAGING_DIR}" "Deluge"
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${STAGING_DIR}" "${deluge_deb_file}" \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || { mflibs::shell::text::red "dpkg-deb failed." && exit 1; }
  qbcompile::verify::deb "${deluge_deb_file}"

  # MD5 checksum
  deluge_md5=$(md5sum "${deluge_deb_file}" | awk '{print $1}')
  mflibs::shell::text::green "Deluge package created: ${deluge_deb_file}"
  mflibs::shell::text::green "MD5 checksum: ${deluge_md5}"

  # Update local package repository index
  repo_index_dir="${deluge_deb_storage:-${deb_storage}/${codename}/binary-amd64/deluge}"
  qbcompile::update_repo_index "${repo_index_dir}" "deluge-headless" "${deluge_version:-unknown}" "deluge"

  # -------------------------------------------------------------------------
  # 7. Cleanup & exit
  # -------------------------------------------------------------------------
  cd "${BUILD_ROOT}" || true
  screen -S deluge_compile -X quit >/dev/null || true
}
