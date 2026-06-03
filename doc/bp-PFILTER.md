# `PFILTER` User Instruction for BosParse

`PFILTER` is BosParse's advanced parameter validation system. It defines expected parameters, types, defaults, prefix matching, and parameter relationships.

## Why `PFILTER`

Use `PFILTER` when you want:

- strict validation for Option values
- default values for missing parameters
- unambiguous prefix matching for Option names and enum values
- exact control over unknown Options
- parameter relationships such as exclusion, dependency, uniqueness and master

## Quick Start

### 1. Define `PFILTER`

BosParse use an associative array called `PFILTER` to define parameters. Every `PFILTER` must include a `PARAM-FILTER` identifier entry:

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]="PFILTER is a bad idea"
  ["help"]="bool:false:"
  ["mode"]="enum:fast|safe|debug:"
  ["output"]="string:/tmp/result.txt:"
  ["verbose"]="bool:false:"
)
```

### 2. Pass `PFILTER` to BosParse

There are three ways to pass `PFILTER` to bosparse:

1. `PFILTER` name reference, for `source mode` only:

   ```bash
   source ./bosparse
   bosparse ~pf=PFILTER "$@"
   ```

1. Pass serialized `PFILTER` (json string), for all `run-modes`:

   ```bash
   pfilter=$(serialize-pfilter PFILTER)
   eval "$(./bosparse ~pf="${pfilter}" "$@")"
   ```

1. by `keys-values` pairs, for all `run-modes`:

   ```bash
   result=$(./bosparse ~pf="${!PFILTER[*]} ${PFILTER[*]}" ~json "$@")
   echo "${result}" | jq '.'
   ```

### 3. Validation and assignment

BosParse parses Options, validates values against `PFILTER`, and then assigns values or defaults as configured.

## `PFILTER` Entry Format

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
["verbose"]="bool:false:"
["force"]="bool:true:"
["debug"]="bool:"
```

- Accepts `true` or `false`
- `data` is the default value
- `-debug` sets `debug=true`

### string

```bash
["username"]="string:guest:"
["output"]="string:/tmp/result.txt:"
["comment"]="string:"
```

- Accepts any string value
- If missing and `~afd` enabled, BosParse assigns the default

### enum

```bash
["mode"]="enum:fast|safe|debug:"
["color"]="enum:red|green|blue:"
```

- Accepts values listed in `data`
- Supports prefix matching for enum values
- The first listed value becomes the default when `~afd` enabled and no value supplied

### Notes

- Default value assignment applied to `un-grouped` parameters only; MCG members follow group rules
- For MCG members, see section MCG

## `PFILTER` Control PSets

- `~pf`: pass `PFILTER` via name reference, serialized json string or `keys-values` pairs from `PFILTER`
- `~rup` (default: true): restrict unknown parameters, causing parsing to fail if an option parameter is not defined in `PFILTER`
- `~afd` (default: true): apply `PFILTER` defaults for un-grouped parameters
- `~pme` (default: true): enable prefix matching for user parameter names; disable with `~pme-`

## Prefix Matching

`PFILTER` supports unambiguous prefix matching for parameter names and enum values.

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]=""
  ["help"]="bool:false:"
  ["username"]="string:guest:"
  ["color"]="enum:red|green|blue:"
)
```

Examples:

- `-h`, `-he`, `-hel` and `-help` matches `-help`
- `-user=alice` matches `-username=alice`
- `-c=g` matches `-color=green`

If a prefix is ambiguous, parsing fails.

## Mutual Correlation Groups(MCG)

`PFILTER` supports group-based relationships.

### Dependency groups (`d`|`D` prefix)

Lowercase members depend on the capital group member.

```bash
["master"]="string::D-auth"
["slave"]="string::d-auth"
```

### Exclusion groups (`e` prefix)

One parameter in the group may supply.

```bash
["option_a"]="string::erole"
["option_b"]="string::erole"
```

### Master groups (`M`|`m` prefix)

Lowercase member set to supplied capital member's name.

```bash
["backup"]="bool::Mg-mode"
["restore"]="bool::Mg-mode"
["op-mode"]="string::mg-mode"
```

### Required groups (r prefix)

All members in the Required group must be supplied or can be assigned a default.

### Uniqueness groups (`u` prefix)

Parameters must receive different values.

```bash
["item_a"]="string::ug_items"
["item_b"]="string::ug_items"
```

## Escaping `PFILTER` Characters

`PFILTER` uses special schema characters:

- `:` field separator
- `|` enum value/group name separator
- `\` escape character

Escape these characters when they appear.

Example:

```bash
declare -A PFILTER=(
  ["PARAM-FILTER"]="escape"
  ["punctuation"]="enum:,|.|;|\\:|\\||\\\\|?:"
)
```

## Troubleshooting

- Missing `PARAM-FILTER` makes `PFILTER` invalid
- Unknown Option errors might mean `~rup` enabled but the Option is not defined in `PFILTER`
- Ambiguous prefix errors mean the prefix matches more than one parameter
- Enum validation errors mean the value is not in the allowed list
- Duplicate parameter names but have different types will result an error
- Hyphens in parameter names will be replaced by underscores after parsing(e.g. `my-param` -> `my_param`)

## See also

- `bp-README.md` for basic BosParse usage
- `doc/BosParse-Reference-Manual.md` for more details like parsing-aid symbols
