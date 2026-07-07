# shellcheck shell=bash
# shellcheck disable=SC2206
# Module 05-parse: Core parsing logic
#   bp_extract_harness_tokens() - iterate harnesses from CML
#   bp_check_param_type()       - classify a CML token (bool/string/liga/value) by context
#   bp_extract_options()        - iterate CML tokens, classify via bp_check_param_type()
#   bp_extract_parameters_watershed()   - split CML at ZN_SEP (--) into op_zone / pp_zone
#   bp_extract_parameters_islands()     - split CML by LID presence (options vs positionals)
#   bp_parse_bool_tag()     - extract trailing true/false tag from parameter name
#   bp_parse_ligas()        - expand ligatures (~abc) into multiple bools
#   bp_parse_bools()        - parse boolean params with trailing tags (+/-)
#   bp_parse_strings()      - parse string params with OV_SEP (=)
#   bp_parse_options()      - orchestrate liga/bool/string parsing for a LID
#   bp_prefix_matching()    - exact then prefix then postfix matching
# --------------------------------------------------------------------------------

# extract harnesses from CML(for Globals) or OP-ZONE(for Priors & Specs)
bp_extract_harness_tokens() {
	local lid=$1
	local -n tokens=$2 _strs=$3 _bls=$4 _opts=$5

	if [[ ${lid} == "${CONFIGS[glid]}" ]] ||
		[[ ${lid} == "${CONFIGS[slid]}" ]] ||
		[[ ${lid} == "${CONFIGS[plid]}" ]]; then
		local i
		for i in "${!tokens[@]}"; do
			bp_with_lid "${tokens[i]}" "${lid}" || continue
			# skip solitary LIDS (e.g. standalone '~~' zone separator colliding with PLID)
			[[ ${#tokens[i]} -gt ${#lid} ]] || continue

			bp_msg -2 "    " "- token: ${tokens[i]%%"${CONFIGS[os]}"*}"
			_opts+=("${tokens[i]}")

			if [[ ${tokens[i]#"${lid}"} == *${CONFIGS[os]}* ]]; then
				_strs+=("${tokens[i]}")
				# bp_msg -3 "    " "- string token:  ${tokens[i]%%"${CONFIGS[os]}"*}"
				bp_msg -3 "    " "- string token:  ${tokens[i]}"
			else
				_bls+=("${tokens[i]}")
				bp_msg -3 "    " "- boolean token: ${tokens[i]}"
			fi
		done
		return 0
	else
		return 1
	fi
}

# classify a CML token by its LID prefix, OV_SEP presence, and next token
# $1 - current LID to match against
# $2 - current token
# $3 - next token (may be empty)
# $4 - nameref: receives the extracted/modified parameter name
# return codes:
#   0: arg (no lid match, solitary argument, caller must handle)
#   1: liga (uliga: lid+lid prefix, e.g. --flag)
#   2: bool (lid prefix, no arg consumed; includes OV_SEP; =true/false)
#   3: bool (lid prefix, consumes next token as true/false)
#   4: string (lid prefix, no arg consumed; OV_SEP present, arg is non-boolean)
#   5: string (lid prefix, consumes next token as value)
#   6: alter-lid match, no consume
#   7: alter-lid match, consume next token
bp_check_param_type() {
	local lid=$1 current=$2 next=$3
	local -n param_ref=$4

	local param_name value

	local ov_sep="${CONFIGS[os]}"
	local tag_true=${CONFIGS[tt]}
	local tag_false=${CONFIGS[tf]}

	bp_msg -2 "    param: " "${current} | ${next}"

	param_ref="${current}"

	# Priors(~~) parssed before Specs(~) and removed from OP-ZONE after Priors parsing,
	# so "${lid}${lid}" will not missmatch
	if bp_with_lid "${current}" "${lid}${lid}"; then
		# '--current' like, uliga
		return 1
	elif bp_with_lid "${current}" "${lid}"; then
		# '-current ' like, with lid
		if [[ "${current}" == ${lid}*${ov_sep}* ]]; then
			# '-current=value' like, depends on value
			param_name=${current#"${lid}"}         # remove lid in case 'lid==OV_SEP'
			param_name=${param_name%%"${ov_sep}"*} # %% in case value contains OV_SEP
			value=${current#*"${ov_sep}"}          # extract value
			if [[ ${value} == true ]]; then
				# '-currnt=true' like, a bool
				param_ref="${lid}${param_name}${tag_true}"
				return 2
			elif [[ ${value} == false ]]; then
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
			# '-current next' like, next without lid
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
				param_ref="${current}${ov_sep}${next}"
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
			# when 'current == *${OV_SEP}*' like, or
			#      'current == -param-' like, might be an input error
			# leave it to alter-lid parsing to handle
			return 7
		fi
	else # without any lid, a solitary argument; leave it to further parsing
		return 0
	fi
}

# iterate CML tokens, classify each via bp_check_param_type, sort into buckets
# $1 - lid to match against
# $2 - nameref: option-zone array (tokens to classify)
# $3 - nameref: receives string-type tokens
# $4 - nameref: receives bool-type tokens
# $5 - nameref: receives liga-type tokens
# $6 - nameref: receives all extracted tokens (union of 3-5)
# for harnesses(globals/priors/specs): filters by lid, splits by OV_SEP into strings/bools
# for user options: delegates to bp_check_param_type, handles arg_consumed flag
# exits 21 on solitary arg (no lid match) for non-global/prior/spec levels
bp_extract_options() {
	local lid=$1
	local -n _op_zone=$2
	local -n strings=$3 bools=$4 ligas=$5 # classified extracted options
	local -n options=$6                   # all extracted options

	bp_msg -2 "  Extract Options '${lid}'" # ": ${_op_zone[*]}"

	# process globals, priors and specs
	bp_extract_harness_tokens "${lid}" _op_zone strings bools options && return 0

	# process user-params
	local i arg_consumed=false
	for i in "${!_op_zone[@]}"; do

		# if [[ ${lid} == "${CONFIGS[glid]}" || ${lid} == "${CONFIGS[plid]}" ]]; then
		# 	# filter out params not match current lid
		# 	bp_with_lid "${_op_zone[i]}" "${lid}" || continue
		# 	# skip solitary LIDS (e.g. standalone '~~' zone separator colliding with PLID)
		# 	[[ ${#_op_zone[i]} -gt ${#lid} ]] || continue
		#
		# 	bp_msg -3 "    " "- token: ${_op_zone[i]}"
		# 	options+=("${_op_zone[i]}")
		# 	[[ ${_op_zone[i]} =~ ${CONFIGS[os]} ]] &&
		# 		strings+=("${_op_zone[i]}") ||
		# 		bools+=("${_op_zone[i]}")
		# 	continue
		# fi

		local curr_param next_param
		local extracted_param="" param_type

		# skip if param is the value of last param
		if [[ "${arg_consumed}" == true ]]; then
			arg_consumed=false
			continue
		fi

		curr_param="${_op_zone[i]}"
		next_param="${_op_zone[$((i + 1))]:-}"

		# bp_msg -3 "    current/next: " "${curr_param}  ${next_param:--}"

		# parse options
		param_type=0
		bp_check_param_type "${lid}" "${curr_param}" "${next_param}" extracted_param || param_type=$?
		bp_msg -3 "    " "- type: ${param_type} | found: ${extracted_param}"
		case "${param_type}" in
		1) ligas+=("${extracted_param}") ;;
		2) bools+=("${extracted_param}") ;;
		3)
			bools+=("${extracted_param}")
			arg_consumed=true
			;;
		4) strings+=("${extracted_param}") ;;
		5)
			strings+=("${extracted_param}")
			arg_consumed=true
			;;
		6) # matching other lid with built-in value, skip
			bp_msg -3 "      ingored: ${extracted_param}"
			continue
			;;
		7) # matching other lid followd by a value, skip with a consumption signal
			arg_consumed=true
			bp_msg -3 "      ingored: ${extracted_param}"
			continue
			;;
		0) # a solitary arg found, parsing failed
			local pros_tag[0]="${curr_param}"
			bp_exit_with_msg 21 pros_tag
			;;
		*)
			# unknow type, should not happened, may used in future
			local pros_tag="unexpected param_type '${param_type}' from bp_check_param_type."
			bp_exit_with_msg 3 pros_tag
			;;
		esac
		options+=("${extracted_param}")
		bp_msg -3 "      extracted: " "${extracted_param}"
	done
	return 0
}

# split CML into option-zone and positional-zone by LID presence (islands style)
# $1 - nameref: receives option-zone tokens (params with any LID)
# $2 - nameref: receives positional-zone tokens (params without LID)
# remaining args are the CML tokens to classify
# ZN_SEP tokens are skipped entirely
bp_extract_parameters_islands() {
	local -n options=$1 positionals=$2
	shift 2

	# extract params
	local param
	for param in "$@"; do
		[[ ${param} == "${CONFIGS[zs]}" ]] && continue
		if bp_with_lid "${param}"; then
			bp_msg -3 "    " "- option token:   ${param}"
			options+=("${param}")
		else
			bp_msg -3 "    " "- position token: ${param}"
			positionals+=("${param}")
		fi
	done
}

# split CML at ZN_SEP (zone separator, default "--") into option-zone and positional-zone
# $1 - nameref: receives option-zone tokens (before ZN_SEP)
# $2 - nameref: receives positional-zone tokens (after ZN_SEP)
# remaining args are the CML tokens to split
#   if no ZN_SEP: guesses zone by checking if first token has a LID
#   if ZN_SEP at position 1: all tokens go to positional-zone
#   if ZN_SEP at last position: all tokens go to option-zone
# exits 20 if more than one ZN_SEP found
bp_extract_parameters_watershed() {
	local -n options=$1 positionals=$2

	shift 2

	bp_msg -3 "    CML: " "$*"
	local param zn_sep_count zn_sep_pos

	# count ZN-SEP and record its position
	zn_sep_count=0
	zn_sep_pos=-1
	for param in "$@"; do
		if [[ ${param} == "${CONFIGS[zs]}" ]]; then
			((zn_sep_count += 1))
		fi
	done

	options=()
	positionals=()

	if [[ ${zn_sep_count} -gt 1 ]]; then
		# duplicate ZONE_SEPs
		local pros_tag[0]="${CONFIGS["zs"]}"
		pros_tag[1]="${zn_sep_count}"
		bp_exit_with_msg 20 pros_tag
	elif [[ ${zn_sep_count} -eq 1 ]]; then
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
				positionals+=("${!i}")
			done
		elif [[ ${zn_sep_pos} -eq $# ]]; then
			# OP_ZONE only with trailing zone-sep
			for ((i = 1; i < $#; i++)); do
				options+=("${!i}")
			done
		else
			# normal case: split at ZN_SEP
			for ((i = 1; i < zn_sep_pos; i++)); do
				options+=("${!i}")
			done
			for ((i = zn_sep_pos + 1; i <= $#; i++)); do
				positionals+=("${!i}")
			done
		fi
	else
		# no ZONE_SEP: one zone only, guess by LID of first param
		if [[ $# -gt 0 ]]; then
			if bp_with_lid "${1}"; then
				options=("$@")
			else
				positionals=("$@")
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
# $1 - lid (used as lid+lid for uliga prefix)
# $2 - nameref: array of ligature tokens
# $3 - nameref: receives expanded {name: tag} pairs
# validates name length is multiple of n; validates each name as shell variable
# exits 24 (invalid name) or 25 (length mismatch)
bp_parse_ligas() {
	local lid=$1
	local -n params=$2 options_pl=$3

	bp_msg -2 "    ligas: " "${params[*]}"
	local liga liga_name liga_tag bool_name bool_name_len start

	for liga in "${params[@]}"; do
		bp_with_lid "${liga}" "${lid}" || continue
		liga=${liga#"${lid}"}                        # strip lid
		liga_tag=$(bp_parse_bool_tag "${liga}")      # parse tag
		liga=${liga%["${TAGS[tt]}${TAGS[tf]}"]}      # strip trailing-tag
		bool_name_len=${liga%%[^[:digit:]]*}         # strip param length
		[[ -n ${bool_name_len} ]] || bool_name_len=1 # default param length
		liga_name=${liga#"${bool_name_len}"}         # param name
		if ((${#liga_name} % bool_name_len)); then
			local pros_tag[0]="${lid}${liga}"
			pros_tag[1]="${liga_name}"
			pros_tag[2]="${bool_name_len}"
			bp_exit_with_msg 25 pros_tag
		fi
		for ((start = 0; start < ${#liga_name}; start += bool_name_len)); do
			bool_name="${liga_name:start:bool_name_len}"
			bp_substitute_variable_name_exceptions bool_name
			if ! bp_validate_variable_name "bool-name in LIGA" bool_name true; then
				local pros_tag[0]="${bool_name}"
				pros_tag[1]="${lid}${liga}"
				bp_exit_with_msg 24 pros_tag
			fi
			options_pl["${bool_name}"]="${liga_tag}"
		done
		bp_msg -3 "    " "- liga ${liga} == '${liga_tag}'"
	done
}

# parse boolean parameters (with trailing +/- tag) into an associative array
# $1 - lid to strip from each param
# $2 - nameref: array of bool tokens (e.g. "flag+" / "flag-")
# $3 - nameref: receives {name: tag} pairs (tag is "true" or "false")
# strips lid and trailing tag; substitutes exceptions; validates variable name
bp_parse_bools() {
	local lid=$1
	local -n params=$2
	local -n options_pb=$3

	bp_msg -2 "    bools: " "${params[*]}"
	local bl param_name bool_tag
	for bl in "${params[@]}"; do
		param_name=${bl#"${lid}"}                           # strip lid
		bool_tag=$(bp_parse_bool_tag "${param_name}")       # parse tag
		param_name=${param_name%["${TAGS[tt]}${TAGS[tf]}"]} # extract name
		bp_substitute_variable_name_exceptions param_name
		bp_validate_variable_name "bool param name" param_name
		options_pb["${param_name}"]="${bool_tag}"
		bp_msg -3 "    " "- bool ${param_name} = '${bool_tag}'"
	done
}

# parse string parameters (with OV_SEP) into an associative array
# $1 - lid to strip from each param
# $2 - nameref: array of string tokens (e.g. "name=value")
# $3 - nameref: receives {name: value} pairs
# strips lid and OV_SEP; substitutes exceptions; validates variable name
bp_parse_strings() {
	local lid=$1
	local -n params=$2 options_ps=$3

	bp_msg -2 "    strings: " "${params[*]}"
	local str str_name str_value
	for str in "${params[@]}"; do
		str_name=${str#"${lid}"}                  # strip lid
		str_name=${str_name%%"${CONFIGS[os]}"*}   # extract name
		str_value="${str#"${lid}${str_name}"}"    # strip <lid><name>
		str_value="${str_value#"${CONFIGS[os]}"}" # extract value
		bp_substitute_variable_name_exceptions str_name
		bp_validate_variable_name "string param name" str_name
		options_ps["${str_name}"]="${str_value}"
		bp_msg -3 "    " "- string  ${str_name} = '${str_value}'"
	done
	return 0
}

# orchestrate parsing of liga/bool/string tokens into a single options array
# $1 - lid context (only ulid gets liga expansion)
# $2 - nameref: string tokens
# $3 - nameref: bool tokens
# $4 - nameref: liga tokens
# $5 - nameref: receives all parsed {name: value} pairs
# order: ligas first, then bools, then strings (last writer wins for dupes)
# option names validated against shell variable naming conventions 
bp_parse_options() {
	local lid=$1
	local -n strings_po=$2 bools_po=$3 ligas_po=$4
	local -n options_po=$5

	bp_msg -2 "  Parse options '${lid}'" #: " "${strings_po[*]:--} | ${bools_po[*]:--} | ${ligas_po[*]:--}"
	# only user-params support ligas
	[[ ${lid} == "${CONFIGS[ulid]}" ]] &&
		((${#ligas_po[@]} > 0)) &&
		bp_parse_ligas "${lid}${lid}" ligas_po options_po

	((${#bools_po[@]} == 0)) ||
		bp_parse_bools "${lid}" bools_po options_po
	((${#strings_po[@]} == 0)) ||
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
	for re_char in "${REGEX_METAS[@]}"; do
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
