# shellcheck shell=bash
# shellcheck disable=SC2154
# Module 03-helpers: Helper functions for parsing workflow
#   reset_verbose() / update_verbose() — manage output verbosity levels (0-4)
#   is_in_resyms() — check if a string consists entirely of reserved symbols
#   check_param_type() — classify a CML token (bool/string/liga/arg) by context
#   parse_bool_tag() — extract trailing true/false tag from parameter name
#   apply_setup() — merge BP_STRINGS/BP_BOOLS into BP_OPTIONS and write to CONFIGS
#   reset_intermediate_arrays() — clear working arrays for re-parsing
#   show_configs() — display current CONFIGS (for ~config and ~~~Defaults directives)
# --------------------------------------------------------------------------------

# reset all verbose flags to default (standard, level 1)
function reset_verbose {
	local v
	for v in "quiet" "extra" "debug" "trace"; do
		CONFIGS["${PSETS[${v}]%%${FLD_SEP}*}"]=false
	done
	CONFIGS["${PSETS["standard"]%%${FLD_SEP}*}"]=true
	verbose=1
}

# turn output settings to verbose
# TRACE > DEBUG > EXTRA > STANDARD > QUIET, then:
# trace > debug > extra > standard > quiet
function update_verbose {

	if [[ ${#DEBUG_MAP[@]} -gt 0 ]]; then
		if [[ ${DEBUG_MAP[TRACE]:-false} == true ]]; then
			verbose=4
		elif [[ ${DEBUG_MAP[DEBUG]:-false} == true ]]; then
			verbose=3
		elif [[ ${DEBUG_MAP[EXTRA]:-false} == true ]]; then
			verbose=2
		elif [[ ${DEBUG_MAP[STANDARD]:-false} == true ]]; then
			verbose=1
		elif [[ ${DEBUG_MAP[QUIET]:-false} == true ]]; then
			verbose=0
		fi
	else
		if [[ ${CONFIGS["${PSETS["trace"]%%${FLD_SEP}*}"]} == true ]]; then
			verbose=4
		elif [[ ${CONFIGS["${PSETS["debug"]%%${FLD_SEP}*}"]} == true ]]; then
			verbose=3
		elif [[ ${CONFIGS["${PSETS["extra"]%%${FLD_SEP}*}"]} == true ]]; then
			verbose=2
		elif [[ ${CONFIGS["${PSETS["quiet"]%%${FLD_SEP}*}"]} == true ]]; then
			verbose=0
		else
			verbose=1
		fi
	fi
	return 0
}

# check if parameter consists entirely of a single repeated reserved symbol
function is_in_resyms {
	local param=$1
	local resym
	for resym in "${RESYMS[@]}"; do
		[[ ${param} == ${resym}* && ${param//${resym}/} == "" ]] && return 0
	done
	return 1
}

# classify a CML token: returns type code (0=arg, 1=liga, 2=bool, 4=string, etc.)
# return codes:
#   0: arg (no lid, not recognized as parameter, leave it to caller to handle)
#   1: liga (with lid, recognized as parameter, no consume)
#   2: bool (with lid, recognized as parameter, no consume)
#   3: bool (with lid, recognized as parameter, consume next token as arg)
#   4: string (with lid, recognized as parameter, consume next token as arg)
#   5: string (with lid, recognized as parameter, consume next token as arg)
#   6: a-param (with alter-lid, recognized as parameter, no consume)
#   7: a-param (with alter-lid, recognized as parameter, consume next token as arg)
function check_param_type {
	local lid=$1 current=$2 next=$3
	local -n param_ref=$4

	local param_name arg

	param_ref="${current}"

	if with_lid "${current}" "${lid}${lid}"; then
		# '--current' like, uliga
		return 1
	elif with_lid "${current}" "${lid}"; then
		# '-current ' like, with lid
		if [[ "${current}" == ${lid}*${OA_SEP}* ]]; then
			# '-current=arg' like, depends on arg
			param_name=${current#"${lid}"}         # remove lid in case '$lid==$OA_SEP'
			param_name=${param_name%%"${OA_SEP}"*} # %% in case arg contains OA_SEP
			arg=${current#*"${OA_SEP}"}            # extract arg
			if [[ ${arg} == true ]]; then
				# '-currnt=true' like, a bool
				param_ref="${lid}${param_name}${TAG_TRUE}"
				return 2
			elif [[ ${arg} == false ]]; then
				# '-current=false' like, a bool
				param_ref="${lid}${param_name}${TAG_FALSE}"
				return 2
			else
				# '-current="right now"' like, a string
				return 4
			fi
		elif with_lid "${next}" || [[ -z "${next}" ]]; then
			# '-current -next' like, or no next(reach end), a bool
			return 2
		else
			# '-current next' like, next is an arg
			param_name=${current#"${lid}"}
			if [[ ${next} == true ]]; then
				# '-current true' like, a bool(next is a boolean value)
				param_ref="${param_name}${TAG_TRUE}"
				return 3
			elif [[ ${next} == false ]]; then
				# '-current false' like, a bool(next is a boolean value)
				param_ref="${param_name}${TAG_FALSE}"
				return 3
			else
				# '-current "year of 1984"' like, a string(next is not a boolean value)
				param_ref="${current}${OA_SEP}${next}"
				return 5
			fi
		fi
	elif with_lid "${current}"; then
		# '<alter-lid>current ' like, match other lids(include ligas)
		if with_lid "${next}" || [[ -z "${next}" ]]; then
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

# extract trailing true/false tag character from parameter name
function parse_bool_tag {
	local param=$1
	local tag=${param: -1}

	case "${tag}" in
	"${TAG_TRUE}") echo true ;;
	"${TAG_FALSE}") echo false ;;
	*) echo "${TAG_DEFAULT}" ;;
	esac
}

# merge parsed Priors/PSets into BP_OPTIONS then write to CONFIGS
function apply_setup {
	local title=$1
	local -n setup_ref=$2

	local ps field_len
	# merge PSets
	for ps in "${!BP_STRINGS[@]}"; do
		BP_OPTIONS["${ps}"]="${BP_STRINGS[${ps}]}"
	done
	for ps in "${!BP_BOOLS[@]}"; do
		BP_OPTIONS["${ps}"]="${BP_BOOLS[${ps}]}"
	done

	msg_bp 4 "  ${title} after applying settings:" >&2
	# apply settings to CONFIGS
	field_len=$(max_array_member_length "${!BP_OPTIONS[@]}")
	for ps in "${!BP_OPTIONS[@]}"; do
		# check if in IMMUTABLE_CONFIGS, otherwise update CONFIGS
		if is_array_member "${ps}" IMMUTABLE_CONFIGS; then
			pros_tag[0]="${title} setting:"
			pros_tag[1]="${ps} is immutable"
			pros_tag[2]="cannot be changed."
			exit_with_msg 27
		fi
		msg_bp 4 "    $(printf "%${field_len}s | %s\n" "${ps}" "${BP_OPTIONS[${ps}]}")" >&2
		CONFIGS["${setup_ref["${ps}"]%%${FLD_SEP}*}"]="${BP_OPTIONS["${ps}"]}"
	done
}

# Reset all intermediate results arrays, for re-parsing if needed
function reset_intermediate_arrays {
	local reset_zone_arra=${1:-true}
	local arr_name
	for arr_name in BP_OPTIONS BP_BOOLS BP_STRINGS BP_POSITIONALS strings bools ligas; do
		declare -n arr_ref="${arr_name}"
		arr_ref=()
	done
	[[ "${reset_zone_arra}" == true ]] || return 0
	op_zone=()
	pp_zone=()
	return 0
}

# display current CONFIGS settings, for debugging & directives
function show_configs {
	local output_as_json key param len_key

	[[ ${CONFIGS[${PSETS["json"]%%${FLD_SEP}*}]} == true ]] && output_as_json=true || output_as_json=false
	[[ ${CONFIGS[${PSETS["run"]%%${FLD_SEP}*}]} == "capture" ]] && output_as_json=true

	# output to stdout if '~config' set, or to stderr for debugging
	# ~/~~/~~~config set to true, output current CONFIGS settings to stdout
	local -n mappings=__BP_SC_MAP
	declare -A show_arr=()
	for param in "${!CONFIGS[@]}"; do
		key=$(key_of_array_member "${param}" mappings) || continue
		show_arr["${key}"]="${CONFIGS[${param}]}"
	done

	if [[ ${CONFIGS["${PSETS["config"]%%${FLD_SEP}*}"]} == true ]]; then
		if [[ ${output_as_json} == true ]]; then
			validate_jq
			serialize_pfilter show_arr | jq
		else
			len_key=$(max_array_member_length "${!show_arr[@]}")
			len_key=$((len_key + 2))
			for key in "${!show_arr[@]}"; do
				printf "%q=%q\n" "${key}" "${show_arr[${key}]}"
			done
		fi
	else
		# for directive Defaults
		if [[ ${output_as_json} == true ]]; then
			validate_jq
			serialize_pfilter show_arr | jq
		else
			# key length
			len_key=$(max_array_member_length "${!CONSTS[@]}" "${!PRIORS[@]}" "${!PSETS[@]}")
			((len_key += 2))
			echo2 ""
			echo2 "BosParse constants:"
			for key in "${!CONSTS[@]}"; do
				printf "%${len_key}s | %s\n" "${key}" "${CONSTS[${key}]}" >&2
			done | sort -n
			echo2 ""
			echo2 "Priors defaults:"
			for key in "${!PRIORS[@]}"; do
				printf "%${len_key}s | %s\n" "~~${key}" "${CONFIGS[${PRIORS[${key}]%%${FLD_SEP}*}]}" >&2
			done | sort -n
			echo2 ""
			echo2 "PSets defaults:"
			for key in "${!PSETS[@]}"; do
				printf "%${len_key}s | %s\n" "~${key}" "${CONFIGS[${PSETS[${key}]%%${FLD_SEP}*}]}" >&2
			done | sort -n
		fi
	fi
}
