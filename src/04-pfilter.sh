# shellcheck shell=bash
# shellcheck disable=SC2153,SC2206
# Module 04-pfilter: PFILTER validation and serialization
#   bp_serialize_pfilter()        — assoc array to JSON string (via jq)
#   bp_deserialize_to_pfilter()   — JSON string to assoc array (via jq)
#   bp_extract_filter_schema()    — split "type:data:mcg" entry into components
#   bp_extract_enum_list()        — split enum values from |-delimited string
#   _bp_validate_pfilter_entry_type() — check type is one of bool/string/enum
#   _bp_validate_pfilter_default()    — ensure default value matches declared type
#   _process_mcg_name()               — classify MCG member (d/D/e/m/M) and record
#   _bp_validate_mcg_exclusion()      — check exclusion group has >=2 members
#   _bp_validate_mcg_dependency()     — check d-member has a D-member
#   _validate_mcg_master()            — check M/m master group relationship
#   bp_pfilter_integrity_check()      — full cross-member MCG validation
#   bp_validate_pfilter()             — entry point: accept name-ref / JSON / keys-values
# --------------------------------------------------------------------------------

# serialize an associative array to JSON string via jq
bp_serialize_pfilter() {
	local -n arr=$1

	# validate jq
	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}
	# in case not an associative array
	if [[ "$(declare -p "${!arr}")" != "declare -A"* ]]; then
		# not an associative array, should output empty?
		echo "{}"
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
#   bp_deserialize_to_pfilter "$pf_str" PFILTER
bp_deserialize_to_pfilter() {
	local json="$1"
	local -n arr_name="$2"
	local keyj valuej

	bp_validate_jq

	while IFS=$'\t' read -r keyj valuej; do
		arr_name["${keyj}"]="${valuej}"
	done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"${json}")
}

# split a PFILTER entry "type:data:mcg" into its three component fields
# $1 — lid context (determines whether to regress symbols after split)
# $2 — entry string (e.g. "bool:true:eg_t")
# $3 — nameref: receives the type field
# $4 — nameref: receives the data field
# $5 — nameref: receives the mcg field
# backslashes and field separators within data are escaped before IFS split,
# then regressed for ulid entries; other lid levels skip regression
bp_extract_filter_schema() {
	local lid=$1 fe_schema=$2
	local -n type_efs=$3 data_efs=$4 mcg_efs=$5

	local FLD_SEP="${CONFIGS[fs]}"

	# escape backslashes before FLD-SEPs, to prevent `\\:` being misinterpreted as `\:`
	bp_escape_symbol fe_schema "\\"
	bp_escape_symbol fe_schema "${FLD_SEP}"

	local OLD_IFS=${IFS}
	local IFS="${FLD_SEP}"
	read -r type_efs data_efs mcg_efs <<<"${fe_schema}"
	IFS="${OLD_IFS}"

	# regress escaped symbols; no need for Harnesses
	if [[ ${lid} == "${CONFIGS[ulid]}" ]]; then
		bp_escape_symbol type_efs "${FLD_SEP}" "regress"
		bp_escape_symbol data_efs "${FLD_SEP}" "regress"
		bp_escape_symbol mcg_efs "${FLD_SEP}" "regress"
		bp_escape_symbol type_efs "\\" "regress"
		bp_escape_symbol data_efs "\\" "regress"
		bp_escape_symbol mcg_efs "\\" "regress"
	fi

	return 0
}

# split an element-separated enum list string into an indexed array
# $1 — enum string (elements separated by CONFIGS[es], typically "|")
# $2 — nameref: receives the resulting array
# escapes backslash, field-sep, and element-sep before IFS split,
# then regresses each element
bp_extract_enum_list() {
	local enum_str=$1
	local -n enum_arr=$2

	local FLD_SEP="${CONFIGS[fs]}"
	local ELM_SEP="${CONFIGS[es]}"
	local ESC_PFX="${CONFIGS[ep]}"

	# in case empty string passed
	if [[ -z ${enum_str:-} ]]; then
		enum_arr=()
		return
	fi

	# substitute escaped symbols before IFS split
	bp_escape_symbol enum_str "\\"
	bp_escape_symbol enum_str "${FLD_SEP}"
	bp_escape_symbol enum_str "${ELM_SEP}"

	# load into array
	readarray -d "${ELM_SEP}" -t enum_arr <<<"${enum_str}"
	enum_arr[-1]="${enum_arr[-1]%$'\n'}"

	# regress escaped symbols in each element
	local i
	for i in "${!enum_arr[@]}"; do
		bp_escape_symbol enum_arr[i] "${ELM_SEP}" "regress"
		bp_escape_symbol enum_arr[i] "${FLD_SEP}" "regress"
		bp_escape_symbol enum_arr[i] "\\" "regress"
	done
}

# validate a single PFILTER entry type against PFE_TYPES
_bp_validate_pfilter_entry_type() {
	local _key=$1 _entry_type=$2
	if ! bp_is_array_member "${_entry_type}" PFE_TYPES; then
		local pros_tag[0]="${_key}"
		pros_tag[1]="${_entry_type}"
		pros_tag[2]="$(bp_join_array_members PFE_TYPES "${CONFIGS[es]}")"
		bp_exit_with_msg 33 pros_tag
	else
		bp_msg -3 "        " "- type '${_entry_type}' validated."
	fi
}

# validate default value matches entry type (string/bool/enum)
_bp_validate_pfilter_default() {
	local entry_type=$1 entry_data=$2 pf_key=$3 entry_schema=$4
	local pros_tag[0]="${entry_schema}"
	pros_tag[1]="${entry_type}"
	pros_tag[2]="${entry_data}"

	if [[ -n "${entry_data}" ]]; then
		case ${entry_type} in
		# values mismatch entry type
		string) [[ ${entry_data} == true || ${entry_data} == false ]] && bp_exit_with_msg 34 pros_tag ;;
		bool) [[ ${entry_data} == true || ${entry_data} == false ]] || bp_exit_with_msg 34 pros_tag ;;
		*) ;;
		esac
	elif [[ ${entry_type} == 'enum' ]]; then
		# empty enum list
		pros_tag[0]=$(printf '%s' "[\"${pf_key}\"]=\"${entry_schema}\"")
		bp_exit_with_msg 35 pros_tag
	fi
	bp_msg -3 "        " "- default value '${entry_data}' validated."
	return 0
}

# validate MCG name, record it, and classify member by type
_process_mcg_name() {
	local pf_key=$1
	local -n mcg_name_pmn=$2
	local -n _mcg_types=$3 _mcg_name_pmns=$4
	local -n _dc_members=$5 _dc_count=$6 _dl_members=$7 _dl_count=$8
	local -n _mc_members=${9} _mc_count=${10} _ml_members=${11} _ml_count=${12}
	local -n _el_members=${13} _el_count=${14}

	bp_escape_symbol mcg_name_pmn "${CONFIGS[es]}" "regress"

	[[ -n ${mcg_name_pmn} ]] || return 0

	# bp_substitute_exceptions mcg_name_pmn
	if ! bp_validate_mcg_name "${mcg_name_pmn}"; then
		bp_escape_symbol mcg_name_pmn "${CONFIGS[es]}" "restore"
		local pros_tag[0]="${mcg_name_pmn}"
		pros_tag[1]="it should be a valid shell variable name(with exceptions)"
		bp_exit_with_msg 37 pros_tag
	fi
	if ! bp_is_array_member "${mcg_name_pmn:0:1}" _mcg_types; then
		pros_tag[0]="${mcg_name_pmn}"
		local types
		types="$(bp_join_array_members _mcg_types "${CONFIGS[es]}")"
		pros_tag[1]="it should respected MCG-TYPES, starts with '${types}'"
		bp_exit_with_msg 37 pros_tag
	fi

	_mcg_name_pmns["${mcg_name_pmn}"]=true
	bp_msg -3 "        member: " "${pf_key}@${mcg_name_pmn}"

	case ${mcg_name_pmn:0:1} in
	D)
		_dc_members["${mcg_name_pmn}"]="${_dc_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_dc_count["${mcg_name_pmn}"] += 1))
		;;
	d)
		_dl_members["${mcg_name_pmn}"]="${_dl_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_dl_count["${mcg_name_pmn}"] += 1))
		;;
	M)
		_mc_members["${mcg_name_pmn}"]="${_mc_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_mc_count["${mcg_name_pmn}"] += 1))
		;;
	m)
		_ml_members["${mcg_name_pmn}"]="${_ml_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_ml_count["${mcg_name_pmn}"] += 1))
		;;
	e)
		_el_members["${mcg_name_pmn}"]="${_el_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_el_count["${mcg_name_pmn}"] += 1))
		;;
	*) ;;
	esac
}

# validate exclusion group: at least two members within same MCG
_bp_validate_mcg_exclusion() {
	local mcg_name=$1
	local -n _el_count=$2 _el_members=$3

	if [[ ${_el_count["${mcg_name}"]:-0} -eq 1 ]]; then
		local pros_tag[0]="${mcg_name}"
		pros_tag[1]="${_el_members[${mcg_name}]#\|}"
		bp_exit_with_msg 38 pros_tag
	fi
}

# validate d-member depends on D-member for a single MCG
_bp_validate_mcg_dependency() {
	local mcg_name=$1
	local -n _dl_count=$2 _dc_count=$3 _dl_members=$4

	if [[ ${_dl_count["${mcg_name}"]:-0} -gt 0 ]] &&
		[[ ${_dc_count["${mcg_name^}"]:-0} -eq 0 ]]; then
		# no D-member defined for d-members
		local pros_tag[0]="${_dl_members[*]#\|}"
		pros_tag[1]="${mcg_name}"
		bp_exit_with_msg 36 pros_tag
	fi
}

# validate m/M master-group relationship for a single MCG
_validate_mcg_master() {
	local mcg_name=$1
	local -n _ml_count=$2 _mc_count=$3 _ml_members=$4 _mc_members=$5

	if [[ ${_ml_count["${mcg_name}"]:-0} -gt 1 ]]; then
		# more than one m-member defined for a MCG
		local pros_tag[0]="${mcg_name}"
		pros_tag[1]="only one m-member permitted but got '${_ml_members[${mcg_name}]#\|}'"
		bp_exit_with_msg 39 pros_tag
	elif [[ ${_ml_count["${mcg_name}"]:-0} -eq 1 ]]; then
		if [[ ${_mc_count["${mcg_name^}"]:-0} -eq 0 ]]; then
			# m-member defined but no M-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="m-member '${_ml_members["${mcg_name}"]#\|}' requires a M-member."
			bp_exit_with_msg 39 pros_tag
		fi
	fi

	if [[ ${_mc_count[${mcg_name}]:-} -gt 0 ]]; then
		if [[ ${_ml_count["${mcg_name,}"]:-} -eq 0 ]]; then
			# M-member defined but no m-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="no m-member for M-member '${_mc_members[${mcg_name}]#\|}'"
			bp_exit_with_msg 39 pros_tag
		fi
	fi
}

# validate all MCG cross-references within a PFILTER
# $1 — nameref to PFILTER associative array
# for each entry: extracts schema, classifies MCG members (d/D/e/m/M),
# validates entry type and default value
# then for each MCG: checks dependency (d→D), master (m↔M), exclusion (e≥2 members)
# exits with 33-39 on violations
bp_pfilter_integrity_check() {
	local -n p_filter=$1

	bp_msg 3 "      Integrity check"
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
		mcg_types+=("${mcg_type#*"${CONFIGS[fs]}"}")
	done

	for pf_key in "${!p_filter[@]}"; do
		local entry_type="" entry_data="" entry_mcg=""

		entry_schema="${p_filter[${pf_key}]}"
		bp_extract_filter_schema "${CONFIGS[ulid]}" "${entry_schema}" entry_type entry_data entry_mcg
		bp_msg -3 "      - extract schema: " "${entry_type} | ${entry_data:--} | ${entry_mcg:--}"

		if [[ -n ${entry_mcg} ]]; then
			bp_escape_symbol entry_mcg "${CONFIGS[es]}"
			readarray -d "${CONFIGS[es]}" -t mcg_name_entry <<<"${entry_mcg}"
			mcg_name_entry[-1]="${mcg_name_entry[-1]%$'\n'}"

			for mcg_name in "${mcg_name_entry[@]}"; do
				_process_mcg_name \
					"${pf_key}" mcg_name \
					mcg_types mcg_names \
					dc_members dc_count dl_members dl_count \
					mc_members mc_count ml_members ml_count \
					el_members el_count
			done
		fi

		_bp_validate_pfilter_entry_type "${pf_key}" "${entry_type}"
		_bp_validate_pfilter_default "${entry_type}" "${entry_data}" "${pf_key}" "${entry_schema}"
	done

	for mcg_name in "${!mcg_names[@]}"; do
		_bp_validate_mcg_dependency "${mcg_name}" dl_count dc_count dl_members
		_validate_mcg_master "${mcg_name}" ml_count mc_count ml_members mc_members
		_bp_validate_mcg_exclusion "${mcg_name}" el_count el_members
	done

	bp_msg 4 "      PFILTER integration check PASSED"
	return 0
}

_bp_validate_key_value_pairs() {
	local -n kv_pairs=$1 _PF=$2

	# not a json string: try key-value pairs (space-delimited)
	declare -a pf_arr=()
	# escape first in case escaped spaces "\\ " missing
	bp_escape_symbol kv_pairs ' '
	readarray -d ' ' -t pf_arr <<<"${kv_pairs}"
	# remove trailing newline '<<<' added as '-t' only remove DELM ' '
	pf_arr[-1]="${pf_arr[-1]%$'\n'}"
	# escape regress
	local i
	for i in "${!pf_arr[@]}"; do
		bp_escape_symbol pf_arr[i] ' ' "regress"
	done
	# if element cout is even number
	local n=${#pf_arr[@]}
	if ((n % 2)); then
		local pros_tag[0]="it is not a valid 'keys-values' string"
		bp_exit_with_msg 31 pros_tag
	fi
	# load into associative array
	for ((i = 0; i < n; i += 2)); do
		_PF["${pf_arr[i]}"]="${pf_arr[i + 1]}"
	done
	bp_msg 3 "    'keys-values' pairs found"
}

# load and validate a PFILTER from CONFIGS["pf"] into an associative array
# $1 — nameref: receives the validated PFILTER entries
#
# three input formats accepted:
#   1. name-ref — a declared associative array name in the caller's scope
#   2. JSON string — serialized associative array via jq
#   3. "keys values" pairs — space-separated string: key1 key2 ... val1 val2 ...
#
# all input formats must contain a PFILTER_ID key ("PARAM_FILTER" or "PARAM_FILTER")
# which is removed after validation
# validates each key name: exception substitution, shell variable name check,
# duplicate-after-substitution detection (exit 58)
# then runs full MCG integrity check
bp_validate_pfilter() {
	local -n PF=$1

	local UP_FILTER="${CONFIGS[pf]}"
	local PFILTER_ID="${CONSTS["PFILTER_ID"]}"

	local pk new_pk

	bp_msg -3 "    " "filter: ${UP_FILTER}"

	if [[ -z ${UP_FILTER} ]]; then
		local pros_tag[0]="it's an 'empty' variable."
		bp_exit_with_msg 31 pros_tag
	fi

	if bp_validate_variable_name "PFILTER name" UP_FILTER true; then
		bp_msg 3 "    PFILTER name: ${UP_FILTER}"

		if [[ "$(declare -p "${UP_FILTER}" 2>/dev/null)" == "declare -A "* ]]; then
			# an associative array
			bp_msg 3 "    An associative array found"
			# if contains id-key
			declare -n tmp="${UP_FILTER}"
			if [[ -v tmp["${PFILTER_ID}"] ]] ; then
				# all test passed
				bp_msg 3 "    PFILTER-ID found"
				for pk in "${!tmp[@]}"; do
					PF["${pk}"]="${tmp[${pk}]}"
				done
				bp_msg 3 "    PFILTER nameref '${UP_FILTER}' supplied"
			else
				# no id-key
				local pros_tag[0]="an identifier key '${PFILTER_ID}' required"
				bp_exit_with_msg 31 pros_tag
			fi
		else
			# not an associative array
			local pros_tag[0]="not an associative array"
			bp_exit_with_msg 31 pros_tag
		fi
	else
		# not an associative array, try json and "key-value" pairs
		if jq -e . <<<"${UP_FILTER}" >/dev/null 2>&1; then
			# a valid json string
			if ! bp_deserialize_to_pfilter "${UP_FILTER}" PF; then
				local pros_tag[0]="it is not a valid seriliazed associative array"
				bp_exit_with_msg 31 pros_tag
			fi
			bp_msg 3 "    JSON string found"
		else
			# not a json string: try key-value pairs (space-delimited)
			_bp_validate_key_value_pairs UP_FILTER PF
		fi
		# if id-key exist, it is
		if [[ -v PF["${PFILTER_ID}"] ]] ; then
			bp_msg 3 "    PFILTER-ID found"
			bp_msg 3 "    Serialized PFILTER supplied"
		else
			local pros_tag[0]="no identifier key '${PFILTER_ID}' or not an associative array"
			bp_exit_with_msg 31 pros_tag
		fi
	fi

	# remove PFILTER_ID
	[[ -v PF["${PFILTER_ID}"] ]] && unset "PF[${PFILTER_ID}]"

	# load PFILTER with:
	#   key name validation
	#   exception substitution on key
	for pk in "${!PF[@]}"; do
		new_pk="${pk}"
		bp_substitute_exceptions new_pk
		if bp_validate_variable_name "PFILTER entry key" new_pk true; then
			if [[ ${pk} != "${new_pk}" ]]; then
				# check: same name after substitution, conflict
				if [[ -v PF["${new_pk}"] ]]; then
					local pros_tag[0]="${new_pk}"
					pros_tag[1]="${pk}"
					bp_exit_with_msg 58 pros_tag
				fi
				# remove old entry if key name changed after substitution
				PF["${new_pk}"]="${PF[${pk}]}"
				unset "PF[${pk}]"
			fi
		else
			# param-name invalid
			local pros_tag[0]="$(printf '%q' "${pk}")"
			bp_exit_with_msg 32 pros_tag
		fi
	done

	# integrity checking:
	bp_pfilter_integrity_check PF

	bp_msg 3 "    PFILTER validated"
}
