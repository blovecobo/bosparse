# bosparse

Parse command-line parameters for bash scripts with predictable, machine-friendly output.

## Feature

- Parse all parameters in one shot; no pre-define or further parsing needed.

## Command line pattern

The command line is split into two zones separated by a zone separator (`ZSEP`):

- OP-ZONE (Option Parameter Zone): contains OParas (option parameters) and PSets (parser settings).
- PP-ZONE (Positional Parameter Zone): contains PParas (positional parameters).

A `ZSEP` is recommended even if one zone exists.

## Parameter types

- **PPara**: positional parameter — a single string added to the `PParas` array.
- **OPara**: option parameter — parsed into variable/value pairs.
  - _String-OPara_: `-name=value` or `-name value`
  - _Bool-OPara_: `-flag` (value inferred from trailing tag, `+`/`-`)
- **ARG**: an argument for a String-OPara.
- **LIGA**: compressed  bools in one parameter (e.g. `--2abcdef` → `ab=true cd=true ef=true`).
- **PSet**: parser setting parameter (leading-id by default uses `~`).

Parameter naming

- OPara: paramter name will be used as variable name, so OPara name should honor bash variable nameing convention.
  As an exception, using hyphen `-` in OPara name permitted if it did'nt at the beginning of the
  paramter name, while all hyphens will be replaced by underscores `_` in the final result
- PParas: should be a valid bash string; if special charactors included, use variables with quotes to pass

## Parsing-aid Symbols

Leading-ids (LIDs) distinguish OParas, LIGAs, PSets and Priors, by default:

- Prior LID: `~~~` (PRLID)
- PSet LID: `~` (PLID)
- OPara LID: `-` (OLID)
- OPara LIGA LID: `--` (OLIGA)
- PSet LIGA LID: `~~` (PLIGA)

Trailing-tags (TAGs) specifies values(`true/false`) for Bool-OParas, by default:

- Tag-for-true: `+` (TT)
- Tag-for-false: `-` (TF)
- Tag-for-default: `true` (TD)

Separators (SEPs) help for separate Zones and parameters, by default:

- Zone separator: `--` (ZSEP)
- OPara-ARG separator: `=` (OSEP)

All LIDs and SEPs are customizable except for the Prior LID (`~~~`), which may used to set PSet
LID.

## Result passing and run-mode

Bosparse determines how to return results using a `run-mode`. Precedence for run mode (highest → lowest):

1. PSet `~run` provided in the command line
2. Autodetection (when `~run` not set explicitly)

Autodetection heuristics (used when `run-mode` not explicitly set):

- If the script is sourced (`source bosparse`), mode = `source`.
- Else if `~j` not set, mode = `eval` (human-friendly output).
- Else if `~j` set, mode = `capture` (output as JSON)

Modes:

- `source`: create variables and arrays in the current shell (recommended).
- `eval`: human-readable output suitable for `eval $(...)` usage.
- `capture`: JSON output on stdout for programmatic consumption.

Note: autodetection is heuristic — prefer explicit `~run` in scripts and CI.

Results:

- For `source`/`eval` mode:
  - OPara: a variable created with the name after the parameter name and assign with it's ARG.
  - PPara: all positional parameters loaded into an index array named `BP_PPara()`
- For `capture` mode:
  - All parsing result output to stdout in JSON.

## Important PSets (defaults shown)

- `~run` (running mode): `source`, `eval`, `capture` (autodetected if omitted)
- `-j` or `~json` (output as JSON): for `capture` mode.

## Usage examples

Source mode (create variables in current shell):

```bash
# soured, source mode; parameter assigned with 'Tom Hanks'
source ./bosparse
bosparse -hero="Tom Hanks" --
echo "hero name: ${hero}"
```

Eval mode:

```bash
# auto detect run mode; parameter will assign with false by trailing-tag '-'
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
# JSON output specified, 'capture' mode
js=$(bosparse ~j -protocol="HTTPS" --)
protocol=$(echo "${js}" | jq -r '.protocol')
echo "${protocol}"
```

Force mode explicitly:

```bash
# force capture mode with positional parameters
bosparse ~run=capture -movie-name="True Lies" -- "perfect movie" | jq '.PParas[]'
```

## Notes

- Leading-id characters and trailing-tags must not conflict.
- Hyphen `-` should not be used as the OSEP.
- Strings that look like `true`/`false` interpreted as booleans; use different capitalization to preserve as strings.

## Requirements

Requirements: `bash` (4.4+), `jq`.
