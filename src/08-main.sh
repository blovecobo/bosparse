# shellcheck shell=bash
# Module 08-main: Entry point and high-level orchestration
#   bosparse() — main function, called when script is executed (not sourced)
#   Workflow: init configs -> detect style -> extract zones -> parse supers ->
#   parse Priors -> parse PSets -> parse User params -> parse Positionals -> output
#   Module-level: BP_ESC_PFX (random escape marker), __BP_READY (sourced marker)
# --------------------------------------------------------------------------------

# initialize runtime configs by calling definitions() and setting CONFIGS defaults
function bosparse_initialize_runtime {
	bosparse_script_path="$(realpath "${BASH_SOURCE[0]}")"
	bosparse_script_name="${bosparse_script_path##*\/}"

	definitions \
		CONFIGS \
		CONSTS \
		PSETS \
		PRIORS \
		SUPERS \
		RESYMS \
		EXCEPTIONS \
		EXIT_MSG \
		PFILTER_ENTRY_TYPES \
		MCG_TYPES \
		SYMNAMES \
		REGEX_METACHARS \
		DEBUG_CMDS \
		IMMUTABLE_CONFIGS

	require_bash_version 4 4
}

# split CML into op_zone (options) and pp_zone (positionals) by current CML_STYLE
function bosparse_extract_zones {
	if [[ ${CML_STYLE} == "watershed" ]]; then
		msg_bp 2 "Extract Watershed-style CML"
		extract_watershed op_zone pp_zone "$@"
	else
		msg_bp 2 "Extract Islands-style CML"
		extract_islands op_zone pp_zone "$@"
	fi
	msg_bp 4 "op zone:" "${op_zone[*]}"
	msg_bp 4 "pp zone:" "${pp_zone[*]}"
}

# show CONFIGS if ~config PSet is set; optionally clear flag after display
function bosparse_show_config_if_needed {
	local setup_map_name=$1
	local clear_after_show=${2:-false}
	local -n setup_ref="${setup_map_name}"

	if [[ -v setup_ref["config"] ]] && [[ ${CONFIGS[${setup_ref["config"]%%${FLD_SEP}*}]} == true ]]; then
		show_configs
		[[ ${clear_after_show} == true ]] && CONFIGS["${setup_ref["config"]%%${FLD_SEP}*}"]=false
	fi
	return 0
}

# orchestrate a single parsing stage (Priors/PSets): extract → parse → validate → apply
function bosparse_parse_stage {
	local stage_label=$1
	local lid=$2
	local setup_map_name=$3
	local rebuild_zones=${4:-false}
	local clear_after_show=${5:-false}
	local reset_after=${6:-true}
	shift 6

	msg_bp 3 "Extract ${stage_label}"
	extract_options "${lid}" strings bools ligas op_zone

	if [[ ${#strings[@]} -ne 0 || ${#bools[@]} -ne 0 || ${#ligas[@]} -ne 0 ]]; then
		msg_bp 2 "Parse ${stage_label}"
		parse_options "${lid}" strings bools ligas

		msg_bp 3 "Validate ${stage_label}"
		validate_options_by_filter "${lid}" true

		msg_bp 3 "Apply ${stage_label}"
		apply_setup "${stage_label}" "${setup_map_name}"
		update_verbose

		if [[ ${reset_after} == true ]]; then
			reset_intermediate_arrays
		else
			reset_intermediate_arrays false
		fi
	else
		msg_bp 3 "  no ${stage_label} supplied, skip parsing ${stage_label}"
	fi

	bosparse_show_config_if_needed "${setup_map_name}" "${clear_after_show}"
	if [[ ${rebuild_zones} == true ]]; then
		bosparse_extract_zones "$@"
		local -a _filtered_zone=()
		local _tok
		for _tok in "${op_zone[@]}"; do
			with_lid "${_tok}" "${lid}" || _filtered_zone+=("${_tok}")
		done
		op_zone=("${_filtered_zone[@]}")
		_filtered_zone=()
		for _tok in "${pp_zone[@]}"; do
			with_lid "${_tok}" "${lid}" || _filtered_zone+=("${_tok}")
		done
		pp_zone=("${_filtered_zone[@]}")
	fi
	return 0
}

# parse user-supplied option params: extract, parse, then validate against PFILTER
function bosparse_parse_user_options {
	msg_bp 2 "Extract user-options"
	extract_options "${ULID}" strings bools ligas op_zone

	msg_bp 2 "Parse user-options"
	parse_options "${ULID}" strings bools ligas

	if [[ ${#BP_OPTIONS[@]} -ne 0 ]] ||
		[[ ${CONFIGS["${PSETS["afd"]%%${FLD_SEP}*}"]} == true ]]; then
		validate_user_options
	fi
}

# emit parsed results in the selected run-mode (source/eval/capture)
function bosparse_emit_output {
	msg_bp 2 "Output parsing result"

	case ${RUN_MODE} in
	source)
		msg_bp 3 "  Output as variables and arrays"
		create_variables
		output_param_arrays
		;;
	eval)
		msg_bp 3 "  Output as eval statements"
		output_eval
		;;
	capture)
		msg_bp 3 "  Output as JSON"
		output_json
		;;
	*) ;;
	esac
}

# reject empty input, lone '--', or lone ZN_SEP before any parsing
function bosparse_validate_input {
	if [[ $# -eq 0 || "$*" == '--' || "$*" == "${ZN_SEP}" ]]; then
		verbose=1
		exit_with_msg 2
	fi
}

# store remaining non-option params from pp_zone as positionals
function bosparse_parse_positionals {
	msg_bp 2 "Parse user-positionals"
	parse_positionals "${pp_zone[@]}"
}

# mark parsing complete (disables exit-trace in sourced mode)
function bosparse_finalize {
	BP_PARSING_STAGE="Mission complete."
	msg_bp 3 "${BP_PARSING_STAGE}"
}

# debug setting
function bosparse_debug_setting {
	local -n params=$1
	local index db_level mapped=false

	for index in "${!params[@]}"; do
		# skip PFILTER, which may contains debug-like strings
		[[ ${params[index]} == ~pf* ]] && continue
		for db_level in "${!DEBUG_CMDS[@]}"; do
			if [[ ${params[index]} == "${DEBUG_CMDS[${db_level}]}" ]]; then
				msg_bp 1 "Debug Setting: ${db_level}"
				DEBUG_MAP["${db_level}"]=true
				mapped=true
			fi
		done
		if [[ ${mapped} == true ]]; then
			unset 'params[index]'
			mapped=false
		fi
	done
	update_verbose
}

# main entry: orchestrate full parsing pipeline (Priors to PSets to User to Positionals to Output)
function bosparse {
	trap on_exit_bp EXIT

	local verbose=1 bosparse_script_name
	declare -a pros_tag=() op_zone=() pp_zone=()
	declare -a op_zone=() pp_zone=()
	declare -a strings=() bools=() ligas=()
	declare -A CONFIGS CONSTS SUPERS PRIORS PSETS
	declare -A EXCEPTIONS EXIT_MSG MCG_TYPES SYMNAMES DEBUG_CMDS
	declare -a RESYMS PFILTER_ENTRY_TYPES REGEX_METACHARS IMMUTABLE_CONFIGS

	bosparse_initialize_runtime

	declare -n NO_PFILTER='CONSTS["NO_PFILTER"]'
	declare -n PFILTER_ID='CONSTS["PFILTER_ID"]'
	declare -n FLD_SEP='CONSTS["FLD_SEP"]'
	declare -n ELM_SEP='CONSTS["ELM_SEP"]'

	declare -n PLID="CONFIGS[${SUPERS["plid"]%%${FLD_SEP}*}]"
	declare -n ULID="CONFIGS[${SUPERS["ulid"]%%${FLD_SEP}*}]"
	declare -n ZN_SEP="CONFIGS[${SUPERS["zs"]%%${FLD_SEP}*}]"
	declare -n OA_SEP="CONFIGS[${PRIORS["os"]%%${FLD_SEP}*}]"
	declare -n TAG_TRUE="CONFIGS[${PRIORS["tt"]%%${FLD_SEP}*}]"
	declare -n TAG_FALSE="CONFIGS[${PRIORS["tf"]%%${FLD_SEP}*}]"
	declare -n TAG_DEFAULT="CONFIGS[${PRIORS[td]%%${FLD_SEP}*}]"

	declare -n SLID="CONFIGS[${SUPERS["slid"]%%${FLD_SEP}*}]"
	local PRLID="${PLID}${PLID}"
	declare -n CML_STYLE="CONFIGS[${SUPERS["style"]%%${FLD_SEP}*}]"

	declare -n RUN_MODE="CONFIGS[${PSETS["run"]%%${FLD_SEP}*}]"
	declare -n PARAM_FILTER="CONFIGS[${PSETS["pf"]%%${FLD_SEP}*}]"

	declare -A "${CONFIGS[${PSETS["oan"]%%${FLD_SEP}*}]}"
	declare -A "${CONFIGS[${PSETS["san"]%%${FLD_SEP}*}]}"
	declare -A "${CONFIGS[${PSETS["ban"]%%${FLD_SEP}*}]}"
	declare -ga "${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}"

	declare -n BP_OPTIONS="${CONFIGS[${PSETS["oan"]%%${FLD_SEP}*}]}"
	declare -n BP_STRINGS="${CONFIGS[${PSETS["san"]%%${FLD_SEP}*}]}"
	declare -n BP_BOOLS="${CONFIGS[${PSETS["ban"]%%${FLD_SEP}*}]}"
	declare -n BP_POSITIONALS="${CONFIGS[${PSETS["pan"]%%${FLD_SEP}*}]}"

	# collision-resistant escape marker prefix; generated once to prevent
	# placeholder collisions with user data containing __COLON__ etc.
	if [[ ! -v BP_ESC_PFX ]]; then
		declare -r BP_ESC_PFX="_bp_${BASHPID}_${RANDOM}_"
	fi

	# build static mapping cache for show_configs
	declare -A __BP_SC_MAP
	for key in "${!SUPERS[@]}"; do
		__BP_SC_MAP["${key}"]="${SUPERS[${key}]%%${FLD_SEP}*}"
	done
	for key in "${!PRIORS[@]}"; do
		__BP_SC_MAP["${key}"]="${PRIORS[${key}]%%${FLD_SEP}*}"
	done
	for key in "${!PSETS[@]}"; do
		__BP_SC_MAP["${key}"]="${PSETS[${key}]%%${FLD_SEP}*}"
	done

	# setting debug
	declare -A DEBUG_MAP=()
	declare -a CML=("$@")
	bosparse_debug_setting CML
	# restore original CML without debug flags for parsing stages
	set -- "${CML[@]}"

	msg_bp 3 "Command line: " "$*"
	msg_bp -2 "verbose: " "${verbose}"

	bosparse_validate_input "$@"

	msg_bp 3 "Command line: " "$*"
	msg_bp -2 "verbose: " "${verbose}"

	reset_intermediate_arrays

	# Supers prarsing needs all params as op_zone
	op_zone=("$@")
	bosparse_parse_stage "Supers" "${SLID}" SUPERS true true true "$@"
	PRLID="${PLID}${PLID}" # sync after supers may change PLID

	if [[ ${#op_zone[@]} -ne 0 ]]; then
		bosparse_parse_stage "Priors" "${PRLID}" PRIORS true true true "$@"
		bosparse_parse_stage "PSets" "${PLID}" PSETS false false false "$@"
		direct_pset_commands
		update_run_mode
		bosparse_parse_user_options
	else
		update_run_mode
	fi

	bosparse_parse_positionals
	bosparse_emit_output
	bosparse_finalize
}

__BP_READY=true # identifying BosParse used

# echo "source assert: $(basename "$(realpath "${BASH_SOURCE[0]}")") | $(basename "$0") "
if [[ $(basename "$(realpath "${BASH_SOURCE[0]}")") == $(basename "$0") ]]; then
	# not source
	bosparse "$@"
fi
