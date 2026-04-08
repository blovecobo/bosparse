# PFILTER User Instruction for BosParse

PFILTER is BosParse's advanced parameter validation system. It defines expected parameters, types, defaults, prefix matching, and parameter relationships.

## Why PFILTER

Use PFILTER when you want:

- strict validation for option values
- default values for missing parameters
- unambiguous prefix matching for options and enum values
- exact control over unknown options
- parameter relationships such as exclusion, dependency, uniqueness, and sibling rules

## Quick Start

### 1. Define PFILTER

Every PFILTER must include a `PARAM-FILTER` identifier entry:

```bash
declare -A PFILTER=(
  [PARAM-FILTER]="PFILTER is a bad idea"
  [help]="bool:false:"
  [mode]="enum:fast|safe|debug:"
  [output]="string:/tmp/result.txt:"
  [verbose]="bool:false:"
)
```

### 2. Pass PFILTER to BosParse

- Source mode:

```bash
source ./bosparse
bosparse ~pf=PFILTER "$@"
```

- Eval mode:

```bash
pfilter=$(serialize_assoc_array PFILTER)
eval "$(./bosparse ~pf="${pfilter}" "$@")"
```

- Capture mode:

```bash
PF_JSON=$(serialize_assoc_array PFILTER)
result=$(./bosparse ~pf="$PF_JSON" ~json "$@")
echo "$result" | jq '.'
```

### 3. Validate and assign

BosParse parses options, validates values against PFILTER, and then assigns values or defaults as configured.

## PFILTER Entry Format

Each entry has the form:

```bash
[param_name]="type:data:mcg"
```

- `type`: `bool`, `string`, or `enum`
- `data`: default value or enum list
- `mcg`: mutual-correlation group name(s)

`data` and `mcg` are optional.

## Supported Types

### bool

```bash
[verbose]="bool:false:"
[force]="bool:true:"
[debug]="bool:"
```

- Accepts only `true` or `false`
- `data` is the default value
- `-debug` sets `debug=true`

### string

```bash
[username]="string:guest:"
[output]="string:/tmp/result.txt:"
[comment]="string:"
```

- Accepts any string value
- If missing and `~apfd` is enabled, BosParse assigns the default

### enum

```bash
[mode]="enum:fast|safe|debug:"
[color]="enum:red|green|blue:"
```

- Accepts only values listed in `data`
- Supports prefix matching for enum values
- The first listed value becomes the default when `~apfd` is enabled and no value is supplied

## PFILTER Control PSets

- `~pf`: PFILTER input
- `~amf`: all-match-filter
  - `~amf` enables strict validation and rejects unknown parameters
  - `~amf-` allows unknown parameters
- `~apfd`: apply PFILTER defaults
  - enabled by default
  - `~apfd-` disables default assignment

## Prefix Matching

PFILTER supports unambiguous prefix matching for parameter names and enum values.

```bash
declare -A PFILTER=(
  [PARAM-FILTER]="PFILTER is a bad idea"
  [help]="bool:false:"
  [username]="string:guest:"
  [color]="enum:red|green|blue:"
)
```

Examples:

- `-h` matches `-help`
- `-user=alice` matches `-username`
- `-col=gr` matches `-color=green`

If a prefix is ambiguous, parsing fails.

## Mutual Correlation Groups

PFILTER supports group-based relationships.

### Exclusion groups (`e` prefix)

Only one parameter in the group may be supplied.

```bash
[option_a]="string::erole"
[option_b]="string::erole"
```

### Uniqueness groups (`u` prefix)

Parameters must receive different values.

```bash
[item_a]="string::ug_items"
[item_b]="string::ug_items"
```

### Dependency groups (`d`/`D` prefix)

Lowercase members depend on the uppercase group leader.

```bash
[master]="string::D-auth"
[slave]="string::d-auth"
```

### Sibling groups (`s` prefix)

Either all members are supplied or none are.

```bash
[host]="string::s-net"
[port]="string::s-net"
```

## Escaping PFILTER Characters

PFILTER uses special schema characters:

- `:` field separator
- `|` enum/group separator
- `\` escape character

Escape these characters when they appear literally.

Example:

```bash
declare -A PFILTER=(
  [PARAM-FILTER]="escape"
  [punctuation]="enum:,|.|;|\\:|\\||\\\\|?:"
)
```

## Troubleshooting

- Missing `PARAM-FILTER` makes PFILTER invalid
- Unknown option errors usually mean `~amf` is enabled or the option is not defined in PFILTER
- Ambiguous prefix errors mean the prefix matches more than one parameter
- Enum validation errors mean the value is not in the allowed list

## See also

- `bp-README.md` for basic BosParse usage
- `doc/bp-MANUAL.md` for advanced features like parsing-aid symbols
