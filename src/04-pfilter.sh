# shellcheck shell=bash
# shellcheck disable=SC2153,SC2206
# Module 04-pfilter: PFILTER validation and serialization
#   serialize_pfilter()     — assoc array to JSON string (via jq)
#   deserialize_to_pfilter() — JSON string to assoc array (via jq)
#   extract_filter_schema() — split "type:data:mcg" entry into components
#   extract_enum_list()     — split enum values from |-delimited string
#   _validate_pfilter_entry_type() — check type is one of bool/string/enum
#   _validate_pfilter_default() — ensure default value matches declared type
#   _process_mcg_name()     — classify MCG member (d/D/e/m/M) and record
#   pfilter_integrity_check() — full cross-member MCG validation
#   validate_pfilter()      — entry point: accept name-ref / JSON / keys-values
# --------------------------------------------------------------------------------

# serialize an associative array to JSON string via jq
function serialize_pfilter {
	local -n arr=$1

	# validate jq
	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}
	# in case not an associative array
	if [[ "$(declare -p "${!arr}")" != "declare -A"* ]]; then
		# not an associative array, should output empty?
		echo # "{}"
		return 1
	fi
	# if the associative array is empty
	if [[ ${#arr[@]} -eq 0 ]]; then
		echo '{}'
		return 1
	fi

	local json first=1 k_esc v_esc k
	json="{"
	for k in "${!arr[@]}"; do
		if [[ ${first} -eq 0 ]]; then json+=","; fi
		k_esc=$(jq -n --arg s "${k}" '$s')
		v_esc=$(jq -n --arg s "${arr[${k}]}" '$s')
		json+="${k_esc}: ${v_esc}"
		first=0
	done
	json+="}"

	echo "${json}"
}

# usage
#   deserialize_to_pfilter "$pf_str" PFILTER
function deserialize_to_pfilter {
	local json="$1"
	local -n arr_name="$2"
	local keyj valuej

	validate_jq

	while read -r keyj valuej; do
		arr_name["${keyj}"]="${valuej}"
	done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"${json}")
}

# split PFILTER entry "type:data:mcg" into its component fields
function extract_filter_schema {
	local lid=$1 p_schema=$2
	local -n p_type=$3 p_data=$4 p_mcg=$5

	# escape FLD-SEPs
	escape_symbol p_schema "${FLD_SEP}"

	# for Priors/PSets, remove conf_name field
	[[ ${lid} == "${ULID}" ]] || p_schema=${p_schema#*"${FLD_SEP}"}

	# use 'read' instead of 'awk' to speed up
	local IFS="${FLD_SEP}"
	read -r p_type p_data p_mcg <<<"${p_schema}"

	# regress escaped FLD_SEPs; no need for Priors and PSets
	[[ ${lid} != "${ULID}" ]] || escape_symbol p_data "${FLD_SEP}" "regress"
	[[ ${lid} != "${ULID}" ]] || escape_symbol p_mcg "${FLD_SEP}" "regress"

	return 0
}

# extract enum values string to array and pass back
function extract_enum_list {
	local enum_str=$1
	local -n enum_arr=$2

	# substitude escaped symbol
	escape_symbol enum_str "\\"
	escape_symbol enum_str "${FLD_SEP}"
	escape_symbol enum_str "${ELM_SEP}"

	# load into array
	local IFS="${ELM_SEP}"
	read -ra enum_arr <<<"${enum_str}"

	# clear array member
	local i
	for i in "${!enum_arr[@]}"; do
		escape_symbol enum_arr[i] "${ELM_SEP}" "regress"
		escape_symbol enum_arr[i] "${FLD_SEP}" "regress"
		escape_symbol enum_arr[i] "\\" "regress"
	done
}

# validate a single PFILTER entry type against PFILTER_ENTRY_TYPES
function _validate_pfilter_entry_type {
	local entry_type=$1
	if ! is_array_member "${entry_type}" PFILTER_ENTRY_TYPES; then
		pros_tag="${entry_type}"
		local IFS="${ELM_SEP}"
		pros_tag2="${PFILTER_ENTRY_TYPES[*]}"
		exit_with_msg 33
	fi
}

# validate default value matches entry type (string/bool/enum)
function _validate_pfilter_default {
	local entry_type=$1 entry_data=$2 pf_key=$3 entry_schema=$4
	pros_tag="${entry_schema}"
	pros_tag2="${entry_type}"
	pros_tag3="${entry_data}"

	if [[ -n "${entry_data}" ]]; then
		case ${entry_type} in
		# values mismatch entry type
		string) [[ ${entry_data} == true || ${entry_data} == false ]] && exit_with_msg 34 ;;
		bool) [[ ${entry_data} == true || ${entry_data} == false ]] || exit_with_msg 34 ;;
		*) ;;
		esac
	elif [[ ${entry_type} == 'enum' ]]; then
		# empty enum list
		pros_tag=$(printf '%s' "[\"${pf_key}\"]=\"${entry_schema}\"")
		exit_with_msg 35
	fi
	return 0
}

# validate MCG name, record it, and classify member by type
function _process_mcg_name {
	local pf_key=$1 mcg_name=$2
	local -n _mcg_types=$3 _mcg_names=$4
	local -n _dc_members=$5 _dc_count=$6 _dl_members=$7 _dl_count=$8
	local -n _mc_members=${9} _mc_count=${10} _ml_members=${11} _ml_count=${12}
	local -n _el_members=${13} _el_count=${14}

	escape_symbol mcg_name "${ELM_SEP}" "regress"

	[[ -n ${mcg_name} ]] || return 0

	if ! validate_variable_name mcg_name true; then
		escape_symbol mcg_name "${FLD_SEP}" "restore"
		pros_tag="${mcg_name}"
		pros_tag2="it should be a valid shell variable name(with exceptions)"
		exit_with_msg 37
	fi
	if ! is_array_member "${mcg_name:0:1}" _mcg_types; then
		pros_tag="${mcg_name}"
		local IFS="${ELM_SEP}"
		pros_tag2="it should respected MCG-TYPES, starts with '${_mcg_types[*]}'"
		exit_with_msg 37
	fi

	_mcg_names["${mcg_name}"]=true
	msg_bp 4 "    - member: ${pf_key}@${mcg_name}"

	case ${mcg_name:0:1} in
	D)
		_dc_members["${mcg_name}"]="${_dc_members[${mcg_name}]:-}|${pf_key}"
		((_dc_count["${mcg_name}"] += 1))
		;;
	d)
		_dl_members["${mcg_name}"]="${_dl_members[${mcg_name}]:-}|${pf_key}"
		((_dl_count["${mcg_name}"] += 1))
		;;
	M)
		_mc_members["${mcg_name}"]="${_mc_members[${mcg_name}]:-}|${pf_key}"
		((_mc_count["${mcg_name}"] += 1))
		;;
	m)
		_ml_members["${mcg_name}"]="${_ml_members[${mcg_name}]:-}|${pf_key}"
		((_ml_count["${mcg_name}"] += 1))
		;;
	e)
		_el_members["${mcg_name}"]="${_el_members[${mcg_name}]:-}|${pf_key}"
		((_el_count["${mcg_name}"] += 1))
		;;
	*) ;;
	esac
}

# validate exclusion group: at least two members within same MCG
function _validate_mcg_exclusion {
	local mcg_name=$1
	local -n _el_count=$2 _el_members=$3

	if [[ ${_el_count["${mcg_name}"]:-0} -eq 1 ]]; then
		pros_tag="${mcg_name}"
		pros_tag2="${_el_members[${mcg_name}]#\|}"
		exit_with_msg 38
	fi
}

# validate d-member depends on D-member for a single MCG
function _validate_mcg_dependency {
	local mcg_name=$1
	local -n _dl_count=$2 _dc_count=$3 _dl_members=$4

	if [[ ${_dl_count["${mcg_name}"]:-0} -gt 0 ]] &&
		[[ ${_dc_count["${mcg_name^}"]:-0} -eq 0 ]]; then
		# no D-member defined for d-members
		pros_tag="${_dl_members[*]#\|}"
		pros_tag2="${mcg_name}"
		exit_with_msg 36
	fi
}

# validate m/M master-group relationship for a single MCG
function _validate_mcg_master {
	local mcg_name=$1
	local -n _ml_count=$2 _mc_count=$3 _ml_members=$4 _mc_members=$5

	if [[ ${_ml_count["${mcg_name}"]:-0} -gt 1 ]]; then
		# more than one m-member defined for a MCG
		pros_tag="${mcg_name}"
		pros_tag2="only one m-member permitted but got '${_ml_members[${mcg_name}]#\|}'"
		exit_with_msg 39
	elif [[ ${_ml_count["${mcg_name}"]:-0} -eq 1 ]]; then
		if [[ ${_mc_count["${mcg_name^}"]:-0} -eq 0 ]]; then
			# m-member defined but no M-member defined for a MCG
			pros_tag="${mcg_name}"
			pros_tag2="m-member '${_ml_members["${mcg_name}"]#\|}' requires a M-member."
			exit_with_msg 39
		fi
	fi

	if [[ ${_mc_count[${mcg_name}]:-} -gt 0 ]]; then
		if [[ ${_ml_count["${mcg_name,}"]:-} -eq 0 ]]; then
			# M-member defined but no m-member defined for a MCG
			pros_tag="${mcg_name}"
			pros_tag2="no m-member for M-member '${_mc_members[${mcg_name}]#\|}'"
			exit_with_msg 39
		fi
	fi
}

# validate all MCG cross-references: dependency, master, exclusion integrity
function pfilter_integrity_check {
	declare -a mcg_types=() mcg_name_entry=()
	local mcg_type mcg_name
	declare -A mcg_names=()
	declare -A dc_members=() dc_count=()
	declare -A dl_members=() dl_count=()
	declare -A mc_members=() mc_count=()
	declare -A ml_members=() ml_count=()
	declare -A el_members=() el_count=()
	local pf_key entry_schema

	for mcg_type in "${MCG_TYPES[@]}"; do
		mcg_types+=("${mcg_type#*"${FLD_SEP}"}")
	done

	for pf_key in "${!p_filter[@]}"; do
		local entry_type="" entry_data="" entry_mcg=""

		entry_schema="${p_filter[${pf_key}]}"
		extract_filter_schema "${ULID}" "${entry_schema}" entry_type entry_data entry_mcg

		_validate_pfilter_entry_type "${entry_type}"

		if [[ -n ${entry_mcg} ]]; then
			escape_symbol entry_mcg "${ELM_SEP}"
			local IFS="${ELM_SEP}"
			read -ra mcg_name_entry <<<"${entry_mcg}"
			for mcg_name in "${mcg_name_entry[@]}"; do
				_process_mcg_name \
					"${pf_key}" "${mcg_name}" \
					mcg_types mcg_names \
					dc_members dc_count dl_members dl_count \
					mc_members mc_count ml_members ml_count \
					el_members el_count
			done
		fi

		_validate_pfilter_default "${entry_type}" "${entry_data}" "${pf_key}" "${entry_schema}"
	done

	for mcg_name in "${!mcg_names[@]}"; do
		_validate_mcg_dependency "${mcg_name}" dl_count dc_count dl_members
		_validate_mcg_master "${mcg_name}" ml_count mc_count ml_members mc_members
		_validate_mcg_exclusion "${mcg_name}" el_count el_members
	done

	msg_bp 4 "    - PFILTER integration check PASSED"
	return 0
}

# PFILTER name or serialize PFILTER stored in CONFIGS while parsing if supplied; or it
# will be ${CONST["NO_PFILTER"]} by default
# three ways to pass PFILTER in:
#   1. PFILTER name_ref    - for an associative array, used in source run-mode
#   2. serialized PFILTER  - a json string, used for all run-modes
#   3. "keys values" pairs - ~pf="${!pfilter[*]} ${pfilter[*]}"
# a valid PFILTER must include a member whose key is "PARAM-FILTER" as identifier
function validate_pfilter {
	local pk new_pk

	# msg_bp 4 "    param-filter: ${PARAM_FILTER}"

	if [[ -z ${PARAM_FILTER} ]]; then
		pros_tag="it's an 'empty' variable."
		exit_with_msg 31
	fi
	if validate_variable_name PARAM_FILTER true; then
		msg_bp 3 "  - PFILTER name: ${PARAM_FILTER}"

		if [[ "$(declare -p "${PARAM_FILTER}" 2>/dev/null)" == "declare -A "* ]]; then
			# an associative array
			msg_bp 3 "  - an associative array"
			# if contains id-key
			declare -n tmp="${PARAM_FILTER}"
			if [[ -v tmp["${PFILTER_ID}"] ]]; then
				# all test passed
				msg_bp 3 "  - PFILTER-ID found."
				declare -n "p_filter=${PARAM_FILTER}"
				msg_bp 4 "    - PFILTER nameref '${PARAM_FILTER}' supplied."
			else
				# no id-key
				pros_tag="an identifier key '${PFILTER_ID}' required."
				exit_with_msg 31
			fi
		else
			# not an associative array
			pros_tag="not an associative array."
			exit_with_msg 31
		fi
	else
		# not an associative array, try json and "keys-values" pairs
		local -A p_filter
		if jq -e . >/dev/null 2>&1 <<<"${PARAM_FILTER}"; then
			# a valid json string
			if ! deserialize_to_pfilter "${PARAM_FILTER}" p_filter; then
				pros_tag="it is not a valid seriliazed associative array."
				exit_with_msg 31
			fi
		else
			# a string, may be keys+values stream
			local -a pf_arr
			read -ra pf_arr <<< "${PARAM_FILTER}"
			local len=${#pf_arr[@]}
			if [[ $((len % 2)) -ne 0 ]]; then
				# length not an even number
				pros_tag="it is not a valid 'keys-values' string."
				exit_with_msg 31
			fi
			len=$((len / 2))
			local i
			for ((i = 0; i < len; i += 1)); do
				p_filter["${pf_arr[i]}"]="${pf_arr[$((i + len))]}"
			done
		fi
		# if id-key exist, it is
		if [[ -v p_filter["${PFILTER_ID}"] ]]; then
			msg_bp 4 "    - Serialized PFILTER supplied."
		else
			pros_tag="no identifier key '${PFILTER_ID}' or not an associative array."
			exit_with_msg 31
		fi
	fi

	# remove PFILTER_ID
	unset "p_filter[${PFILTER_ID}]"

	# load PFILTER with:
	#   validate key name
	#   exception substitution on key
	for pk in "${!p_filter[@]}"; do
		new_pk="${pk}"
		if validate_variable_name new_pk true; then
			PFILTER["${new_pk}"]="${p_filter[${pk}]}"
			# remove old entry when p_filter=PFILTER
			[[ ${pk} == "${new_pk}" ]] || unset "PFILTER[${pk}]"
		else # param-name invalid
			pros_tag="${pk}"
			exit_with_msg 32
		fi
	done

	# integrity checking:
	pfilter_integrity_check

	msg_bp 3 "    PFILTER validated"
}
