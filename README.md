**Simple Usage:**

```bash
$ bosparse -name=Bosparse --
name=Bosparse

$ eval $(bosparse -name=BosParse --)
$ echo "${name}"
BosParse

$ eval $(bosparse -parser-name=BosParse  -- "bad parser" "wonderful parser")
$ echo "${parser_name} is a ${BP_Positionals_1}" 
BosParse is a wonderful parser

$ bosparse -name=BosParse ~json -- "Solar System"
{
  "name": "BosParse",
  "BP_Positionals": [
    "Solar System"
  ]
}
```
