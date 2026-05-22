# Option validation ---------------------------------------------------------------

function validate_option_name() {
	local lid=$1
	local -n param_ref=$2 matching_filter=$3
	local mandatory=${4:-true}

	local matched_names rtn=0

	# msg_bp 4 "      validate param: ${param_ref} | mandatory: ${mandatory}"

	matched_names=$(prefix_matching "${param_ref}" matching_filter) || rtn=$?

	if [[ ${rtn} -eq 0 ]]; then
		# matched(exact or prefix-), return the exact name
		param_ref="${matched_names}"
		return 0
	elif [[ ${mandatory} == true ]]; then
		# not matched but mandatory required
		pros_tag="${ptitle}"
		pros_tag2="${lid}${param_ref}"
		case ${rtn} in
		1) # not matched
			if [[ ${lid} == "${ULID}" ]]; then
				exit_with_msg 53
			else
				exit_with_msg 54
			fi
			;;
		2) # multiple matched
			pros_tag3="${matched_names// /|}"
			exit_with_msg 56
			;;
		*) ;;
		esac
	fi
	return 0
}
function validate_option_args() {
	local lid=$1
	local param=$2 e_param=$3 pf_type=$4 pf_data=$5 pf_mcg=$6

	local i
	# echo param: $param
	local val=${v_options[${e_param}]}
	declare pm_arr=()

	pros_tag="${ptitle}"

	[[ ${verbose} -ge 4 ]] && printf "    \e[2m%-8s - %-14s | %-6s | %10s | %-10s | %s\n\e[0m" \
		"${param}" "${e_param}" "${pf_type}" "${pf_data}" "${val}" "${pf_mcg:--}" >&2
	case ${pf_type} in
	enum)
		# this branch must in front of "bool" branch in case EMF & EMl usage
		# split enum string safely into array, handling escapes
		local pf_data_orig="${pf_data}"
		local enum_list=()
		extract_enum_list "${pf_data}" enum_list
		# restore pf_data in case used in error mssage
		pf_data="${pf_data_orig}"
		# EMF by false
		if [[ ${val} == false ]]; then
			# EMF, an enum parameter intend to use first value, use bool parameter syntax 'false'
			# remove the parameter from v_bools, re-assign with the first item of enum list
			unset "v_bools[${e_param}]"
			v_options[${e_param}]="${enum_list[0]}"
			v_strings[${e_param}]="${enum_list[0]}"
			return 0
		fi
		# EML by true
		if [[ ${val} == true ]]; then
			# EML, an enum parameter intend to use last value, use bool parameter syntax 'true'
			# remove the parameter from v_bools, re-assign with the last item of enum list
			unset "v_bools[${e_param}]"
			v_options[${e_param}]="${enum_list[-1]}"
			v_strings[${e_param}]="${enum_list[-1]}"
			return 0
		fi
		# try prefix-matching
		local pfm_names rtn=0
		pfm_names=$(prefix_matching "${val}" enum_list) || rtn=$?
		case ${rtn} in
		0)
			# exactly or prefixly matched, assign result with the exact name
			v_options[${e_param}]="${pfm_names}"
			v_strings[${e_param}]="${pfm_names}"
			;;
		1)
			# not matched
			pros_tag2="${lid}${param}='${val}'"
			pros_tag3="${pf_data}"
			exit_with_msg 50
			;;
		2)
			# multiple matched
			pros_tag="enum value of"
			pros_tag2="${lid}${param}=${val}"
			# pros_tag3="${pfm_names[*]//"${ELM_SEP}"/\/}"
			pros_tag3="${pfm_names[*]}"
			exit_with_msg 56
			;;
		*) ;;
		esac
		;;
	bool)
		# validate type
		if [[ ${val} != true && ${val} != false ]]; then
			pros_tag2="${param}='${val}'"
			pros_tag3="'true' or 'false'"
			exit_with_msg 51
		fi
		;;
	string)
		if [[ ${val} == true || ${val} == false ]]; then
			pros_tag2="${param}='${val}'"
			pros_tag3="a string but got a bool"
			exit_with_msg 51
		fi
		;;
	resym)
		# if consist of resyms
		is_in_resyms "${val//[0-9]/}" || { # remove length before testing resyms
			pros_tag2="${param}='${val}'"
			pros_tag3="a RESYM or RESYMs but got '${val}'"
			exit_with_msg 51
		}
		# validate length of resym if specified in pf_data, e.g. "resym:3-_" means a parameter
		# with length of 3 and cannot contains '-' and '_' (sequence not matter)
		local resym_len=${pf_data//[^[:digit:]]/}
		[[ -n ${resym_len} ]] || resym_len=1
		if [[ ${#val} -ne ${resym_len} ]]; then
			pros_tag2="${param}='${val}'"
			pros_tag3="mismatch length, value length should be '${resym_len}' instead of '${#val}'"
			exit_with_msg 52
		fi
		# check excluded resyms
		local exclude_resym="${pf_data//[0-9]/}"
		if [[ ${val} =~ [${exclude_resym}] ]]; then
			pros_tag2="${param}='${val}'"
			pros_tag3="contains resym(s) not permitted: '${exclude_resym}'"
			exit_with_msg 52
		fi
		;;
	*) # will not happen, shellcheck keep warning without default branch of case block
		;;
	esac
	return 0
}
function get_all_mcg_names() {
	local lid=$1
	local -n pfilter=$2 mcg_groups_ref=$3
	local mem dummy mcg mcg_name

	for mem in "${!pfilter[@]}"; do
		extract_filter_schema "${lid}" "${pfilter[${mem}]}" dummy dummy mcg
		if [[ -n ${mcg} ]]; then
			escape_symbol mcg "${ELM_SEP}"
			# a param might belongs to multiple groups
			local IFS="${ELM_SEP}"
			for mcg_name in ${mcg}; do
				# clean up mcg-name
				escape_symbol mcg_name "${ELM_SEP}" "regress"
				mcg_groups_ref["${mcg_name}"]=true
			done
		fi
	done
}
function validate_mcg_types() {
	local -n mcg_names_ref=$1

	local mem
	declare -a mcg_types=()

	# all available type in PFILTER
	for mem in "${MCG_TYPES[@]}"; do
		mcg_types+=("${mem#*"${FLD_SEP}"}")
	done

	declare -A mcg_type_map=()
	for mem in "${mcg_types[@]}"; do mcg_type_map["${mem}"]=true; done

	for mem in "${mcg_names_ref[@]}"; do
		[[ -v mcg_type_map[${mem:0:1}] ]] || {
			pros_tag="${mem}"
			pros_tag2="${mcg_types[*]}"
			exit_with_msg 37
		}
	done
}

# validate_required_groups: ensure all members of Required MCGs are supplied or have defaults
function validate_required_groups() {
	local -n groups=$1 filter_ref2=$2

	local mcg member def_type def_data
	local member_mcg
	declare -a mcg_members=()

	msg_bp 3 "    checking Required MCGs"
	for mcg in "${groups[@]}"; do
		[[ ${mcg,,} == required* ]] || continue
		# msg_bp -3 "    - checking MCG - " "${mcg}"

		member_mcg=""
		mcg_members=()

		# find members in the same mcg
		for member in "${!filter_ref2[@]}"; do
			member_mcg=${filter_ref2[${member}]##*:}
			if [[ "required" =~ ^${member_mcg,,} ]]; then
				mcg_members+=("${member}")
			fi
		done

		# check if all members available(supplied or can be fulfilled)
		for member in "${mcg_members[@]}"; do
			if [[ -v vpe_options["${member}"] ]]; then
				msg_bp -4 "      member " "'${member}@${mcg}' supplied"
				continue
			else
				extract_filter_schema "${lid}" "${filter_ref2[${member}]}" def_type def_data
				if [[ -n ${def_data} ]]; then
					msg_bp -4 "      member " "'${member}@${mcg}' fulfill with default"
					vpe_options["${member}"]="${def_data}"
					if [[ ${def_type} == 'bool' ]]; then
						vpe_bools["${member}"]="${def_data}"
					else
						vpe_strings["${member}"]="${def_data}"
					fi
				else
					pros_tag="${mcg}"
					pros_tag2="${member}"
					# pros_tag3="${mcg_members[*]}"
					exit_with_msg 70
				fi
			fi
		done
		msg_bp 3 "      - MCG ${mcg}: PASSED"
	done
}
# single-pass: build mcg -> members mapping from all PFILTER entries
function _build_mcg_membership_map() {
	local lid=$1
	local -n _pf=$2 _ms=$3
	local member def_type def_data def_mcg mcg_name
	local -a member_mcg_names

	for member in "${!_pf[@]}"; do
		extract_filter_schema "${lid}" "${_pf[${member}]}" def_type def_data def_mcg
		[[ -n ${def_mcg} ]] || continue
		escape_symbol def_mcg "${ELM_SEP}"
		local IFS="${ELM_SEP}"
		read -ra member_mcg_names <<<"${def_mcg}"
		for mcg_name in "${!member_mcg_names[@]}"; do
			escape_symbol member_mcg_names["${mcg_name}"] "${ELM_SEP}" "regress"
		done
		for mcg_name in "${member_mcg_names[@]}"; do
			_ms["${mcg_name}"]+="|${member}"
		done
	done
}

# validate dependence groups: any d-member supplied requires D-member supplied
function _validate_dependence_groups() {
	local -n _dc_supplied=$1 _dc_unsupplied=$2 _dl_supplied=$3 _dl_unsupplied=$4
	local lid=$5

	local cap_mcg d_member
	local -a d_members
	local D_groups=("${!_dc_supplied[@]}" "${!_dc_unsupplied[@]}")
	local IFS="${ELM_SEP}"

	for cap_mcg in "${D_groups[@]}"; do
		[[ -n ${_dc_supplied["${cap_mcg}"]:-} ]] &&
			msg_bp -4 "      member " "'${_dc_supplied[${cap_mcg}]}'@${cap_mcg} supplied"
		[[ -n ${_dc_unsupplied["${cap_mcg}"]:-} ]] &&
			msg_bp -4 "      member " "'${_dc_unsupplied[${cap_mcg}]}'@${cap_mcg} un-supplied"

		[[ -n ${_dl_unsupplied[${cap_mcg,}]:-} ]] && {
			read -ra d_members <<<"${_dl_unsupplied[${cap_mcg,}]#\|}"
			for d_member in "${d_members[@]}"; do
				msg_bp -4 "      member " "'${d_member}'@${cap_mcg,} un-supplied\e[0m"
			done
		}

		if [[ -n ${_dl_supplied[${cap_mcg,}]:-} ]]; then
			read -ra d_members <<<"${_dl_supplied[${cap_mcg,}]#\|}"
			for d_member in "${d_members[@]}"; do
				msg_bp -4 "      member " "'${d_member}'@${cap_mcg,} supplied"
			done
			if [[ -n ${_dc_supplied["${cap_mcg}"]:-} ]]; then
				msg_bp 3 "      - MCG ${cap_mcg,}: PASSED"
			else
				msg_bp 3 "      - MCG ${cap_mcg,}: FAILED"
				case ${lid} in
				"${PRLID}") pros_tag="Prior '${_dc_unsupplied[${cap_mcg}]}'" ;;
				"${PLID}") pros_tag="PSet '${_dc_unsupplied[${cap_mcg}]}'" ;;
				*) pros_tag="Parameter '${_dc_unsupplied[${cap_mcg}]}'" ;;
				esac
				pros_tag="${d_members[*]}"
				pros_tag2="${cap_mcg,}"
				exit_with_msg 46
			fi
		else
			msg_bp 3 "      - MCG ${cap_mcg,}: PASSED"
		fi
	done
}

# validate master groups:
#   1 if any m-member supplied, fails
#   2 if just one / none M-member supplied, pass
#   3 assign supplied M-member's name to m-member
function _validate_master_groups() {
	local -n _mc_members=$1 _mc_count=$2
	local -n _ml_supplied=$3 _ml_unsupplied=$4
	local -n _mc_supplied=$5 _mc_unsupplied=$6
	local -n _vpe_options=${7} _vpe_bools=${8} _vpe_strings=${9}

	local mcg

	for mcg in "${!_mc_members[@]}"; do
		if [[ ${#_ml_supplied["${mcg,}"]} -ne 0 ]]; then
			msg_bp -4 "      \e[2mmember " "\e[2m'${_ml_supplied[${mcg,}]#\|}'@${mcg,} supplied\e[0m"
			msg_bp 3 "      - MCG ${mcg}: FAILED"
			pros_tag="${_ml_supplied[${mcg,}]}"
			pros_tag2="${_mc_members[${mcg}]#|}"
			pros_tag3="${mcg,}"
			exit_with_msg 47
		fi

		if [[ ${_mc_count["${mcg}"]:-0} -eq 0 ]]; then
			msg_bp -4 "      \e[2mmember " "\e[2m'${_mc_members[${mcg}]#\|}'@${mcg} un-supplied\e[0m"
			[[ -v _vpe_bools["${_ml_unsupplied[${mcg,}]}"] ]] &&
				unset "_vpe_bools[${_ml_unsupplied[${mcg,}]}]" ||
				unset "_vpe_strings[${_ml_unsupplied[${mcg,}]}]"
			unset "_vpe_options[${_ml_unsupplied[${mcg,}]}]"
		else
			[[ -z ${_mc_unsupplied["${mcg}"]:-} ]] ||
				msg_bp -4 "      \e[2mmember " "\e[2m'${_mc_unsupplied[${mcg}]#\|}'@${mcg} un-supplied\e[0m"
			msg_bp -4 "      \e[2mmember " "\e[2m'${_mc_supplied[${mcg}]#\|}'@${mcg} supplied\e[0m"

			if [[ ${_mc_count["${mcg}"]} -ne 1 ]]; then
				msg_bp 3 "      - MCG ${mcg}: Failed"
				pros_tag="${_mc_supplied[${mcg}]#\|}"
				pros_tag2="${_mc_members[${mcg^}]#|}"
				exit_with_msg 45
			fi
			[[ -v _vpe_bools["${_ml_unsupplied[${mcg,}]}"] ]] &&
				unset "_vpe_bools[${_ml_unsupplied[${mcg,}]}]"
			_vpe_options["${_ml_unsupplied[${mcg,}]}"]="${_mc_supplied[${mcg}]#\|}"
			_vpe_strings["${_ml_unsupplied[${mcg,}]}"]="${_mc_supplied[${mcg}]#\|}"
		fi
		msg_bp 3 "      - MCG ${mcg}: Passed"
	done
}

# orchestrate all MCG validation: classify, then validate per-type rules
function validate_option_mcgs() {
	local lid=$1
	local -n filter_ref=$2
	local -n vpe_options=$3 vpe_bools=$4 vpe_strings=$5

	msg_bp 3 "  - check mutual-correlate groups"

	# collect and validate MCG names
	declare -A mc_groups=()
	get_all_mcg_names "${lid}" filter_ref mc_groups
	local -a mcg_list=("${!mc_groups[@]}")
	msg_bp -4 "    MCG names: " "${mcg_list[*]}"
	validate_mcg_types mcg_list
	[[ ${lid} == "${ULID}" ]] && validate_required_groups mcg_list filter_ref

	# build MCG membership map
	declare -A mcg_members_map=()
	_build_mcg_membership_map "${lid}" filter_ref mcg_members_map

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
		[[ ${mcg:0:1} == [sorR] ]] && continue

		IFS="${ELM_SEP}" read -ra mcg_members <<<"${mcg_members_map[${mcg}]#|}"
		eg_supplied=()
		ug_values=()
		ug_supplied=()

		for member in "${mcg_members[@]}"; do
			extract_filter_schema "${lid}" "${filter_ref[${member}]}" def_type def_data
			case ${mcg:0:1} in
			d)
				if [[ -v vpe_options["${member}"] ]]; then
					dl_supplied["${mcg}"]="${dl_supplied["${mcg}"]:-}|${member}"
				else
					dl_unsupplied["${mcg}"]="${dl_unsupplied["${mcg}"]:-}|${member}"
				fi
				;;
			D)
				[[ -v vpe_options["${member}"] ]] &&
					dc_supplied["${mcg}"]="${member}" ||
					dc_unsupplied["${mcg}"]="${member}"
				;;
			e)
				if [[ -v vpe_options["${member}"] ]]; then
					msg_bp -4 "      member " "'${member}'@${mcg} supplied"
					eg_supplied+=("${member}")
				else
					msg_bp -4 "      member " "'${member}'@${mcg} un-supplied, ignored\e[0m"
				fi
				;;
			m)
				ml_members["${mcg}"]="${ml_members[${mcg}]:-}|${member}"
				ml_types["${mcg}"]="${def_type}"
				ml_values["${mcg}"]="${def_data}"
				[[ -v vpe_options["${member}"] ]] &&
					ml_supplied["${mcg}"]="${member}" ||
					ml_unsupplied["${mcg}"]="${member}"
				;;
			M)
				mc_members["${mcg}"]="${mc_members[${mcg}]:-}|${member}"
				if [[ -v vpe_options["${member}"] ]]; then
					mc_supplied["${mcg}"]="${mc_supplied[${mcg}]:-}|${member}"
					((mc_count["${mcg}"] += 1))
				else
					mc_unsupplied["${mcg}"]="${mc_unsupplied[${mcg}]:-}|${member}"
				fi
				;;
			u)
				if [[ -v vpe_options["${member}"] ]]; then
					msg_bp -4 "      member " "'${member}'@${mcg} supplied"
					ug_values["${vpe_options[${member}]}"]=true
					ug_supplied+=("${member}")
				else
					[[ ${lid} == "${ULID}" ]] && {
						msg_bp -4 "      \e[2mmember " "\e[2m'${member}'@${mcg} un-supplied, ignored\e[0m"
						continue
					}
					ug_supplied+=("${member}")
					if [[ ${lid} == "${PLID}" ]]; then
						default_value="${CONFIGS[${PSETS[${member}]%%"${FLD_SEP}"*}]}"
					elif [[ ${lid} == "${PRLID}" ]]; then
						default_value="${CONFIGS[${PRIORS[${member}]%%"${FLD_SEP}"*}]}"
					fi
					msg_bp -4 "      member " "'${member}' un-supplied, default: '${default_value}'"
					ug_values["${default_value}"]=true
				fi
				;;
			*) ;;
			esac
		done

		# per-group assertions
		case ${mcg:0:1} in
		e)
			msg_bp -4 "      - supplied members: " "${eg_supplied[*]}"
			if [[ ${#eg_supplied[@]} -gt 1 ]]; then
				msg_bp 3 "      - MCG ${mcg}: FAILED"
				pros_tag="${mcg}"
				pros_tag2="${eg_supplied[*]}"
				exit_with_msg 42
			fi
			;;
		u)
			if [[ ${#ug_values[@]} -ne "${#ug_supplied[@]}" ]]; then
				msg_bp 3 "      - MCG ${mcg}: FAILED"
				pros_tag="${mcg}"
				pros_tag2="${mcg_members[*]}"
				exit_with_msg 41
			fi
			;;
		*) ;;
		esac
		[[ ${mcg:0:1} == [eu] ]] && msg_bp 3 "      - MCG ${mcg}: PASSED"
	done

	_validate_dependence_groups dc_supplied dc_unsupplied dl_supplied dl_unsupplied "${lid}"

	_validate_master_groups \
		mc_members mc_count \
		ml_supplied ml_unsupplied \
		mc_supplied mc_unsupplied \
		vpe_options vpe_bools vpe_strings

	return 0
}

# validate BP_OPTIONS(Priors/PSets/User-Options) with their definitions(PRIORS/PSETS/PFILTER)
function validate_options_by_filter() {
	local lid=$1 mandatory=${2:-true}

	declare -A v_options=() v_strings=() v_bools=()
	declare -a pm_arr=()

	local ptitle exact_param
	local param pf_type pf_data pf_mcg

	case ${lid} in
	"${ULID}") # for user parameters
		declare -n def=PFILTER
		ptitle="Parameter"
		;;
	"${PLID}") # for PSets
		declare -n def=PSETS
		ptitle="PSet"
		;;
	"${PRLID}") # for Priors
		declare -n def=PRIORS
		ptitle="Prior"
		;;
	*) ;;
	esac

	msg_bp 3 "  - validate names and args:"
	[[ ${verbose} -ge 4 ]] && printf "    \e[4;33m%-8s - %-14s | %-6s | %10s | %-10s | %s\n\e[0m" \
		"supplied" "matched" "type" "setting" "data" "mcg" >&2

	for param in "${!BP_OPTIONS[@]}"; do
		# msg_bp 4 "    $param:"
		# validate name
		exact_param="${param}"
		pm_arr=("${!def[@]}")
		validate_option_name "${lid}" exact_param pm_arr "${mandatory}"
		# load v_ arrays by types
		v_options["${exact_param}"]="${BP_OPTIONS["${param}"]}"
		[[ -v BP_STRINGS["${param}"] ]] && v_strings["${exact_param}"]="${BP_STRINGS["${param}"]}"
		[[ -v BP_BOOLS["${param}"] ]] && v_bools["${exact_param}"]="${BP_BOOLS["${param}"]}"

		# check arg
		#   - if defined in def, do arg checking;
		#   - if not defined, let it be (for non-mandatory case)
		if [[ -v def["${exact_param}"] ]]; then
			extract_filter_schema "${lid}" "${def[${exact_param}]}" pf_type pf_data pf_mcg
			validate_option_args "${lid}" "${param}" "${exact_param}" "${pf_type}" "${pf_data}" "${pf_mcg}"
		else # not defined in def, let it be
			:
		fi
	done

	# show_array v_options "-option-"
	# show_array v_bools "-BOOL-"
	# show_array v_strings "-STRING-"

	# check mcg conflict
	validate_option_mcgs "${lid}" def v_options v_bools v_strings

	# load validated params into result arrays
	reset_intermediate_arrays false
	for param in "${!v_options[@]}"; do
		BP_OPTIONS["${param}"]="${v_options[${param}]}"
	done
	for param in "${!v_strings[@]}"; do
		BP_STRINGS["${param}"]="${v_strings[${param}]}"
	done
	for param in "${!v_bools[@]}"; do
		BP_BOOLS["${param}"]="${v_bools[${param}]}"
	done
}
