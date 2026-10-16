#!/usr/bin/env bash
################################################################################
# @file_name: view
# @version: 1.0.2
# @project_name: qb-compile
# @description: View context for qb-compile script
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
# @description: Function to view information about compiled .deb and binary files.
# This includes listing them by codename, package, category, file name, filesize, and hash.
# @noargs
# @output: Lists compiled .deb and binary files with their MD5 checksums and file sizes in alphabetical order.
# @notes: - Binary files are located in the ${deb_storage}/${codename}/static-binary/ directory.
# - .deb files are located in the ${deb_storage}/${codename}/binary-amd64/ directory.
# - Categories are inferred from the parent directory of each file.
# @example: qb-compile --list-packages
# qb-compile -lp
# @break
################################################################################
qbcompile::view::compiled_info() {
  # Define directories to check
  local directories
  directories=$(find "${deb_storage}" -mindepth 2 -maxdepth 2 -type d)
  # If no directories found, return an error message
  [[ -z ${directories} ]] && mflibs::shell::text::red "No compiled packages or binaries found in ${deb_storage}." && return 1
  # Function to convert file size into human-readable format
  qbcompile::convert_filesize() {
    local bytes=${1}
    local sizes=(B KB MB GB TB)
    local scale=0
    while [[ ${bytes} -ge 1024 && ${scale} -lt ${#sizes[@]} ]]; do
      bytes=$((bytes / 1024))
      ((scale++))
    done
    echo "${bytes} ${sizes[${scale}]}"
  }
  # Loop through each directory to find .deb files and binaries
  for dir in ${directories}; do
    # Extract the codename and package name from directory structure
    local codename
    codename=$(basename "$(dirname "${dir}")")
    local compiled_package
    compiled_package=$(basename "${dir}")
    [[ ${compiled_package} == "static-binary" || ${compiled_package} == "binary-amd64" ]] &&
      mflibs::shell::misc::nl &&
      mflibs::shell::text::blue "Listing compiled files for package: ${compiled_package}, Code Name: ${codename}"
    # Handle static-binary directory separately for binaries
    if [[ ${compiled_package} == "static-binary" ]]; then
      local binaries
      binaries=$(find "${dir}" -type f -executable | sort)
      if [[ -n ${binaries} ]]; then
        mflibs::shell::text::cyan "Found binaries:"
        mflibs::shell::misc::nl
        local last_category=""
        for binary in ${binaries}; do
          # Determine the category based on the parent directory
          local category
          category=$(basename "$(dirname "${binary}")")
          # Print the category only if it changes
          if [[ ${category} != "${last_category}" ]]; then
            if [[ -n ${last_category} ]]; then
              mflibs::shell::misc::nl
            fi
            mflibs::shell::text::white::sl "Category: "
            mflibs::shell::text::cyan "${category}"
            last_category="${category}"
          fi
          local filesize
          filesize=$(stat -c %s "${binary}")
          filesize=$(qbcompile::convert_filesize "${filesize}")
          local hash
          hash=$(md5sum "${binary}" | awk '{print $1}')
          mflibs::shell::text::white::sl "Binary: "
          mflibs::shell::text::green::sl "$(basename "${binary}")"
          mflibs::shell::text::cyan " (${filesize})"
          mflibs::shell::text::white::sl "MD5 Hash: "
          mflibs::shell::text::blue "${hash}"
        done
        mflibs::shell::misc::nl
      else
        mflibs::shell::text::red "No binaries found in ${compiled_package}."
      fi
    # Handle binary-amd64 directory for .deb files
    elif [[ ${compiled_package} == "binary-amd64" ]]; then
      local deb_files
      deb_files=$(find "${dir}" -type f -name "*.deb" | sort)
      if [[ -n ${deb_files} ]]; then
        mflibs::shell::text::cyan "Found .deb files:"
        mflibs::shell::misc::nl
        local last_category=""
        for deb in ${deb_files}; do
          # Determine the category based on the parent directory
          local category
          category=$(basename "$(dirname "${deb}")")
          # Print the category only if it changes
          if [[ ${category} != "${last_category}" ]]; then
            if [[ -n ${last_category} ]]; then
              mflibs::shell::misc::nl
            fi
            mflibs::shell::text::white::sl "Category: "
            mflibs::shell::text::cyan "${category}"
            last_category="${category}"
          fi
          local filesize
          filesize=$(stat -c %s "${deb}")
          filesize=$(qbcompile::convert_filesize "${filesize}")
          local hash
          hash=$(md5sum "${deb}" | awk '{print $1}')
          mflibs::shell::text::white::sl "File: "
          mflibs::shell::text::green::sl "$(basename "${deb}")"
          mflibs::shell::text::cyan " (${filesize})"
          mflibs::shell::text::white::sl "MD5 Hash: "
          mflibs::shell::text::blue "${hash}"
        done
        mflibs::shell::misc::nl
      else
        mflibs::shell::text::red "No .deb files found in ${compiled_package}."
      fi
    fi
    mflibs::shell::misc::nl
  done
}
