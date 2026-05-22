# Constants and definitions --------------------------------------------------------

function consts() {
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
function definitions() {
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
	local -n SVERBOSE_ref=${11}
	local -n SYMNAMES_ref="${12}"

	consts \
		CONSTANTS_ref \
		PFILTER_ENTRY_TYPES_ref

	# BOSPARSE_PARAMETER_NAME
	# running and output(4)
	local run="run_mode"
	local json="output_as_json"

	local eoe="exit_on_error"
	local dvo="disable_variable_output"

	# parsing style(2)
	local prem="prefix_matching_enabled"
	local style="style_of_commandline"

	# directives(4)
	local Banner="directive_bannaer"
	local Defaults="directive_default_configs"
	local Resymbols="directive_resyms"
	local Version="directive_version"

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

	# SVERBOSE_ref/SUPERS_refPRIORS_ref/PSETS_ref used to define SVerbose/Supers/Priors/PSets
	# SVerbose: super verbose params, they will be parsed at the very beginning of the parser
	# SUPERS: lid of Super Verbose params & Prior PSets
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
	#             - uniqueness, group name start with 'u'
	#             - exclusion, group name start with 'e'
	#             - dependency, group name start with 'd|D'
	#             - siblings, group name start with 's'
	#             - master, group name start with 'm|M'

	# output control for Prior parsing
	SVERBOSE_ref=(
		["quiet"]="${quiet}:bool::eg_sv"
		["standard"]="${standard}:bool::eg_sv"
		["extra"]="${extra}:bool::eg_sv"
		["debug"]="${debug}:bool::eg_sv"
		["trace"]="${trace}:bool::eg_sv"
	)
	SUPERS_ref=(
		["slid"]="${slid}:resym:4"
		["prlid"]="${prlid}:resym:3"
		["style"]="${style}:enum:watershed|islands"
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
		["required"]="enum:r" # all required parameters, no matter they are in the same MCG or not
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
		['(']="PARENTHESIS_LEFG"
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
		["${eoe}"]=false  # exit on errors
		["${dvo}"]=false  # disable variables output, for source mode only to avoid param names conflict

		# parsing style
		["${style}"]="${CONSTANTS_ref[CML_STYLE]%|*}" # cml style, watershed|islands

		# directives
		["${Defaults}"]=false  # ~Default, output CONFIGS to stdout
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
		["3"]="${pros_tag}"

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
		["126"]="Found an empty parameter, perhanps input error."

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

		["44"]="Parameter(s) '\${pros_tag3}' should be supplied together but '\${pros_tag2}' missed. " # sibling
		["144"]="Parameter(s) '\${pros_tag3}' in Sibling MCG '\${pros_tag}' should bind together, but '\${pros_tag2}' un-supplied and without a default."

		["45"]="Only one of the parameters '\${pros_tag}' should be supplied."
		["145"]="M-members '\${pros_tag}' of Master MCG '\${pros_tag2}' cannot supplied at sametime."

		["46"]="\${pros_tag} required by '\${pros_tag2}' but not supplied." # dependency
		["146"]="\${pros_tag} in Dependency MCG '\${pros_tag3}' required by '\${pros_tag2}'"

		["47"]="Invalid parameter '\${pros_tag}', use one of '\${pros_tag2}'"
		["147"]="Parameter '\${pros_tag}' is an m-member of Master MCG '\${pros_tag3}', setting it by one of the parameters: '\${pros_tag2}'"

		["48"]="Needs one of the  parameters '\${pros_tag2}' supplied." # no supplied M-member and no default value
		["148"]="No M-member of Master MCG '\${pros_tag}' supplied, needs one of '\${pros_tag2}'"

		["49"]="Invalid \${pros_tag} '\${pros_tag2}' in PFILTER, the value should be one of '\${pros_tag3}'"    # enum check(used)
		["14r98"]="Invalid \${pros_tag} '\${pros_tag2}' in PFILTER, the value should be one of '\${pros_tag3}'" # bool/string/resym check(used)

		# filter parameter with PFILTER
		["50"]="Invalid \${pros_tag} \${pros_tag2}, the value should be one of '\${pros_tag3}'" # enum check(used)
		["150"]="Invalid enum entry value: \${pros_tag2}, available enums: '\${pros_tag3}'"

		["51"]="Invalid setting: \${pros_tag2}" # bool/string/resym type check
		["151"]="Invalid \${pros_tag} setting: \${pros_tag2}, ARG should be \${pros_tag3}"

		["52"]="Invalid \${pros_tag} setting \${pros_tag2}: \${pros_tag3}" # assert resym

		["53"]="Unknown parameter '\${pros_tag2}'" # for user parameter
		["153"]="PSet '~rup' requires all parameters matching 'PFLILTER' but '\${pros_tag}' didn't."

		["54"]="Unknown \${pros_tag} '\${pros_tag2}'" # for Priors/PSets
		["154"]="Invaolid \${pros_tag} '\${pros_tag2}', cannot match any \${pros_tag}."

		["55"]="Missing parameter '\${pros_tag}'" # un-supplied and no default
		["155"]="Un-suplied parameter '\${pros_tag}' reuqires a default value by '~afd'"

		["56"]="Unrecognized \${pros_tag} '\${pros_tag2}', may be one of '\${pros_tag3}'?" # assert multi-prefix-matching
		["156"]="Invalid \${pros_tag} '\${pros_tag2}', multiple matched: '\${pros_tag3}'."

		["70"]="Parameter '\${pros_tag2}' is required but not supplied."
		["170"]="Parameter '\${pros_tag2}' in Required MCG '\${pros_tag} without default value and not supplied."
	)
}
function validate_variable_name() {
	local -n var_name_ref="$1"
	local return_on_error=${2:-false} # return if invalid instead of exit with a message

	[[ -n "${var_name_ref}" ]] || exit_with_msg 26
	pros_tag="${var_name_ref}"
	if [[ ${var_name_ref} =~ ^[a-zA-Z_](-?[a-zA-Z0-9_])*$ ]]; then
		# replace exceptions
		substitute_exceptions var_name_ref
		return 0
	else
		if [[ ${return_on_error} == true ]]; then
			return 1
		else
			# exit with different msg
			[[ ${var_name_ref:0:1} == [0-9] ]] && {
				pros_tag2="${var_name_ref:0:1}"
				exit_with_msg 23
			}
			[[ ${var_name_ref} =~ ^[a-zA-Z0-9_]+$ ]] || {
				pros_tag2="${var_name_ref//[a-zA-Z0-9-_]/}"
				exit_with_msg 22
			}
			exit_with_msg 21
		fi
	fi
}
