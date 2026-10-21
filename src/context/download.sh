#!/usr/bin/env bash
################################################################################
# @file_name: download
# @version: 1.0.13
# @project_name: qb-compile
# @description: Download context for qb-compile script
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
# @description: Download a GitHub branch or tag archive and unpack its contents
#   (without the top-level directory) into a destination directory.
# @arg $1: repository (owner/name)
# @arg $2: branch or tag
# @arg $3: destination directory
# @example: qbcompile::download::github_archive QuickBox/qb-compile main /tmp/qbcompile
# @break
################################################################################
qbcompile::download::github_archive() {
  local repo="$1" ref="$2" dest="$3" work
  [[ ${repo} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { mflibs::shell::text::red "Invalid repository: ${repo}" && return 1; }
  [[ ${ref} =~ ^[A-Za-z0-9._/-]+$ ]] || { mflibs::shell::text::red "Invalid branch or tag: ${ref}" && return 1; }
  work=$(mktemp -d -t qbcompile-archive-XXXX)
  curl -fsSL -o "${work}/archive.zip" "https://github.com/${repo}/archive/${ref}.zip" || { rm -rf "${work}" && return 1; }
  unzip -q "${work}/archive.zip" -d "${work}/unpacked" || { rm -rf "${work}" && return 1; }
  mkdir -p "${dest}"
  # GitHub archives hold a single top-level directory (<name>-<ref>)
  cp -a "${work}"/unpacked/*/. "${dest}/" || { rm -rf "${work}" && return 1; }
  rm -rf "${work}"
}

################################################################################
# @description: Function to download the latest qb-compile from GitHub. Set
#   QBCOMPILE_REPO (owner/name) and QBCOMPILE_REF (branch or tag) to use a fork.
# @noargs
# @example: qbcompile::download::qb-compile
# @break
################################################################################
qbcompile::download::qb-compile() {
  if [[ ! -d /opt/qb-compile ]]; then
    sudo mkdir -p /opt/qb-compile
  fi
  mflibs::shell::text::blue "Downloading the latest qb-compile project..."
  local tmp_dir
  tmp_dir=$(mktemp -d -t qbcompile-XXXX)
  qbcompile::download::github_archive "${QBCOMPILE_REPO:-QuickBox/qb-compile}" "${QBCOMPILE_REF:-main}" "${tmp_dir}/qb-compile" || { mflibs::shell::text::red "Failed to download qb-compile archive." && exit 1; }
  # Properly rsync the unpacked project to /opt/qb-compile
  mflibs::shell::text::blue "Deploying qb-compile to /opt/qb-compile..."
  # Install rsync if not present
  if ! command -v rsync >/dev/null 2>&1; then
    mflibs::shell::text::yellow "rsync not found. Installing rsync..."
    if ! (sudo apt-get update && sudo apt-get install -y rsync); then
      mflibs::shell::text::red "Failed to install rsync."
      exit 1
    fi
  fi
  rsync -a --exclude='.git/' "${tmp_dir}/qb-compile/" "/opt/qb-compile/" || { mflibs::shell::text::red "Failed to deploy qb-compile to /opt/qb-compile." && exit 1; }
  # Clean up
  rm -rf "${tmp_dir}"
  mflibs::shell::text::green "qb-compile downloaded to /opt/qb-compile"
}

################################################################################
# @description: Function to download the libcurl source tarball and verify its
#   signature against the curl release key (Daniel Stenberg). The key is fetched
#   from its published location, and only a good signature from the pinned
#   primary key fingerprint is accepted.
# @noargs
# @example: qbcompile::download::libcurl_tarball
# @break
################################################################################
qbcompile::download::libcurl_tarball() {
  local curl_release_fpr="27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2"
  local tarball="${temp_dir:-/opt/qb-compile/builds}/curl-${libcurl_version}.tar.xz"
  local gnupg_home status
  mflibs::shell::text::blue "Downloading libcurl ${libcurl_version} source..."
  rm -f "${tarball}" "${tarball}.asc"
  if ! curl -fsSL -o "${tarball}" "https://curl.se/download/curl-${libcurl_version}.tar.xz" ||
    ! curl -fsSL -o "${tarball}.asc" "https://curl.se/download/curl-${libcurl_version}.tar.xz.asc"; then
    mflibs::shell::text::red "Failed to download the libcurl ${libcurl_version} tarball or its signature."
    exit 1
  fi
  gnupg_home=$(mktemp -d -t qbcompile-gnupg-XXXX)
  chmod 0700 "${gnupg_home}"
  if ! curl -fsSL "https://daniel.haxx.se/mykey.asc" | gpg --batch --quiet --homedir "${gnupg_home}" --import >/dev/null 2>&1; then
    rm -rf "${gnupg_home}"
    mflibs::shell::text::red "Failed to import the curl release key."
    exit 1
  fi
  status=$(gpg --batch --homedir "${gnupg_home}" --status-fd 1 --verify "${tarball}.asc" "${tarball}" 2>/dev/null || true)
  gpgconf --homedir "${gnupg_home}" --kill all >/dev/null 2>&1 || true
  rm -rf "${gnupg_home}"
  if ! grep -q '^\[GNUPG:\] GOODSIG ' <<<"${status}" ||
    [[ $(awk '$2 == "VALIDSIG" { print $NF; exit }' <<<"${status}") != "${curl_release_fpr}" ]]; then
    mflibs::shell::text::red "libcurl ${libcurl_version} signature is not a good signature from the curl release key; refusing to build."
    exit 1
  fi
  mflibs::shell::text::green "Verified curl-${libcurl_version}.tar.xz against the curl release key."
}

################################################################################
# @description: Function to download the latest libtorrent tarball
# @noargs
# @example: qbcompile::download::libtorrent_tarball
# @break
################################################################################
qbcompile::download::libtorrent_tarball() {
  mflibs::shell::text::blue "Downloading libtorrent tarball..."
  # Set the libtorrent version
  qbcompile::get::libtorrent_version 2>&1
  # Find which rtorrent release contains this libtorrent version
  mflibs::shell::text::cyan "Searching for rtorrent release containing libtorrent ${libtorrent_version}..."
  local rtorrent_release_tag
  rtorrent_release_tag=$(curl -s https://api.github.com/repos/rakshasa/rtorrent/releases | jq -r --arg ltver "libtorrent-${libtorrent_version}.tar.gz" '.[] | select(.assets[].name == $ltver) | .tag_name' | head -n 1)
  if [[ -z "${rtorrent_release_tag}" ]]; then
    mflibs::shell::text::red "Failed to find rtorrent release containing libtorrent ${libtorrent_version}"
    mflibs::shell::text::yellow "Available libtorrent versions in rtorrent releases:"
    curl -s https://api.github.com/repos/rakshasa/rtorrent/releases | jq -r '.[] | "\(.tag_name): " + (.assets[] | select(.name | startswith("libtorrent")) | .name)' | head -20
    exit 1
  fi
  mflibs::shell::text::cyan "Found in rtorrent release: ${rtorrent_release_tag}"
  # Download from rtorrent releases
  local libtorrent_tarball_url="https://github.com/rakshasa/rtorrent/releases/download/${rtorrent_release_tag}/libtorrent-${libtorrent_version}.tar.gz"
  mflibs::shell::text::cyan "Downloading from: ${libtorrent_tarball_url}"
  wget "${libtorrent_tarball_url}" -O "${temp_dir:-/opt/qb-compile/builds}/libtorrent-${libtorrent_version}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to download libtorrent tarball."
    exit 1
  fi
  mflibs::shell::text::green "Downloaded libtorrent-${libtorrent_version}.tar.gz"
}

################################################################################
# @description: Function to download the latest stable qBittorrent tarball
# @noargs
# @example: qbcompile::download::qbittorrent_tarball
# @break
################################################################################
qbcompile::download::qbittorrent_tarball() {
  # Fetch the latest stable qBittorrent version
  if ! qbcompile::get::qbittorrent_version || [[ -z ${latest_qbittorrent_tag} ]]; then
    mflibs::shell::text::red "Failed to get the latest stable qBittorrent version." && exit 1
  fi
  [[ -d "qBittorrent-${latest_qbittorrent_tag}" ]] && rm -rf "qBittorrent-${latest_qbittorrent_tag}"
  mflibs::shell::text::blue "Downloading qBittorrent source archive for version ${latest_qbittorrent_tag}..."
  local tarball_url="https://github.com/qbittorrent/qBittorrent/archive/refs/tags/${latest_qbittorrent_tag}.tar.gz"
  curl -L -o "qBittorrent-${latest_qbittorrent_tag}.tar.gz" "${tarball_url}" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    mflibs::shell::text::red "Failed to download the qBittorrent tarball."
    exit 1
  fi
  mflibs::shell::text::green "Downloaded qBittorrent-${latest_qbittorrent_tag}.tar.gz"
  mflibs::log "tar -xzf qBittorrent-${latest_qbittorrent_tag}.tar.gz"
  cd "qBittorrent-${latest_qbittorrent_tag}" || { mflibs::shell::text::red "Failed to enter qBittorrent directory." && exit 1; }
}

################################################################################
# @description: Function to download the latest rtorrent tarball
# @noargs
# @example: qbcompile::download::rtorrent_tarball
# @break
################################################################################
qbcompile::download::rtorrent_tarball() {
  mflibs::shell::text::blue "Downloading the latest rTorrent tarball..."
  # Set the version
  qbcompile::get::rtorrent_version 2>&1
  # Define the URL for the rTorrent tarball
  local rtorrent_tarball_url="https://github.com/rakshasa/rtorrent/releases/download/v${rtorrent_version}/rtorrent-${rtorrent_version}.tar.gz"
  # Download the rTorrent tarball
  wget "${rtorrent_tarball_url}" -O "${temp_dir:-/opt/qb-compile/builds}/rtorrent-${rtorrent_version}.tar.gz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download rTorrent tarball." && exit 1; }
  mflibs::shell::text::green "Downloaded rtorrent-${rtorrent_version}.tar.gz"
}
