# BosParse

**BosParse** is a Bash command-line parser that converts flags, options, and positional arguments into shell variables or JSON output.

## Quick Start

### Source mode (recommended inside scripts)

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

### Eval mode

```bash
#!/usr/bin/env bash
eval "$(./bosparse "$@")"
echo "name=$name"
```

Run it:

```bash
./script.sh -name alice -- data.txt
```

### Capture mode (JSON output)

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
- `--`: recommended separator

## Supported Parameters

### Option parameters

- `-name=value`
- `-name value`
- `-flag+` sets boolean true
- `-flag-` sets boolean false
- `-flag` treated as `true`

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
```

This sets `a=true`, `b=true`, `c=true`, and `d=true`.

## Parser Settings (`~` PSets)

Parser settings use the `~` prefix.

Common settings:

- `~json`: produce JSON output
- `~run=source`, `~run=eval`, `~run=capture`
- `~mode` alias for `~run`
- `~quiet`, `~debug`, `~trace`
- `~oan`, `~san`, `~ban`, `~pan` to rename result arrays
- `~Banner`, `~Version`, `~Resymbols`, `~Defaults`

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
- `BP_Positionals[0]=file1.txt`

### Capture / JSON mode

```bash
./script.sh ~json -name=alice -active+ -- file1.txt
```

Result:

```json
{
  "name": "alice",
  "active": true,
  "BP_Positionals": ["file1.txt"]
}
```

## Best Practices

- Always use `--` before positional arguments
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
