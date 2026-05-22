
# Default & output ----------------------------------------------------------------

function assign_user_param_defaults() {
	local param=$1 pf_type=$2 pf_data=$3 pf_mcg=$4
	local default_enum

	[[ ${verbose} -ge 4 ]] && printf "    \e[2;33m%-12s - %6s | %14s | %-10s | %s\e[0m\n" \
		"${param}" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" "default" >&2
	case "${pf_type}" in
	bool | string)
		if [[ -n ${pf_data} ]]; then
			# default value specified in PFILTER
			BP_OPTIONS["${param}"]="${pf_data}"
			if [[ ${pf_type} == "bool" ]]; then
				BP_BOOLS["${param}"]="${pf_data}"
			else
				BP_STRINGS["${param}"]="${pf_data}"
			fi
		else # not supplied && no default value, parsing failed
			pros_tag="${param}"
			exit_with_msg 55
		fi
		;;
	enum)
		# set with first enum as default value
		default_enum=${pf_data%%'|'*}
		BP_OPTIONS["${param}"]="${default_enum}"
		# enum type is treated as string in BP_OPTIONS(true|false should be set as Booleans)
		BP_STRINGS["${param}"]="${default_enum}"
		;;
	*) # this will not happen since integrity checking already done in validate_pfilter
		;;
	esac
	[[ ${verbose} -ge 3 ]] && printf "    \e[2m%-12s - %6s | %14s | %-10s | \e[0;2m%s\e[0m\n" \
		"${param}" "${pf_type}" "${BP_OPTIONS[${param}]:--}" "${pf_mcg}" "assigned" >&2
	return 0
}

# validate user option parameters by PFILTER
#   validate PFILTER
#   validate param name(include prefixes)
#   validate param values
#   assign defaults for un-supplied user params if needed
#     - skip Priors/PSets, they are always 'always supplied'
#     - skip MCG members, they use MCG rules
# key params:
#	~pf: nameref of PFILTER, or serialized PFILTER
#	PFILTER_ID: identify the PFILTER
#   ~rup: all parameters must be defined in PFILTER(false by defautl)
#   ~afd: apply PFILTER defaults on parameters(true by default)
function validate_user_options() {
	msg_bp 2 "Validate user option parameters"

	local param pf_type pf_data pf_mcg
	local mandatory no_pfilter=true

	mandatory="${CONFIGS[${PSETS["rup"]%%:*}]}"
	# check if PFILTER supplied or not
	[[ "${CONFIGS[${PSETS["pf"]%%:*}]}" == "${NO_PFILTER}" ]] &&
		no_pfilter=true || no_pfilter=false

	msg_bp 4 "  PFILTER-ID: ${PFILTER_ID} | rup: ${mandatory}"

	if [[ "${no_pfilter}" == true ]]; then
		# [[ ${mandatory} == true ]] && exit_with_msg 30 # no PFILTER supplied
		msg_bp 3 "  No PFILTER supplied, no validation for supplied parameters."
		return 0
	fi

	msg_bp 3 "  Validate PFILTER"
	# in case the name 'PFILTER' used by user
	if [[ ${PARAM_FILTER} != "PFILTER" ]]; then
		declare -A PFILTER
	fi
	validate_pfilter

	msg_bp 3 "  validate params with PFILTER"
	validate_options_by_filter "${ULID}" "${mandatory}"

	# fulfilling un-supplied parameters if '~afd' set
	if [[ ${CONFIGS["${PSETS[afd]%%"${FLD_SEP}"*}"]} == true ]]; then
		msg_bp 3 "  - assign default values if not supplied"
		[[ ${verbose} -ge 4 ]] && printf "    \e[4;33m%-12s - %6s | %14s | %-10s | %s\e[0m\n" \
			"param" "type" "data" "mcg" "status" >&2
		for param in "${!PFILTER[@]}"; do
			extract_filter_schema "${ULID}" "${PFILTER[${param}]}" pf_type pf_data pf_mcg
			# skip assignment for mcg members
			[[ -z ${pf_mcg} ]] || {
				[[ ${verbose} -ge 4 ]] && printf "    \e[2;33m%-12s - %6s | %14s | %-10s | %s\e[0m\n" \
					"${param}" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" "MCG member" >&2
				continue
			}
			# skip supplied ones
			[[ -v BP_OPTIONS["${param}"] ]] && {
				[[ ${verbose} -ge 4 ]] && printf "    \e[2;33m%-12s - %6s | %14s | %-10s | %s\e[0m\n" \
					"${param}" "${pf_type}" "${pf_data:--}" "${pf_mcg:--}" "supplied" >&2
				continue
			}
			# no default value, failed
			if [[ -z "${pf_data}" ]]; then
				pros_tag="${param}"
				exit_with_msg 55
			fi
			# assigning defaults
			assign_user_param_defaults "${param}" "${pf_type}" "${pf_data}" "${pf_mcg}"
		done
	else
		msg_bp 3 "  - fulfilling disabled by '~afd-'"
	fi
}

# create variables for option parameters as parsing result
function create_variables() {
	local var
	if [[ ${CONFIGS["${PSETS[dvo]%%:*}"]} == true ]]; then
		msg_bp 2 "  - Options output disabled."
		return 0
	fi

	msg_bp 2 "  - Option parameters:"

	# bools
	msg_bp 2 "    - Boolean parameters:"
	for var in "${!BP_BOOLS[@]}"; do
		declare -g "${var}"="${BP_BOOLS["${var}"]}"
		msg_bp -2 "      ${var} = " "${BP_BOOLS["${var}"]}"
	done

	# strings
	msg_bp 2 "    - String parameters:"
	for var in "${!BP_STRINGS[@]}"; do
		declare -g "${var}"="${BP_STRINGS[${var}]}"
		msg_bp -2 "      ${var} = " "${BP_STRINGS[${var}]}"
	done
}

# Output parsing result as arrays with name references specified by user, e.g. if user specified
# "~oan=all_options" for OAN from CML, then an array named "all_option" will be created and
# assigned with all Options, then user can use "${all_option[@]}" to access all Options in
# their script; if not specified, no array will be created for that type of params.
#
# These arrays are for run-mode source, not for run-mode eval/capture since variables output
# in other formats in both mode; for example, in eval mode, output as variable assignment
# statements, and in capture, output as JSON string.
function output_param_arrays() {
	local option_an bools_an strings_an positional_an
	local i key_max_len

	msg_bp 2 "  Output parameter arrays"

	# option parameters
	option_an=${CONFIGS["${PSETS["oan"]%%:*}"]}
	msg_bp 2 "  - Option parameters in '${option_an}()'"
	key_max_len=$(max_array_member_length "${!BP_OPTIONS[@]}")
	((key_max_len += 6))
	# max_array_key_len BP_OPTIONS key_max_len 6
	if [[ ${option_an} != "${CONSTS["OAN"]}" ]]; then
		declare -gA "${option_an}=()"
		declare -n arr_ref="${option_an}"
		for i in "${!BP_OPTIONS[@]}"; do
			arr_ref["${i}"]="${BP_OPTIONS[${i}]}"
		done
	fi
	for i in "${!BP_OPTIONS[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s = " "[\"${i}\"]")" "\"$(printf "%s\n" "${BP_OPTIONS[${i}]}")\""
	done

	# bool parameters
	bools_an=${CONFIGS["${PSETS["ban"]%%:*}"]}
	msg_bp 2 "  - Boolean parameters in '${bools_an}()'"
	key_max_len=$(max_array_member_length "${!BP_BOOLS[@]}")
	((key_max_len += 6))
	# max_array_key_len BP_Bools key_max_len 6
	if [[ ${bools_an} != "${CONSTS["BAN"]}" ]]; then
		declare -gA "${bools_an}=()"
		declare -n arr_ref="${bools_an}"
		for i in "${!BP_BOOLS[@]}"; do
			arr_ref["${i}"]="${BP_BOOLS[${i}]}"
		done
	fi
	for i in "${!BP_BOOLS[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s = " "[\"${i}\"]")" "$(printf "%s\n" "${BP_BOOLS[${i}]}")"
	done

	# string parameters
	strings_an=${CONFIGS["${PSETS["san"]%%:*}"]}
	msg_bp 2 "  - String parameters in '${strings_an}()'"
	key_max_len=$(max_array_member_length "${!BP_STRINGS[@]}")
	((key_max_len += 6))
	# max_array_key_len BP_Strings key_max_len 6
	if [[ ${strings_an} != "${CONSTS["SAN"]}" ]]; then
		declare -gA "${strings_an}=()"
		declare -n arr_ref="${strings_an}"
		for i in "${!BP_STRINGS[@]}"; do
			arr_ref["${i}"]="${BP_STRINGS[${i}]}"
		done
	fi
	for i in "${!BP_STRINGS[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s = " "[\"${i}\"]")" "$(printf "%s\n" "\"${BP_STRINGS[${i}]}")\""
	done

	# position parameters
	positional_an=${CONFIGS["${PSETS["pan"]%%:*}"]}
	msg_bp 2 "  - Positional parameters in '${positional_an}()'"
	if [[ ${positional_an} != "${CONSTS["PAN"]}" ]]; then
		# create a new array for positionals
		declare -gA "${positional_an}=()"
		declare -n arr_ref="${positional_an}"
		if [[ ${#BP_POSITIONALS[@]} -ne 0 ]]; then
			for i in "${!BP_POSITIONALS[@]}"; do
				arr_ref["${i}"]="${BP_POSITIONALS[${i}]}"
			done
		fi
	fi
	for i in "${!BP_POSITIONALS[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s | " "${i}")" "\"$(printf "%s\n" "${BP_POSITIONALS[${i}]}")\""
	done
}

# output parsing result as variable assignment statements, for run-mode eval
function output_eval() {
	local index pvn_prefix

	for index in "${!BP_OPTIONS[@]}"; do
		echo "${index}=$(printf %q "${BP_OPTIONS[${index}]}")"
	done
	# output optional parameters as vars
	# variable name prefix
	pvn_prefix="${CONFIGS[${PSETS["pan"]%%:*}]}"
	for index in "${!BP_POSITIONALS[@]}"; do
		echo "${pvn_prefix}_${index}=$(printf %q "${BP_POSITIONALS[${index}]}")"
	done
}

# output parsing result as JSON, for run-mode capture
function output_json() {
	# output $BP_OPTIONS in JSON using a single jq -n call

	local param val idx=0
	local -a jq_args=()
	local expr='{}'

	validate_jq

	# helper: valid number check (no leading zeros except '0')
	function is_number() {
		[[ $1 =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]
	}

	for param in "${!BP_OPTIONS[@]}"; do
		val="${BP_OPTIONS[${param}]}"
		idx=$((idx + 1))
		jq_args+=(--arg "k${idx}" "${param}")
		if [[ "${val}" == "true" || "${val}" == "false" ]]; then
			# boolean literal
			jq_args+=(--argjson "v${idx}" "${val}")
		elif is_number "${val}"; then
			# numeric literal (integers or decimals without leading zeros)
			jq_args+=(--argjson "v${idx}" "${val}")
		else
			# force string
			jq_args+=(--arg "v${idx}" "${val}")
		fi
		expr+=" + {(\$k${idx}): \$v${idx}}"
	done

	# Emit positional parameters as a JSON array under the key 'bp_positionals'
	if [[ ${#BP_POSITIONALS[@]} -gt 0 ]]; then
		local positionals_json
		positionals_json=$(printf '%s\n' "${BP_POSITIONALS[@]}" | jq -R -s -c 'split("\n")[:-1]')
		idx=$((idx + 1))
		jq_args+=(--arg "k${idx}" "${CONFIGS[${PSETS["pan"]%%:*}]}")
		jq_args+=(--argjson "v${idx}" "${positionals_json}")
		expr+=" + {(\$k${idx}): \$v${idx}}"
	fi

	jq -n "${jq_args[@]}" "${expr}"
}

# Run-mode detection --------------------------------------------------------------
function update_run_mode() {
	# unless '~run' or '~mode' specified, autodetect
	if [[ ${RUN_MODE} == 'auto' ]]; then
		# autodetect
		if [[ ${local_script_name} != $(basename "$0") ]]; then
			msg_bp 3 "  Sourced, output option parameters as variables."
			RUN_MODE="source"
		else
			# not source, assert with '~json'
			if [[ ${CONFIGS[${PSETS["json"]%%:*}]} == true ]]; then
				msg_bp 3 "Not sourced, use run-mode 'capture' as 'json' specified."
				RUN_MODE="capture"
			else
				msg_bp 3 "Not sourced, use run-mode 'eval' as default"
				RUN_MODE="eval"
			fi
		fi
	fi
}

# direct_pset_commands: execute directive PSets (Banner, Version, Resymbols, Defaults)
function direct_pset_commands() {
	# direct commands for some special PSets, which will not be output user parameters but
	# executed directly in BosParse, e.g. show version or print a message

	if [[ "${CONFIGS[${PSETS["Banner"]%%:*}]}" == true ]]; then
		# show banner
		echo -e "${CONSTS["BANNER"]} with love"
	elif [[ "${CONFIGS[${PSETS["Version"]%%:*}]}" == true ]]; then
		# show version
		echo "${CONSTS["VERSION"]}"
	elif [[ "${CONFIGS[${PSETS["Resymbols"]%%:*}]}" == true ]]; then
		# show resyms
		echo "Available resyms: ${RESYMS[*]}"
	elif [[ "${CONFIGS[${PSETS["Defaults"]%%:*}]}" == true ]]; then
		# show_configs
		show_configs
	else
		return 0
	fi
	exit 0
}
