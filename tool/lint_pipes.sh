#!/usr/bin/env bash
# shellcheck shell=bash
# whuppi/ci's own gate, not stamped into consumers. Under `set -o pipefail`, a
# reader that quits early (head, a quiet or max-count grep, a sed quit) closes
# the pipe while the writer may still be writing; the writer dies of SIGPIPE,
# the pipeline returns 141, and the step fails or an `if` reads false. It is a
# race: a writer that finishes in one write passes, one that writes line by
# line (oras version, ps, adb) fails at random. So a pipe feeds a reader that
# reads to the end: `sed -n 1p` for the first line, a plain grep sent to
# /dev/null for a match test. A quiet grep fed by printf or echo of a variable
# stays: that writer is done in one write before the reader starts.
# Patterns name the readers in prose-free regex, so this file never matches itself.
set -uo pipefail

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "lint_pipes: run inside a git repo" >&2; exit 2; }

files=(/dev/null)
while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.sh' '*.yml' '*.yaml' 'hooks/*')

echo "── pipes read to the end (tracked shell + YAML) ──"
found=$(grep -nE '[|][[:space:]]*(he[a]d([[:space:]]|$)|sed[[:space:]]+-?[0-9]*q|grep[[:space:]]+(-[a-zA-Z]*[qm][a-zA-Z]*|--quiet|--max-count))' "${files[@]}" 2>/dev/null \
  | grep -vE '(printf|echo)[[:space:]][^|]*[|][[:space:]]*grep[[:space:]]+-[a-zA-Z]*q' || true)
if [ -z "$found" ]; then
  echo "  clean — every pipe reader reads to the end"
  exit 0
fi
echo "  early-exit reader after a pipe (SIGPIPE under pipefail; use sed -n 1p, or a plain grep to /dev/null):" >&2
printf '%s\n' "$found" | sed 's/^/    /' >&2
exit 1
