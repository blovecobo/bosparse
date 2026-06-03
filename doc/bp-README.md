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

> Note: `eval` mode executes generated shell assignments. Only use it when the invocation and parameter names are trusted.
> For details and mitigations, see the Reference Manual: [Eval Mode Security](doc/BosParse-Reference-Manual.md#eval-mode-security).

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

## Parser Settings (`~` PSets)

Parser setting parameters use the `~` as LID. They control how BosParse behaves and outputs results.

They do not set variables directly but affect the parsing process and output format.

### Common settings

- `~~~style`: command line structure style, `watershed`(default) or `islands`
- `~json`: produce JSON output
- `~run`: run-mode setting, `auto` (default), `source`, `eval`, `capture`
- `~dvo`: disable variables output; for source mode only
- `~quiet`, `~standard`, `~extra`, `~debug`, `~trace`: output control, `~standard` by default
- `~oan`, `~san`, `~ban`, `~pan`: specify array names of parsing result
- `~pme`: enable prefix matching for user params (default `true`); disable with `~pme-`
- `~Banner`, `~Version`, `~Resymbols`, `~Defaults`, `~Help`: display BosParse properties

Example:

```bash
./script.sh ~run=capture -name=alice -active+ -- file.txt | jq .
```

## Important Features

- BosParse supports PSet names prefix-matching in all PSets scope, e.g. `~r=j` -> `~run=json`
- Options sequence is insensitive for PSets and User-params in OP-ZONE (`watershed`) or in whole CML (`islands`)
- Prefix-matching (`~pme`, default `true`) supports unambiguous abbreviation for parameter names and enum values for PSets, disable with `~pme-` when strict exact matching is needed; Prefix-matching for User options needs `PFILTER` support, see doc/BosParse-Reference-Manual.md#Prefix-Matching
- When the same parameter supplied multiple times, the latter wins; when the same parameter name used with different types, parsing fails
- If a boolean parameter supplied as a boolean and a member of LIGA-style flag at sametime, boolean setting takes precedence
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
- `OA-SEP` must be used to separate Option name and value in `islands` style CML, while `space(s)` as `OA-SEP` allowed in `watershed` style CML
- Quote values with spaces or special characters
- Use clear, consistent Option names
- Use `~json` for machine-readable output

## PFILTER

For advanced validation, default values, prefix matching, and parameter relationships, see `doc/bp-PFILTER.md`.

For details about BosParse like parsing-aid symbols and customization, see `doc/BosParse-Reference-Manual.md`.

## Requirements

- Bash 4.4+
- `jq` for JSON output or PFILTER serialization
