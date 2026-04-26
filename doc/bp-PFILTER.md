# PFILTER User Instruction for BosParse

PFILTER is BosParse's advanced parameter validation system. It defines expected parameters, types, defaults, prefix matching, and parameter relationships.

## Why PFILTER

Use PFILTER when you want:

- strict validation for option values
- default values for missing parameters
- unambiguous prefix matching for options and enum values
- exact control over unknown options
- parameter relationships such as exclusion, dependency, uniqueness, master and sibling

## Quick Start

### 1. Define PFILTER

Every PFILTER must include a `PARAM-FILTER` identifier entry:

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]="PFILTER is a bad idea"
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
pfilter=$(serialize-pfilter PFILTER)
eval "$(./bosparse ~pf="${pfilter}" "$@")"
```

- Capture mode:

```bash
PF_JSON=$(serialize-pfilter PFILTER)
result=$(./bosparse ~pf="$PF_JSON" ~json "$@")
echo "$result" | jq '.'
```

### 3. Validation and assignment

BosParse parses options, validates values against PFILTER, and then assigns values or defaults as configured.

## PFILTER Entry Format

Each entry has the form:

```bash
[param_name]="type:data:mcg"
```

- `type`: `bool`, `string` or `enum`
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

- Accepts `true` or `false`
- `data` is the default value
- `-debug` sets `debug=true`

### string

```bash
[username]="string:guest:"
[output]="string:/tmp/result.txt:"
[comment]="string:"
```

- Accepts any string value
- If missing and `~apfd` enabled, BosParse assigns the default

### enum

```bash
[mode]="enum:fast|safe|debug:"
[color]="enum:red|green|blue:"
```

- Accepts values listed in `data`
- Supports prefix matching for enum values
- The first listed value becomes the default when `~apfd` enabled and no value supplied

## PFILTER Control PSets

- `~pf`: pass PFILTER via PFILTER name reference or a serialized json string from PFILTER
- `~amf`: all-match-filter
  - `~amf` enables strict validation and rejects unknown parameters
  - `~amf-` allows unknown parameters
- `~apfd`: apply PFILTER defaults for un-grouped parameters
  - enabled by default
  - `~apfd-` disables default assignment

## Prefix Matching

PFILTER supports unambiguous prefix matching for parameter names and enum values.

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]=""
  [help]="bool:false:"
  [username]="string:guest:"
  [color]="enum:red|green|blue:"
)
```

Examples:

- `-h`, `-he`, `-hel`and `-help` matches `-help`
- `-user=alice` matches `-username=alice`
- `-c=g` matches `-color=green`

If a prefix is ambiguous, parsing fails.

## Mutual Correlation Groups

PFILTER supports group-based relationships.

### Dependency groups (`d`|`D` prefix)

Lowercase members depend on the capital group member.

```bash
[master]="string::D-auth"
[slave]="string::d-auth"
```

### Exclusion groups (`e` prefix)

One parameter in the group may supply.

```bash
[option_a]="string::erole"
[option_b]="string::erole"
```

### Master groups (`M`|`m` prefix)

Lowercase member set to supplied capital member's name.

```bash
["master1"]="bool::Master"
["master2"]="bool::Master"
["follower"]="string:master3:master"
```
### Required groups(`rquired`)
All members in the Required group must be supplied or can be assigned a default.

### Sibling groups (`s` prefix)

Either all members supplied or none does.

### Uniqueness groups (`u` prefix)

Parameters must receive different values.

```bash
[item_a]="string::ug_items"
[item_b]="string::ug_items"
```

```bash
[host]="string::s-net"
[port]="string::s-net"
```

## Escaping PFILTER Characters

PFILTER uses special schema characters:

- `:` field separator
- `|` enum value/group name separator
- `\` escape character

Escape these characters when they appear.

Example:

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]="escape"
  [punctuation]="enum:,|.|;|\\:|\\||\\\\|?:"
)
```

## Troubleshooting

- Missing `PARAM-FILTER` makes PFILTER invalid
- Unknown option errors might mean `~amf` enabled but the option is not defined in PFILTER
- Ambiguous prefix errors mean the prefix matches more than one parameter
- Enum validation errors mean the value is not in the allowed list

## See also

- `bp-README.md` for basic BosParse usage
- `doc/bp-MANUAL.md` for advanced features like parsing-aid symbols
