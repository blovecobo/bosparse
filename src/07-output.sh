# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154
# Module 07-output: Default assignment and result output
#   assign_user_param_defaults() — assign PFILTER defaults to un-supplied params
#   validate_user_options()      — validate user params against PFILTER
#   create_variables()           — export bool/string params as shell variables
#   output_param_arrays()        — create named result arrays
#   output_eval()                — emit variable assignment statements
#   output_json()                — emit JSON object (capture mode)
#   update_run_mode()            — auto-detect source vs eval vs capture
#   direct_pset_commands()       — execute directive PSets
# --------------------------------------------------------------------------------

# assign PFILTER default value to an un-supplied parameter
function assign_user_param_defaults {
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
			pros_tag[0]="${param}"
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
function validate_user_options {
	msg_bp 2 "Validate user option parameters"

	local param pf_type pf_data pf_mcg
	local mandatory no_pfilter=true

	mandatory="${CONFIGS[${PSETS["rup"]%%${FLD_SEP}*}]}"
	# check if PFILTER supplied or not
	[[ "${CONFIGS[${PSETS["pf"]%%${FLD_SEP}*}]}" == "${NO_PFILTER}" ]] &&
		no_pfilter=true || no_pfilter=false

	msg_bp 4 "  PFILTER-ID: ${PFILTER_ID} | rup: ${mandatory}"

	if [[ "${no_pfilter}" == true ]]; then
		msg_bp 3 "  No PFILTER supplied, no validation for supplied parameters."
		return 0
	fi

	msg_bp 3 "  Validate PFILTER"
	# in case the name 'PFILTER' used by user
	if [[ ${PARAM_FILTER} != "PFILTER" ]]; then
		declare -A PFILTER
		validate_pfilter PFILTER
	else
		declare -A PFILTER_alias
		validate_pfilter PFILTER_alias
		declare -n PFILTER="PFILTER_alias"
	fi

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
				pros_tag[0]="${param}"
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
function create_variables {
	local var
	if [[ ${CONFIGS["${PSETS[dvo]%%${FLD_SEP}*}"]} == true ]]; then
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
function output_param_array {
	local label=$1
	local array_name=$2
	local pset_key=$3
	local default_name=$4
	local key_max_len i

	local -n arr_ref="${array_name}"
	local result_name="${CONFIGS[${PSETS[${pset_key}]%%${FLD_SEP}*}]}"

	msg_bp 2 "  - ${label} in '${result_name}()'"
	key_max_len=$(max_array_member_length "${!arr_ref[@]}")
	((key_max_len += 6))

	if [[ ${result_name} != "${default_name}" ]]; then
		declare -gA "${result_name}=()"
		declare -n out_ref="${result_name}"
		for i in "${!arr_ref[@]}"; do
			out_ref["${i}"]="${arr_ref[${i}]}"
		done
	fi

	for i in "${!arr_ref[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s = " "[\"${i}\"]")" "$(printf "%s\n" "${arr_ref[${i}]}")"
	done
}

function output_positionals_array {
	local positional_an=$1
	local key_max_len i

	msg_bp 2 "  - Positional parameters in '${positional_an}()'"
	if [[ ${positional_an} != "${CONSTS["PAN"]}" ]]; then
		declare -gA "${positional_an}=()"
		declare -n arr_ref="${positional_an}"
		if [[ ${#BP_POSITIONALS[@]} -ne 0 ]]; then
			for i in "${!BP_POSITIONALS[@]}"; do
				arr_ref["${i}"]="${BP_POSITIONALS[${i}]}"
			done
		fi
	fi
	key_max_len=$(max_array_member_length "${!BP_POSITIONALS[@]}")
	((key_max_len += 2))
	for i in "${!BP_POSITIONALS[@]}"; do
		msg_bp -2 "  $(printf "%${key_max_len}s | " "${i}")" "$(printf "%s\n" "${BP_POSITIONALS[${i}]}")"
	done
}

function output_param_arrays {
	msg_bp 2 "  Output parameter arrays"

	output_param_array "Option parameters" BP_OPTIONS "oan" "${CONSTS["OAN"]}"
	output_param_array "Boolean parameters" BP_BOOLS "ban" "${CONSTS["BAN"]}"
	output_param_array "String parameters" BP_STRINGS "san" "${CONSTS["SAN"]}"

	output_positionals_array "${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}"
}

# output parsing result as variable assignment statements, for run-mode eval
# WARNING: eval-mode emits shell assignments. Values are quoted with printf %q,
# but variable names and PFILTER-derived config keys must still be trusted.
# Prefer capture-mode JSON parsing for untrusted input or external callers.
function output_eval {
	local index pvn_prefix

	for index in "${!BP_OPTIONS[@]}"; do
		echo "${index}=$(printf %q "${BP_OPTIONS[${index}]}")"
	done
	# output optional parameters as vars
	# variable name prefix
	pvn_prefix="${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}"
	for index in "${!BP_POSITIONALS[@]}"; do
		echo "${pvn_prefix}_${index}=$(printf %q "${BP_POSITIONALS[${index}]}")"
	done
}

# output parsing result as JSON, for run-mode capture
function output_json {
	# output $BP_OPTIONS in JSON using a single jq -n call

	local param val idx=0
	local -a jq_args=()
	local expr='{}'

	validate_jq

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
	# this implements handling special characters(include newlines) in positionals without breaking
	# the JSON structure
	if [[ ${#BP_POSITIONALS[@]} -gt 0 ]]; then
		idx=$((idx + 1))
		local local_jq_args=() positional_keys=""

		# 1. Build all --arg flags correctly, preserving newlines in values
		for index in "${!BP_POSITIONALS[@]}"; do
			local_jq_args+=(--arg "p${index}" "${BP_POSITIONALS[index]}")
			positional_keys+="\$p${index}, "
		done
		positional_keys="${positional_keys%,*}"

		# append these arguments to jq_args and re-run the main jq command.
		jq_args+=(--arg "k${idx}" "${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}") # Use PSET value as key
		jq_args+=("${local_jq_args[@]}")

		#  Construct the jq expression to create the array from the individual arguments
		expr+=" + {(\$k${idx}): [${positional_keys}]}"

	else
		idx=$((idx + 1))
		jq_args+=(--arg "k${idx}" "${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}") # Use PSET value as key
		expr+=" + {(\$k${idx}): []}"
	fi
	jq -n -c "${jq_args[@]}" "${expr}"
}

# Run-mode detection --------------------------------------------------------------
function update_run_mode {
	# unless '~run' or '~mode' specified, autodetect
	if [[ ${RUN_MODE} == 'auto' ]]; then
		# autodetect
		if [[ ${bosparse_script_name} != $(basename "$0") ]]; then
			msg_bp 3 "  Sourced, output option parameters as variables."
			RUN_MODE="source"
		else
			# not source, assert with '~json'
			if [[ ${CONFIGS[${PSETS["json"]%%${FLD_SEP}*}]} == true ]]; then
				msg_bp 3 "Not sourced, use run-mode 'capture' as 'json' specified."
				RUN_MODE="capture"
			else
				msg_bp 3 "Not sourced, use run-mode 'eval' as default"
				RUN_MODE="eval"
			fi
		fi
	fi
}

# display comprehensive online help for BosParse
function show_help {
	echo "BosParse ${CONSTS["VERSION"]} — parameter parser in & for bash"
	echo
	echo "USAGE"
	echo "    source bosparse && bosparse [options] ${ZN_SEP} [positionals]"
	echo "    eval \$(./bosparse [options] ${ZN_SEP} [positionals])"
	echo "    json=\$(./bosparse ~json [options] ${ZN_SEP} [positionals])"
	echo
	echo "CML STYLES"
	echo "    watershed    options before '${ZN_SEP}', positionals after '${ZN_SEP}' (default)"
	echo "    islands      options start with LID(${ULID}), positionals without LID"
	echo "    ${SLID}style=islands|watershed   set at runtime"
	echo
	echo "PARAMETER TYPES"
	echo "    bool         ${ULID}flag, ${ULID}flag${TAG_TRUE}, ${ULID}flag${TAG_FALSE}"
	echo "    string       ${ULID}param${OA_SEP}value, ${ULID}param value"
	echo "    enum         like string, matched against enum list in PFILTER"
	echo "    liga         ${ULID}${ULID}nparams (expands to params of length n; n=1 may omit)"
	echo
	echo "RUN MODES (auto-detected)"
	echo "    source       sourced in script, exports variables"
	echo "    eval         prints \"key=value\" statements"
	echo "    capture      outputs JSON (requires jq)"
	echo
	echo "PSETs (${PLID} prefix):"
	echo "    ${PLID}run=<mode>         set run mode (auto/source/eval/capture)"
	echo "    ${PLID}json               force JSON output"
	echo "    ${PLID}pf=<pfilter>       pass PFILTER (array/json/keys-values)"
	echo "    ${PLID}dvo                disable variable output (source mode)"
	echo "    ${PLID}rup                restrict unknown parameters"
	echo "    ${PLID}afd                apply PFILTER defaults"
	echo "    ${PLID}pme                prefix-matching for user params (default: on)"
	echo "    ${PLID}oan=<name>         options array name"
	echo "    ${PLID}ban=<name>         bools array name"
	echo "    ${PLID}san=<name>         strings array name"
	echo "    ${PLID}pan=<name>         positionals array name"
	echo "    ${PLID}config             show config after parsing"
	echo "    ${PLID}Defaults           show default configs"
	echo "    ${PLID}Banner             show banner"
	echo "    ${PLID}Version            show version"
	echo "    ${PLID}Resymbols          show reserved symbols"
	echo "    ${PLID}Help               show this help"
	echo
	echo "SUPERS (${SLID} prefix, set before any parsing):"
	echo "    ${SLID}quiet           verbose level 0"
	echo "    ${SLID}standard        verbose level 1 (default)"
	echo "    ${SLID}extra           verbose level 2"
	echo "    ${SLID}debug           verbose level 3"
	echo "    ${SLID}trace           verbose level 4"
	echo "    ${SLID}style=<style>   set CML style (watershed/islands)"
	echo "    ${SLID}zs=<resym2>     zone separator (default: ${ZN_SEP})"
	echo "    ${SLID}plid=<resym>    PSET lid (default: ${PLID})"
	echo "    ${SLID}ulid=<resym>    user-param lid (default: ${ULID})"
	echo
	echo "PRIORS (${PRLID} prefix, customize at runtime):"
	echo "    ${PRLID}os=<resym>       OA separator (default: ${OA_SEP})"
	echo "    ${PRLID}tt=<resym>       true tag (default: ${TAG_TRUE})"
	echo "    ${PRLID}tf=<resym>       false tag (default: ${TAG_FALSE})"
	echo "    ${PRLID}td=<bool>        default bool tag (default: ${TAG_DEFAULT})"
	echo
	echo "OUTPUT"
	echo "    source mode:   exports variables + named arrays"
	echo "    eval mode:     prints key=value statements"
	echo "    capture mode:  prints JSON via jq"
	echo
	echo "PFILTER FORMAT"
	echo "    \"type:data:mcg\"  with '${FLD_SEP}' field sep, '${ELM_SEP}' element sep"
	echo "    type: bool|string|enum"
	echo "    data: default value or enum list (element-separated)"
	echo "    mcg:  mutual-correlate group (d/D/e/m/M/r/u prefix)"
	echo
	echo "MCG TYPES"
	echo "    d/D   dependency (d-members require D-member supplied)"
	echo "    e     exclusion (at most one member may be supplied)"
	echo "    m/M   master (M-member supplies its name to m-member)"
	echo "    r     required (all members must be supplied or have defaults)"
	echo "    u     uniqueness (all supplied member values must differ)"
	echo
	echo "EXIT CODES"
	echo "    0     success"
	echo "    2     no input or error"
	echo "    20+   parameter/filter errors (see doc/BosParse-Reference-Manual.md)"
	echo
	echo "For details: doc/BosParse-Reference-Manual.md  doc/bp-PFILTER.md"
}

# direct_pset_commands: execute directive PSets (Help, Banner, Version, Resymbols, Defaults)
function direct_pset_commands {
	# direct commands for some special PSets, which will not be output user parameters but
	# executed directly in BosParse, e.g. show version or print a message

	if [[ "${CONFIGS[${PSETS["Help"]%%${FLD_SEP}*}]}" == true ]]; then
		show_help
	elif [[ "${CONFIGS[${PSETS["Banner"]%%${FLD_SEP}*}]}" == true ]]; then
		# show banner
		echo -e "${CONSTS["BANNER"]} with love"
	elif [[ "${CONFIGS[${PSETS["Version"]%%${FLD_SEP}*}]}" == true ]]; then
		# show version
		echo "${CONSTS["VERSION"]}"
	elif [[ "${CONFIGS[${PSETS["Resymbols"]%%${FLD_SEP}*}]}" == true ]]; then
		# show resyms
		echo "Available resyms${FLD_SEP} ${RESYMS[*]}"
	elif [[ "${CONFIGS[${PSETS["Defaults"]%%${FLD_SEP}*}]}" == true ]]; then
		# show_configs
		show_configs
	else
		return 0
	fi
	BP_PARSING_STAGE="Mission complete."
	exit 0
}
