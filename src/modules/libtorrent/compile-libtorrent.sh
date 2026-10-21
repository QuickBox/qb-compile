#!/usr/bin/env bash
################################################################################
# @file_name: compile-libtorrent
# @version: 1.0.9
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
  local libtorrent_build_rev
  libtorrent_build_rev="$(qbcompile::rakshasa::build_rev "libtorrent" "${libtorrent_version}")"
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
  if [[ ${apply_patch} == "true" ]]; then
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
  # private static libcurl on hosts whose system libcurl is too old for 0.16
  local -a curl_configure_args=()
  local package_description="libtorrent (rakshasa) for rTorrent and other applications"
  if qbcompile::libcurl::bundled "${libtorrent_version}"; then
    local libtorrent_src_dir="${PWD}"
    qbcompile::compile::libcurl
    cd "${libtorrent_src_dir}" || {
      mflibs::shell::text::red "Failed to return to the libtorrent directory."
      exit 1
    }
    curl_configure_args=("LIBCURL_CFLAGS=$(qbcompile::libcurl::flags cflags)" "LIBCURL_LIBS=$(qbcompile::libcurl::flags libs)")
    package_description="libtorrent (rakshasa) for rTorrent, with libcurl ${libcurl_version} built in"
  fi
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
    "${curl_configure_args[@]}" \
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
    # the private libcurl is inside libtorrent.so, so consumers need no libcurl
    if [[ ${#curl_configure_args[@]} -gt 0 ]]; then
      sudo sed -i -E \
        -e '/^Requires\.private:/s/,[[:space:]]*libcurl//' \
        -e 's|^Libs\.private:.*$|Libs.private: -pthread|' "${pc}"
    fi
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
  if [[ ${#curl_configure_args[@]} -gt 0 ]]; then
    qbcompile::libcurl::verify "${libfile}"
    depends="$(qbcompile::libcurl::depends "${libfile}")" || exit 1
  elif command -v dpkg-shlibdeps >/dev/null 2>&1 && [[ -n "${libfile}" ]]; then
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
Description: ${package_description}
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
  qbcompile::verify::deb "${libtorrent_deb_file}"
  declare -xg libtorrent_md5_hash
  libtorrent_md5_hash=$(md5sum "${libtorrent_deb_file}" | awk '{ print $1 }')
  mflibs::shell::text::green "MD5 checksum of the created package: ${libtorrent_md5_hash}"
  cd "${temp_dir:-/opt/qb-compile/builds}" || true
  screen -S libtorrent_compile -X quit >/dev/null
}
