# shellcheck shell=bash
# shellcheck disable=SC2206
# Module 05-parse: Core parsing logic
#   bp_extract_options()    — iterate CML tokens, classify via bp_check_param_type()
#   bp_extract_watershed()   — split CML at ZN_SEP (--) into op_zone / pp_zone
#   bp_extract_islands()     — split CML by LID presence (options vs positionals)
#   bp_parse_bool_tag()     — extract trailing true/false tag from parameter name
#   bp_parse_ligas()        — expand ligatures (~abc) into multiple bools
#   bp_parse_bools()        — parse boolean params with trailing tags (+/-)
#   bp_parse_strings()      — parse string params with OA_SEP (=)
#   bp_parse_options()      — orchestrate liga/bool/string parsing for a LID
#   bp_prefix_matching()    — exact then prefix then postfix matching
# --------------------------------------------------------------------------------

# extract harnesses from CML(for Globals) or OP-ZONE(for Priors & Specs)
_bp_extract_options_harnesses() {
	local lid_eoh=$1
	local -n oz_eoh=$2 strs_eoh=$3 bls_eoh=$4 opts_eoh=$5

	if [[ ${lid_eoh} == "${CONFIGS[glid]}" ]] ||
		[[ ${lid_eoh} == "${CONFIGS[slid]}" ]] ||
		[[ ${lid_eoh} == "${CONFIGS[plid]}" ]]; then
		local i
		for i in "${!oz_eoh[@]}"; do
			bp_with_lid "${oz_eoh[i]}" "${lid_eoh}" || continue
			# skip solitary LIDS (e.g. standalone '~~' zone separator colliding with PLID)
			[[ ${#oz_eoh[i]} -gt ${#lid_eoh} ]] || continue

			# bp_msg -3 "    " "- token: ${oz_eoh[i]}"
			opts_eoh+=("${oz_eoh[i]}")

			if [[ ${oz_eoh[i]#"${lid_eoh}"} == *${CONFIGS[os]}* ]]; then
				strs_eoh+=("${oz_eoh[i]}")
				bp_msg -3 "    " "- string token:  ${oz_eoh[i]}"
			else
				bls_eoh+=("${oz_eoh[i]}")
				bp_msg -3 "    " "- boolean token: ${oz_eoh[i]}"
			fi
		done
		return 0
	else
		return 1
	fi
}

# iterate CML tokens, classify each via bp_check_param_type, sort into buckets
# $1 — lid to match against
# $2 — nameref: option-zone array (tokens to classify)
# $3 — nameref: receives string-type tokens
# $4 — nameref: receives bool-type tokens
# $5 — nameref: receives liga-type tokens
# $6 — nameref: receives all extracted tokens (union of 3-5)
# for glid/plid levels: filters by lid, splits by OA_SEP into strings/bools
# for other levels: delegates to bp_check_param_type, handles arg_consumed flag
# exits 21 on solitary arg (no lid match) for non-global/prior levels
bp_extract_options() {
	local lid=$1
	local -n oz_eo=$2
	local -n strings_eo=$3 bools_eo=$4 ligas_eo=$5 # classified extracted options
	local -n options_eo=$6                         # all extracted options

	bp_msg -2 "  Extract Options '${lid}': " "${oz_eo[*]}"

	# process globals & priors; specs?
	_bp_extract_options_harnesses "${lid}" oz_eo strings_eo bools_eo options_eo && return 0

	# process user-params
	local i arg_consumed=false
	for i in "${!oz_eo[@]}"; do

		# if [[ ${lid} == "${CONFIGS[glid]}" || ${lid} == "${CONFIGS[plid]}" ]]; then
		# 	# filter out params not match current lid
		# 	bp_with_lid "${oz_eo[i]}" "${lid}" || continue
		# 	# skip solitary LIDS (e.g. standalone '~~' zone separator colliding with PLID)
		# 	[[ ${#oz_eo[i]} -gt ${#lid} ]] || continue
		#
		# 	bp_msg -3 "    " "- token: ${oz_eo[i]}"
		# 	options_eo+=("${oz_eo[i]}")
		# 	[[ ${oz_eo[i]} =~ ${CONFIGS[os]} ]] &&
		# 		strings_eo+=("${oz_eo[i]}") ||
		# 		bools_eo+=("${oz_eo[i]}")
		# 	continue
		# fi

		local curr_param next_param
		local extracted_param="" param_type

		# skip if param is the ARG of last param
		if [[ "${arg_consumed}" == true ]]; then
			arg_consumed=false
			continue
		fi

		curr_param="${oz_eo[i]}"
		next_param="${oz_eo[$((i + 1))]:-}" || next_param=""

		bp_msg -3 "    current/next: " "${curr_param}  ${next_param:--}"

		# parse options
		param_type=0
		bp_check_param_type "${lid}" "${curr_param}" "${next_param}" extracted_param || param_type=$?
		bp_msg -3 "    " "- type: ${param_type} | found: ${extracted_param}"
		case "${param_type}" in
		1) ligas_eo+=("${extracted_param}") ;;
		2) bools_eo+=("${extracted_param}") ;;
		3)
			bools_eo+=("${extracted_param}")
			arg_consumed=true
			;;
		4) strings_eo+=("${extracted_param}") ;;
		5)
			strings_eo+=("${extracted_param}")
			arg_consumed=true
			;;
		6) continue ;; # matching other lid with built-in arg, skip
		7)             # matching other lid followd by an arg, skip with a consumption signal
			arg_consumed=true
			continue
			;;
		0) # a solitary arg found, parsing failed
			local pros_tag[0]="${curr_param}"
			bp_exit_with_msg 21 pros_tag
			;;
		*)
			local pros_tag="unexpected param_type '${param_type}' from bp_check_param_type."
			bp_exit_with_msg 4 pros_tag
			;;
		esac
		options_eo+=("${extracted_param}")
		bp_msg -3 "      extracted: ${extracted_param}"
	done
	return 0
}

# split CML into option-zone and positional-zone by LID presence (islands style)
# $1 — nameref: receives option-zone tokens (params with any LID)
# $2 — nameref: receives positional-zone tokens (params without LID)
# remaining args are the CML tokens to classify
# ZN_SEP tokens are skipped entirely
bp_extract_zones_islands() {
	local -n op_zone_ei=$1 pp_zone_ei=$2

	shift 2

	# extract params
	local param
	for param in "$@"; do
		[[ ${param} == "${CONFIGS[zs]}" ]] && continue
		if bp_with_lid "${param}"; then
			bp_msg -4 "    " "- option token:   ${param}"
			op_zone_ei+=("${param}")
		else
			bp_msg -4 "    " "- position token: ${param}"
			pp_zone_ei+=("${param}")
		fi
	done
}

# split CML at ZN_SEP (zone separator, default "--") into option-zone and positional-zone
# $1 — nameref: receives option-zone tokens (before ZN_SEP)
# $2 — nameref: receives positional-zone tokens (after ZN_SEP)
# remaining args are the CML tokens to split
# if no ZN_SEP: guesses zone by checking if first token has a LID
# if ZN_SEP at position 1: all tokens go to positional-zone
# if ZN_SEP at last position: all tokens go to option-zone
# exits 20 if more than one ZN_SEP found
bp_extract_zones_watershed() {
	local -n op_zone_ew=$1 pp_zone_ew=$2

	# bp_msg 2 "Extract Watershed"

	shift 2
	local param zsep_count zn_sep_pos

	bp_msg -4 "    CML: " "$*"

	# count ZN_SEP and record its position
	zsep_count=0
	zn_sep_pos=-1
	for param in "$@"; do
		if [[ ${param} == "${CONFIGS[zs]}" ]]; then
			((zsep_count += 1))
		fi
	done

	op_zone_ew=()
	pp_zone_ew=()

	if [[ ${zsep_count} -gt 1 ]]; then
		# duplicate ZONE_SEPs
		local pros_tag[0]="${CONFIGS["zs"]}"
		pros_tag[1]="${zsep_count}"
		bp_exit_with_msg 20 pros_tag
	elif [[ ${zsep_count} -eq 1 ]]; then
		# locate the ZN_SEP position (1-based indirection)
		local i
		for ((i = 1; i <= $#; i++)); do
			if [[ ${!i} == "${CONFIGS[zs]}" ]]; then
				zn_sep_pos=${i}
				break
			fi
		done
		if [[ ${zn_sep_pos} -eq 1 ]]; then
			# PP_ZONE only with leading zone-sep
			for ((i = 2; i <= $#; i++)); do
				pp_zone_ew+=("${!i}")
			done
		elif [[ ${zn_sep_pos} -eq $# ]]; then
			# OP_ZONE only with trailing zone-sep
			for ((i = 1; i < $#; i++)); do
				op_zone_ew+=("${!i}")
			done
		else
			# normal case: split at ZN_SEP
			for ((i = 1; i < zn_sep_pos; i++)); do
				op_zone_ew+=("${!i}")
			done
			for ((i = zn_sep_pos + 1; i <= $#; i++)); do
				pp_zone_ew+=("${!i}")
			done
		fi
	else
		# no ZONE_SEP: one zone only, guess by LID of first param
		if [[ $# -gt 0 ]]; then
			if bp_with_lid "${1}"; then
				op_zone_ew=("$@")
			else
				pp_zone_ew=("$@")
			fi
		fi
	fi
}

# extract trailing true/false tag character from parameter name
bp_parse_bool_tag() {
	local param=$1

	local tag=${param: -1}
	case "${tag}" in
	"${TAGS[tt]}") echo true ;;
	"${TAGS[tf]}") echo false ;;
	*) echo "${TAGS[td]}" ;;
	esac
}

# expand a ligature string into multiple bool parameters
# ligature format: <lid><lid><n><name> where n is char-length of each param name
#   e.g. --abc with n=1 → -a=true -b=true -c=true
#   e.g. --2abcd with n=2 → -ab=true -cd=true
# $1 — lid (used as lid+lid for uliga prefix)
# $2 — nameref: array of ligature tokens
# $3 — nameref: receives expanded {name: tag} pairs
# validates name length is multiple of n; validates each name as shell variable
# exits 24 (invalid name) or 25 (length mismatch)
bp_parse_ligas() {
	local lid=$1
	local -n params=$2 options_pl=$3

	local liga liga_name btag bname b_nlen start

	for liga in "${params[@]}"; do
		bp_with_lid "${liga}" "${lid}" || continue
		liga=${liga#"${lid}"}                   # strip lid
		btag=$(bp_parse_bool_tag "${liga}")     # parse tag
		liga=${liga%["${TAGS[tt]}${TAGS[tf]}"]} # strip trailing-tag
		b_nlen=${liga%%[^[:digit:]]*}           # strip param length
		[[ -n ${b_nlen} ]] || b_nlen=1          # default param length
		liga_name=${liga#"${b_nlen}"}           # param name
		if ((${#liga_name} % b_nlen)); then
			local pros_tag[0]="${lid}${liga}"
			pros_tag[1]="${liga_name}"
			pros_tag[2]="${b_nlen}"
			bp_exit_with_msg 25 pros_tag
		fi
		for ((start = 0; start < ${#liga_name}; start += b_nlen)); do
			bname="${liga_name:start:b_nlen}"
			bp_substitute_exceptions bname
			if ! bp_validate_variable_name "bool-name in LIGA" bname true; then
				local pros_tag[0]="${bname}"
				pros_tag[1]="${lid}${liga}"
				bp_exit_with_msg 24 pros_tag
			fi
			options_pl["${bname}"]="${btag}"
		done
		bp_msg -4 "    " "- liga ${liga} == '${btag}'"
	done
}

# parse boolean parameters (with trailing +/- tag) into an associative array
# $1 — lid to strip from each param
# $2 — nameref: array of bool tokens (e.g. "flag+" / "flag-")
# $3 — nameref: receives {name: tag} pairs (tag is "true" or "false")
# strips lid and trailing tag; substitutes exceptions; validates variable name
bp_parse_bools() {
	local lid=$1
	local -n params=$2
	local -n options_pb=$3

	local bl bname btag
	for bl in "${params[@]}"; do
		bname=${bl#"${lid}"} # strip lid
		btag=$(bp_parse_bool_tag "${bname}")
		bname=${bname%["${TAGS[tt]}${TAGS[tf]}"]}
		bp_substitute_exceptions bname
		bp_validate_variable_name "bool param name" bname
		options_pb["${bname}"]="${btag}"
		bp_msg -4 "    " "- bool ${bname} = '${btag}'"
	done
}

# parse string parameters (with OA_SEP) into an associative array
# $1 — lid to strip from each param
# $2 — nameref: array of string tokens (e.g. "name=value")
# $3 — nameref: receives {name: value} pairs
# strips lid and OA_SEP; substitutes exceptions; validates variable name
bp_parse_strings() {
	local lid=$1
	local -n params=$2 options_ps=$3

	local str sname arg
	for str in "${params[@]}"; do
		sname=${str#"${lid}"}             # strip lid
		sname=${sname%%"${CONFIGS[os]}"*} # extract name
		arg="${str#"${lid}${sname}"}"     # strip <lid><name>
		arg="${arg#"${CONFIGS[os]}"}"     # extract arg
		bp_substitute_exceptions sname
		bp_validate_variable_name "string param name" sname
		options_ps["${sname}"]="${arg}"
		bp_msg -4 "    " "- string  ${sname} = '${arg}'"
	done
	return 0
}

# orchestrate parsing of liga/bool/string tokens into a single options array
# $1 — lid context (only ulid gets liga expansion)
# $2 — nameref: string tokens
# $3 — nameref: bool tokens
# $4 — nameref: liga tokens
# $5 — nameref: receives all parsed {name: value} pairs
# order: ligas first, then bools, then strings (last writer wins for dupes)
bp_parse_options() {
	local lid=$1
	local -n strings_po=$2 bools_po=$3 ligas_po=$4
	local -n options_po=$5

	bp_msg -3 "  Parse options '${lid}': " "${strings_po[*]:--} | ${bools_po[*]:--} | ${ligas_eo[*]:--}"
	# only user-params support ligas
	[[ ${lid} == "${CONFIGS[ulid]}" ]] &&
		bp_parse_ligas "${lid}${lid}" ligas_po options_po

	bp_parse_bools "${lid}" bools_po options_po
	bp_parse_strings "${lid}" strings_po options_po
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
# relies global:
#   - REGEX_METACHARS
# params:
#   $1: the parameter name being checked
#   $2: list of parameters to match against (array nameref)
#   $3: type of matching ('exact', 'prefix', or 'postfix')
bp_prefix_matching() {
	local needle=$1
	local -n haystack=$2
	local match_method=${3:-prefix}

	local pk needle_regex
	local re_char

	declare -a matched=()

	((${#haystack[@]} > 0)) || return 1
	[[ -n ${needle} ]] || return 1

	# build regex-safe pattern from needle
	needle_regex="${needle}"
	# escape regex metacharacters (backslash first to avoid double-escaping)
	for re_char in "${REGEX_METACHARS[@]}"; do
		needle_regex="${needle_regex//"${re_char}"/\\"${re_char}"}"
	done

	# try exactly match (plain string comparison, no regex)
	if bp_is_array_member "${needle}" haystack; then
		echo "${needle}"
		return 0
	elif [[ "exactly" =~ ^${match_method} ]]; then
		return 1
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
			bp_exit_with_msg 4
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
