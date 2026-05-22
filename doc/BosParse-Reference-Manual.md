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

1. Extract and parse Super Verbose flag
1. Update `CONFIGS` with super verbose flag.

This will be used to control the output verbosity during Priors parsing

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

Output parsing results according to the run-mode specified by the user.

#### Source Mode

By default, BosParse outputs as follows:

1. Output Options as shell variables
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

If `~oan` specified, output Positional Arguments with the format `~oan=ps` -> `ps_<index>=<value>`

#### Capture Mode

Output Options and Positional arguments in JSON format.

## Main Data Structures

1. **CONSTANTS**: Constants used in BosParse
1. **CONFIGS**: Configurations used in BosParse
1. **PRIORS**: Prior definitions; BosParse updates `CONFIGS` after Priors parsing at runtime
1. **PSETS**: PSet definitions; BosParse updtes `CONFIGS` after PSets parsing at runtime
1. **RESERVED_SYMBOLS**: Reserved symbols used by PAS
1. **EXIT_MSG**: Exit codes and messages
1. **PFILTER**: User parameter definitions

## Parameter Definition

BosParse supports flexible parameter definition using `PFILTER` created by programer, which is an associative array containing all the necessary information for parsing user parameters. With the help of `PFILTER`, BosParse can parse user parameters in a flexible way, including type/value validation, default value assignment, prefix matching for parameter names and enum values, as well as mutual correlation groups for parameters.

### Syntax of `PFILTER` entry

The syntax of `PFILTER` entry is as follows:

```bash
[param-name]="type:data:mcg-name"
```

Where:

- **param-name**: the name of the parameter
- **type** field: the type of the parameter, which can be `string`, `boolean` or `enum`
- **data** field: the data for the parameter, which can be default value, or a list of available values for `enum` separated by FLD-SEP(`|` pipe)
- **mcg-name** field: the name(s) of the mutual correlation group(s), used to group parameters that are mutually correlated; multiple group names separated by FLD-SEP (`|` pipe)

Data field and mcg-name field are optional.

### Serializing `PFILTER`

When running BosParse in `eval/capture` mode, `PFILTER` should be serialized before passing to BosParse. BosParse accepts two formas of serialized `PFILTER`:

- json format, can be serialized with the utility `utils/bp-serialize-pfilter`:

  ```bash
  ~pf="$(bp-serialize-pfilter PFILTER)"
  ```

- `keys-values` string:

  ```bash
  ~pf="$(!PFILTER[*]} ${PFILTER[*])"
  ```

  Restrictions for this purpose:
  - `PFILTER` entry values must not be empty, printable charactor(s) needed;
  - `PFILTER` entry values must not contain space(s) or non-printable charactors

### PFILTER-ID

`PFILTER-ID` is a special entry in `PFILTER`, which is used to validate the `PFILTER`:

```bash
["PARAM-FILTER"]="any-string-not-empty"
```

The value of `PFILTER-ID` entry does not matter while the key `PARAM-FILTER` is reserved for `PFILTER-ID`; BosParse will check the existence of `PFILTER-ID` entry to determine if this associative array is a `PFILTER` or not.

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
- `fmi`: Forbid m-member of Master MCG input, use M-member's name(when one M supplied) or m's default(when no M supplied)

### Prefixes-matching

BosParse supports prefixes-matching for parameter names and enum values.

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
["color"]="enum:red,green,blue"
```

- When `-c` provided, use `blue` (`true`, EML)
- When `-c-` provided, use `red` (`false`, EMF)

### MCG support

BosParse supports MCG, which are used to define a set of parameters that are mutually correlated.
See details in section "Mutual Correlation Groups"

## Mutual Correlation Groups

MCGs enforce relationships between parameters. Parameters can belong to more than one group.

### Group Types

- **Dependency (`d`/`D` prefix)**: d-members depend on D-members
- **Exclusion (`e` prefix)**: One or none parameter in the group can supply
- **Masters(`m`/`M` prefix)**: m-member assigned with the name of the supplied M-member
- **Required (`r` prefix)**: members must be supplied or fulfilled
- **Uniqueness (`u` prefix)**: Parameters must have different values

### Detailed Rules

- **Dependency Groups**
  - d-member(s) require one or more D-member(s) supplied;
  - No d-member is permitted
  - D-members can be supplied without d-members;
  - Error if d-members supplied without D-members.

- **Exclusion Groups**
  - Group members are mutually exclusive; if more than one member supplied, parsing fails.
  - An Exclusion group must contain two or more members

- **Master Groups**
  - Master group includes M-members and a m-member.
  - m-member assigned with the supplied M-member's name; not allowed to supply
  - If no M-member supplied, no value assigned to m-member(not defined)
  - Error if:
    1. m-member supplied, or
    1. More than one M-member supplied

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

For `watershed` style CML, a `ZN-SEP` is always recommended even if only one zone is provided. While if `ZN-SEP` not found, BosParse will try to 'guess': if the first paramter is an Option parameter(starts with any LID), BosParse will assume that only `op-zone` is provided; otherwise, Bosparse will assume that only `pp-zone` is provided.

`watershed` style is more suitable for complex CML with many parameters, especially when there are many Positional parameters which may cause ambiguity if `ZN-SEP` not provided.

For `islands` style CML, all parameters regarded as standalone parameters(Options or Positionals) instead of values of other Options. `Space(s)` cannot be used to separate user parameter names and values, `ZN-SEP` acceptable but not required.

`islands` style is more suitable for simple CML, For example, if there is only one Positional parameter, `islands` style can be more concise and user-friendly.:

```bash
#!/bin/bash
bosparse ~~~sty=i "$@"
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

  Option parameters always start with a LID. Different LIDs can be used to distinguish between different types of parameters. BosParse support 'string', 'boolean', 'enum' and 'liga' Options, which can be distinguished by different LIDs and syntaxes:
  - **String Option**: support string; using schema '1' and '2', like `-name=value` or `-name value` -> `name=value`
  - **Boolean Option**: support boolean; using schema '3', like `-verbose+`, `-verbose-` or `-verbose` -> `verbose=` `true`,`false` and `true`(if `~td` is `true`) respectively
  - **Enum Option**: support enum; using schema '1' and '2', similar to String Option but with limited available values
  - **LIGA Option**: compressed Booleans; using schema '4', like `--abc+` is equivalent to `-a+ -b+ -c+`, or `--2abcdef-` is equivalent to `-ab- -cd- -ef-`

  Differnt LIDs for different type of Options, see section 'Terminology' for more details.

- `Positional Parameter` (Positional)
  Positional parameters are simply strings, without any special syntax.

## Directives

Directives are a group of special `PSets`, which will lead to execute specific actions.

Directives execute after `PSets` parsing, then the parser will exit at once; that means all User Parameters will be ignored.

BosParse supports the following directives:

- `~Banner`: Show banner, mainly used to test if BosParse is working
- `~Default`: Show default settings, all data from `CONFIGS` will be shown
- `~Help`: Show help(not implemented)
- `~Resymbols`: Show reservable symbol set for PAS except FLD-SEP and ELM-SEP
- `~Version`: Show BosParse version

## Configuration Options

1. Priors - Parsing-aid symbols setting
   - Leading-ids
     - `~~~style`: command line structure style, available styles: `watershed` and `islands`
     - `~~~plid` (default `~`): prefix of PSets
     - `~~~ulid` (default `-`): prefix of user Options
   - Trailing-tags
     - `~~~tf` (default `-`): `false` tag for Boolean Options
     - `~~~tt` (default `+`): `true` tag for Boolean Options
     - `~~~td` (default `true`): default value if no tag is specified
   - Separators
     - `~~~zs` (default `--`): separator between Option parameters and Positional parameters
     - `~~~os` (default `=`): separator between Option parameters and values
   - Runtime output controls(for PSet parsing stage; will be reset by PSet settings before User-Option parsing)
     - `~~~quiet`: Suppress all output include errors
     - `~~~standard`: Output standard information, error message mainly
     - `~~~extra`: Output extra information
     - `~~~debug`: Output debug format
     - `~~~trace`: Output trace format
     - `~~~config`: Output configurations after Priors parsing

1. PSets - Parser settings
   - Runtime mode and output format
     - `~json`: JSON output
     - `~run`: Run-mode setting, available modes: `source`, `eval` and `capture`, `auto` by default
     - `~dvo`: disable variables output; for source mode only (to avoid param names conflict)
     - `~oan`, `~san`, `~ban`, `~pan`: Specify array names of parsing result

   - PFILTER related
     - `~pf`: Pass `PFILTER` to BosParse
     - `~rup`: Restrict unknown parameters
     - `~afd`: Apply `PFILTER` defaults
     - `~fmi`: forbid m-member of Master MCG from supplying

   - Directives
     - `~Banner`: Show banner
     - `~Default`: Show default settings
     - `~Help`: Show help(not implemented)
     - `~Resymbols`: Show reservable symbols used by PAS
     - `~Version`: Show BosParse version

   - Runtime output controls (for user Options parsing stage)
     - `~quiet`: Suppress all output include errors
     - `~standard`: Output standard information
     - `~extra`: Output extra information
     - `~debug`: Output debug format
     - `~trace`: Output trace format
     - `~config`: Output configurations after PSet parsing

## Terminology

- **`Directive`**: a set of special PSets which will lead to execute specific actions, like showing banner or version, then exit immediately
- **`ELM-SEP`**: separator between enum values or MCG names in `PFILTER` and config arrays
- **`FLD-SEP`**: separator between entry fields in `PFILTER` and config arrays
- **`LID`**: Leading identifier, used to distinguish Option types
- **`LIGA`**: ligature style parameter, used to pass multiple boolean Options with one parameter
- **`islands`**: one of command line structure styles with intermixing Options and Positionals, `OA-SET` is required; another style is `watershed`
- **`MCG`**: Mutual Correlation Group, a group of parameters with mutual correlation rules; MCGs defined in `PFILTER` and validated after parsing
- **`OA-SEP`**: separator between Option name and its value
- **`op-zone`**: the part of CML before `ZN-SEP` contains Opsions in `watershed` style CML
- **`Option`**: parsable parameters with a LID, including Priors, PSets and User Options; different LIDs used to distinguish different types of Options, User Params, PSets, Priors, LIGAs, etc.
- **`PAS`**: Parsing-Aid-Symbols, e.g. LIDs, SEPs, PAS consist of RESYMS
- **`PLID`**: LID for PSets, `~` by default, customieze with PSet `~~~plid`
- **`PLIGA`**: LID for PSet LIGAs, always double `PLID`, `~~` by default
- **`Positional`**: Positional parameters without a LID, simply strings
- **`pp-zone`**: the part of CML afer `ZN-SEP` contains Optionals in `watershed` style CML
- **`Prior`**: prior parsing PSets, used to customize PASs
- **`PRLID`**: LID for Priors, `~~~` by default, cannot be customized
- **`PSet`**: parameters to config BosParse
- **`PFILTER`**: an associative array with definitions of User Options created by user for advance features; `PFILTER` passed to BosParse via the PSet `~pf` with `PFILTER`'s name reference or a JSON string(serialized `PFILTER`) or a `keys-values` string
- **`RESYMS`**: a character set includes BosParse reserved characters used in PASs.
- **`run-mode`**: method to use BosParse. BosParse will detect which mode it's running if no `run-mode` explicitly specified by user(via PSet `-run` )
- **`TD`**: default value if trailing tag omitted, set by `~~~td`
- **`TF`**: trailing tag for `false`, set by `~~~tf`
- **`TT`**: trailing tag for `true`, set by `~~~tt`
- **`ULID`**: LID for User Options, `-` by default, customize by `~~~ulid`
- **`ULIGA`**: LID for User LIGAs, always double `ULID`
- **`watershed`**: command line structure style with a clear separator between Options and Positionals, support space(s) as OA-SEP, while `ZN-SEP` is required to separate Options and Positionals
- **`ZN-SEP`**: separator between Options and Positionals in `watershed` style CML
