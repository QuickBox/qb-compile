#!/usr/bin/env bash
################################################################################
# @file_name: compile-rtorrent
# @version: 1.0.9
# @project_name: qb-compile
# @description: Compilation script for rTorrent for qb-compile
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
# @description: Function to compile rTorrent and create a .deb package
# @noargs
# @example: qbcompile::compile::rtorrent
# @break
################################################################################
qbcompile::compile::rtorrent() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/rtorrent_compile.log"
  # rotate + tail
  if [[ -f "${mflibs_log_location}" ]]; then
    mv "${mflibs_log_location}" "${mflibs_log_location}.1" 2>/dev/null || true
  fi
  : >"${mflibs_log_location}"
  sudo screen -dmS rtorrent_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "rTorrent compilation log: "
  mflibs::shell::text::cyan "screen -r rtorrent_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating rTorrent compilation..."
  # dest + version
  declare -xg rtorrent_deb_storage
  rtorrent_deb_storage="${deb_storage}/${codename}/binary-amd64/rtorrent"
  mkdir -p "${rtorrent_deb_storage}"
  qbcompile::get::libtorrent_version 2>&1
  qbcompile::get::rtorrent_version
  # Build revision. 0.16.11 carries the backported SCGI trust-flag reset, so it
  # ships as -2build1; every other version stays -1build1.
  local rtorrent_build_rev="1build1"
  [[ ${rtorrent_version} == "0.16.11" ]] && rtorrent_build_rev="2build1"
  declare -xg rtorrent_deb_file
  rtorrent_deb_file="${rtorrent_deb_storage}/rtorrent_${rtorrent_version}-${rtorrent_build_rev}_amd64.deb"
  if ! qbcompile::check_existing_deb_or_binary "${rtorrent_deb_file}"; then
    screen -S rtorrent_compile -X quit >/dev/null
    return 0
  fi
  # workspace
  cd "${temp_dir:-/opt/qb-compile/builds}" || {
    mflibs::shell::text::red "Failed to enter temp directory."
    exit 1
  }
  rm -rf rtorrent-* || true
  qbcompile::download::rtorrent_tarball
  mflibs::log "tar -xf rtorrent-${rtorrent_version}.tar.gz" || {
    mflibs::shell::text::red "Failed to extract rTorrent source."
    exit 1
  }
  cd "rtorrent-${rtorrent_version}" || {
    mflibs::shell::text::red "Failed to enter rTorrent directory."
    exit 1
  }
  # clean autotools
  rm -f config.cache config.log config.status Makefile
  rm -rf autom4te.cache .deps
  find . -name Makefile -delete 2>/dev/null || true
  # Backport the upstream SCGI trust-flag reset (commit 9811845) onto stable
  # 0.16.11 ONLY. Pooled SCgiTask slots are reused round-robin and m_trusted is
  # set once at construction, so the first UNTRUSTED_CONNECTION=1 request poisons
  # a slot for the life of the process. Reset trust on reuse. Idempotent via the
  # marker grep, sed against the real source.
  if [[ ${rtorrent_version} == "0.16.11" ]]; then
    scgi_task_file="src/rpc/scgi_task.cc"
    if [[ -f "${scgi_task_file}" ]]; then
      if ! grep -q "SCGI_TRUST_RESET_FIX" "${scgi_task_file}" 2>/dev/null; then
        mflibs::shell::text::yellow "Applying SCGI_TRUST_RESET_FIX to ${scgi_task_file}..."
        # (a) reset the reuse flag to trusted in open()
        if grep -q "m_accepts_compression = false;" "${scgi_task_file}" 2>/dev/null; then
          sed -i 's|\(  m_accepts_compression = false;\)|\1\n\n  m_trusted             = true;  // SCGI_TRUST_RESET_FIX: reset trust on pooled task reuse|' "${scgi_task_file}"
          mflibs::shell::text::green "  ✓ Applied open() trust reset."
        fi
        # (b) make the UNTRUSTED_CONNECTION=0 branch an explicit reset
        if grep -qF '; // Default is trusted, so do nothing.' "${scgi_task_file}" 2>/dev/null; then
          sed -i 's|        ; // Default is trusted, so do nothing.|        m_trusted = true;  // SCGI_TRUST_RESET_FIX: explicit reset on header value 0|' "${scgi_task_file}"
          mflibs::shell::text::green "  ✓ Applied UNTRUSTED_CONNECTION=0 explicit reset."
        fi
      else
        mflibs::shell::text::green "SCGI_TRUST_RESET_FIX already applied."
      fi
    else
      mflibs::shell::text::yellow "${scgi_task_file} not found; skipping SCGI_TRUST_RESET_FIX."
    fi
  fi
  # toolchain: FORCE system compilers & clean env (avoids GLIBCXX drift)
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  unset LD_LIBRARY_PATH
  export CC="/usr/bin/gcc"
  export CXX="/usr/bin/g++"
  export CFLAGS="-O2 -g"
  export CXXFLAGS="-O2 -g -Wall -pthread"
  export CPPFLAGS="-I/usr/include"
  multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
  export LDFLAGS="-L/usr/lib/${multiarch}"
  # Prefer freshly built libtorrent if it exists (staged install)
  staged_root="${temp_dir:-/opt/qb-compile/builds}/libtorrent_install"
  staged_pc="${staged_root}/usr/lib/${multiarch}/pkgconfig"
  staged_lt_libdir="${staged_root}/usr/lib/${multiarch}"
  staged_lt_incdir="${staged_root}/usr/include"
  sys_pc="/usr/lib/${multiarch}/pkgconfig"
  # When the paired libtorrent build was SKIPPED (its .deb already existed),
  # nothing is staged under builds/libtorrent_install and nothing is installed
  # system-wide, so rTorrent would compile against absent headers. Guarantee the
  # dep is present by installing the packaged libtorrent .deb. The rakshasa libs
  # use per-version package NAMES (libtorrent155/156/157) whose files overlap, so
  # purge any conflicting version before installing.
  if [[ ! -d "${staged_lt_incdir}/torrent" ]]; then
    lt_pkg="libtorrent${libtorrent_compact_version}"
    if ! dpkg-query -W -f='${db:Status-Abbrev}' "${lt_pkg}" 2>/dev/null | grep -q '^ii'; then
      lt_deb="${deb_storage}/${codename}/binary-amd64/libtorrent-rakshasa/${lt_pkg}_${libtorrent_version}-1build1_amd64.deb"
      if [[ -f "${lt_deb}" ]]; then
        mflibs::shell::text::blue "Installing packaged ${lt_pkg} for the rTorrent link..."
        qbcompile::verify::deb "${lt_deb}"
        # The rakshasa libtorrent packages use per-version names (libtorrent156,
        # libtorrent157, ...) that all ship the same headers, so any other one left
        # installed makes the dpkg -i below fail with a file-overwrite conflict.
        # Purge each installed one INDIVIDUALLY: a single apt remove across name
        # patterns is all-or-nothing, so one pattern that matches no package aborts
        # the batch and removes nothing.
        while read -r conflicting_pkg; do
          [[ -n "${conflicting_pkg}" ]] || continue
          dpkg --purge "${conflicting_pkg}" >/dev/null 2>&1 ||
            dpkg --purge --force-depends "${conflicting_pkg}" >/dev/null 2>&1 || true
        done < <(dpkg-query -W -f='${Package}\n' 'libtorrent*' 2>/dev/null | grep -E '^libtorrent[0-9]+$')
        ldconfig || true
        dpkg -i "${lt_deb}" || { mflibs::shell::text::red "Failed to install ${lt_pkg}." && exit 1; }
      else
        mflibs::shell::text::red "libtorrent not staged or installed and no packaged .deb found; compile it first: ${script_name} --libtorrent --libtorrent-version ${libtorrent_version}" && exit 1
      fi
    fi
  fi
  export PKG_CONFIG_PATH=""
  [[ -d "${staged_pc}" ]] && PKG_CONFIG_PATH+="${staged_pc}:"
  PKG_CONFIG_PATH+="${sys_pc}:/usr/share/pkgconfig"
  # Make the linker and runtime prefer staged libtorrent first
  if [[ -d "${staged_lt_libdir}" ]]; then
    export LDFLAGS="-L${staged_lt_libdir} ${LDFLAGS}"
    export LD_LIBRARY_PATH="${staged_lt_libdir}:${LD_LIBRARY_PATH:-}"
  fi
  # The staged .pc reports includedir=/usr/include (the DESTDIR install keeps the
  # prefix), so pkg-config aims the compiler at the system headers. On a clean
  # host with no system libtorrent that misses torrent/*.h; put the staged include
  # dir ahead of the system paths so the freshly built headers win.
  if [[ -d "${staged_lt_incdir}/torrent" ]]; then
    export CPPFLAGS="-I${staged_lt_incdir} ${CPPFLAGS:-}"
  fi
  # autogen / autoreconf
  if [[ -f autogen.sh && ! -f configure ]]; then
    ./autogen.sh 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || {
      mflibs::shell::text::red "autogen.sh failed"
      exit 1
    }
  elif [[ -x "$(command -v autoreconf)" && ! -f configure ]]; then
    autoreconf -fi 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || {
      mflibs::shell::text::red "autoreconf failed"
      exit 1
    }
  fi
  # read clean libtorrent flags (strip any polluted tokens defensively)
  _strip_bad() { sed -E 's/(^|[[:space:]])--(libdir|enable-shared|disable-static)[^[:space:]]*//g' | xargs; }
  LT_CFLAGS="$(pkg-config --cflags libtorrent 2>/dev/null | _strip_bad || true)"
  LT_LIBS="$(pkg-config --libs libtorrent 2>/dev/null | _strip_bad || true)"
  [[ -z "${LT_CFLAGS}" ]] && LT_CFLAGS="-I/usr/include"
  [[ -z "${LT_LIBS}" ]] && LT_LIBS="-L/usr/lib/${multiarch} -ltorrent"
  # Ensure staged libdir is first if available
  if [[ -d "${staged_lt_libdir}" ]]; then
    LT_LIBS="-L${staged_lt_libdir} ${LT_LIBS}"
  fi
  # configure (system dirs; xmlrpc tinyxml2 + ncurses)
  mflibs::shell::text::blue "Configuring rTorrent with xmlrpc-tinyxml2 and ncurses..."
  CPPFLAGS="${CPPFLAGS} ${LT_CFLAGS}" \
    CXXFLAGS="${CXXFLAGS} ${LT_CFLAGS}" \
    ./configure \
    --prefix=/usr \
    --libdir="/usr/lib/${multiarch}" \
    --with-xmlrpc-tinyxml2 \
    --with-ncurses \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "configure failed"
    exit 1
  }
  # scrub any leaked configure-style tokens (belt-and-suspenders)
  sudo sed -i -E \
    -e 's/(^|[[:space:]])--libdir=[^[:space:]]+//g' \
    -e 's/(^|[[:space:]])--enable-shared//g' \
    -e 's/(^|[[:space:]])--disable-static([[:space:]]|$)//g' \
    -e 's|--disable-static/([[:alnum:]_.\-/]+)|/\1|g' \
    Makefile src/Makefile 2>/dev/null || true
  # --- IMPORTANT: temporarily disable any libtorrent.la so libtool uses .so (not stale .la) ---
  _disabled_las=()
  _maybe_disable_la() {
    local f="$1"
    [[ -f "${f}" ]] || return 0
    sudo mv "${f}" "${f}.qbdisabled" && _disabled_las+=("${f}.qbdisabled")
  }
  # candidates: staged, pkg-config libdir, common system paths
  lt_pkg_libdir="$(pkg-config --variable=libdir libtorrent 2>/dev/null || echo "/usr/lib/${multiarch}")"
  _maybe_disable_la "${staged_lt_libdir%/}/libtorrent.la"
  _maybe_disable_la "${lt_pkg_libdir%/}/libtorrent.la"
  _maybe_disable_la "/usr/lib/${multiarch}/libtorrent.la"
  _maybe_disable_la "/usr/local/lib/${multiarch}/libtorrent.la"
  _restore_las() {
    local b
    for b in "${_disabled_las[@]}"; do
      if [[ -f "${b}" ]]; then
        sudo mv "${b}" "${b%.qbdisabled}"
      fi
    done
  }
  # link helper libs (curl/z/crypto/pthread + ncursesw/tinfo) to avoid late undefined refs
  NC_LIBS="$(pkg-config --libs ncursesw 2>/dev/null || echo '-lncursesw -ltinfo')"
  ALL_LIBS="${NC_LIBS} ${LT_LIBS} -lcurl -lz -lcrypto -lpthread"
  # build
  qbcompile::build::status &
  status_pid=$!
  make LIBS="${ALL_LIBS}" -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    kill "${status_pid}" >/dev/null 2>&1 || true
    _restore_las
    mflibs::shell::text::red "Failed to build rTorrent."
    exit 1
  fi
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  # re-enable any .la we sidelined
  _restore_las
  # staged install
  install_dir="${temp_dir:-/opt/qb-compile/builds}/rtorrent_install"
  rm -rf "${install_dir}"
  mkdir -p "${install_dir}"
  make DESTDIR="${install_dir}" install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "Install to staging failed"
    exit 1
  }
  # package
  installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
  package_dir="${temp_dir:-/opt/qb-compile/builds}/rtorrent_package"
  rm -rf "${package_dir}"
  mkdir -p "${package_dir}/DEBIAN" "${package_dir}/usr"
  cp -a "${install_dir}/usr/." "${package_dir}/usr/"
  # Depends (prefer shlibdeps). Also handle older hosts that only provide
  # libssl1.1 instead of libssl3/libcrypto3.
  depends=""
  if command -v dpkg-shlibdeps >/dev/null 2>&1 && [[ -x "${package_dir}/usr/bin/rtorrent" ]]; then
    dpkg-shlibdeps -O "${package_dir}/usr/bin/rtorrent" >"${package_dir}/DEBIAN/substvars" 2>/dev/null || true
    depends="$(awk -F= '/^shlibs:Depends=/{print $2}' "${package_dir}/DEBIAN/substvars" 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  fi
  if [[ -z "${depends}" ]]; then
    depends="libtorrent${libtorrent_compact_version}, libcurl4, zlib1g, libcrypto3 | libssl3, libtinfo6, libncursesw6"
  fi
  _resolve_ssl_fallback() {
    local _d="$1"
    local cand_crypto cand_ssl cand_ssl11
    cand_crypto="$(apt-cache policy libcrypto3 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    cand_crypto="${cand_crypto:-(none)}"
    cand_ssl="$(apt-cache policy libssl3 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    cand_ssl="${cand_ssl:-(none)}"
    cand_ssl11="$(apt-cache policy libssl1.1 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    cand_ssl11="${cand_ssl11:-(none)}"
    if [[ "${cand_crypto}" == "(none)" && "${cand_ssl}" == "(none)" && "${cand_ssl11}" != "(none)" ]]; then
      _d="$(printf '%s' "${_d}" | sed -E 's/libcrypto3 \| libssl3/libssl1.1/g; s/libssl3/libssl1.1/g; s/libcrypto3/libssl1.1/g')"
    fi
    printf '%s' "${_d}"
  }
  depends="$(_resolve_ssl_fallback "${depends}")"
  cat >"${package_dir}/DEBIAN/control" <<EOF
Package: rtorrent
Version: ${rtorrent_version}-${rtorrent_build_rev}
Section: net
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: rTorrent - A BitTorrent client for the command line
Depends: ${depends}
Installed-Size: ${installed_size}
EOF
  qbcompile::verify::payload "${package_dir}" "rTorrent" "rtorrent"
  mflibs::shell::text::blue "Packaging rTorrent version ${rtorrent_version}..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${package_dir}" "${rtorrent_deb_storage}/rtorrent_${rtorrent_version}-${rtorrent_build_rev}_amd64.deb" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to create rTorrent .deb package."
    exit 1
  }
  rtorrent_deb_file=$(find "${rtorrent_deb_storage}/" -maxdepth 1 -type f -name "rtorrent*.deb" | head -n 1)
  [[ -z ${rtorrent_deb_file} ]] && {
    mflibs::shell::text::red "No .deb file found for rTorrent."
    exit 1
  }
  qbcompile::verify::deb "${rtorrent_deb_file}"
  declare -xg rtorrent_md5_hash
  rtorrent_md5_hash=$(md5sum "${rtorrent_deb_file}" | awk '{ print $1 }')
  mflibs::shell::text::green "MD5 checksum of the created package: ${rtorrent_md5_hash}"
  cd "${temp_dir:-/opt/qb-compile/builds}" || true
  screen -S rtorrent_compile -X quit >/dev/null
}
