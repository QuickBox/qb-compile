#!/usr/bin/env bash
################################################################################
# @file_name: init
# @version: 1.0.2
# @project_name: qb-compile
# @description: Initialization script for qb-compile
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
# @description: Function to initialize the environment
# @noargs
# @global: script_name
# @return: Imports mflibs and sets up the environment
# @example: qbcompile::environment::init
# @break
# shellcheck disable=SC1090,SC1091,SC2068,SC2154
################################################################################
qbcompile::environment::init() {
  declare -xg script_name script_dir script_path script_version
  script_name="qb-compile"
  script_dir="/opt/${script_name}"
  script_path="${script_dir}/${script_name}.sh"
  script_version=$(grep -m 1 -oP "# @version:\s*\K[0-9.]+" "/opt/qb-compile/qb-compile.sh" | tr -d '\n')
  # Module Paths
  declare -xg config_path mod_path context_path
  config_path="${script_dir}/src/config"
  mod_path="${script_dir}/src/modules"
  context_path="${script_dir}/src/context"
}

################################################################################
# @description: Function to initialize various contexts and import libraries
# @noargs
# @example: qbcompile::import "essentials,builds,views"
# @break
################################################################################
qbcompile::import() {
  local IFS=',' modules
  read -ra modules <<<"$*"
  for module in "${modules[@]}"; do
    local i
    i=$(echo "${module}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Skip empty module names
    [[ -z "${i}" ]] && continue
    if [[ -f "${config_path}/${i}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${config_path}/${i}.sh"
    elif [[ -f "${context_path}/${i}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${context_path}/${i}.sh"
    elif [[ -f "${mod_path}/${i}/${i}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${mod_path}/${i}/${i}.sh"
    else
      # Try to find the file in any subdirectory of mod_path
      local found_module=""
      for mod_dir in "${mod_path}"/*; do
        if [[ -f "${mod_dir}/${i}.sh" ]]; then
          found_module="${mod_dir}/${i}.sh"
          break
        fi
      done
      if [[ -n "${found_module}" ]]; then
        # shellcheck source=/dev/null
        source "${found_module}"
      else
        mflibs::shell::text::red "Import Error: Could not find module '${i}'"
        exit 1
      fi
    fi
  done
}

################################################################################
qbcompile::environment::init
################################################################################
