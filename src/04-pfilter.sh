# shellcheck shell=bash
# shellcheck disable=SC2153,SC2206
# Module 04-pfilter: PFILTER validation and serialization
#   bp_serialize_pfilter_to_json_string()    - assoc array to JSON string (via jq)
#   bp_serialize_pfilter_to_element_stream() - assoc array to element stream
#   bp_serialize_pfilter_to_kv_sequence()    - assoc array to key-value sequence
#
#   bp_deserialize_json_string_to_pfilter()  - JSON string to assoc array (via jq)
#
#   bp_validate_pfilter_json_string()     - check PFILTER against json
#   bp_validate_pfilter_element_stream()  - check PFILTER against 'key=value' format items
#   bp_validate_pfilter_kv_sequence()     - check PFILTER against 'key-value' pairs
#
#   bp_extract_enum_value_list()          - split enum values from |-delimited string
#
#   bp_validate_pfilter_entry_type()      - check type is one of bool/string/enum
#   bp_validate_pfilter_default()         - ensure default value matches declared type
#   bp_process_pfilter_entry_mcg_name()   - classify MCG member (d/D/e/m/M) and record
#   bp_validate_mcg_exclusion()           - check exclusion group has >=2 members
#   bp_validate_mcg_dependency()          - check d-member has a D-member
#   bp_validate_mcg_master()              - check M/m master group relationship
#   bp_validate_pfilter_mcg_settings()    - full cross-member MCG validation
#   bp_validate_pfilter()                 - entry point: accept name-ref / JSON / keys-values
# --------------------------------------------------------------------------------

# serialize an associative array to JSON string via jq
# usage: json=$(bp_serialize_pfilter_to_json_string PFILTER)
bp_serialize_pfilter_to_json_string() {
	local -n _filter=$1

	# validate jq
	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}
	# in case not an associative array
	if [[ "$(declare -p "${!_filter}")" != "declare -A"* ]]; then
		# not an associative array, output an emptyp object instead of an 'empty'
		echo "{}"
		return 1
	fi
	# if the associative array is empty
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
	json="${json%,}" # remove last comma ','
	json+="}"

	echo "${json}"
}

bp_serialize_pfilter_to_element_stream() {
	local -n _filter_map=$1 _element_stream=$2

	local key
	for key in "${!_filter_map[@]}"; do
		_element_stream+="${key}=${_filter_map[${key}]} "
	done
	# IMPORTANT: remove last space
	_element_stream="${_element_stream% }"
}

bp_serialize_pfilter_to_kv_sequence() {
	local -n _filter_map=$1 _kv_sequence=$2

	local key
	for key in "${!_filter_map[@]}"; do
		_kv_sequence+="${key} ${_filter_map[${key}]} "
	done
	# IMPORTANT: remove last space
	_kv_sequence="${_kv_sequence% }"
}

# usage
#   bp_deserialize_json_string_to_pfilter "${json_str}" PFILTER
bp_deserialize_json_string_to_pfilter() {
	local json="$1"
	local -n _filter="$2"
	local keyj valuej

	bp_validate_jq

	while IFS=$'\t' read -r keyj valuej; do
		_filter["${keyj}"]="${valuej}"
	done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"${json}")
}

# split an element-separated enum list string into an indexed array
# $1 - enum string (elements separated by CONFIGS[es], typically "|")
# $2 - nameref: receives the resulting array
# escapes backslash, field-sep, and element-sep before IFS split,
# then regresses each element
bp_extract_enum_value_list() {
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
	local key=$1 fe_type=$2
	if ! bp_is_array_member "${fe_type}" PFE_TYPES; then
		local pros_tag[0]="${key}"
		pros_tag[1]="${fe_type}"
		pros_tag[2]="$(
			IFS="${CONFIGS[es]}"
			echo "${PFE_TYPES[*]}"
		)"
		bp_exit_with_msg 33 pros_tag
	else
		bp_msg -3 "        " "- type '${fe_type}' validated."
	fi
}

# validate default value matches entry type (string/bool/enum)
bp_validate_pfilter_default() {
	local fe_type=$1 fe_data=$2 fe_key=$3 fe_entry=$4

	local pros_tag[0]="${fe_entry}"
	pros_tag[1]="${fe_type}"
	pros_tag[2]="${fe_data}"

	if [[ -n "${fe_data}" ]]; then
		case ${fe_type} in
		# values mismatch entry type
		string) [[ ${fe_data} == true || ${fe_data} == false ]] && bp_exit_with_msg 34 pros_tag ;;
		bool) [[ ${fe_data} == true || ${fe_data} == false ]] || bp_exit_with_msg 34 pros_tag ;;
		*) ;;
		esac
	elif [[ ${fe_type} == 'enum' ]]; then
		# empty enum list not allowed
		pros_tag[0]=$(printf '%s' "[\"${fe_key}\"]=\"${fe_entry}\"")
		bp_exit_with_msg 35 pros_tag
	fi
	bp_msg -3 "        " "- default value '${fe_data}' validated."
	return 0
}

# validate MCG name against bash name
# validate MCG type
# record MCG name
# classify member by mcg-name
bp_process_pfilter_entry_mcg_name() {
	local fe_key=$1
	local -n fe_mcg_name=$2
	local -n _dep_cap_members=$3 _dep_cap_count=$4 _dep_low_members=$5 _dep_low_count=$6
	local -n _mst_cap_members=$7 _mst_cap_count=$8 _mst_low_members=$9 _mst_low_count=${10}
	local -n _excl_low_members=${11} _excl_low_count=${12}

	# all types
	local mcg_types=() mcg_type
	for mcg_type in "${MCG_TYPES[@]}"; do
		mcg_types+=("${mcg_type#*"${CONFIGS[fs]}"}")
	done

	[[ -n ${fe_mcg_name} ]] || return 0

	# validate mcg name against shell variable naming convention
	bp_substitute_variable_name_exceptions fe_mcg_name
	if ! bp_validate_variable_name "mcg name" fe_mcg_name true; then
		bp_escape_symbol fe_mcg_name "${CONFIGS[es]}" "restore"
		local pros_tag[0]="${fe_mcg_name}"
		pros_tag[1]="it should be a valid shell variable name(with exceptions)"
		bp_exit_with_msg 37 pros_tag
	fi

	# validate mcg type
	if ! bp_is_array_member "${fe_mcg_name:0:1}" mcg_types; then
		pros_tag[0]="${fe_mcg_name}"
		local types
		types="$(
			IFS="${CONFIGS[es]}"
			echo "${mcg_types[*]}"
		)"
		pros_tag[1]="it should respected MCG-TYPES, starts with '${types}'"
		bp_exit_with_msg 37 pros_tag
	fi

	bp_msg -3 "        member: " "${fe_key}@${fe_mcg_name}"

	# clarify by name(and by type)
	case ${fe_mcg_name:0:1} in
	D)
		_dep_cap_members["${fe_mcg_name}"]="${_dep_cap_members[${fe_mcg_name}]:-}|${fe_key}"
		((_dep_cap_count["${fe_mcg_name}"] += 1))
		;;
	d)
		_dep_low_members["${fe_mcg_name}"]="${_dep_low_members[${fe_mcg_name}]:-}|${fe_key}"
		((_dep_low_count["${fe_mcg_name}"] += 1))
		;;
	M)
		_mst_cap_members["${fe_mcg_name}"]="${_mst_cap_members[${fe_mcg_name}]:-}|${fe_key}"
		((_mst_cap_count["${fe_mcg_name}"] += 1))
		;;
	m)
		_mst_low_members["${fe_mcg_name}"]="${_mst_low_members[${fe_mcg_name}]:-}|${fe_key}"
		((_mst_low_count["${fe_mcg_name}"] += 1))
		;;
	e)
		_excl_low_members["${fe_mcg_name}"]="${_excl_low_members[${fe_mcg_name}]:-}|${fe_key}"
		((_excl_low_count["${fe_mcg_name}"] += 1))
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
		# more than one m-member defined for a master MCG
		local pros_tag[0]="${mcg_name}"
		pros_tag[1]="only one m-member permitted but got '${_mst_low_members[${mcg_name}]#\|}'"
		bp_exit_with_msg 39 pros_tag
	elif [[ ${_mst_low_count["${mcg_name}"]:-0} -eq 1 ]]; then
		# only one m-member defined
		if [[ ${_mst_cap_count["${mcg_name^}"]:-0} -eq 0 ]]; then
			# m-member defined but no M-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="m-member '${_mst_low_members["${mcg_name}"]#\|}' requires a M-member."
			bp_exit_with_msg 39 pros_tag
		else
			# multiple M-member defined, OK
			:
		fi
	fi

	if [[ ${_mst_cap_count[${mcg_name}]:-} -gt 0 ]]; then
		# M-member(s) defined
		if [[ ${_mst_low_count["${mcg_name,}"]:-} -eq 0 ]]; then
			# no m-member defined for a MCG
			local pros_tag[0]="${mcg_name}"
			pros_tag[1]="no m-member for M-member '${_mst_cap_members[${mcg_name}]#\|}'"
			bp_exit_with_msg 39 pros_tag
		else
			# m-member(s) defined, OK
			:
		fi
	fi
}

# validate all MCG cross-references within a PFILTER
# $1 - nameref to PFILTER associative array
# for each entry: extracts schema, classifies MCG members (d/D/e/m/M),
# validates entry type and default value
# then for each MCG: checks dependency (d→D), master (m↔M), exclusion (e≥2 members)
# exits with 33-39 on violations
bp_validate_pfilter_mcg_settings() {
	local -n _pfilter=$1

	bp_msg 3 "    Check MCG settings"
	declare -a mcg_name_entry=()
	declare -A mcg_names=()
	declare -A dep_cap_members=() dep_cap_count=()
	declare -A dep_low_members=() dep_low_count=()
	declare -A mst_cap_members=() mst_cap_count=()
	declare -A mst_low_members=() mst_low_count=()
	declare -A excl_low_members=() excl_low_count=()
	local mcg_name
	local fe_key fe_entry

	# for mcg_type in "${MCG_TYPES[@]}"; do
	# 	mcg_types+=("${mcg_type#*"${CONFIGS[fs]}"}")
	# done

	for fe_key in "${!_pfilter[@]}"; do
		local fe_type="" fe_data="" fe_mcg_name=""

		fe_entry="${_pfilter[${fe_key}]}"
		bp_extract_filter_entry "${CONFIGS[ulid]}" "${fe_entry}" fe_type fe_data fe_mcg_name
		bp_msg -3 "      - extract entry: " "${fe_type} | ${fe_data:--} | ${fe_mcg_name:--}"

		# validate mcg name/type; create group-member mappings
		if [[ -n ${fe_mcg_name} ]]; then
			bp_escape_symbol fe_mcg_name "${CONFIGS[es]}"
			readarray -d "${CONFIGS[es]}" -t mcg_name_entry <<<"${fe_mcg_name}"
			mcg_name_entry[-1]="${mcg_name_entry[-1]%$'\n'}"

			for mcg_name in "${mcg_name_entry[@]}"; do
				bp_escape_symbol mcg_name "${CONFIGS[es]}" "regress"
				mcg_names["${mcg_name}"]=true
				bp_process_pfilter_entry_mcg_name \
					"${fe_key}" mcg_name \
					dep_cap_members dep_cap_count dep_low_members dep_low_count \
					mst_cap_members mst_cap_count mst_low_members mst_low_count \
					excl_low_members excl_low_count
			done
		fi

		bp_validate_pfilter_entry_type "${fe_key}" "${fe_type}"
		bp_validate_pfilter_default "${fe_type}" "${fe_data}" "${fe_key}" "${fe_entry}"
	done

	# validate group member relationships
	for mcg_name in "${!mcg_names[@]}"; do
		bp_validate_mcg_dependency "${mcg_name}" dep_low_count dep_cap_count dep_low_members
		bp_validate_mcg_master "${mcg_name}" mst_low_count mst_cap_count mst_low_members mst_cap_members
		bp_validate_mcg_exclusion "${mcg_name}" excl_low_count excl_low_members
	done

	bp_msg 3 "      PFILTER MCG settings check PASSED"
	return 0
}

bp_validate_pfilter_json_string() {
	local -n json_stream=$1 _out_pfilter=$2

	if jq -e . <<<"${json_stream}" >/dev/null 2>&1; then
		# a valid json string
		if bp_deserialize_json_string_to_pfilter "${json_stream}" _out_pfilter; then
			bp_msg 3 "    JSON-STREAM found"
			return 0
		fi
	fi
	bp_msg 3 "    no valid JSON-STREAM found"
	return 1
}

# validate pfilter with format: "key1=value1" "key2=value2" ...
#   - ignore empty items
#   - empty values permitted
# any element missing OV-SEP will result validate fails
bp_validate_pfilter_element_stream() {
	local -n elm_stream=$1 _out_pfilter=$2

	local elements=() element value
	bp_escape_symbol elm_stream ' '
	mapfile -d ' ' -t elements <<<"${elm_stream}"
	elements[-1]="${elements[-1]%$'\n'}"

	for element in "${elements[@]}"; do
		if [[ ${element} == *"${CONFIGS[os]}"* ]]; then
			bp_escape_symbol element ' ' "regress"
			_out_pfilter["${element%%=*}"]="${element#*=}"
		else
			bp_msg 3 "    no valid ELM-STREAM found"
			return 1
		fi
	done

	bp_msg 3 "    ELM-STREAM found"
}

# validate PFILTER with format: "key1" "value1" "key2" "value2 ...
# the key-value pair must be:
#   - pairing, no single key or value
#   - in sequence
#   - empty value permitted, use "" as place holder
#   - no leading or trailing space(s)
bp_validate_pfilter_kv_sequence() {
	local -n kv_stream=$1 _out_pfilter=$2

	declare -a pf_arr=()
	# escape first in case escaped spaces "\\ " missing
	bp_escape_symbol kv_stream ' '
	readarray -d ' ' -t pf_arr <<<"${kv_stream}"
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
		bp_msg 3 "    no valid KV-STREAM found"
		return 1
	fi
	# populate associative array
	for ((i = 0; i < n; i += 2)); do
		_out_pfilter["${pf_arr[i]}"]="${pf_arr[i + 1]}"
	done

	bp_msg 3 "    KV-STREAM found"
}

# all input formats must contain a PFILTER_ID key ("PARAM_FILTER" )
# which is removed after validation
# validates each key name: exception substitution, shell variable name check,
# duplicate-after-substitution detection (exit 58)
# then runs full MCG integrity check
# handle assoc array branch of bp_validate_pfilter
# copies entries from source to target, or verifies id-key if same array
# $1 - target variable name (string, e.g. "PFILTER")
# $2 - source variable name (string, user's PFILTER name from CONFIGS[pf])
# $3 - PFILTER_ID key to verify
bp_validate_pfilter_assoc_array() {
	local _pf_trg_name=$1
	local _pf_src_name=$2

	# 
	# echo2 "$_pf_trg_name | $_pf_src_name"
	# declare -n _pf_src="${_pf_src_name}"
	# bp_show_array ${_pf_src_name}
	# echo2 "_pf_src_name: ${_pf_trg_name}"
	# echo2 "_pf_src_name: ${_pf_trg_name[*]}"

	local _pf_id="${CONSTS["PFILTER_ID"]//-/_}"

	if [[ "${_pf_src_name}" != "${_pf_trg_name}" ]]; then
		local -n _pf_trg="${_pf_trg_name}"
		declare -n _pf_src="${_pf_src_name}"
		if [[ -v _pf_src[${_pf_id}] ]]; then
			bp_msg 3 "    PFILTER-ID found"
			# pollution PFILTER
			local _k
			for _k in "${!_pf_src[@]}"; do
				_pf_trg["${_k}"]="${_pf_src[${_k}]}"
			done
		else
			local pros_tag[0]="an identifier key '${_pf_id}' required"
			bp_exit_with_msg 31 pros_tag
		fi
	else
		local -n _pf_trg="${_pf_trg_name}"
		if [[ ! -v _pf_trg[${_pf_id}] ]]; then
			local pros_tag[0]="an identifier key '${_pf_id}' required"
			bp_exit_with_msg 31 pros_tag
		fi
	fi
	bp_msg 3 "    PFILTER nameref '${_pf_src_name}' supplied"
}

# load and validate a PFILTER from CONFIGS["pf"] into an associative array
# $1 - nameref: receives the validated PFILTER entries
#
# three input formats accepted:
#   1. name-ref          - a declared associative array name in the caller's scope(source mode only)
#   2. JSON string       - serialized associative array via jq
#   3. elemenet stream   - assignment stream: key1-value1 key2=value2 ...
#   3. "key-value" pairs - space-separated string: key1 val1 key2 val2 ...
bp_validate_pfilter() {
	local _pf_target=$1 # receive name instead of nameref to avoid name conflict

	local up_filter="${CONFIGS[pf]}"
	local pfilter_id="${CONSTS["PFILTER_ID"]//-/_}"

	local pk new_pk parser
	local -a parser_order=(
		bp_validate_pfilter_json_string
		bp_validate_pfilter_element_stream
		bp_validate_pfilter_kv_sequence
	)
	local parsed=false

	bp_msg -3 "    " "filter: ${up_filter}"

	[[ -n ${up_filter} ]] || {
		local pros_tag[0]="it's an 'empty' variable."
		bp_exit_with_msg 31 pros_tag
	}

	# check type BEFORE declaring the nameref — no shadow possible
	local _is_assoc=false
	if bp_validate_variable_name "PFILTER name" up_filter true; then
		bp_msg 3 "    PFILTER name: ${up_filter}"
		[[ "$(declare -p "${up_filter}" 2>/dev/null)" == "declare -A "* ]] && _is_assoc=true
	fi

	# now declare the nameref (type check already done)

	if [[ ${_is_assoc} == true ]]; then
		bp_msg 3 "    An associative array found"
		bp_validate_pfilter_assoc_array "${_pf_target}" "${up_filter}"
		local -n pfilter="${_pf_target}"
	else
		local -n pfilter="${_pf_target}"
		# not a associative array, try serialized stream
		for parser in "${parser_order[@]}"; do
			if "${parser}" up_filter pfilter; then
				parsed=true
				break
			fi
		done

		# when all parse failed, no valid PFILTER
		if [[ ${parsed} != true ]]; then
			local pros_tag[0]="it should be a json string, an element stream, or a key-value sequence"
			bp_exit_with_msg 31 pros_tag
		fi

		if [[ -v pfilter["${pfilter_id}"] ]]; then
			bp_msg 3 "    PFILTER-ID found"
			bp_msg 3 "    Serialized PFILTER supplied"
		else
			local pros_tag[0]="no identifier key '${pfilter_id}'"
			bp_exit_with_msg 31 pros_tag
		fi
	fi

	unset "pfilter[${pfilter_id}]"

	# populate PFILTER and normalize key names
	for pk in "${!pfilter[@]}"; do
		new_pk="${pk}"
		bp_substitute_variable_name_exceptions new_pk
		if ! bp_validate_variable_name "PFILTER key" new_pk true; then
			local pros_tag[0]="$(printf '%q' "${pk}")"
			bp_exit_with_msg 32 pros_tag
		fi

		if [[ ${pk} != "${new_pk}" ]]; then
			if [[ -v pfilter["${new_pk}"] ]]; then
				# name conflict, like both 'dry-run' and 'dry_run' exist as keys
				local pros_tag[0]="${new_pk}"
				pros_tag[1]="${pk}"
				bp_exit_with_msg 58 pros_tag
			fi
			# update PFILTER
			pfilter["${new_pk}"]="${pfilter[${pk}]}"
			unset "pfilter[${pk}]"
		fi
	done

	bp_validate_pfilter_mcg_settings pfilter
	bp_msg 3 "    PFILTER validated"
}
