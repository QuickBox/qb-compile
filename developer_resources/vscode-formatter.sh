#!/usr/bin/env bash
################################################################################
# @file_name: vscode-formatter.sh
# @version: 1.0.0
# @description: VS Code-compatible bash formatter that runs on save without conflicts
# @project_name: qb-compile
# @author: Jason Matthews (JMSolo)
# @license: MIT
# Copyright (C) 2019-2025, QuickBox.IO
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'

################################################################################
# @description: Main function - format file and increment version
# @arg: $1: file path (required)
################################################################################
main() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <file_path>"
    exit 1
  fi

  local file_path="${1}"

  if [[ ! -f "${file_path}" ]]; then
    echo "Error: File not found: ${file_path}" >&2
    exit 1
  fi

  if [[ ! "${file_path}" =~ \.sh$ ]] && [[ ! $(head -n1 "${file_path}") =~ bash ]]; then
    echo "Error: Not a bash file: ${file_path}" >&2
    exit 1
  fi

  # Parse metadata and increment version if enabled
  local metadata_info
  metadata_info=$(parse_metadata "${file_path}")
  increment_version "${file_path}" "${metadata_info}"

  # Format the file with shfmt
  if command -v shfmt &>/dev/null; then
    if shfmt -i 2 -w "${file_path}" 2>/dev/null; then
      # Additional cleanup
      cleanup_bash_file "${file_path}"
    else
      # Fallback to basic cleanup
      basic_bash_cleanup "${file_path}"
    fi
  else
    # Basic cleanup if shfmt not available
    basic_bash_cleanup "${file_path}"
  fi
}

################################################################################
# @description: Parse metadata from file for version incrementing
# @arg: $1: file path
################################################################################
parse_metadata() {
  local file_path="${1}"
  local automated_versioning="false"
  local type=""

  if grep -q '@save_tasks' "${file_path}"; then
    type="newmeta"
    # Parse @save_tasks metadata
    while IFS='' read -r line; do
      if [[ "${line}" =~ ^[[:space:]]*automated_versioning:[[:space:]]*true ]]; then
        automated_versioning="true"
        break
      fi
    done < <(sed -n -e '/\@save_tasks/,/^################################################################################$/ p' "${file_path}" | grep "automated_versioning")
  elif grep -q 'Save Tasks' "${file_path}"; then
    type="oldmeta"
    # Parse old metadata format
    while IFS='' read -r line; do
      if [[ "${line}" =~ ^[[:space:]]*automated_versioning[[:space:]]*=[[:space:]]*true ]]; then
        automated_versioning="true"
        break
      fi
    done < <(sed -n -e '/Save\ Tasks/,/Author:/ p' "${file_path}" | grep "automated_versioning")
  fi

  echo "${automated_versioning}:${type}"
}

################################################################################
# @description: Increment version number in file
# @arg: $1: file path
# @arg: $2: metadata info (automated_versioning:type)
################################################################################
increment_version() {
  local file_path="${1}"
  local metadata_info="${2}"
  local automated_versioning="${metadata_info%:*}"
  local type="${metadata_info#*:}"

  if [[ "${automated_versioning}" != "true" ]]; then
    return 0
  fi

  if [[ "${type}" == "newmeta" ]]; then
    # Handle bash files with # @version: format
    if grep -q '# @version:' "${file_path}"; then
      local version_old version_number version_split version_new
      version_old=$(grep -o '# @version: [0-9]\+\.[0-9]\+\.[0-9]\+' "${file_path}" | head -n 1 | cut -d: -f2 | tr -d " ")
      if [[ -n "${version_old}" ]]; then
        version_number=$(echo "${version_old}" | grep -Eo '[0-9]+$')
        if [[ -n "${version_number}" ]]; then
          version_number=$(("${version_number}" + 1))
          version_split=$(echo "${version_old}" | grep -o '.*[.]')
          version_new="${version_split}${version_number}"
          sed -i "s/# @version: [0-9]\+\.[0-9]\+\.[0-9]\+/# @version: ${version_new}/" "${file_path}"
          echo "✓ Version incremented from ${version_old} to ${version_new}" >&2
        fi
      fi
    fi
  elif [[ "${type}" == "oldmeta" ]]; then
    # Handle old metadata format
    local version_old version_number version_split version_new
    version_old=$(grep -o '# File Version: [0-9]\+\.[0-9]\+\.[0-9]\+' "${file_path}" | head -n 1 | cut -d: -f2 | tr -d " ")
    if [[ -n "${version_old}" ]]; then
      version_number=$(echo "${version_old}" | grep -Eo '[0-9]+$')
      if [[ -n "${version_number}" ]]; then
        version_number=$(("${version_number}" + 1))
        version_split=$(echo "${version_old}" | grep -o '.*[.]')
        version_new="${version_split}${version_number}"
        sed -i "s/# File Version: [0-9]\+\.[0-9]\+\.[0-9]\+/# File Version: ${version_new}/" "${file_path}"
        echo "✓ Version incremented from ${version_old} to ${version_new}" >&2
      fi
    fi
  fi
}

################################################################################
# @description: Clean up bash file after formatting
# @arg: $1: file path
################################################################################
cleanup_bash_file() {
  local file_path="${1}"

  # Ensure proper shebang line
  if [[ ! $(head -n1 "${file_path}") =~ ^#!/ ]]; then
    sed -i '1i#!/usr/bin/env bash' "${file_path}"
  fi

  # Ensure strict mode is present (add if missing)
  if ! grep -q "set -Eeuo pipefail" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\set -Eeuo pipefail" "${file_path}"
    fi
  fi

  # Ensure IFS is set properly
  if ! grep -q "IFS=" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\IFS=\$'\\n\\t'" "${file_path}"
    fi
  fi

  # Ensure inherit_errexit is set if available
  if ! grep -q "inherit_errexit" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\shopt -s inherit_errexit 2>/dev/null || true" "${file_path}"
    fi
  fi

  # Remove trailing whitespace
  sed -i 's/[[:space:]]\+$//' "${file_path}"

  # Ensure file ends with newline
  if [[ -s "${file_path}" ]] && [[ $(tail -c1 "${file_path}" | wc -l) -eq 0 ]]; then
    echo >>"${file_path}"
  fi

  # Ensure proper file permissions
  chmod +x "${file_path}" 2>/dev/null || true
}

################################################################################
# @description: Basic bash file cleanup when shfmt is not available
# @arg: $1: file path
################################################################################
basic_bash_cleanup() {
  local file_path="${1}"

  # Convert tabs to spaces
  sed -i 's/\t/    /g' "${file_path}"

  # Remove trailing whitespace
  sed -i 's/[[:space:]]\+$//' "${file_path}"

  # Ensure file ends with newline
  if [[ -s "${file_path}" ]] && [[ $(tail -c1 "${file_path}" | wc -l) -eq 0 ]]; then
    echo >>"${file_path}"
  fi

  # Ensure proper file permissions
  chmod +x "${file_path}" 2>/dev/null || true
}

# Execute main function with all arguments
main "$@"
