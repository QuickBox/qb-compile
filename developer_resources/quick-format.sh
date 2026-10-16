#!/usr/bin/env bash
################################################################################
# @file_name: quick-format.sh
# @version: 1.0.0
# @description: Quick format and version increment for current file - no conflicts
# @project_name: qb-compile
# @author: Jason Matthews (JMSolo)
# @license: MIT
# Copyright (C) 2019-2025, QuickBox.IO
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'

################################################################################
# @description: Main function - format current file if it's a bash file
# @noargs
################################################################################
main() {
  # Get the current working directory (should be the workspace root)
  local workspace_root
  workspace_root="$(pwd)"

  # Check if we're in the qb-compile workspace
  if [[ ! -f "${workspace_root}/developer_resources/format-bash.sh" ]]; then
    echo "Error: Not in qb-compile workspace. Please run this from the project root." >&2
    exit 1
  fi

  # If files are specified as arguments, format those
  if [[ $# -gt 0 ]]; then
    echo "Formatting specified files:"
    for file in "$@"; do
      if [[ -f "${file}" ]]; then
        echo "Processing: ${file}"
        "${workspace_root}/developer_resources/format-bash.sh" "${file}"
        echo ""
      else
        echo "Warning: File not found: ${file}" >&2
      fi
    done
    echo "✓ All specified files processed!"
    return 0
  fi

  # Check if there are any modified or untracked .sh files
  local modified_files
  modified_files=$(git status --porcelain | grep '^[AM]' | awk '{print $2}' | grep '\.sh$' | head -5)

  local untracked_files
  untracked_files=$(git status --porcelain | grep '^??' | awk '{print $2}' | grep '\.sh$' | head -5)

  local all_files
  all_files="${modified_files}"$'\n'"${untracked_files}"
  all_files=$(echo "${all_files}" | grep -v '^$' | sort -u)

  if [[ -z "${all_files}" ]]; then
    echo "No modified or untracked .sh files found."
    echo ""
    echo "Usage:"
    echo "  $0                    # Format modified/untracked .sh files"
    echo "  $0 file1.sh file2.sh # Format specific files"
    echo ""
    echo "To format all .sh files in the project:"
    echo "  ./developer_resources/format-bash.sh --all"
    exit 0
  fi

  echo "Found bash files to process:"
  echo "${all_files}"
  echo ""

  # Format each file
  for file in ${all_files}; do
    if [[ -f "${file}" ]]; then
      echo "Processing: ${file}"
      "${workspace_root}/developer_resources/format-bash.sh" "${file}"
      echo ""
    fi
  done

  echo "✓ All bash files processed!"
}

# Execute main function
main "$@"
