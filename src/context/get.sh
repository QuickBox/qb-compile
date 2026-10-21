#!/usr/bin/env bash
################################################################################
# @file_name: get
# @version: 1.0.17
# @project_name: qb-compile
# @description: Get context for qb-compile script
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
# @description: Function to get the latest version of qb-compile
# @noargs
# @output: Latest version of qb-compile
# @example: qbcompile::get::latest_version
# @break
################################################################################
qbcompile::get::latest_version() {
  # Get the latest version of the script
  mflibs::shell::text::blue "Checking for updates..."
  # Read the version from the main script on GitHub
  local latest_version
  latest_version=$(curl -fsSL "https://raw.githubusercontent.com/${QBCOMPILE_REPO:-QuickBox/qb-compile}/${QBCOMPILE_REF:-main}/qb-compile.sh" | grep -m 1 -oP '# @version:\s*\K[0-9.]+') || { mflibs::shell::text::red "Failed to extract version from qb-compile script." && exit 1; }
  # Get the current script version
  script_version=$(grep -m 1 -oP '# @version:\s*\K[0-9.]+' "${script_path}" || { mflibs::shell::text::red "Failed to extract version from qb-compile script." && exit 1; })
  # Check if the latest version is available
  if [[ -n ${latest_version} ]]; then
    mflibs::shell::text::white::sl "Latest version: "
    mflibs::shell::text::green::bold "${latest_version}"
    mflibs::shell::text::white::sl "Current version: "
    mflibs::shell::text::green::bold "${script_version}"
    mflibs::shell::misc::nl
    if [[ ${latest_version} != "${script_version}" ]]; then
      mflibs::shell::text::yellow "A new version of the script is available."
      # Update the script
      qbcompile::update
      mflibs::shell::misc::nl
    else
      mflibs::shell::text::green "You are running the latest version of the script."
      mflibs::shell::misc::nl
    fi
  else
    mflibs::shell::text::yellow "Failed to get the latest version."
    mflibs::shell::misc::nl
  fi
}

################################################################################
# @description: Function to get the latest stable version of CMake from GitHub
# @return: latest cmake version as a string
# @example: qbcompile::get::cmake_version
# @break
################################################################################
qbcompile::get::cmake_version() {
  mflibs::shell::text::blue "Fetching the latest stable CMake version..."
  # Use GitHub API to fetch release versions and filter out beta/rc versions
  cmake_version=$(curl -s https://api.github.com/repos/Kitware/CMake/releases | jq -r '.[].tag_name' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  declare -xg cmake_version
  # Remove leading 'v' from the version string
  cmake_version="${cmake_version#v}"
  if [[ -z ${cmake_version} ]]; then
    mflibs::shell::text::red "Failed to fetch the latest CMake version from GitHub."
    exit 1
  fi
  mflibs::shell::text::green "Latest CMake version: ${cmake_version}"
}

################################################################################
# Backwards-compatible shim: populate global deluge_version
# Older legacy calls use `qbcompile::get::deluge_version` but modern code
# exposes `qbcompile::utils::get::deluge_version`. Provide a small shim that
# prefers the modern function and falls back to config/versions files.
# @noargs
# @example: qbcompile::get::deluge_version
# @return: deluge_version global variable
# @break
################################################################################
qbcompile::get::deluge_version() {
  # Simple strategy: prefer modern helper, then DELUGE_VERSION env var,
  # then query GitHub releases for the latest tag, finally fall back to
  # the bundled versions file in the repo if present.
  if declare -F qbcompile::utils::get::deluge_version >/dev/null 2>&1; then
    qbcompile::utils::get::deluge_version && return 0 || return $?
  fi
  if [[ -n "${DELUGE_VERSION:-}" ]]; then
    deluge_version="${DELUGE_VERSION}"
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    local raw_tags sel_line sel_norm sel_raw
    raw_tags=$(curl -fsS --max-time 10 "https://api.github.com/repos/deluge-torrent/deluge/tags" 2>/dev/null | grep -Po '"name"\s*:\s*"\K[^" ]+' || true)
    # Build a list of normalized<TAB>raw, exclude pre-release/dev tags, sort by normalized and pick last
    sel_line=$(printf '%s\n' "${raw_tags}" | grep -Ei -v 'dev|alpha|beta|rc' | awk '{raw=$0; norm=$0; sub(/^v/,"",norm); sub(/^deluge-/,"",norm); print norm "\t" raw}' | sort -t$'\t' -k1,1V | tail -n1 || true)
    if [[ -n "${sel_line}" ]]; then
      sel_norm=$(printf '%s' "${sel_line}" | cut -f1)
      sel_raw=$(printf '%s' "${sel_line}" | cut -f2)
      deluge_version=${sel_norm}
      declare -xg deluge_tag=${sel_raw}
      return 0
    fi
  fi
  local vf
  vf="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0}}")" 2>/dev/null && pwd -P)/../src/lib/qbcompile/utils/versions.sh"
  if [[ -f "${vf}" ]]; then
    local ver
    ver=$(sed -nE 's/.*deluge_version\s*=\s*"([^"]+)".*/\1/p' "${vf}" | head -n1 || true)
    if [[ -n "${ver}" ]]; then
      declare -xg deluge_version="${ver}"
      return 0
    fi
  fi
  return 1
}

################################################################################
# @description: Function to get the latest stable version of gcc from the official GNU mirror
# @return: latest gcc version as a string
# @example: qbcompile::get::gcc_version
# @break
################################################################################
qbcompile::get::gcc_version() {
  mflibs::shell::text::blue "Fetching the latest stable GCC version..."
  # Check the current GCC version, if gcc --version is less than 13.2.0, then fetch the latest version
  #declare -xg current_gcc_version
  #current_gcc_version=$(gcc --version | head -n 1 | grep -oP 'gcc \([A-Za-z]+ \K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)
  declare -xg gcc_version #gcc_version_path gcc_version_major
  #if [[ -n ${current_gcc_version} ]] && dpkg --compare-versions "${current_gcc_version}" lt "13.2.0"; then
  # Use the GNU mirror to fetch the latest GCC version
  #gcc_version=$(curl -s https://ftp.gnu.org/gnu/gcc/ | grep -oP 'gcc-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)
  gcc_version="13.2.0"
  #else
  #	gcc_version="${current_gcc_version}"
  #fi
  if [[ -z ${gcc_version} ]]; then
    mflibs::shell::text::red "Failed to fetch the latest GCC version from the GNU mirror."
    exit 1
  fi
  #gcc_version_major=$(echo "${gcc_version}" | cut -d. -f1)
  #gcc_version_path=$(echo "${gcc_version}" | cut -d. -f1-2)
  #gcc_version_path="12.2"
  mflibs::shell::text::green "Latest GCC version: ${gcc_version}"
}

################################################################################
# @description: Function to get the libcurl version built into libtorrent 0.16
#   on hosts whose system libcurl is too old for it. The version is pinned so a
#   change is a reviewed edit here. Raise libcurl_generation with every change of
#   the pinned version: it moves the libtorrent and rTorrent packages that carry
#   libcurl to a new build revision, so installs are offered the new libcurl.
# @noargs
# @output: libcurl version, libcurl package generation
# @example: qbcompile::get::libcurl_version
# @break
################################################################################
qbcompile::get::libcurl_version() {
  declare -xg libcurl_version="8.23.0" libcurl_generation=1
  mflibs::shell::text::cyan "Using libcurl version: ${libcurl_version}"
}

################################################################################
# @description: Function to get the latest stable libtorrent version
# @noargs
# @output: libtorrent version
# @example: qbcompile::get::libtorrent_version
# @break
################################################################################
qbcompile::get::libtorrent_version() {
  # Check if a custom version is set
  if [[ ${custom_libtorrent_version} == "source" ]]; then
    declare -xg libtorrent_version libtorrent_compact_version
    libtorrent_version="0.16.6"
    libtorrent_compact_version="166"
    return 0
  elif [[ -n "${custom_libtorrent_version}" ]]; then
    declare -xg libtorrent_version libtorrent_compact_version
    libtorrent_version="${custom_libtorrent_version}"
    # Compact version removes leading `0` and decimal points for use in versioned filenames
    libtorrent_compact_version=$(echo "${libtorrent_version}" | sed 's/\.//g; s/^0*//') || { mflibs::shell::text::red "Failed to create compact libtorrent version." && exit 1; }
    mflibs::shell::text::cyan "Using custom libtorrent version: ${libtorrent_version}"
    return 0
  fi
  mflibs::shell::text::blue "Fetching the latest stable libtorrent version..."
  # Step 1: Fetch the tags from the libtorrent GitHub repository
  local api_url="https://api.github.com/repos/rakshasa/libtorrent/tags"
  local curl_output
  curl_output=$(curl -s "${api_url}") || { mflibs::shell::text::red "Failed to fetch tags from libtorrent repository." && exit 1; }
  # Step 2: Filter for stable versions (excluding RC and beta)
  local jq_output
  jq_output=$(echo "${curl_output}" | jq -r '.[] | select(.name | test("rc|beta") | not) | .name') || { mflibs::shell::text::red "Error parsing JSON response for libtorrent version." && exit 1; }
  # Step 3: Get the latest stable version
  declare -xg latest_libtorrent_tag
  latest_libtorrent_tag=$(echo "${jq_output}" | head -n 1) || { mflibs::shell::text::red "Failed to retrieve the latest stable libtorrent tag." && exit 1; }
  # Extract the version number from the tag
  declare -xg libtorrent_version libtorrent_compact_version
  libtorrent_version=$(echo "${latest_libtorrent_tag}" | grep -Po '\d+\.\d+\.\d+') || { mflibs::shell::text::red "Failed to extract libtorrent version from the tag." && exit 1; }
  # Compact version removes leading `0` and decimal points for use in versioned filenames
  libtorrent_compact_version=$(echo "${libtorrent_version}" | sed 's/\.//g; s/^0*//') || { mflibs::shell::text::red "Failed to create compact libtorrent version." && exit 1; }
  # Step 4: Output the latest stable version
  mflibs::shell::text::cyan "Latest libtorrent version from rakshasa: ${libtorrent_version}"
}

################################################################################
# @description: Function to get the latest stable libtorrent-rasterbar version
# @noargs
# @output: libtorrent-rasterbar version
# @example: qbcompile::get::libtorrent_rasterbar_version
# @break
################################################################################
qbcompile::get::libtorrent_rasterbar_version() {
  # Check if a custom version is set (pins both libtorrent-rasterbar and python3-libtorrent)
  if [[ -n "${custom_libtorrent_rasterbar_version}" ]]; then
    declare -xg libtorrent_rasterbar_version
    libtorrent_rasterbar_version="${custom_libtorrent_rasterbar_version}"
    mflibs::shell::text::cyan "Using custom libtorrent-rasterbar version: ${libtorrent_rasterbar_version}"
    return 0
  fi
  # Pin the default to the 2.0.x stable line. The qBittorrent-nox and Deluge
  # binaries we ship link against libtorrent-rasterbar 2.0.13; the 2.1.x tags are
  # arvidn's development branch, which those clients cannot load. Pinning the
  # exact patch also keeps the compiled package in lockstep with the qBittorrent
  # binary's embedded lt-version token, avoiding intra-2.0 drift. Override with
  # --rasterbar-version.
  declare -xg libtorrent_rasterbar_version
  libtorrent_rasterbar_version="2.0.14"
  mflibs::shell::text::cyan "Using pinned stable libtorrent-rasterbar version: ${libtorrent_rasterbar_version}"
}

################################################################################
# @description: Function to get the latest stable qBittorrent version
# @noargs
# @output: Latest stable version tag and tarball URL
# @example: qbcompile::get::qbittorrent_version
# @break
################################################################################
qbcompile::get::qbittorrent_version() {
  mflibs::shell::text::blue "Fetching the latest stable qBittorrent version..."
  local api_url="https://api.github.com/repos/qbittorrent/qBittorrent/tags"
  local curl_output
  if ! curl_output=$(curl -s "${api_url}"); then
    mflibs::shell::text::red "Error fetching tags from GitHub." && return 1
  fi
  [[ -z ${curl_output} ]] && { mflibs::shell::text::red "Error fetching tags from GitHub." && return 1; }
  local jq_output
  if ! jq_output=$(echo "${curl_output}" | jq -r '.[] | select(.name | test("rc|beta") | not) | .name'); then
    mflibs::shell::text::red "Error parsing JSON response." && return 1
  fi
  [[ -z ${jq_output} ]] && { mflibs::shell::text::red "Error parsing JSON response." && return 1; }
  declare -xg latest_qbittorrent_tag
  latest_qbittorrent_tag=$(echo "${jq_output}" | head -n 1)
  [[ -z ${latest_qbittorrent_tag} ]] && { mflibs::shell::text::red "No valid tags found." && return 1; }
  declare -xg qbittorrent_version
  qbittorrent_version=$(echo "${latest_qbittorrent_tag}" | grep -Po '\d+\.\d+\.\d+')
  [[ -z ${qbittorrent_version} ]] && { mflibs::shell::text::red "Failed to extract qBittorrent version from the tag." && return 1; }
  mflibs::shell::text::cyan "Latest qBittorrent version: ${qbittorrent_version}"
}

################################################################################
# @description: Function to fetch the latest Qt version and subversion and download the archive
# @noargs
# @example: qbcompile::get::qt_version
# @break
################################################################################
qbcompile::get::qt_version() {
  # Base URL for Qt official releases (change this to a faster mirror)
  declare -xg qt_base_url="https://ftp.fau.de/qtproject/official_releases/qt/"
  # Fetch the latest release (e.g., 6.8)
  declare -xg qt_latest_release
  qt_latest_release=$(curl -s "${qt_base_url}" | grep -Po 'href="\K([0-9]+\.[0-9]+)/' | sort -V | tail -n 1)
  # Check if release is empty or failed to retrieve
  if [[ -z ${qt_latest_release} ]]; then
    mflibs::shell::text::red "Failed to fetch the latest Qt release version."
    return 1
  fi
  # Fetch the latest sub-version (e.g., 6.8.0)
  declare -xg qt_latest_version
  qt_latest_version=$(curl -s "${qt_base_url}${qt_latest_release}" | grep -Po 'href="\K([0-9]+\.[0-9]+\.[0-9]+)' | sort -V | tail -n 1)
  # Check if version is empty or failed to retrieve
  if [[ -z ${qt_latest_version} ]]; then
    mflibs::shell::text::red "Failed to fetch the latest Qt sub-version."
    return 1
  fi
}

################################################################################
# @description: Function to fetch the latest Qt version and subversion and download the archive
# @noargs
# @example: qbcompile::get::qt_latest_release
# @break
################################################################################
qbcompile::get::qt_latest_release() {
  qbcompile::get::qt_version
  # Build the download URL for qt-everywhere-src
  local download_url="${qt_base_url}${qt_latest_release}${qt_latest_version}/single/qt-everywhere-src-${qt_latest_version}.tar.xz"
  mflibs::shell::text::blue "Downloading Qt source from:"
  mflibs::shell::text::cyan "${download_url}"
  # Download the Qt source tarball
  if [[ -f "${temp_dir:-/opt/qb-compile/builds}/qt-everywhere-src-${qt_latest_version}.tar.xz" ]]; then
    mflibs::shell::text::yellow "Qt source package already exists. Skipping download."
  else
    wget "${download_url}" -O "${temp_dir:-/opt/qb-compile/builds}/qt-everywhere-src-${qt_latest_version}.tar.xz" 2>&1 | sudo tee -a "${mflibs_log_location}" >/dev/null
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { mflibs::shell::text::red "Failed to download Qt source." && exit 1; }
  fi
}

################################################################################
# @description: Function to get the latest rTorrent version
# @noargs
# @output: rTorrent version
# @example: qbcompile::get::rtorrent_version
# @break
################################################################################
qbcompile::get::rtorrent_version() {
  # Check if a custom version is set
  if [[ -n "${custom_rtorrent_version}" ]]; then
    declare -xg rtorrent_version
    rtorrent_version="${custom_rtorrent_version}"
    mflibs::shell::text::cyan "Using custom rTorrent version: ${rtorrent_version}"
    return 0
  fi

  mflibs::shell::text::blue "Fetching the latest rTorrent version..."
  # Fetch the tags from the rTorrent GitHub repository
  local api_url="https://api.github.com/repos/rakshasa/rtorrent/tags"
  local curl_output
  curl_output=$(curl -s "${api_url}") || { mflibs::shell::text::red "Failed to fetch tags from rTorrent repository." && exit 1; }
  # Filter for versions (excluding RC and beta)
  local jq_output
  jq_output=$(echo "${curl_output}" | jq -r '.[] | select(.name | test("rc|beta") | not) | .name') || { mflibs::shell::text::red "Error parsing JSON response for rTorrent version." && exit 1; }
  # Get the latest version
  declare -xg latest_rtorrent_tag
  latest_rtorrent_tag=$(echo "${jq_output}" | head -n 1) || { mflibs::shell::text::red "Failed to retrieve the latest rTorrent tag." && exit 1; }
  # Extract the version number
  declare -xg rtorrent_version
  rtorrent_version=$(echo "${latest_rtorrent_tag}" | grep -Po '\d+\.\d+\.\d+') || { mflibs::shell::text::red "Failed to extract rTorrent version from the tag." && exit 1; }
  # Output the latest version
  mflibs::shell::text::cyan "Latest rTorrent version: ${rtorrent_version}"
}

################################################################################
# @description: Function to get the latest stable transmission version
# @noargs
# @output: transmission version
# @example: qbcompile::get::transmission_version
# @break
################################################################################
qbcompile::get::transmission_version() {
  mflibs::shell::text::blue "Fetching the latest stable Transmission version..."
  local api_url="https://api.github.com/repos/transmission/transmission/tags"
  local curl_output
  curl_output=$(curl -s "${api_url}") || { mflibs::shell::text::red "Failed to fetch tags from Transmission repository." && exit 1; }
  local jq_output
  jq_output=$(echo "${curl_output}" | jq -r '.[] | select(.name | test("rc|beta") | not) | .name') || { mflibs::shell::text::red "Error parsing JSON response for Transmission version." && exit 1; }
  declare -xg latest_transmission_tag
  latest_transmission_tag=$(echo "${jq_output}" | head -n 1) || { mflibs::shell::text::red "Failed to retrieve the latest stable Transmission tag." && exit 1; }
  declare -xg transmission_version
  transmission_version=$(echo "${latest_transmission_tag}" | grep -Po '\d+\.\d+\.\d+') || { mflibs::shell::text::red "Failed to extract Transmission version from the tag." && exit 1; }
  mflibs::shell::text::cyan "Latest Transmission version: ${transmission_version}"
}

################################################################################
# @description: Function to get the latest (advanced) xmlrpc-c version
# @noargs
# @output: xmlrpc-c version
# @example: qbcompile::get::xmlrpc_c_version
# @break
################################################################################
qbcompile::get::xmlrpc_c_version() {
  mflibs::shell::text::blue "Fetching the latest xmlrpc-c version and revision..."
  declare -xg xmlrpc_latest_revision xmlrpc_c_version
  # Fetch the latest version of xmlrpc-c from the advanced tree of SourceForge
  xmlrpc_latest_revision=$(svn info https://svn.code.sf.net/p/xmlrpc-c/code/advanced | grep "Revision:" | awk '{print $2}')
  xmlrpc_c_version=$(curl -s https://sourceforge.net/p/xmlrpc-c/code/HEAD/tree/advanced/version.mk?format=raw | awk -F ' = ' '
/XMLRPC_MAJOR_RELEASE/ { major = $2 }
/XMLRPC_MINOR_RELEASE/ { minor = $2 }
/XMLRPC_POINT_RELEASE/ { point = $2 }
END { printf "%s.%s.%s", major, minor, point }
' | sed 's/ //g')
  # Output the latest xmlrpc-c version and revision
  mflibs::shell::text::cyan "Latest xmlrpc-c version: ${xmlrpc_c_version} (Revision: ${xmlrpc_latest_revision})"
}
