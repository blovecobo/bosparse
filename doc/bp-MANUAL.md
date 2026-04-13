# BosParse User's Manual

This manual covers detail information of BosParse not included in the basic README or PFILTER guide. It includes parsing-aid symbols, customization, preserved symbols, and detailed mutual-correlation group rules.

## Naming Option Parameters

BosParse parsed Options to key-value pairs for script usage, that requires parameter names should be valid bash variable names.

As an exception, using the hyphen `-` in parameter name permitted if not at the beginning or end(e.g. -user-name), and BosParse will replace hyphens `-` to underscores `_` in the final result.

## Parsing-Aid Symbols (PAS)

BosParse uses configurable symbols to identify and parse command-line parameters:

### Leading IDs (LIDs)

- User-option LID (ULID): `-` for user options (default)
- User-option LIGA LID (ULIGA): `--` for user ligatures (auto-set to double ULID)
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
- Element separator (ELM-SEP): `|` separates PFILTER enum values or MCG names (default)

Note:

- For user options, a space or spaces used to separate Option names from ARGs supported;
- Except FLD-SEP, ELM-SEP and PRLID, all other PAS characters can be customized by user, but some restrictions apply(see RESYMS section).
- Always use ZN-SEP to separate options from positionals, even if only one zone exists, to avoid parsing errors.

## Customizing Parsing-Aid Symbols (Priors)

Prior PSets (PRLID `~~~`) parsed before others, sequence in CML doesn't matter:

```bash
./bosparse %name@value ~~~ulid=% ~~~plid=+ +trace! ~~~os=@ ~~~tt=! --
```

Repeatedly BosParse calling supported:

```bash
source ./bosparse
# setting first
bosparse  ~~~ulid=% ~~~plid=@ ~~~tt=- ~~~tf=~ --
# user params
bosparse %name=value %registered~ @debug- -- file.txt
```

This changes:

- ULID from `-` to `%`
- PLID from `~` to `@`
- TT from `+` to `-`
- TF from `-` to `~`

Example command:

```bash
JSON=$(bosparse !name=value ~~~ulid=! ~~~plid=@ @json ~~~zs=== == file.txt)
```

Available Priors:

- `~~~plid`,`~~~ulid`: set PSet LID and User-option LID
- `~~~zs`, `~~os`: set ZN-SEP and OA-SEP
- `~~~tt`, `~~~tf`: set trailing-tags
- `~~~td`: set TD value

## Preserved Symbols (RESYMS)

RESYMS are characters reserved for PAS.
Some restrictions apply:

- All LIDs: duplicate values not permitted(include LIGAs)
- TT & TF: `=` excluded; `+` and `-` recommended for clarity and consistency with common conventions
- OA-SEP: `-`/`_` excluded (conflicts with parameter names)
- FLD-SEP/ELM-SEP: should escape when using in fields; customize not supported

RESYMS set can be checked with direct command:

```bash
bosparse ~Resymbols
```

## Mutual-Correlation Group (MCG) Rules

MCGs enforce relationships between parameters. Parameters can belong to more than one group.

### Group Types

- **Exclusion (`e` prefix)**: One or none parameter in the group can supply
- **Uniqueness (`u` prefix)**: Parameters must have different values
- **Dependency (`d`/`D` prefix)**: Lowercase members depend on capital member
- **Masters(`m`/`M`)**: Lowercase member assigned to the name of supplied capital member
- **Sibling (`s` prefix)**: All members must supplied together or omitted together

### Detailed Rules

#### Exclusion Groups

If more than one member supplied, parsing fails.

```bash
[role_a]="string::erole"
[role_b]="string::erole"
```

Error if both `-role_a=admin` and `-role_b=user` supplied.

#### Uniqueness Groups

All supplied members must have different values.

```bash
[item_a]="string::ug_items"
[item_b]="string::ug_items"
[item_c]="string::ug_items"
```

Error if `-item_a=apple -item_b=apple`.

#### Dependency Groups

Lowercase members (`d`) require the capital (`D`) supplied.

```bash
[director]="string::D-auth"
[actor1]="string::d-auth"
[actor2]="string::d-auth"
```

Error if `-actor1=name1` or/and `-actor2=name2` supplied without `-director=director_name`.

#### Master Groups

Lowercase member(`m`) assigned to the supplied capital member(`M`)'s name; used default value if none supplied.

```bash
["backup"]="bool::M-mode"
["restore"]="bool::M-mode"
["operation"]="string:sync:m-mode"
```

`-b -> operation=backup`

Error if both `-backup` and `-restore` supplied; `operation="sync"` if either.

#### Sibling Groups

All members must supply together, or all omitted. Defaults assigned to missing members if available.

```bash
[host]="string::s-net"
[port]="string::s-net"
```

Error if `-host=localhost` without `-port=8080`(no default value); `port` set to default if existed.

### MCG Validation Order

1. Check sibling rules and assign defaults
2. Check exclusion/uniqueness rules
3. Check dependency rules
4. Check master rules

## Advanced PFILTER Features

### Serialization for Subprocesses

Serialize PFILTER to JSON for eval/capture modes:

```bash
serialize-pfilter() {
  local -n arr=$1
  local json="{" first=1
  for k in "${!arr[@]}"; do
    [[ $first -eq 0 ]] && json+="," || first=0
    json+="\"$k\":\"${arr[$k]}\""
  done
  json+="}"
  echo "$json"
}

PF_JSON=$(serialize-pfilter PFILTER)
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

### Bulk Varialbles Assighment

```bash
declare -A vars=(
["PARAM-FILTER"]=""
[var1]="string:val1"
[var2]="bool:false"
...
[var100]="enum:val100"
)
eval $(./bosparse ~apfd ~pf="$(serialize-pfilter vars)")
```

## Run Mode Details

### Source Mode

- Variables created in current shell
- Parsing result loaded into:
  - key-value pairs for all options(`-port=80` -> `port=80`; `-verbose` -> `verbose=true`)
  - BP_Options(): all option parameters (`BP_Options["port"]=80`)
  - BP_Stings(): all options with string type
  - BP_Bools(): all options with boolean type
  - BP_Positionals(): all positional parameters (`BP_Positionals[0]="first-positional-param`)
  - Array names can change by `~oan ~san ~ban ~pan`
- Best for scripts sourcing BosParse

### Eval Mode

- Outputs shell assignments
- Parsing result supplied by:
  - key-value pair for all options like that in Source mode
  - key-value pair for all positional parameters with `BP_Positionals_0="first positional param"`
    name prefix "BP_Positionals" can change by `~pan`
- Use `eval "$(bosparse "$@")"`

### Capture Mode

- Outputs JSON
- Best for programmatic consumption
- Use `result=$(bosparse ~json "$@")`

## Performance Notes

- PFILTER adds validation overhead
- Avoid large PFILTERs in performance-critical code
- Cache serialized PFILTERs for repeated subprocess calls

## See Also

- `bp-README.md`: Basic usage
- `bp-PFILTER.md`: PFILTER guide
