# shellcheck shell=bash
# shellcheck disable=SC2154
# Module 03-helpers: Helper functions for parsing workflow
#   bp_update_verbose()        — manage output verbosity levels (0-4)
#   bp_is_in_resyms()          — check if a string consists entirely of reserved symbols
#   bp_check_param_type()      — classify a CML token (bool/string/liga/arg) by context
#   bp_apply_setup()           — merge parsed options into CONFIGS
#   bp_apply_filter_default()  — assign PFILTER defaults to un-supplied parameters
#   bp_show_configs()          — display current CONFIGS
#   bp_substitute_exceptions() — replace hyphens with underscores in variable names
# --------------------------------------------------------------------------------

# set a CONFIGS key to a value after validation
# $1 — config key (must exist in HARNESSES)
# $2 — value to set
# validates:
#   - key exists in HARNESSES (else exit 3)
#   - key is not in IMMUTABLES (else exit 27)
#   - value does not contain chars listed in PAS_EXCLUSION for this key (else exit 27)
# side effects: when ulid changes, llid is doubled; when slid changes, plid is doubled
bp_set_configs() {
	local key=$1 value=$2

	if [[ ! -v HARNESSES["${key}"] ]]; then
		local pros_tag[0]="Invalid CONFIGS setting, wrong config name: '${key}'"
		bp_exit_with_msg 4 pros_tag
	fi

	# validate settings
	# check IMMUTABLES
	if bp_is_array_member "${key}" IMMUTABLES; then
		local pros_tag[0]="harness setting"
		pros_tag[1]="'${key}' is immutable"
		pros_tag[2]="and cannot be changed."
		bp_exit_with_msg 27 pros_tag
	fi
	# check PAS_EXCLUSION
	if [[ -v PAS_EXCLUSION["${key}"] ]]; then
		if [[ ${value} =~ [${PAS_EXCLUSION[${key}]}] ]]; then
			local pros_tag[0]="Prior setting:"
			pros_tag[1]="'${CONFIGS[plid]}${key}=${value}'"
			pros_tag[2]="${PAS_EXCLUSION[${key}]}"
			bp_exit_with_msg 27 pros_tag
		fi
	fi

	# check BASH_VARS
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
	# sync llid when ulid changes; sync plid when slid changes
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
# $1 — string to check
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

# classify a CML token by its LID prefix, OA_SEP presence, and next token
# $1 — current LID to match against
# $2 — current token
# $3 — next token (may be empty)
# $4 — nameref: receives the extracted/modified parameter name
# return codes:
#   0: arg (no lid match, caller must handle)
#   1: liga (uliga: lid+lid prefix, e.g. --flag)
#   2: bool (lid prefix, no arg consumed; includes OA_SEP=true/false)
#   3: bool (lid prefix, consumes next token as true/false)
#   4: string (OA_SEP present, arg is non-boolean)
#   5: string (lid prefix, consumes next token as value)
#   6: alter-lid match, no consume
#   7: alter-lid match, consume next token
bp_check_param_type() {
	local lid=$1 current=$2 next=$3
	local -n param_ref=$4

	local param_name arg

	local oa_sep="${CONFIGS[os]}"
	local tag_true=${CONFIGS[tt]}
	local tag_false=${CONFIGS[tf]}

	bp_msg -4 "    param: " "$*"

	param_ref="${current}"

	if bp_with_lid "${current}" "${lid}${lid}"; then
		# '--current' like, uliga
		return 1
	elif bp_with_lid "${current}" "${lid}"; then
		# '-current ' like, with lid
		if [[ "${current}" == ${lid}*${oa_sep}* ]]; then
			# '-current=arg' like, depends on arg
			param_name=${current#"${lid}"}         # remove lid in case 'lid==OA_SEP'
			param_name=${param_name%%"${oa_sep}"*} # %% in case arg contains OA_SEP
			arg=${current#*"${oa_sep}"}            # extract arg
			if [[ ${arg} == true ]]; then
				# '-currnt=true' like, a bool
				param_ref="${lid}${param_name}${tag_true}"
				return 2
			elif [[ ${arg} == false ]]; then
				# '-current=false' like, a bool
				param_ref="${lid}${param_name}${tag_false}"
				return 2
			else
				# '-current="right now"' like, a string
				return 4
			fi
		elif bp_with_lid "${next}" || [[ -z "${next}" ]]; then
			# '-current -next' like, or no next(reach the end), a bool
			return 2
		else
			# '-current next' like, next is an arg
			param_name=${current#"${lid}"}
			if [[ ${next} == true ]]; then
				# '-current true' like, a bool(next is a boolean value)
				param_ref="${param_name}${tag_true}"
				return 3
			elif [[ ${next} == false ]]; then
				# '-current false' like, a bool(next is a boolean value)
				param_ref="${param_name}${tag_false}"
				return 3
			else
				# '-current "year of 1984"' like, a string(next is not a boolean value)
				param_ref="${current}${oa_sep}${next}"
				return 5
			fi
		fi
	elif bp_with_lid "${current}"; then
		# '<alter-lid>current ' like, match other lids(include ligas)
		if bp_with_lid "${next}" || [[ -z "${next}" ]]; then
			# '<alter-lid>current <lid>next' like
			# or '<alter-lid>current --' like, not consume an arg
			return 6
		else
			# '<lid>current next' like, will consume an arg
			# when 'current == *${OA_SEP}*' like, or
			#      'current == -param-' like, might be an input error
			# leave it to alter-lid parsing to handle
			return 7
		fi
	else # without any lid, an arg; leave it to further parsing
		return 0
	fi
}

# apply parsed Harness options (Globals/Priors/Specs) to CONFIGS
# $1 — nameref to associative array of {key: value} pairs from the tier
# calls bp_set_configs for each entry, then refreshes LIDS/TAGS via bosparse_update_mutables
bp_apply_setup() {
	local -n setup_bas=$1

	local ps field_len

	bp_msg 3 "  Apply settings"
	if [[ ${#setup_bas[@]} -eq 0 ]]; then
		bp_msg -3 "    " "no new setup"
		return 0
	fi
	# bp_msg 4 "    ${title} settings applied:" >&2
	# apply settings to CONFIGS
	field_len=$(bp_max_array_member_length "${!setup_bas[@]}")
	for ps in "${!setup_bas[@]}"; do
		bp_msg 4 "      $(printf "\e[0;2m%${field_len}s - '%s'\n" "${ps}" "${setup_bas[${ps}]}")" >&2
		bp_set_configs "${ps}" "${setup_bas[${ps}]}"
	done
	bosparse_update_mutables
}

# assign PFILTER default values to parameters not supplied by the user
# $1 — nameref to user-supplied options (modified in-place for missing params)
# $2 — nameref to PFILTER entries {key: "type:data:mcg"}
# skips MCG members; fails with exit 55 if a non-MCG param has no default
# enum defaults use the first element of the enum list
bp_apply_filter_default() {
	local -n opt_afd=$1 filter_afd=$2

	local pf_type pf_data pf_mcg

	bp_msg 3 "  Assign PFILTER default values if not supplied"
	local prn_pattern='%15s - %12s | %8s | %14s | %-10s'
	[[ ${verbose} -ge 3 ]] && printf "    \e[4;33m${prn_pattern}\e[0m\n" \
		"param" "status" "type" "data" "mcg" >&2
	for param in "${!filter_afd[@]}"; do
		bp_extract_filter_schema "${CONFIGS[ulid]}" "${filter_afd[${param}]}" pf_type pf_data pf_mcg
		# skip mcg members
		[[ -z ${pf_mcg} ]] || {
			[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
				"${param}" "MCG member" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" >&2
			continue
		}
		# skip supplied ones
		[[ -v opt_afd["${param}"] ]] && {
			[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
				"${param}" "supplied" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" >&2
			continue
		}
		# no default value, failed
		if [[ -z "${pf_data}" ]]; then
			local pros_tag[0]="${param}"
			bp_exit_with_msg 55 pros_tag
		fi

		# assigning defaults
		[[ ${verbose} -ge 3 ]] && printf "    \e[2;33m${prn_pattern}\e[0m\n" \
			"${param}" "default" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" >&2
		case "${pf_type}" in
		bool | string)
			opt_afd["${param}"]="${pf_data}"
			;;
		enum)
			# set with first enum as default value
			opt_afd["${param}"]="${pf_data%%"${CONFIGS[es]}"*}"
			;;
		*) # this will not happen since integrity checking already done in bp_validate_pfilter
			;;
		esac
		[[ ${verbose} -ge 3 ]] && printf "    \e[2m${prn_pattern}\e[0;2m%s\e[0m\n" \
			"${param}" "assigned" "${pf_type}" "${opt_afd[${param}]:--}" "${pf_mcg}" >&2
	done
	return 0
}

# display current CONFIGS settings, for debugging & directives
bp_show_configs() {
	local output_as_json key param len_key

	[[ ${CONFIGS["json"]} == true ]] && output_as_json=true || output_as_json=false
	[[ ${CONFIGS["run"]} == "capture" ]] && output_as_json=true

	if [[ ${CONFIGS["Defaults"]} == true ]]; then
		if [[ ${output_as_json} == true ]]; then
			bp_validate_jq
			bp_serialize_pfilter CONFIGS | jq
		else
			bp_show_array CONFIGS 2>&1 | sort -n
		fi
	else
		local key
		for key in "${!CONFIGS[@]}"; do
			printf '%s=%q\n' "${key}" "${CONFIGS[${key}]}"
		done | sort -n
	fi
}

# replace exception characters in a variable name per VN_EXCEPTIONS map
# $1 — nameref: variable name to modify (modified in-place)
# currently replaces hyphens with underscores, e.g. "my-param" → "my_param"
# first and last characters are never substituted (preserves LID/tag boundaries)
# no-op when string length <= 2
bp_substitute_exceptions() {
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
