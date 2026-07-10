# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154
# Module 07-output: Default assignment and result output
#
# Ouput result:
#   bp_output_source_variables()  - export bool/string params as shell variables (source mode)
#   bp_output_source_arrays()     - create named result arrays (source mode)
#   bp_output_eval()              - emit variable assignment statements (eval mode)
#   bp_output_json()              - emit JSON object (capture mode, requires jq)
#
# Directives:
#   bp_show_help()                - display online help text
#   bp_show_configs()             - display current CONFIGS
#   bp_direct_commands()          - execute directive SPECS (Help, Banner, Version, …)
# --------------------------------------------------------------------------------

# create variables for option parameters as parsing result
bp_output_source_variables() {
	local -n options_emit=$1
	if [[ ${CONFIGS["dvo"]} == true ]]; then
		# auto set output option variables via array
		[[ -n ${CONFIGS["oan"]} ]] || bp_set_configs 'oan' "${CONSTS[OAN]}"
		bp_msg 3 "    Output variables disabled"
		return 0
	fi

	bp_msg 3 "    Options to variables"

	# output all variables
	if ((${#options_emit[@]} > 0)); then
		local var
		for var in "${!options_emit[@]}"; do
			declare -g "${var}"="${options_emit["${var}"]}"
			bp_msg -3 "      - " "${var} = ${options_emit["${var}"]}"
		done
	else
		bp_msg -3 "      " "  no options"
	fi

}

bp_output_source_arrays() {
	local -n options_emit=$1 positionals_emit=$2
	bp_msg 3 "    Output parameter arrays"

	# output options
	local key oan
	oan="${CONFIGS["oan"]}"
	bp_msg -3 "      Options to array " "'${oan}'"
	if [[ -n ${oan} ]]; then
		declare -Ag "${oan}"
		declare -n "option_emit=${oan}"
		for key in "${!options_emit[@]}"; do
			option_emit["${key}"]="${options_emit[${key}]}"
			bp_msg -3 "      - " "${key} - ${options_emit[${key}]}"
		done
	else
		bp_msg -3 "      " "  not required"
	fi

	# output positionals
	local pan
	pan="${CONFIGS["pan"]}"
	bp_msg -3 "      Positionals to array " "'${pan}'"
	if ((${#positionals_emit[@]} > 0)); then
		declare -Ag "${pan}"
		declare -n "positional_emit=${pan}"
		for key in "${!positionals_emit[@]}"; do
			positional_emit["${key}"]="${positionals_emit[${key}]}"
			bp_msg -3 "      - " "${key} - ${positionals_emit[${key}]}"
		done
	else
		bp_msg -3 "      " "  no positionals"
	fi
}

# output parsing result as variable assignment statements, for run-mode eval
# WARNING: eval-mode emits shell assignments. Values are quoted with printf %q,
# but variable names and PFILTER-derived config keys must still be trusted.
# Prefer capture-mode JSON parsing for untrusted input or external callers.
bp_output_eval() {
	local -n options_emit=$1 positionals_emit=$2

	bp_msg 3 "    Output variables"
	local index prefix

	# output option parameters as var
	bp_msg 3 "      Options -> variables"
	if ((${#options_emit[@]} > 0)); then
		for index in "${!options_emit[@]}"; do
			echo "${index}=$(printf %q "${options_emit[${index}]}")"
			bp_msg -3 "        - " "${index} - ${options_emit[${index}]}"
		done
	else
		bp_msg -3 "        " "no options"
	fi

	# variable name prefix
	bp_msg 3 "      Positionals -> variables"
	if ((${#positionals_emit[@]} > 0)); then
		prefix="${CONFIGS["pan"]}"
		# output positionals as var with prefix
		for index in "${!positionals_emit[@]}"; do
			echo "${prefix}_${index}=$(printf %q "${positionals_emit[${index}]}")"
			bp_msg -3 "        - " "${index} - ${positionals_emit[${index}]}"
		done
	else
		bp_msg -3 "        " "no positionals"
	fi
}

# output parsing result as JSON, for run-mode capture
bp_output_json() {
	local -n OPTS_OUTPUT=$1 POS_OUTPUT=$2

	bp_msg 3 "  Output variables as JSON"
	# output $OPTS_OUTPUT in JSON using a single jq -n call

	local param val idx=0
	local -a jq_args=()
	local expr='{}'

	bp_validate_jq

	for param in "${!OPTS_OUTPUT[@]}"; do
		val="${OPTS_OUTPUT[${param}]}"
		idx=$((idx + 1))
		jq_args+=(--arg "k${idx}" "${param}")
		if [[ "${val}" == "true" || "${val}" == "false" ]]; then
			# boolean literal
			jq_args+=(--argjson "v${idx}" "${val}")
		elif bp_is_number "${val}"; then
			# numeric literal (integers or decimals without leading zeros)
			jq_args+=(--argjson "v${idx}" "${val}")
		else
			# force string
			jq_args+=(--arg "v${idx}" "${val}")
		fi
		expr+=" + {(\$k${idx}): \$v${idx}}"
	done

	# Emit positional parameters as a JSON array under the key 'CONFIGS["pan"]'
	# this implements handling special characters(include newlines) in positionals without breaking
	# the JSON structure
	if [[ ${#POS_OUTPUT[@]} -gt 0 ]]; then
		idx=$((idx + 1))
		local local_jq_args=() positional_keys=""

		# 1. Build all --arg flags correctly, preserving newlines in values
		for index in "${!POS_OUTPUT[@]}"; do
			local_jq_args+=(--arg "p${index}" "${POS_OUTPUT[index]}")
			positional_keys+="\$p${index}, "
		done
		positional_keys="${positional_keys%,*}"

		# append these arguments to jq_args and re-run the main jq command.
		jq_args+=(--arg "k${idx}" "${CONFIGS[pan]}") # Use Harness value as key
		jq_args+=("${local_jq_args[@]}")

		#  Construct the jq expression to create the array from the individual arguments
		expr+=" + {(\$k${idx}): [${positional_keys}]}"

	else
		idx=$((idx + 1))
		jq_args+=(--arg "k${idx}" "${CONFIGS["pan"]}") # Use Harness value as key
		expr+=" + {(\$k${idx}): []}"
	fi
	jq -n -c "${jq_args[@]}" "${expr}"
}

# display comprehensive online help for BosParse
bp_show_help() {

	local GLID="${CONFIGS[glid]}"
	local PLID="${CONFIGS[plid]}"
	local SLID="${CONFIGS[slid]}"
	local ULID="${CONFIGS[ulid]}"
	local ZN_SEP="${CONFIGS[zs]}"
	local OV_SEP="${CONFIGS[os]}"
	local FLD_SEP="${CONFIGS[fs]}"
	local ELM_SEP="${CONFIGS[es]}"
	local TAG_TRUE="${CONFIGS[tt]}"
	local TAG_FALSE="${CONFIGS[tf]}"
	local TAG_DEFAULT="${CONFIGS[td]}"

	echo "BosParse ${CONSTS["VERSION"]} - parameter parser in & for bash"
	echo
	echo "USAGE"
	echo "    source bosparse && bosparse [options] ${ZN_SEP} [positionals]"
	echo "    eval \$(./bosparse [options] ${ZN_SEP} [positionals])"
	echo "    json=\$(./bosparse ~json [options] ${ZN_SEP} [positionals])"
	echo
	echo "CML STYLES"
	echo "    watershed    options before '${ZN_SEP}', positionals after '${ZN_SEP}' (default)"
	echo "    islands      options start with LID, positionals without LID"
	echo "    ${GLID}style=islands|watershed   set at runtime"
	echo
	echo "RUN MODES (auto-detected)"
	echo "    source       sourced in script, exports variables"
	echo "    eval         prints \"key=value\" statements"
	echo "    capture      outputs JSON (requires jq)"
	echo
	echo "PARAMETER TYPES"
	echo "    bool         ${ULID}flag, ${ULID}flag${TAG_TRUE}, ${ULID}flag${TAG_FALSE}"
	echo "    string       ${ULID}param${OV_SEP}value, ${ULID}param value"
	echo "    enum         like string, matched against enum list in PFILTER"
	echo "    liga         ${ULID}${ULID}nparams (expands to params of length n; n=1 may omit)"
	echo
	echo "GLOBALS (${GLID} prefix, set before any parsing):"
	echo "    ${GLID}style=<style>   set CML style (watershed/islands)"
	echo "    ${GLID}zs=<resym2>     zone separator (default: ${ZN_SEP})"
	echo "    ${GLID}slid=<resym>    SPEC lid (default: ${SLID})"
	echo "    ${GLID}ulid=<resym>    user-param lid (default: ${ULID})"
	echo "    ${GLID}quiet           verbose level 0 (default)"
	echo "    ${GLID}standard        verbose level 1"
	echo "    ${GLID}extra           verbose level 2"
	echo "    ${GLID}debug           verbose level 3"
	echo "    ${GLID}trace           verbose level 4"
	echo
	echo "PRIORS (${PLID} prefix, customize at runtime):"
	echo "    ${PLID}os=<resym>       OA separator (default: ${OV_SEP})"
	echo "    ${PLID}tt=<resym>       true tag (default: ${TAG_TRUE})"
	echo "    ${PLID}tf=<resym>       false tag (default: ${TAG_FALSE})"
	echo "    ${PLID}td=<bool>        default bool tag (default: ${TAG_DEFAULT})"
	echo
	echo "SPECS (${SLID} prefix):"
	echo "    ${SLID}run=<mode>         set run mode (auto/source/eval/capture)"
	echo "    ${SLID}json               force JSON output"
	echo "    ${SLID}pf=<pfilter>       pass PFILTER (array/json/keys-values)"
	echo "    ${SLID}dvo                disable variable output (source mode)"
	echo "    ${SLID}rup                restrict unknown parameters"
	echo "    ${SLID}afd                apply PFILTER defaults"
	echo "    ${SLID}pme                prefix-matching for user params (default: on)"
	echo "    ${SLID}oan=<name>         options array name"
	echo "    ${SLID}pan=<name>         positionals array name"
	echo "    ${SLID}config             show config after parsing"
	echo "    ${SLID}Defaults           show default configs"
	echo "    ${SLID}Banner             show banner"
	echo "    ${SLID}Version            show version"
	echo "    ${SLID}Resymbols          show reserved symbols"
	echo "    ${SLID}Help               show this help"
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

# display current CONFIGS settings, for debugging & directives
bp_show_configs() {
	local output_as_json key param len_key

	[[ ${CONFIGS["json"]} == true ]] && output_as_json=true || output_as_json=false
	[[ ${CONFIGS["run"]} == "capture" ]] && output_as_json=true

	if [[ ${CONFIGS["Defaults"]} == true ]]; then
		# respond to directive calling
		if [[ ${output_as_json} == true ]]; then
			bp_validate_jq
			bp_serialize_pfilter_to_json_string CONFIGS | jq
		else
			bp_show_array CONFIGS 2>&1 | sort -n
		fi
	else
		# for debugging
		local key
		for key in "${!CONFIGS[@]}"; do
			printf '%s=%q\n' "${key}" "${CONFIGS[${key}]}"
		done | sort -n
	fi
}

# bp_direct_commands: execute directive SPECS (Help, Banner, Version, Resymbols, Defaults)
bp_direct_commands() {
	# direct commands for some special SPECS, which will not be output user parameters but
	# executed directly in BosParse, e.g. show version or print a message

	if [[ "${CONFIGS["Help"]}" == true ]]; then
		bp_show_help
	elif [[ "${CONFIGS["Banner"]}" == true ]]; then
		# show banner
		echo -e "${CONSTS["BANNER"]} with love"
	elif [[ "${CONFIGS["Version"]}" == true ]]; then
		# show version
		echo "${CONSTS["VERSION"]}"
	elif [[ "${CONFIGS["Resymbols"]}" == true ]]; then
		# show resyms
		echo "Available resyms: ${RESYMS[*]}"
	elif [[ "${CONFIGS["Defaults"]}" == true ]]; then
		# bp_show_configs
		bp_show_configs
	else
		return 0
	fi
	bosparse_finalize
	exit 0
}
