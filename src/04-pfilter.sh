# shellcheck shell=bash
# shellcheck disable=SC2153,SC2206
# Module 04-pfilter: PFILTER validation and serialization
#
# General used functions for PFILTER manipulations:
#   bp_serialize_pfilter_to_json_string()    - assoc array to JSON string (via jq)
#   bp_serialize_pfilter_to_element_stream() - assoc array to element stream
#   bp_serialize_pfilter_to_kv_sequence()    - assoc array to key-value sequence
#   bp_deserialize_json_string_to_pfilter()  - JSON string to assoc array (via jq)
#
# Desrialize function used by 'bp_validate_pfilter()':
#   bp_deserialize_json_string()     - JSON-STING  -> PFILTER
#   bp_deserialize_element_stream()  - ELM-STREAM  -> PFILTER
#   bp_deserialize_kv_sequence()     - KV_SEQUENCE -> PFILTER
#
# PFILTER field validations:
#   bp_validate_pfilter_entry_type()      - check type is one of bool/string/enum
#   bp_validate_pfilter_default()         - ensure default value matches declared type
#   bp_process_pfilter_entry_mcg_name()   - classify MCG member (d/D/e/m/M) and record
#
# MCG setting validations:
#   bp_validate_mcg_exclusion()           - check exclusion group has >=2 members
#   bp_validate_mcg_dependency()          - check d-member has a D-member
#   bp_validate_mcg_master()              - check M/m master group relationship
#   bp_validate_pfilter_mcg_settings()    - full cross-member MCG validation
#
# PFILTER validation:
#   bp_validate_pfilter()                 - entry point: accept name-ref / JSON / keys-values
#
# PFILTER fields(separated by colon ':'):
#   field1: type 
#   field2: data
#     - default value for bool/string type
#     - enum value list for enum type 
#   field3: mcg name(s)
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

# serialize a PFILTER to ELM-STREAM
# $1: nameref of a PFILTER
# $2: nameref of the created ELM-STREAM
# ELM-STREAM format: key1=value1 key2=value2 ...
# caution:
#   spaces at beginning and end should be trimed before return
#   spaces in values should be escaped
bp_serialize_pfilter_to_element_stream() {
	local -n _filter_map=$1 _element_stream=$2

	local key
	for key in "${!_filter_map[@]}"; do
		_element_stream+="${key}=${_filter_map[${key}]} "
	done
	# IMPORTANT: remove last space
	_element_stream="${_element_stream% }"
}

# serialize a PFILTER to KV_SEQUENCE
# $1: nameref of a PFILTER
# $2: nameref of the created KV_SEQUENCE
# ELM-STREAM format: key1 value1 key2 value2 ...
# caution:
#   spaces at beginning and end should be trimed before return
#   spaces in values should be escaped
#   order matters, no solitary key or value allowed
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

# populate FPILTER with validated input filter, and:
#   - substitute exceptions in key-nmae
#   - validate key name against shell variable name
#   - check key name collision(dry_run vs dry-run)
bp_populate_pfilter() {
	local -n _pfilter_vld=$1 _pfilter_trg=$2

	local key key_sub
	for key in "${!_pfilter_vld[@]}"; do
		key_sub="${key}"
		# key validation and normallization
		bp_substitute_variable_name_exceptions key_sub
		if ! bp_validate_variable_name "PFILTER key" key_sub true; then
			local pros_tag[0]="$(printf '%q' "${key}")"
			bp_exit_with_msg 32 pros_tag
		fi

		# test key name confict
		if [[ ${key} == "${key_sub}" ]]; then
			_pfilter_trg["${key_sub}"]="${_pfilter_vld[${key}]}"
		else
			# name changed after exception substitution
			if [[ -v _pfilter_vld["${key_sub}"] ]]; then
				# name conflict, like both 'dry-run' and 'dry_run' exist as keys
				local pros_tag[0]="${key_sub}"
				pros_tag[1]="${key}"
				bp_exit_with_msg 58 pros_tag
			fi
			_pfilter_trg["${key_sub}"]="${_pfilter_vld[${key}]}"
		fi
	done
}

# one of deserializers of function 'bp_validate_pfilter()'
# deserialize json string to associative array
# $1: nameref of json string
# $2: nameref of PFILTER array to populate
bp_deserialize_json_string() {
	local -n json_stream=$1 _out_pfilter=$2

	if jq -e . <<<"${json_stream}" >/dev/null 2>&1; then
		# a valid json string
		if bp_deserialize_json_string_to_pfilter "${json_stream}" _out_pfilter; then
			bp_msg 3 "    JSON-string found"
			return 0
		fi
	fi
	bp_msg 3 "    no valid JSON-string found"
	return 1
}

# deseialize element stream with format: key1=value1 key2=value2 ...
# the element stream must be:
#   - no leading ro trailing spaces
#   - empty values permitted, use "" as place holder
#   - empty element permitted but will be removed
# feature:
#   - ignore empty elements
#   - any element missing '=' will result in deserializing failure
# $1: element stream(a string nameref)
# $2: nameref of PFILTER array to populate
bp_deserialize_element_stream() {
	local -n _element_str=$1 _out_pfilter=$2

	local elements=() element value
	# may contains escaped spaces
	bp_escape_symbol _element_str ' '
	mapfile -d ' ' -t elements <<<"${_element_str}"
	elements[-1]="${elements[-1]%$'\n'}"
	[[ -n "${elements[-1]}" ]] || unset "elements[-1]"

	for element in "${elements[@]}"; do
		# drop empty element
		[[ -n "${element}" ]] || continue
		if [[ ${element} == *=* ]]; then
			bp_escape_symbol element ' ' "regress"
			_out_pfilter["${element%%=*}"]="${element#*=}"
		else
			bp_msg 3 "    no valid ELM-STREAM found"
			return 1
		fi
	done

	bp_msg 3 "    ELM-stream found"
}

# deserialize kv-sequence with format: key1 value1 key2 value2 ...
# the key-value sequence must be:
#   - space separated
#   - pairing, no solitary keys or values
#   - keep k-v-k-v order
# feature:
#   - empty value permitted, use "" as place holder
#   - no leading or trailing space(s)
# $1: key-value sequence(a string nameref)
# $2: nameref of PFILTER array to populate
bp_deserialize_kv_sequence() {
	local -n kv_seq=$1 _out_pfilter=$2

	declare -a pf_arr=()
	# escape first in case escaped spaces "\\ " contained
	bp_escape_symbol kv_seq ' '
	readarray -d ' ' -t pf_arr <<<"${kv_seq}"
	# remove trailing newline '<<<' added as '-t' only remove DELM ' '
	pf_arr[-1]="${pf_arr[-1]%$'\n'}"

	# escape regress
	local i
	for i in "${!pf_arr[@]}"; do
		bp_escape_symbol pf_arr[i] ' ' "regress"
	done
	# if element count is even number
	local n=${#pf_arr[@]}
	if ((n % 2)); then
		bp_msg 3 "    no valid KV-sequence found"
		return 1
	fi
	# populate associative array
	for ((i = 0; i < n; i += 2)); do
		_out_pfilter["${pf_arr[i]}"]="${pf_arr[i + 1]}"
	done

	bp_msg 3 "    KV-sequence found"
}

# load and validate a PFILTER from CONFIGS["pf"] into an associative array
# $1 - nameref: receives the validated PFILTER entries
# four input formats accepted:
#   1. name-ref           - a declared associative array name in the caller's scope(source mode only)
#   2. JSON string        - serialized associative array via jq
#   3. elemenet stream    - space-separated stream: key1-value1 key2=value2 ...
#   4. key-value sequence - space-separated sequence key1 val1 key2 val2 ...
bp_validate_pfilter() {

	local pfilter_spl="${CONFIGS[pf]}"
	local pfilter_id="${CONSTS[PFILTER_ID]}"

	# deserialize functions
	local deserializers=(
		bp_deserialize_json_string
		bp_deserialize_element_stream
		bp_deserialize_kv_sequence
	)

	# check supplid pf(CONFIGS[pf])
	local filter_valid=false
	if [[ "$(declare -p "${pfilter_spl}" 2>/dev/null)" == "declare -A "* ]]; then
		# associative array nameref supplied
		[[ ${pfilter_spl} == "pfilter" ]] || declare -n pfilter="${pfilter_spl}"
		bp_msg 3 "    An associative array found"
		filter_valid="true"
	else
		bp_msg 3 "    No associative array found"
		# try json/elements/kvs
		declare -A "pfilter=()"
		local func
		for func in "${deserializers[@]}"; do
			if "${func}" pfilter_spl pfilter; then
				filter_valid="true"
				break
			fi
		done
	fi

	# check filter-id
	if [[ ${filter_valid} == true ]]; then
		# check pfilter id
		if [[ -v pfilter["${pfilter_id}"] ]]; then
			bp_msg 3 "    PFILTER-ID found"
			bp_msg 3 "    Serialized PFILTER supplied"
			unset "pfilter[${pfilter_id}]"
		else
			local pros_tag[0]="no identifier key '${pfilter_id}'"
			bp_exit_with_msg 31 pros_tag
		fi
	else
		local pros_tag[0]="it should be a json string, an element sequence or a key-value stream"
		bp_exit_with_msg 31 pros_tag
	fi

	local -n pfilter_trg=$1
	bp_populate_pfilter pfilter pfilter_trg

	bp_validate_pfilter_mcg_settings pfilter_trg
	bp_msg 3 "    PFILTER validated"
}
