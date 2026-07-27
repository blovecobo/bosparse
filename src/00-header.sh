#!/usr/bin/env bash

# Module header: script preamble
#   - Shebang and interpreter declaration
#   - Project metadata (author, version, platform requirements)
#   - Usage examples for all run modes (source, eval, capture)
#   - Both CML styles: watershed (-- separator) and islands (LID-based)
#   - Dependency notes (bash 5.2+, jq for JSON)
#   - Brief changelog of key features
#   - Strict mode: set -euo pipefail
#
# BosParse - a parameter parser in & for bash script
# author: blovecobo
# version: 0.2.3
# platform: bash 4.4+
#
# usage:
#	- style:
#	  - watershed style:
#	    bosparse [options] -- [positionals]
#	  - islands style:
#	    bosparse [options | positionals]
#   - source mode(watershed style):
#       source bosparse
#       bosparse [options] -- [positionals]
#   - eval mode(watershed style):
#       eval $(./bosparse [options] -- [positionals])
#   - capture mode:
#       json=$(./bosparse ~j [options] -- [positionals])
#
# dependencies:
#   - bash, version 4.4+(will use 5.2+ in next version to avoid circular name reference using ${!nameref})
#   - jq, if output json(capture-mode) or serialized-pfilter passed

# change log:
#   - fix valiate pfilter name confict
#   - refactor 'bp_validate_pfilter()'
#
set -euo pipefail
