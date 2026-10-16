#!/usr/bin/env bash
################################################################################
# @file_name: update
# @version: 1.0.8
# @project_name: qb-compile
# @description: Update context for qb-compile script
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
# shellcheck disable=SC1091,SC2154
################################################################################

################################################################################
# @description: Function to update the script
# @noargs
# @output: Updates the script
# @example: qb-compile --update
# @break
################################################################################
qbcompile::update() {
  mflibs::shell::text::white "Updating qb-compile script..."
  qbcompile::download::qb-compile
  # Now update permissions
  mflibs::shell::text::blue "Updating permissions for /opt/qb-compile..."
  find /opt/mflibs/src/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
  find /opt/qb-compile/ -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \; 2>/dev/null
  # Symlink the main script
  sudo ln -sf "/opt/qb-compile/qb-compile.sh" "/usr/local/bin/qb-compile" || { mflibs::shell::text::red "Failed to symlink qb-compile script." && exit 1; }
  # Now update the bash_completion if it exists
  if [[ -f "/etc/bash_completion.d/qb-compile" ]]; then
    mflibs::shell::text::blue "Updating qb-compile bash completion..."
    sudo rm -rf "/etc/bash_completion.d/qb-compile"
    sudo ln -sf "/opt/qb-compile/src/config/bash_completion.d/qb-compile" "/etc/bash_completion.d/qb-compile" || { mflibs::shell::text::red "Failed to symlink qb-compile bash completion." && exit 1; }
    # Reload bash completion
    if command -v bash-completion >/dev/null 2>&1; then
      source /etc/bash_completion.d/qb-compile
    fi
  fi
  # Now update the mflibs if it exists
  if [[ -d "/opt/mflibs/src/custom/qbcompile.sh" ]]; then
    mflibs::shell::text::blue "Updating qb-compile mflibs..."
    sudo rm -rf "/opt/mflibs/src/custom/qbcompile.sh"
    sudo ln -sf "/opt/qb-compile/src/config/mflibs/qbcompile.sh" "/opt/mflibs/src/custom/qbcompile.sh" || { mflibs::shell::text::red "Failed to symlink qb-compile mflibs." && exit 1; }
  fi
  mflibs::shell::text::green "qb-compile script updated successfully."
}
