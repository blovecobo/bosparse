# Parsing tasks -------------------------------------------------------------------

function show_all_params() {
	echo "all options: " >&2
	show_array BP_OPTIONS '-OP-' 1
	show_array BP_STRINGS '-STR-' 1
	show_array BP_BOOLS '-BOOL-' 1
}
function extract_options() {
	local lid=$1
	local -n strings_ref=$2 bools_ref=$3 ligas_ref=$4 # for passing back PSets
	local -n CML=$5

	msg_bp 2 "  extract ${lid}options"

	local curr_param next_param
	local extracted_param param_type arg_consumed=false
	local i

	for i in "${!CML[@]}"; do

		# process priors
		if [[ ${lid} == "${PRLID}" ]]; then
			# filter out non-prior params
			with_lid "${CML[i]}" "${PRLID}" || continue
			if [[ ${CML[i]} == *${OA_SEP}* ]]; then
				strings_ref+=("${CML[i]}")
			else
				bools_ref+=("${CML[i]}")
			fi
			continue
		fi

		if [[ "${arg_consumed}" == true ]]; then
			# param is the ARG of last param, skip
			arg_consumed=false
			continue
		fi

		curr_param="${CML[i]}"
		next_param="${CML[$((i + 1))]:-}" || next_param=""

		# parse options
		param_type=0
		check_param_type "${lid}" "${curr_param}" "${next_param}" extracted_param || param_type=$?
		msg_bp 4 "  type: ${param_type} | extracted: ${extracted_param}"
		case "${param_type}" in
		1) ligas_ref+=("${extracted_param}") ;;
		2) bools_ref+=("${extracted_param}") ;;
		3)
			bools_ref+=("${extracted_param}")
			arg_consumed=true
			;;
		4) strings_ref+=("${extracted_param}") ;;
		5)
			strings_ref+=("${extracted_param}")
			arg_consumed=true
			;;
		6) ;; # matching other lid with built-in arg, skip
		7)    # matching other lid followd by an arg, skip with a consumption signal
			arg_consumed=true
			;;
		*) # a solitary arg found, parsing failed
			pros_tag="${curr_param}"
			exit_with_msg 21
			;;
		esac
	done
	return 0
}

# check command line style
function update_cml_style() {
	local CML_arr=("$@")
	local param pset_list param_name matched stl super_list

	local available_style=(
		${CONSTS[CML_STYLE]%|*}
		${CONSTS[CML_STYLE]#*|}
	)

	super_list=("${!SUPERS[@]}")

	msg_bp 2 "Test CML style"
	for param in "${CML_arr[@]}"; do
		with_lid "${SLID}" || continue
		param_name="${param%%=*}"
		param_name=${param_name##"${SLID}"}
		if matched=$(prefix_matching "${param_name}" super_list); then
			if [[ ${matched} == "style" ]]; then
				# ~~~style= found, validate
				# test EML
				if [[ ${param} == *"${OA_SEP}"* ]]; then
					# OA-SEP found, match style
					for stl in "${available_style[@]}"; do
						# matching available style
						if [[ ${stl} =~ ^${param#*=} ]]; then
							# matching, update CONFIGS
							msg_bp 2 "CML style: ${stl}"
							CML_STYLE="${stl}"
							return 0
						fi
					done
					# unknown style
					pros_tag="Prior setting"
					pros_tag2="${param}"
					pros_tag3="CML style should be one of '${CONSTS[CML_STYLE]}'"
					exit_with_msg 27
				else
					# no 'OA-SEP', EML
					CML_STYLE="${CONSTS[CML_STYLE]##*|}"
					return 0
				fi
			fi
		fi
	done

}
# extract islands style cml
function extract_islands() {
	local -n op_zone_ref=$1 pp_zone_ref=$2

	shift 2
	local -a CML=("$@")

	# extract params
	local param
	for param in "${CML[@]}"; do
		[[ ${param} == "${ZN_SEP}" ]] && continue
		if with_lid "${param}"; then
			op_zone_ref+=("${param}")
		else
			pp_zone_ref+=("${param}")
		fi
	done
}
# extract watershed style cml
function extract_watershed() {
	local -n op_zone_ref=$1 pp_zone_ref=$2

	# msg_bp 2 "Extract Watershed"

	shift 2
	local EZ_CML="$*" param zsep_count

	# count ZN_SEP
	zsep_count=0
	for param in "$@"; do
		[[ ${param} != "${ZN_SEP}" ]] || ((zsep_count += 1))
	done

	op_zone_ref=()
	pp_zone_ref=()

	if [[ ${zsep_count} -gt 1 ]]; then
		# duplicate ZONE_SEPs
		pros_tag="${CONFIGS[${PRIORS["zs"]%%:*}]}"
		pros_tag2="${zsep_count}"
		exit_with_msg 20
	elif [[ "${EZ_CML}" == *[[:space:]]${ZN_SEP} ]]; then
		# OP_ZONE only with trailing ZN_SEP
		op_zone_ref=("$@")
		# remove last param which is ZN_SEP
		unset "op_zone_ref[$(($# - 1))]"
		return 0
	elif [[ ${EZ_CML} == ${ZN_SEP}[[:space:]]* ]]; then
		# PP_ZONE only with leading zone-sep
		pp_zone_ref=("$@")
		unset "pp_zone_ref[0]"            # remove first param which is ZN_SEP
		pp_zone_ref=("${pp_zone_ref[@]}") # re-index array after unset
		return 0
	elif [[ ${EZ_CML} == *[[:space:]]${ZN_SEP}[[:space:]]* ]]; then
		# two zones separated by a a ZONE_SEP
		local seen_zsep=false
		for param in "$@"; do
			if [[ ${seen_zsep} == false ]]; then
				if [[ ${param} == "${ZN_SEP}" ]]; then
					seen_zsep=true
				else
					op_zone_ref+=("${param}")
				fi
			else
				pp_zone_ref+=("${param}")
			fi
		done
	else
		# no ZONE_SEP: route params by LID
		for param in "$@"; do
			if with_lid "${param}"; then
				op_zone_ref+=("${param}")
			else
				pp_zone_ref+=("${param}")
			fi
		done
	fi
}

# split liga into bools, parse values, load into result array
# used for ligas for Pirors/PSets/U-Options
# only shell variable validating applied on param names.
function parse_ligas() {
	local lid=$1
	local -n ligas_ref2=$2

	local liga liga_name b_name b_nlen b_tag start

	msg_bp 3 "  parse ${lid}ligas"

	for liga in "${ligas_ref2[@]}"; do
		# filter out non-liga params
		with_lid "${liga}" "${lid}" || continue

		liga=${liga#"${lid}"}                    # remove lid
		b_tag=$(parse_bool_tag "${liga}")        # parse tag
		liga=${liga%["${TAG_TRUE}${TAG_FALSE}"]} # remove tag
		b_nlen=${liga%%[^[:digit:]]*}            # extract name length
		[[ -n "${b_nlen}" ]] || b_nlen=1         # default name length 1
		liga_name=${liga#"${b_nlen}"}            # remove length-integer

		msg_bp -4 "    liga: " "${liga} ${b_tag}"

		# check parameter name length in liga
		if ((${#liga_name} % b_nlen)); then
			pros_tag="${lid}${liga}"
			pros_tag2="${liga_name}"
			pros_tag3="${b_nlen}"
			exit_with_msg 25
		fi

		for ((start = 0; start < ${#liga_name}; start += b_nlen)); do
			b_name="${liga_name:${start}:${b_nlen}}"
			if ! validate_variable_name b_name true; then
				pros_tag="${b_name}"
				pros_tag2="${lid}${liga}"
				exit_with_msg 24
			fi
			BP_BOOLS["${b_name}"]="${b_tag}"
			BP_OPTIONS["${b_name}"]="${b_tag}"
		done
	done
}

# parse boolean parameter with trailing-tag; load into result array
# check if a valid shell variable
function parse_bools() {
	local lid=$1
	local -n bs_ref=$2

	local bl b_name b_tag

	msg_bp 3 "  parse ${lid}bools"

	for bl in "${bs_ref[@]}"; do
		b_name=${bl#"${lid}"}                        # remove lid
		b_tag=$(parse_bool_tag "${b_name}")          # parse tag
		b_name=${b_name%["${TAG_TRUE}${TAG_FALSE}"]} # remove tag

		msg_bp -4 "    bool: " "${bl} | ${b_tag}"
		validate_variable_name b_name

		BP_BOOLS["${b_name}"]="${b_tag}"
		BP_OPTIONS["${b_name}"]="${b_tag}"
	done
}

# parse string parameter and load result into array
# validate if the param name is a valid shell variable(with exception subsititution)
function parse_strings() {
	local lid=$1
	local -n str_ref=$2

	local str s_name val

	msg_bp 3 "  parse ${lid}strings"

	for str in "${str_ref[@]}"; do
		s_name=${str#"${lid}"}             # remove lid
		s_name=${s_name%%"${OA_SEP}"*}     # remove OA_SEP and value
		val="${str#*"${s_name}${OA_SEP}"}" # extract value(in case value contains OA_SEP)

		msg_bp -4 "    string: " "${str%%=*} | ${val:--}"
		# validate param s_name
		validate_variable_name s_name

		BP_STRINGS["${s_name}"]="${val}"
		BP_OPTIONS["${s_name}"]="${val}"
	done
}

# parse Options with all types of params, and load results into arrays
function parse_options() {
	local lid=$1
	local -n strings_ref=$2 bools_ref=$3 ligas_ref=$4

	# no liga for priors
	[[ ${lid} == "${PRLID}" ]] || parse_ligas "${lid}${lid}" ligas_ref
	parse_bools "${lid}" bools_ref
	parse_strings "${lid}" strings_ref
}

# parse positionals, which are all params in PP_ZONE, and load results into array
function parse_positionals() {
	BP_POSITIONALS=("$@")
	local i
	msg_bp 3 "  positionals parsed: "
	for i in "${!BP_POSITIONALS[@]}"; do
		msg_bp -3 "   $(printf '%3s | ' "${i}")" "\"$(printf '%s\n' "${BP_POSITIONALS[i]}")\""
	done
}

# validate:
#   test exactly match an array member
#   if not, try prefix-matching/postfix-matching(depends on $4)
# output:
#	non-matched:      ""
#   one matched:      expactly/prefixly matched
#   multiple matched: matching names
# note:
#   this script assumes that no duplicated members in matching-list
function prefix_matching() {
	# local lid=$1
	local candidate=$1
	local -n matching_list=$2
	local prefix=${3:-prefix}

	local pk candidate_escaped

	declare -a matched=()

	# in case candidate needs escape(\)
	candidate_escaped="$(printf '%q' "${candidate}")"
	# FLD_SEP must be escaped, candidate may contain FLD_SEP, which will cause regex matching failure
	candidate_escaped="${candidate_escaped//"${FLD_SEP}"/\\"${FLD_SEP}"}"

	# try exactly match
	if is_array_member "${candidate_escaped}" matching_list; then
		echo "${candidate}"
		return 0
	fi

	# try prefix/postfix matching
	for pk in "${matching_list[@]}"; do
		if [[ ${prefix} == "prefix" ]]; then
			# prefix matching
			[[ ${pk} =~ ^${candidate_escaped} ]] && matched+=("${pk}")
		elif [[ "postfix" =~ ^${prefix} ]]; then
			# postfix-matching
			[[ ${pk} =~ ${candidate_escaped}$ ]] && matched+=("${pk}")
		else
			pros_tag="Wrong options '${prefix}' when calling 'prefix-matching()', 'prefix(default)|postfix' available."
			exit_with_msg 3
		fi
	done

	if [[ "${#matched[@]}" -eq 1 ]]; then
		# one prefix-matched
		echo "${matched[0]}"
		return 0
	elif [[ ${#matched[@]} -eq 0 ]]; then
		# none  matched
		return 1
	else
		# multiple matched
		echo "${matched[*]}"
		return 2
	fi
}
