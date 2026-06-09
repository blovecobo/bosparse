# shellcheck shell=bash
# shellcheck disable=SC2206
# Module 05-parse: Core parsing logic
#   extract_options()       — iterate CML tokens, classify via check_param_type()
#   bosparse_parse_supers() — detect watershed vs islands, parse supers (~~~style, ~~~zs)
#   extract_watershed()     — split CML at ZN_SEP (--) into op_zone / pp_zone
#   extract_islands()       — split CML by LID presence (options vs positionals)
#   parse_ligas()           — expand ligatures (~abc) into multiple bools
#   parse_bools()           — parse boolean params with trailing tags (+/-)
#   parse_strings()         — parse string params with OA_SEP (=)
#   parse_options()         — orchestrate liga/bool/string parsing for a LID
#   parse_positionals()     — store remaining params as positional array
#   prefix_matching()       — exact then prefix then postfix matching
# --------------------------------------------------------------------------------

# debugging helper: print all BP_OPTIONS, BP_STRINGS, BP_BOOLS to stderr
function show_all_params {
	echo "all options: " >&2
	show_array BP_OPTIONS '-OP-' 1
	show_array BP_STRINGS '-STR-' 1
	show_array BP_BOOLS '-BOOL-' 1
}

# iterate CML tokens, classify via check_param_type, sort into strings/bools/ligas
function extract_options {
	local lid=$1
	local -n strings_ref=$2 bools_ref=$3 ligas_ref=$4 # for passing back PSets
	local -n CML=$5

	msg_bp -2 "  extract ${lid} " "options"

	local curr_param next_param
	local extracted_param param_type arg_consumed=false
	local i

	for i in "${!CML[@]}"; do

		# process supers & priors
		if [[ ${lid} == "${PRLID}" || ${lid} == "${SLID}" ]]; then
			# filter out non-prior params
			with_lid "${CML[i]}" "${lid}" || continue
			# skip solitary PRLID (e.g. standalone '~~' zone separator colliding with PRLID)
			[[ ${#CML[i]} -gt ${#lid} ]] || continue
			# extract and validate param name (strip LID, OA_SEP+val, trailing bool tag)
			local _pname="${CML[i]#"${lid}"}"
			_pname="${_pname%%"${OA_SEP}"*}"               # strip OA_SEP and val
			_pname="${_pname%["${TAG_TRUE}${TAG_FALSE}"]}" # strip trailing bool tag


			local _ptype
			if [[ ${lid} == "${PRLID}" ]]; then
				_ptype="Prior"
			else
				_ptype="Super"
			fi
			msg_bp 2 "  found ${_ptype} token: ${CML[i]} -> name: ${_pname}"
			validate_variable_name "${_ptype} name" _pname
			if [[ ${CML[i]} == *${OA_SEP}* ]]; then
				strings_ref+=("${CML[i]}")
			else
				bools_ref+=("${CML[i]}")
			fi
			continue
		fi

		# skip if param is the ARG of last param
		if [[ "${arg_consumed}" == true ]]; then
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
		0) # a solitary arg found, parsing failed
			pros_tag[0]="${curr_param}"
			exit_with_msg 21
			;;
		*) exit_with_msg 3 "unexpected param_type '${param_type}' from check_param_type." ;;
		esac
	done
	return 0
}

# # extract islands style cml
function extract_islands {
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
function extract_watershed {
	local -n op_zone_ref=$1 pp_zone_ref=$2

	# msg_bp 2 "Extract Watershed"

	shift 2
	local param zsep_count zn_sep_pos

	# count ZN_SEP and record its position
	zsep_count=0
	zn_sep_pos=-1
	for param in "$@"; do
		if [[ ${param} == "${ZN_SEP}" ]]; then
			((zsep_count += 1))
		fi
	done

	op_zone_ref=()
	pp_zone_ref=()

	if [[ ${zsep_count} -gt 1 ]]; then
		# duplicate ZONE_SEPs
		pros_tag[0]="${CONFIGS[${SUPERS["zs"]%%${FLD_SEP}*}]}"
		pros_tag[1]="${zsep_count}"
		exit_with_msg 20
	elif [[ ${zsep_count} -eq 1 ]]; then
		# locate the ZN_SEP position (1-based indirection)
		local i
		for ((i = 1; i <= $#; i++)); do
			if [[ ${!i} == "${ZN_SEP}" ]]; then
				zn_sep_pos=${i}
				break
			fi
		done
		if [[ ${zn_sep_pos} -eq 1 ]]; then
			# PP_ZONE only with leading zone-sep
			for ((i = 2; i <= $#; i++)); do
				pp_zone_ref+=("${!i}")
			done
		elif [[ ${zn_sep_pos} -eq $# ]]; then
			# OP_ZONE only with trailing zone-sep
			for ((i = 1; i < $#; i++)); do
				op_zone_ref+=("${!i}")
			done
		else
			# normal case: split at ZN_SEP
			for ((i = 1; i < zn_sep_pos; i++)); do
				op_zone_ref+=("${!i}")
			done
			for ((i = zn_sep_pos + 1; i <= $#; i++)); do
				pp_zone_ref+=("${!i}")
			done
		fi
	else
		# no ZONE_SEP: one zone only, guess by LID of first param
		if [[ $# -gt 0 ]]; then
			if with_lid "${1}"; then
				op_zone_ref=("$@")
			else
				pp_zone_ref=("$@")
			fi
		fi
	fi
}

# split liga into bools, parse values, load into result array
# used for ligas for Pirors/PSets/U-Options
# only shell variable validating applied on param names.
function parse_ligas {
	local lid=$1
	local -n ligas_ref2=$2

	local liga liga_name b_name b_nlen b_tag start

	msg_bp -3 "  parse ${lid} " "ligas"

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
			pros_tag[0]="${lid}${liga}"
			pros_tag[1]="${liga_name}"
			pros_tag[2]="${b_nlen}"
			exit_with_msg 25
		fi

		for ((start = 0; start < ${#liga_name}; start += b_nlen)); do
			b_name="${liga_name:${start}:${b_nlen}}"
			if ! validate_variable_name "bool-name in LIGA" b_name true; then
				pros_tag[0]="${b_name}"
				pros_tag[1]="${lid}${liga}"
				exit_with_msg 24
			fi
			BP_BOOLS["${b_name}"]="${b_tag}"
			BP_OPTIONS["${b_name}"]="${b_tag}"
		done
	done
}

# parse boolean parameter with trailing-tag; load into result array
# check if a valid shell variable
function parse_bools {
	local lid=$1
	local -n bs_ref=$2

	local bl b_name b_tag

	msg_bp -3 "  parse ${lid} " "bools"

	for bl in "${bs_ref[@]}"; do
		b_name=${bl#"${lid}"}                        # remove lid
		b_tag=$(parse_bool_tag "${b_name}")          # parse tag
		b_name=${b_name%["${TAG_TRUE}${TAG_FALSE}"]} # remove tag

		msg_bp -4 "    bool: " "${bl} | ${b_tag}"
		validate_variable_name "bool param name" b_name

		BP_BOOLS["${b_name}"]="${b_tag}"
		BP_OPTIONS["${b_name}"]="${b_tag}"
	done
}

# parse string parameter and load result into array
# validate if the param name is a valid shell variable(with exception subsititution)
function parse_strings {
	local lid=$1
	local -n str_ref=$2

	local str str_name val

	msg_bp -3 "  parse ${lid} " "strings"

	for str in "${str_ref[@]}"; do
		str_name=${str#"${lid}"}             # remove lid
		str_name=${str_name%%"${OA_SEP}"*}   # remove OA_SEP and value
		val="${str#*"${str_name}${OA_SEP}"}" # extract value(in case value contains OA_SEP)

		msg_bp -4 "    string: " "${str%%=*} | ${val:--}"
		# validate param str_name
		validate_variable_name "string param name" str_name

		BP_STRINGS["${str_name}"]="${val}"
		BP_OPTIONS["${str_name}"]="${val}"
	done
}

# parse Options with all types of params, and load results into arrays
function parse_options {
	local lid=$1
	local -n strings_ref=$2 bools_ref=$3 ligas_ref=$4

	# no liga for priors and psets, so only parse bools and strings
	[[ ${lid} == "${ULID}" ]] && parse_ligas "${lid}${lid}" ligas_ref
	parse_bools "${lid}" bools_ref
	parse_strings "${lid}" strings_ref
}

# parse positionals, which are all params in PP_ZONE, and load results into array
function parse_positionals {
	BP_POSITIONALS=("$@")
	local i
	msg_bp 3 "  positionals parsed: "
	for i in "${!BP_POSITIONALS[@]}"; do
		msg_bp -3 "   $(printf '%3s | ' "${i}")" "\"$(printf '%s\n' "${BP_POSITIONALS[i]}")\""
	done
}

# validate:
#   test exactly match an array member
#   if not, try prefix-matching/postfix-matching(depends on $3)
# return code and output:
#   0 - one matched:      expactly/prefixly/postfixly matched
#	1 - non-matched:      ""
#   2 - multiple matched: matching names
# note:
#   this script assumes that no duplicated members in matching-list
function prefix_matching {
	local needle=$1
	local -n haystack=$2
	local match_method=${3:-prefix}

	local pk needle_regex
	local re_char

	declare -a matched=()

	# build regex-safe pattern from needle
	needle_regex="${needle}"
	# escape regex metacharacters (backslash first to avoid double-escaping)
	for re_char in "${REGEX_METACHARS[@]}"; do
		needle_regex="${needle_regex//"${re_char}"/\\"${re_char}"}"
	done

	# try exactly match (plain string comparison, no regex)
	if is_array_member "${needle}" haystack; then
		echo "${needle}"
		return 0
	fi

	# try prefix/postfix matching
	for pk in "${haystack[@]}"; do
		if [[ "prefix" == "${match_method}" ]]; then
			# prefix matching
			[[ ${pk} =~ ^${needle_regex} ]] && matched+=("${pk}")
		elif [[ "postfix" =~ ^${match_method} ]]; then
			# postfix-matching
			[[ ${pk} =~ ${needle_regex}$ ]] && matched+=("${pk}")
		else
			pros_tag[0]="Wrong options '${match_method}' when calling 'prefix-matching()', 'prefix(default)|postfix' available."
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
