# PFILTER User Instruction for bosparse

PFILTER(Parameter Filter) is a new function of flexible validation and defaulting for user parameters in bosparse. It enables robust command-line parsing, type checking, aliasing, mutual-exclusion enforcement, and default value assignment.

---

## Quick Start

1. **Define PFILTER** as an associative array, specifying each parameter's type, allowed values, default, and (optionally) mutual-exclusion group.
2. **Pass PFILTER to bosparse** using the reserved Pset `~pf`:

- **Source mode:** Pass PFILTER by name reference (for sourced/in-shell use).
- **Eval/Capture mode:** Serialize PFILTER to a string and pass as a parameter (for subprocesses or remote execution).

3. **bosparse validates and assigns** parameters:

- Command-line values are validated and assigned.
- Parameters not on the command line but defined in PFILTER get their default value (if specified).
- Aliases are resolved.
- Mutual-exclusion groups are checked for uniqueness.

---

## Why Use PFILTER?

- **Validation:** Enforce types, enums, and required parameters.
- **Aliasing:** Support multiple flag names (e.g., `-h` for `-help`).
- **Defaults:** Simplify user input by auto-filling missing values.
- **Mutual-Exclusion:** Prevent duplicate assignments in defined groups.
- **Automation:** Works in both interactive and automated/scripted contexts.

---

## PFILTER Entry Structure

Each entry in PFILTER follows:

```
[param_name]="type:data:meg"
```

### Supported Types

- **bool**
  - Accepts only `true` or `false`
  - Default value can be set in the `data` field.
  - Useful for flags and switches.
  - Example:

    ```bash
    [verbose]="bool:false:"
    [force]="bool:true:"
    [debug]="bool::"
    ```

    If not provided,
    - `verbose` defaults to `false`;
    - `force` defaults to `true`;
    - `debug` remains unset unless provided.

- **string**
  - Accepts any string value.
  - Default value can be set in the `data` field.
  - Useful for free-form user input, names, paths, etc.
  - Example:

    ```bash
    [username]="string:guest:"
    [output]="string:/tmp/result.txt:"
    [comment]="string::"
    ```

    - If not provided,
      - `username` defaults to `guest`;
      - `output` defaults to `/tmp/result.txt`;
      - `comment` remains unset unless provided.

- **enum**
  - Accepts only values listed in the `data` field, separated by `|`
  - Default is the first value unless specified otherwise.
  - Useful for mode selection, limited options, etc.
  - Example:

    ```bash
    [mode]="enum:fast|safe|debug:"
    [color]="enum:red|green|blue:"
    [size]="enum:small|medium|large:"
    ```

    - If not provided:
      - `mode` defaults to `fast`;
      - `color` defaults to `red`;
      - `size` defaults to `small`.
    - If user provides `-color=yellow`, validation fails(not in enums).

- **alias**
  - Points to another parameter; value is transferred to the target.
  - Aliases will be removed after validation.
  - Useful for shorthand flags or compatibility.
  - Example:

    ```bash
    [h]="alias:help:"
    [v]="alias:verbose:"
    [vb]="alias:verbose:"
    [u]="alias:username:"
    ```

    - User can use `-h` instead of `-help`, `-v` instead of `-verbose`, `-vb` instead of `-verbose` `-u` instead of `-username`.
    - Aliases cannot be chained (e.g., `-h` -> `help` -> `verbose`), and circular references are not allowed.
    - Aliases do not have their own defaults and meg; they inherit from their target parameter.
    - if both alias and target are provided, target takes precedence, and alias value will be ignored.

---

## Example: Typical PFILTER

```bash
declare -A PFILTER=(
  [help]="bool:false:"
  [h]="alias:help:"
  [mode]="enum:fast|safe|debug:"
  [color]="enum:red|green|blue:"
  [username]="string:guest:"
  [output]="string:/tmp/result.txt:"
  [force]="bool:true:"
  [v]="alias:verbose:"
  [verbose]="bool:false:"
  [size]="enum:small|medium|large:"
  [comment]="string::"
  [u]="alias:username:"
  [port_ssh]="string:22:gnet"
  [port_telnet]="string::gnet"
  [port_https]="string:443:gnet"
)
```

---

## How PFILTER Works in bosparse

### The Reserved Pset `~pf` (parameter filter)

Always pass PFILTER using the reserved Pset `~pf`. bosparse will use this to find and apply your validation rules.

### Step-by-Step Logic

1. PFILTER defines expected parameter types, allowed values, aliases, defaults, and mutual-exclusion groups(meg).
2. bosparse parses command-line input and matches parameters to PFILTER.
3. For each PFILTER entry:
   - If present on the command line, value is validated and assigned.
   - If not present but a default exists, default is assigned.
   - If neither, prsing failed with an error message.
   - Aliases are resolved and transferred.
   - Mutual-exclusion value groups are checked for value uniqueness.

### Edge Cases & Notes

- Parameters in PFILTER but not on the command line and without defaults exit with a error.
- Invalid defaults (e.g., not in enum) cause validation errors.
- Aliases cannot chained or circular.
- Mutual-exclusion applies only within the same group.
- If a parameter provided on the command line but not defined in PFILTER, it will be assigned without validation (unless `~amf` set).
- When PSET `~amf`(all matching filter) set(`true`), any parameter not defined in PFILTER will cause parsing failure; if PFILTER is not supplied, parsing will fail.

---

## Practical Example

Suppose PFILTER is:

```bash
declare -A PFILTER=(
  [mode]="enum:fast|safe|debug:"
  [h]="alias:help:"
  [help]="bool:false:"
  [user]="string:guest:"
  [role_a]="string:admin:grole"
  [role_b]="string::grole"
  [role_c]="string::grole"
)
```

Call bosparse as:

```bash
bosparse -mode=safe -role_a=manager -role_b=developer ~pf=PFILTER -h -role_d=tester --
```

Result:

- `mode` is set to `safe` (validated against enum)
- `role_a` and `role_b` are set from input
- `role_c` is not provided, so remains unset (no default)
- `role_d` is not defined in PFILTER, so is assigned without validation (unless `~amf=true` is set)
- `user` is not provided, so is set to `guest` (default)
- `help` is not provided, so is set to `false` (default)
- `h` is an alias for `help`, so it would set `help` to `true`
- Mutual-exclusion group `grole` is checked for uniqueness among `role_a`, `role_b`, `role_c`

Call bosparse as:

```bash
bosparse -mode=safe -role_a=manager -role_b=developer ~pf=PFILTER -h -role_d=tester ~amf=true --
```

Result:

- `~amf=true` causes parsing failure since `role_d` is not defined in PFILTER.

See the `bp-test` script for more scenarios and test cases.

---

## Mutual-Exclusion Groups (meg)

Parameters in the same group (e.g., `grole`) must have unique values. This is enforced automatically by bosparse.

If a user tries to set `-role_a=admin -role_b=admin`, bosparse will raise a mutual-exclusion error since
both `role_a` and `role_b` belong to the same group `grole` and cannot have the same value.

If a parameter belongs to multiple groups, it must be unique across all those groups. For example, if
`role_a` belongs to both `grole` and `gproject`, it must have a unique value that does not conflict with
any other parameter in either group.

---

## Serialization & Deserialization

To use PFILTER in eval/capture mode (e.g., subprocesses), serialize as follows:

**Serialize:**

```bash
serialize_assoc_array() {
  local -n arr=$1
  local out=""
  for k in "${!arr[@]}"; do
    out+="${k}=${arr[$k]};"
  done
  echo "${out%;}"
}
pf_str=$(serialize_assoc_array PFILTER)
```

bosparse will parse this string back into an associative array in the subprocess.

## Running bosparse

Example:

```bash
serialize_assoc_array() {
  local -n arr=$1
  local out=""
  for k in "${!arr[@]}"; do
    out+="${k}=${arr[$k]};"
  done
  echo "${out%;}"
}
pf_str=$(serialize_assoc_array PFILTER)
bosparse -role_a=manager -role_b=developer -role_c=director ~pf="${pf_str}" -h --
```

---

## Error Handling

bosparse will report errors for:

- Invalid enum value
- Mutual-exclusion conflict
- Alias resolution error
- Type mismatch

---

## Advanced Usage & Scenarios

#### 1. Nested Aliasing and Chained Defaults

Multiple aliases can point to the same target parameter, allowing users to choose their preferred flag style.

```bash
declare -A PFILTER=(
  [h]="alias:help:"
  [help]="bool:false:"
  [assist]="alias:help:"
  [v]="alias:verbose:"
  [verbose]="bool:true:"
)
```

User can use `-h`, `-assist`, or `-help` interchangeably. Aliases are resolved in order, and default values are applied if not provided.

#### 2. Dynamic PFILTER Construction

Build PFILTER at runtime based on script logic or user input:

```bash
declare -A PFILTER
if [[ "$mode" == "admin" ]]; then
  PFILTER[admin_code]="string:secret:"
fi
PFILTER[username]="string:guest:"
PFILTER[mode]="enum:user|admin:"
```

This allows context-sensitive validation and defaults.

#### 3. Runtime Enum Extension

You can extend enum values dynamically:

```bash
PFILTER[mode]="enum:fast|safe|debug:"
if [[ "$EXTRA_MODE" ]]; then
  PFILTER[mode]="enum:fast|safe|debug|$EXTRA_MODE:"
fi
```

This lets you add new valid values at runtime.

#### 4. Conditional Defaults

Set defaults based on other parameter values:

```bash
if [[ "$mode" == "admin" ]]; then
  PFILTER[username]="string:admin:"
else
  PFILTER[username]="string:guest:"
fi
```

This ensures defaults are context-aware.

#### 5. Complex Mutual-Exclusion Groups

You can define multiple mutual-exclusion groups for different sets of parameters:

```bash
declare -A PFILTER=(
  [role_a]="string:admin:grole"
  [role_b]="string::grole"
  [role_c]="string::grole"
  [project_a]="string::gproject"
  [project_b]="string::gproject"
)
```

Here, `role_a/b/c` must be unique among themselves, and `project_a/b` must be unique among themselves.

#### 6. Required Parameters Without Defaults

If a PFILTER entry has no default and is not provided, bosparse can enforce required parameters:

```bash
declare -A PFILTER=(
  [username]="string::"
  [mode]="enum:fast|safe|debug:"
)
```

If `username` is not provided, bosparse will raise a missing-required error.

#### 7. Combining PFILTER with External Data

You can load PFILTER entries from YAML or JSON for large or dynamic validation sets:

```bash
eval $(yq eval '.pf_entries | to_entries | .[] | "PFILTER[" + .key + "]=\"" + .value + "\""' config.yaml)
```

This enables integration with external configuration sources.

---

For more advanced test cases, see the `bp-test` script or ask for a custom scenario.

---

## Troubleshooting & Reference

- Always use the reserved Pset `~pf` for PFILTER input.
- For more examples, see the `bp-test` script.
- For integration help, see bosparse documentation or ask for a custom snippet.
