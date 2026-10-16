#!/usr/bin/env bash
################################################################################
# @file_name: format-bash.sh
# @version: 1.0.1
# @description: Bash file formatter with version incrementing - no save conflicts
# @project_name: qb-compile
# @author: Jason Matthews (JMSolo)
# @license: MIT
# Copyright (C) 2019-2025, QuickBox.IO
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'

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
          echo "✓ Version incremented from ${version_old} to ${version_new}"
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
        echo "✓ Version incremented from ${version_old} to ${version_new}"
      fi
    fi
  fi
}

################################################################################
# @description: Format a single bash file
# @arg: $1: file path
# @arg: $2: workspace path (optional)
################################################################################
format_file() {
  local file_path="${1}"
  local workspace_path="${2:-$(pwd)}"

  if [[ ! -f "${file_path}" ]]; then
    echo "Error: File not found: ${file_path}" >&2
    return 1
  fi

  if [[ ! "${file_path}" =~ \.sh$ ]] && [[ ! $(head -n1 "${file_path}") =~ bash ]]; then
    echo "Error: Not a bash file: ${file_path}" >&2
    return 1
  fi

  echo "Processing: ${file_path}"

  # First, increment version if enabled
  local metadata_info
  metadata_info=$(parse_metadata "${file_path}")
  increment_version "${file_path}" "${metadata_info}"

  # Then format the file
  echo "Formatting: ${file_path}"

  # Check if shfmt is available
  if ! command -v shfmt &>/dev/null; then
    echo "shfmt not found. Installing..." >&2
    install_shfmt
  fi

  # Format the file with shfmt
  if shfmt -i 2 -w "${file_path}" 2>/dev/null; then
    echo "✓ Successfully formatted with shfmt"

    # Additional cleanup
    cleanup_bash_file "${file_path}"
  else
    echo "Warning: shfmt formatting failed, applying basic cleanup" >&2
    basic_bash_cleanup "${file_path}"
  fi
}

################################################################################
# @description: Install shfmt if not available
# @noargs
################################################################################
install_shfmt() {
  # Try to install shfmt via go
  if command -v go &>/dev/null; then
    go install mvdan.cc/sh/v3/cmd/shfmt@latest
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
      export PATH="$HOME/go/bin:$PATH"
    fi
  else
    # Fallback to direct download
    local shfmt_version="v3.8.0"
    local arch
    arch=$(uname -m)

    case "${arch}" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) arch="amd64" ;; # Default fallback
    esac

    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    local download_url="https://github.com/mvdan/sh/releases/download/${shfmt_version}/shfmt_${shfmt_version}_${os}_${arch}"

    echo "Downloading shfmt ${shfmt_version} for ${os}_${arch}..." >&2
    if curl -L -o /tmp/shfmt "${download_url}"; then
      chmod +x /tmp/shfmt
      sudo mv /tmp/shfmt /usr/local/bin/shfmt
      echo "shfmt installed successfully" >&2
    else
      echo "Failed to install shfmt. Using basic cleanup only." >&2
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
    echo "Added missing shebang"
  fi

  # Ensure strict mode is present (add if missing)
  if ! grep -q "set -Eeuo pipefail" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\set -Eeuo pipefail" "${file_path}"
      echo "Added strict mode"
    fi
  fi

  # Ensure IFS is set properly
  if ! grep -q "IFS=" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\IFS=\$'\\n\\t'" "${file_path}"
      echo "Added IFS setting"
    fi
  fi

  # Ensure inherit_errexit is set if available
  if ! grep -q "inherit_errexit" "${file_path}"; then
    # Find the first line after shebang and comments
    local insert_line
    insert_line=$(grep -n "^[^#]" "${file_path}" | head -n1 | cut -d: -f1)
    if [[ -n "${insert_line}" ]]; then
      sed -i "${insert_line}i\\shopt -s inherit_errexit 2>/dev/null || true" "${file_path}"
      echo "Added inherit_errexit setting"
    fi
  fi

  # Remove trailing whitespace
  sed -i 's/[[:space:]]\+$//' "${file_path}"

  # Ensure file ends with newline
  if [[ -s "${file_path}" ]] && [[ $(tail -c1 "${file_path}" | wc -l) -eq 0 ]]; then
    echo >>"${file_path}"
    echo "Added trailing newline"
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

  echo "Applied basic cleanup"
}

################################################################################
# @description: Main function
# @noargs
################################################################################
main() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <file1> [file2] [file3] ..."
    echo "   or: $0 --all (format all .sh files in src/)"
    exit 1
  fi

  if [[ "${1}" == "--all" ]]; then
    echo "Formatting all bash files in src/..."
    find src -name "*.sh" -exec "$0" {} \;
  else
    for file in "$@"; do
      format_file "${file}"
    done
  fi
}

# Execute main function with all arguments
main "$@"
