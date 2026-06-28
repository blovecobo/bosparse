# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154,SC2015
# Module 06-validate: Parameter validation against PFILTER and MCG rules
#   bp_validate_option_name()        — match param name against filter (exact/prefix/multi)
#   bp_validate_option_args()        — validate value per type (bool/string/enum/resym)
#   bp_get_all_mcgs()                — collect all MCG names from PFILTER entries
#   bp_validate_mcg_types()          — ensure MCG names start with valid type prefixes
#   bp_validate_required_groups()    — enforce required MCG members are supplied
#   bp_build_mcg_membership_map()    — invert PFILTER: MCG name to member list
#   bp_validate_dependence_groups()  — d-member supplied requires D-member supplied
#   bp_validate_master_groups()      — M/m MCG rules
#   bp_validate_option_mcgs()        — orchestrate all MCG validation by type
#   bp_validate_mcg_name()           — validate MCG name (hyphens allowed, not at edges)
#   bp_validate_variable_name()      — validate & normalize a shell variable name
# --------------------------------------------------------------------------------

# match a parameter name against PFILTER keys using exact or prefix matching
# $1 — nameref: parameter name (modified in-place to matched key on success)
# $2 — nameref: filter keys array
# $3 — lid context
# $4 — tier title (for error messages)
# when lid is ulid and pme is off: exact-only matching
# otherwise: prefix matching via bp_prefix_matching
# exits 53/54 (no match) or 56 (multiple matches) on failure
bp_validate_option_name() {
	local -n param_ref=$1 filter_ref=$2
	local lid=$3 ptitle=$4

	bp_msg -3 "    Option name: " "${param_ref}"

	local matched_names rtn=0
	if [[ ${lid} == "${CONFIGS[ulid]}" && ${CONFIGS["pme"]} != true ]]; then
		# no prefix-matching for user parameters when pme unset
		bp_is_array_member "${param_ref}" filter_ref && return 0
		return 1
	else
		# when prefix/postfix matching enabled
		matched_names=$(bp_prefix_matching "${param_ref}" filter_ref "prefix") || rtn=$?
	fi

	if ((rtn == 0)); then
		bp_msg -4 "    - name: " "${param_ref} -> ${matched_names}"
		param_ref="${matched_names}"
		return 0
	else
		local pros_tag[0]="${ptitle:-Parameter}"
		pros_tag[1]="${lid}${param_ref}"
		case ${rtn} in
		1) if [[ ${lid} == "${CONFIGS[ulid]}" ]]; then
			bp_exit_with_msg 53 pros_tag
		else
			bp_exit_with_msg 54 pros_tag
		fi ;;
		2)
			pros_tag[2]="${matched_names// /|}"
			bp_exit_with_msg 56 pros_tag
			;;
		*) ;;
		esac
	fi
	return 0
}

# validate a parameter's value against its declared PFILTER type
# $1 — lid context
# $2 — tier title (for error messages)
# $3 — original parameter name
# $4 — canonical parameter name (after matching)
# $5 — nameref: value to validate (modified for enum EMF/EML shortcuts)
# $6 — PFILTER entry type (bool/string/enum/resym)
# $7 — PFILTER entry data (default value, enum list, or resym spec)
# $8 — PFILTER entry mcg (unused here, for logging)
#
# enum: supports EMF (false→first) / EML (true→last) shortcuts
# enum: prefix-matching against enum list; exits 50 (no match) or 56 (multi-match)
# bool: must be "true" or "false"; exits 51
# string: must not be "true" or "false"; exits 51
# resym: must be all-resym-char (digits stripped before check); uses pf_data for
#        length constraint and exclusion chars; exits 51/52 on violation
bp_validate_option_args() {
	local lid=$1 ptitle=$2
	local param=$3 param_cmp=$4
	local -n arg_ref=$5
	local pf_type=$6 pf_data=$7 pf_mcg=$8

	local pros_tag[0]="${ptitle}"

	bp_msg -3 "    Option arg: " "${arg_ref}"
	[[ ${verbose} -ge 4 ]] &&
		printf "      \e[33marg:  \e[0;2m%-6s | type - %-6s | mcg - %-12s | data - %s\e[0m\n" \
			"${arg_ref}" "${pf_type}" "${pf_mcg:--}" "${pf_data:--}" >&2
	case ${pf_type} in
	enum)
		# this branch must in front of "bool" branch in case EMF & EMl usage
		# split enum string safely into array, handling escapes
		local pf_data_orig="${pf_data}" # may useful for error msg
		local enum_list=()
		bp_extract_enum_list "${pf_data}" enum_list
		# restore pf_data in case used in error mssage
		pf_data="${pf_data_orig}"
		# EMF and EML by value (false/true)
		if [[ ${arg_ref} == false ]]; then
			arg_ref="${enum_list[0]}"
			return 0
		elif [[ ${arg_ref} == true ]]; then
			arg_ref="${enum_list[-1]}"
			return 0
		fi
		# try prefix-matching
		local pfm_names rtn=0
		pfm_names=$(bp_prefix_matching "${arg_ref}" enum_list) || rtn=$?
		case ${rtn} in
		0)
			# exactly or prefixly matched, assign result with the exact name
			arg_ref="${pfm_names}"
			;;
		1)
			# not matched
			pros_tag[1]="${lid}${param}='${arg_ref}'"
			pros_tag[2]="${pf_data}"
			bp_exit_with_msg 50 pros_tag
			;;
		2)
			# multiple matched
			pros_tag[0]="enum value of"
			if [[ -z ${arg_ref} ]]; then
				pros_tag[1]="${lid}${param}"
			else
				pros_tag[1]="${lid}${param}=${arg_ref}"
			fi
			pros_tag[2]="${pfm_names[*]// / \| }"
			bp_exit_with_msg 56 pros_tag
			;;
		*) ;;
		esac
		;;
	bool)
		# validate type
		if [[ ${arg_ref} != true && ${arg_ref} != false ]]; then
			pros_tag[1]="${param}='${arg_ref}'"
			pros_tag[2]="'true' or 'false'"
			bp_exit_with_msg 51 pros_tag
		fi
		;;
	string)
		if [[ ${arg_ref} == true || ${arg_ref} == false ]]; then
			pros_tag[1]="${param}='${arg_ref}'"
			pros_tag[2]="a string but got a bool"
			bp_exit_with_msg 51 pros_tag
		fi
		;;
	resym)
		# if consist of resyms
		bp_is_in_resyms "${arg_ref//[0-9]/}" || { # remove length before testing resyms
			pros_tag[1]="${param}='${arg_ref}'"
			pros_tag[2]="a RESYM or RESYMs but got '${arg_ref}'"
			bp_exit_with_msg 51 pros_tag
		}
		# validate length of resym if specified in pf_data, e.g. "resym:3-_" means a parameter
		# with length of 3 and cannot contains '-' and '_' (sequence not matter)
		local resym_len=${pf_data//[^[:digit:]]/}
		[[ -n ${resym_len} ]] || resym_len=1
		if [[ ${#arg_ref} -ne ${resym_len} ]]; then
			pros_tag[1]="${param}='${arg_ref}'"
			pros_tag[2]="mismatch length, value length should be '${resym_len}' instead of '${#arg_ref}'"
			bp_exit_with_msg 52 pros_tag
		fi
		# check excluded resyms
		local exclude_resym="${pf_data//[0-9]/}"
		if [[ ${arg_ref} =~ [${exclude_resym}] ]]; then
			pros_tag[1]="${param}='${arg_ref}'"
			pros_tag[2]="contains resym(s) not permitted: '${exclude_resym}'"
			bp_exit_with_msg 52 pros_tag
		fi
		;;
	*) # will not happen, shellcheck keep warning without default branch of case block
		;;
	esac
	return 0
}

# collect all unique MCG names referenced across PFILTER entries
bp_get_all_mcgs() {
	local lid=$1
	local -n filter=$2 mcgs_ref=$3

	local mem dummy mcg mcg_name mcg_names=()
	local ELM_SEP="${CONFIGS[es]}"

	for mem in "${!filter[@]}"; do
		bp_extract_filter_schema "${lid}" "${filter[${mem}]}" dummy dummy mcg
		if [[ -n ${mcg} ]]; then
			bp_escape_symbol mcg "${ELM_SEP}"
			# a param might belongs to multiple groups separated by ELM_SEP
			readarray -d "${ELM_SEP}" -t mcg_names <<<"${mcg}"
			mcg_names[-1]="${mcg_names[-1]%$'\n'}"
			for mcg_name in "${mcg_names[@]}"; do
				# clean up mcg-name
				bp_escape_symbol mcg_name "${ELM_SEP}" "regress"
				mcgs_ref["${mcg_name}"]=true
			done
		fi
	done
}

# verify each MCG name starts with a valid type prefix (d/D/e/m/M/r/u)
bp_validate_mcg_types() {
	local -n mcg_names_ref=$1

	# all available type in PFILTER
	# assum MCG_TYPE schema: 'type:name-prefix'
	local -a mcgt_mt=() mem
	for mem in "${MCG_TYPES[@]}"; do
		mcgt_mt+=("${mem#*"${CONFIGS[fs]}"}")
	done

	declare -A mcg_type_map=()
	for mem in "${mcgt_mt[@]}"; do mcg_type_map["${mem}"]=true; done

	# group names should match initial letters
	for mem in "${mcg_names_ref[@]}"; do
		[[ -v mcg_type_map[${mem:0:1}] ]] || {
			local pros_tag[0]="${mem}" IFS="${CONFIGS[es]}"
			pros_tag[1]="MCG name should start with '${mcgt_mt[*]}'"
			bp_exit_with_msg 37 pros_tag
		}
	done
}

# bp_validate_required_groups: ensure all members of Required MCGs are supplied or have defaults
bp_validate_required_groups() {
	local -n groups=$1 filter_rg=$2 opts=$3

	local mcg mem def_type def_data def_mcg
	local mem_mcgs
	declare -a mcg_mems=()

	bp_msg 3 "    checking Required MCGs"
	for mcg in "${groups[@]}"; do
		[[ ${mcg,,} =~ ^r ]] || continue
		bp_msg -3 "      - checking MCG - " "${mcg}"

		mem_mcgs="" # all mcgs an entry inside
		mcg_mems=() # all members in a mcg

		# find members in the same mcg
		for mem in "${!filter_rg[@]}"; do
			bp_extract_filter_schema "${lid}" "${filter_rg[${mem}]}" def_type def_data mem_mcg
			readarray -d "${CONFIGS[es]}" -t mem_mcgs <<<"${mem_mcg}"
			mem_mcgs[-1]="${mem_mcgs[-1]%$'\n'}"
			for mcg_entry in "${mem_mcgs[@]}"; do
				if [[ "${mcg}" =~ ^${mcg_entry,,} ]]; then
					mcg_mems+=("${mem}")
					break
				fi
			done
		done

		# check if all members available(supplied or can be fulfilled)
		for mem in "${mcg_mems[@]}"; do
			if [[ -v opts["${mem}"] ]]; then
				bp_msg -3 "      " "- member '${mem}@${mcg}' supplied"
				continue
			else
				bp_extract_filter_schema "${lid}" "${filter_rg[${mem}]}" def_type def_data def_mcg
				if [[ -n ${def_data} ]]; then
					bp_msg -3 "      " "- member '${mem}@${mcg}' fulfill with default"
					opts["${mem}"]="${def_data}"
				else
					bp_msg -3 "      " "- member '${mem}@${mcg}' not available"
					local pros_tag[0]="${mcg}"
					pros_tag[1]="${mem}"
					# pros_tag[2]="${mcg_mems[*]}"
					bp_exit_with_msg 70 pros_tag
				fi
			fi
		done
		bp_msg 3 "        - MCG ${mcg}: PASSED"
	done
}

# single-pass: build mcg -> members mapping from all PFILTER entries
bp_build_mcg_membership_map() {
	local lid=$1
	local -n filter_bmm=$2 mcg_mems=$3

	local mem def_type def_data def_mcg mcg_name
	local -a mem_mcg_names ELM_SEP="${CONFIGS[es]}"

	for mem in "${!filter_bmm[@]}"; do
		bp_extract_filter_schema "${lid}" "${filter_bmm[${mem}]}" def_type def_data def_mcg
		[[ -n ${def_mcg} ]] || continue
		bp_escape_symbol def_mcg "${ELM_SEP}" "regress"
		readarray -d "${ELM_SEP}" -t mem_mcg_names <<<"${def_mcg}"
		mem_mcg_names[-1]="${mem_mcg_names[-1]%$'\n'}"
		for mcg_name in "${!mem_mcg_names[@]}"; do
			bp_escape_symbol mem_mcg_names["${mcg_name}"] "${ELM_SEP}" "regress"
		done
		for mcg_name in "${mem_mcg_names[@]}"; do
			mcg_mems["${mcg_name}"]+="|${mem}"
		done
	done
}

# validate dependence groups: any d-member(s) supplied requires D-member(s) supplied
bp_validate_dependence_groups() {
	local -n _dc_supplied=$1 _dc_unsupplied=$2 _dl_supplied=$3 _dl_unsupplied=$4
	local lid=$5

	local cap_mcg d_member
	local -a d_members
	local D_groups=("${!_dc_supplied[@]}" "${!_dc_unsupplied[@]}")
	local IFS="${CONFIGS[es]}"

	for cap_mcg in "${D_groups[@]}"; do
		[[ -n ${_dc_supplied["${cap_mcg}"]:-} ]] &&
			bp_msg -3 "      " "- member '${_dc_supplied[${cap_mcg}]}'@${cap_mcg} supplied"
		[[ -n ${_dc_unsupplied["${cap_mcg}"]:-} ]] &&
			bp_msg -3 "      " "- member '${_dc_unsupplied[${cap_mcg}]}'@${cap_mcg} un-supplied"

		[[ -n ${_dl_unsupplied[${cap_mcg,}]:-} ]] && {
			read -ra d_members <<<"${_dl_unsupplied[${cap_mcg,}]#\|}"
			for d_member in "${d_members[@]}"; do
				bp_msg -3 "      " "- member '${d_member}'@${cap_mcg,} un-supplied\e[0m"
			done
		}

		if [[ -n ${_dl_supplied[${cap_mcg,}]:-} ]]; then
			read -ra d_members <<<"${_dl_supplied[${cap_mcg,}]#\|}"
			for d_member in "${d_members[@]}"; do
				bp_msg -3 "      " "- member '${d_member}'@${cap_mcg,} supplied"
			done
			if [[ -n ${_dc_supplied["${cap_mcg}"]:-} ]]; then
				bp_msg 3 "     - MCG ${cap_mcg,}: PASSED"
			else
				bp_msg 3 "      - MCG ${cap_mcg,}: FAILED"
				local pros_tag
				case ${lid} in
				"${CONFIGS[glid]}") pros_tag[0]="Global '${_dc_unsupplied[${cap_mcg}]}'" ;;
				"${CONFIGS[plid]}") pros_tag[0]="Prior '${_dc_unsupplied[${cap_mcg}]}'" ;;
				"${CONFIGS[slid]}") pros_tag[0]="Spec '${_dc_unsupplied[${cap_mcg}]}'" ;;
				*) pros_tag[0]="Parameter '${_dc_unsupplied[${cap_mcg}]}'" ;;
				esac
				pros_tag[1]="${d_members[*]}"
				pros_tag[2]="${cap_mcg,}"
				bp_exit_with_msg 46 pros_tag
			fi
		else
			bp_msg 3 "      - MCG ${cap_mcg,}: PASSED"
		fi
	done
}

# validate master groups:
#   1 if the m-member supplied, fails
#   2 if just none M-member supplied, pass
#   3 if one M-member supplied: assign supplied M-member's name to m-member
#   4 fails for others
bp_validate_master_groups() {
	local -n _mc_members=$1 _mc_count=$2
	local -n _ml_supplied=$3 _ml_unsupplied=$4
	local -n _mc_supplied=$5 _mc_unsupplied=$6
	local -n options_vmg=${7}

	local mcg

	for mcg in "${!_mc_members[@]}"; do
		# m-member supply not allowed
		if [[ ${#_ml_supplied["${mcg,}"]} -ne 0 ]]; then
			bp_msg -3 "      " "- member '${_ml_supplied[${mcg,}]#\|}'@${mcg,} supplied\e[0m"
			bp_msg 3 "      - MCG ${mcg}: FAILED"
			local pros_tag[0]="${_ml_supplied[${mcg,}]}"
			pros_tag[1]="${_mc_members[${mcg}]#|}"
			pros_tag[2]="${mcg,}"
			bp_exit_with_msg 47 pros_tag
		fi

		if [[ ${_mc_count["${mcg}"]:-0} -eq 0 ]]; then
			# no M-members supplied
			bp_msg -3 "      " "- member '${_mc_members[${mcg}]#\|}'@${mcg} un-supplied\e[0m"
			[[ -v options_vmg["${_ml_unsupplied[${mcg,}]}"] ]] &&
				unset "options_vmg[${_ml_unsupplied[${mcg,}]}]"
		else
			# show status of M-members
			[[ -z ${_mc_unsupplied["${mcg}"]:-} ]] ||
				bp_msg -3 "      " "- member '${_mc_unsupplied[${mcg}]#\|}'@${mcg} un-supplied\e[0m"
			bp_msg -3 "      " "- member '${_mc_supplied[${mcg}]#\|}'@${mcg} supplied\e[0m"

			if [[ ${_mc_count["${mcg}"]} -ne 1 ]]; then
				# multiple M-members supplied
				bp_msg 3 "      - MCG ${mcg}: Failed"
				local pros_tag[0]="${_mc_supplied[${mcg}]#\|}"
				pros_tag[1]="${_mc_members[${mcg}]#|}"
				bp_exit_with_msg 45 pros_tag
			fi

			# only one M-member supplied
			[[ -v options_vmg["${_ml_unsupplied[${mcg,}]}"] ]] &&
				unset "options_vmg[${_ml_unsupplied[${mcg,}]}]"
			options_vmg["${_ml_unsupplied[${mcg,}]}"]="${_mc_supplied[${mcg}]#\|}"
		fi
		bp_msg 3 "    - MCG ${mcg}: Passed"
	done
}

# orchestrate all MCG validation: classify, then validate per-type rules
# globals relied:
#   - CONFIGS
bp_validate_option_mcgs() {
	local lid=$1
	local -n filter_vom=$2 options_vom=$3

	bp_msg 2 "  MCG validation"

	# collect and validate MCG names
	declare -A mc_groups=()
	bp_get_all_mcgs "${lid}" filter_vom mc_groups
	local -a mcg_list=("${!mc_groups[@]}")
	bp_msg -3 "    MCG names: " "${mcg_list[*]}"
	bp_validate_mcg_types mcg_list

	# validate requirement mcg for user parameters only
	bp_validate_required_groups mcg_list filter_vom options_vom

	# build MCG membership map
	declare -A mcg_members_map=()
	bp_build_mcg_membership_map "${lid}" filter_vom mcg_members_map

	# accumulator arrays populated during member classification
	declare -A dl_supplied=() dl_unsupplied=()
	declare -A dc_supplied=() dc_unsupplied=()
	declare -a eg_supplied=()
	declare -A ml_supplied=() ml_unsupplied=() ml_types=() ml_members=() ml_values=()
	declare -A mc_supplied=() mc_unsupplied=() mc_members=() mc_count=()
	declare -A ug_values=()
	declare -a ug_supplied=()

	local -a mcg_members=()
	local def_type def_data def_mcg
	local mcg member default_value

	# classify members for each MCG
	for mcg in "${mcg_list[@]}"; do
		# skip r/R (required — handled by bp_validate_required_groups) and non-MCG names
		# skip r/R (required — handled by validate_required_groups) and non-MCG names
		[[ ${mcg:0:1} == [rR] ]] && continue

		readarray -d "${CONFIGS[es]}" -t mcg_members <<<"${mcg_members_map[${mcg}]#|}"
		mcg_members[-1]="${mcg_members[-1]%$'\n'}"
		eg_supplied=()
		ug_values=()
		ug_supplied=()

		for member in "${mcg_members[@]}"; do
			bp_extract_filter_schema "${lid}" "${filter_vom[${member}]}" def_type def_data def_mcg
			case ${mcg:0:1} in
			d)
				if [[ -v options_vom["${member}"] ]]; then
					dl_supplied["${mcg}"]="${dl_supplied["${mcg}"]:-}|${member}"
				else
					dl_unsupplied["${mcg}"]="${dl_unsupplied["${mcg}"]:-}|${member}"
				fi
				;;
			D)
				[[ -v options_vom["${member}"] ]] &&
					dc_supplied["${mcg}"]="${member}" ||
					dc_unsupplied["${mcg}"]="${member}"
				;;
			e)
				if [[ -v options_vom["${member}"] ]]; then
					bp_msg -3 "      " "- member '${member}'@${mcg} supplied"
					eg_supplied+=("${member}")
				else
					bp_msg -3 "      " "- member '${member}'@${mcg} un-supplied, ignored\e[0m"
				fi
				;;
			m)
				ml_members["${mcg}"]="${ml_members[${mcg}]:-}|${member}"
				ml_types["${mcg}"]="${def_type}"
				ml_values["${mcg}"]="${def_data}"
				[[ -v options_vom["${member}"] ]] &&
					ml_supplied["${mcg}"]="${member}" ||
					ml_unsupplied["${mcg}"]="${member}"
				;;
			M)
				mc_members["${mcg}"]="${mc_members[${mcg}]:-}|${member}"
				if [[ -v options_vom["${member}"] ]]; then
					mc_supplied["${mcg}"]="${mc_supplied[${mcg}]:-}|${member}"
					((mc_count["${mcg}"] += 1))
				else
					mc_unsupplied["${mcg}"]="${mc_unsupplied[${mcg}]:-}|${member}"
				fi
				;;
			u)
				if [[ -v options_vom["${member}"] ]]; then
					bp_msg -3 "      " "- member '${member}'@${mcg} supplied"
					ug_values["${options_vom[${member}]}"]=true
					ug_supplied+=("${member}")
				else
					bp_msg -3 "      " "- member '${member}'@${mcg} un-supplied, ignored\e[0m"

					# [[ ${lid} == "${CONFIGS[ulid]}" ]] && {
					# 	bp_msg -3 "      " "- member '${member}'@${mcg} un-supplied, ignored\e[0m"
					# 	continue
					# }
					# # for Harnesses, they are always 'supplied'
					# ug_supplied+=("${member}")
					# default_value="${CONFIGS[${member}]}"
					# bp_msg -3 "      " "- member '${member}' un-supplied, default: '${default_value}'"
					# ug_values["${default_value}"]=true
				fi
				;;
			*) ;;
			esac
		done

		# per-group assertions
		case ${mcg:0:1} in
		e)
			# bp_msg -3 "      - supplied members: " "${eg_supplied[*]}"
			if [[ ${#eg_supplied[@]} -gt 1 ]]; then
				bp_msg 3 "      - MCG ${mcg}: FAILED"
				local pros_tag[0]="${mcg}"
				pros_tag[1]="${eg_supplied[*]}"
				bp_exit_with_msg 42 pros_tag
			fi
			;;
		u)
			if [[ ${#ug_values[@]} -ne "${#ug_supplied[@]}" ]]; then
				bp_msg 3 "      - MCG ${mcg}: FAILED"
				local pros_tag[0]="${mcg}"
				pros_tag[1]="${mcg_members[*]}"
				bp_exit_with_msg 41 pros_tag
			fi
			;;
		*) ;;
		esac
		[[ ${mcg:0:1} == [eu] ]] && bp_msg 3 "      - MCG ${mcg}: PASSED"
	done

	bp_validate_dependence_groups dc_supplied dc_unsupplied dl_supplied dl_unsupplied "${lid}"

	bp_validate_master_groups \
		mc_members mc_count \
		ml_supplied ml_unsupplied \
		mc_supplied mc_unsupplied \
		options_vom

	return 0
}

# validate an MCG name: hyphens allowed internally, not at edges
# $1 — MCG name to validate
# rules:
#   - no leading or trailing hyphen (exits 37)
#   - body (after removing first/last char) must be [a-zA-Z0-9_-]+
# exits 37 on invalid name
bp_validate_mcg_name() {
	local mcg_name=$1

	local pros_tag[0]="${mcg_name}"
	local first="${mcg_name:0:1}" last="${mcg_name: -1}"
	if [[ ${first} == '-' ]] || [[ ${last} == '-' ]]; then
		pros_tag[1]="a hyphen '-' at the beginning or end of MCG name are not allowed."
		bp_exit_with_msg 37 pros_tag
	fi

	local test_name="${mcg_name:1:-1}"
	[[ ${test_name} =~ ^[a-zA-Z0-9_-]*$ ]] && return 0
	pros_tag[1]="contains invalid character(s): '${test_name//[a-zA-Z0-9_-]/}'"
	bp_exit_with_msg 37 pros_tag
}

# validate a shell variable name (exception substitution must be done before calling)
# $1 — class/label for the variable (used in error messages)
# $2 — nameref: variable name to validate (not modified)
# $3 — return_on_error (default false): if true, returns 1 instead of exiting on failure
# rules:
#   - must not be empty (exit 26 / return 1)
#   - must not start or end with hyphen (exit 22 / return 1)
#   - must match ^[a-zA-Z_][a-zA-Z0-9_]*$ (exit 22/23/21 or return 1)
# returns: 0 if valid, 1 if invalid (only when return_on_error=true)
bp_validate_variable_name() {
	local var_class=$1
	local -n var_name_ref="$2"
	local return_on_error=${3:-false}

	local pros_tag[0]="${var_class}"
	pros_tag[1]="${var_name_ref}"

	if [[ -z "${var_name_ref}" ]]; then
		[[ ${return_on_error} == true ]] && return 1
		bp_exit_with_msg 26 pros_tag
	fi

	# leading or trailing hyphens are not allowed (would break LID/trailing-tag parsing)
	if [[ ${var_name_ref} == -* ]] || [[ ${var_name_ref} == *- ]]; then
		if [[ ${return_on_error} == true ]]; then
			return 1
		fi
		pros_tag[2]="-"
		bp_exit_with_msg 22 pros_tag
	fi

	[[ ${var_name_ref} =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && return 0

	[[ ${return_on_error} == true ]] && return 1

	if [[ ${var_name_ref:0:1} == [0-9] ]]; then
		pros_tag[2]="${var_name_ref:0:1}"
		bp_exit_with_msg 23 pros_tag
	fi

	if [[ ! ${var_name_ref} =~ ^[a-zA-Z0-9_]+$ ]]; then
		pros_tag[2]="${var_name_ref//[a-zA-Z0-9_]/}"
		bp_exit_with_msg 22 pros_tag
	fi
	bp_exit_with_msg 21 pros_tag
}
