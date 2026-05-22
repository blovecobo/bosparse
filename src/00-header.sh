#!/usr/bin/env bash

# BosParse - a parameter parser in & for bash script
# author: blovecobo
# version: 0.2.0
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
#   - bash, version 4.4+
#   - jq, if output json(capture, serialize pfilter) used

# changelog:
#   - islands/watershed ~~~style
#   - add pset ~dvo (disable values output) for source mode
#   - add new PFILTER format: "keys-values" string, no-need special serialize function
#
set -euo pipefail
