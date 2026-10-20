#!/usr/bin/env bash
################################################################################
# @file_name: compile-libtorrent
# @version: 1.0.11
# @project_name: qb-compile
# @description: Compilation script for libtorrent (rakshasa) for qb-compile
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
# @description: Whether the built-in EPOLL_FD_RACE_FIX applies to a libtorrent version.
#   True for the 0.16 line from 0.16.7 on (the epoll backend with the
#   PollInternal::modify() switch); 0.16.5/0.16.6 and every older line keep the
#   opt-in --patch behavior.
# @arg $1 libtorrent version (e.g. 0.16.23)
# @return 0 when the fix is applied automatically, 1 otherwise
# @example: qbcompile::libtorrent::epoll_fix_applies "0.16.23"
# @break
################################################################################
qbcompile::libtorrent::epoll_fix_applies() {
  [[ $1 == 0.16.* && $1 != 0.16.[0-6] ]]
}

################################################################################
# @description: Patch libtorrent's epoll backend so a descriptor that libcurl has
#   already closed no longer aborts rTorrent. curl closes its own sockets, so the
#   kernel has dropped them from epoll before libtorrent issues epoll_ctl on them
#   and the call fails with EBADF. EPOLL_CTL_DEL then tolerates EBADF/ENOENT and
#   EPOLL_CTL_MOD tolerates EBADF; EPOLL_CTL_ADD stays fatal. Must run from the
#   unpacked libtorrent source root. Each edit is anchored on the exact throw
#   statement and the log line above it, so a changed upstream source fails
#   instead of being edited in the wrong place.
# @noargs
# @return 0 when exactly two EPOLL_FD_RACE_FIX edits are present, 1 otherwise
# @example: qbcompile::libtorrent::epoll_fd_race_fix
# @break
################################################################################
qbcompile::libtorrent::epoll_fd_race_fix() {
  local poll_file="" candidate marker_count
  local mod_throw='epoll_ctl(MOD) error for event: " + event->print_name_fd_str() + " : " + std::string('
  local del_throw='epoll_ctl(DEL) error for event: " + event->print_name_fd_str() + " : " + std::string('
  for candidate in src/torrent/system/poll_epoll.cc src/torrent/net/poll_epoll.cc; do
    if [[ -f ${candidate} ]]; then
      poll_file="${candidate}"
      break
    fi
  done
  if [[ -z ${poll_file} ]]; then
    mflibs::shell::text::red "poll_epoll.cc not found; cannot apply EPOLL_FD_RACE_FIX."
    return 1
  fi
  marker_count=$(grep -c "EPOLL_FD_RACE_FIX" "${poll_file}" || true)
  if [[ ${marker_count} -eq 2 ]]; then
    mflibs::shell::text::green "EPOLL_FD_RACE_FIX already applied to ${poll_file}."
    return 0
  fi
  if [[ ${marker_count} -ne 0 ]] ||
    [[ $(grep -cF -- "${mod_throw}" "${poll_file}" || true) -ne 1 ]] ||
    [[ $(grep -cF -- "${del_throw}" "${poll_file}" || true) -ne 1 ]]; then
    mflibs::shell::text::red "${poll_file} does not match the expected epoll_ctl(MOD)/epoll_ctl(DEL) error handling; cannot apply EPOLL_FD_RACE_FIX."
    return 1
  fi
  mflibs::shell::text::yellow "Applying EPOLL_FD_RACE_FIX to ${poll_file}..."
  if ! awk -v mod="${mod_throw}" -v del="${del_throw}" '
    function flush() { if (have) print prev; have = 0 }
    {
      kind = index($0, mod) ? "MOD" : (index($0, del) ? "DEL" : "")
      if (kind != "") {
        if (!have || index(prev, "LT_LOG_EVENT(\"modify event EPOLL_CTL_" kind " failed: %s\"") == 0) {
          bad = 1
        } else {
          match(prev, /^[[:space:]]*/)
          ind = substr(prev, 1, RLENGTH)
          cond = (kind == "MOD") ? "errno == EBADF" : "errno == EBADF || errno == ENOENT"
          print ind "if (" cond ") { // EPOLL_FD_RACE_FIX"
          print ind "  LT_LOG_EVENT(\"modify event EPOLL_CTL_" kind " ignored for a closed descriptor: %s\", std::strerror(errno));"
          print ind "  return;"
          print ind "}"
          edits++
        }
      }
      flush()
      prev = $0
      have = 1
    }
    END { flush(); if (bad || edits != 2) exit 3 }
  ' "${poll_file}" >"${poll_file}.qbfix"; then
    rm -f "${poll_file}.qbfix"
    mflibs::shell::text::red "Unexpected layout around the epoll_ctl error handling in ${poll_file}; cannot apply EPOLL_FD_RACE_FIX."
    return 1
  fi
  cat "${poll_file}.qbfix" >"${poll_file}"
  rm -f "${poll_file}.qbfix"
  marker_count=$(grep -c "EPOLL_FD_RACE_FIX" "${poll_file}" || true)
  if [[ ${marker_count} -ne 2 ]]; then
    mflibs::shell::text::red "EPOLL_FD_RACE_FIX left ${marker_count} markers in ${poll_file}; expected 2."
    return 1
  fi
  mflibs::shell::text::green "  ✓ Applied EPOLL_CTL_DEL and EPOLL_CTL_MOD closed-descriptor handling."
}

################################################################################
# @description: Debian build revision of the libtorrent package for a version.
#   The one place this is decided: the libtorrent build and the rTorrent build
#   that links against the packaged libtorrent both call it, so they always
#   agree on the .deb file name.
# @arg $1 libtorrent version (e.g. 0.16.23)
# @output: build revision (2build1 when the epoll fix is built in, else 1build1)
# @example: qbcompile::libtorrent::build_rev "0.16.23"
# @break
################################################################################
qbcompile::libtorrent::build_rev() {
  if qbcompile::libtorrent::epoll_fix_applies "$1"; then
    echo "2build1"
  else
    echo "1build1"
  fi
}

################################################################################
# @description: Whether the built-in CURL_POLL_REMOVE_FIX applies to a libtorrent version.
#   True for the 0.16 line from 0.16.16 on, the releases whose CurlSocket has a
#   separate handle_poll_remove(); earlier 0.16 releases already clear the easy
#   handle inside receive_socket() when libcurl removes a socket.
# @arg $1 libtorrent version (e.g. 0.16.23)
# @return 0 when the fix is applied automatically, 1 otherwise
# @example: qbcompile::libtorrent::curl_poll_remove_fix_applies "0.16.23"
# @break
################################################################################
qbcompile::libtorrent::curl_poll_remove_fix_applies() {
  local patch_level
  [[ $1 == 0.16.* ]] || return 1
  patch_level="${1#0.16.}"
  [[ ${patch_level} =~ ^[0-9]+$ ]] && ((10#${patch_level} >= 16))
}

################################################################################
# @description: Patch libtorrent's libcurl socket handling so a socket that libcurl
#   removed from polling can be handed to the next transfer. After
#   CURL_POLL_REMOVE for a socket libcurl keeps open, the stale easy handle stays
#   on the CurlSocket; libcurl then reports the socket again with no owner and
#   handle_poll_new() aborts on "existing CurlSocket easy_handle not null". The
#   edit clears the easy handle and the libcurl socket pointer right after the
#   read/write polling is removed. Must run from the unpacked libtorrent source
#   root. The edit is anchored on the exact log line and the two remove calls
#   after it, so a changed upstream source fails instead of being edited in the
#   wrong place.
# @noargs
# @return 0 when exactly one CURL_POLL_REMOVE_FIX edit is present, 1 otherwise
# @example: qbcompile::libtorrent::curl_poll_remove_fix
# @break
################################################################################
qbcompile::libtorrent::curl_poll_remove_fix() {
  local curl_file="src/net/curl_socket.cc" marker_count
  local anchor='LT_LOG_DEBUG_SOCKET_FD_HANDLE("handle_poll_remove(CURL_POLL_REMOVE) : removing from read/write polling", 0);'
  if [[ ! -f ${curl_file} ]]; then
    mflibs::shell::text::red "${curl_file} not found; cannot apply CURL_POLL_REMOVE_FIX."
    return 1
  fi
  marker_count=$(grep -c "CURL_POLL_REMOVE_FIX" "${curl_file}" || true)
  if [[ ${marker_count} -eq 1 ]]; then
    mflibs::shell::text::green "CURL_POLL_REMOVE_FIX already applied to ${curl_file}."
    return 0
  fi
  if [[ ${marker_count} -ne 0 ]] || [[ $(grep -cF -- "${anchor}" "${curl_file}" || true) -ne 1 ]]; then
    mflibs::shell::text::red "${curl_file} does not match the expected handle_poll_remove() polling removal; cannot apply CURL_POLL_REMOVE_FIX."
    return 1
  fi
  mflibs::shell::text::yellow "Applying CURL_POLL_REMOVE_FIX to ${curl_file}..."
  if ! awk -v anchor="${anchor}" '
    {
      print
      if (state == 0) { if (index($0, anchor)) state = 1; next }
      if (state >= 3 || $0 ~ /^[[:space:]]*$/) next
      if (state == 1) {
        if ($0 ~ /^[[:space:]]*this_thread::poll\(\)->remove_read\(socket\);[[:space:]]*$/) state = 2
        else { bad = 1; state = 9 }
        next
      }
      if ($0 ~ /^[[:space:]]*this_thread::poll\(\)->remove_write\(socket\);[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        ind = substr($0, 1, RLENGTH)
        print ""
        print ind "// CURL_POLL_REMOVE_FIX: release the easy handle and the libcurl socket pointer"
        print ind "// so the next transfer on this socket does not find a stale owner."
        print ind "socket->m_easy_handle = nullptr;"
        print ind "curl_multi_assign(stack->handle(), fd, nullptr);"
        edits++
        state = 3
      } else { bad = 1; state = 9 }
    }
    END { if (bad || edits != 1) exit 3 }
  ' "${curl_file}" >"${curl_file}.qbfix"; then
    rm -f "${curl_file}.qbfix"
    mflibs::shell::text::red "Unexpected layout around the handle_poll_remove() polling removal in ${curl_file}; cannot apply CURL_POLL_REMOVE_FIX."
    return 1
  fi
  cat "${curl_file}.qbfix" >"${curl_file}"
  rm -f "${curl_file}.qbfix"
  marker_count=$(grep -c "CURL_POLL_REMOVE_FIX" "${curl_file}" || true)
  if [[ ${marker_count} -ne 1 ]]; then
    mflibs::shell::text::red "CURL_POLL_REMOVE_FIX left ${marker_count} markers in ${curl_file}; expected 1."
    return 1
  fi
  mflibs::shell::text::green "  ✓ Applied CURL_POLL_REMOVE easy handle reset."
}

################################################################################
# @description: Function to compile libtorrent (for rTorrent or standalone) and create a .deb package
# @noargs
# @example: qbcompile::compile::libtorrent
# @break
# shellcheck disable=SC1004
################################################################################
qbcompile::compile::libtorrent() {
  declare -xg mflibs_log_location="/opt/qb-compile/logs/libtorrent-rakshasa_compile.log"
  # rotate log + tail
  if [[ -f "${mflibs_log_location}" ]]; then
    mv "${mflibs_log_location}" "${mflibs_log_location}.1" 2>/dev/null || true
  fi
  : >"${mflibs_log_location}"
  sudo screen -dmS libtorrent_compile bash -c "tail -f ${mflibs_log_location}"
  mflibs::shell::text::white::sl "libtorrent-rakshasa compilation log: "
  mflibs::shell::text::cyan "screen -r libtorrent_compile"
  mflibs::shell::misc::nl
  mflibs::shell::text::blue "Initiating libtorrent-rakshasa compilation..."
  # storage
  declare -xg libtorrent_deb_storage
  libtorrent_deb_storage="${deb_storage}/${codename}/binary-amd64/libtorrent-rakshasa"
  mkdir -p "${libtorrent_deb_storage}"
  # version + existing
  qbcompile::get::libtorrent_version
  # The 0.16 line from 0.16.7 on is built with EPOLL_FD_RACE_FIX and ships as
  # -2build1; every other version stays -1build1.
  local libtorrent_build_rev
  libtorrent_build_rev="$(qbcompile::libtorrent::build_rev "${libtorrent_version}")"
  declare -xg libtorrent_deb_file
  libtorrent_deb_file="${libtorrent_deb_storage}/libtorrent${libtorrent_compact_version}_${libtorrent_version}-${libtorrent_build_rev}_amd64.deb"
  if ! qbcompile::check_existing_deb_or_binary "${libtorrent_deb_file}"; then
    screen -S libtorrent_compile -X quit >/dev/null
    return 0
  fi
  # workspace
  cd "${temp_dir:-/opt/qb-compile/builds}" || {
    mflibs::shell::text::red "Failed to enter temp directory."
    exit 1
  }
  rm -rf "libtorrent-${libtorrent_version}" libtorrent-*.tar.gz || true
  # If custom_libtorrent_version does not equal 'source' and no `--branch` flag is used
  if [[ ${custom_libtorrent_version} != "source" ]]; then
    qbcompile::download::libtorrent_tarball
    mflibs::log "tar -xf libtorrent-${libtorrent_version}.tar.gz" || {
      mflibs::shell::text::red "Failed to extract libtorrent tarball."
      exit 1
    }
  else
    mflibs::shell::text::blue "Cloning libtorrent-rakshasa source from GitHub..."
    git clone --branch "${preferred_branch}" --depth 1 "https://github.com/rakshasa/libtorrent.git" "libtorrent-${libtorrent_version}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || {
      mflibs::shell::text::red "Failed to clone libtorrent-rakshasa source."
      exit 1
    }
  fi
  cd "libtorrent-${libtorrent_version}" || {
    mflibs::shell::text::red "Failed to enter libtorrent directory."
    exit 1
  }
  # clean autotools
  rm -f config.cache config.log config.status Makefile
  rm -rf autom4te.cache .deps
  find . -name Makefile -delete 2>/dev/null || true
  if qbcompile::libtorrent::epoll_fix_applies "${libtorrent_version}"; then
    # Always patched: fail before configure when the source does not match.
    qbcompile::libtorrent::epoll_fd_race_fix || exit 1
  elif [[ ${apply_patch} == "true" ]]; then
    # PATCH: Fix curl socket race condition causing epoll_ctl crashes
    poll_epoll_file="src/torrent/net/poll_epoll.cc"
    if [[ -f "${poll_epoll_file}" ]]; then
      if ! grep -q "EPOLL_FD_RACE_FIX" "${poll_epoll_file}" 2>/dev/null; then
        mflibs::shell::text::yellow "Applying EPOLL_FD_RACE_FIX to ${poll_epoll_file}..."
        # Fix 1: EPOLL_CTL_DEL - ignore all errors on delete
        if grep -q "op == EPOLL_CTL_DEL && errno == ENOENT" "${poll_epoll_file}" 2>/dev/null; then
          sed -i 's/if (op == EPOLL_CTL_DEL && errno == ENOENT)/if (op == EPOLL_CTL_DEL) \/\/ EPOLL_FD_RACE_FIX/' "${poll_epoll_file}"
          mflibs::shell::text::green "  ✓ Applied EPOLL_CTL_DEL fix."
        fi
        # Fix 2: Suppress EBADF/EPERM/ENOENT before throw
        if grep -q 'if (errno || epoll_ctl(m_fd, retry, event->file_descriptor()' "${poll_epoll_file}" 2>/dev/null; then
          sed -i 's/throw internal_error(errmsg);/if (errno == EBADF || errno == EPERM || errno == ENOENT) return; \/\* EPOLL_FD_RACE_FIX \*\/ throw internal_error(errmsg);/' "${poll_epoll_file}"
          mflibs::shell::text::green "  ✓ Applied EBADF/EPERM/ENOENT suppression fix."
        fi
      else
        mflibs::shell::text::green "EPOLL_FD_RACE_FIX already applied."
      fi
    else
      mflibs::shell::text::yellow "${poll_epoll_file} not found; skipping EPOLL_FD_RACE_FIX."
    fi
  fi
  if qbcompile::libtorrent::curl_poll_remove_fix_applies "${libtorrent_version}"; then
    qbcompile::libtorrent::curl_poll_remove_fix || exit 1
  fi
  # toolchain: FORCE system compilers and a clean env to avoid GCC-13 bleed
  export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
  unset LD_LIBRARY_PATH
  export CC="/usr/bin/gcc"
  export CXX="/usr/bin/g++"
  export CFLAGS="-O2 -g"
  export CXXFLAGS="-O2 -g -Wall -pthread"
  export CPPFLAGS="-I/usr/include"
  multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
  export LDFLAGS="-L/usr/lib/${multiarch}"
  # autogen / autoreconf
  mflibs::shell::text::yellow "Using autogen.sh and configure."
  if [[ -f "./autogen.sh" ]]; then
    ./autogen.sh 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || {
      mflibs::shell::text::red "autogen.sh failed"
      exit 1
    }
  elif [[ -x "$(command -v autoreconf)" ]]; then
    autoreconf -fi 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || {
      mflibs::shell::text::red "autoreconf failed"
      exit 1
    }
  else
    mflibs::shell::text::red "Neither autogen.sh nor autoreconf available."
    exit 1
  fi
  # configure (shared libs only; system dirs)
  ./configure \
    --prefix=/usr \
    --libdir="/usr/lib/${multiarch}" \
    --disable-static \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to configure libtorrent."
    exit 1
  }
  # build
  qbcompile::build::status &
  status_pid=$!
  make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to compile libtorrent."
    exit 1
  }
  # staged install
  install_dir="${temp_dir:-/opt/qb-compile/builds}/libtorrent_install"
  rm -rf "${install_dir}"
  mkdir -p "${install_dir}"
  make install DESTDIR="${install_dir}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to install libtorrent."
    exit 1
  }
  # sanitize libtorrent.pc (strip any rogue configure-style tokens)
  pc="${install_dir}/usr/lib/${multiarch}/pkgconfig/libtorrent.pc"
  if [[ -f "${pc}" ]]; then
    sudo sed -i -E \
      -e 's/(^|[[:space:]])--(libdir|enable-shared|disable-static)[^[:space:]]*//g' \
      -e "s|^Cflags:.*$|Cflags: -I/usr/include|" \
      -e "s|^Libs:.*$|Libs: -L/usr/lib/${multiarch} -ltorrent|" "${pc}" || true
  fi
  # package dir
  installed_size=$(du -sk "${install_dir}" | awk '{print $1}')
  package_dir="${temp_dir:-/opt/qb-compile/builds}/libtorrent_package"
  rm -rf "${package_dir}"
  mkdir -p "${package_dir}/DEBIAN" "${package_dir}/usr"
  cp -a "${install_dir}/usr/." "${package_dir}/usr/"
  # ldconfig triggers (shared library best practice)
  cat >"${package_dir}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
ldconfig
exit 0
EOF
  cat >"${package_dir}/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
ldconfig
exit 0
EOF
  chmod 0755 "${package_dir}/DEBIAN/postinst" "${package_dir}/DEBIAN/prerm"
  # Depends via shlibdeps (fallback if empty). Also account for older hosts
  # where libssl3/libcrypto3 are unavailable (e.g., Debian 11). In that case
  # prefer libssl1.1 if present on the system.
  depends=""
  libfile="$(find "${package_dir}/usr/lib" -type f -name 'libtorrent.so.*' | head -n1)"
  if command -v dpkg-shlibdeps >/dev/null 2>&1 && [[ -n "${libfile}" ]]; then
    dpkg-shlibdeps -O "${libfile}" >"${package_dir}/DEBIAN/substvars" 2>/dev/null || true
    depends="$(awk -F= '/^shlibs:Depends=/{print $2}' "${package_dir}/DEBIAN/substvars" 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  fi
  if [[ -z "${depends}" ]]; then
    depends="libc6, libstdc++6, libcurl4, zlib1g, libcrypto3 | libssl3"
  fi
  # Inline resolver: if host lacks libcrypto3/libssl3 but DOES provide libssl1.1,
  # rewrite the dependency string to prefer libssl1.1 for compatibility.
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
  # control
  cat >"${package_dir}/DEBIAN/control" <<EOF
Package: libtorrent${libtorrent_compact_version}
Version: ${libtorrent_version}-${libtorrent_build_rev}
Section: libs
Priority: optional
Architecture: amd64
Maintainer: ${maintainer}
Description: libtorrent (rakshasa) for rTorrent and other applications
Depends: ${depends}
Installed-Size: ${installed_size}
EOF
  # build .deb
  qbcompile::verify::payload "${package_dir}" "libtorrent" "libtorrent.so.*"
  mflibs::shell::text::blue "Packaging libtorrent version ${libtorrent_version}..."
  qbcompile::dpkg-deb::status &
  status_pid=$!
  dpkg-deb --build "${package_dir}" "${libtorrent_deb_file}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to create libtorrent .deb package."
    exit 1
  }
  # verify
  [[ -f ${libtorrent_deb_file} ]] || {
    mflibs::shell::text::red "No .deb file found for libtorrent."
    exit 1
  }
  qbcompile::verify::deb "${libtorrent_deb_file}"
  declare -xg libtorrent_md5_hash
  libtorrent_md5_hash=$(md5sum "${libtorrent_deb_file}" | awk '{ print $1 }')
  mflibs::shell::text::green "MD5 checksum of the created package: ${libtorrent_md5_hash}"
  cd "${temp_dir:-/opt/qb-compile/builds}" || true
  screen -S libtorrent_compile -X quit >/dev/null
}
