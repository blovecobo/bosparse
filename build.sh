#!/usr/bin/env bash
# BosParse build script
# Concatenates modules from src/ into a single bosparse script
# Usage:
#   ./build.sh              # build to ./bosparse (default)
#   ./build.sh ./bosparse   # build to custom path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-${SCRIPT_DIR}/bosparse}"
SRC_DIR="${SCRIPT_DIR}/src"

MODULES=(
  00-header.sh
  01-util.sh
  02-defs.sh
  03-helpers.sh
  04-pfilter.sh
  05-parse.sh
  06-validate.sh
  07-output.sh
  08-main.sh
)

echo "Building BosParse from modules..."

# Check all modules exist
for mod in "${MODULES[@]}"; do
  [[ -f "${SRC_DIR}/${mod}" ]] || { echo "Error: missing ${SRC_DIR}/${mod}" >&2; exit 1; }
done

# Concatenate modules
{
  for mod in "${MODULES[@]}"; do
    cat "${SRC_DIR}/${mod}"
    echo  # ensure trailing newline
  done
} > "$OUTPUT"

chmod +x "$OUTPUT"

# Validate syntax
if bash -n "$OUTPUT"; then
  echo "Build successful: $(wc -l < "$OUTPUT") lines -> $OUTPUT"
else
  echo "ERROR: Built script has syntax errors!" >&2
  exit 1
fi
