# shellcheck shell=bash
# Module 08-main: Entry point and high-level orchestration
#   bosparse() — main function, called when script is executed (not sourced)
#   Workflow: init configs -> detect style -> extract zones ->
#   parse Priors -> parse PSets -> parse User params -> parse Positionals -> output
#   Module-level: BP_ESC_PFX (random escape marker), __BP_READY (sourced marker)
# --------------------------------------------------------------------------------

# initialize runtime configs by calling definitions() and setting CONFIGS defaults
function bosparse_initialize_runtime {
	local_script_path="$(realpath "${BASH_SOURCE[0]}")"
	local_script_name="${local_script_path##*\/}"

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
		SYMNAMES

	CONFIGS["run_mode"]="auto"
	CONFIGS["style_of_commandline"]="watershed"
	CONFIGS["output_as_json"]=false
	CONFIGS["param_filter"]="${CONSTS["NO_PFILTER"]}"
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

	if [[ ${CONFIGS[${setup_ref["config"]%%:*}]} == true ]]; then
		show_configs
		[[ ${clear_after_show} == true ]] && CONFIGS["${setup_ref["config"]%%:*}"]=false
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

		bosparse_show_config_if_needed "${setup_map_name}" "${clear_after_show}"
		[[ ${rebuild_zones} == true ]] && bosparse_extract_zones "$@"
		return 0
	fi

	msg_bp 3 "  no ${stage_label} supplied, skip parsing ${stage_label}"
}

# parse user-supplied option params: extract, parse, then validate against PFILTER
function bosparse_parse_user_options {
	msg_bp 2 "Extract user-options"
	extract_options "${ULID}" strings bools ligas op_zone

	msg_bp 2 "Parse user-options"
	parse_options "${ULID}" strings bools ligas

	if [[ ${#BP_OPTIONS[@]} -ne 0 ]] ||
		[[ ${CONFIGS["${PSETS["afd"]%%:*}"]} == true ]]; then
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
	if [[ $# -eq 0 || $* == '--' || $* == "${ZN_SEP}" ]]; then
		verbose=1
		exit_with_msg 2
	fi
}

# collect super-verbose (~~~~) flags from CML before main parsing starts
function bosparse_collect_super_flags {
	local CMLM=("$@") spr param="${SLID}"

	for i in "${!CMLM[@]}"; do
		if [[ ${CMLM[i]} =~ ^\~pf= ]]; then
			unset "CMLM[i]"
			break
		fi
	done

	for spr in "${!SUPERS[@]}"; do
		[[ ${SUPERS[${spr}]##*:} == "eg_sv" ]] || continue
		for i in "${!CMLM[@]}"; do
			if [[ ${CMLM[i]} =~ ${param}${spr} ]]; then
				supers+=("${spr}")
				break
			fi
		done
	done

	update_verbose
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

# main entry: orchestrate full parsing pipeline (Priors to PSets to User to Positionals to Output)
function bosparse {
	# trap on_exit_bp EXIT
	local verbose
	local pros_tag="" pros_tag2="" pros_tag3="" pros_tag4="" pros_tag5=""

	declare -a op_zone=() pp_zone=()
	declare -a strings=() bools=() ligas=()
	declare -A CONFIGS CONSTS SUPERS PRIORS PSETS
	declare -A EXCEPTIONS EXIT_MSG MCG_TYPES SYMNAMES
	declare -a RESYMS PFILTER_ENTRY_TYPES

	bosparse_initialize_runtime
	declare -n SLID="CONFIGS[${SUPERS["slid"]%%:*}]"
	declare -n PRLID="CONFIGS[${SUPERS["prlid"]%%:*}]"
	declare -n CML_STYLE="CONFIGS[style_of_commandline]"
	declare -l param="$SLID"

	declare -n PLID="CONFIGS[${PRIORS["plid"]%%:*}]"
	declare -n ULID="CONFIGS[${PRIORS["ulid"]%%:*}]"
	declare -n ZN_SEP="CONFIGS[${PRIORS["zs"]%%:*}]"
	declare -n OA_SEP="CONFIGS[${PRIORS["os"]%%:*}]"
	declare -n TAG_TRUE="CONFIGS[${PRIORS["tt"]%%:*}]"
	declare -n TAG_FALSE="CONFIGS[${PRIORS["tf"]%%:*}]"
	declare -n TAG_DEFAULT="CONFIGS[${PRIORS[td]%%:*}]"

	declare -n RUN_MODE="CONFIGS[run_mode]"
	declare -n PARAM_FILTER="CONFIGS[param_filter]"

	declare -n NO_PFILTER='CONSTS["NO_PFILTER"]'
	declare -n PFILTER_ID='CONSTS["PFILTER_ID"]'
	declare -n FLD_SEP="CONSTS[FLD_SEP]"
	declare -n ELM_SEP="CONSTS[ELM_SEP]"

	declare -A "${CONFIGS[${PSETS["oan"]%%:*}]}"
	declare -A "${CONFIGS[${PSETS["san"]%%:*}]}"
	declare -A "${CONFIGS[${PSETS["ban"]%%:*}]}"
	declare -ga "${CONFIGS[${PSETS["pan"]%%:*}]}"

	declare -n BP_OPTIONS="${CONFIGS[${PSETS["oan"]%%:*}]}"
	declare -n BP_STRINGS="${CONFIGS[${PSETS["san"]%%:*}]}"
	declare -n BP_BOOLS="${CONFIGS[${PSETS["ban"]%%:*}]}"
	declare -n BP_POSITIONALS="${CONFIGS[${PSETS["pan"]%%:*}]}"

	# build static mapping cache for show_configs
	declare -A __BP_SC_MAP
	for key in "${!PRIORS[@]}"; do
		__BP_SC_MAP["${key}"]="${PRIORS[${key}]%%:*}"
	done
	for key in "${!PSETS[@]}"; do
		__BP_SC_MAP["${key}"]="${PSETS[${key}]%%:*}"
	done

	declare -a supers=()
	bosparse_validate_input "$@"
	bosparse_collect_super_flags "$@"

	msg_bp 3 "Command line: " "$*"
	msg_bp -2 "verbose: " "${verbose}"

	reset_intermediate_arrays
	check_cml_style "$@"
	bosparse_extract_zones "$@"

	[[ ${#op_zone[@]} -eq 0 && ${#pp_zone[@]} -eq 0 ]] && exit_with_msg 2

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

# collision-resistant escape marker prefix; generated once to prevent
# placeholder collisions with user data containing __COLON__ etc.
if [[ ! -v BP_ESC_PFX ]]; then
	declare -gr BP_ESC_PFX="_bp_${BASHPID}_${RANDOM}_"
fi

# echo "source assert: $(basename "$(realpath "${BASH_SOURCE[0]}")") | $(basename "$0") "
if [[ $(basename "$(realpath "${BASH_SOURCE[0]}")") == $(basename "$0") ]]; then
	# not source
	bosparse "$@"
fi
