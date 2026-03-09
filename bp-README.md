# bosparse

Parse command-line parameters for bash scripts with predictable, machine-friendly output.

## Feature

- Parse all parameters in one shot; no further parsing needed.
- Support both option parameters (OParas) and positional parameters (PParas).
- Flexible parameter naming and value assignment.
- Customizable parsing-aid symbols (leading-ids, trailing-tags, separators).
- Multiple run modes for different use cases (source, eval, capture).
- Autodetection of run mode based on context and provided PSets.
- Optional parameter filtering and validation via PSets.

## Command line pattern

The command line is split into two zones separated by a zone separator (`ZSEP`):

`OP-ZONE` `ZSEP` `PP-ZONE`

- OP-ZONE (Option Parameter Zone): contains OParas (option parameters) and PSets (parser settings).
- PP-ZONE (Positional Parameter Zone): contains PParas (positional parameters).
- ZSEP (Zone Separator): separator between OP-ZONE and PP-ZONE

A `ZSEP` is recommended even if one zone exists.

## Parameter types

- **PPara**: positional parameter — a single string parsed into an indexed array `BP_PPara()`.
- **OPara**: option parameter — parsed into variable/value pairs.
  - _String-OPara_: `-name=value` or `-name value`
  - _Bool-OPara_: `-flag` (value inferred from trailing tag, `+`/`-`)
- **ARG**: an argument for a String-OPara.
- **LIGA**: compressed bools in one parameter (e.g. `--2abcdef` → `ab=true cd=true ef=true`).
- **PSet**: parser setting parameter (leading-id by default uses `~`).

## Parameter syntax
- OPara: `-name=value` or `-name value` for String-OParas; `-flag+` or `-flag-` or `-flag` for Bool-OParas.
- LIGA: `--[number][flags]` (e.g. `--ab` → `a=true b=true`).
- PSet: `~key=value` (e.g. `~run=capture`

## Parameter naming

- OPara: parameter name will be used as variable name, so OPara name should honor bash variable nameing convention.
  As an exception, using hyphen `-` in OPara name permitted if it did'nt at the beginning of the paramter name, while all hyphens will be replaced by underscores `_` in the final result
- PParas: should be a valid bash string; if special charactors included, use variables with quotes to pass in is recommended.

## Parsing-aid Symbols

Leading-ids (LIDs) distinguish OParas, LIGAs, PSets and Priors, by default:

- Prior LID: `~~~` (PRLID)
- PSet LID: `~` (PLID)
- OPara LID: `-` (OLID)
- OPara LIGA LID: `--` (OLIGA)
- PSet LIGA LID: `~~` (PLIGA)
- PParas and ARGs need not any LIDs

Trailing-tags (TAGs) specifies values(`true/false`) for Bool-OParas and LIGAs, by default:

- Tag-for-true: `+` (TT)
- Tag-for-false: `-` (TF)
- Tag-for-default: `true` (TD)

Separators (SEPs) help for separate Zones and OPara/ARG, by default:

- Zone separator: `--` (ZSEP)
- OPara-ARG separator: `=` (OSEP)

All LIDs and SEPs are customizable except for the Prior LID (`~~~`), which may used to set PSet LIDs.

## Result passing and run-mode

Bosparse determines how to return results using a `run-mode`. Precedence for run mode (highest → lowest):

1. PSet `~run/~mode` provided in the command line
2. Autodetection (when `~run/~mode` not set explicitly)

Autodetection heuristics (used when `run-mode` not explicitly set):

- If the bosparse script is sourced (`source bosparse`), `run-mode` = `source`.
- Else if `~json` not set, `run-mode` = `eval` (human-friendly output).
- Else if `~json` set, `run-mode` = `capture` (output as JSON)

Modes:

- `source`: create variables and arrays in the current shell (recommended).
- `eval`: human-readable output suitable for `eval $(...)` usage.
- `capture`: JSON output on stdout for programmatic consumption.

Note: autodetection is heuristic — prefer explicit `~run/~mode` in scripts and CI.

Results:

- For `source`/`eval` mode:
  - OPara:
    - a variable created with the name after the OPara name and assign with it's ARG.
  - PPara:
    - all PParas loaded into an index array named `BP_PPara()`(source mode), or
    - each PPara create a variable `ppara_xx` assign with PPara string (eval mode)
- For `capture` mode:
  - All parsing result output to stdout in JSON.

## Important PSets (defaults shown)

- `~run` or `~mode` (running mode): `auto` (default), `source`, `eval`, `capture`
- `~json-` (output as JSON): for `capture` mode.
- `~pf` (parameter filter): for validation parameter name/value, name matching, etc.(see `bp-PFILTER.md`)
- `~amf-` (all matching filter): used together with `~pf` to fillter out parameters not in PFILTER

## Directives

- `~version`, display version and exit
- `~tag`, display a bosparse tag, default is `Parsed by BosParse with love`
- `~resyms`, display all parsing-aid symbols in use and exit

* if any directive is present in the command line, bosparse will execute the directive and exit
  immediately without parsing parameters.

## Usage examples

Source mode (create variables in current shell):

```bash
# soured, 'source' mode; parameter 'hero' assigned with 'Tom Hanks'
source ./bosparse
bosparse -hero="Tom Hanks" --
echo "hero name: ${hero}"
```

Eval mode:

```bash
# auto detect run mode 'eval'; parameter 'graduated' will assign with false by trailing-tag '-'
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
bosparse ~run=capture -movie-name="True Lies" -- "perfect movie" | jq '.PParas[]'
```

## Notes

- Leading-ids and trailing-tags must not conflict.
- Hyphen `-` should not be used as the OSEP.
- Strings that look like `true`/`false` interpreted as booleans; use different capitalization to preserve as strings.
- By default, bosparse validate OPara names to ensure they can be used as bash variable names (with hyphens replaced by underscores).
- bosparse introduced `~pf` and `~amf` PSets to supply more functionalities for OPara parsing, such as value validation, prefix-matching name, default value, and more. Details can be found in `bp-pfilter.md`.
- As a hyphen `-` permitted in OPara names (except at the beginning), and all hyphens will be replaced by
  underscores `_` in the final variable names, that means two parameters with the name like
  `-my-param` and `-my_param` will be treated as the same parameter, and only one of them will be
  kept in the final result, which is determined by the order of parameters in the command line (the
  later one will override the previous one). So it's recommended to avoid using both hyphens and
  underscores in OPara names to prevent confusion.

## Requirements

Requirements: `bash` (4.4+), `jq`.
