# shellcheck shell=bash
# Module 09-main: Entry point, high-level orchestration, and global mutables
#   bosparse() -- main function, called when script is executed (not sourced)
#   Workflow: init configs -> detect style -> extract zones -> parse globals ->
#   parse Priors -> parse Specs -> parse User params -> parse Positionals -> output
#
#   bosparse_immutables()           -- create IMMUTABLES/BASH_VARS/LID_NAMES/TAG_NAMES
#   bosparse_update_mutables()      -- refresh LIDS/TAGS from CONFIGS
#   bosparse_require_bash_version() -- verify bash >= 4.4
#   bosparse_detect_run_mode()      -- auto-detect source vs eval vs capture
#   bosparse_emit_output()          -- dispatch to source/eval/capture output handler
#   bosparse_validate_input()       -- reject empty input, lone '--', or lone ZN_SEP
#   bosparse_finalize()             -- mark parsing complete (disables exit trace)
#   bosparse_parse_debug_flags()    -- extract __debug, __trace, etc. from CML
# --------------------------------------------------------------------------------
# create groups of immutables from HARNESSES
bosparse_immutables() {
	bp_derive_harness_entries_by_field "immutable" "imm" IMMUTABLES
	# CONFIGS value should be a validate shell variable name if the cluster contains BASH_VARS
	bp_derive_harness_entries_by_field "cluster" "bash_variable" BASH_VARS
	bp_derive_harness_entries_by_field "cluster" "lid" LID_NAMES
	bp_derive_harness_entries_by_field "cluster" "tag" TAG_NAMES
}

# refresh LIDS and TAGS associative arrays from current CONFIGS values
# must be called after any CONFIGS change that affects lid or tag cluster keys
bosparse_update_mutables() {
	local item
	for item in "${LID_NAMES[@]}"; do
		LIDS["${item}"]="${CONFIGS[${item}]}"
	done
	for item in "${TAG_NAMES[@]}"; do
		TAGS["${item}"]="${CONFIGS[${item}]}"
	done
}

# require a minimum Bash version and exit plainly if not available
bosparse_require_bash_version() {
	local major=${1:-4} minor=${2:-4}
	if ((BASH_VERSINFO[0] < major || (BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor))); then
		printf 'BosParse requires bash %d.%d or newer. Current: %d.%d\n' \
			"${major}" "${minor}" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" >&2
		exit 1
	fi
}

# run-mode detection
# detect the run-mode when 'auto' set in CONFIGS
bosparse_detect_run_mode() {
	local script_name=$1

	local run_mode=""
	declare -A config_run_mode=()

	if [[ ${script_name} != $(basename "$0") ]]; then
		bp_msg 3 "  Sourced, output option parameters as variables."
		run_mode="source"
	else
		# not source, assert with '~json'
		if [[ ${CONFIGS["json"]} == true ]]; then
			bp_msg 3 "  Not sourced, use run-mode 'capture' as 'json' specified."
			run_mode="capture"
		else
			bp_msg 3 "  Not sourced, use run-mode 'eval' as default"
			run_mode="eval"
		fi
	fi
	bp_set_configs 'run' "${run_mode}"
}

# dispatch parsed results to the appropriate output handler
# $1 - run mode: "source" (shell vars+arrays), "eval" (key=value), "capture" (JSON)
# $2 - nameref: options associative array
# $3 - nameref: positionals indexed array
bosparse_emit_output() {
	local -n OPTS_EMIT=$1 POS_EMIT=$2

	case ${CONFIGS["run"]} in
	source)
		bp_msg 2 "  Output as variables and arrays"
		bp_output_source_variables OPTS_EMIT
		bp_output_source_arrays OPTS_EMIT POS_EMIT
		;;
	eval)
		bp_msg 2 "  Output as eval statements"
		bp_output_eval OPTS_EMIT POS_EMIT
		;;
	capture)
		bp_msg 2 "  Output as JSON"
		bp_output_json OPTS_EMIT POS_EMIT
		;;
	*) ;;
	esac
}

# reject empty input, lone '--', or lone ZN_SEP (zone separator)
# exits 2 with verbose=1 if validation fails
bosparse_validate_input() {
	if [[ $# -eq 0 || "$*" == '--' || "$*" == "${CONFIGS[zs]}" ]]; then
		verbose=1
		local pros_tag[0]=""
		bp_exit_with_msg 2 pros_tag
	fi
}

# mark parsing as complete (disables the exit-trace handler in sourced mode)
# sets BP_PARSING_STAGE to "Mission complete." so bp_on_exit becomes a no-op
bosparse_finalize() {
	BP_PARSING_STAGE="Mission complete"
	bp_msg 1 "${BP_PARSING_STAGE}"
}

# extract debug flags (__trace, __debug, __extra, __standard, __quiet) from CML
# $1 - nameref: CML parameters array (modified in-place, debug tokens removed)
# $2 - nameref: DEBUG_CMDS mapping (flag name → debug key, e.g. __trace → TRACE)
# $3 - nameref: receives DEBUG_MAPS entries (e.g. DEBUG_MAPS[TRACE]=true)
# uses prefix matching for flexibility; skips tokens starting with "~pf"
bosparse_parse_debug_flags() {
	local -n params=$1
	local -n DEBUG_CMDS_ref=$2
	local -n DEBUG_MAPS_ref=$3

	local index matched cmd

	for index in "${!params[@]}"; do
		# skip PFILTER, which may contains debug-like strings
		[[ ${params[index]} == ~pf* ]] && continue
		if matched=$(bp_prefix_matching "${params[index]}" DEBUG_CMDS_ref); then
			bp_msg 3 "Debug Setting: ${matched}"
			cmd=$(bp_key_of_array_member "${matched}" DEBUG_CMDS_ref)
			DEBUG_MAPS_ref["${cmd}"]=true
			# strip debug indicator from CML
			unset 'params[index]'
		fi
	done
}

# main entry point: orchestrate the full parsing pipeline
# called when the script is executed (not sourced)
# flow: init configs → parse debug flags → validate input → service globals →
#       service priors → service specs → service users → infer run mode → emit output
# all CONFIGS, CONSTS, and derived arrays are declared and populated here,
# then made read-only before parsing begins
bosparse() {
	trap bp_on_exit EXIT

	local verbose=0
	local bosparse_script_path="$(realpath "${BASH_SOURCE[0]}")"
	local bosparse_script_name="${bosparse_script_path##*\/}"

	# echo2 "path: ${bosparse_script_path}"
	# echo2 "name: ${bosparse_script_name}"

	bosparse_require_bash_version 4 4
	BP_PARSING_STAGE="Mission begin"
	bp_msg 1 "${BP_PARSING_STAGE}"

	declare -A CONSTS HARNESSES CONFIGS EXIT_MSG
	declare -A VN_EXCEPTIONS PAS_EXCLUSIONS SYMNAMES MCG_TYPES DEBUG_CMDS
	declare -a HRNS_FLDS PFE_TYPES RESYMS REGEX_METAS

	bp_definitions \
		CONSTS \
		HARNESSES \
		CONFIGS \
		EXIT_MSG \
		VN_EXCEPTIONS \
		PAS_EXCLUSIONS \
		SYMNAMES \
		MCG_TYPES \
		DEBUG_CMDS \
		HRNS_FLDS \
		PFE_TYPES \
		RESYMS \
		REGEX_METAS

	local IMMUTABLES=() BASH_VARS=()
	local LID_NAMES=() TAG_NAMES=()
	declare -A LIDS=() TAGS=()
	bosparse_immutables
	bosparse_update_mutables

	# used as read-only globals:
	declare -r CONSTS HARNESSES EXIT_MSG VN_EXCEPTIONS \
		PAS_EXCLUSIONS SYMNAMES MCG_TYPES DEBUG_CMDS HRNS_FLDS \
		PFE_TYPES RESYMS REGEX_METAS IMMUTABLES

	# used as mutable globals:
	# verbose - update with 'bp_update_verbose()'
	# CONFIGS - update with 'bp_set_configs()'

	# extract initial validation and parse debug flags
	declare -A DEBUG_MAPS=()
	declare -a CML=("$@")
	bosparse_parse_debug_flags CML DEBUG_CMDS DEBUG_MAPS
	bp_update_verbose

	# restore original CML without debug flags for parsing stages
	set -- "${CML[@]}"

	bp_msg 3 "Command line: " "$*"
	bp_msg -3 "verbose: " "${verbose}"

	bosparse_validate_input "$@"

	# create entry fields caches: FILTER_ENTRY_CACHE
	declare -A FILTER_ENTRY_CACHE=()

	declare -a op_zone=() pp_zone=()

	BP_PARSING_STAGE="Mission service"

	bp_service_globals op_zone pp_zone CML
	bp_service_priors op_zone
	bp_service_specs op_zone

	declare -A option_variables=()
	bp_service_users op_zone option_variables

	bp_msg 1 "Output parsing result"
	[[ ${CONFIGS["run"]} == 'auto' ]] && bosparse_detect_run_mode "${bosparse_script_name}"

	bosparse_emit_output option_variables pp_zone 

	bosparse_finalize
}

__BP_READY=true # identifying BosParse used

if [[ $(basename "$(realpath "${BASH_SOURCE[0]}")") == $(basename "$0") ]]; then
	# not source
	bosparse "$@"
fi
