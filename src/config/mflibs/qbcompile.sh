#!/usr/bin/env bash
################################################################################
# shellcheck disable=SC1091,SC2001,SC2154,SC2249,SC2254,SC2312
################################################################################

# Import mflibs shell functions
source "/opt/mflibs/src/libs/shell.sh"
# Initialize MFLIBS_LOADED with log enabled
mflibs::log::init
declare -xg mflibs_log_location="/opt/qb-compile/logs/compilation.log"
MFLIBS_LOADED+=(log)
# Load the shell library
MFLIBS_LOADED+=(shell)
#echo "[DEBUG] MFLIBS_LOADED: ${MFLIBS_LOADED[*]}"

################################################################################
# @description: outputs new line
# @noargs
################################################################################
mflibs::shell::misc::nl() {
	printf "\n"
	[[ " ${MFLIBS_LOADED[*]} " =~ log ]] && printf "\n" >>"${mflibs_log_location:?}"
}

mflibs::shell::output() {
	declare shell_reset
	shell_reset=$(tput sgr0)

	# Set default values for newline handling
	if [[ -z ${shell_newline} ]]; then
		declare shell_newline="\n"
	else
		unset shell_newline
	fi

	# Handle shell icons if provided
	if [[ -n ${shell_icon} && -n "$*" ]]; then
		declare shell_newline="\n"
	elif [[ -n ${shell_icon} && -z "$*" ]]; then
		unset shell_newline
	fi

	# Map shell options to tput values
	case "${shell_option}" in
	bold) shell_option=$(tput bold) ;;
	underline) shell_option=$(tput smul) ;;
	standout) shell_option=$(tput smso) ;;
	esac

	# Map shell icons to symbols
	case "${shell_icon}" in
	arrow) shell_icon="➜ ${shell_reset}" ;;
	warning) shell_icon="⚠ ${shell_reset}" ;;
	check) shell_icon="✓ ${shell_reset}" ;;
	cross) shell_icon="✗ ${shell_reset}" ;;
	esac

	# Output the formatted message to the shell
	printf -- "${shell_reset}${shell_color}${shell_icon}${shell_option}%s${shell_newline}${shell_reset}" "$@"

	# Handle log file output with consistent message prefix and strip terminal formatting
	if [[ " ${MFLIBS_LOADED[*]} " =~ log ]]; then
		# Assign log message prefix based on explicit shell text command used
		if [[ ${shell_color} == "$(tput setaf 1)" ]]; then
			log_prefix="[ERROR]"
		elif [[ ${shell_color} == "$(tput setaf 3)" ]]; then
			log_prefix="[WARNING]"
		elif [[ ${shell_color} == "$(tput setaf 2)" ]]; then
			log_prefix="[SUCCESS]"
		elif [[ ${shell_color} == "$(tput setaf 4)" ]]; then
			log_prefix="[INFO]"
		elif [[ ${shell_color} == "$(tput setaf 5)" ]]; then
			log_prefix="[DEBUG]"
		elif [[ ${shell_color} == "$(tput setaf 6)" ]]; then
			log_prefix="[NOTICE]"
		elif [[ ${shell_color} == "$(tput setaf 7)" ]]; then
			log_prefix="[CUSTOM]"
		else
			log_prefix="[INFO]" # Default prefix
		fi

		# Log the message without color codes
		printf "${log_prefix} %s${shell_newline}" "$(echo "$@" | sed -e 's/\x1B\[[0-9;]*[JKmsu]//g')" >>"${mflibs_log_location}"
	fi

	unset shell_color shell_newline shell_option shell_icon
}
