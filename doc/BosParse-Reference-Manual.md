# BosParse Reference Manual

## Overview

BosParse is a powerful tool designed to parse command-line arguments in a flexible and efficient manner. This manual outlines the architecture, workflow, and implementation details of BosParse to guide developers in understanding and using it effectively.

## Architecture

BosParse follows workflow-driven architecture, where each step is designed to be executed sequentially. The core stages of BosParse include:

1. **Prior Parsing**: Parsing Prior arguments, which will set up the Parsing-Aid-Symbols (PAS)
1. **PSet Parsing**: Parsing PSet arguments, which will set up essential parsing Options
1. **Parsing User Parameters**: Parsing user parameters, which will extract the user's input, validate parsing results if needed
1. **Output Parsing Results**: Outputting the parsing results, according to the user's preferences

## Workflow

### Loading initial configurations

Load all the configuration arrays:

1. Constants: `CONSTANTS`
1. Super Verbose flags: `SVERBOSE`
1. Super Lids: `SUPERS`
1. Priors: `PRIORS`
1. PSets: `PSETS`
1. PFILTER Entry Types: `PFILTER_ENTRY_TYPES`
1. MCG Types: `MCG_TYPES`
1. Reserved Symbols: `RESYMS`
1. Symbol Names: `SYMNAMES`
1. Exceptions: `EXCEPTIONS`
1. Core Configurations `CONFIGS`
1. Exit Messages: `EXIT_MSG`

### Super verbose parsing

1. Extract and parse Super Verbose flags and `style`
1. Update `CONFIGS` with Super Verbose flags and `style`.

Super Verbose flags used to control the parameter extraction and output verbosity during Priors parsing.
`style` used to extract the command line structure in subsequent parsing stages.

### Prior Parsing

1. Extract and parse all Priors
1. Validate all Priors
1. Update `CONFIGS`


### PSet Parsing

1. Extract and parse all PSets
1. Validate all PSet
1. Execute Directive if required
1. Update `CONFIGS`

### Parsing User Parameters

1. Extract and parse all user parameters
1. Validate all user parameters if `PFILTER` is provided

### Output Parsing Results

Output parsing results according to the `run-mode` specified by the user.

#### Source Mode

By default, BosParse outputs as follows in `source-mode`:

1. Output Options as shell variables(can be disabled by `~dvo`)
1. Output Positional Arguments as an associative array named `BP_Positionals`

If user specified, BosParse outputs parsing result in arrays with customize name:

- `~oan`: specify an associative array for all Options
- `~san`: an associative array for String-Options
- `~ban`: an associative array for Boolean-Options
- `~pan`: an index array for Positional arguments

#### Eval Mode

By default, BosParse outputs shell assignments for `eval $(...)`:

1. Output Options in shell assignments with the format `name=value`
1. Output Positional Arguments in shell assignments with the format `BP_Positionals_<index>=<value>`

If `~pan` is set to a different name, positional variables use that prefix, for example `<prefix>_<index>=<value>`.

This mode executes generated assignment text in the calling shell, so only use it for trusted invocations. For untrusted or external input, prefer capture mode.

#### Eval Mode Security

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

The helper function `capture_json_extract` (defined in `01-util.sh`, available in source mode) simplifies extracting values:

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

#### Capture Mode

Output Options and Positional arguments in JSON format.

## Main Data Structures

1. **CONSTANTS**: Constants used in BosParse
1. **CONFIGS**: Configurations used in BosParse
1. **PRIORS**: Prior definitions; BosParse updates `CONFIGS` after Priors parsing at runtime
1. **PSETS**: PSet definitions; BosParse updates `CONFIGS` after PSets parsing at runtime
1. **RESERVED_SYMBOLS**: Reserved symbols used by PAS
1. **EXIT_MSG**: Exit codes and messages
1. **PFILTER**: User parameter definitions

## Parameter Definition

BosParse supports flexible parameter definition using `PFILTER` created by developer, which is an associative array containing all the necessary information for parsing user parameters.

### Symbol Escaping System

BosParse uses an internal symbol escaping mechanism to safely handle special characters (`:`, `|`, `\`, etc.) in parameter names and values. A random-per-session marker `BP_ESC_PFX` (`_bp_${BASHPID}_${RANDOM}_`) prevents collision with user data. Available in sourced scripts via `capture_json_extract`.

The helpers `escape_symbol` and `capture_json_extract` (see `01-util.sh`) expose this for downstream use. With the help of `PFILTER`, BosParse can parse user parameters in a flexible way, including type/value validation, default value assignment, prefix matching for parameter names and enum values, as well as mutual correlation groups for parameters.

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
- As `param-name` of Options will be used as Bash variable name in the parsing result, Option `param-name` should satisfy Bash variable naming convention, but in command line, an Option like `--dry-run` sounds reasonable. For this reason, BosParse accepts hyphen `-` using in `param-name` as an exception if it isn't at the beginning or end. BosParse will replace every hyphen `-` with a underscore `_` in the final result.
- Exceptions substituting hyphen `-` with underscore `_` may cause name collision, for example, `--dry-run` and `--dry_run` will both be converted to `dry_run`. To avoid this, BosParse will check for potential collision in `PFILTER` definition and exit with error if any is detected.
- `mcg-name` follows the same naming rules and the exception.

### Serializing `PFILTER`

When running BosParse in `eval/capture` mode, `PFILTER` should be serialized before passing to BosParse. BosParse accepts two formas of serialized `PFILTER`:

- json format, can be serialized with the utility `utils/bp-serialize-pfilter`:

  ```bash
  ~pf="$(bp-serialize-pfilter PFILTER)"
  ```

- `keys-values` string:

  ```bash
  ~pf="${!PFILTER[*]} ${PFILTER[*]}"
  ```

  Restrictions for this purpose:
  - `PFILTER` entry value must not be empty;
  - `PFILTER` entry value should be literal text

### PFILTER-ID

`PFILTER-ID` is a special entry in `PFILTER`, which is used to validate the `PFILTER`:

```bash
["PARAM-FILTER"]="text-not-empty"
```

The value of `PFILTER-ID` entry does not matter while the key `PARAM-FILTER` is reserved as `PFILTER-ID`; BosParse will check the existence of `PFILTER-ID` entry to determine if this associative array is a `PFILTER` or not.

### PFILTER-related PSets

- `~pf`: Pass `PFILTER` to BosParse, should be a name reference(source mode) or a serialized `PFILTER`(JSON string, for all modes)
  - PFILTER must be defined in the current shell environment when using name reference
  - When no PFILTER provided, no respective functionality is added; BosParse behaves as if PFILTER is not used
  - When PFILTER not valid, parsing fails with an error
- `~rup`: Restrict unknown parameters, an un-difined parameter will be rejected if `~rup` is set
  - enabled by default
  - `~rup` enables strict validation and rejects parameters not defined in PFILTER
  - `~rup-` allows any parameters; only those defined in PFILTER are validated
- `~afd`: Apply `PFILTER` defaults for paramters not belong to any MCG; MCG member parameters follow group rules.
  - enabled by default
  - `~afd-` disables default assignment
- `~dvo`: Disable variable output, no `variable=value` output to avoid variable name conflict
  - for `source-mode` only
  - `false` by default (variables are output)
- '~pme': Prefix for parameter name matching, allows prefix matching for parameter names and enum values
  - enabled by default
  - for user parameters only; prefix-matching for Priors and PSets are always enabled
  - when set, BosParse will strip the prefix before matching with PFILTER keys

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

### MCG support

BosParse supports MCG, which are used to define a set of parameters that are mutually correlated.
See details in section "Mutual Correlation Groups"

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
  - No `d-member` supplied is permitted
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

## Command line structure

Bosparse accepts the following command line structures:

```bash
[op-zone] [zn-sep] [pp-zone] # watershed style
[Options | Positionals]      # islands style
```

where:

- `op-zone`: contains all the Option parameters, including Priors, PSets and User Options
- `zn-sep` (`--` by default): separator between Option parameters and Positional parameters
- `pp-zone`: contains all the Positional parameters

For `watershed` style CML, a `ZN-SEP` is always recommended even if only one zone is provided. While if `ZN-SEP` not found, BosParse will try to 'guess': if the first parameter is an Option parameter(starts with any LID), BosParse will assume that only `op-zone` is provided; otherwise, Bosparse will assume that only `pp-zone` is provided.

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

With `islands` style, `charlie` will be parsed as a Positional parameter, without `ZN-SEP` or parameter name supplied. When using `watershed` style, with the script modified, the CML should be:

```bash
# with ZN-SEP
# 'watershed' style command line
./script.sh -- charlie
# or an Option parameter with value needed
./script.sh -name charlie
```

## Parameter Schema and Types

BosParse supports the following parameter types:

- `Option Parameter` (Option): parsable Option parameters should be with the following syntaxes:
  - Schema 1: `<LID> <Option-name> <OA-SEP> <Option-value>`
  - Schema 2: `<LID> <Option-name> <SPACE{1,}> <Option-value>`
  - Schema 3: `<LID> <Option-name> [Trailing-Tag]`
  - Schema 4: `<LID> <length-option-name> <option-names> [Trailing-Tag]`

  Option parameters always start with a LID. Different LIDs used to distinguish between different types of parameters. BosParse support 'string', 'boolean', 'enum' and 'liga' Options, which can be distinguished by different LIDs and syntaxes:
  - **String Option**: support string; using schema '1' and '2', like `-name=value` or `-name value` -> `name=value`
  - **Boolean Option**: support boolean; using schema '3', like `-verbose+`, `-verbose-` or `-verbose` -> `verbose=` `true`,`false` and `true`(if `~td` is `true`) respectively
  - **Enum Option**: support enum; using schema '1' and '2', similar to String Option but with limited available values
  - **LIGA Option**: compressed Booleans; using schema '4', like `--abc+` is equivalent to `-a+ -b+ -c+`, or `--2abcdef-` is equivalent to `-ab- -cd- -ef-`.
  - Ligature syntax is supported for user options only; PSet ligatures using double PSet LIDs (`~~` by default) are unsupported and not recognized.

  Different LIDs for different types of Options, see section 'Terminology' for more details.

- `Positional Parameter` (Positional)
  Positional parameters are simply strings, without any special syntax.

## Directives

A group of special `PSets`, which will lead to execute specific actions.

Directives execute after `PSets` parsing, then the parser will exit at once; all User Parameters will be ignored.

BosParse supports the following directives:

- `~Banner`: Show banner, mainly used to test if BosParse is working
- `~Defaults`: Show default constant/prior/pset settings
- `~Help`: Show online help
- `~Resymbols`: Show reserved symbol set for PAS except FLD-SEP and ELM-SEP
- `~Version`: Show BosParse version

## Configuration Options

1. Supers - Super PSets (`~~~` prefix)
   - `~~~style`: command line structure style, available styles: `watershed`(default) and `islands`
     - `~~~style=islands` or `~~~style=watershed` to set explicitly
     - `~~~style` without a value (bare) defaults to `islands` (EML)
   - `~~~slid`: Super LID string (default `~~~`), used to identify Super PSets (defined but not configurable at runtime)
   - `~~~prlid`: Prior LID string (default `~~`), used to identify Priors (defined but not configurable at runtime)
   - `~~~zs` (default `--`): separator between Option parameters and Positional parameters

1. Priors - Parsing-aid symbols setting
   - Leading-ids
     - `~~plid` (default `~`): prefix of PSets
     - `~~ulid` (default `-`): prefix of user Options
   - Trailing-tags
     - `~~tf` (default `-`): `false` tag for Boolean Options
     - `~~tt` (default `+`): `true` tag for Boolean Options
     - `~~td` (default `true`): default value if no tag is specified
   - Separators
     - `~~os` (default `=`): separator between Option parameters and values
   - Runtime output controls (for PSet parsing stage; will be reset by PSet settings before User-Option parsing)
     - `~~quiet`: Output level 0 (suppress messages, errors still shown)
     - `~~standard`: Output standard information, error messages mainly
     - `~~extra`: Output extra information
     - `~~debug`: Output debug format
     - `~~trace`: Output trace format
     - `~~config`: Output configurations after Priors parsing

1. PSets - Parser settings
   - Runtime mode and output format
     - `~json`: JSON output
     - `~run`: Run-mode setting, available modes: `source`, `eval` and `capture`, `auto` by default
     - `~dvo`: disable variables output; for source mode only (to avoid param name conflict)
     - `~oan`, `~san`, `~ban`, `~pan`: Specify array names of parsing result

   - PFILTER related
     - `~pf`: Pass `PFILTER` to BosParse
     - `~rup`: Restrict unknown parameters
     - `~afd`: Apply `PFILTER` defaults
     - `~pme`: prefix-matching for user params enabled (default `true`), disable with `~pme-`

   - Directives
     - `~Banner`: Show banner
     - `~Defaults`: Show default settings
     - `~Help`: Show online help
     - `~Resymbols`: Show reserved symbols used by PAS
     - `~Version`: Show BosParse version

   - Runtime output controls (for user Options parsing stage)
     - `~quiet`: Output level 0 (suppress messages, errors still shown)
     - `~standard`: Output standard information
     - `~extra`: Output extra information
     - `~debug`: Output debug format
     - `~trace`: Output trace format
     - `~config`: Output configurations after PSet parsing

## Terminology

- **`Directive`**: a set of special PSets which will lead to execute specific actions, like showing banner or version, then exit immediately
- **`dvo`**: disable variable output, for `source-mode` only
- **`ELM-SEP`**: separator between enum values or MCG names in `PFILTER` and config arrays
- **`FLD-SEP`**: separator between entry fields in `PFILTER` and config arrays
- **`LID`**: Leading identifier, used to distinguish Option types
- **`LIGA`**: ligature style user parameter, used to pass multiple boolean Options with one parameter
- **`islands`**: one of command line structure styles with intermixing Options and Positionals, `OA-SEP` is required; another style is `watershed`
- **`MCG`**: Mutual Correlation Group, a group of parameters with mutual correlation rules; MCGs defined in `PFILTER` and validated after parsing
- **`OA-SEP`**: separator between Option name and its value
- **`op-zone`**: the part of CML before `ZN-SEP` contains Options in `watershed` style CML
- **`Option`**: parsable parameters with a LID, including Priors, PSets and User Options; different LIDs used to distinguish different types of Options, User Params, PSets, Priors, LIGAs, etc.
- **`PAS`**: Parsing-Aid-Symbols, e.g. LIDs, SEPs, PAS consist of RESYMS
- **`PFILTER`**: a set of rules defined in a specific format to specify the expected parameters, their types, default values, mutual correlation rules, etc., used to aid parsing and validate user parameters; PFILTER is passed to BosParse with PSet `~pf`
- **`PLID`**: LID for PSets, `~` by default, customize with Prior `~~plid`; double-PLID ligatures are not supported.
- **`pme`**: prefix-matching switch for user params, default `true`, disable with `~pme-`
- **`Positional`**: Positional parameters without a LID, simply strings
- **`pp-zone`**: the part of CML after `ZN-SEP` contains Positionals in `watershed` style CML
- **`Prior`**: prior parsing PSets, used to customize PASs
- **`PRLID`**: LID for Priors, `~~` by default, currently cannot be customized at runtime
- **`PSet`**: Parser setting, a special type of Option with a PLID, used to configure the parser's behavior; PSets are defined in BosParse and can be set by users; PSets can be categorized into runtime mode settings, output format settings, PFILTER related settings, directive PSets and runtime output control settings
- **`PFILTER`**: an associative array with definitions of User Options created by user for advanced features; `PFILTER` passed to BosParse via the PSet `~pf` with `PFILTER`'s name reference or a JSON string (serialized `PFILTER`) or a `keys-values` string
- **`RESYMS`**: a character set of BosParse reserved characters used in PASs.
- **`run-mode`**: method to use BosParse. BosParse will detect which mode it's running if no `run-mode` explicitly specified by user (via PSet `~run`); available modes: `source`, `eval` and `capture`; different modes will lead to different output formats
- **`style`**: Super PSet(`~~~` as lid), identify the CML structure, available: `watershed` and `islands`
- **`TD`**: default value if trailing tag omitted, set by `~~td`
- **`TF`**: trailing tag for `false`, set by `~~tf`
- **`TT`**: trailing tag for `true`, set by `~~tt`
- **`ULID`**: LID for User Options, `-` by default, customize by `~~ulid`
- **`watershed`**: command line structure style with a clear separator between Options and Positionals; supports space(s) as OA-SEP, while `ZN-SEP` is required to separate Options and Positionals
- **`ZN-SEP`**: separator between Options and Positionals in `watershed` style CML
- **`BP_ESC_PFX`**: random-per-session marker (`_bp_${BASHPID}_${RANDOM}_`) used by the escaping system to avoid collision with user data
- **`capture_json_extract`**: helper function to extract values from capture mode JSON output
