# PFILTER User Instruction for bosparse

PFILTER(Parameter Filter) is a new function of flexible validation and defaulting for user parameters in bosparse. It enables robust command-line parsing, type checking, name matching, mutual-exclusion enforcement, and default value assignment.

---

## Quick Start

1. **Define PFILTER** as an associative array, specifying each parameter's type, allowed values, default, and (optionally) mutual-exclusion group.
   - Note: PFILTER must include the identifier entry `[PARA-FILTER]=":"` to be recognized by bosparse(value doesn't matter).
2. **Pass PFILTER to bosparse** using the reserved Pset `~pf`:

- **Source mode:** Pass PFILTER by name reference (for sourced/in-shell use).
- **Eval/Capture mode:** Serialize PFILTER to a json string and pass as a parameter (for subprocesses or remote execution).

3. **bosparse validates and assigns** parameters:

- Command-line values are validated and assigned.
- Parameters not on the command line but defined in PFILTER get their default value (if specified).
- Prefix-matching parameter names are resolved and assigned accordingly.
- Mutual-exclusion groups are checked for value uniqueness.

---

## Why Use PFILTER?

- **Validation:** Enforce types, enums, and required parameters.
- **Prefix-matching:** Allow users to use unambiguous prefixes for convenience.
- **Defaults:** Simplify user input by auto-filling missing values.
- **Mutual-Exclusion:** Prevent duplicate assignments in defined groups.
- **Automation:** Works in both interactive and automated/scripted contexts.

---

## PFILTER Entry Structure

Each entry in PFILTER follows:

```
[param_name]="type:data:meg"
```

bosparse uses an identifier entry in PFILTER to validate the PFILTER(value of the entry is not important, only the key matters):

```
# Required identifier entry to recognize PFILTER
[PARA-FILTER]=":"
# or
[PARA-FILTER]="PFILTER is a bad idea" # value doesn't matter, only the key matters
```

### Supported Types

- **bool**
  - Accepts only `true` or `false`
  - Default value can be set in the `data` field.
  - Useful for flags and switches.
  - Example:

    ```bash
    [verbose]="bool:false:"
    [force]="bool:true"
    [debug]="bool"
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
    [output]="string:/tmp/result.txt"
    [comment]="string:"
    ```

    - If not provided,
      - `username` defaults to `guest`;
      - `output` defaults to `/tmp/result.txt`;
      - `comment` remains unset unless provided.

- **enum**
  - Accepts only values listed in the `data` field, separated by `|`
  - Default is the first value unless specified otherwise.
  - When a enmu value contains `|`, it should be escaped(`\|`)
  - Useful for mode selection, limited options, etc.
  - Example:

    ```bash
    [mode]="enum:fast|safe|debug:"
    [color]="enum:red|green|blue"
    [size]="enum:small|medium|large"
    ```

    - If not provided:
      - `mode` defaults to `fast`;
      - `color` defaults to `red`;
      - `size` defaults to `small`.
    - If user provides `-color=yellow`, validation fails(not in enums).

### Data Fields

Data fields in PFILTER are designed as follows:

- for type `bool`/`string`, it stores the default value;
- for type `enum`, it stores all the possible values separated by `|`;

### Mutual Exclusion Groups

PFILTER supports mutual exclusion groups(MEG).
Mutual exclusion groups are used to define mutual exclusion between options.
Parameters in the same MEG must be assigned to different values.

---

## prefix-matching parameter name

- **Prefix**: Any string that matches the parameter name when no ambiguous prefix exists.
- **Supported Types**: string, bool, enum and resym
- Example:

  ```bash
  [help]="bool:false:"
  [comment]="string:"
  [color]="enum:red|green|blue:"
  ```

  In the above example,
  - if user provides `-h`/`-he`/`-hel`/`-help`, it will set `help` to `true` (since it's a bool type);
  - if user provides `-com="This is a comment"`, it will set `comment` to "This is a comment";
  - if user provides `-col=green`, it will set `color` to `green`.
  - If user provideds `-co=green`, parser will raise an error since `-co` is ambiguous between
    `-color` and `-comment`.
  - If user provides `-color=yellow`, validation fails(not in enums).

---

## Example: Typical PFILTER

```bash
declare -A PFILTER=(
  [PARA-FILTER]=""
  [help]="bool:false"
  [mode]="enum:fast|safe|debug"
  [color]="enum:red|green|blue:"
  [username]="string:guest"
  [output]="string:/tmp/result.txt"
  [force]="bool:true"
  [verbose]="bool:false"
  [size]="enum:small|medium|large"
  [comment]="string"
  [port_ssh]="string:22:gnet:gport"
  [port_telnet]="string::gnet:gport"
  [port_https]="string:443:gnet:gport"
)
```

---

## How PFILTER Works in bosparse

### The Reserved Pset `~pf` (parameter filter)

Always pass PFILTER using the reserved PSet `~pf`. bosparse will use this to find and apply your validation rules.

### Step-by-Step Logic

1. PFILTER defines expected parameter types, allowed values, defaults, and mutual-exclusion groups(meg).
2. bosparse parses command-line input and matches parameters to PFILTER.
3. prefix-matched parameters are validated against PFILTER
4. For each PFILTER entry:
   - If present on the command line, value is validated and assigned.
   - If not present but a default exists, default is assigned.
   - If neither, prsing failed with an error message.
   - If present but invalid, parsing failed with an error message.
   - Mutual-exclusion value groups are checked for value uniqueness.

### Edge Cases & Notes

- Parameters in PFILTER but not on the command line and without defaults, exit with a error.
- Invalid defaults (e.g., not in enum) cause validation errors.
- Mutual-exclusion applies only within the same group.
- If a parameter provided on the command line but not defined in PFILTER, it will be assigned without validation (unless `~amf` set).
- When PSet `~amf`(all matching filter) set(`true`), any parameter not defined in PFILTER will cause parsing failure; if PFILTER is not provided, parsing will fail.

---

## Practical Example

Suppose PFILTER is:

```bash
declare -A PFILTER=(
  [PARA-FILTER]=":"
  [mode]="enum:fast|safe|debug:"
  [help]="bool:false"
  [user]="string:guest"
  [role_a]="string:admin:grole"
  [role_b]="string::grole"
  [role_c]="string:viewer:grole"
)
```

Call bosparse as:

```bash
bosparse -mode=safe -role_a=manager -role_b=developer ~pf=PFILTER -h -role_d=tester --
```

Result:

- `mode` is set to `safe` (validated against enum)
- `role_a`, `role_b` and `role_c` are set from input
- `role_d` is not defined in PFILTER, so is assigned without validation (as `~amf` is not set)
- `user` is not provided, so is set to `guest` (default)
- `help` is not provided, so is set to `false` (default)
- `h` prefix-matched for `help`, so it would set `help` to `true`(latter one wins)
- Mutual-exclusion group `grole` is checked for uniqueness value among `role_a`, `role_b`, `role_c`

Call bosparse as:

```bash
bosparse -mode=safe -role_a=manager -role_b=developer ~pf=PFILTER -h -role_d=tester ~amf --
```

Result:

- `~amf` causes parsing failure since `role_d` is not defined in PFILTER.

See the `bp-test-inte.sh` script for more scenarios and test cases.

---

## Mutual-Exclusion Groups (meg)

Parameters in the same group (e.g., `grole`) must have unique values. This is enforced automatically by bosparse.

For the example above, if a user tries to set `-role_a=admin -role_b=admin`, bosparse will raise a mutual-exclusion error since both `role_a` and `role_b` belong to the same group `grole` and cannot have the same value.

If a parameter belongs to multiple groups, it must be unique across all those groups. For example, if `role_a` belongs to both `grole` and `gproject`, it must have a unique value that does not conflict with any other parameter in either group.

---

## Serialization & Deserialization

To use PFILTER in eval/capture mode (e.g., subprocesses), serialize PFILTER array to a json object as follows:

**Serialize:**

```bash
# Serialize PFILTER to a JSON string for passing to subprocesses
serialize_assoc_array() {
	local -n arr=$1

	command -v jq >/dev/null 2>&1 || {
		echo "jq required for serialization" >&2
		return 1
	}

	local json first=1 k_esc v_esc

	json="{"
	for k in "${!arr[@]}"; do
		if [[ ${first} -eq 0 ]]; then json+=","; fi
		k_esc=$(jq -n --arg s "${k}" '$s')
		v_esc=$(jq -n --arg s "${arr[${k}]}" '$s')
		json+="${k_esc}: ${v_esc}"
		first=0
	done
	json+="}"

	echo "${json}"
}
pf_str="$(serialize_assoc_array PFILTER)"
```

bosparse will parse this json string back into an associative array in the subprocess.

**Limitations:**

- Requires `jq` for serialization.
- Only supports string values (which is sufficient for PFILTER entries).

## Running bosparse

Example:

```bash
pf_str=$(serialize_assoc_array PFILTER)
bosparse -role_a=manager -role_b=developer -role_c=director ~pf="${pf_str}" -h --
```

---

## Error Handling

bosparse will report errors for:

- Invalid enum value
- Mutual-exclusion conflict
- name matching error
- Type mismatch

---

## Advanced Usage & Scenarios

#### 1. Dynamic PFILTER Construction

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

#### 2. Runtime Enum Extension

You can extend enum values dynamically:

```bash
PFILTER[mode]="enum:fast|safe|debug:"
if [[ "$EXTRA_MODE" ]]; then
  PFILTER[mode]="enum:fast|safe|debug|$EXTRA_MODE:"
fi
```

This lets you add new valid values at runtime.

#### 3. Conditional Defaults

Set defaults based on other parameter values:

```bash
if [[ "$mode" == "admin" ]]; then
  PFILTER[username]="string:admin:"
else
  PFILTER[username]="string:guest:"
fi
```

This ensures defaults are context-aware.

#### 4. Complex Mutual-Exclusion Groups

You can define multiple mutual-exclusion groups for different sets of parameters:

```bash
declare -A PFILTER=(
  [PARA-FILTER]=""
  [role_a]="string:admin:grole"
  [role_b]="string::grole"
  [role_c]="string::grole"
  [project_a]="string::gproject"
  [project_b]="string::gproject"
)
```

Here, `role_a/b/c` must be unique among themselves, and `project_a/b` must be unique among themselves.

#### 5. Required Parameters Without Defaults

If a PFILTER entry has no default and is not provided, bosparse can enforce required parameters:

```bash
declare -A PFILTER=(
  [PARA-FILTER]=""
  [username]="string::"
  [mode]="enum:fast|safe|debug:"
)
```

If `username` is not provided, bosparse will raise a missing-required error.

#### 6. Combining PFILTER with External Data

You can load PFILTER entries from YAML or JSON for large or dynamic validation sets:

```bash
eval $(yq eval '.pf_entries | to_entries | .[] | "PFILTER[" + .key + "]=\"" + .value + "\""' config.yaml)
```

This enables integration with external configuration sources.

---

For more advanced test cases, see the `bp-test-inte.sh` script or ask for a custom scenario.

---

## Troubleshooting & Reference

- Always use the reserved Pset `~pf` for PFILTER input.
- For integration help, see bosparse documentation or ask for a custom snippet.
