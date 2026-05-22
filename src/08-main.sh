# Main function -------------------------------------------------------------------

function bosparse() {

	# trap on_exit_bp EXIT

	local local_script_path
	# local local_script_dir
	local local_script_name

	local_script_path="$(realpath "${BASH_SOURCE[0]}")"
	# local_script_dir="${local_script_path%\/*}"
	local_script_name="${local_script_path##*\/}"

	declare -a op_zone=() pp_zone=()
	declare -a strings=() bools=() ligas=()

	# local variables
	local verbose
	# local run_mode
	local __QUIET __STANDARD __EXTRA __DEBUG __TRACE
	local pros_tag="" pros_tag2="" pros_tag3="" pros_tag4="" pros_tag5=""
	# local pros_tag pros_tag2 pros_tag3 pros_tag4 pros_tag5

	declare -A CONFIGS CONSTS SUPERS PRIORS PSETS SVERBOSE
	declare -A EXCEPTIONS EXIT_MSG MCG_TYPES SYMNAMES
	declare -a RESYMS PFILTER_ENTRY_TYPES

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
		SVERBOSE \
		SYMNAMES

	declare -n SLID="CONFIGS[${SUPERS["slid"]%%:*}]"
	declare -n PRLID="CONFIGS[${SUPERS["prlid"]%%:*}]"
	declare -n CML_STYLE="CONFIGS[${SUPERS["style"]%%:*}]"

	declare -n PLID="CONFIGS[${PRIORS["plid"]%%:*}]"
	declare -n ULID="CONFIGS[${PRIORS["ulid"]%%:*}]"
	declare -n ZN_SEP="CONFIGS[${PRIORS["zs"]%%:*}]"
	declare -n OA_SEP="CONFIGS[${PRIORS["os"]%%:*}]"
	declare -n TAG_TRUE="CONFIGS[${PRIORS["tt"]%%:*}]"
	declare -n TAG_FALSE="CONFIGS[${PRIORS["tf"]%%:*}]"
	declare -n TAG_DEFAULT="CONFIGS[${PRIORS[td]%%:*}]"

	declare -n RUN_MODE="CONFIGS[${PSETS["run"]%%:*}]"
	declare -n PARAM_FILTER="CONFIGS[${PSETS["pf"]%%:*}]"

	declare -n NO_PFILTER='CONSTS["NO_PFILTER"]'
	declare -n PFILTER_ID='CONSTS["PFILTER_ID"]'
	declare -n FLD_SEP="CONSTS[FLD_SEP]"
	declare -n ELM_SEP="CONSTS[ELM_SEP]"

	# arrays for parsing result
	#   - BP_OPTIONS is the main result array for all types of Options
	#   - BP_STRINGS/BP_BOOLS are for storing string/bool type Options separately
	#   - BP POSITIONALS entries are all position parameters
	# BP_POSITIONALS defined as global array since it is always needed for run-mode Source,
	# while others defined as local arrays to reduce global variable usage and avoid potential
	# conflicts with user variables; for eval/capture, these arrays will not be used directly,
	# so it does not matter if they are global or local.

	declare -A "${CONFIGS[${PSETS["oan"]%%:*}]}"
	declare -A "${CONFIGS[${PSETS["san"]%%:*}]}"
	declare -A "${CONFIGS[${PSETS["ban"]%%:*}]}"
	declare -ga "${CONFIGS[${PSETS["pan"]%%:*}]}"

	declare -n BP_OPTIONS="${CONFIGS[${PSETS["oan"]%%:*}]}"
	declare -n BP_STRINGS="${CONFIGS[${PSETS["san"]%%:*}]}"
	declare -n BP_BOOLS="${CONFIGS[${PSETS["ban"]%%:*}]}"
	declare -n BP_POSITIONALS="${CONFIGS[${PSETS["pan"]%%:*}]}"

	# echo --------------------- >&2
	# echo $* >&2

	# process empty "$@"
	[[ $# -eq 0 || $* == '--' || $* == "${ZN_SEP}" ]] && {
		verbose=1
		exit_with_msg 2
	}

	# supper verbose for Priors parse monitoring
	local supers=() spr matched_spr
	# remove '~pf' from cml in case SLID included in PFILTER
	local CMLM=("$@") i
	for i in "${!CMLM[@]}"; do
		if [[ ${CMLM[i]} =~ ^\~pf= ]]; then
			unset "CMLM[i]"
			break
		fi
	done
	for spr in "${!SVERBOSE[@]}"; do
		if [[ ${CMLM[*]} =~ ${SLID}${spr} ]]; then
			matched_spr="${BASH_REMATCH[0]}"
			supers+=("${BASH_REMATCH[0]##*\~}")
		fi
	done

	update_verbose
	unset spr supers

	msg_bp 3 "Command line: " "$*"
	# echo "Command line: $*" >&2
	msg_bp -2 "verbose: " "${verbose}"

	reset_intermediate_arrays

	# check cml style
	update_cml_style "$@"
	# msg_bp 2 "CML style: ${CML_STYLE}"
	if [[ ${CML_STYLE} == "watershed" ]]; then
		# disassemble command line parameters
		msg_bp 2 "Extract Watershed-style CML"
		extract_watershed op_zone pp_zone "$@"
	else
		msg_bp 2 "Extract Islands-style CML"
		extract_islands op_zone pp_zone "$@"
	fi

	msg_bp 4 "op zone:" "${op_zone[*]}"
	msg_bp 4 "pp zone:" "${pp_zone[*]}"

	# in case no parameter supplied
	[[ ${#op_zone[@]} -eq 0 && ${#pp_zone[@]} == 0 ]] && exit_with_msg 2

	if [[ ${#op_zone[@]} -ne 0 ]]; then
		# option parameter supplied
		msg_bp 3 "Extract Priors"
		extract_options "${PRLID}" strings bools ligas op_zone

		# process Priors ---------------------------------------------
		# if no priors supplied, skip parsing priors
		if [[ ${#strings[@]} -ne 0 || ${#bools[@]} -ne 0 || ${#ligas[@]} -ne 0 ]]; then
			msg_bp 2 "Parse Priors"
			parse_options "${PRLID}" strings bools ligas

			msg_bp 3 "Validate Priors"
			validate_options_by_filter "${PRLID}" true

			# show_array CONFIGS "CF"

			msg_bp 3 "Apply Priors"
			apply_setup "Priors" PRIORS
			# unset "${super_verbose}"
			update_verbose

			reset_intermediate_arrays
			if [[ ${CONFIGS[${PRIORS["config"]%%:*}]} == true ]]; then
				# if config is true, show configs after parsing Priors
				show_configs
				# set config to false after showing configs, to avoid showing configs again
				# after parsing PSets
				CONFIGS["${PRIORS["config"]%%:*}"]=false
			# else
			# 	[[ ${verbose} -ge 3 ]] && show_configs
			fi

			# msg_bp 2 "CML stype: ${CML_STYLE}"
			if [[ ${CML_STYLE} == "watershed" ]]; then
				# re-extract zones for PSets and user Options, in case some prior settings changed
				msg_bp 2 "Extract Watershed-style CML Again"
				extract_watershed op_zone pp_zone "$@"
			else
				msg_bp 2 "Extract Islands-style CML Again"
				extract_islands op_zone pp_zone "$@"
			fi

			msg_bp 4 "op zone:" "${op_zone[*]}"
			msg_bp 4 "pp zone:" "${pp_zone[*]}"
		else
			msg_bp 3 "  no Priors supplied, skip parsing Priors"
		fi

		# Psets
		msg_bp 3 "Extract PSets"
		extract_options "${PLID}" strings bools ligas op_zone

		# parsing PSets ----------------------------------------------
		# in case no PSets supplied
		if [[ ${#strings[@]} -ne 0 || ${#bools[@]} -ne 0 || ${#ligas[@]} -ne 0 ]]; then
			msg_bp 2 "Parse PSets"
			parse_options "${PLID}" strings bools ligas

			msg_bp 3 "Validate PSets"
			validate_options_by_filter "${PLID}" true

			msg_bp 3 "Apply PSets"
			apply_setup "PSets" PSETS
			update_verbose

			# directives for some special PSets, which will not be output as user parameters but
			# executed directly in BosParse, e.g. show version or print Banner
			direct_pset_commands

			reset_intermediate_arrays false
			if [[ ${CONFIGS[${PSETS["config"]%%:*}]} == true ]]; then
				# if config is true, show configs after parsing PSets
				show_configs
			# else
			# 	[[ ${verbose} -ge 3 ]] && show_configs
			fi
		else
			msg_bp 3 "  no PSets supplied, skip parsing PSets"
		fi
		# PSet parsed, update run-mode in case not specified
		update_run_mode

		# parsing user parameters-------------------------------------
		msg_bp 2 "Extract user-options"
		extract_options "${ULID}" strings bools ligas op_zone

		msg_bp 2 "Parse user-options"
		parse_options "${ULID}" strings bools ligas

		if [[ ${#BP_OPTIONS[@]} -ne 0 ]] ||
			[[ ${CONFIGS["${PSETS["afd"]%%:*}"]} == true ]]; then
			validate_user_options
		fi
	else
		update_run_mode
	fi

	# parsing optional parameters ---------------------------------
	msg_bp 2 "Parse user-positionals"
	parse_positionals "${pp_zone[@]}"

	# output parsing result ---------------------------------------
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
	BP_PARSING_STAGE="Mission complete."
	msg_bp 3 "${BP_PARSING_STAGE}"
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
