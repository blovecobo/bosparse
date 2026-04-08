# BosParse Advanced Manual

This manual covers advanced BosParse features not included in the basic README or PFILTER guide. It includes parsing-aid symbols, customization, preserved symbols, and detailed mutual-correlation group rules.

## Parsing-Aid Symbols (PAS)

BosParse uses configurable symbols to identify and parse command-line parameters:

### Leading IDs (LIDs)

- User-option LID (ULID): `-` for user options (default)
- User-option LIGA LID (ULIGA): `--` for user ligatures (default)
- PSet LID (PLID): `~` for parser settings (default)
- PSet LIGA LID (PLIGA): `~~` for ligature PSets (auto-set to double PLID)
- Prior LID (PRLID): `~~~` for prior-parsing PSets (default)

### Trailing Tags (TAGs)

- Tag-for-true (TT): `+` assigns boolean true (default)
- Tag-for-false (TF): `-` assigns boolean false (default)
- Tag-for-default (TD): `true` (default value when tag omitted)

### Separators (SEPs)

- Zone separator (ZN-SEP): `--` separates options from positionals (default)
- Option-ARG separator (OA-SEP): `=` separates option names from values (default)
- Field separator (FLD-SEP): `:` separates PFILTER fields (default)
- Element separator (ELM-SEP): `|` separates enum values or group names (default)

Note: 
- for user options, a space or spaces used to separate ARGs from Option names supported


## Customizing Parsing-Aid Symbols (Priors)

Prior PSets (PRLID `~~~`) parsed before others, sequence in CML does't matter:

```bash
./bosparse -name=value ~~~ulid=& ~~~plid=@ ~~~tt=- ~~~tf=~ -- file.txt
```

In `source` mode, repeatedly BosParse calling supported:

```bash
source ./bosparse
# setting first
bosparse  ~~~ulid=& ~~~plid=@ ~~~tt=- ~~~tf=~ --
# user params
bosparse -name=value -- file.txt
```

This changes:

- ULID from `-` to `&`
- PLID from `~` to `@`
- TT from `+` to `-`
- TF from `-` to `~`

Example command:

```bash
bosparse ~~~ulid=& ~~~plid=@ &name=value @json -- file.txt
```

Note:
- ZN-SEP(`~~~zs`) can only be set in source mode via separated BosParse calling.


## Preserved Symbols (RESYMS)

RESYMS are characters reserved for PAS and PFILTER fields.
Some restrictions apply:

- All LIDs: duplicate values not permitted(include LIGAs)
- TT & TD: different values
- OA-SEP: `-`/`_` excluded(conflicts with parameter names)
- ZN-SEP: `|`/`&` excluded(interfers Bash globbing)
- FLD-SEP/ELM-SEP: should be escaped when using in fields

RESYMS set can be checked with directive:

```bash
bosparse ~Resymbols 
```

## Mutual-Correlation Group (MCG) Rules

MCGs enforce relationships between parameters. Parameters can belong to multiple groups.

### Group Types

- **Exclusion (`e` prefix)**: Only one parameter in the group can be supplied
- **Uniqueness (`u` prefix)**: Parameters must have different values
- **Dependency (`d`/`D` prefix)**: Lowercase members depend on uppercase leader
- **Sibling (`s` prefix)**: All members must be supplied together or omitted together

### Detailed Rules

#### Exclusion Groups

If more than one member is supplied, parsing fails.

```bash
[role_a]="string::erole"
[role_b]="string::erole"
```

Error if both `-role_a=admin -role_b=user` are provided.

#### Uniqueness Groups

All supplied members must have different values.

```bash
[item_a]="string::ug_items"
[item_b]="string::ug_items"
[item_c]="string::ug_items"
```

Error if `-item_a=apple -item_b=apple`.

#### Dependency Groups

Lowercase members (`d`) require the uppercase leader (`D`) to be supplied.

```bash
[master]="string::D-auth"
[slave]="string::d-auth"
[worker]="string::d-auth"
```

Error if `-slave=val` without `-master=val`.

#### Sibling Groups

All members must be supplied together, or all omitted. Defaults are assigned to missing members if available.

```bash
[host]="string::s-net"
[port]="string::s-net"
```

Error if only `-host=localhost` without `-port=8080`.

### MCG Validation Order

1. Check sibling rules and assign defaults
2. Check exclusion rules
3. Check uniqueness rules
4. Check dependency rules

## Advanced PFILTER Features

### Serialization for Subprocesses

Serialize PFILTER to JSON for eval/capture modes:

```bash
serialize_assoc_array() {
  local -n arr=$1
  local json="{"
  for k in "${!arr[@]}"; do
    [[ $first -eq 0 ]] && json+="," || first=0
    json+="\"$k\":\"${arr[$k]}\""
  done
  json+="}"
  echo "$json"
}

PF_JSON=$(serialize_assoc_array PFILTER)
result=$(./bosparse ~pf="$PF_JSON" ~json "$@")
```

### Dynamic PFILTER Construction

Build PFILTER at runtime:

```bash
declare -A PFILTER
PFILTER[PARAM-FILTER]="dynamic"
if [[ $mode == "admin" ]]; then
  PFILTER[admin_code]="string:secret:"
fi
PFILTER[username]="string:guest:"
```

## Run Mode Details

### Source Mode

- Variables created in current shell
- Best for scripts sourcing BosParse

### Eval Mode

- Outputs shell assignments
- Use `eval "$(bosparse "$@")"`

### Capture Mode

- Outputs JSON
- Use `result=$(bosparse ~json "$@")`

## Performance Notes

- PFILTER adds validation overhead
- Avoid large PFILTERs in performance-critical code
- Cache serialized PFILTERs for repeated subprocess calls

## See Also

- `bp-README.md`: Basic usage
- `bp-PFILTER.md`: PFILTER guide
