# shellcheck shell=bash
# Module 01-util: Utility functions
#   Debugging & tracing (trace, on_exit_bp, msg_bp)
#   Symbol escaping/restoring system for safe parameter handling
#   String operations (count_substr, max_array_member_length)
#   Array helpers (key_of_array_member, is_array_member, show_array)
#   LID matching (with_lid)
#   Error exit with contextual messages (exit_with_msg)
#   Variable name exception substitution (substitute_exceptions)
#   jq availability validation
# --------------------------------------------------------------------------------

# trace: show call stack during debugging
function trace {
	local start=${1:-0} ll

	[[ ${verbose:-1} -gt 3 ]] || return
	local ln_levels fld_len

	local fn=("${FUNCNAME[@]}")

	ln_levels="${#BASH_LINENO[@]}"
	[[ ${#fn[@]} -gt "${ln_levels}" ]] || ln_levels="${#fn[@]}"

	fld_len=$(max_array_member_length "${fn[@]}")

	for ((ll = start; ll < ln_levels; ll += 1)); do
		printf "%${fld_len}s - %s\n" "${fn[ll]}" "${BASH_LINENO[ll]}" >&2
	done
}

# on_exit_bp: trap handler that dumps call stack on unexpected exit
function on_exit_bp {
	[[ ${BP_PARSING_STAGE:-} == "Mission complete." ]] || trace 2
}

# stderr print shortcut, for debugging and error messages
function echo2 { printf '%s\n' "$*" >&2; }

# operations:
#   mark: symbol -> symbol-with-mark
#           : -> \:
#   substitue: symbol-with-escape-mark -> symbol-name-pattern(default)
#           \: -> <BP_ESC_PFX><SYMBOLNAME>__
#   restore: symbol-name-pattern -> symbol-with-escape-mark
#           <BP_ESC_PFX><SYMBOLNAME>__ -> \:
#   regress: symbol-name-pattern -> symbol
#           <BP_ESC_PFX><SYMBOLNAME>__ -> :
#   remove: symbol-with-escape-mark -> symbol
#           \: -> :
function escape_symbol {
	local -n target_str=$1
	local symbol=$2
	local op=${3:-substitute}

	if [[ ${op} == "mark" ]]; then
		target_str="${target_str//"${symbol}"/\\"${symbol}"}"
	elif [[ ${op} == "substitute" ]]; then
		target_str="${target_str//\\"${symbol}"/"${BP_ESC_PFX}""${SYMNAMES[${symbol}]}"__}"
	elif [[ ${op} == "restore" ]]; then
		target_str="${target_str//"${BP_ESC_PFX}""${SYMNAMES[${symbol}]}"__/\\"${symbol}"}"
	elif [[ ${op} == "regress" ]]; then
		target_str="${target_str//"${BP_ESC_PFX}""${SYMNAMES[${symbol}]}"__/"${symbol}"}"
	elif [[ ${op} == "remove" ]]; then
		target_str="${target_str//\\"${symbol}"/"${symbol}"}"
	else
		:
	fi
}

# count occurrences of substring in string
function count_substr {
	local sub="$1" str="$2"
	[[ -n ${sub} ]] || {
		echo 0
		return
	}
	local stripped="${str//"${sub}"/}"
	echo $(((${#str} - ${#stripped}) / ${#sub}))
}

# calculate max length among array members without external tools('wc'.. )
# usage:
#   max_length "${sample[@]}"
function max_array_member_length {
	local max_len=0 item len
	for item in "$@"; do
		len=${#item}
		((len > max_len)) && max_len=${len}
	done
	echo "${max_len}"
}

# assert jq is available, exit with code 10 if not
function validate_jq {
	jq --version >/dev/null 2>&1 || exit_with_msg 10
}

# require a minimum Bash version and exit plainly if not available
function require_bash_version {
	local major=${1:-4} minor=${2:-4}
	if (( BASH_VERSINFO[0] < major || (BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor) )); then
		printf 'BosParse requires bash %d.%d or newer. Current: %d.%d\n' "${major}" "${minor}" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" >&2
		exit 1
	fi
}

# extract a single value from capture-mode JSON output using a jq filter
# Usage: capture_json_extract "$json" '.options.foo' 'default-value'
function capture_json_extract {
	local json="$1" jq_filter="${2:-.}" default="${3:-}"

	validate_jq
	if [[ -z "${json}" ]]; then
		printf '%s' "${default}"
		return 1
	fi

	jq -r --arg default "${default}" "try ${jq_filter} catch \$default" <<<"${json}"
}

# find array key of a member
function key_of_array_member {
	local member=$1
	local -n arr_ref=$2
	local key

	for key in "${!arr_ref[@]}"; do
		if [[ ${arr_ref["${key}"]} == "${member}" ]]; then
			echo "${key}"
			return 0
		fi
	done
	return 1
}

# chck if a string is an array member
function is_array_member {
	local str=$1
	local -n arr_ref=${2:-} # array might not available

	local mem
	for mem in "${arr_ref[@]}"; do
		[[ ${mem} == "${str}" ]] && return 0
	done
	return 1
}

# conditional colored message to stderr, filtered by verbosity level
# show msg in one-line if msg-level little than zero
function msg_bp {
	local msg_level=${1:-0} title=${2:-} content=${3:-}
	local in_one_line

	[[ ${verbose:-0} -ge 1 ]] || return 0
	[[ -n ${title} ]] || {
		echo
		return 0
	}

	[[ ${msg_level} -lt 0 ]] && {
		in_one_line=true
		msg_level=$((0 - msg_level))
	}

	[[ ${msg_level} -le ${verbose} ]] || return 0

	if [[ ${in_one_line:-false} == true ]]; then
		printf '\e[33m%s\e[0;2m%s\e[0m\n' "${title}" "${content}" >&2
	else
		printf '\e[33m%s\e[0m\n' "${title}" >&2
		[[ -n ${content} ]] && printf '\e[2m%s\e[0m\n' "${content}" >&2
	fi
	return 0
}

# render and print a formatted exit message for the current error context
function render_exit_msg {
	local exit_code=$1
	local additional_msg=${2:-}
	local msg

	msg="$(eval echo "\"${EXIT_MSG[${exit_code}]}\"")"
	printf '\e[33merror %d:\e[0m %s\n' "${exit_code}" "${msg}" >&2

	if [[ -n "${additional_msg}" ]]; then
		additional_msg="$(eval echo "\"${additional_msg}\"")"
		printf '\e[2m        %s\e[0m\n' "${additional_msg}" >&2
	fi
}

# exit with a specific exit code and a relevant message
function exit_with_msg {
	local exit_code=$1
	local additional_msg=${2:-}
	local last_command=${3:-}

	if [[ ${verbose:-0} -ge 3 ]]; then
		# use developer message
		[[ -v EXIT_MSG["$((exit_code + 100))"] ]] && ((exit_code += 100))
		trace
	fi

	if [[ "${verbose:-0}" -gt 0 ]]; then
		render_exit_msg "${exit_code}" "${additional_msg}"
		[[ -n "${last_command}" ]] && bash -c -- "${last_command}" >&2
	fi
	exit "${exit_code}"
}

# check if a parameter is a LID or starts with a LID, if the second parameter is given, only check
# against that LID, otherwise check against all LIDs(including ligatures)
function with_lid {
	local param=$1 lid=${2:-}
	local lid_len="${#lid}"

	if [[ -n ${lid} ]]; then
		[[ ${param} == "${lid}" ]] && return 0 # match a solitary LID
		[[ 
			${param} == "${lid}"* &&
			${#param} -gt ${lid_len} &&
			${param:lid_len:1} != "${lid:0:1}" ]] &&
			return 0
	else
		# try all lids(include ligas) - note: user ligatures only, no PSets ligatures
		local Lid lids lid_len
		lids=("${SLID}" "${PRLID}" "${PLID}" "${ULID}" "${ULID}${ULID}")
		for Lid in "${lids[@]}"; do
			lid_len="${#Lid}"
			[[ ${param} == "${Lid}" ]] && return 0
			[[ ${param} == "${Lid}"* &&
				${#param} -gt ${lid_len} &&
				${param:lid_len:1} != "${Lid:0:1}" ]] &&
				return 0
		done
	fi
	return 1
}

# show array in a formatted way with specified separator, default separator is '-'
function show_array {
	local -n target_arr=$1
	local separator=${2:--}
	local gap=${3:-1}

	if [[ ${gap} -gt 0 ]]; then
		gap=$(printf '%*s' "${gap}" '')
	else
		gap=''
	fi
	local lmax=0 key
	for key in "${!target_arr[@]}"; do
		((${#key} > lmax)) && lmax=${#key}
	done
	((lmax += 2))
	for key in "${!target_arr[@]}"; do
		printf "%${lmax}s%s%s%s%s \n" "${key}" "${gap}" "${separator}" "${gap}" "${target_arr[${key}]}" >&2
	done
}

# replace exception characters (e.g. hyphens) in variable names per EXCEPTIONS map
function substitute_exceptions {
	[[ -n ${1:-} ]] || return 0
	local -n var_name=$1
	local except_char

	for except_char in "${!EXCEPTIONS[@]}"; do
		var_name=${var_name//"${except_char}"/"${EXCEPTIONS[${except_char}]}"}
	done
}
