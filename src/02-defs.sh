# shellcheck shell=bash
# Module 02-defs: Constants and definitions
#   consts()     — immutable constants (array names, separators, version, etc.)
#   definitions() — all configuration schemas, defaults, exit messages, and reserved symbols
#   validate_variable_name() — validates & normalizes shell variable names
#
# This module defines the entire configuration surface of BosParse:
#   CONFIGS   — runtime configuration key-value store
#   CONSTS    — immutable constants (separators, array names)
#   SUPERS    — super-verbose definitions (~~~~slid, ~~~~prlid, ~~~~style, verbose flags)
#   PRIORS    — prior (~~~) definitions, parsed before PSets
#   PSETS     — parser-set (~) definitions, parsed after Priors
#   MCG_TYPES — mutual-correlate group type prefixes (d/D/e/m/M/r/u)
#   RESYMS    — reserved symbols for LIDs and separators
#   EXCEPTIONS — hyphen-to-underscore mapping for bash variable names
#   SYMNAMES   — human-readable names for escapable special characters
#   EXIT_MSG   — exit code to message mapping (with developer variants at +100)
# --------------------------------------------------------------------------------

# populate immutable constants: array names, separators, version, etc.
function consts {
	local -n CONSTANTS_ref2=$1
	local -n PFILTER_ENTRY_TYPES_ref2=$2

	CONSTANTS_ref2=(
		["BANNER"]="Parsed by BosParse" # identifying BosParse used

		["NO_PFILTER"]="no-param-filter" # identifying no PFILTER supplied
		["PFILTER_ID"]="PARAM-FILTER"    # use it as an array key to identify a valid PFILTER

		["OAN"]=BP_Options     # name of array to store Option parameters
		["SAN"]=BP_Strings     # name of array to store String-Options
		["BAN"]=BP_Bools       # name of array to store Bool-Options
		["PAN"]=BP_Positionals # name of array to store Positional parameters

		["FLD_SEP"]=":"
		["ELM_SEP"]="|"
		["CML_STYLE"]="watershed|islands"

		["VERSION"]="0.2.0" # version of BosParse
	)
	PFILTER_ENTRY_TYPES_ref2=(
		"string"
		"bool"
		"enum"
	)
}

# populate all config maps: CONFIGS, CONSTS, SUPERS, PRIORS, PSETS, EXIT_MSG, etc.
function definitions {
	local -n CONFIGS_ref=$1
	local -n CONSTANTS_ref=$2
	local -n PSETS_ref=$3
	local -n PRIORS_ref=$4
	local -n SUPERS_ref=$5
	local -n RESYMS_ref=$6
	local -n EXCEPTIONS_ref=$7
	local -n EXIT_MSG_ref=$8
	local -n PFILTER_ENTRY_TYPES_ref=$9
	local -n MCG_TYPES_ref=${10}
	local -n SYMNAMES_ref=${11}

	consts \
		CONSTANTS_ref \
		PFILTER_ENTRY_TYPES_ref

	# BOSPARSE_PARAMETER_NAME
	# running and output(3)
	local run="run_mode"
	local json="output_as_json"
	local dvo="disable_variable_output"
	# local eoe="exit_on_error"

	# parsing style(2)
	local prem="prefix_matching_enabled"
	local style="style_of_commandline"

	# directives(5)
	local Banner="directive_banner"
	local Defaults="directive_default_configs"
	local Resymbols="directive_resyms"
	local Version="directive_version"
	local Help="directive_help"

	# FILTER(5)
	local pf="param_filter"
	local pf_id="pfilter_id"
	local rup="all_matching_filter"
	local afd="apply_pfilter_defaults"

	# array for results(4)
	local oan="options_array_name"
	local ban="bools_array_name"
	local san="strings_array_name"
	local pan="positionals_array_name"

	# parsing-aid sympbols(11)
	local slid="super_lid"
	local prlid="prior_lid"
	local plid="pset_lid"
	local ulid="option_lid"
	local tt="trailing_tag_true"
	local tf="trailing_tag_false"
	local td="trailing_tag_default"
	local zs="zn_sep"
	local os="oa_sep"
	local fs="filter_field_sep"
	local es="filter_element_sep"

	# output control(6)
	local config="show_config"
	local quiet="quiet"
	local standard="standard"
	local extra="extra"
	local debug="debug"
	local trace="trace"

	# not used, for memo only
	declare -A CONFIG_PARAMS_ref=(
		["run"]="${run}"
		["json"]="${json}"

		["prem"]="${prem}"
		["dvo"]="${dvo}"

		["Defaults"]="${Defaults}"
		["Banner"]="${Banner}"
		["Resymbols"]="${Resymbols}"
		["Version"]="${Version}"
		["Help"]="${Help}"

		["pf"]="${pf}"
		["pf_id"]="${pf_id}"
		["rup"]="${rup}"
		["afd"]="${afd}"

		["oan"]="${oan}"
		["ban"]="${ban}"
		["san"]="${san}"
		["pan"]="${pan}"

		["slid"]="${slid}"
		["prlid"]="${prlid}"
		["plid"]="${plid}"
		["ulid"]="${ulid}"
		["tt"]="${tt}"
		["tf"]="${tf}"
		["td"]="${td}"
		["zs"]="${zs}"
		["os"]="${os}"
		["fs"]="${fs}"
		["es"]="${es}"

		["config"]="${config}"
		["quiet"]="${quiet}"
		["standard"]="${standard}"
		["extra"]="${extra}"
		["debug"]="${debug}"
		["trace"]="${trace}"
	)

	# SUPERS_ref/PRIORS_ref/PSETS_ref used to define Supers/Priors/PSets
	# SUPERS: lid of Super Verbose params & Prior PSets; CML style
	# PRIORS: PAS devinition; output control during PSets parsing
	# PSETS: Paser sets; PFILTER setting
	#
	# setting schema:
	#   field1: entry key in CONFIGS                 | string
	#	field2: data type                            | string
	#	        may be bool, string, resym or enum
	#   field3: for strings: length                  | integer(1 if omitted)
	#           for bools: n/a                       | empty
	#           for resyms: length and/or exclusions | integer and/or resym-excluded
	#           for emums: enum values               | strings separated by '|'
	#   field4: mcg names                            | string(mutual correlate group)
	#           for parameters interfered each other
	#             - dependency, group name start with 'd|D'
	#             - exclusion, group name start with 'e'
	#             - master, group name start with 'm|M'
	#             - required, group name start with 'r'
	#             - uniqueness, group name start with 'u'

	SUPERS_ref=(
		["slid"]="${slid}:resym:4"
		["prlid"]="${prlid}:resym:3"
		["style"]="${style}:enum:watershed|islands"
		["quiet"]="${quiet}:bool::eg_sv"
		["standard"]="${standard}:bool::eg_sv"
		["extra"]="${extra}:bool::eg_sv"
		["debug"]="${debug}:bool::eg_sv"
		["trace"]="${trace}:bool::eg_sv"
	)
	PRIORS_ref=(

		["plid"]="${plid}:resym::ug_lid"
		["ulid"]="${ulid}:resym::ug_lid"

		["zs"]="${zs}:resym:2"
		["os"]="${os}:resym:-_:ug_ttag" # in case missmatch param-name or tags
		["tt"]="${tt}:resym:=:ug_ttag"  # in case `-param=`
		["tf"]="${tf}:resym:=:ug_ttag"
		["td"]="${td}:bool"

		["config"]="${config}:bool:"
		["quiet"]="${quiet}:bool::"
		["standard"]="${standard}:bool::"
		["extra"]="${extra}:bool::"
		["debug"]="${debug}:bool::"
		["trace"]="${trace}:bool::"
	)

	PSETS_ref=(
		["run"]="${run}:enum:auto|source|capture|eval"
		["json"]="${json}:bool"
		["dvo"]="${dvo}:bool"

		["Defaults"]="${Defaults}:bool::eg-directive"
		["Help"]="${Help}:bool::eg-directive"
		["Banner"]="${Banner}:bool::eg-directive"
		["Resymbols"]="${Resymbols}:bool::eg-directive"
		["Version"]="${Version}:bool::eg-directive"

		["pf"]="${pf}:string::D-pfilter"
		["rup"]="${rup}:bool::d-pfilter"
		["afd"]="${afd}:bool::d-pfilter"
		["prem"]="${prem}:bool::d-pfilter"

		["oan"]="${oan}:string::umcg_arr_name"
		["ban"]="${ban}:string::umcg_arr_name"
		["san"]="${san}:string::umcg_arr_name"
		["pan"]="${pan}:string::umcg_arr_name"

		["config"]="${config}:bool:"
		["quiet"]="${quiet}:bool::"
		["standard"]="${standard}:bool::"
		["extra"]="${extra}:bool::"
		["debug"]="${debug}:bool::"
		["trace"]="${trace}:bool::"
	)

	MCG_TYPES_ref=(
		["dependency"]="enum:d"
		["Dependency"]="enum:D"
		["exclusion"]="enum:e"
		# ["Exclusion"]="enum:E"
		["master"]="enum:m"
		["Master"]="enum:M"
		["required"]="enum:r" # all r- group members are all required
		["uniqueness"]="enum:u"
	)

	# reserved symbols for LIDs and SEPs
	RESYMS_ref=(
		'~'
		'-'
		'='
		'_'
		'+'
		'%'
		'@'
		'!'
	)

	declare -A prior_resyms=(
		["all"]="${RESYMS_ref[@]}"
		["${plid}"]="~-=_+%@!" # except:
		["${ulid}"]="~-=_+%@!" # except:

		["${zs}"]="~-=_+%@!" # except:
		["${os}"]="~=+%@!"   # except: -_
		["${tt}"]="~-_+%@!"  # except: =
		["${tf}"]="~-_+%@!"  # except =
	)

	# escape symbles
	SYMNAMES_ref=(
		["&"]="AMPERSAND"
		# ['\']="BACK_SLASH"
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

	# exceptions for bash variable naming convention, replacing hyphens with underscores
	EXCEPTIONS_ref=(
		['-']="_"
	)

	# BosParse configs
	CONFIGS_ref=(
		# running mode
		["${run}"]=auto   # ~run, run-mode, maybe "source", "eval" or "capture"
		["${json}"]=false # ~json, output  to stdout as json
		# ["${eoe}"]=false  # exit on errors
		["${dvo}"]=false # disable variables output, for source mode only to avoid param names conflict

		# parsing style
		["${style}"]="${CONSTANTS_ref[CML_STYLE]%|*}" # cml style, watershed|islands

		# directives
		["${Defaults}"]=false  # ~Defaults, output CONFIGS to stdout
		["${Help}"]=false      # ~Help, show help
		["${Banner}"]=false    # ~Banner, show banner
		["${Resymbols}"]=false # ~Resymbols, show reserved symbols
		["${Version}"]=false   # ~Version, show version

		# filter related
		["${pf}"]="${CONSTANTS_ref[NO_PFILTER]}"    # filter or a mark for unsupplied
		["${pf_id}"]="${CONSTANTS_ref[PFILTER_ID]}" # the key in PFILTER to identify itself
		# mandatories
		["${prem}"]=true # enable prefix-matching for user params
		["${rup}"]=true  # restrict parameters not defined in PFILTER
		["${afd}"]=true  # apply PFILTER defaults for un-supplied parameters(exclude mcg-members)

		# parse result arrays
		["${oan}"]="${CONSTANTS_ref["OAN"]}" # ~oan, name of array to store Options
		["${ban}"]="${CONSTANTS_ref["BAN"]}" # ~ban, name of array to store Bool-Options
		["${san}"]="${CONSTANTS_ref["SAN"]}" # ~san, name of array to store String-Options
		["${pan}"]="${CONSTANTS_ref["PAN"]}" # ~pan, name of array to store Positionals

		# runtime output control
		["${config}"]=false  # ~/~~~config, output current CONFIGS after a parsing stage
		["${quiet}"]=false   # ~/~~~quiet    output level, 0
		["${standard}"]=true # ~/~~~standard output level, 1(default)
		["${extra}"]=false   # ~/~~~extra    output level, 2
		["${debug}"]=false   # ~/~~~debug    output level, 3
		["${trace}"]=false   # ~/~~~trace    output level, 4

		# Parsing-aid symbols
		# lids
		["${slid}"]='~~~~'
		["${prlid}"]='~~~' # ~~~prlid,  leading id sighn for priors, psets and seps
		["${plid}"]='~'    # ~~~plid,   leading id sign for setting-parameters
		["${ulid}"]='-'    # ~~~ulid,   leading id sign for user-parameters
		# separators
		["${zs}"]='--' # ~~~zs, separator between VAR_ZONE and PP_ZONE
		["${os}"]='='  # ~~~os, separator between parameter names and their args
		# separators reserved for configs
		["${fs}"]="${CONSTANTS_ref["FLD_SEP"]}" # setup-banned
		["${es}"]="${CONSTANTS_ref["ELM_SEP"]}" # setup-banned
		# trailing-tags
		["${tt}"]='+'  # ~~~tt, tag character for 'true'
		["${tf}"]='-'  # ~~~tf, tag character for 'false'
		["${td}"]=true # ~~~td, defaut tag value(when tag omitted)
	)

	EXIT_MSG_ref=(
		["0"]="Parsing succeeded."
		["1"]="Parsing failed."
		["2"]="No parameter supplied."
		["3"]="\${pros_tag}"

		# system
		["10"]="'jq' required but not available."
		["110"]="Functionalities deal with JSON required 'jq' but not available."

		# Basic parsing(without PFILTER)
		["20"]="Only one ZONE-SEP '\${pros_tag}' permitted but '\${pros_tag2}' SEPs found."

		["21"]="Unknown parameter '\${pros_tag}'"
		["121"]="A solitary ARG '\${pros_tag}' found, parsing failed."

		["22"]="Invalid Parameter: '\${pros_tag}', contains special character(s) '\${pros_tag2}'"
		["122"]="Parameter name '\${pros_tag}' contains invalid character(s) '\${pros_tag2}', it should respect the Bash variable name convention."

		["23"]="Invalid parameter: '\${pros_tag}', start with a number '\${pros_tag2}'"
		["123"]="Parameter name '\${pros_tag}' start with number '\${pros_tag2}', it should respect the Bash variable name convention."

		["24"]="Invalid parameter '\${pros_tag}' in LIGA '\${pros_tag2}'"
		["124"]="Parameter '\${pros_tag}' in LIGA '\${pros_tag2}' not a valid Bash variable name."

		["25"]="Invalid LIGA name '\${pros_tag}', length mismatch."
		["125"]="Invalid LIGA name '\${pros_tag}', length of LIGA name '\${pros_tag2}' should be multiple of member length '\${pros_tag3}'"

		# an empty parameter
		["26"]="Empty parameter found."
		["126"]="Found an empty parameter, perhaps input error."

		# Priors/PSets
		["27"]="Invalid \${pros_tag} '\${pros_tag2}', \${pros_tag3}"

		["28"]="Invalid Prior setting '\${pros_tag}' when using 'islands' style CML."

		# Validate PFILTER
		["30"]="PSet '~rup' requires a 'PFILTER'(by ~pf) but not supplied."

		["31"]="Invalid PFILTER: \${pros_tag}"

		["32"]="Invalid parameter name '\${pros_tag}' in PFILTER, it should be a valid shell variable name."

		["33"]="Invalid PFILTER entry type '\${pros_tag}', it should be one of '\${pros_tag2}'"

		["34"]="Invalid PFILTER entry '\${pros_tag}': default value '\${pros_tag3}' mismatch the type '\${pros_tag2}'"

		["35"]="Invalid PFILTER enum entry \${pros_tag}: missing enum values."

		["36"]="MCG member(s) '\${pros_tag}' in '\${pros_tag2}' depends on the D-member but not found in PFILTER."

		["37"]="Invalid MCG name '\${pros_tag}', \${pros_tag2}."
		# ["137"]="MCG name '\${pros_tag}' should satisfy MCG_TYPES, starting with '\${pros_tag2}'"

		# # multiple D-members allowed now
		# ["38"]="Only one D-member in \${pros_tag} MCG '\${pros_tag2}' permitted, but multiple found: '\${pros_tag3}'"

		["38"]="Exclusion MCG '\${pros_tag}' should have at least two members, but found only one: '\${pros_tag2}'"

		["39"]="Invalid Master MCG '\${pros_tag}' setting, \${pros_tag2}"

		# PFILTER-MCG
		["41"]="Parameters '\${pros_tag2}' should not be given the same value." # uniqueness(used)
		["141"]="Same settings found among Uniqueness MCG '\${pros_tag}' members: '\${pros_tag2}'"

		["42"]="Parameters '\${pros_tag2}' cannot be supplied at same time." # exclusion
		["142"]="Only one parameters in Exclusion MCG '\${pros_tag}' can be supplied, but found: '\${pros_tag2}'"

		["45"]="Only one of the parameters '\${pros_tag}' should be supplied."
		["145"]="M-members '\${pros_tag}' of Master MCG '\${pros_tag2}' cannot supplied at sametime."

		["46"]="\${pros_tag} required by '\${pros_tag2}' but not supplied." # dependency
		["146"]="\${pros_tag} in Dependency MCG '\${pros_tag3}' required by '\${pros_tag2}'"

		["47"]="Invalid parameter '\${pros_tag}', use one of '\${pros_tag2}'"
		["147"]="Parameter '\${pros_tag}' is an m-member of Master MCG '\${pros_tag3}', setting it by one of the parameters: '\${pros_tag2}'"

		["48"]="Needs one of the  parameters '\${pros_tag2}' supplied." # no supplied M-member and no default value
		["148"]="No M-member of Master MCG '\${pros_tag}' supplied, needs one of '\${pros_tag2}'"

		["49"]="Invalid \${pros_tag} '\${pros_tag2}' in PFILTER, the value should be one of '\${pros_tag3}'"    # enum check(used)
		["149"]="Invalid \${pros_tag} '\${pros_tag2}' in PFILTER, the value should be one of '\${pros_tag3}'" # bool/string/resym check(used)

		# filter parameter with PFILTER
		["50"]="Invalid \${pros_tag} \${pros_tag2}, the value should be one of '\${pros_tag3}'" # enum check(used)
		["150"]="Invalid enum entry value: \${pros_tag2}, available enums: '\${pros_tag3}'"

		["51"]="Invalid setting: \${pros_tag2}" # bool/string/resym type check
		["151"]="Invalid \${pros_tag} setting: \${pros_tag2}, ARG should be \${pros_tag3}"

		["52"]="Invalid \${pros_tag} setting \${pros_tag2}: \${pros_tag3}" # assert resym

		["53"]="Unknown parameter '\${pros_tag2}'" # for user parameter
		["153"]="PSet '~rup' requires all parameters matching 'PFILTER' but '\${pros_tag}' didn't."

		["54"]="Unknown \${pros_tag} '\${pros_tag2}'" # for Priors/PSets
		["154"]="Invalid \${pros_tag} '\${pros_tag2}', cannot match any \${pros_tag}."

		["55"]="Missing parameter '\${pros_tag}'" # un-supplied and no default
		["155"]="Un-supplied parameter '\${pros_tag}' requires a default value by '~afd'"

		["56"]="Unrecognized \${pros_tag} '\${pros_tag2}', may be one of '\${pros_tag3}'?" # assert multi-prefix-matching
		["156"]="Invalid \${pros_tag} '\${pros_tag2}', multiple matched: '\${pros_tag3}'."

		["70"]="Parameter '\${pros_tag2}' is required but not supplied."
		["170"]="Parameter '\${pros_tag2}' in Required MCG '\${pros_tag} without default value and not supplied."
	)
}

# validate and normalize a shell variable name; apply EXCEPTIONS substitution
function validate_variable_name {
	local -n var_name_ref="$1"
	local return_on_error=${2:-false} # return if invalid instead of exit with a message

	[[ -n "${var_name_ref}" ]] || exit_with_msg 26
	pros_tag="${var_name_ref}"

	# leading or trailing hyphens are not allowed (would break LID/trailing-tag parsing)
	if [[ ${var_name_ref} == -* ]] || [[ ${var_name_ref} == *- ]]; then
		if [[ ${return_on_error} == true ]]; then
			return 1
		fi
		pros_tag2="-"
		exit_with_msg 22
	fi

	# substitute exceptions (hyphen → underscore), then validate as bare variable name
	local original="${var_name_ref}"
	substitute_exceptions var_name_ref

	if [[ ${var_name_ref} =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		return 0
	fi

	if [[ ${return_on_error} == true ]]; then
		var_name_ref="${original}"
		return 1
	fi

	if [[ ${var_name_ref:0:1} == [0-9] ]]; then
		pros_tag2="${var_name_ref:0:1}"
		exit_with_msg 23
	fi

	if [[ ! ${var_name_ref} =~ ^[a-zA-Z0-9_]+$ ]]; then
		pros_tag2="${var_name_ref//[a-zA-Z0-9_]/}"
		exit_with_msg 22
	fi
	exit_with_msg 21
}

declare -ra BP_REGEX_METACHARS=('\' '.' '[' ']' '(' ')' '{' '}' '^' '$' '*' '+' '?' '|')
