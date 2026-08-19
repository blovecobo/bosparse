# shellcheck shell=bash
#
# Module defs: Constants and harnesses definitions
#
#   bp_definitions() - populates CONSTS, HARNESSES, CONFIGS, EXIT_MSG, SYMNAMES, RESYMS, etc.
#
# This module defines the entire configuration surface of BosParse:
#   CONSTS         - true constants (array names, separators, version, banners)
#   HARNESSES      - all config params with all attributes (type, levels, mcg, immutability, default)
#   CONFIGS        - runtime config values derived from HARNESSES defaults + post-overrides
#   EXIT_MSG       - exit code to message mapping (developer variants at +100)
#   VN_EXCEPTIONS  - hyphen-to-underscore mapping for bash variable names
#   PAS_EXCLUSIONS - forbidden characters for certain config keys
#   SYMNAMES       - human-readable names for escapable special characters
#   MCG_TYPES      - mutual-correlate group type prefixes (d/D/e/m/M/r/u)
#   DEBUG_CMDS     - debug command indicators (__quiet, __trace, etc.)
#   HRNS_FLDS      - ordered list of HARNESSES field names
#   PFE_TYPES      - PFILTER entry types (string/bool/enum)
#   RESYMS         - reserved symbols for LIDs and separators
#   REGEX_METAS    - regex metacharacters for prefix-matching escaping
#
# HARNESSES fields (colon-separated):
#   field 1 - type       : bool | string | enum | resym
#   field 2 - type-arg   : enum values (pipe-separated), resym length, or empty
#   field 3 - mcg        : mutual-correlate group name (or empty)
#   field 4 - levels     : parser levels: global | prior | spec (pipe-separated)
#   field 5 - immutable  : imm if immutable at runtime, empty otherwise
#   field 6 - default    : default value for CONFIGS
#   field 7 - cluster    : lid | sep | tag | arr (auto-derived context group)
# --------------------------------------------------------------------------------

# populate all config maps
bp_definitions() {
	# idempotent guard
	[[ -z "${CONFIGS[*]:-}" ]] || return 0

	local -n CONSTANTS_ref=$1
	local -n HARNESSES_ref=$2
	local -n CONFIGS_ref=$3
	local -n EXIT_MSG_ref=$4
	local -n VN_EXCEPTIONS_ref=$5
	local -n PAS_EXCLUSIONS_ref=$6
	local -n SYMNAMES_ref=$7
	local -n MCG_TYPES_ref=$8
	local -n DEBUG_CMDS_ref=$9
	local -n HRNS_FLDS_ref=${10}
	local -n PFE_TYPES_ref=${11}
	local -n RESYMS_ref=${12}
	local -n REGEX_METAS_ref=${13}

	local ESC_PFX="_bp_${BASHPID}_${RANDOM}_"

	# -- HARNESSES FIELDS --
	HRNS_FLDS_ref=("type" "type-arg" "mcg" "levels" "immutable" "default" "cluster")

	# -- PFILTER entry types --
	PFE_TYPES_ref=("string" "bool" "enum")

	# -- Reserved symbols for LIDs and SEPs --
	RESYMS_ref=('~' '-' '=' '_' '+' '%' '@' '!')

	# -- Regex metacharacters for prefix-matching escaping --
	REGEX_METAS_ref=('\\' '.' '[' ']' '(' ')' '{' '}' '^' '$' '*' '+' '?' '|')

	# -- TRUE CONSTANTS - never mutated at runtime --
	CONSTANTS_ref=(
		["BANNER"]="Parsed by BosParse"
		["PFILTER_ID"]="PARAM_FILTER"

		["OAN"]="BP_Options"
		["PAN"]="BP_Positionals"

		["FLD_SEP"]=":"
		["ELM_SEP"]="|"

		["CML_STYLE"]="watershed|islands"

		["VERSION"]="0.2.3"
	)

	# -- MCG type prefix bp_definitions --
	MCG_TYPES_ref=(
		["dependency"]="enum:d"
		["Dependency"]="enum:D"
		["exclusion"]="enum:e"
		["master"]="enum:m"
		["Master"]="enum:M"
		["required"]="enum:r"
		["uniqueness"]="enum:u"
	)

	# -- SINGLE HARNESSES -- every config param, one line --
	# Fields: type : type-arg : mcg : levels : immutable : default : cluster
	#   defined in 'HRNS_FLDS'
	# Pipe | used as internal separator within fields
	HARNESSES_ref=(
		# -- CML style (global level) --
		["style"]="enum:watershed|islands::global::watershed:"
		# -- Zone separator (global level, cluster: sep) --
		["zs"]="resym:2::global::--:sep"

		# -- Infrastructure (global, immutable, cluster: sep) --
		# Defaults for these are set via post-loop overrides
		["fs"]="string:1:ug-sep:global:imm::sep"
		["es"]="string:1:ug-sep:global:imm::sep"
		["ep"]="string:::global:imm::sep"

		# -- LIDs (global level, cluster: lid) --
		["glid"]="resym:3::global:imm:~~~:lid"  # Global ~~~ level
		["plid"]="resym:2::global:imm:~~:lid"   # Prior ~~ level
		["slid"]="resym:1:ug-lid:global::~:lid" # Spec ~ level
		["ulid"]="resym:1:ug_lid:global::-:lid" # User param - level
		["llid"]="resym:2::global:imm:--:lid"   # User liga - level

		# -- Trailing tags / option-value separator (prior level) --
		["os"]="resym:1::prior::=:sep"
		["tt"]="resym:1:ug_tag:prior::+:tag"
		["tf"]="resym:1:ug_tag:prior::-:tag"
		["td"]="bool:::prior::true:tag"

		# -- Core runtime configs (spec level) --
		["run"]="enum:auto|source|capture|eval::spec::auto:"
		["json"]="bool:::prior|spec::false:"
		["dvo"]="bool:::spec::false:"
		["spr"]="bool:::spec::false:"

		# -- PFILTER related (spec level) --
		["pf"]="string::D-pfilter:spec:::"
		["pf_id"]="string:::spec:imm:PARAM_FILTER:"
		["rup"]="bool::d-pfilter:spec::true:"
		["afd"]="bool::d-pfilter:spec::true:"
		["pme"]="bool::d-pfilter:spec::true:"

		# -- Output array names (spec level, cluster: bash_variable) --
		["oan"]="string::ug-an:spec:::bash_variable"
		# ["ban"]="string::ug-an:spec::BP_Bools:bash_variable"
		# ["san"]="string::ug-an:spec::BP_Strings:bash_variable"
		# ["pan"]="string::ug-an:spec::BP_Positionals:bash_variable"
		["pan"]="string::ug-an:spec::BP_Positionals:bash_variable"

		# -- Directives (spec level) --
		["Banner"]="bool::eg-directive:spec::false:"
		["Defaults"]="bool::eg-directive:spec::false:"
		["Help"]="bool::eg-directive:spec::false:"
		["Resymbols"]="bool::eg-directive:spec::false:"
		["Version"]="bool::eg-directive:spec::false:"

		# -- Runtime output control (all levels) --
		["config"]="bool:::global|prior|spec::false:"
		["quiet"]="bool:::global|prior|spec::true:"
		["standard"]="bool:::global|prior|spec::false:"
		["extra"]="bool:::global|prior|spec::false:"
		["debug"]="bool:::global|prior|spec::false:"
		["trace"]="bool:::global|prior|spec::false:"
	)

	# -- Derive CONFIGS from HARNESSES defaults --
	local index key fields=() target="default"
	# locate the field match $target
	for index in "${!HRNS_FLDS_ref[@]}"; do
		[[ ${HRNS_FLDS_ref[index]} == "${target}" ]] || continue
		break
	done
	# load $target field to CONFIGS
	for key in "${!HARNESSES_ref[@]}"; do
		readarray -d: -t fields <<<"${HARNESSES_ref[${key}]}"
		fields[-1]="${fields[-1]%$'\n'}"
		CONFIGS_ref["${key}"]="${fields[index]}"
	done

	# -- Post-loop overrides (defaults that need computed values) --
	CONFIGS_ref["ep"]="${ESC_PFX}"
	# -- Post-loop overrides (defined in CONSTANTS_ref) --
	CONFIGS_ref["fs"]="${CONSTANTS_ref[FLD_SEP]}"
	CONFIGS_ref["es"]="${CONSTANTS_ref[ELM_SEP]}"
	# CONFIGS_ref["oan"]="${CONSTANTS_ref[OAN]}"
	CONFIGS_ref["pan"]="${CONSTANTS_ref[PAN]}"

	# -- Short→long name mapping (for documentation only, not used at runtime) --
	declare -A CFG_NMS_ref=(
		["style"]="style_of_commandline" # CML style, watershed[default]|islands

		["run"]="run_mode"                # dictate output method, auto[default]|eval|capture
		["json"]="output_as_json"         # specify capture mode if 'run' not specified
		["dvo"]="disable_variable_output" # output variables via arrays only in source mode
		["spr"]="show_parsed_variables"   # show parsed result in source-mode on stderr

		["Banner"]="directive_banner"            # show Banner
		["Defaults"]="directive_default_configs" # show CONFIGS after Specs parsing
		["Help"]="directive_help"                # show online help
		["Resymbols"]="directive_resyms"         # show reserved symbols
		["Version"]="directive_version"          # show current BosParse version

		["pf"]="param_filter"             # pass PFILTER, may be nameref, ELM-stream or KV sequence
		["pf_id"]="pfilter_id"            # key of PFILTER-ID in PFILTER
		["rup"]="all_matching_filter"     # restrict unknown parameters
		["afd"]="apply_filter_defaults"   # appliy PFILTER devault values for un-grouped entries
		["pme"]="prefix_matching_enabled" # enable prefix-matching on user params and enum list
		["oan"]="options_array_name"      # array name contains parsed Options
		["pan"]="positionals_array_name"  # array name contains parsed Positionals

		["glid"]="global_lid"         # LID of Globals
		["plid"]="prior_lid"          # LID of Priors
		["slid"]="spec_lid"           # LID of Specs
		["ulid"]="user_lid"           # LID of Usser-params
		["zs"]="zn_sep"               # ZONE separator
		["os"]="ov_sep"               # separator for Option name and value
		["fs"]="filter_field_sep"     # field seperator in PFILTER entries
		["es"]="filter_element_sep"   # element separator in PFILTER entry fields
		["tt"]="trailing_tag_true"    # trailing-tag for 'true'
		["tf"]="trailing_tag_false"   # traiiing-tag for 'false'
		["td"]="trailing_tag_default" # default value if trailing-tag omitted

		["ep"]="escape_prefix" # escape prefix for symbol escaping

		["config"]="bp_show_config" # show CONFIGS
		["quiet"]="quiet"           # verbose level 0
		["standard"]="standard"     # verbose level 1
		["extra"]="extra"           # verbose level 2
		["debug"]="debug"           # verbose level 3
		["trace"]="trace"           # verbose level 4
	)

	PAS_EXCLUSIONS_ref=(
		["os"]="-_"
		["tt"]="="
		["tf"]="="
	)

	# -- Escape symbol names --
	SYMNAMES_ref=(
		["&"]="AMPERSAND"
		["\\"]="BACKSLASH"
		['`']="BACKTICK"
		[':']="COLON"
		['$']="DOLLAR_SIGN"
		['"']="DOUBLE_QUOTE"
		['!']="EXCLAMATION"
		['>']="GREATER_THAN"
		['<']="LESS_THAN"
		['?']="QUESTION"
		["'"]="SINGLE_QUOTE"
		['/']="SLASH"
		[' ']="SPACE"
		['~']="TILDE"
		['|']="VERTICAL_BAR"
		['(']="PARENTHESIS_LEFT"
		[')']="PARENTHESIS_RIGHT"
		['[']="BRACKET_LEFT"
		[']']="BRACKET_RIGHT"
		['{']="BRACE_LEFT"
		['}']="BRACE_RIGHT"
	)

	# -- Exceptions for bash variable naming (hyphen → underscore) --
	VN_EXCEPTIONS_ref=(
		['-']="_"
	)

	# -- Debug commands (testing only, not used in production) --
	DEBUG_CMDS_ref=(
		["QUIET"]="__quiet"
		["STANDARD"]="__standard"
		["EXTRA"]="__extra"
		["DEBUG"]="__debug"
		["TRACE"]="__trace"
	)

	# -- Exit messages --
	EXIT_MSG_ref=(
		["0"]="Parsing succeeded."
		["1"]="Parsing failed."
		["2"]="No parameter supplied."
		["3"]="Unknown error"
		["4"]="\${pros_tag[0]}"

		# system
		["10"]="'\${pros_tag[0]}' required but not available."
		["110"]="Functionalities deal with \${pros_tag[1]} required '\${pros_tag[0]}' but not available."

		# Basic parsing (without PFILTER)
		["20"]="Only one ZONE-SEP '\${pros_tag[0]}' permitted but '\${pros_tag[1]}' SEPs found."
		["21"]="Unknown '\${pros_tag[0]}"
		["121"]="A solitary argument '\${pros_tag[0]}' found, parsing failed."

		["22"]="Invalid \${pros_tag[0]}: '\${pros_tag[1]}', contains special character(s) '\${pros_tag[2]}'"
		["122"]="Parameter name '\${pros_tag[0]}' contains invalid character(s) '\${pros_tag[1]}', it should respect the Bash variable name convention."

		["23"]="Invalid \${pros_tag[0]}: '\${pros_tag[1]}', starts with a number '\${pros_tag[2]}'"

		["24"]="Invalid parameter '\${pros_tag[0]}' in LIGA '\${pros_tag[1]}'"
		["124"]="Parameter '\${pros_tag[0]}' in LIGA '\${pros_tag[1]}' not a valid Bash variable name."

		["25"]="Invalid LIGA name '\${pros_tag[0]}', length mismatch."
		["125"]="Invalid LIGA name '\${pros_tag[0]}', length of LIGA name '\${pros_tag[1]}' should be multiple of member length '\${pros_tag[2]}'"

		["26"]="Empty \${pros_tag[0]} found."
		["126"]="Found an empty \${pros_tag[0]}, perhaps input error."

		# Global/Priors/Specs
		["27"]="Invalid \${pros_tag[0]} \${pros_tag[1]}, \${pros_tag[2]}"
		["28"]="Invalid Prior setting '\${pros_tag[0]}' when using 'islands' style CML."

		# escape symbol
		["29"]="Cannot escape symbol, \${pros_tag[0]}"

		# Validate PFILTER
		["30"]="Specs '~rup' requires a 'PFILTER'(by ~pf) but not supplied."
		["31"]="Invalid PFILTER: \${pros_tag[0]}"
		["32"]="Invalid PFILTER key name '\${pros_tag[0]}' in PFILTER, it should be a valid shell variable name."
		["33"]="Invalid PFILTER entry '\${pros_tag[0]}' type '\${pros_tag[1]}', it should be one of '\${pros_tag[2]}'"
		["34"]="Invalid PFILTER entry '\${pros_tag[0]}': default value '\${pros_tag[2]}' mismatch the type '\${pros_tag[1]}'"
		["35"]="Invalid PFILTER enum entry \${pros_tag[0]}: missing enum values."
		["36"]="MCG member(s) '\${pros_tag[0]}' in '\${pros_tag[1]}' depends on the D-member but not found in PFILTER."
		["37"]="Invalid MCG name '\${pros_tag[0]}', \${pros_tag[1]}."
		["38"]="Exclusion MCG '\${pros_tag[0]}' should have at least two members, but found only one: '\${pros_tag[1]}'"
		["39"]="Invalid Master MCG '\${pros_tag[0]}' setting, \${pros_tag[1]}"

		# PFILTER-MCG
		["41"]="Parameters '\${pros_tag[1]}' should not be given the same value."
		["141"]="Same settings found among Uniqueness MCG '\${pros_tag[0]}' members: '\${pros_tag[1]}'"

		["42"]="Parameters '\${pros_tag[1]}' cannot be supplied at same time."
		["142"]="Only one parameters in Exclusion MCG '\${pros_tag[0]}' can be supplied, but found: '\${pros_tag[1]}'"

		["45"]="Only one of the parameters '\${pros_tag[0]}' should be supplied."
		["145"]="M-members '\${pros_tag[0]}' of Master MCG '\${pros_tag[1]}' cannot supplied at sametime."

		["46"]="\${pros_tag[0]} required by '\${pros_tag[1]}' but not supplied."
		["146"]="\${pros_tag[0]} in Dependency MCG '\${pros_tag[2]}' required by '\${pros_tag[1]}'"

		["47"]="Invalid parameter '\${pros_tag[0]}', use one of '\${pros_tag[1]}'"
		["147"]="Parameter '\${pros_tag[0]}' is an m-member of Master MCG '\${pros_tag[2]}', setting it by one of the parameters: '\${pros_tag[1]}'"

		["48"]="Needs one of the  parameters '\${pros_tag[1]}' supplied."
		["148"]="No M-member of Master MCG '\${pros_tag[0]}' supplied, needs one of '\${pros_tag[1]}'"

		["49"]="Invalid \${pros_tag[0]} '\${pros_tag[1]}' in PFILTER, the value should be one of '\${pros_tag[2]}'"
		["149"]="Invalid \${pros_tag[0]} '\${pros_tag[1]}' in PFILTER, the value should be one of '\${pros_tag[2]}'"

		# filter parameter with PFILTER
		["50"]="Invalid \${pros_tag[0]} \${pros_tag[1]}, the value should be one of '\${pros_tag[2]}'"
		["150"]="Invalid enum entry value: \${pros_tag[1]}, available enums: '\${pros_tag[2]}'"

		["51"]="Invalid setting: \${pros_tag[1]}"
		["151"]="Invalid \${pros_tag[0]} setting: \${pros_tag[1]}, value should be \${pros_tag[2]}"

		["52"]="Invalid \${pros_tag[0]} setting \${pros_tag[1]}: \${pros_tag[2]}"

		["53"]="Unknown \${pros_tag[0]} '\${pros_tag[1]}'"
		["153"]="Specs '~rup' requires all parameters defined in 'PFILTER' but '\${pros_tag[1]}' didn't."

		["54"]="Unknown \${pros_tag[0]} '\${pros_tag[1]}'"
		["154"]="Invalid \${pros_tag[0]} '\${pros_tag[1]}', cannot match any of \${pros_tag[0]}."

		["55"]="Missing parameter '\${pros_tag[0]}'"
		["155"]="Un-supplied parameter '\${pros_tag[0]}' requires a default value by '~afd'"

		["56"]="Ambiguous \${pros_tag[0]} '\${pros_tag[1]}' found, may be one of '\${pros_tag[2]}'?"
		["156"]="Ambiguous \${pros_tag[0]} '\${pros_tag[1]}', multiple matched: '\${pros_tag[2]}'."

		["57"]="Parameter '\${pros_tag[1]}' has the same name as '\${pros_tag[0]}' but a different type."

		["58"]="Parameter name conflict: '\${pros_tag[1]}' vs '\${pros_tag[0]}'"
		["158"]="PFILTER entry name '\${pros_tag[1]}' conflict with parameter name '\${pros_tag[0]}' after exception substitution."

		["70"]="Parameter '\${pros_tag[1]}' is required but not supplied."
		["170"]="Parameter '\${pros_tag[1]}' in Required MCG '\${pros_tag[0]}' without default value and not supplied."
	)
}
