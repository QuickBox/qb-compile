#!/usr/bin/env bash
################################################################################
# @file_name: deploy.sh
# @module: deployment
# @version: 1.0.28
# @description: Deploy development version to /opt/qb-compile
# @author: Jason Matthews (JMSolo)
# @license: MIT
#
# @save_tasks:
#  automated_versioning: true
#  automated_documentation: true
#
# @build_tasks:
#  automated_comment_strip: true
#  automated_encryption: false
#
# Copyright (C) 2026, QuickBox.IO
################################################################################
# shellcheck disable=SC1091
################################################################################

set -euo pipefail

################################################################################
# @description: Used to set deploy script colors
################################################################################
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
# Special colors for info, success, warning, error with iconic representation
INFO="${BLUE}ℹ️ "
SUCCESS="${GREEN}✅ "
WARNING="${YELLOW}⚠️ "
ERROR="${RED}❌ "

################################################################################
# Ensure script is run as root
################################################################################
if [[ ${EUID} -ne 0 ]]; then
  echo -e "${ERROR}This script must be run as root. Use sudo.${NC}" >&2
  exit 1
fi

################################################################################
# Define source and destination directories
################################################################################
script_name="qb-compile"
dest_dir="/opt/qb-compile"
# Create destination directory if it doesn't exist
mkdir -p "${dest_dir}"

################################################################################
# @description: Download a GitHub branch or tag archive and unpack its contents
#   (without the top-level directory) into a destination directory.
# @arg $1: repository (owner/name)
# @arg $2: branch or tag
# @arg $3: destination directory
################################################################################
fetch_github_archive() {
  local repo="$1" ref="$2" dest="$3" work
  [[ ${repo} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo -e "${ERROR}Invalid repository: ${repo}${NC}" >&2 && return 1; }
  [[ ${ref} =~ ^[A-Za-z0-9._/-]+$ ]] || { echo -e "${ERROR}Invalid branch or tag: ${ref}${NC}" >&2 && return 1; }
  work=$(mktemp -d -t qbcompile-archive-XXXX)
  curl -fsSL -o "${work}/archive.zip" "https://github.com/${repo}/archive/${ref}.zip" || { rm -rf "${work}" && return 1; }
  unzip -q "${work}/archive.zip" -d "${work}/unpacked" || { rm -rf "${work}" && return 1; }
  mkdir -p "${dest}"
  # GitHub archives hold a single top-level directory (<name>-<ref>)
  cp -a "${work}"/unpacked/*/. "${dest}/" || { rm -rf "${work}" && return 1; }
  rm -rf "${work}"
}

################################################################################
# Source repositories. Override to deploy from a fork or another branch/tag, e.g.
#   sudo QBCOMPILE_REPO=you/qb-compile QBCOMPILE_REF=my-branch bash deploy.sh
################################################################################
qbcompile_repo="${QBCOMPILE_REPO:-QuickBox/qb-compile}"
qbcompile_ref="${QBCOMPILE_REF:-main}"
mflibs_repo="${MFLIBS_REPO:-QuickBox/mflibs}"
mflibs_ref="${MFLIBS_REF:-main}"

################################################################################
# Download the latest qb-compile from GitHub
################################################################################
echo -e "${INFO}Downloading the latest qb-compile project...${NC}"
tmp_dir=$(mktemp -d -t qbcompile-XXXX)
fetch_github_archive "${qbcompile_repo}" "${qbcompile_ref}" "${tmp_dir}/qb-compile" || { echo -e "${ERROR}Failed to download qb-compile archive.${NC}" >&2 && exit 1; }
if ! command -v rsync >/dev/null 2>&1; then
  echo -e "${WARNING}rsync not found. Installing rsync...${NC}"
  if ! (sudo apt-get update && sudo apt-get install -y rsync); then
    echo -e "${ERROR}Failed to install rsync.${NC}" >&2
    exit 1
  fi
fi
rsync -a --exclude='.git/' "${tmp_dir}/qb-compile/" "/opt/qb-compile/" || { echo -e "${ERROR}Failed to deploy qb-compile to /opt/qb-compile.${NC}" >&2 && exit 1; }
# Clean up
rm -rf "${tmp_dir}"
# Ensure all files are executable
find /opt/qb-compile/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
# Final deploy message
echo -e "${GREEN}qb-compile deployed to ${dest_dir} successfully.${NC}"
# Create symlink to /usr/local/bin
echo -e "${INFO}Creating symlink to /usr/local/bin/qb-compile...${NC}"
sudo ln -sf "/opt/qb-compile/qb-compile.sh" "/usr/local/bin/qb-compile" || { echo -e "${ERROR}Failed to create symlink.${NC}" >&2 && exit 1; }
# Final link message
echo -e "${GREEN}Symlink created successfully.${NC}"

################################################################################
# Check and setup mflibs if not present
################################################################################
if [[ ! -d "/opt/mflibs" ]]; then
  echo -e "${WARNING}Essential libraries not found. Downloading and setting up now...${NC}"
  [[ -d /opt/mflibs ]] && rm -rf /opt/mflibs
  mflibs_base_path="/opt/mflibs"
  rm -rf "${mflibs_base_path}"
  tmp_dir=$(mktemp -d -t mflibsfetch-XXXXXXXX)
  fetch_github_archive "${mflibs_repo}" "${mflibs_ref}" "${tmp_dir}/mflibs" || {
    echo -e "${ERROR}Unable to download mflibs archive.${NC}" >&2
    exit 1
  }
  # Move into place
  mkdir -p "${mflibs_base_path}"
  if ! cp -rf "${tmp_dir}"/mflibs/. "${mflibs_base_path}"; then
    echo -e "${ERROR}Unable to copy lib files.${NC}" >&2
    exit 1
  fi
  if ! rm -rf "${tmp_dir}"; then
    echo -e "${WARNING}Unable to remove temporary libs directory: ${tmp_dir}${NC}" >&2
  fi
  mkdir -p "/opt/qb-compile/logs/" && mkdir -p "/opt/mflibs/logs/"
  chmod +x "$(find /opt/mflibs/src/ -type f -name "init.sh")" 2>/dev/null
  if [[ -f "/opt/mflibs/src/init.sh" ]]; then
    declare -xg mflibs_log_location="/opt/${script_name}/logs/compilation.log"
    # Create the qbcompile.sh file in the custom directory
    mkdir -p /opt/mflibs/src/custom
    # Symlink qbcompile mflibs
    ln -sf /"opt/qb-compile/src/config/mflibs/qbcompile.sh" "/opt/mflibs/src/custom/qbcompile.sh"
    chmod +x /opt/mflibs/src/custom/qbcompile.sh
    # Ensure all files are executable
    find /opt/mflibs/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    find /opt/qb-compile/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
    . "/opt/mflibs/src/init.sh" 2>/dev/null || {
      echo -e "${ERROR}Unable to source mflibs init.sh.${NC}" >&2
      exit 1
    }
    [[ " ${MFLIBS_LOADED[*]} " =~ verbose ]] && mflibs::import verbose
    mflibs::import shell,status,log,info,qbcompile
    # Create a temporary directory for .deb file storage
    mkdir -p /opt/qb-compile/packaged
    # Symlink qb-compile bash completion
    ln -sf "/opt/qb-compile/src/config/bash_completion.d/qb-compile" "/etc/bash_completion.d/qb-compile"
    # Source the autocomplete script
    [[ -f "/etc/bash_completion.d/qb-compile" ]] && source "/etc/bash_completion.d/qb-compile" 2>/dev/null
    echo -e "${GREEN}Essential libraries setup completed successfully.${NC}"
  else
    echo -e "${ERROR}Unable to download libraries.${NC}" >&2
    exit 1
  fi
else
  echo -e "${INFO}Essential libraries already present. Skipping download.${NC}"
  find /opt/mflibs/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
  # Symlink qb-compile bash completion
  ln -sf "/opt/qb-compile/src/config/bash_completion.d/qb-compile" "/etc/bash_completion.d/qb-compile"
  # Source the autocomplete script
  [[ -f "/etc/bash_completion.d/qb-compile" ]] && source "/etc/bash_completion.d/qb-compile" 2>/dev/null
fi

################################################################################
# Final message
echo -e "${SUCCESS}Deployment of qb-compile completed successfully.${NC}"
exit 0
################################################################################
