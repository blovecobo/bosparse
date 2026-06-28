# shellcheck shell=bash
# Module 08-services: Stage service functions
#   All dependencies received via explicit parameters.
#   Nameref variables use ${!varname} when passed to sub-functions
#   to avoid circular name reference warnings in bash 5.2+.
#
#   bp_parse_tier()       — extract, parse, validate, and MCG-check one parsing tier
#   bp_service_globals()  — parse ~~~ (GLID) tokens, detect CML style, extract zones
#   bp_service_priors()   — parse ~~ (PLID) tokens, apply prior-level settings
#   bp_service_specs()    — parse ~ (SLID) tokens, apply spec-level settings
#   bp_service_users()    — parse - (ULID) tokens, validate against PFILTER
# --------------------------------------------------------------------------------
# run one parsing tier: extract, parse, validate, and MCG-check options
# $1 — lid for this tier (glid/plid/slid/ulid)
# $2 — tier name label ("Global"/"Prior"/"Specs"/"User-params")
# $3 — nameref to filter entries for this tier (empty = no PFILTER)
# $4 — nameref: receives validated {name: value} options
# $5 — nameref to option-zone tokens (modified in-place: parsed tokens removed)
# workflow: extract_options → parse_options → validate names & args → MCG checks
bp_parse_tier() {
	local lid=$1 tier=$2
	local -n FILTER=$3 OPTIONS_tier=$4 OP_ZONE=$5

	declare -a strs=() bls=() ligas=() opts=()
	declare -A OPTS_parsed=()

	local index filter_keys=() arg arg_ori
	filter_keys=("${!FILTER[@]}")

	bp_extract_options "${lid}" OP_ZONE strs bls ligas opts

	# remove parsed options from CML
	for index in "${!OP_ZONE[@]}"; do
		bp_is_array_member "${OP_ZONE[index]}" opts || continue
		bp_msg -3 "    - stripped from CML: " "${OP_ZONE[index]}"
		unset 'OP_ZONE[index]'
	done
	OP_ZONE=("${OP_ZONE[@]}")

	# parse options
	if ((${#opts[@]} > 0)); then
		bp_parse_options "${lid}" strs bls ligas OPTS_parsed

		# validate options
		bp_msg -2 "  Validate options " "${lid}"
		for param in "${!OPTS_parsed[@]}"; do
			param_cmp="${param}"

			# ~afd check on user-params only; always true for globals/priors/specs
			if ((${#FILTER[@]} == 0)); then
				# no filter, validate option names against bash variable naming conventions
				bp_substitute_exceptions param_cmp
				bp_validate_variable_name "${tier}" param_cmp
				bp_msg -3 "      " "- variable name: ${param} -> ${param_cmp}"
				OPTIONS_tier["${param_cmp}"]="${OPTS_parsed[${param}]}"
			else
				# validate against filter
				bp_validate_option_name param_cmp filter_keys "${lid}" "${tier}"
				bp_msg -3 "      " "- variable name: ${param} -> ${param_cmp}"

				bp_extract_filter_schema "${lid}" "${FILTER[${param_cmp}]}" \
					ent_type ent_data ent_mcg
				bp_msg -3 "      " "- filter schema: ${FILTER[${param_cmp}]} -> ${ent_type} | ${ent_data:--} | ${ent_mcg:--}"
				# OPTS_parsed[${param}]: param_cmp may differ to param
				arg="${OPTS_parsed[${param}]}"
				arg_ori="${arg}"
				bp_validate_option_args "${lid}" "${tier}" "${param}" "${param_cmp}" \
					arg "${ent_type}" "${ent_data}" "${ent_mcg}"
				bp_msg -3 "      " "- ${arg_ori} -> ${arg}"
				OPTIONS_tier["${param_cmp}"]="${arg}"
				# bp_validate_option_mcgs "${lid}" FILTER OPTIONS_tier
			fi
		done
		((${#filter_keys[@]} == 0)) || bp_validate_option_mcgs "${lid}" FILTER OPTIONS_tier
		else
			bp_msg -2 "    " "no ${tier} options"
	fi
}

# service tier: parse global-level (~~~) tokens, detect CML style, extract zones
# $1 — nameref: receives option-zone tokens
# $2 — nameref: receives positional-zone tokens
# $3 — nameref: CML reference (modified in-place: parsed tokens removed)
# builds filter from HARNESSES entries with level "global"; runs bp_parse_tier;
# applies parsed settings to CONFIGS; detects watershed vs islands; extracts zones
bp_service_globals() {
	local -n o_zone=$1 p_zone=$2
	local -n CML_ref=$3

	bp_msg 1 "Service Tier: Globals"
	declare -A OPTIONS=() # parsed options with completed keynames

	# build Globals filter
	declare -A globals=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "global" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		globals["${key}"]="$(bp_join_array_members fields)"
	done

	bp_parse_tier "${CONFIGS[glid]}" "Global" globals OPTIONS CML_ref

	bp_apply_setup OPTIONS
	bp_update_verbose

	# extract zone
	CML_STYLE="${CONFIGS["style"]}"
	bp_msg 3 "  CML style: ${CML_STYLE}"
	if [[ ${CML_STYLE} == "watershed" ]]; then
		bp_msg 2 "  Extract Watershed-style CML"
		bp_extract_zones_watershed o_zone p_zone "${CML_ref[@]}"
	else
		bp_msg 2 "  Extract Islands-style CML"
		bp_extract_zones_islands o_zone p_zone "${CML_ref[@]}"
	fi
	bp_msg -3 "    OP-ZONE:" " '${o_zone[*]}'"
	bp_msg -3 "    PP-ZONE:" " '${p_zone[*]}'"
}

# service tier: parse prior-level (~~) tokens, apply prior settings
# $1 — nameref to option-zone tokens (modified in-place)
# builds filter from HARNESSES entries with level "prior"; runs bp_parse_tier
bp_service_priors() {
	local -n o_zone=$1

	bp_msg 1 "Service Tier: Priors"
	# build prior filter
	declare -A priors=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "prior" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		priors["${key}"]="$(bp_join_array_members fields)"
	done

	declare -A OPTIONS=()
	bp_parse_tier "${CONFIGS[plid]}" "Prior" priors OPTIONS o_zone

	bp_apply_setup OPTIONS
	bp_update_verbose

	# shaw_array CONFIGS
	[[ ${CONFIGS[config]} == false ]] || bp_show_configs

	bp_msg -4 "  OP-ZONE:" " '${o_zone[*]}'"
	bp_msg -4 "  PP-ZONE:" " '${p_zone[*]}'"
}

# service tier: parse spec-level (~) tokens, apply spec settings, handle directives
# $1 — nameref to option-zone tokens (modified in-place)
# builds filter from HARNESSES entries with level "spec"; runs bp_parse_tier;
# handles direct commands (Help/Banner/Version/Resymbols/Defaults)
bp_service_specs() {
	local -n o_zone=$1

	bp_msg 1 "Service Tier: Specs"
	declare -A specs=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "spec" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		specs["${key}"]="$(bp_join_array_members fields)"
	done

	declare -A OPTIONS=()
	bp_parse_tier "${CONFIGS[slid]}" "Specs" specs OPTIONS o_zone

	bp_apply_setup OPTIONS
	bp_direct_commands
	bp_update_verbose

	[[ ${CONFIGS[config]} == false ]] || bp_show_configs

	bp_msg -4 "  OP-ZONE:" " '${o_zone[*]}'"
	bp_msg -4 "  PP-ZONE:" " '${p_zone[*]}'"
}

# service tier: parse user-level (-) tokens, validate against PFILTER
# $1 — nameref to option-zone tokens (modified in-place)
# $2 — nameref: receives validated {name: value} options
# loads PFILTER from CONFIGS["pf"] (if set); runs bp_parse_tier;
# applies PFILTER defaults to un-supplied params if ~afd is set
bp_service_users() {
	local -n o_zone=$1 opts_su=$2

	bp_msg 1 "Service Tier: USERS"

	# check PFILTER
	if [[ -n ${CONFIGS["pf"]} ]]; then
		bp_msg 3 "  Validate PFILTER"
		# in case the name 'PFILTER' used by user
		if [[ ${CONFIGS["pf"]} != "PFILTER" ]]; then
			declare -A PFILTER
			bp_validate_pfilter PFILTER
		else
			declare -A PFILTER_alias
			bp_validate_pfilter PFILTER_alias
			declare -n PFILTER="PFILTER_alias"
		fi
	else
		bp_msg 4 "  No PFILTER"
		declare -A PFILTER=()
	fi
	bp_parse_tier "${CONFIGS[ulid]}" "User-params" PFILTER opts_su o_zone
	# bp_show_array opts_su

	if ((${#PFILTER[@]} != 0)) && [[ ${CONFIGS[afd]} == true ]]; then
		bp_apply_filter_default opts_su PFILTER
	else
		return 0
	fi
}
