# shellcheck shell=bash
# Module 08-services: Stage service functions
#   All dependencies received via explicit parameters.
#   Nameref variables use ${!varname} when passed to sub-functions
#   to avoid circular name reference warnings in bash 5.2+.
#
#   bp_parse_tier()       - extract, parse, validate, and MCG-check one parsing tier
#   bp_service_globals()  - parse ~~~ (GLID) tokens, detect CML style, extract zones
#   bp_service_priors()   - parse ~~ (PLID) tokens, apply prior-level settings
#   bp_service_specs()    - parse ~ (SLID) tokens, apply spec-level settings
#   bp_service_users()    - parse - (ULID) tokens, validate against PFILTER
# --------------------------------------------------------------------------------

# run one parsing tier: extract, parse, validate, and MCG-check options
# params:
#   $1 - lid for this tier (glid/plid/slid/ulid)
#   $2 - tier name label ("Global"/"Prior"/"Specs"/"User-params")
#   $3 - nameref to filter entries for this tier (empty = no PFILTER)
#   $4 - nameref: receives validated {name: value} options
#   $5 - nameref to option-zone tokens (modified in-place: parsed tokens removed)
# workflow: extract_options → parse_options → validate names & args → MCG checks
bp_parse_tier() {
	local lid=$1 tier=$2
	local -n filter_tier=$3 options_tier=$4 op_zone_tier=$5

	declare -a strings_ext=() bools_ext=() ligas_ext=() options_ext=()
	declare -A options_parsed=()

	bp_extract_options "${lid}" op_zone_tier strings_ext bools_ext ligas_ext options_ext

	# remove extracted options from op-zone
	local index param var_name
	for index in "${!op_zone_tier[@]}"; do
		bp_is_array_member "${op_zone_tier[index]}" options_ext || continue
		bp_msg -3 "    - stripped from CML: " "${op_zone_tier[index]}"
		unset 'op_zone_tier[index]'
	done
	op_zone_tier=("${op_zone_tier[@]}")

	# parse options
	if ((${#options_ext[@]} > 0)); then
		bp_parse_options "${lid}" strings_ext bools_ext ligas_ext options_parsed

		# validate options
		local filter_keys=() option_value option_value_ori
		filter_keys=("${!filter_tier[@]}")
		bp_msg -2 "  Validate options " "${lid}"
		for param in "${!options_parsed[@]}"; do
			var_name="${param}"

			# validate names
			# option names were valid shell variables after parsing
			if ((${#filter_tier[@]} == 0)); then
				# no filter, add the param into result directly
				bp_msg -3 "      " "- variable name: ${param} -> ${var_name}"
				options_tier["${var_name}"]="${options_parsed[${param}]}"
			else
				# filter provided, validate parsed options against filter
				# validate name, undifined parames let off if '~rup-'
				bp_validate_option_name var_name filter_keys "${lid}" "${tier}"
				bp_msg -3 "      " "- variable name: ${param} -> ${var_name}"

				# for 'undifined' 'user options', skip value validation and add into
				# parsing result directly if '~rup-'
				[[ ${CONFIGS["rup"]} == false ]] &&
					! bp_is_array_member "${var_name}" filter_keys &&
					[[ ${lid} == "${CONFIGS[ulid]}" ]] &&
					options_tier["${var_name}"]="${options_parsed[${var_name}]}" &&
					return

				# validate values
				local fe_type fe_data fe_mcg_name
				bp_extract_filter_entry "${lid}" "${filter_tier[${var_name}]}" \
					fe_type fe_data fe_mcg_name
				bp_msg -3 "      " "- filter entry: '${filter_tier[${var_name}]}' -> '${fe_type}' '${fe_data:--}' '${fe_mcg_name:--}'"
				# options_parsed[${param}]: var_name may differ to param
				option_value="${options_parsed[${param}]}"
				option_value_ori="${option_value}"
				bp_validate_option_values "${lid}" "${tier}" "${param}" "${var_name}" \
					option_value "${fe_type}" "${fe_data}" "${fe_mcg_name}"
				bp_msg -3 "      " "- ${option_value_ori} -> ${option_value}"
				options_tier["${var_name}"]="${option_value}"
			fi
		done
		# validate options against MCG rules of filter
		((${#filter_keys[@]} == 0)) || bp_validate_options_against_mcgs "${lid}" filter_tier options_tier
	else
		bp_msg -2 "    " "no ${tier} options"
	fi
}

# service tier: parse global-level (~~~) tokens, detect CML style, extract zones
# $1 - nameref: receives option-zone tokens
# $2 - nameref: receives positional-zone tokens
# $3 - nameref: CML reference (modified in-place: parsed tokens removed)
# builds filter from HARNESSES entries with level "global"; runs bp_parse_tier;
# applies parsed settings to CONFIGS; detects watershed vs islands; extracts zones
bp_service_globals() {
	local -n option_zone=$1 positional_zone=$2
	local -n CML_ref=$3

	bp_msg 1 "Service Tier: Globals"
	declare -A global_options=() # parsed options with completed keynames

	# build Globals filter
	declare -A global_filter=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "global" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		global_filter["${key}"]="$(
			IFS=:
			echo "${fields[*]}"
		)"
	done

	bp_parse_tier "${CONFIGS[glid]}" "Global" global_filter global_options CML_ref

	bp_update_configs global_options
	bp_update_verbose

	# extract zone
	cml_style="${CONFIGS["style"]}"
	bp_msg -2 "  CML style: " "${cml_style}"
	if [[ ${cml_style} == "watershed" ]]; then
		bp_msg 2 "  Extract Watershed-style CML"
		bp_extract_parameters_watershed option_zone positional_zone "${CML_ref[@]}"
	else
		bp_msg 2 "  Extract Islands-style CML"
		bp_extract_parameters_islands option_zone positional_zone "${CML_ref[@]}"
	fi
	bp_msg -3 "    OP-ZONE:" " '${option_zone[*]}'"
	bp_msg -3 "    PP-ZONE:" " '${positional_zone[*]}'"
}

# service tier: parse prior-level (~~) tokens, apply prior settings
# $1 - nameref to option-zone tokens (modified in-place)
# builds filter from HARNESSES entries with level "prior"; runs bp_parse_tier
bp_service_priors() {
	local -n option_zone=$1

	bp_msg 1 "Service Tier: Priors"
	# build prior filter
	declare -A prior_filter=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "prior" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		prior_filter["${key}"]="$(
			IFS=:
			echo "${fields[*]}"
		)"
	done

	declare -A prior_options=()
	bp_parse_tier "${CONFIGS[plid]}" "Prior" prior_filter prior_options option_zone

	bp_update_configs prior_options
	bp_update_verbose

	# shaw_array CONFIGS
	[[ ${CONFIGS[config]} == false ]] || bp_show_configs

	bp_msg -3 "  OP-ZONE:" " '${option_zone[*]}'"
}

# service tier: parse spec-level (~) tokens, apply spec settings, handle directives
# $1 - nameref to option-zone tokens (modified in-place)
# builds filter from HARNESSES entries with level "spec"; runs bp_parse_tier;
# handles direct commands (Help/Banner/Version/Resymbols/Defaults)
bp_service_specs() {
	local -n option_zone=$1

	bp_msg 1 "Service Tier: Specs"
	declare -A spec_filter=()
	local keys=() key fields=()
	bp_derive_harness_entries_by_field "levels" "spec" keys
	for key in "${keys[@]}"; do
		bp_derive_harness_entry_fields "${key}" fields "type" "type-arg" "mcg"
		spec_filter["${key}"]="$(
			IFS=:
			echo "${fields[*]}"
		)"
	done

	declare -A spec_options=()
	bp_parse_tier "${CONFIGS[slid]}" "Specs" spec_filter spec_options option_zone

	bp_update_configs spec_options
	bp_direct_commands
	bp_update_verbose

	[[ ${CONFIGS[config]} == false ]] || bp_show_configs

	bp_msg -3 "  OP-ZONE:" " '${option_zone[*]}'"
}

# service tier: parse user-level (-) tokens, validate against PFILTER
# $1 - nameref to option-zone tokens (modified in-place)
# $2 - nameref: receives validated {name: value} options
# populate PFILTER from CONFIGS["pf"] (if set); runs bp_parse_tier;
# applies PFILTER defaults to un-supplied params if ~afd is set
bp_service_users() {
	local -n option_zone=$1 user_options=$2

	bp_msg 1 "Service Tier: Users"

	# check PFILTER
	if [[ -n ${CONFIGS["pf"]} ]]; then
		bp_msg 3 "  Validate PFILTER"
		# in case the name 'PFILTER' used by user
		if [[ ${CONFIGS["pf"]} != "PFILTER" ]]; then
			declare -A PFILTER=()
			bp_validate_pfilter PFILTER
		else
			declare -A PFILTER_alias=()
			bp_validate_pfilter PFILTER_alias
			declare -n PFILTER="PFILTER_alias"
		fi
	else
		bp_msg 3 "  No PFILTER supplied, no PFILTER-based functionalities"
		declare -A PFILTER=()
	fi
	bp_parse_tier "${CONFIGS[ulid]}" "User-params" PFILTER user_options option_zone

	if ((${#PFILTER[@]} != 0)) &&
		[[ ${CONFIGS[afd]} == true ]]; then
		# [[ ${CONFIGS[rup]} == true ]]; then
		bp_apply_filter_default user_options PFILTER
	else
		return 0
	fi
}
