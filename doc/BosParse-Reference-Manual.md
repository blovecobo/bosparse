# BosParse Reference Manual

## Overview

BosParse is a powerful tool designed to parse command-line arguments in a flexible and efficient manner. This manual outlines the architecture, workflow, and implementation details of BosParse to guide developers in understanding and using it effectively.

## Architecture

BosParse follows workflow-driven architecture, where each step is designed to be executed sequentially. The core stages of BosParse include:

1. **Prior Parsing**: Parsing Prior arguments, which will setup the Parsing-Aid-Symbols (PAS)
1. **PSet Parsing**: Parsing PSet arguments, which will setup essential parsing options
1. **Parsing User Parameters**: Parsing user parameters, which will extract the user's input,validate parsing results if needed
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
1. Validate all user parameters if PFILTER is provided

### Output Parsing Results

Output parsing results according to the run-mode specified by the user.

#### Source Mode

By default, BosParse outputs as follows:

1. Output all Options as shell variables
1. Output all Positional Arguments as an associative array named `BP_Positionals` by default

If user specified, output:

- all Options in an associative array using the name specified by `~oan`
- all String options in an associative array using the name specified by `~san`
- all Boolean options in an associative array using the name specified by `~ban`
- all Positional arguments in an index array using the name specified by `~pan`

#### Eval Mode

By default, BosParse outputs shell assignments for `eval $(...)`:

1. Output all Options in shell assignments with the format `name=value`
1. Output all Positional Arguments in shell assignments with the format `BP_Positionals_<index>=<value>`

If `~oan` specified, output positional arguments with the format `~oan=ps` -> `ps_<index>=<value>`

#### Capture Mode

Output all Options and Positional arguments in JSON format.

## Main Data Structures

1. **CONSTANTS**: This structure contains all the constants used in BosParse
1. **CONFIGS**: This structure contains all the configurations used in BosParse
1. **PRIORS**: Contains all the Priors provided for user to customize PAS; all Prior setings wil be stored in `CONFIGS` at runtime
1. **PSETS**: Contains all the PSet provided for user to customize PFILTER; all PSet settings wil be stored in `CONFIGS` at runtime
1. **RESERVED_SYMBOLS**: Contains all the reserved symbols used by PAS
1. **EXIT_MSG**: Contains all the exit codes and messages used by BosParse
1. **PFILTER**: Contains all user parameter definitions, including parameter names, types, default values, available enum values , prefix matching for paramters/enum values and mutual correlation groups
   BosParse outputs JSON for machine-readable output

## Parameter Definition

BosParse supports flexible parameter definition using PFILTER by user, which is an associative array containing all the necessary information for parsing user parameters. With the help of PFILTER, BosParse can parse user parameters in a flexible way, including type checking, value validation, default value assignment, prefix matching for parameter names and enum values, as well as mutual correlation groups for parameters.


#### Syntax of PFILTER entry

The syntax of PFILTER entry is as follows:

```bash
[param-name]="type:data:mcg-name"
```

Where:

- **param-name**: the name of the parameter
- **type** field: the type of the parameter, which can be 'string', 'boolean' or 'enum'
- **data** field: the data for the parameter, which can be default value, or a list of available values for 'enum' separated by `|` (pipe)
- **mcg-name** field: the name(s) of the mutual correlation group(s), which can be used to group parameters that are mutually correlated; multiple group names can be separated by `|` (pipe)

Data field and mcg-name field are optional.

### PFILTER-ID

PFILTER-ID is a special entry in PFILTER, which is used to validate the PFILTER:

```bash
["PARAM-FILTER"]="any-string-or-empty"
```

The value of PFILTER-ID entry does not matter while the key `PARAM-FILTER` is reserved for PFILTER-ID; BosParse will check the existence of PFILTER-ID entry to determine if PFILTER is valid or not.

### PFILTER-related PSets

- `~pf`: Pass PFILTER to BosParse, should be a name reference(source mode) or a serialized PFILTER(JSON string, for all modes)
- `~amf`: Restrict unknown parameters, an un-difined parameter will be rejected if `~amf` is set
- `~apfd`: Apply PFILTER defaults for paramters not belong to any MCG; MCG member parameters follow group rules.
- `fmi`: forbid m-member of master MCG from supplying; if `~fmi` set, m-member of master MCG will
  not be allowed to supply, and must get value from the assigned M-member or default value(if no
  M-member supplied); if `~fmi-` set, m-member of master MCG can also supply value, which will
  override the assigned M-member's value or default value(if no M-member supplied)

### Prefixes-matching

BosParse supports prefixes-matching for parameter names and enum values.

```bash
["help"]="bool:false"
["fruit"]="enum:apple|banana|cherry"
```

When no ambiguity is found, BosParse will use the prefix-matched parameter:

`-h`, `-he`, `-hel`, `-help` will all be matched to `help`
`-f=b` or `-f b` will be matched to `banana`

### Last enum matching

When a Enum type parameter is provided using Boolean syntax, BosParse will use the last value in the enum values list:

```bash
["color"]="enum:red,green,blue"
```

When `-c` is provided, BosParse will use `blue`

### MCG support

BosParse supports MCG, which are used to define a set of parameters that are mutually correlated.
See details in section "Mutual Corelation Groups"

## Mutual Correlation Groups

MCGs enforce relationships between parameters. Parameters can belong to more than one group.

### Group Types

- **Dependency (`d`/`D` prefix)**: d-members depend on D-members
- **Exclusion (`e` prefix)**: One or none parameter in the group can supply
- **Masters(`m`/`M`)**: m-member assigned to the name of the supplied M-member
- **Required (`required`)**: members must be supplied or fulfilled
- **Sibling (`s` prefix)**: All members must supplied together or omitted together
- **Uniqueness (`u` prefix)**: Parameters must have different values

### Detailed Rules

- **Dependency Groups**

  d-member(s) require D-member supplied; D-members can be supplied without d-members; error if m-members supplied without D-members.

- **Exclusion Groups**

  Group members are mutually exclusive; if more than one member supplied, parsing fails.

- **Master Groups**

  Master group includes M-members and a m-member.

  m-member assigned to the supplied M-member's name, or to the default value if no M-member supplied.

  Error if:

  1. More than one M-member supplied, or
  1. M-member supplied together with m-member, or
  1. No M-member supplied and m-member have no default value, or
  1. No M-member supplied and apply default value forbidden(`~fmi` set)

- **Required Groups**

  All members must be supplied or can be assigned default values; error if any member is missing and cannot be assigned a default value.

- **Sibling Groups**

  All members must supply together, or all omitted. Defaults assigned to missing members if available; error if defaults not available for missing members.

- **Uniqueness Groups**

  All supplied members must have different values; if any two members have the same value, parsing fails.

  Members not supplied will be ignored.

### **MCG Validation Order**

As default value assignment might affect validation result, validation order matters.

1. Check required rules and assign defaults
1. Check sibling rules and assign defaults
1. Check exclusion/uniqueness rules
1. Check dependency rules
1. Check master rules

## Command line structure

Bosparse accepts the following command line structure:
`op-zone` `zn-sep` `pp-zone`
where:

- `op-zone`: contains all the Option parameters, including Priors, PSets and User Options
- `zn-sep` (`--` by default): separator between Option parameters and Positional parameters
- `pp-zone`: contains all the Positional parameters

A `zn-sep` is always recommended even if only one zone is provided. While if `zn-sep` not found, BosParse will try to 'guess': if the first paramter is an Option parameter(starts with any LID), BosParse will assume that only `op-zone` is provided; otherwise, Bosparse will assume that only `pp-zone` is provided.

## Parameter Schema and Types

BosParse supports the following parameter types:

- `Option Parameter` (Option): parsable Option parameters should be with the following syntaxes:

  - Schema 1: `<LID> <Option-name> <OA-SEP> <Option-value>`
  - Schema 2: `<LID> <Option-name> <SPACE{1,}> <Option-value>`
  - Schema 3: `<LID> <Option-name> [Trailing-Tag]`
  - Schema 4: `<LID> <length-option-name> <Option-names> [Trailing-Tag]`

  Option parameters always start with a LID. Different LIDs can be used to distinguish between different types of parameters. BosParse support 'string', 'boolean', 'enum' and 'liga' options, which can be distinguished by different LIDs and syntaxes:

  - **String Option**: support string; using schema '1' and '2', like `-name=value` or `-name value` -> `name=value`
  - **Boolean Option**: support boolean; using schema '3', like `-verbose+`, `-verbose-` or `-verbose` -> `verbose=` `true`,`false` and `true`(if `~td` is `true`) respectively
  - **Enum Option**: support enum; using schema '1' and '2', similar to String Option but with limited available values
  - **LIGA Option**: compressed Booleans; using schema '4', like `--abc+` is equivalent to `-a+ -b+ -c+`, or `--2abcdef-` is equivalent to `-ab- -cd- -ef-`

  Differnt LIDs for different type of options, see section 'Terminology' for more details.

- `Positional Parameter` (Positional)
  Positional parameters are simply strings, without any special syntax.

## Directives

Directives are a group of special `PSets`, which will lead to execute specific actions.

Directives execute after `PSets` parsing, then the parser will exit at once; that means all User Parameters will be ignored.

BosParse supports the following directives:

- `~Banner`: Show banner, mainly used to test if BosParse is working
- `~Default`: Show default settings, all data from `CONFIGS` will be shown
- `~Help`: Show help(not implemented)
- `~Resymbols`: Show reservable symbol set for PAS except FLD_SEP and ELM_SEP
- `~Version`: Show BosParse version

## Configuration Options

1. Priors - Parsing-aid symbols setting

   - Leading-ids
     - `~~~plid` (default `-`): prefix of PSets
     - `~~~ulid` (default `_`): prefix of user options
   - Trailing-tags
     - `~~~tf` (default `-`): `false` tag for boolean options
     - `~~~tt` (default `-`): `true` tag for boolean options
     - `~~~td` (default `true`): default tag if no tag is specified
   - Separators
     - `~~~zs` (default `--`): separator between Option parameters and Positional parameters
     - `~~~os` (default `=`): separator between Option parameters and values
   - Runtime output controls(for PSet parsing stage; will be reset by PSet settings before User-option parsing)
     - `~~~quiet`: Suppress all output include errors
     - `~~~standard`: Output standard information, error message mainly
     - `~~~extra`: Output extra information
     - `~~~debug`: Output debug format
     - `~~~trace`: Output trace format
     - `~~~config`: Output configurations after Priors parsing

1. PSets - Parser settings

   - Runtime mode and output format

     - `~json`: JSON output
     - `~run`/`~mode`: Run-mode setting, available modes: `source`, `eval` and `capture`
     - `~oan`, `~san`, `~ban`, `~pan`: Specify array names of parsing result

   - PFILTER related

     - `~pf`: Pass PFILTER to BosParse
     - `~amf`: Restrict unknown parameters(all-matching-filter)
     - `~apfd`: Apply PFILTER defaults
     - `~fmi`: forbid m-member of master MCG from supplying

   - Directives

     - `~Banner`: Show banner
     - `~Default`: Show default settings
     - `~Help`: Show help(not implemented)
     - `~Resymbols`: Show reservable symbols used by PAS
     - `~Version`: Show BosParse version

   - Runtime output controls (for user options parsing stage)

     - `~quiet`: Suppress all output include errors
     - `~standard`: Output standard information
     - `~extra`: Output extra information
     - `~debug`: Output debug format
     - `~trace`: Output trace format
     - `~config`: Output configurations after PSet parsing

## Terminology

- **`Directive`**: a set of special PSets which will lead to execute specific actions, like showing banner or version, then exit immediately
- **`ELM-SEP`**: separator between enum values or MCG names in PFILTER and config arrays
- **`FLD-SEP`**: separator between entry fields in PFILTER and config arrays
- **`LID`**: Leading identifier, used to distinguish Option types
- **`LIGA`**: ligature style parameter, used to pass multiple boolean Options with one parameter
- **`MCG`**: Mutual Correlation Group, a group of parameters with mutual correlation rules; MCGs defined in PFILTER and validated after parsing
- **`OA-SEP`**: separator between Option name and its value
- **`Option`**: parsable parameters with a LID, including Priors, PSets and User Options; different LIDs can be used to distinguish different types of options
- **`PAS`**: Parsing-Aid-Symbols, e.g. LIDs, SEPs, PAS consist of RESYMS
- **`PLID`**: LID for PSets, `~` by default, customieze with PSet `~~~plid`
- **`PLIGA`**: LID for PSet LIGAs, always double `PLID`, `~~` by default
- **`Positional`**: positional parameters without a LID, simply strings
- **`Prior`**: prior parsing PSets, used to customize PASs
- **`PRLID`**: LID for Priors, `~~~` by default, cannot be customiezed
- **`PSet`**: parameters to config BosParse
- **`PFILTER`**: an associative array with definitions of Options created by user for advance features; PFILTER pass to BosParse via the PSet `~pf` with PFILTER's name reference or a JSON string(serialized PFILTER)
- **`RESYMS`**: a character set includes BosParse reserved characters used in PASs.
- **`run-mode`**: method to use BosParse. BosParse will detect which mode it's running if no `run-mode` explicitly specified by user(via `-run` or `~mode`)
- **`TD`**: default value if trailing tag omitted, set by `~td`
- **`TF`**: trailing tag for `false`, set by `~tf`
- **`TT`**: trailing tag for `true`, set by `~tt`
- **`ULID`**: LID for User parameters, `-` by default, customize by `~~~ulid`
- **`ULIGA`**: LID for User LIGAs, always double `ULID`
- **`ZN-SEP`**: separator between Options and Positionals in CML
