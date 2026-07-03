# Updating whuppi/ci

Maintenance recipes. For how the pieces fit together see
[`ARCHITECTURE.md`](ARCHITECTURE.md); for consumer onboarding and
major-version migration see [`MIGRATION.md`](MIGRATION.md).

---

## Who bumps what (the ownership table)

| Thing | Bumped by | You do |
|---|---|---|
| Tool/binary pins (`tool/versions.env`) | `self-upgrade.yml` daily PR | Review the hashes, merge, cut a release |
| Third-party action SHAs (workflows + composite actions) | Dependabot (7-day cooldown) | Review, merge, cut a release |
| Consumers' Flutter SDK + lockfiles | reusable `upgrade-check.yml` in each consumer | Nothing here |
| Consumers' whuppi/ci pins | each consumer's grouped Dependabot PR, after a release here | Cut the release |

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
a migration note in [`MIGRATION.md`](MIGRATION.md). Adding an optional input
with a safe default = MINOR.

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

Prerequisite (one-time): a `RELEASE_TOKEN` repo secret — a fine-grained PAT
scoped to THIS repo with **contents + workflows read/write**. The stamp commit
modifies `.github/workflows/` files, and the default `GITHUB_TOKEN` can never
carry the `workflows` scope, so its push is rejected.

1. PR to `main` adding a new top heading to `CHANGELOG.md` (MAJOR/MINOR/PATCH
   per the README's rules) with a short summary.
2. Merge. `self-release.yml` gates, stamps every internal `@main` →
   `@vX.Y.Z` in a detached commit, tags it, creates the GitHub release.
3. Consumers' Dependabot opens one grouped PR each (after its cooldown); their
   own CI tests the bump before they merge.

Never hand-tag `main` — the tag must point at the stamped commit. A release
can also be cut from a maintainer machine (credentials with the workflow
scope): `git checkout --detach && GITHUB_REPOSITORY=whuppi/ci bash
tool/ci/self_release.sh --discover && git checkout main`.

## When a pinned asset breaks

`self-check.yml`'s pin-availability job (or `make pins-check`) failing means an
upstream pruned or repointed an asset. `self-upgrade.yml` refuses to bump over
a repoint (`verify-pinned` runs first). Fix by reviewing the new upstream
release and letting `tool/ci/upgrade.sh apply` recompute the hashes — never
hand-edit a hash in `versions.env`.
