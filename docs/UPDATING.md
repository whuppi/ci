# Updating whuppi/ci

Maintenance recipes. For how the pieces fit together see
[`ARCHITECTURE.md`](ARCHITECTURE.md) — its first-push runbook covers
consumer onboarding.

---

## Who bumps what (the ownership table)

| Thing | Bumped by | You do |
|---|---|---|
| Tool/binary pins (`tool/versions.env`) | `self-upgrade.yml` daily PR | Review the hashes, merge, cut a release |
| Consumer pub deps + third-party actions in **workflow files** | consumer's **Dependabot** (ignoring `whuppi/ci*`) | Review + merge its grouped PRs |
| Every **whuppi/ci ref** (workflow + composite, uniform) + third-party actions **inside composites** | the `composite-refs` job in the reusable `upgrade-check.yml` (opt-in) | Review + merge the one bump PR it opens |
| Consumers' Flutter SDK + lockfiles | reusable `upgrade-check.yml` | Nothing here |

**The composite blind spot (`composite-refs`).** Dependabot's github-actions
updater never reads `uses:` refs inside composite `action.yml`
([dependabot/dependabot-core#6704](https://github.com/dependabot/dependabot-core/issues/6704),
open) — a consumer's vendored `make-target/action.yml`, and any third-party action
pinned inside a composite, is invisible to it. A grouped whuppi/ci bump moves only
the workflow-level refs and splits the pin, which the `pin-availability` gate then
rejects. The opt-in `composite-refs` job owns exactly that gap: it sweeps every
whuppi/ci ref across `.github` (workflows AND composites) to the latest release —
uniform by construction — and pins third-party actions inside composites to the
latest SHA with `pinact`. Dependabot keeps pub deps + third-party actions in
workflow FILES; the two never overlap. A consumer opts in by calling the reusable
with `sweepActions: true`, passing `CI_ACTIONS_TOKEN`, and adding `whuppi/ci*` to
its Dependabot `ignore`. The token is a whuppi org secret (`CI_ACTIONS_TOKEN`, a
Workflows-scope PAT) — the sweep writes `.github/workflows/`, which `GITHUB_TOKEN`
can't.

A pin bump merged to `main` reaches nobody until a release is cut — merging
and releasing are separate, deliberate steps.

## Adding a capability action

1. New `actions/capabilities/<name>/action.yml`. If it downloads a binary:
   pin the version + per-platform sha256 in `tool/versions.env`, fetch through
   `"$CI_ROOT/tool/fetch_verified.sh"` (`CI_ROOT="$GITHUB_ACTION_PATH/../../.."`),
   and add a bump block + `asset_urls` entries to `tool/ci/upgrade.sh` so the
   daily radar owns it.
2. Wire it into `actions/make-target/action.yml`: a new boolean input + an
   `if:`-gated call using `@main` (never a version tag).
3. `make check`, then a MINOR release. Consumers opt in by passing the new
   input — additive, nothing breaks.

## Changing make-target's or a reusable workflow's interface

Inputs, secrets, and job/step contracts ARE the compatibility surface.
Renaming/removing an input, changing a default that alters behavior, or
renaming a gate job consumers list in branch protection = **MAJOR** release +
a CHANGELOG entry spelling out what consumers must change. Adding an optional
input with a safe default = MINOR.

## Editing the shared release script

`tool/ci/release.sh` runs inside every consumer's release. Before merging a
behavior change, prove parity or intent on a real consumer checkout:

```bash
cd ../<consumer> && export GITHUB_REPOSITORY=whuppi/<consumer>
BRANCH=dev  bash ../ci/tool/ci/release.sh --check-versions
BRANCH=prod bash ../ci/tool/ci/release.sh --check-versions
```

Consumer-specific asset hashing belongs in THEIR `tool/ci/release_hooks.sh`
(`release_extra_asset_hashes` → `name<TAB>sha256` lines), never in the shared
script.

## Editing the hooks or commit-types

`hooks/commit-msg`, `hooks/pre-commit`, and `tool/commit-types.txt` here are
the canonical copies. After editing:

```bash
/Users/deepanshu/personal1/whuppi/.claude/scripts/stamp-hooks.sh --apply
```

then commit each consumer's re-stamped files. Never edit a consumer's
`.githooks/` directly — the next stamp reverts it.

## Cutting a release

Prerequisite (one-time): a `RELEASE_TOKEN` secret on the `release` environment —
a fine-grained PAT scoped to THIS repo with **Contents + Workflows read/write**.
The stamp commit edits `.github/workflows/` files, and neither `GITHUB_TOKEN`
nor a GitHub App token can carry the `workflows` scope, so a token that has it
is required. Stored via the deploy tooling:
`deploy/.deploy/secrets.sh set release/RELEASE_TOKEN <pat>`.

1. Merge a PR to `main` adding a new top heading to `CHANGELOG.md`
   (MAJOR/MINOR/PATCH per the README's rules) with a short summary.
2. `self-release.yml` fires on the changelog push: it runs the shared
   `tool/ci/release.sh`, whose `release_stamp_tree` hook stamps every internal
   `@main` → `@vX.Y.Z` in a detached commit, tags it, creates the release.
   `main` never carries the stamp.
3. Consumers' Dependabot opens one grouped PR each (after its cooldown); their
   own CI tests the bump before they merge.

Manual fallback: `make release` cuts a release from your own machine with your
own login (no token needed) — use it if the PAT lapses or to cut without a
changelog push. Never hand-tag `main` — the tag must point at the stamped commit.

## When a pinned asset breaks

`self-check.yml`'s pin-availability job (or `make pins-check`) failing means an
upstream pruned or repointed an asset. `self-upgrade.yml` refuses to bump over
a repoint (`verify-pinned` runs first). Fix by reviewing the new upstream
release and letting `tool/ci/upgrade.sh apply` recompute the hashes — never
hand-edit a hash in `versions.env`.
