#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# self_release.sh — whuppi/ci's OWN release cut.
#
# whuppi/ci ships versioned, immutable releases so each consumer can
# upgrade its pin on its own time, tested by that consumer's PR. This
# script drives that from a single-lane CHANGELOG.md on `main`, the same
# changelog-driven shape the package repos use — but with one extra job:
# THE STAMP.
#
# The stamp (why this file exists)
# ────────────────────────────────
# On `main`, every internal whuppi/ci reference says `@main`:
#   uses: whuppi/ci/actions/capabilities/fvm@main
#   repository: whuppi/ci   ref: main
# so the repo is self-consistent for anyone consuming `@main` and for its
# own PR checks. At release time, --discover rewrites every `@main` (and
# every `ref: main`) to the release tag IN A DETACHED RELEASE COMMIT, tags
# THAT commit, and never touches main. Result: a consumer calling any file
# `@v1.2.0` gets internal refs that also say `v1.2.0`, byte-for-byte — the
# tag is the compatibility unit and internals can't skew from it.
#
# Modes
# ─────
#   --gate            Should this push trigger a release? (CHANGELOG.md)
#                     Env: BEFORE, AFTER (optional). Outputs: should_run, version.
#   --check-versions  Fail if the changelog adds >1 unreleased version.
#   --discover        Stamp internal refs, tag, create the GitHub release.
#                     Outputs: tag, version, has_release.
#
# Version discipline (state it in the changelog + README too):
#   MAJOR  a consumer must change its caller stubs or Makefile contract
#   MINOR  new capability / input / workflow (additive)
#   PATCH  fixes + pinned-tool/binary bumps
#
# Requires : gh CLI authenticated (GH_TOKEN). Run from the repo root.
# ════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

MODE="${1:---help}"
CHANGELOG="CHANGELOG.md"

usage() {
  cat <<'EOF'
Usage: self_release.sh <mode>

  --gate            Env: BEFORE, AFTER. Outputs should_run, version.
  --check-versions  Fail if CHANGELOG.md adds >1 unreleased version.
  --discover        Stamp internal @main refs → tag, create the release.
                    Env: GH_TOKEN. Outputs tag, version, has_release.
EOF
}

# ── helpers (mirrors release.sh idioms; kept local so this file stands alone) ──

gh_output() {
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"
  echo "  output: $1=$2"
}

git_ci_identity() {
  git config user.name  "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  [ -n "${GH_TOKEN:-}" ] && gh auth setup-git
}

valid_semver() {  # X.Y.Z (+ optional -pre / +build)
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
}

# Every "## version" heading, newest-first, one per line.
get_changelog_versions() {
  sed -n 's/^## \([^ ]*\).*/\1/p' "$1" 2>/dev/null || true
}

# One version's body (heading excluded); the version is regex-escaped.
extract_entry() {
  local file="$1" version="$2" escaped
  escaped=$(printf '%s' "$version" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
  awk "/^## ${escaped}($| )/{found=1; next} /^## /{found=0} found" "$file"
}

REPO="${GITHUB_REPOSITORY:-whuppi/ci}"

# ── --gate ──────────────────────────────────────────────────────────
# Trigger only when this push added a NEW top heading to CHANGELOG.md.
# No BEFORE (dispatch/force-push/new branch) → fall back to a tag check on
# the top heading. A wasted run is cheap; a missed release is not.
cmd_gate() {
  local versions_after new_version
  versions_after=$(get_changelog_versions "$CHANGELOG")

  if [ -z "${BEFORE:-}" ]; then
    new_version=$(head -1 <<< "$versions_after")
    if [ -n "$new_version" ] && git rev-parse "v$new_version" &>/dev/null; then
      echo "Gate: top version $new_version already tagged v$new_version — skipping"
      new_version=""
    fi
  else
    local versions_before
    versions_before=$(git show "${BEFORE}:$CHANGELOG" 2>/dev/null \
      | sed -n 's/^## \([^ ]*\).*/\1/p' || true)
    new_version=$(comm -23 <(sort <<< "$versions_after") <(sort <<< "$versions_before") | head -1)
  fi

  if [ -n "$new_version" ] && valid_semver "$new_version"; then
    gh_output should_run true
    gh_output version "$new_version"
    echo "Gate: $new_version is new — triggering release"
  else
    gh_output should_run false
    gh_output version ""
    echo "Gate: no new valid version at the top of $CHANGELOG — skipping"
  fi
}

# ── --check-versions ────────────────────────────────────────────────
# The top heading is the release candidate (allowed untagged — about to be
# tagged). EVERY heading below it must carry its own v<version> git tag.
# No pub.dev / no-tag clause: this repo has no registry to prove against.
cmd_check_versions() {
  [ -f "$CHANGELOG" ] || { echo "✓ no $CHANGELOG — nothing to check"; return 0; }
  git fetch --tags --quiet origin 2>/dev/null || true

  local versions total
  versions=$(get_changelog_versions "$CHANGELOG")
  total=0
  [ -n "$versions" ] && total=$(grep -c . <<< "$versions")

  local top_ver
  top_ver=$(head -1 <<< "$versions")
  if [ -n "$top_ver" ] && ! valid_semver "$top_ver"; then
    echo "✗ $CHANGELOG: top version '$top_ver' is not valid semver" >&2
    return 1
  fi
  if [ "$total" -le 1 ]; then
    echo "✓ $CHANGELOG: $total heading(s) — nothing below the top to check"
    return 0
  fi

  echo "Top (release candidate): $top_ver — exempt"
  local -a faulty=()
  local idx=0 ver
  while IFS= read -r ver; do
    idx=$((idx + 1))
    [ "$idx" -eq 1 ] && continue
    [ -z "$ver" ] && continue
    if git rev-parse -q --verify "refs/tags/v$ver" >/dev/null 2>&1; then
      echo "  • $ver — tag v$ver ✓"
    else
      faulty+=("$ver")
      echo "  ✗ $ver — no tag v$ver"
    fi
  done <<< "$versions"

  if [ ${#faulty[@]} -gt 0 ]; then
    echo ""
    echo "::error::$CHANGELOG: below-top version(s) with no git tag — ${faulty[*]}"
    echo "A release is cut from the TOP heading only, so these would silently collapse into it."
    echo "Release each before adding a newer one, or fold it into the top."
    return 1
  fi
  echo ""
  echo "✓ $CHANGELOG: one new version at the top ($top_ver); every heading below is tagged"
}

# ── the stamp ───────────────────────────────────────────────────────
# Rewrite every internal whuppi/ci ref @main → @<tag>, and every
# `ref: main` marked by the stamp comment → `ref: <tag>`, across the
# tracked workflow + action files. Fails if any @main survives.
stamp_internal_refs() {
  local tag="$1" f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    sed -i.bak \
      -e "s|\(uses:[[:space:]]*whuppi/ci[^@[:space:]]*\)@main|\1@$tag|g" \
      -e "s|^\([[:space:]]*ref:\)[[:space:]]*main[[:space:]]*#[[:space:]]*stamped.*$|\1 $tag|" \
      "$f" && rm -f "$f.bak"
  done < <(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml')

  local leftover
  leftover=$(grep -rnE 'uses:[[:space:]]*whuppi/ci[^@[:space:]]*@main' \
    .github/workflows/ actions/ 2>/dev/null || true)
  if [ -n "$leftover" ]; then
    printf '%s\n' "$leftover" >&2
    echo "::error::stamp left @main internal refs unresolved — see above" >&2
    return 1
  fi
}

# ── --discover ──────────────────────────────────────────────────────
cmd_discover() {
  [ -f "$CHANGELOG" ] || { gh_output has_release false; echo "No $CHANGELOG"; return 0; }

  local version tag
  version=$(get_changelog_versions "$CHANGELOG" | head -1 || true)
  if [ -z "$version" ] || ! valid_semver "$version"; then
    gh_output has_release false
    echo "No valid version heading in $CHANGELOG"
    return 0
  fi
  tag="v$version"

  if gh release view "$tag" --repo "$REPO" --json tagName >/dev/null 2>&1; then
    echo "Release $tag already exists."
    gh_output tag "$tag"
    gh_output version "$version"
    gh_output has_release true
    return 0
  fi

  echo "=== Stamping internal refs → $tag ==="
  stamp_internal_refs "$tag"

  git_ci_identity
  git add -A
  if git diff --cached --quiet; then
    echo "  Nothing to stamp — refs already pinned? (unexpected on main)"
  else
    # Conventional-commit type so the commit-msg hook passes on a local cut
    # (docs/UPDATING.md documents the maintainer-machine path). If the commit
    # fails anyway, restore the tree so no stamped ref lingers uncommitted.
    git commit -m "chore(release): $tag — stamp internal refs" || {
      git reset --hard HEAD
      echo "::error::stamp commit failed — tree restored, nothing stamped" >&2
      return 1
    }
  fi

  local stamped_sha staging
  stamped_sha=$(git rev-parse HEAD)
  staging="_release-staging-$version"
  echo "  Stamped commit: $stamped_sha"

  # Push the detached stamped commit to a staging branch so the release can
  # target it; main itself never carries the stamp. The tag keeps the commit
  # alive after the staging branch is deleted.
  git push origin --delete "refs/heads/$staging" 2>/dev/null || true
  git push origin "$stamped_sha:refs/heads/$staging"
  trap 'git push origin --delete "refs/heads/'"$staging"'" 2>/dev/null || true' EXIT

  local notes
  notes=$(mktemp)
  extract_entry "$CHANGELOG" "$version" > "$notes"

  gh release create "$tag" \
    --repo "$REPO" \
    --target "$stamped_sha" \
    --title "whuppi/ci $version" \
    --notes-file "$notes"
  rm -f "$notes"
  echo "  Created release $tag at $stamped_sha"

  trap - EXIT
  git push origin --delete "refs/heads/$staging" 2>/dev/null || true

  gh_output tag "$tag"
  gh_output version "$version"
  gh_output has_release true
}

case "$MODE" in
  --help | -h)      usage ;;
  --gate)           cmd_gate ;;
  --check-versions) cmd_check_versions ;;
  --discover)       cmd_discover ;;
  *) echo "Unknown mode: $MODE" >&2; usage >&2; exit 1 ;;
esac
