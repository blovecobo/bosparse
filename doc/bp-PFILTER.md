# `PFILTER` User Instruction for BosParse

`PFILTER` is BosParse's advanced parameter validation system. It defines expected parameters, types, defaults, prefix matching, and parameter relationships.

## Why `PFILTER`

Use `PFILTER` when you want:

- strict validation for Option values
- default values for missing parameters
- unambiguous prefix matching for Option names and enum values
- exact control over undefined Options
- parameter relationships such as exclusion, dependency, uniqueness and master

## Quick Start

### 1. Define `PFILTER`

BosParse uses an associative array called `PFILTER` to define parameters. Every `PFILTER` must include a `PARAM_FILTER` identifier entry:

```bash
declare -A PFILTER=(
  ["PARAM_FILTER"]="PFILTER is a bad idea"
  ["help"]="bool:false:"
  ["mode"]="enum:fast|safe|debug:"
  ["output"]="string:/tmp/result.txt:"
  ["verbose"]="bool:false:"
)
```

### 2. Pass `PFILTER` to BosParse

There are four ways to pass `PFILTER` to bosparse:

1. `PFILTER` name reference, for `source mode` only:

   ```bash
   source ./bosparse
   bosparse ~pf=PFILTER "$@"
   ```

1. Pass serialized `PFILTER` (JSON string), for all `run-modes`:

   ```bash
   pfilter=$(serialize-pfilter PFILTER)
   eval "$(./bosparse ~pf="${pfilter}" "$@")"
   ```

1. Element streams for all `run-modes`:

   ```bash
   ~pf="key1=value1 key2=value2 ..."
   ```

1. By `key-value` pairs, for all `run-modes`:

   ```bash
    ~pf="key1 value1 key2 value2 ..."
   ```

### 3. Validation and assignment

BosParse parses Options, validates values against `PFILTER`, and then assigns values or defaults as configured.

## `PFILTER` Entry Format

`PFILTER` is an associative array with each entry has the form:

```bash
["param_name"]="type:data:mcg"
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
- If missing and `~afd` enabled, BosParse assigns the default(in `data` field)

### enum

```bash
["mode"]="enum:fast|safe|debug:"
["color"]="enum:red|green|blue:"
```

- Accepts values listed in `data`
- Supports prefix matching for enum values if `~pme` set
- The first listed value becomes the default when `~afd` enabled and no value supplied

### Notes

- Default value assignment applied to `un-grouped` parameters only; MCG members follow group rules
- For MCG members, see section MCG

## `PFILTER` Control Harnesses

- `~pf`: pass `PFILTER` via name reference, serialized JSON string, element stream or `key-value` pairs from `PFILTER`
- `~rup` (default: true): restrict unknown parameters, causing parsing to fail if an option parameter is not defined in `PFILTER`
- `~afd` (default: true): apply `PFILTER` defaults for un-grouped parameters
- `~pme` (default: true): enable prefix matching for user parameter names; disable with `~pme-`for exact matching

## Prefix Matching

`PFILTER` supports unambiguous prefix matching for parameter names and enum values.

```bash
declare -A PFILTER=(
  ["PARAM_FILTER"]=""
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

## MCG Validation Order

Default value assignment can affect validation results, so order matters:

1. **Required rules** — check all `r`-group members are supplied or have defaults (assign defaults first)
1. **Exclusion / Uniqueness rules** — check `e`-group has at most one member; check `u`-group members have distinct values
1. **Dependency rules** — check `d`-members require their `D`-member
1. **Master rules** — check `m`/`M`-group: assign M-member name to m-member; error on multiple M-members supplying; m-member supplying not allowed

## Escaping `PFILTER` Characters

`PFILTER` uses special schema characters:

- `:` field separator
- `|` enum value/group name separator
- `\` escape character

Escape these characters when they appear.

Example:

```bash
declare -A PFILTER=(
  ["PARAM_FILTER"]="escape"
  ["punctuation"]="enum:,|.|;|\\:|\\||\\\\|?:"
)
```

## Troubleshooting

- Missing `PARAM_FILTER` makes `PFILTER` invalid
- Unknown Option errors might mean `~rup` enabled but the Option is not defined in `PFILTER`
- Ambiguous prefix errors mean the prefix matches more than one parameter
- Enum validation errors mean the value is not in the allowed list
- Duplicate parameter names with different types will result in an error
- Hyphens in parameter names will be replaced by underscores after parsing(e.g. `my-param` -> `my_param`)

## See also

- `bp-README.md` for basic BosParse usage
- `BosParse-Reference-Manual.md` for more details like parsing-aid symbols
