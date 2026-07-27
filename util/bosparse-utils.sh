#!/bin/env bash

# utilities to serialize PFILTER and emit variables from result in JSON

# bp_pfilter_to_json_string()    - serialize PFILTER to JSON string
# bp_pfilter_to_element_stream() - serialize a PFILTER to ELM-STREAM
# bp_pfilter_to_kv_sequence()    - serialize a PFILTER to KV_SEQUENCE

# bp_capture_json_extract()   - extract a single value from capture-mode JSON output
# bp_output_json_whitelist()  - secure output specific vairables from a json string
#
# cation:
#   - passing the name reference of the PFILTER is recommended in source mode
#   - passing json string is recommended for external calls
#   - when running on Bash 5.2+, 'kv-sequence' can be create via parameter expansion:
#     `kv_sequnce="${PFILTER[@]@k}"`

# serialize PFILTER(associative array) to JSON string via jq
# usage:
#   json=$(bp_pfilter_to_json_string PFILTER)
bp_pfilter_to_json_string() {
	local -n _filter=$1

	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}
	if [[ "$(declare -p "${!_filter}")" != "declare -A"* ]]; then
		echo "{}"
		return 1
	fi
	if [[ ${#_filter[@]} -eq 0 ]]; then
		echo '{}'
		return 1
	fi

	local json k_esc v_esc k
	json="{"
	for k in "${!_filter[@]}"; do
		k_esc=$(jq -n --arg s "${k}" '$s')
		v_esc=$(jq -n --arg s "${_filter[${k}]}" '$s')
		json+="${k_esc}: ${v_esc},"
	done
	json="${json%,}"
	json+="}"

	echo "${json}"
}

# serialize a PFILTER to ELM-STREAM
# usage:
#   bp_pfilter_to_element_stream PFILTER ELM_STREAM
# $1: nameref of a PFILTER
# $2: nameref of the created ELM-STREAM
# ELM-STREAM format: key1=value1 key2=value2 ...
# caution:
#   spaces in PFILTER entries should be escaped beforehand
#   spaces at beginning and end of stream string should be trimed before return
bp_pfilter_to_element_stream() {
	local -n _filter_map=$1 _element_stream=$2

	local key
	for key in "${!_filter_map[@]}"; do
		_element_stream+="${key}=${_filter_map[${key}]} "
	done
	# IMPORTANT: remove last space
	_element_stream="${_element_stream% }"
}

# serialize a PFILTER to KV_SEQUENCE
# usage:
#   bp_pfilter_to_kv_sequence PFILTER KV_SEQUENCE
# $1: nameref of a PFILTER
# $2: nameref of the created KV_SEQUENCE
# ELM-STREAM format: key1 value1 key2 value2 ...
# caution:
#   spaces in PFILTER entries should be escaped (" " -> "\ ") beforehand
#   order matters, no solitary key or value allowed
#   spaces at beginning and end should be trimed before return
bp_pfilter_to_kv_sequence() {
	local -n _filter_map=$1 _kv_sequence=$2

	local key
	for key in "${!_filter_map[@]}"; do
		_kv_sequence+="${key} ${_filter_map[${key}]} "
	done
	# IMPORTANT: remove last space
	_kv_sequence="${_kv_sequence% }"
}

# extract a single value from capture-mode JSON output
# Usage:
#   capture_json_extract "$json" '.options.foo' 'default-value'
# $1: JSON string output by bosparse
# $2: which objects to extract, '.' for all[default]
# $3: defautl value for empty entries
bp_capture_json_extract() {
	local json="$1" jq_filter="${2:-.}" default="${3:-}"

	command -v jq >/dev/null 2>&1 || return 1

	if [[ -z "${json}" ]]; then
		printf '%s' "${default}"
		return 1
	fi

	jq -r --arg default "${default}" "try ${jq_filter} catch \$default" <<<"${json}"
}

# secure output specific vairables from a json string
# usage:
#   output_json_whitelist "${json}" "var1" "var2" "var3"
bp_output_json_whitelist() {
	[[ $# -gt 1 ]] || return 0
	local json=$1
	shift
	local white_list=("$@")

	command -v jq >/dev/null 2>&1 || return 1

	for k in "${white_list[@]}"; do
		v=$(jq -r --arg k "${k}" '.[$k] // empty' <<<"${json}")
		[[ -n "${v}" ]] && printf -v "${k}" '%s' "${v}"
	done
}
