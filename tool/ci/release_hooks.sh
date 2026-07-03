# shellcheck shell=bash
# whuppi/ci's OWN consumer-extension file for the shared release.sh — used
# when ci releases ITSELF. (A package repo's hook file lives in that repo's
# own tool/ci/, resolved against the working directory; this one is never
# sourced for consumer releases.) Source, don't execute.
#
# The stamp (why this hook exists)
# ────────────────────────────────
# On `main`, every internal whuppi/ci reference says `@main`:
#   uses: whuppi/ci/actions/capabilities/fvm@main
#   repository: whuppi/ci   ref: main
# so the repo is self-consistent for anyone consuming `@main` and for its
# own PR checks. At release time this hook rewrites every `@main` (and every
# whuppi/ci checkout `ref: main`) to the release tag inside release.sh's
# detached release commit — main never carries the stamp. Result: a consumer
# calling any file `@v1.2.0` gets internal refs that also say `v1.2.0`,
# byte-for-byte — the tag is the compatibility unit and internals can't skew
# from it.
#
# The checkout ref is stamped BLOCK-AWARE, not by a marker comment: any
# `ref: main` YAML key sitting inside a `repository: whuppi/ci` checkout is
# stamped, so a forgotten comment can never silently leak a ref. Matched by
# exact YAML-key shape (`^\s*ref:\s*main...$`), so a guard's grep string that
# merely mentions the tokens is never touched, and a plain self-checkout
# (`actions/checkout` with no `repository:`) correctly stays `ref: main`.
# Self-verifies: fails (aborting the release) if any internal @main /
# whuppi-ci `ref: main` survives.
release_stamp_tree() {
  local tag="$1" f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    awk -v tag="$tag" '
      { line = $0 }
      line ~ /^[[:space:]]*repository:[[:space:]]*whuppi\/ci[[:space:]]*$/ { inblk = 1 }
      inblk && line ~ /^[[:space:]]*ref:[[:space:]]*main([[:space:]]*(#.*)?)?$/ {
        match(line, /^[[:space:]]*/); line = substr(line, 1, RLENGTH) "ref: " tag; inblk = 0
      }
      line ~ /^[[:space:]]*-[[:space:]]/ { inblk = 0 }
      { print line }
    ' "$f" > "$f.stamp.tmp"
    sed "s|\(uses:[[:space:]]*whuppi/ci[^@[:space:]]*\)@main|\1@$tag|g" "$f.stamp.tmp" > "$f"
    rm -f "$f.stamp.tmp"
  done < <(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml')

  local uses_left ref_left
  uses_left=$(grep -rnE 'uses:[[:space:]]*whuppi/ci[^@[:space:]]*@main' \
    .github/workflows/ actions/ 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  ref_left=$(
    while IFS= read -r f; do
      awk -v F="$f" '
        $0 ~ /^[[:space:]]*repository:[[:space:]]*whuppi\/ci[[:space:]]*$/ { inblk = 1; next }
        inblk && $0 ~ /^[[:space:]]*ref:[[:space:]]*main([[:space:]]*(#.*)?)?$/ { print F ": " $0; inblk = 0 }
        $0 ~ /^[[:space:]]*-[[:space:]]/ { inblk = 0 }
      ' "$f"
    done < <(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml')
  )
  if [ -n "$uses_left$ref_left" ]; then
    [ -n "$uses_left" ] && printf '%s\n' "$uses_left" >&2
    [ -n "$ref_left" ]  && printf '%s\n' "$ref_left" >&2
    echo "::error::stamp left internal @main / whuppi-ci ref: main unresolved — see above" >&2
    return 1
  fi
}
