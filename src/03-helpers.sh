# shellcheck shell=bash
# shellcheck disable=SC2154
# Module 03-helpers: Helper functions for parsing workflow
#   bp_update_verbose()           - manage output verbosity levels (0-4)
#   bp_is_in_resyms()             - check if a string consists entirely of reserved symbols
#   bp_set_configs()              - set single CONFIGS entry if imm/vn-excl/value check passed
#   bp_update_configs()           - merge parsed options into CONFIGS
#   bp_apply_filter_default()     - assign PFILTER defaults to un-supplied parameters
#   bp_extract_filter_entry()     - split "type:data:mcg" entry into components
#   bp_show_configs()             - display current CONFIGS
#   bp_read_filter_entry_cache()  - read extracted entry data from cache; return 1 if not hit
#   bp_write_filter_entry_cache() - write extracted entry data to cache
#   bp_substitute_variable_name_exceptions() - replace hyphens with underscores in variable names
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

# assign PFILTER default values to parameters not supplied by the user
# $1 - nameref to user-supplied options (modified in-place for missing params)
# $2 - nameref to PFILTER entries {key: "type:data:mcg"}
# skips MCG members; fails with exit 55 if a non-MCG param has no default when ~afd(default setting)
# enum defaults use the first element of the enum list
# ensure '~afd' before calling(no '~afd' check inside function)
bp_apply_filter_default() {
	local -n _options=$1 _pfilter=$2

	local fe_type fe_data fe_mcg

	bp_msg 3 "  Assign PFILTER default values if not supplied"
	local prn_pattern='%15s - %12s | %8s | %14s | %-10s'
	[[ ${verbose} -ge 3 ]] && printf "    \e[4;33m${prn_pattern}\e[0m\n" \
		"param" "status" "type" "data" "mcg-name" >&2
	for param in "${!_pfilter[@]}"; do
		bp_extract_filter_entry "${CONFIGS[ulid]}" "${_pfilter[${param}]}" fe_type fe_data fe_mcg
		# skip mcg members
		[[ -z ${fe_mcg} ]] || {
			[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
				"${param}" "MCG member" "${fe_type}" "${fe_data:--}" "${fe_mcg:--}" >&2
			continue
		}
		# skip supplied ones
		[[ -v _options["${param}"] ]] && {
			[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
				"${param}" "supplied" "${fe_type}" "${fe_data:--}" "${fe_mcg:--}" >&2
			continue
		}
		# no default value, failed
		if [[ -z "${fe_data}" ]]; then
			local pros_tag[0]="${param}"
			bp_exit_with_msg 55 pros_tag
		fi

		# assigning defaults
		[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
			"${param}" "default" "${fe_type}" "${fe_data:--}" "${fe_mcg:--}" >&2
		case "${fe_type}" in
		bool | string)
			_options["${param}"]="${fe_data}"
			;;
		enum)
			# set with first enum as default value
			_options["${param}"]="${fe_data%%"${CONFIGS[es]}"*}"
			;;
		*) # this will not happen since integrity checking already done in bp_validate_pfilter
			;;
		esac
		[[ ${verbose} -ge 3 ]] && printf "    \e[2m${prn_pattern}\e[0;2m%s\e[0m\n" \
			"${param}" "assigned" "${fe_type}" "${_options[${param}]:--}" "${fe_mcg}" >&2
	done
	return 0
}

# display current CONFIGS settings, for debugging & directives
bp_show_configs() {
	local output_as_json key param len_key

	[[ ${CONFIGS["json"]} == true ]] && output_as_json=true || output_as_json=false
	[[ ${CONFIGS["run"]} == "capture" ]] && output_as_json=true

	if [[ ${CONFIGS["Defaults"]} == true ]]; then
		# respond to directive calling
		if [[ ${output_as_json} == true ]]; then
			bp_validate_jq
			bp_serialize_pfilter_to_json_string CONFIGS | jq
		else
			bp_show_array CONFIGS 2>&1 | sort -n
		fi
	else
		# for debugging
		local key
		for key in "${!CONFIGS[@]}"; do
			printf '%s=%q\n' "${key}" "${CONFIGS[${key}]}"
		done | sort -n
	fi
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
