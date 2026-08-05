# shellcheck shell=bash
#
# Module util: Utility functions
#
#   Debugging & tracing (bp_trace, bp_on_exit, echo2, bp_msg)
#   Symbol escaping/restoring system for safe parameter handling (bp_escape_symbol)
#   String operations (bp_is_number, bp_count_substr, bp_max_array_member_length)
#   Array helpers (bp_key_of_array_member, bp_is_array_member, bp_show_array)
#   LID matching (bp_with_lid)
#   Error exit with contextual messages (bp_exit_with_msg)
#   JSON extraction (bp_capture_json_extract, bp_output_json_whitelist)
#   jq availability validation (bp_validate_jq)
# --------------------------------------------------------------------------------

# bp_trace: show calv stack during debugging
bp_trace() {
	local start=${1:-0} compact=${2:-false}

	local lv levels
	local fn=("${FUNCNAME[@]}")

	if [[ ${compact} == true ]]; then
		local compact_info="" levels=$((start + 2))
		for ((lv = start; lv < levels; lv += 1)); do
			compact_info+=$(printf ' <= %s(%s)' "${fn[lv]}" "${BASH_LINENO[lv]}")
		done
		printf '\e[2m%s\e[0m\n' "${compact_info%}" >&2
	else
		local fld_len

		levels="${#BASH_LINENO[@]}"
		[[ ${#fn[@]} -gt "${levels}" ]] || levels="${#fn[@]}"

		fld_len=$(bp_max_array_member_length "${fn[@]}")
		echo "------- trace ---------" >&2
		for ((lv = start; lv < levels; lv += 1)); do
			printf "%${fld_len}s - %s\n" "${fn[lv]}" "${BASH_LINENO[lv]}" >&2
		done
	fi
}

# bp_on_exit: trap handler that dumps call stack on unexpected exit
bp_on_exit() {
	[[ ${BP_PARSING_STAGE:-} == "Mission complete" ]] || bp_trace 0
}

# stderr print shortcut, for debugging and error messages
echo2() { printf '%s\n' "$*" >&2; }

# operations:
#   mark: symbol -> symbol-with-mark
#           : -> \:
#   substitute: symbol-with-escape-mark -> symbol-name-pattern(default)
#           \: -> <ESC_PFX><SYMBOLNAME>
#   restore: symbol-name-pattern -> symbol-with-escape-mark
#           <ESC_PFX><SYMBOLNAME> -> \:
#   regress: symbol-name-pattern -> symbol
#           <ESC_PFX><SYMBOLNAME> -> :
#   remove: symbol-with-escape-mark -> symbol
#           \: -> :
# globals relied:
#   - CONFIGS (key 'ep' for esc_pfx)
#   - SYMNAMES
bp_escape_symbol() {
	local -n _target_str=$1
	local symbol=$2
	local esc_mode=${3:-substitute}

	local esc_modes=("mark" "substitute" "restore" "regress" "remove")
	local esc_pfx="${CONFIGS[ep]}"

	declare syms pros_tag
	if [[ ! -v SYMNAMES["${symbol}"] ]]; then
		# unsupport symbol
		syms="$(printf '%q' "${!SYMNAMES[@]}")"
		pros_tag[0]="symbol '${symbol}' not supported, available symbols: '${syms}"
		bp_exit_with_msg 29 pros_tag
	fi

	if [[ ${esc_mode} == "mark" ]]; then
		_target_str="${_target_str//"${symbol}"/\\"${symbol}"}"
	elif [[ ${esc_mode} == "substitute" ]]; then
		_target_str="${_target_str//\\"${symbol}"/"${esc_pfx}""${SYMNAMES[${symbol}]}"}"
	elif [[ ${esc_mode} == "restore" ]]; then
		_target_str="${_target_str//"${esc_pfx}""${SYMNAMES[${symbol}]}"/\\"${symbol}"}"
	elif [[ ${esc_mode} == "regress" ]]; then
		_target_str="${_target_str//"${esc_pfx}""${SYMNAMES[${symbol}]}"/"${symbol}"}"
	elif [[ ${esc_mode} == "remove" ]]; then
		_target_str="${_target_str//\\"${symbol}"/"${symbol}"}"
	else
		# unknow escape mode
		pros_tag[0]="invalid escape operation '${esc_mode}', available operations: 'mark|substitute|restore|regress|remove'"
		bp_exit_with_msg 29 pros_tag
	fi
}

# check if string is a valid decimal number
# accepts: optional leading -, single 0 or non-zero-digit prefix, optional fractional part
# rejects: leading zeros (except "0" itself), empty string, leading +, trailing dot
# returns: 0 if valid, 1 otherwise
bp_is_number() {
	if [[ $1 =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]; then
		return 0
	fi
	return 1
}

# count non-overlapping occurrences of substring in string
# echoes the count to stdout; returns 0
# note: bash ${var//pat/} replacement is non-overlapping ("aa" in "aaa" → 1)
# returns 0 for empty substring (no-op)
bp_count_substr() {
	local sub="$1" str="$2"
	[[ -n ${sub} ]] || {
		echo 0
		return
	}
	local stripped="${str//"${sub}"/}"
	echo $(((${#str} - ${#stripped}) / ${#sub}))
}

# join array members with a custom separator
# no need to manipulate IFS in current shell
# $1: array nameref
# $2: symbol as separator, colon by default
# output result via stdout
bp_join_array_members() {
	local -n _in_arr=$1
	local sym=${2:-:}

	local result="" item
	for item in "${_in_arr[@]}"; do
		if [[ -n "${result}" ]]; then
			result+="${sym}"
		fi
		result+="${item}"
	done
	echo "${result}"
}

# calculate max length among array members without external tools('wc'.. )
# usage:
#   bp_max_array_member_length "${sample[@]}"
bp_max_array_member_length() {
	local max_len=0 item len
	for item in "$@"; do
		len=${#item}
		((len > max_len)) && max_len=${len}
	done
	echo "${max_len}"
}

# assert jq is available, exit with code 10 if not
bp_validate_jq() {
	jq --version >/dev/null 2>&1 && return 0
	local pros_tag[0]="jq"
	pros_tag[1]="JSON"
	bp_exit_with_msg 10 pros_tag
}

# find the first key in an associative array whose value matches $1
# $1 - value to search for (literal string comparison)
# $2 - nameref to associative array
# stdout: the matching key
# returns: 0 if found, 1 if not found
bp_key_of_array_member() {
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

# check if a string is a member of an indexed array
# $1 - string to find
# $2 - nameref to indexed array (optional: silently returns 1 if omitted)
# returns: 0 if found, 1 if not found
bp_is_array_member() {
	local str=$1

	if (($# < 2)) || [[ $2 == "" ]]; then
		return 1
	else
		local -n arr_ref=${2:-}
	fi

	local mem
	for mem in "${arr_ref[@]}"; do
		[[ ${mem} == "${str}" ]] && return 0
	done
	return 1
}

# conditional colored message to stderr, filtered by verbosity level
# $1 - msg_level: required verbosity level (negative = one-line mode)
# $2 - title (colored yellow)
# $3 - content (dimmed, shown below title or inline if msg_level < 0)
# prints only when $bp_verbose >= abs($msg_level); no-op when bp_verbose < 1
bp_msg() {
	local msg_level=${1:-0} title=${2:-} content=${3:-}
	local in_one_line

	[[ ${bp_verbose:-0} -ge 1 ]] || return 0
	[[ -n ${title} ]] || {
		echo -e "\e[2mno title\e[0m" >&2
		return 0
	}

	[[ ${msg_level} -lt 0 ]] && {
		in_one_line=true
		msg_level=$((0 - msg_level))
	}

	[[ ${msg_level} -le ${bp_verbose} ]] || return 0

	if [[ ${in_one_line:-false} == true ]]; then
		printf '\e[33m%s\e[0;2m%s\e[0m' "${title}" "${content}" >&2
	else
		printf '\e[33m%s\e[0m' "${title}" >&2
		[[ -n ${content} ]] && printf '\n\e[2m%s\e[0m' "${content}" >&2
	fi
	((${msg_level} == 4)) && bp_trace 1 true || echo >&2
	return 0
}

# bp_exit_with_msg: exit with code and contextual error message
# $1 - exit code (uses +100 developer-message variant when verbose >= 3)
# $2 - optional nameref to pros_tag array for pros_tag[n] substitution
# $3 - optional additional message text (also gets pros_tag substitution)
# globals: EXIT_MSG, bp_verbose
# always exits; does not return
bp_exit_with_msg() {
	local exit_code=$1
	if (($# > 1)); then local -n pt_ref=$2; else local pt_ref=(); fi
	local additional_msg=${3:-}

	if [[ ${bp_verbose:-0} -ge 3 ]]; then
		# use developer message
		[[ -v EXIT_MSG["$((exit_code + 100))"] ]] && ((exit_code += 100))
	fi

	local msg exit_code_orig
	msg="${EXIT_MSG[${exit_code}]}"
	if [[ ${#pt_ref[@]} -gt 0 ]]; then
		# substitute pros_tag placeholders in message
		for index in "${!pt_ref[@]}"; do
			msg="${msg//\$\{pros_tag\["${index}"\]\}/${pt_ref[index]}}"
			additional_msg="${additional_msg//\$\{pros_tag\[${index}\]\}/${pt_ref[index]}}"
		done
	else
		# no pros_tag passed, use 'unknown error'
		exit_code_orig="${exit_code}"
		exit_code=3 # error code for unknow error
		msg="${EXIT_MSG[${exit_code}]} (${exit_code_orig})."
	fi

	printf '\e[33merror %d:\e[0m %s\n' "${exit_code}" "${msg}" >&2
	[[ -z "${additional_msg}" ]] ||
		printf '\e[2m   %s\n\e[0m' "${additional_msg}" >&2

	exit "${exit_code}"
}

# check whether a parameter starts with a given LID (or any known LID)
# $1 - param to test
# $2 - lid string (optional: when empty, tests against all entries in LIDS array)
# matching rules:
#   - exact param == lid → match (solitary LID)
#   - param starts with lid AND is longer AND next char != lid[0] → match
#     (prevents e.g. "~~~" from matching LID "~~" since next char "~" == lid[0])
# returns: 0 if matched, 1 if not matched
bp_with_lid() {
	local param=$1
	local lid=${2:-}

	local lid_len="${#lid}"

	if [[ -n ${lid} ]]; then
		[[ ${param} == "${lid}" ]] && return 0 # match a solitary LID
		[[ 
			${param} == "${lid}"* &&
			${#param} -gt ${lid_len} &&
			${param:lid_len:1} != "${lid:0:1}" ]] &&
			return 0
	else
		# try all lids(include ligas) - note: user ligatures only, no harness ligatures
		local lid
		for lid in "${LIDS[@]}"; do
			lid_len="${#lid}"
			[[ ${param} == "${lid}" ]] && return 0
			[[ ${param} == "${lid}"* &&
				${#param} -gt ${lid_len} &&
				${param:lid_len:1} != "${lid:0:1}" ]] &&
				return 0
		done
	fi
	return 1
}

# show array in a formatted way with specified separator, default separator is '-'
bp_show_array() {
	local -n target_arr=$1
	local separator=${2:--}
	local gap=${3:-1}
	local sort_opt=${4:-}
	local indent=${5:-0}

	# echo >&2 "${!target_arr}:"
	if [[ ${gap} -gt 0 ]]; then
		gap=$(printf '%*s' "${gap}" '')
	else
		gap=''
	fi
	local lmax=0 key
	for key in "${!target_arr[@]}"; do
		((${#key} > lmax)) && lmax=${#key}
	done
	((lmax += (2 + indent)))
	if [[ ${sort_opt} == true ]]; then
		sort_opt=' -n'
	else
		sort_opt=""
	fi
	for key in "${!target_arr[@]}"; do
		printf "%${lmax}s%s%s%s'%s'\n" "${key}" "${gap}" "${separator}" "${gap}" "${target_arr[${key}]}"
	done | sort ${sort_opt} >&2
}

# extract a single value from a JSON string using a jq filter
# Usage: bp_capture_json_extract "$json" '.options.foo' 'default-value'
bp_capture_json_extract() {
	local json="$1" jq_filter="${2:-.}" default="${3:-}"

	bp_validate_jq
	if [[ -z "${json}" ]]; then
		printf '%s' "${default}"
		return 1
	fi

	jq -r --arg default "${default}" "try ${jq_filter} catch \$default" <<<"${json}"
}

# extract specific variables from a JSON string (whitelist pattern)
# usage:
#   bp_output_json_whitelist "${json}" "var1" "var2" "var3"
bp_output_json_whitelist() {
	[[ $# -gt 1 ]] || return 0
	local json=$1
	shift
	local white_list=("$@")

	for k in "${white_list[@]}"; do
		v=$(jq -r --arg k "${k}" '.[$k] // empty' <<<"${json}")
		[[ -n "${v}" ]] && printf -v "${k}" '%s' "${v}"
	done
}
