# BosParse Reference Manual

## Overview

BosParse is a powerful tool designed to parse command-line arguments in a flexible and efficient manner. This manual outlines the architecture, workflow, and implementation details of BosParse to guide developers in understanding and using it effectively.

For a quick start guide, see `bp-README.md`. For PFILTER-specific documentation, see `bp-PFILTER.md`.

## Workflow

1. **Initialize**: Loading pre-defined data, generate runtime environment, `CONFIGS`, verbose, etc.
1. **Global Parsing**: Parsing Global arguments, which will set CML Style and ZONE-SEP
1. **Prior Parsing**: Parsing Prior arguments, which will set up the Parsing-Aid-Symbols (PAS)
1. **Spec Parsing**: Parsing Spec arguments, which will set up essential parsing Options
1. **Parsing User Parameters**: Parsing user parameters, which will extract the user's input, validate parsing results if needed
1. **Output Parsing Results**: Outputting the parsing results, according to the user's preferences

## Main Data Structures

1. **CONSTANTS**: Constants used in BosParse
1. **HARNESSES**: Harness original definitions, immutable
1. **CONFIGS**: Runtime Harness collection, will update at every service tier
1. **EXIT_MSG**: Exit codes and messages
1. **PFILTER**: User parameter definitions
1. **RESYMS**: Reserved symbols used by PAS
1. **PFE_TYPES**: available `PFILTER` entry types
1. **MCG_TYPES**: available MCG name prefixes

## Terminology

- **`Directive`**: a set of special Specs which will lead to execute specific actions, like showing banner or version, then exit immediately
- **`dvo`**: disable variable output, for `source-mode` only
- **`ELM-SEP`**: separator between enum values or MCG names in `PFILTER` and `CONFIGS`
- **`FLD-SEP`**: separator between entry fields in `PFILTER` and `CONFIGS`
- **`Global`**: Harnesses to config Style, ZONE-SEP and LIDs
- **`GLID`**: lid for Globals, `~~~`, customize not allowed
- **`LID`**: Leading identifier, used to distinguish Option types
- **`LIGA`**: ligature style user parameter, used to pass multiple boolean Options with one parameter
- **`islands`**: one of command line structure styles with intermixing Options and Positionals, `OA-SEP` is required; `ZONE-SEP` not required; another style is `watershed`
- **`MCG`**: Mutual Correlation Group, a group of parameters with mutual correlation rules; MCGs defined in `PFILTER` and validated after parsing
- **`OA-SEP`**: separator between Option name and its value
- **`OP-ZONE`**: the part of CML before `ZN-SEP` that contains Options in `watershed` style CML
- **`Options`**: parsable parameters with a LID, including Globals, Priors, Specs, User Options and LIGAs; different LIDs used to distinguish different types of Options
- **`PAS`**: Parsing-Aid-Symbols, e.g. LIDs, SEPs, PAS consist of RESYMS
- **`pme`**: prefix-matching switch for user params, default `true`, disable with `~pme-`
- **`Positional`**: Positional parameters without a LID, simply strings
- **`PP-ZONE`**: the part of CML after `ZN-SEP` that contains Positionals in `watershed` style CML
- **`PLID`**: LID for Priors, double SLID (e.g. `~~`), cannot be customized at runtime
- **`Prior`**: prior parsing Harness, used to customize PASs
- **`SLID`**: LID for Specs, `~` by default, customize with Global `~~~slid`
- **`Spec`**: Parser setting Harness, a special type of Option with a SLID, used to configure the parser's behavior; Specs are defined in BosParse and can be set by users; Specs can be categorized into runtime mode settings, output format settings, PFILTER related settings, directive Specs and runtime output control settings
- **`PFILTER`**: an associative array with definitions of User Options created by user for advanced features; `PFILTER` passed to BosParse via the Specs `~pf` with `PFILTER`'s name reference or a JSON string (serialized `PFILTER`) or a `keys-values` string
- **`RESYMS`**: a set of BosParse reserved characters used in PASs.
- **`run-mode`**: method to use BosParse. BosParse will detect which mode it's running if no `run-mode` explicitly specified by user (via Specs `~run`); available modes: `source`, `eval` and `capture`; different modes will lead to different output formats
- **`style`**: Global Harness (`~~~` as lid), identify the CML structure, available: `watershed` and `islands`
- **`TD`**: for boolean flags, default value if trailing tag omitted, set by `~~td`
- **`TF`**: for boolean flags, trailing tag for `false`, set by `~~tf`
- **`TT`**: for boolean flags, trailing tag for `true`, set by `~~tt`
- **`ULID`**: LID for User Options, `-` by default, customize by `~~~ulid`
- **`watershed`**: command line structure style with a clear separator between Options and Positionals; supports space(s) as OA-SEP, while `ZN-SEP` is required to separate Options and Positionals
- **`ZN-SEP`**: separator between Options and Positionals in `watershed` style CML
- **`ESC_PFX`**: random-per-session marker (`_bp_${BASHPID}_${RANDOM}_`) used by the escaping system to avoid collision with user data
- **`capture_json_extract`**: helper function to extract values from capture mode JSON output

## Command line structure

Bosparse accepts the following command line structures:

```bash
[OP-ZONE] [ZN-SEP] [PP-ZONE] # watershed style
[Options | Positionals]      # islands style
```

where:

- `OP-ZONE`: contains all the Option parameters, including Globals, Priors, Specs and User Options
- `ZN-SEP` (`--` by default): separator between Option parameters and Positional parameters
- `PP-ZONE`: contains all the Positional parameters

For `watershed` style CML, a `ZN-SEP` is always recommended even if only one zone is provided. While `ZN-SEP` not found, BosParse will try to 'guess': if the first parameter is an Option parameter(starts with any LIDs), BosParse will assume that only `op-zone` is provided; otherwise, Bosparse will assume that only `pp-zone` is provided.

`watershed` style is more suitable for complex CML with many parameters, especially when there are many Positional parameters which may cause ambiguity if `ZN-SEP` not provided.

For `islands` style CML, all parameters regarded as standalone parameters(Options or Positionals) instead of values of other Options. `Space(s)` cannot be used to separate user parameter names and values, `ZN-SEP` acceptable but not required.

`islands` style is more suitable for simple CML, For example, if there is only one Positional parameter, `islands` style can be more concise and user-friendly.:

```bash
#!/bin/bash
bosparse ~~sty=i "$@"
echo "name: ${BP_Positionals_0}"
```

Then run the script with:

```bash
# 'island' style command line
./script.sh charlie
```

With `islands` style, `charlie` will be parsed as a Positional parameter, without `zn-sep` or parameter name supplied. When using `watershed` style, with the script modified, the CML should be:

```bash
# with ZN-SEP
# 'watershed' style command line
./script.sh -- charlie
# or an Option parameter with value needed
./script.sh -name charlie --
```

## PFILTER Definition

BosParse supports flexible parameter definition using `PFILTER` created by developer, which is an associative array containing all the necessary information for parsing user parameters.

### Syntax of `PFILTER` entry

The syntax of `PFILTER` entry is as follows:

```bash
["param-name"]="type:data:mcg-name"
```

Where:

- **param-name**: the name of the parameter
- **type** field: the type of the parameter, which can be `string`, `boolean` or `enum`
- **data** field: the data for the parameter, which can be default value, or a list of available values for `enum` separated by ELM-SEP (`|` pipe)
- **mcg-name** field: the name(s) of the mutual correlation group(s), used to group parameters that are mutually correlated; multiple group names separated by ELM-SEP (`|` pipe)

#### Note

- Data field and mcg-name field are optional.
- As `param-name` of Options will be used as Bash variable name in the parsing result, Option `param-name` should satisfy Bash variable naming convention, but in command line, an Option like `--dry-run` sounds reasonable. For this reason, BosParse accepts hyphen `-` using in `param-name` as an exception if it isn't at the beginning or end of the param-name. BosParse will replace every hyphen `-` with a underscore `_` in the final result.
- Exceptions substituting hyphen `-` with underscore `_` may cause name collision, for example, `--dry-run` and `--dry_run` will both be converted to `dry_run`. To avoid this, BosParse will check for potential collision in `PFILTER` definition and exit with error if any is detected.
- `mcg-name` follows the same naming rules and the exception.

### Serializing `PFILTER`

When running BosParse in `eval/capture` mode, `PFILTER` should be serialized before passing to BosParse. BosParse accepts two formas of serialized `PFILTER`:

- JSON format, can be serialized with the utility `utils/bp-serialize-pfilter`:

  ```bash
  ~pf="$(bp-serialize-pfilter PFILTER)"
  ```

- `key-value` pairs:

  ```bash
  ~pf="key1 value1 key2 value2 ..."
  ```

  Restrictions for this purpose:

  - `PFILTER` entry value contains space(s) or special characters will break the `key-value` pairs passing. Assign a double quoted variable to `~pf` can solve this problem:

  ```bash
  for key in "${PFILTER[@]}"; do
       spf+="${key} "
       spf+="${PFILTER[${key}]} "
   done
  result=$(./bosparse ~pf="${spf% }" ~json "$@")
  ```

  - No space(s) or special characters in `PFILTER` entry value is recommended

### PFILTER-ID

`PFILTER-ID` is a special entry in `PFILTER`, which is used to validate the `PFILTER` by `PARAM-FILTER` as key:

```bash
["PARAM-FILTER"]="arbitrary-content"
```

The value of `PFILTER-ID` entry does not matter while the key `PARAM-FILTER` is reserved as `PFILTER-ID`; BosParse will check the existence of `PFILTER-ID` entry to determine if this associative array is a valid `PFILTER` or not.

### PFILTER-related Harnesses

- `~pf`: Pass `PFILTER` to BosParse, should be a name reference(source mode) or a serialized `PFILTER`(JSON string/key-value pairs, for all modes)
  - PFILTER must be defined in the current shell environment when using name reference
  - When no PFILTER provided, or `~pf=""`, no respective functionality is added; BosParse behaves as if PFILTER is not used
  - When PFILTER not valid, parsing fails with an error
- `~rup`: Restrict unknown parameters, an undefined parameter will be rejected if `~rup` is set
  - enabled by default
  - `~rup` enables strict validation and rejects parameters not defined in PFILTER
  - `~rup-` allows any parameters; only those defined in PFILTER are validated
- `~afd`: Apply `PFILTER` defaults for parameters not belong to any MCGs; MCG member parameters follow group rules.
  - enabled by default
  - `~afd-` disables default assignment
- `~dvo`: Disable variable output, no `variable=value` output to avoid variable name conflict
  - for `source-mode` only
  - `false` by default (variables are output)
- '~pme': Enable-prefix-matching, allows prefix matching for user parameter names and their enum values.
  - enabled by default
  - for user parameters only; prefix-matching on Harnesses are always enabled

### Prefix-matching

BosParse supports prefix-matching for parameter names(include LIAG members) and enum values.

```bash
["help"]="bool:false"
["fruit"]="enum:apple|banana|cherry"
```

When no ambiguity is found, BosParse will use the prefix-matched parameter:

- `-h`, `-he`, `-hel`, `-help`: will all be matched to `help`
- `-f=b` or `-f b`: assign `banana` to `fruit` (`fruit=banana`)

### Enum Matching First(EMF) and Enum Matching Last(EML)

When an Enum type parameter is provided using Boolean syntax, BosParse will use the First or Last value in the enum list:

```bash
["color"]="enum:red|green|blue"
```

- When `-c` provided, use `blue` (`true`, EML)
- When `-c-` provided, use `red` (`false`, EMF)

### Symbol Escaping

BosParse uses an internal symbol escaping mechanism to safely handle special characters (`:`, `|`, `\`, etc.) in `PFILTER` entries and parameter values. A random-per-session marker `ESC_PFX` (`_bp_${BASHPID}_${RANDOM}_`) prevents collision with user data. Available in sourced scripts via `capture_json_extract`.

The helpers `escape_symbol` and `capture_json_extract` (see `02-util.sh`) expose this for downstream use. With the help of `PFILTER`, BosParse can parse user parameters in a flexible way, including type/value validation, default value assignment, prefix matching for parameter names and enum values, as well as mutual correlation groups for parameters.

### MCG support

BosParse supports MCGs, which are used to define a set of parameters that are mutually correlated.
See details in section "Mutual Correlation Groups"

## Parameter Schema and Types

BosParse supports the following parameter schema:

- `Option Parameter` (Option): parsable Option parameters should be with the following syntaxes:

  - Schema 1: `<LID> <Option-name> <OA-SEP> <Option-value>`
  - Schema 2: `<LID> <Option-name> <SPACE{1,}> <Option-value>`
  - Schema 3: `<LID> <Option-name> [Trailing-Tag]`
  - Schema 4: `<LID> <length-option-name> <option-names> [Trailing-Tag]`

  Option parameters always start with a LID. Different LIDs used to distinguish between different types of parameters. BosParse support 'string', 'bool', 'enum' and 'liga' Options, which can be distinguished by different LIDs and syntaxes:

  - **String Option**: support string; using schema '1' and '2', like `-name=value` or `-name value` -> `name=value`
  - **Boolean Option**: support boolean; using schema '3', like `-verbose+`, `-verbose-` or `-verbose` -> `verbose=` `true`/`false`/`true`(if `~td` is `true`) respectively
  - **Enum Option**: support enum; using schema '1' and '2', similar to String Option but with limited available values
  - **LIGA Option**: compressed Booleans; using schema '4', like `--abc+` is equivalent to `-a+ -b+ -c+`, or `--2abcdef-` is equivalent to `-ab- -cd- -ef-`.
  - Ligature syntax is supported for user options only

  Different LIDs for different types of Options, see section 'Terminology' for more details.

- `Positional Parameter` (Positional)
  Positional parameters are simply strings, without any special syntax.

## Mutual Correlation Groups

MCGs enforce relationships between parameters. Parameters can belong to more than one group.

### Group Types

- **Dependency (`d`/`D` prefix)**: `d-members` depend on `D-members`
- **Exclusion (`e` prefix)**: One or none parameter in the group can supply
- **Masters(`m`/`M` prefix)**: `m-member` assigned with the name of the supplied `M-member`
- **Required (`r` prefix)**: `members` must be supplied or fulfilled
- **Uniqueness (`u` prefix)**: Parameters must have different values

### Detailed Rules

- **Dependency Groups**

  - `d-member(s)` require one or more `D-member(s)` supplied;
  - No `d-member` supplying is permitted
  - `D-members` can be supplied without `d-members`;
  - Error if `d-members` supplied without `D-members`.

- **Exclusion Groups**

  - Group members are mutually exclusive; if more than one member supplied, parsing fails.
  - An Exclusion group must contain two or more members

- **Master Groups**

  - Master group includes `M-members` and a `m-member`.
  - `m-member` assigned with the supplied `M-member`'s name; not allowed to supply
  - If no `M-member` supplied, no value assigned to `m-member`(not defined)
  - Error if:
    1. `m-member` supplied, or
    1. More than one `M-member` supplied

- **Required Groups**

  All members must be available, be supplied or can be assigned default values; error if any member is missing and without default value.

- **Uniqueness Groups**

  - All supplied members must have different values; if any two members have the same value, parsing fails.
  - Un-supplied members will be ignored.

### **MCG Validation Order**

As default value assignment might affect validation result, validation order matters.

1. Check required rules and assign defaults
1. Check exclusion/uniqueness rules
1. Check dependency rules
1. Check master rules

## Directives

A group of special `Specs`, which will lead to execute specific actions.

Directives execute after `Specs` parsing, then the parser will exit at once; all User Parameters will be ignored.

BosParse supports the following directives:

- `~Banner`: Show banner, mainly used to test if BosParse is working
- `~Defaults`: Show CONFIGS settings
- `~Help`: Show online help
- `~Resymbols`: Show reserved symbol set for PAS except FLD-SEP and ELM-SEP
- `~Version`: Show BosParse version

## Harnesses

1. Globals - Set `Style`, `ZONE-SEP` and `LIDs` (LID: `~~~`)

   - `~~~style`: command line structure style, available styles: `watershed`(default) and `islands`
     - `~~~style=islands` or `~~~style=watershed` to set explicitly
     - `~~~style` without a value (bare) defaults to `islands` (EML — last enum value)
     - `~~~style-` match to `watershed` (EMF — first enum value)
   - `~~~glid`: (default `~~~`) Global LID string, nonconfigurable
   - `~~~plid`: (default `~~`) Prior LID string, nonconfigurable, sync with double `slid` (<slid><slid>)
   - `~~~slid`: (default `~`) Spec LID string
   - `~~~ulid`: (default `-`) User Parameter LID string
   - `~~~zs` (default `--`): Separator between Option parameters and Positional parameters

1. Priors - Parsing-aid symbols setting

   - Trailing-tags

     - `~~tf` (default `-`): `false` tag for Boolean Options
     - `~~tt` (default `+`): `true` tag for Boolean Options
     - `~~td` (default `true`): default value if no tag is specified

   - Separators

     - `~~os` (default `=`): separator between Option parameters and values

1. Specs - Specify parser settings

   - Runtime mode and output format

     - `~json`: JSON output
     - `~run`: Run-mode setting, available modes: `source`, `eval` and `capture`, `auto` by default
     - `~dvo`: disable variables output; for source mode only (to avoid variable name conflict)
     - `~oan`, `~pan`: Specify array names of parsing result

   - PFILTER related

     - `~pf`: Pass `PFILTER` to BosParse
     - `~rup`: Restrict unknown parameters
     - `~afd`: Apply `PFILTER` defaults
     - `~pme`: prefix-matching for user params enabled (default `true`)

   - Directives

     - `~Banner`: Show banner
     - `~Defaults`: Show default settings
     - `~Help`: Show online help
     - `~Resymbols`: Show reserved symbols used by PAS
     - `~Version`: Show BosParse version

1. Runtime output controls

   BosParse supports staged output control:

   - Use Globals to set verbosity of Priors-parsing stage
   - Use Priors to set verbosity of Specs-parsing stage
   - Use Specs to set verbosity of user-option parsing stage

   All output controls(use `~/~~/~~~`):

   - `quiet`: Output level 0 (suppress messages, errors still shown)
   - `standard`: Output standard information, error messages mainly
   - `extra`: Output extra information
   - `debug`: Output debug format
   - `trace`: Output trace format
   - `config`: Output CONFIGS(not available in Globals)

## Output Parsing Results

Output parsing results according to the `run-mode` specified by the user.

### Source Mode

By default, BosParse outputs as follows in `source-mode`:

1. Output Options as shell variables(can be disabled by `~dvo`)
    - if `~dvo` set, variables will output via array named after `CONSTS[OAN]`
1. Output Positional Arguments as an associative array named after `CONSTS[PAN]`

If user specified, BosParse outputs parsing result in arrays with customize name:

- `~oan`: specify an associative array for all Options
- `~pan`: an index array for Positional arguments

### Eval Mode

By default, BosParse outputs shell assignments for `eval $(...)`:

1. Output Options in shell assignments with the format `name=value`
1. Output Positional Arguments in shell assignments with the format `BP_Positionals_<index>=<value>`

If `~pan` is set to a different name, positional variables use that prefix, e.g. `<prefix>_<index>=<value>`.

This mode executes generated assignment text in the calling shell, so only use it for trusted invocations. For untrusted or external input, prefer capture mode.

### Eval Mode Security

`eval` mode runs text containing shell assignments in the calling shell process. Even though BosParse quotes values before emitting them, the emitted text is still executed by the shell and therefore represents a trust boundary.

Risks and mitigations:

- Injection: Untrusted inputs may craft option names or PFILTER-derived identifiers that result in unexpected assignments or code execution. Avoid passing untrusted text into `eval`-driven invocations.
- Identifier safety: Ensure PFILTER definitions and parameter names are controlled by the script author (do not accept arbitrary parameter names from external sources).
- Use capture mode: For external callers or untrusted input, use `~json` (capture mode) and parse the JSON with `jq` or the helper `capture_json_extract` instead of `eval`.
- Whitelisting: When integrating with dynamic PFILTERs, implement a strict whitelist of accepted parameter names or perform validation before invoking `eval`.

Example (safer): prefer capture mode for untrusted input

```bash
json=$(./bosparse ~json "$@")
name=$(capture_json_extract "$json" '.name // ""')
```

The helper function `capture_json_extract` (defined in `02-util.sh`, available in source mode) simplifies extracting values:

```bash
source ./bosparse
json=$(bosparse ~json "$@")
name=$(capture_json_extract "$json" '.name // ""' "default_name")
echo "name=${name}"
```

If `eval` is required for convenience, make sure the invocation and involved PFILTER definitions are not influenced by untrusted users and document the trust assumptions clearly.

Whitelist pattern (recommended)

The safest approach is to avoid `eval` entirely and explicitly accept only known parameter names from the JSON output. The snippet below shows a minimal, safe pattern that assigns only whitelisted keys into shell variables without using `eval`:

```bash
# capture JSON output
json=$(./bosparse ~json "$@")

# whitelist of allowed option names
allowed=(name active timeout)

for k in "${allowed[@]}"; do
  if jq -e --arg k "$k" 'has($k)' >/dev/null <<<"$json"; then
    v=$(jq -r --arg k "$k" '.[$k]' <<<"$json")
    # assign safely without eval: printf -v writes directly to variable
    printf -v "$k" '%s' "$v"
  fi
done

echo "name=${name:-}" "active=${active:-}" "timeout=${timeout:-}"
```

If you must generate and execute assignment text, restrict the generated statements to the whitelist and quote values safely before executing. For example:

```bash
json=$(./bosparse ~json "$@")
allowed=(name active timeout)
{
  for k in "${allowed[@]}"; do
    if jq -e --arg k "$k" 'has($k)' >/dev/null <<<"$json"; then
      v=$(jq -r --arg k "$k" '.[$k]' <<<"$json")
      printf '%s=%q\n' "$k" "$v"
    fi
  done
} | bash
```

Prefer the first pattern (direct assignment via `jq` + `printf -v`) because it avoids executing arbitrary generated text and thus reduces the attack surface.

### Capture Mode

Output Options and Positional arguments in JSON format.
