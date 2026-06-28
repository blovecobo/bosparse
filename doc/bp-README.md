# BosParse

**BosParse** is a Bash command-line parser that converts command line parameters into shell variables or JSON output.

## Quick Start

- Source mode

```bash
#!/usr/bin/env bash
source ./bosparse
bosparse "$@"

echo "name=$name"
echo "verbose=$verbose"
echo "first positional=${BP_Positionals[0]}"
```

Run it:

```bash
./script.sh -name=alice -verbose+ -- file1.txt file2.txt
```

- Eval mode

```bash
#!/usr/bin/env bash
eval "$(./bosparse "$@")"
echo "name=$name"
```

> Note: `eval` mode executes generated shell assignments. Only use it when the invocation and parameter names are trusted. For details and mitigations, see the Reference Manual: [Eval Mode Security](./BosParse-Reference-Manual.md).

Run it:

```bash
./script.sh -name alice -- data.txt
```

- Capture mode (JSON output)

```bash
json=$(./bosparse ~json "$@")
name=$(capture_json_extract "$json" '.name // ""')
echo "name=${name}"
```

This uses the new helper `capture_json_extract` to read values safely from capture-mode JSON output.

```bash
#!/usr/bin/env bash
result=$(./bosparse ~json "$@")
echo "$result" | jq '.'
```

Run it:

```bash
./script.sh -name=alice -active+ -- file1.txt
```

## Command Line Structure

BosParse supports two main styles of command line structures: `watershed` and `islands`.

```bash
[OP-ZONE] [ZN-SEP] [PP-ZONE] # watershed style
[OPTIONS | POSITIONALS]      # islands style
```

- `OP-ZONE`: Options and parser settings
- `PP-ZONE`: Positional values
- `ZN-SEP`: zone separator(`--` by default) that distinguishes Options from Positionals
- `OPTIONS`: Options parameters that set variables
- `POSITIONALS`: values that become Positional parameters

The main difference between the two styles is how they handle the separation of Options and Positionals:

- `watershed` style(default) uses `ZN-SEP` to separate Options and Positionals, while `islands` style allows intermixing Options and Positionals.
- In `watershed` style, Options must come before `ZN-SEP`, and Positionals must come after.
- `islands` style, Options and Positionals may be mixed in any order, but Options must use `OA-SEP` ( `=` by default) to separate name and value. In `watershed` style, space-separated option values are also allowed.

## Supported Parameters

### Option parameters

- `-name=value`
- `-name value` (same as `-name=value`, only available in `watershed` style CML)
- `-flag+` sets boolean true
- `-flag-` sets boolean false
- `-flag` set `true` (default setting)
- `-flag=true` or `-flag true` sets booleans not strings

Example:

```bash
./script.sh -username=john -quiet- -output /tmp/out.txt -- file.txt
```

### Positional parameters

In `watershed` style CML, everything after `ZN-SEP (-- by default)` becomes Positional values in the `BP_Positionals` array:

```bash
./script.sh -name=bob -- one two three
```

In `islands` style CML, Positionals can be interspersed with Options:

```bash
./script.sh -name=bob one two -verbose+ three
```

### LIGA-style flags

Ligatures compress boolean flags:

```bash
./script.sh --abcd --
./script.sh --2abcdef --
```

This sets `a=true`, `b=true`, `c=true`, `d=true`, or `ab=true`, `cd=true`, `ef=true`.

## Parser Harnesses (`~` `~~` `~~~`)

Parser Harnesses are parameters used to configure the parser. They use the `~` LID and control how BosParse behaves and outputs results.

They do not set variables directly but affect the parsing process and output format.

### Common settings

- `~~~style`: command line structure style, `watershed`(default) or `islands`
- `~~os`: separator for option names and args, `=` by default
- `~~tt` and `~~tf`: trailing tags for booleans, `+`/`-` by default
- `~json`: produce JSON output
- `~run`: run-mode setting, `auto` (default), `source`, `eval`, `capture`
- `~dvo`: disable variables output; for source mode only
- `~quiet`, `~standard`, `~extra`, `~debug`, `~trace`: output control, `~quiet` by default
- `~oan`, `~pan`: specify array names of parsing result
- `~Banner`, `~Version`, `~Resymbols`, `~Defaults`, `~Help`: display BosParse properties

Example:

```bash
./script.sh ~run=capture -name=alice -active+ -- file.txt | jq .
```

## Important Features

- Options sequence is insensitive for params in OP-ZONE (`watershed`) or the whole CML (`islands`)
- When the same parameter supplied multiple times, the latter wins; when the same parameter name used with different types, parsing fails
- If a boolean parameter is supplied as both a standalone boolean and a member of a LIGA-style flag, the boolean setting takes precedence
- BosParse supports prefix-matching on Harnesses name and enum values in all Harnesses scope, e.g. `~r=j` -> `~run=json`
- Prefix-matching on user parameters needs `PFILTER` support, see BosParse-Reference-Manual.md#Prefix-Matching
- Parameters like `-flag=true` or `-flag=false` are parsed as boolean, not string

## Run Modes

- `source`: sets variables directly in the current shell
- `eval`: outputs shell assignments for `eval $(...)`
- `capture`: outputs JSON

### Safe vs eval mode

- `source` is the safest mode when BosParse is sourced into your own script and you need direct shell variables.
- `eval` emits shell assignments and executes them, so only use it when the BosParse invocation, option names, and any PFILTER-derived identifiers are trusted.
- `capture` mode is the safest option for external or untrusted input. Use `~json` and parse the JSON output with `jq` or `capture_json_extract`.

Quick whitelist snippet (capture mode):

```bash
# capture JSON and assign only known keys
json=$(./bosparse ~json "$@")
for k in name active timeout; do
  v=$(jq -r --arg k "${k}" '.[$k] // empty' <<<"${json}")
  [[ -n ${v} ]] && printf -v "${k}" '%s' "${v}"
done
```

## Examples

### Source mode

```bash
source ./bosparse
bosparse -name="Jane Doe" -verbose+ -- file.txt
```

Result:

- `name=Jane Doe`
- `verbose=true`
- `BP_Positionals[0]=file.txt`

### Eval mode

```bash
eval "$(./bosparse -name=alice -active- -- file1.txt)"
```

Result:

- `name=alice`
- `active=false`
- `BP_Positionals_0=file1.txt`

### Capture / JSON mode

```bash
./bosparse ~json -name=alice -active+ -- file1.txt | jq .
```

output:

```json
{
  "name": "alice",
  "active": true,
  "BP_Positionals": ["file1.txt"]
}
```

## Best Practices

- Always use `ZN-SEP` to separate Options and Positional arguments for `watershed` style CML
- `islands` style CML allows intermixing Options and Positionals, `ZN-SEP` not required but permitted
- `OA-SEP` must be used to separate Option name and value in `islands` style CML, while `space(s)` as `OA-SEP` is allowed in `watershed` style CML
- Quote values with spaces or special characters
- Use clear, consistent Option names
- Use `~json` for machine-readable output

## PFILTER

For advanced validation, default values, prefix matching, and parameter relationships, see `bp-PFILTER.md`.

For details about BosParse like parsing-aid symbols and customization, see `BosParse-Reference-Manual.md`.

## Quick Reference

All parser harnesses, their LIDs, types, defaults, and tiers:

| Key         | LID   | Type   | Default          | Level     |
| ----------- | ----- | ------ | ---------------- | --------- |
| `style`     | `~~~` | enum   | `watershed`      | global    |
| `zs`        | `~~~` | resym  | `--`             | global    |
| `glid`      | `~~~` | resym  | `~~~`            | global    |
| `plid`      | `~~~` | resym  | `~~`             | global    |
| `slid`      | `~~~` | resym  | `~`              | global    |
| `ulid`      | `~~~` | resym  | `-`              | global    |
| `os`        | `~~`  | resym  | `=`              | prior     |
| `tt`        | `~~`  | resym  | `+`              | prior     |
| `tf`        | `~~`  | resym  | `-`              | prior     |
| `td`        | `~~`  | bool   | `true`           | prior     |
| `run`       | `~`   | enum   | `auto`           | spec      |
| `json`      | `~`   | bool   | `false`          | spec      |
| `dvo`       | `~`   | bool   | `false`          | spec      |
| `pf`        | `~`   | string |                  | spec      |
| `rup`       | `~`   | bool   | `true`           | spec      |
| `afd`       | `~`   | bool   | `true`           | spec      |
| `pme`       | `~`   | bool   | `true`           | spec      |
| `oan`       | `~`   | string |                  | spec      |
| `pan`       | `~`   | string | `BP_Positionals` | spec      |
| `Banner`    | `~`   | bool   | `false`          | spec      |
| `Defaults`  | `~`   | bool   | `false`          | spec      |
| `Help`      | `~`   | bool   | `false`          | spec      |
| `Resymbols` | `~`   | bool   | `false`          | spec      |
| `Version`   | `~`   | bool   | `false`          | spec      |
| `quiet`     | all   | bool   | `true`           | all tiers |
| `standard`  | all   | bool   | `false`          | all tiers |
| `extra`     | all   | bool   | `false`          | all tiers |
| `debug`     | all   | bool   | `false`          | all tiers |
| `trace`     | all   | bool   | `false`          | all tiers |
| `config`    | all   | bool   | `false`          | all tiers |

- **Global** (`~~~`): CML style, LIDs, zone separator, verbosity
- **Prior** (`~~`): trailing tags, OA separator, verbosity
- **Spec** (`~`): run mode, PFILTER, output arrays, directives, verbosity
- **Verbosity**: `quiet` (0), `standard` (1), `extra` (2), `debug` (3), `trace` (4)
- **MCG validation order**: required → exclusion/uniqueness → dependency → master

## Requirements

- Bash 4.4+
- `jq` for JSON output or PFILTER serialization
