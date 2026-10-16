#!/usr/bin/env bash
################################################################################
# @file_name: onSave-wrapper.sh
# @version: 1.0.0
# @description: Wrapper script to prevent onSave conflicts with other extensions
# @project_name: qb-compile
# @author: Jason Matthews (JMSolo)
# @license: MIT
# Copyright (C) 2019-2025, QuickBox.IO
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'

# This wrapper script prevents the onSave script from running when called by
# conflicting extensions like foxundermoon.shell-format

# Only allow execution when called by our intended process
if [[ -n "${VSCODE_EXTENSION_ID:-}" ]] && [[ "${VSCODE_EXTENSION_ID}" != "emeraldwalk.runonsave" ]]; then
  exit 0
fi

# Check if we're being called from the correct workspace
if [[ ! -f "${PWD}/developer_resources/format-bash.sh" ]]; then
  exit 0
fi

# If we pass all checks, call the actual onSave script
if [[ $# -ge 2 ]]; then
  exec "${PWD}/developer_resources/onSave" "$@"
else
  echo "Usage: $0 <file> <workspace>"
  exit 1
fi
