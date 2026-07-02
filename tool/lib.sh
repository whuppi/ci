# shellcheck shell=bash
# Shared helpers — ONLY functions used by 2+ scripts belong here.
# Single-use functions stay in their own script. Source, don't execute.
#
#   source "$(dirname "$0")/lib.sh"

# Gate for tools that ship on every GitHub runner but aren't cleanly
# auto-installable (gh, jq). Present → use it. Missing → error with
# instructions and exit 1: on CI that means a broken runner image; locally
# the dev installs it. No auto-install path — unlike provide_tool, which is
# for tools CI genuinely has to fetch.
require_present() {
  local cmd="$1"; shift
  command -v "$cmd" >/dev/null 2>&1 && return 0
  echo "Error: '$cmd' not found. Install it:" >&2
  local line
  for line in "$@"; do echo "  $line" >&2; done
  exit 1
}

# jq is one of those pre-installed tools.
ensure_jq() {
  require_present jq \
    "macOS:   brew install jq" \
    "Linux:   sudo apt-get install jq" \
    "Windows: choco install jq"
}

# Read a value from a JSON file by jq path. jq does the parse, so nested paths
# work: json_get '.a.b' file.json. Errors if the path is absent or null.
#   ver=$(json_get '.flutter' .fvmrc)
json_get() {
  local expr="$1" file="${2:?json_get requires a file argument}"
  ensure_jq
  jq -er "$expr" "$file" 2>/dev/null || {
    echo "Error: '$expr' not found in $file" >&2
    exit 1
  }
}

# sha256 of a file. GNU coreutils ships sha256sum; macOS ships
# `shasum -a 256`. Use whichever exists; print the bare hash. Feed the file on
# stdin, never as a path argument: both escape the output line — a backslash
# before the digest — when the filename contains a backslash, as every Windows
# Git Bash path does. Stdin keeps the filename out of the output entirely.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | awk '{print $1}'
  else
    shasum -a 256 < "$1" | awk '{print $1}'
  fi
}
