# BosParse

**BosParse** is a Bash command-line parser that converts flags, options, and positional arguments into shell variables or JSON output.

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

Run it:

```bash
./script.sh -name alice -- data.txt
```

- Capture mode (JSON output)

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

BosParse divides arguments into two zones:

```bash
OP-ZONE -- PP-ZONE
```

- `OP-ZONE`: options and parser settings
- `PP-ZONE`: positional values
- `--`: default zone separator(ZN-SEP)

## Supported Parameters

### Option parameters

- `-name=value`
- `-name value`
- `-flag+` sets boolean true
- `-flag-` sets boolean false
- `-flag` set `true` (default setting)

Example:

```bash
./script.sh -username=john -quiet- -output /tmp/out.txt -- file.txt
```

### Positional parameters

Everything after `--` becomes positional values in the `BP_Positionals` array:

```bash
./script.sh -name=bob -- one two three
```

### LIGA-style flags

Ligatures compress boolean flags:

```bash
./script.sh --abcd --
./script.sh --2abcdef --
```

This sets `a=true`, `b=true`, `c=true`, `d=true`, or `ab=true`, `cd=true`, `ef=true`.

## Parser Settings (`~` PSets)

Parser setting parameters use the `~` prefix.

Common settings:

- `~json`: produce JSON output
- `~run=source`, `~run=eval`, `~run=capture`: run-mode setting
- `~mode` alias for `~run`
- `~quiet`, `~standard`, `~extra`, `~debug`, `~trace`: output control
- `~oan`, `~san`, `~ban`, `~pan`: specify array names of parsing result
- `~Banner`, `~Version`, `~Resymbols`, `~Defaults`: display BosParse properties

Example:

```bash
./script.sh ~run=capture -name=alice -active+ -- file.txt
```

## Run Modes

- `source`: sets variables directly in the current shell
- `eval`: outputs shell assignments for `eval $(...)`
- `capture`: outputs JSON

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

- Always use `--` to separate options and positional arguments
- Quote values with spaces or special characters
- Use clear, consistent option names
- Reserve `~` values for parser settings
- Use `~json` for machine-readable output

## PFILTER

For advanced validation, default values, prefix matching, and parameter relationships, see `doc/bp-PFILTER.md`.

For advanced features like parsing-aid symbols and customization, see `doc/bp-MANUAL.md`.

## Requirements

- Bash 4.4+
- `jq` for JSON output or PFILTER serialization
