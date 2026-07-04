# shellcheck shell=bash
# shellcheck disable=SC2153,SC2206
# Module 04-pfilter: PFILTER validation and serialization
#   bp_serialize_pfilter()               — assoc array to JSON string (via jq)
#   bp_deserialize_to_pfilter()          — JSON string to assoc array (via jq)
#   bp_extract_filter_entry()            — split "type:data:mcg" entry into components
#   bp_extract_enum_list()               — split enum values from |-delimited string
#   bp_validate_key_value_pairs()        -- pass PFILTER with 'key-value' pairs
#   bp_validate_pfilter_entry_type()     — check type is one of bool/string/enum
#   bp_validate_pfilter_default()        — ensure default value matches declared type
#   bp_process_pfilter_entry_mcg_name()  — classify MCG member (d/D/e/m/M) and record
#   bp_validate_mcg_exclusion()          — check exclusion group has >=2 members
#   bp_validate_mcg_dependency()         — check d-member has a D-member
#   bp_validate_mcg_master()             — check M/m master group relationship
#   bp_validate_pfilter_mcgs()           — full cross-member MCG validation
#   bp_validate_pfilter()                — entry point: accept name-ref / JSON / keys-values
# --------------------------------------------------------------------------------

# serialize an associative array to JSON string via jq
# usage: json=$(bp_serialize_pfilter PFILTER)
bp_serialize_pfilter() {
	local -n _flt_ref=$1

	# validate jq
	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}
	# in case not an associative array
	if [[ "$(declare -p "${!_flt_ref}")" != "declare -A"* ]]; then
		# not an associative array, output an emptyp object
		echo "{}"
		return 1
	fi
	# if the associative array is empty
	if [[ ${#_flt_ref[@]} -eq 0 ]]; then
		echo '{}'
		return 1
	fi

	local json first=1 k_esc v_esc k
	json="{"
	for k in "${!_flt_ref[@]}"; do
		if [[ ${first} -eq 0 ]]; then json+=","; fi
		k_esc=$(jq -n --arg s "${k}" '$s')
		v_esc=$(jq -n --arg s "${_flt_ref[${k}]}" '$s')
		json+="${k_esc}: ${v_esc}"
		first=0
	done
	json+="}"

	echo "${json}"
}

# usage
#   bp_deserialize_to_pfilter "${json_str}" PFILTER
bp_deserialize_to_pfilter() {
	local json="$1"
	local -n flt_name="$2"
	local keyj valuej

	bp_validate_jq

	while IFS=$'\t' read -r keyj valuej; do
		flt_name["${keyj}"]="${valuej}"
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
bp_extract_filter_entry() {
	local lid=$1 _entry=$2
	local -n _type=$3 _data=$4 _mcg_name=$5

	local FLD_SEP="${CONFIGS[fs]}"

	local cache_key="${lid}${FLD_SEP}${_entry}"

	# try cache
	bp_read_filter_cache "${cache_key}" _type _data _mcg_name && return 0

	# escape backslashes before FLD-SEPs, to prevent `\\:` being misinterpreted as `\:`
	bp_escape_symbol _entry "\\"
	bp_escape_symbol _entry "${FLD_SEP}"

	local OLD_IFS=${IFS}
	local IFS="${FLD_SEP}"
	read -r _type _data _mcg_name <<<"${_entry}"
	IFS="${OLD_IFS}"

	# regress escaped symbols; no need for Harnesses
	if [[ ${lid} == "${CONFIGS[ulid]}" ]]; then
		bp_escape_symbol _type "${FLD_SEP}" "regress"
		bp_escape_symbol _data "${FLD_SEP}" "regress"
		bp_escape_symbol _mcg_name "${FLD_SEP}" "regress"
		bp_escape_symbol _type "\\" "regress"
		bp_escape_symbol _data "\\" "regress"
		bp_escape_symbol _mcg_name "\\" "regress"
	fi

	# cache result
	bp_write_filter_cache "${cache_key}" "${_type}" "${_data}" "${_mcg_name}"
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

	# in case empty string passed
	if [[ -z ${enum_str:-} ]]; then
		enum_arr=()
		return
	fi

	# substitute escaped symbols before IFS split
	bp_escape_symbol enum_str "\\"
	bp_escape_symbol enum_str "${FLD_SEP}"
	bp_escape_symbol enum_str "${ELM_SEP}"

	# load enum values into array
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
bp_validate_pfilter_entry_type() {
	local _key=$1 _pf_type=$2
	if ! bp_is_array_member "${_pf_type}" PFE_TYPES; then
		local pros_tag[0]="${_key}"
		pros_tag[1]="${_pf_type}"
		pros_tag[2]="$(bp_join_array_members PFE_TYPES "${CONFIGS[es]}")"
		bp_exit_with_msg 33 pros_tag
	else
		bp_msg -3 "        " "- type '${_pf_type}' validated."
	fi
}

# validate default value matches entry type (string/bool/enum)
bp_validate_pfilter_default() {
	local pf_type=$1 pf_data=$2 pf_key=$3 pf_entry=$4

	local pros_tag[0]="${pf_entry}"
	pros_tag[1]="${pf_type}"
	pros_tag[2]="${pf_data}"

	if [[ -n "${pf_data}" ]]; then
		case ${pf_type} in
		# values mismatch entry type
		string) [[ ${pf_data} == true || ${pf_data} == false ]] && bp_exit_with_msg 34 pros_tag ;;
		bool) [[ ${pf_data} == true || ${pf_data} == false ]] || bp_exit_with_msg 34 pros_tag ;;
		*) ;;
		esac
	elif [[ ${pf_type} == 'enum' ]]; then
		# empty enum list not allowed
		pros_tag[0]=$(printf '%s' "[\"${pf_key}\"]=\"${pf_entry}\"")
		bp_exit_with_msg 35 pros_tag
	fi
	bp_msg -3 "        " "- default value '${pf_data}' validated."
	return 0
}

# validate MCG name & type
# record MCG name
# classify member by mcg-name
bp_process_pfilter_entry_mcg_name() {
	local pf_key=$1
	local -n mcg_name_pmn=$2
	local -n _dep_cap_members=$3 _dep_cap_count=$4 _dep_low_members=$5 _dep_low_count=$6
	local -n _mst_cap_members=$7 _mst_cap_count=$8 _mst_low_members=$9 _mst_low_count=${10}
	local -n _excl_low_members=${11} _excl_low_count=${12}

	# all types
	local mcg_types=() mcg_type
	for mcg_type in "${MCG_TYPES[@]}"; do
		mcg_types+=("${mcg_type#*"${CONFIGS[fs]}"}")
	done

	[[ -n ${mcg_name_pmn} ]] || return 0

	# validate mcg name against shell variable naming convention
	bp_substitute_exceptions mcg_name_pmn
	if ! bp_validate_mcg_name "${mcg_name_pmn}"; then
		bp_escape_symbol mcg_name_pmn "${CONFIGS[es]}" "restore"
		local pros_tag[0]="${mcg_name_pmn}"
		pros_tag[1]="it should be a valid shell variable name(with exceptions)"
		bp_exit_with_msg 37 pros_tag
	fi

	# validate mcg type
	if ! bp_is_array_member "${mcg_name_pmn:0:1}" mcg_types; then
		pros_tag[0]="${mcg_name_pmn}"
		local types
		types="$(bp_join_array_members mcg_types "${CONFIGS[es]}")"
		pros_tag[1]="it should respected MCG-TYPES, starts with '${types}'"
		bp_exit_with_msg 37 pros_tag
	fi

	bp_msg -3 "        member: " "${pf_key}@${mcg_name_pmn}"

	# clarify by name(and by type)
	case ${mcg_name_pmn:0:1} in
	D)
		_dep_cap_members["${mcg_name_pmn}"]="${_dep_cap_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_dep_cap_count["${mcg_name_pmn}"] += 1))
		;;
	d)
		_dep_low_members["${mcg_name_pmn}"]="${_dep_low_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_dep_low_count["${mcg_name_pmn}"] += 1))
		;;
	M)
		_mst_cap_members["${mcg_name_pmn}"]="${_mst_cap_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_mst_cap_count["${mcg_name_pmn}"] += 1))
		;;
	m)
		_mst_low_members["${mcg_name_pmn}"]="${_mst_low_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_mst_low_count["${mcg_name_pmn}"] += 1))
		;;
	e)
		_excl_low_members["${mcg_name_pmn}"]="${_excl_low_members[${mcg_name_pmn}]:-}|${pf_key}"
		((_excl_low_count["${mcg_name_pmn}"] += 1))
		;;
	*) ;;
	esac
}

# validate exclusion group: at least two members within same MCG
bp_validate_mcg_exclusion() {
	local mcg_name=$1
	local -n _excl_low_count=$2 _excl_low_members=$3

	if [[ ${_excl_low_count["${mcg_name}"]:-0} -eq 1 ]]; then
		local pros_tag[0]="${mcg_name}"
		pros_tag[1]="${_excl_low_members[${mcg_name}]#\|}"
		bp_exit_with_msg 38 pros_tag
	fi
}

# validate d-member depends on D-member for a single MCG
bp_validate_mcg_dependency() {
	local mcg_name=$1
	local -n _dep_low_count=$2 _dep_cap_count=$3 _dep_low_members=$4

	if [[ ${_dep_low_count["${mcg_name}"]:-0} -gt 0 ]] &&
		[[ ${_dep_cap_count["${mcg_name^}"]:-0} -eq 0 ]]; then
		# no D-member defined for d-members
		local pros_tag[0]="${_dep_low_members[*]#\|}"
		pros_tag[1]="${mcg_name}"
		bp_exit_with_msg 36 pros_tag
	fi
}

# validate m/M master-group relationship for a single MCG
bp_validate_mcg_master() {
	local mcg_name=$1
	local -n _mst_low_count=$2 _mst_cap_count=$3 _mst_low_members=$4 _mst_cap_members=$5

	if [[ ${_mst_low_count["${mcg_name}"]:-0} -gt 1 ]]; then
		# more than one m-member defined for a MCG
		local pros_tag[0]="${mcg_name}"
		pros_tag[1]="only one m-member permitted but got '${_mst_low_members[${mcg_name}]#\|}'"
		bp_exit_with_msg 39 pros_tag
	elif [[ ${_mst_low_count["${mcg_name}"]:-0} -eq 1 ]]; then
		if [[ ${_mst_cap_count["${mcg_name^}"]:-0} -eq 0 ]]; then
			# m-member defined but no M-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="m-member '${_mst_low_members["${mcg_name}"]#\|}' requires a M-member."
			bp_exit_with_msg 39 pros_tag
		fi
	fi

	if [[ ${_mst_cap_count[${mcg_name}]:-} -gt 0 ]]; then
		if [[ ${_mst_low_count["${mcg_name,}"]:-} -eq 0 ]]; then
			# M-member defined but no m-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="no m-member for M-member '${_mst_cap_members[${mcg_name}]#\|}'"
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
bp_validate_pfilter_mcgs() {
	local -n in_pfilter=$1

	bp_msg 3 "      Integrity check"
	declare -a mcg_name_entry=()
	local mcg_name
	declare -A mcg_names=()
	declare -A dep_cap_members=() dep_cap_count=()
	declare -A dep_low_members=() dep_low_count=()
	declare -A mst_cap_members=() mst_cap_count=()
	declare -A mst_low_members=() mst_low_count=()
	declare -A excl_low_members=() excl_low_count=()
	local pf_key pf_entry

	# for mcg_type in "${MCG_TYPES[@]}"; do
	# 	mcg_types+=("${mcg_type#*"${CONFIGS[fs]}"}")
	# done

	for pf_key in "${!in_pfilter[@]}"; do
		local pf_type="" pf_data="" pf_mcg_name=""

		pf_entry="${in_pfilter[${pf_key}]}"
		bp_extract_filter_entry "${CONFIGS[ulid]}" "${pf_entry}" pf_type pf_data pf_mcg_name
		bp_msg -3 "      - extract entry: " "${pf_type} | ${pf_data:--} | ${pf_mcg_name:--}"

		# validate mcg name/type; create group-member mappings
		if [[ -n ${pf_mcg_name} ]]; then
			bp_escape_symbol pf_mcg_name "${CONFIGS[es]}"
			readarray -d "${CONFIGS[es]}" -t mcg_name_entry <<<"${pf_mcg_name}"
			mcg_name_entry[-1]="${mcg_name_entry[-1]%$'\n'}"

			for mcg_name in "${mcg_name_entry[@]}"; do
				bp_escape_symbol mcg_name "${CONFIGS[es]}" "regress"
				mcg_names["${mcg_name}"]=true
				bp_process_pfilter_entry_mcg_name \
					"${pf_key}" mcg_name \
					dep_cap_members dep_cap_count dep_low_members dep_low_count \
					mst_cap_members mst_cap_count mst_low_members mst_low_count \
					excl_low_members excl_low_count
			done
		fi

		bp_validate_pfilter_entry_type "${pf_key}" "${pf_type}"
		bp_validate_pfilter_default "${pf_type}" "${pf_data}" "${pf_key}" "${pf_entry}"
	done

	# validate group member relationships
	for mcg_name in "${!mcg_names[@]}"; do
		bp_validate_mcg_dependency "${mcg_name}" dep_low_count dep_cap_count dep_low_members
		bp_validate_mcg_master "${mcg_name}" mst_low_count mst_cap_count mst_low_members mst_cap_members
		bp_validate_mcg_exclusion "${mcg_name}" excl_low_count excl_low_members
	done

	bp_msg 4 "      PFILTER MCG settings check PASSED"
	return 0
}

bp_validate_key_value_pairs() {
	local -n kv_pairs=$1 _out_pfilter=$2

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
	# populate associative array
	for ((i = 0; i < n; i += 2)); do
		_out_pfilter["${pf_arr[i]}"]="${pf_arr[i + 1]}"
	done
	bp_msg 3 "    'keys-values' pairs found"
}

# load and validate a PFILTER from CONFIGS["pf"] into an associative array
# $1 — nameref: receives the validated PFILTER entries
#
# three input formats accepted:
#   1. name-ref          — a declared associative array name in the caller's scope
#   2. JSON string       — serialized associative array via jq
#   3. "key-value" pairs — space-separated string: key1 key2 ... val1 val2 ...
#
# all input formats must contain a PFILTER_ID key ("PARAM_FILTER" )
# which is removed after validation
# validates each key name: exception substitution, shell variable name check,
# duplicate-after-substitution detection (exit 58)
# then runs full MCG integrity check
bp_validate_pfilter() {
	local -n _pfilter=$1

	local up_filter="${CONFIGS[pf]}"
	local pfilter_id="${CONSTS["PFILTER_ID"]}"

	local pk new_pk

	bp_msg -3 "    " "filter: ${up_filter}"

	if [[ -z ${up_filter} ]]; then
		local pros_tag[0]="it's an 'empty' variable."
		bp_exit_with_msg 31 pros_tag
	fi

	if bp_validate_variable_name "PFILTER name" up_filter true; then
		bp_msg 3 "    PFILTER name: ${up_filter}"

		if [[ "$(declare -p "${up_filter}" 2>/dev/null)" == "declare -A "* ]]; then
			# an associative array
			bp_msg 3 "    An associative array found"
			# if contains id-key
			declare -n flt_tmp="${up_filter}"
			if [[ -v flt_tmp["${pfilter_id}"] ]]; then
				# all test passed
				bp_msg 3 "    PFILTER-ID found"
				for pk in "${!flt_tmp[@]}"; do
					_pfilter["${pk}"]="${flt_tmp[${pk}]}"
				done
				bp_msg 3 "    PFILTER nameref '${up_filter}' supplied"
			else
				# no id-key
				local pros_tag[0]="an identifier key '${pfilter_id}' required"
				bp_exit_with_msg 31 pros_tag
			fi
		else
			# not an associative array
			local pros_tag[0]="not an associative array"
			bp_exit_with_msg 31 pros_tag
		fi
	else
		# not an associative array, try json and "key-value" pairs
		if jq -e . <<<"${up_filter}" >/dev/null 2>&1; then
			# a valid json string
			if ! bp_deserialize_to_pfilter "${up_filter}" _pfilter; then
				local pros_tag[0]="it is not a valid seriliazed associative array"
				bp_exit_with_msg 31 pros_tag
			fi
			bp_msg 3 "    JSON string found"
		else
			# not a json string: try key-value pairs (space-delimited)
			bp_validate_key_value_pairs up_filter _pfilter
		fi
		# if id-key exist, it is
		if [[ -v _pfilter["${pfilter_id}"] ]]; then
			bp_msg 3 "    PFILTER-ID found"
			bp_msg 3 "    Serialized PFILTER supplied"
		else
			local pros_tag[0]="no identifier key '${pfilter_id}' or not an associative array"
			bp_exit_with_msg 31 pros_tag
		fi
	fi

	# remove PFILTER_ID
	# [[ -v _pfilter["${pfilter_id}"] ]] && unset "_pfilter[${pfilter_id}]"
	unset "_pfilter[${pfilter_id}]"

	# populate PFILTER and:
	#   - exception substitution on key
	#   - key name validation against shell variable naming conventions
	for pk in "${!_pfilter[@]}"; do
		new_pk="${pk}"
		bp_substitute_exceptions new_pk
		if bp_validate_variable_name "PFILTER entry key" new_pk true; then
			if [[ ${pk} != "${new_pk}" ]]; then
				# check: new_name exists in filter, conflict
				if [[ -v _pfilter["${new_pk}"] ]]; then
					local pros_tag[0]="${new_pk}"
					pros_tag[1]="${pk}"
					bp_exit_with_msg 58 pros_tag
				fi
				# remove old entry if key name changed after substitution
				_pfilter["${new_pk}"]="${_pfilter[${pk}]}"
				unset "_pfilter[${pk}]"
			fi
		else
			# param-name invalid
			local pros_tag[0]="$(printf '%q' "${pk}")"
			bp_exit_with_msg 32 pros_tag
		fi
	done

	# integrity checking:
	bp_validate_pfilter_mcgs _pfilter

	bp_msg 3 "    PFILTER validated"
}
