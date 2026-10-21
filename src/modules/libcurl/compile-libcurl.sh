#!/usr/bin/env bash
################################################################################
# @file_name: compile-libcurl
# @version: 1.0.1
# @project_name: qb-compile
# @description: Private static libcurl for the libtorrent (rakshasa) 0.16 builds
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
# @description: Whether a libtorrent (rakshasa) version is built with a private
#   static libcurl on this host. libtorrent 0.16 runs libcurl on its network
#   thread and aborts on the libcurl shipped by Ubuntu 22.04 (7.81.0) and
#   Ubuntu 24.04 (8.5.0), so those hosts get a current libcurl linked into
#   libtorrent.so itself. The system libcurl is left untouched.
# @arg $1 libtorrent version (e.g. 0.16.23)
# @return: 0 when the private libcurl is built in, 1 otherwise
# @example: qbcompile::libcurl::bundled "0.16.23"
# @break
################################################################################
qbcompile::libcurl::bundled() {
  [[ $1 == 0.16.* ]] || return 1
  [[ ${codename} == "jammy" || ${codename} == "noble" ]]
}

################################################################################
# @description: Debian build revision of a libtorrent (rakshasa) or rTorrent
#   package. The libtorrent and rTorrent builds both call it, so a pair always
#   agrees on its file names. rTorrent 0.16.11 carries the backported SCGI
#   trust-flag reset (2build1). A pair with the private libcurl built in moves
#   both packages above the highest revision the pair shipped without it, by the
#   libcurl package generation, so each new libcurl pin gets a new revision.
# @arg $1 package (libtorrent or rtorrent)
# @arg $2 version (e.g. 0.16.23)
# @output: build revision (e.g. 1build1)
# @example: qbcompile::rakshasa::build_rev "rtorrent" "0.16.11"
# @break
################################################################################
qbcompile::rakshasa::build_rev() {
  local package="$1" version="$2" rtorrent_rev=1
  [[ ${version} == "0.16.11" ]] && rtorrent_rev=2
  if qbcompile::libcurl::bundled "${version}"; then
    qbcompile::get::libcurl_version >/dev/null
    echo "$((rtorrent_rev + libcurl_generation))build1"
  elif [[ ${package} == "rtorrent" ]]; then
    echo "${rtorrent_rev}build1"
  else
    echo "1build1"
  fi
}

################################################################################
# @description: Build libcurl as a static, position-independent archive for
#   linking into libtorrent.so. It uses the Debian feature set (OpenSSL,
#   threaded resolver, nghttp2, zlib, brotli, zstd, idn2, psl) and the system CA
#   store, and installs into a private prefix under the build directory, never
#   into the system. A finished build of the same version is reused.
# @noargs
# @global: libcurl_prefix (set to the private install prefix)
# @example: qbcompile::compile::libcurl
# @break
################################################################################
qbcompile::compile::libcurl() {
  qbcompile::get::libcurl_version
  declare -xg libcurl_prefix
  libcurl_prefix="${temp_dir:-/opt/qb-compile/builds}/libcurl_static"
  if [[ -f "${libcurl_prefix}/lib/libcurl.a" && $(cat "${libcurl_prefix}/.qbcompile-version" 2>/dev/null) == "${libcurl_version}" ]]; then
    mflibs::shell::text::green "Reusing the static libcurl ${libcurl_version} build."
    return 0
  fi
  mflibs::shell::text::blue "Building static libcurl ${libcurl_version} for libtorrent..."
  local build_root="${temp_dir:-/opt/qb-compile/builds}" rc status_pid
  cd "${build_root}" || {
    mflibs::shell::text::red "Failed to enter temp directory."
    exit 1
  }
  rm -rf "curl-${libcurl_version}" "${libcurl_prefix}"
  qbcompile::download::libcurl_tarball
  mflibs::log "tar -xJf curl-${libcurl_version}.tar.xz" || {
    mflibs::shell::text::red "Failed to extract the libcurl tarball."
    exit 1
  }
  cd "curl-${libcurl_version}" || {
    mflibs::shell::text::red "Failed to enter the libcurl directory."
    exit 1
  }
  env PATH="/usr/sbin:/usr/bin:/sbin:/bin" CC="/usr/bin/gcc" CFLAGS="-O2 -g -fPIC" CPPFLAGS="" LDFLAGS="" \
    ./configure \
    --prefix="${libcurl_prefix}" \
    --disable-shared --enable-static --with-pic \
    --disable-dependency-tracking --enable-symbol-hiding \
    --enable-threaded-resolver --disable-ares \
    --with-openssl --with-nghttp2 --with-zlib --with-brotli --with-zstd \
    --with-libidn2 --with-libpsl \
    --with-ca-path=/etc/ssl/certs --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
    --disable-ldap --disable-ldaps --without-libssh2 --without-libssh \
    --without-librtmp --without-gssapi --without-ngtcp2 --without-nghttp3 \
    --disable-manual --disable-docs \
    2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to configure libcurl."
    exit 1
  }
  qbcompile::build::status &
  status_pid=$!
  make -j"$(qbcompile::build::jobs)" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  rc=${PIPESTATUS[0]}
  wait "${status_pid}"
  kill "${status_pid}" >/dev/null 2>&1 || true
  [[ ${rc} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to compile libcurl."
    exit 1
  }
  make install 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || {
    mflibs::shell::text::red "Failed to install libcurl into ${libcurl_prefix}."
    exit 1
  }
  # libtool would follow the .la to the archive's own link line; the static
  # archive alone is what libtorrent links.
  rm -f "${libcurl_prefix}/lib/libcurl.la"
  [[ -f "${libcurl_prefix}/lib/libcurl.a" && ! -e "${libcurl_prefix}/lib/libcurl.so" ]] || {
    mflibs::shell::text::red "Static libcurl archive missing from ${libcurl_prefix}/lib."
    exit 1
  }
  echo "${libcurl_version}" >"${libcurl_prefix}/.qbcompile-version"
  cd "${build_root}" || true
  mflibs::shell::text::green "Static libcurl ${libcurl_version} ready."
}

################################################################################
# @description: Compiler and linker flags that link the private static libcurl
#   into libtorrent.so. Every libcurl symbol stays local to the library (only
#   the libcurl archive is excluded from the export table; libtorrent's own
#   code also reaches the link as archives, and its API must stay exported), and
#   curl_version is kept in the link so the library carries the libcurl/X.Y.Z
#   version string that QuickBox reads to report the libcurl in use.
# @arg $1 cflags or libs
# @output: the flags
# @example: qbcompile::libcurl::flags libs
# @break
################################################################################
qbcompile::libcurl::flags() {
  # curl-config names only libcurl's direct dependencies; pkg-config --static
  # would also pull the static-only dependencies of the shared libraries.
  local curl_config="${libcurl_prefix}/bin/curl-config"
  case "$1" in
  cflags) "${curl_config}" --cflags ;;
  libs) echo "-Wl,--exclude-libs,libcurl.a -Wl,--undefined=curl_version $("${curl_config}" --static-libs)" ;;
  esac
}

################################################################################
# @description: Confirm a built libtorrent.so carries the private libcurl: no
#   libcurl.so NEEDED entry, no curl symbol exported or left undefined, the
#   libtorrent API still exported, and the libcurl/X.Y.Z version string of the
#   bundled release.
# @arg $1 path to libtorrent.so.*
# @return: 0 when all checks pass, hard-exits 1 otherwise
# @example: qbcompile::libcurl::verify "${libfile}"
# @break
################################################################################
qbcompile::libcurl::verify() {
  local libfile="$1" exported undefined literal
  if objdump -p "${libfile}" | awk '$1 == "NEEDED" { print $2 }' | grep -q '^libcurl'; then
    mflibs::shell::text::red "${libfile##*/} still links the system libcurl."
    exit 1
  fi
  exported=$(nm -D --defined-only "${libfile}" | grep -c 'curl_' || true)
  undefined=$(nm -D --undefined-only "${libfile}" | grep -c 'curl_' || true)
  if [[ ${exported} -ne 0 || ${undefined} -ne 0 ]]; then
    mflibs::shell::text::red "${libfile##*/} has ${exported} exported and ${undefined} undefined curl symbols; expected none."
    exit 1
  fi
  if ! nm -D --defined-only "${libfile}" | grep -q ' _ZN7torrent10log_groupsE$'; then
    mflibs::shell::text::red "${libfile##*/} no longer exports the libtorrent API."
    exit 1
  fi
  literal=$(strings -a "${libfile}" | grep -oE 'libcurl/[0-9]+\.[0-9]+\.[0-9]+' | sort -u)
  if [[ ${literal} != "libcurl/${libcurl_version}" ]]; then
    mflibs::shell::text::red "${libfile##*/} carries '${literal:-no libcurl version}', expected libcurl/${libcurl_version}."
    exit 1
  fi
  mflibs::shell::text::green "${libfile##*/}: libcurl ${libcurl_version} built in, no system libcurl linked."
}

################################################################################
# @description: Runtime Depends for a shared library, read from its NEEDED
#   entries and resolved to the installed package that owns each one, so the
#   names match the host release (t64 names on Ubuntu 24.04).
# @arg $1 path to the shared library
# @output: comma separated package list
# @example: qbcompile::libcurl::depends "${libfile}"
# @break
################################################################################
qbcompile::libcurl::depends() {
  local libfile="$1" multiarch soname pkg
  local -a pkgs=()
  multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
  while read -r soname; do
    pkg=$(dpkg -S "*/${multiarch}/${soname}" 2>/dev/null | grep -v '^diversion' | head -n 1 | cut -d: -f1)
    [[ -n ${pkg} ]] || {
      mflibs::shell::text::red "No installed package provides ${soname} for ${libfile##*/}."
      exit 1
    }
    pkgs+=("${pkg}")
  done < <(objdump -p "${libfile}" | awk '$1 == "NEEDED" { print $2 }')
  printf '%s\n' "${pkgs[@]}" | sort -u | paste -sd, - | sed 's/,/, /g'
}
