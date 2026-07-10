# shellcheck shell=bash
# shellcheck disable=SC2154
# Module 03-helpers: Helper functions for parsing workflow
#
# CONFIGS operations:
#   bp_set_configs()     - set single CONFIGS entry if imm/vn-excl/value check passed
#   bp_update_configs()  - merge parsed options into CONFIGS
#   bp_update_verbose()  - manage output verbosity levels (0-4)
#
# RESYMS relevants:
#   bp_is_in_resyms()    - check if a string consists entirely of reserved symbols
#   bp_substitute_variable_name_exceptions() - replace hyphens with underscores in variable names
#
# Schema pattern operations:
#   bp_extract_filter_entry()     - split "type:data:mcg" entry into components
#   bp_extract_enum_value_list()  - split enum values from |-delimited string
#
# Filter caching:
#   bp_read_filter_entry_cache()  - read extracted entry data from cache; return 1 if not hit
#   bp_write_filter_entry_cache() - write extracted entry data to cache
#
# Derive data from HARNESSES:
#   bp_derive_harness_entry_fields()     - extract specific fields from a HARNESSES entry
#   bp_derive_harness_entries_by_field() - find all HARNESSES keys matching a field+value
#   bp_derive_context_group()            - extract one cluster's members from HARNESSES+CONFIGS
# --------------------------------------------------------------------------------

# set a CONFIGS key to a value after validation
# $1 - config key (must exist in HARNESSES)
# $2 - value to set
# validates:
#   - key exists in HARNESSES (else exit 4)
#   - key is not in IMMUTABLES (else exit 27)
#   - value does not contain chars listed in PAS_EXCLUSIONS for this key (else exit 27)
# side effects: when ulid changes, llid is doubled; when slid changes, plid is doubled
bp_set_configs() {
	local key=$1 value=$2

	if [[ ! -v HARNESSES["${key}"] ]]; then
		local pros_tag[0]="Invalid CONFIGS setting, wrong config name: '${key}'"
		bp_exit_with_msg 4 pros_tag
	fi

	# validate setting
	# check IMMUTABLES: set not allowed if the key in IMMUTABLES
	if bp_is_array_member "${key}" IMMUTABLES; then
		local pros_tag[0]="harness setting"
		pros_tag[1]="'${key}' is immutable"
		pros_tag[2]="and cannot be changed."
		bp_exit_with_msg 27 pros_tag
	fi
	# check PAS_EXCLUSIONS: exclusion resym not allowed in value
	# for resyms type:
	#   - should match length (done in bp_validate_option_values())
	#   - consist of resyms  (done in bp_validate_option_values())
	#   - not contains resyms in PAS_EXCLUSIONS
	if [[ -v PAS_EXCLUSIONS["${key}"] ]] && [[ -n "${PAS_EXCLUSIONS[${key}]}" ]]; then
		local stripped_value="${value//[${PAS_EXCLUSIONS[${key}]}]/}"
		if ((${#stripped_value} != "${#value}")); then
			local pros_tag[0]="Prior setting:"
			pros_tag[1]="'${CONFIGS[plid]}${key}=${value}'"
			pros_tag[2]="contains resyms not allowed: '${PAS_EXCLUSIONS[${key}]}'"
			bp_exit_with_msg 27 pros_tag
		fi
	fi

	# check BASH_VARS: value must be valid shell variable
	if bp_is_array_member "${key}" "${BASH_VARS}"; then
		# key in blacklist, validate value
		if ! bp_validate_variable_name "harness" value true; then
			local pros_tag[0]="Harness"
			pros_tag[1]="${key}='${value}'"
			pros_tag[2]="the value should be a valid BASH variable name."
			bp_exit_with_msg 27 pros_tag
		fi
	fi
	# update CONFIGS
	CONFIGS["${key}"]="${value}"
	# sync llid when ulid changed; sync plid when slid changed
	[[ ${key} != "ulid" ]] || CONFIGS["llid"]="${value}${value}"
	[[ ${key} != "slid" ]] || CONFIGS["plid"]="${value}${value}"
}

# apply parsed Harness options (Globals/Priors/Specs) to CONFIGS
# $1 - nameref to associative array of {key: value} pairs from the tier
# calls bp_set_configs for each entry, then refreshes LIDS/TAGS via bosparse_update_mutables
bp_update_configs() {
	local -n options_ref=$1

	local ps field_len

	bp_msg 3 "  Apply settings"
	if [[ ${#options_ref[@]} -eq 0 ]]; then
		bp_msg -3 "    " "no new setup"
		return 0
	fi
	# apply settings to CONFIGS
	field_len=$(bp_max_array_member_length "${!options_ref[@]}")
	for ps in "${!options_ref[@]}"; do
		bp_set_configs "${ps}" "${options_ref[${ps}]}"
		bp_msg 3 "      $(printf "\e[0;2m%${field_len}s - '%s'\n" "${ps}" "${options_ref[${ps}]}")" >&2
	done
	bosparse_update_mutables
}

# set the global $verbose level from CONFIGS or DEBUG_MAPS
# priority: DEBUG_MAPS (from __debug/__trace flags) > CONFIGS (trace/debug/extra/standard/quiet)
# verbose levels: 4=trace, 3=debug, 2=extra, 1=standard, 0=quiet
# globals: reads CONFIGS (trace/debug/extra/standard) and DEBUG_MAPS; writes $verbose
bp_update_verbose() {

	if [[ ${#DEBUG_MAPS[@]} -gt 0 ]]; then
		if [[ ${DEBUG_MAPS[TRACE]:-false} == true ]]; then
			verbose=4
		elif [[ ${DEBUG_MAPS[DEBUG]:-false} == true ]]; then
			verbose=3
		elif [[ ${DEBUG_MAPS[EXTRA]:-false} == true ]]; then
			verbose=2
		elif [[ ${DEBUG_MAPS[STANDARD]:-false} == true ]]; then
			verbose=1
		elif [[ ${DEBUG_MAPS[QUIET]:-false} == true ]]; then
			verbose=0
		fi
	else
		if [[ ${CONFIGS["trace"]} == true ]]; then
			verbose=4
		elif [[ ${CONFIGS["debug"]} == true ]]; then
			verbose=3
		elif [[ ${CONFIGS["extra"]} == true ]]; then
			verbose=2
		elif [[ ${CONFIGS["standard"]} == true ]]; then
			verbose=1
		else
			verbose=0
		fi
	fi
	return 0
}

# check if a string consists entirely of ONE repeated reserved symbol
# e.g. "~~~" (all ~) returns 0; "~-" (mixed) returns 1
# $1 - string to check
# globals: reads RESYMS array
# returns: 0 if param is all-one-resym, 1 otherwise
bp_is_in_resyms() {
	local param=$1
	local resym
	for resym in "${RESYMS[@]}"; do
		[[ ${param} == ${resym}* && ${param//${resym}/} == "" ]] && return 0
	done
	return 1
}

# replace exception characters in a variable name per VN_EXCEPTIONS map
# $1 - nameref: variable name to modify (modified in-place)
# currently replaces hyphens with underscores, e.g. "my-param" → "my_param"
# first and last characters are never substituted (exceptions at both ends disallowed)
# no-op when string length <= 2
bp_substitute_variable_name_exceptions() {
	local -n var_name=${1:-}

	((${#var_name} > 2)) || {
		bp_msg -3 "      " "- substitution: ${var_name} -> ${var_name}"
		return 0
	}
	local first="" last="" test_name orig="${var_name}"
	first="${var_name:0:1}"
	last="${var_name: -1}"
	test_name="${var_name:1:-1}"

	local except_char
	for except_char in "${!VN_EXCEPTIONS[@]}"; do
		test_name=${test_name//"${except_char}"/"${VN_EXCEPTIONS[${except_char}]}"}
	done
	var_name="${first}${test_name}${last}"
	bp_msg -3 "      " "- substitution: ${orig} -> ${var_name}"
}

# split a PFILTER entry "type:data:mcg" into its three component fields
# $1 - lid context (determines whether to regress symbols after split)
# $2 - entry string (e.g. "bool:true:eg_t")
# $3 - nameref: receives the type field
# $4 - nameref: receives the data field
# $5 - nameref: receives the mcg field
# backslashes and field separators within data are escaped before IFS split,
# then regressed for ulid entries; other lid levels skip regression
bp_extract_filter_entry() {
	local lid=$1 entry=$2
	local -n _type=$3 _data=$4 _mcg_name=$5

	local FLD_SEP="${CONFIGS[fs]}"

	local cache_key="${lid}${FLD_SEP}${entry}"

	# try cache
	bp_read_filter_entry_cache "${cache_key}" _type _data _mcg_name && return 0

	# escape backslashes before FLD-SEPs, to prevent `\\:` being misinterpreted as `\:`
	bp_escape_symbol entry "\\"
	bp_escape_symbol entry "${FLD_SEP}"

	local OLD_IFS=${IFS}
	local IFS="${FLD_SEP}"
	read -r _type _data _mcg_name <<<"${entry}"
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
	bp_write_filter_entry_cache "${cache_key}" "${_type}" "${_data}" "${_mcg_name}"
	return 0
}

# split an ELM_SEP-separated enum list string into an indexed array
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

# use the cached data if hitted
# return code:
#   - 0: hitted, cached data passed back
#   - 1: not hitted, nothing changed
# filter format:
#   - ${key}
#   - ${key}_type
#   - ${key}_data
#   - ${key}_mcg
bp_read_filter_entry_cache() {
	local key=$1
	if [[ -v FILTER_ENTRY_CACHE[${key}] ]]; then
		local -n fe_type=$2 fe_data=$3 fe_mcg=$4
		fe_type="${FILTER_ENTRY_CACHE[${key}_type]}"
		fe_data="${FILTER_ENTRY_CACHE[${key}_data]}"
		fe_mcg="${FILTER_ENTRY_CACHE[${key}_mcg]}"
		return 0
	else
		return 1
	fi
}

# populate FILTER_ENTRY_CACHE with data passed in
bp_write_filter_entry_cache() {
	local key=$1
	shift

	local entry_fields=("$@")
	FILTER_ENTRY_CACHE["${key}"]=true                      # use to check
	FILTER_ENTRY_CACHE["${key}_type"]="${entry_fields[0]}" # type field
	FILTER_ENTRY_CACHE["${key}_data"]="${entry_fields[1]}" # data fields
	FILTER_ENTRY_CACHE["${key}_mcg"]="${entry_fields[2]}"  # mcg field
}

# extract specific fields from a HARNESSES entry into an indexed array
# usage:
#   bp_derive_harness_entry_fields KEY OUT_ARRAY FIELD [FIELD...]
#   - KEY       - short config name (e.g. run, glid, fs)
#   - OUT_ARRAY - nameref target receiving field values in order
#   - FIELD     - name(s) of field(s) to extract: type, type-arg, mcg,
#               levels, immutable, default, cluster
#               derive all fields if only 'all' provided
# example:
#   bp_derive_harness_entry_fields fs type immutable RESULT    # RESULT=(string imm)
# globals relied:
#   - HRNS_FLDS - fields pattern of HARNESSES
#   - HARNESSES - all-in-one configuration
# return codes:
#   0 - success
#   1 - failure, field(s) not match HRNS_FLDS
bp_derive_harness_entry_fields() {
	local key=$1
	local -n _out_arr=$2
	shift 2

	# 'all' fields test
	local flds_required_arr=("$@")
	((${#flds_required_arr[@]} == 1)) &&
		[[ ${flds_required_arr[0]} == 'all' ]] &&
		flds_required_arr=("${HRNS_FLDS[@]}")

	local i entry_flds=()

	(("${#flds_required_arr[@]}" != 0)) || return 1

	declare -A index_map=()
	for i in "${!HRNS_FLDS[@]}"; do
		index_map[${HRNS_FLDS[i]}]="${i}"
	done

	readarray -d: -t entry_flds <<<"${HARNESSES[${key}]}"
	entry_flds[-1]="${entry_flds[-1]%$'\n'}"

	for ((i = 0; i < ${#flds_required_arr[@]}; i++)); do
		local field=${flds_required_arr[i]}
		if [[ -v index_map["${field}"] ]]; then
			_out_arr[i]="${entry_flds[index_map[${field}]]}"
			continue
		fi
		# no matched field
		_out_arr=("${field}")
		return 1
	done
	return 0
}

# find all HARNESSES keys where a field contains a substring
# usage: bp_derive_harness_entries_by_field FIELD SUBSTRING OUT_ARRAY
#   FIELD     - field name defined in HRNS_FLDS
#   NEEDLE    - value to search for (substring match)
#   OUT_ARRAY - nameref receiving matching keys
# examples:
#   bp_derive_harness_entries_by_field levels global  GLOBAL_CFGS # keys usable at global level
#   bp_derive_harness_entries_by_field cluster lid    LID_KEYS    # keys in the lid cluster
#   bp_derive_harness_entries_by_field immutable imm  IMM_KEYS    # immutable keys
bp_derive_harness_entries_by_field() {
	local field=$1 needle=$2
	local -n _out_array=$3

	local i fld_no fields_derived=() key fields_arr=()

	for i in "${!HRNS_FLDS[@]}"; do
		[[ ${HRNS_FLDS[i]} == "${field}" ]] || continue
		fld_no="${i}"
		break
	done

	for key in "${!HARNESSES[@]}"; do
		readarray -d: -t fields_arr <<<"${HARNESSES[${key}]}"
		fields_arr[-1]="${fields_arr[-1]%$'\n'}"
		[[ ${fields_arr[${fld_no}]:-} =~ ${needle} ]] || continue
		_out_array+=("${key}")
	done
}

# extract members of a HARNESSES field group and their CONFIGS values
# $1 - target field name in HRNS_FLDS (e.g. "cluster")
# $2 - value to match in the target field (e.g. "lid", "sep", "tag", "arr")
# $3 - optional nameref: receives {key: CONFIGS_value} pairs; omit for stdout
# usage: bp_derive_context_group "cluster" lid" "ctx""  # cluster=lid, output to ctx
#        bp_derive_context_group "immutable" "imm"      # field=immutable, print to stdout
bp_derive_context_group() {
	local field=$1
	local match=$2

	local i fld_no=-1
	for i in "${!HRNS_FLDS[@]}"; do
		[[ ${HRNS_FLDS[i]} == "${field}" ]] || continue
		fld_no="${i}"
		break
	done
	[[ ${fld_no} -ge 0 ]] || return 0

	local key fields=() field_arr=()

	if (($# >= 3)); then
		local -n __out=$3
		__out=()
	fi

	for key in "${!HARNESSES[@]}"; do
		readarray -d: -t fields <<<"${HARNESSES[${key}]}"
		fields[-1]=${fields[-1]%$'\n'} # '<<<' introduced a trailing newline
		readarray -d "${CONFIGS[es]}" -t field_arr <<<"${fields[fld_no]}"
		field_arr[-1]="${field_arr[-1]%$'\n'}" # remove trailing newline
		for i in "${!field_arr[@]}"; do
			[[ ${field_arr[i]} == "${match}" ]] || continue
			if (($# >= 3)); then
				__out["${key}"]="${CONFIGS[${key}]}"
			else
				printf '%s=%s\n' "${key}" "${CONFIGS[${key}]}"
			fi
			break
		done
	done
	# for key in "${!HARNESSES[@]}"; do
	# 	readarray -d: -t fields <<<"${HARNESSES[${key}]}"
	# 	fields[-1]=${fields[-1]%$'\n'} # '<<<' introduced a trailing newline
	# 	[[ ${fields[fld_no]:-} != "${match}" ]] || printf '%s=%s\n' "${key}" "${CONFIGS[$key]}"
	# done
}
