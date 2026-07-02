# whuppi/ci

Shared CI for whuppi's Flutter/Dart package repos. Three things live here:

- **Reusable workflows** — a consumer's `.github/workflows/*.yml` are thin
  callers that own the triggers and concurrency; the jobs live here.
- **Composite actions** — `make-target` provisions capabilities (Chrome, an
  emulator, an Xcode cache…) and runs a Makefile target, so the Makefile stays
  the single source of truth for what CI runs, the same locally and in CI.
- **A pinned-tool supply chain** — `tool/versions.env` pins fvm, Chrome, bore,
  zizmor, and actionlint; every binary is sha256-verified through
  `tool/fetch_verified.sh` before it runs.

## Consuming

| Reusable workflow | What it does | Caller trigger |
|---|---|---|
| `pr-checks.yml` | commit-title, promotion chain, changelog sanity, workflow+shell lint | `pull_request` |
| `triage.yml` | auto-label + assign, revoke stale `ready-to-test` | `issues`, `pull_request_target` |
| `auto-close.yml` | resolved-issue lifecycle | `issues`, `issue_comment`, `schedule` |
| `labels.yml` | sync labels to `.github/labels.json` | `push` (labels.json) |
| `retry.yml` | one auto-retry of a failed run | `workflow_run` |
| `upgrade-check.yml` | Flutter-SDK + lockfile refresh PRs | `schedule` |
| `release.yml` | gate → discover → publish to pub.dev | `push` (changelog) |

A caller stub owns the trigger and grants the callee's job permissions:

```yaml
name: PR Checks
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
    branches: [dev, prod]
permissions: {}
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  checks:
    permissions:
      contents: read
      pull-requests: write
    uses: whuppi/ci/.github/workflows/pr-checks.yml@v1.0.0
```

A consumer's own CI workflow uses `make-target` directly, declaring capabilities
as booleans:

```yaml
  test-web:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with: { persist-credentials: false }
      - uses: whuppi/ci/actions/make-target@v1.0.0
        with:
          make-target: test-web
          chrome: true
          headless-display: true
```

## The version contract

Releases are cut from `CHANGELOG.md` by `self-release.yml` as immutable version
tags (`v1.0.0`, `v1.1.0`…). **There is no moving major tag** — a moving tag
would change under every consumer at once, untested. Consumers pin an exact
version everywhere and upgrade individually: Dependabot opens one grouped PR per
consumer bumping every `whuppi/ci` ref together, and that PR runs the consumer's
own CI before merge. An old pin keeps working forever.

`MAJOR` = a consumer must change its caller stubs or Makefile contract; `MINOR`
= additive (new capability/input/workflow); `PATCH` = fixes and pin bumps.

Internal references (make-target → its capabilities, a reusable workflow → its
`tool/` checkout) say `@main` on the `main` branch; `self-release.yml` stamps
them to the release tag in a detached release commit, so a consumer calling any
file `@v1.2.0` gets internal refs that also resolve to `v1.2.0`. Never
hand-write a version tag into an internal ref — `self-check.yml` fails the PR.

## Pins ownership

| Pin | Owned by | Bumped by |
|---|---|---|
| fvm, Chrome, bore, zizmor, actionlint (+ sha256) | this repo (`tool/versions.env`) | `self-upgrade.yml` — one bump reaches every consumer via the next release |
| Flutter SDK (`.fvmrc`), lockfiles | consumer repo | reusable `upgrade-check.yml` |
| pub deps, action SHAs | consumer repo / this repo | Dependabot |

## Repo model

`main` plus version tags — no dev/prod promotion chain. Consumers pin tags, not
branches, so a promotion chain guards nothing here. This is a deliberate
deviation from the workspace standard in `whuppi/docs/universal/repo-setup.md`
§2, which governs the package repos.

## Local gates

`make check` runs the shell portability gate (`tool/lint_shell.sh`) and the
workflow/action YAML parse, then actionlint and zizmor when they're installed
(CI enforces the full set regardless). `make pins-check` HEADs every pinned
asset.

## Docs

- `docs/ARCHITECTURE.md` — how consumption, the stamping rule, and the release
  model fit together.
- `docs/BUILD_SPEC.md` — the build record: how this repo was generalized from
  the reference package's CI.
