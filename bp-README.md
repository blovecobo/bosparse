# BosParse

Parse command-line parameters in one-shot

## Feature

- Parse all parameters in one shot; no further parsing needed.
- Support both option parameters (Options) and positional parameters (Positionals).
- Flexible parameter naming and value assignment.
- Customizable parsing-aid symbols (leading-ids, trailing-tags, separators).
- Multiple run modes for different use cases (source, eval, capture).
- Autodetection of run mode based on context and provided PSets.
- Optional parameter filtering and validation via PSets.
- Parameter validating, default assigning, name prefix-matching, relation grouping etc. by PFILTER

## Command line pattern

The command line is split into two zones separated by a zone separator (`ZONE-SEP`):

`OP-ZONE` `ZONE-SEP` `PP-ZONE`

- OP-ZONE (Option Parameter Zone): contains Options (option parameters) and PSets (parser settings).
- PP-ZONE (Positional Parameter Zone): contains Positionals (positional parameters).
- ZONE-SEP (Zone Separator): separator between OP-ZONE and PP-ZONE

A `ZONE-SEP` is recommended even if only one zone exists.

## Parameter types

- **Positional**: positional parameter — a single string parsed into an indexed array `BP_Positionals()`.
- **Option**: option parameter — parsed into variable/value pairs.
  - _String-Option_: `-name=value` or `-name value`
  - _Bool-Option_: `-flag` (value inferred from trailing tag, `+`/`-`)
- **ARG**: an argument for a String-Option.
- **LIGA**: compressed bools in one parameter (e.g. `--2abcdef` → `ab=true cd=true ef=true`).
- **PSet**: parser setting parameter (leading-id by default uses `~`).

## Parameter syntax

- Option: `-name=value` or `-name value` for String-Options; `-flag+` or `-flag-` or `-flag` for Bool-Options.
- LIGA: `--[number][flags][trailing-tag]` (e.g. `--ab-` → `a=false b=false`).
- PSet: `~key=value` (e.g. `~run=capture`

## Parameter naming

- **Options**: parameter name will be used as variable name, so Option name should honor bash variable nameing convention.<br>
  As an exception, using hyphen `-` in Option name permitted if it did'nt at the beginning or end of the paramter name, while all hyphens will be replaced by underscores `_` in the final result
- **Positionals**: should be a valid bash string; if special charactors included(space e.g.), it must be quoted, or use variables with quotes to pass.

## Parsing-aid Symbols

BosParse using Parsing-aid Symbols(PAS) to expact and identify command line parameters, including Leading-ids(LID), Trailing-tags(TAG) and Zone-separators(SEP).

Leading-ids (LIDs) distinguish User-options, LIGAs, PSets and Priors, by default:

- User-option LID(ULID) `-`, for user options
- User-option LIGA LID(ULIGA) `--`, for user ligatures
- PSet LID(PLID) `~`, for parser-setting options
- PSet LIGA LID(PLIGA) `~~`, for ligutures of PSets
- Prior LID(PRLID) `~~~`, for prior-parsing PSets
- Positionals and ARGs need no LIDs

Trailing-tags (TAGs) specifies values(`true/false`) for Bool-Options and LIGAs, they are 'ARGs' for Bool-Options and LIGAs,  by default:

- Tag-for-true(TT) `+`, used to identify a bool or a liga to assign to `true`
- Tag-for-false(TF) `-`, identifying a boo/liga assign to `false`
- Tag-for-default(TD) `true`, specifying default trailing-tag represent `true`

Separators (SEPs) help for separate Zones and Option/ARG, by default:

- Zone separator(ZONE-SEP) `--`, separate positinal paramter from others(options, args)
- Option-ARG separator(OA-SEP) `=`, separate an arg from options it serves

Notes:

- All LIDs and SEPs are customizable except for the LIGAs.
- PLIGAS/ULIGAS is set as doubles of PLID/ULID; and will change automatically with PLID/ULID
- Charactors permitted to use in PAS are reserved symbols(RESYMs); a directive PSet (~Resymbols) used to check all availables.

## Result passing and run-mode

BosParse determines how to return results using a PSet `run-mode`. Precedence for run mode (highest → lowest):

1. PSet `~run/~mode` provided on the command line
2. Autodetection (when `~run/~mode` not set explicitly)

Autodetection heuristics (used when `run-mode` not explicitly set):

- If the BosParse script is sourced (`source bosparse`), `run-mode` = `source`.
- Else if `~json` not set, `run-mode` = `eval` (human-friendly output).
- Else if `~json` set, `run-mode` = `capture` (output as JSON)

Modes:

- `source`: create variables and arrays in the current shell (recommended).
- `eval`: human-readable output suitable for `eval $(...)` usage.
- `capture`: JSON output on stdout for programmatic consumption.

Note: autodetection is default setting; explicit `~run/~mode` is always the priority.

Results:

- For `source`/`eval` mode:
  - Option:
    - a variable created with the name after the Option name and assign to it's ARG or TAG.
  - Positional:
    - all Positionals loaded into an index array named `BP_Positionals()`(source mode), or
    - each Positional create a variable `bp_positionals_xx` assign with Positional string (eval
      mode), `xx` refers to the occuring order in command line.
- For `capture` mode:
  - All parsing result output to stdout in JSON.

## Important PSets (defaults shown)

- `~run` or `~mode` (running mode): `auto` (default), `source`, `eval`, `capture`
- `~json-` (output as JSON): for `capture` mode.
- `~pf` (parameter filter): for validation parameter name/value, name matching, etc.(see `bp-PFILTER.md`)
- `~amf-` (all matching filter): used together with `~pf` to fillter out parameters not in PFILTER

## Directives

- `~BANNER`, display a BosParse tag, default is `Parsed by BosParse with love`
- `~RESYMS`, display all parsing-aid symbols in use and exit
- `~VERSION`, display version and exit

if any directive is present on the command line, BosParse will execute the directive and exit
immediately without parsing other parameters.

## Usage examples

Source mode (create variables in current shell):

```bash
# auto detected 'source' mode; parameter 'hero' assigned with 'Tom Hanks'
source ./bosparse
bosparse -hero="Tom Hanks" --
echo "hero name: ${hero}"
```

Eval mode:

```bash
# auto detected mode 'eval'; parameter 'graduated' will assign with false by trailing-tag '-'
eval $(bosparse -graduated- --)
echo "${graduated}"
```

Capture mode (JSON):

```bash
# explicitly specify 'capture' mode for JSON output
favor=$(bosparse ~run=capture -movie-name="Gone with the Wind" --)
favor_movie=$(echo "${favor}" | jq -r '.movie_name')
echo "${favor_movie}"
```

Autodetected

```bash
# JSON output specified, 'capture' mode; parameter 'protocal' assign with ARG 'HTTPS'
js=$(bosparse ~json -protocol="HTTPS" --)
protocol=$(echo "${js}" | jq -r '.protocol')
echo "${protocol}"
```

Force mode explicitly:

```bash
# force capture mode with positional parameters
bosparse ~run=capture -movie-name="True Lies" -- "perfect movie" | jq '.Positionals[]'
```

## Notes

- Leading-ids and trailing-tags must not conflict.
- Hyphen `-` should not be used as the OA-SEP.
- Strings that look like `true`/`false` interpreted as booleans; use different capitalization to preserve as strings.
- By default, BosParse validate Option names to ensure they can be used as bash variable names (with hyphens replaced by underscores).
- As a hyphen `-` permitted in Option names (except at the beginning and end), and all hyphens will be replaced by underscores `_` in the final variable names, that means two parameters with the names like
  `-my-param` and `-my_param` will be treated as the same parameter, and will be regarded as a parameter  supplied twice if using in the same command line. At this time, the first one will be overridden by the latter(latter-win-principle)in the final result, so it's recommended to avoid using both hyphens and underscores in Option names to prevent confusion.
- BosParse introduced PFILTER suppored by PSets `~pf`, `~amf` adn `~apfd` to supply more functionalities for Options parsing, such as value/type validation, name prefix-matching, default value, correlation grouping and more. Details can be found in `bp-pfilter.md`.

## Requirements

Requirements: `bash` (4.4+), `jq`.
