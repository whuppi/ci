# whuppi/ci — Architecture

How the shared CI is put together. For the consumer-facing surface see the
README. (This repo was generalized from pdf_manipulator's battle-tested CI;
that history lives in git, not in a doc.)

## Two consumption mechanisms

**Reusable workflows** (`workflow_call`). A consumer's workflow file is a thin
caller: it owns the `on:` triggers, the `concurrency` group, and any
privileged-trigger `zizmor: ignore` comment; it calls a workflow here with
`uses: whuppi/ci/.github/workflows/<name>.yml@vX.Y.Z`. The callee owns the jobs.
A caller job must grant the union of the callee jobs' permissions. Callees take
a `runner` string input rather than a `workflow_dispatch` choice menu — the menu
belongs caller-side.

**Composite actions**. A consumer's own workflows (its fast-gate `ci.yml`, its
cross-target `full-test.yml`) call `whuppi/ci/actions/make-target@vX.Y.Z`, which
provisions capabilities and runs a Makefile target. The Makefile is the single
source of truth for what CI runs, so the same command runs locally and in CI.

## Script access — two paths, never crossed

A composite action reads its own repo's files through `GITHUB_ACTION_PATH` (the
runner materializes the whole action repo under `_actions/…`, separate from any
consumer checkout). Depth from an action file to the repo root:

| Action file | Repo root |
|---|---|
| `actions/capabilities/<x>/action.yml` | `$GITHUB_ACTION_PATH/../../..` |
| `actions/debug-ssh/action.yml`, `actions/release-tool/action.yml` | `$GITHUB_ACTION_PATH/../..` |

Each such `run:` block sets a `CI_ROOT` from that depth and sources
`"$CI_ROOT/tool/versions.env"` / calls the tool scripts through it.
(`make-target` and `matrix-filter` read no repo files — pure composition
and pure logic respectively.)

For running the shared release.sh, prefer the `release-tool` action over a
workspace checkout, in every workflow — reusable AND consumer-authored. It runs
the script from the action cache in the consumer's working directory, so (a)
its ref is Dependabot-bumpable like any action (a checkout step's `with: ref:`
is NOT), and (b) nothing shared sits in the workspace to leak into a stamped
release tree or pub tarball. The remaining `.whuppi-ci/` checkout pattern is
for reusable-workflow jobs that need MULTIPLE tool files at once (pr-checks'
workflow-lint: versions.env + lint_shell + the commit-types fallback); as
defense-in-depth, release.sh's discover excludes `.whuppi-ci` from the stamped
tree even though nothing should put it there anymore.

## make-target — the orchestration contract

Capabilities are independent actions under `actions/capabilities/`, each
provisioning one thing (a JDK, a pinned Chrome, an emulator). `make-target` is a
flat list of `if:`-gated capability calls with zero logic of its own. The run
command is authored ONCE into `/tmp/make-run.sh` — `flutter doctor -v` then
`make <target>` — and both the direct path and the emulator path execute that
same file, so the two can never drift. Doctor always runs against the fully
provisioned environment (live emulator on Android, host elsewhere) on the line
before make.

The Android emulator carries a teardown watchdog: on CPU-starved CI emulators
Flutter's teardown hangs (adb force-stop on Binder IPC; fire-and-forget DDS
shutdown), so the watchdog kills the stuck teardown and a reconciler
(`tool/ci/reconcile_test_json.sh`) decides pass/fail from the machine JSON
report plus the captured console, not the killed process's exit code. The report
path is an input (`report-json`, default `test-results/int-android.json`) the
consumer's make target must write to.

A full-test matrix row gates itself with the `matrix-filter` action (portability
toggle + name filter → a `match` output every later step checks), so a skipped
row completes green without provisioning anything.

## The versioned-release model + the stamping rule

whuppi/ci ships immutable version tags cut from `CHANGELOG.md`. Consumers pin
exact versions and upgrade one repo at a time through a grouped Dependabot PR
that runs that consumer's own CI. This is the whole reason for versioned
releases: a shared-CI change lands in each consumer on its own schedule, tested
by the PR that adopts it, never all at once.

The subtlety this creates is internal self-consistency. whuppi/ci's own cross-
references — make-target → its capabilities, a reusable workflow → its
`.whuppi-ci` checkout — must resolve to the SAME version the consumer pinned. On
`main` every internal ref says `@main` (and `ref: main`), so the repo is
self-consistent for anyone consuming `@main` and for its own PR checks. At
release time, `self-release.yml` runs `tool/ci/self_release.sh --discover`, which
rewrites every `@main` → `@vX.Y.Z` and every stamp-marked `ref: main` →
`ref: vX.Y.Z` in a detached commit, tags that commit, and creates the release.
`main` never carries the stamp. `self-check.yml`'s `internal-refs-are-main` job
fails any PR that hand-writes a version tag into an internal ref, so a stamped
ref can't leak back onto `main` and freeze internals at an old release.

Because these first-party refs are `@main`/`@vX.Y.Z` rather than SHA-pinned,
zizmor's blanket `unpinned-uses` policy would reject them. `.github/zizmor.yml`
sets a `ref-pin` policy for `whuppi/ci/*` only — the tag/branch ref is the pin,
and the stamping makes it exact at release. Every third-party action still
requires a SHA. Consumers carry the same one-line config so their own
`@vX.Y.Z` pins pass the same gate.

## The repo guard

Privileged reusable workflows (triage, retry, labels) guard on
`github.repository_owner == 'whuppi'`, generalizing the reference package's
exact-repo guard. A fork that enables Actions can't run them in its own context;
every whuppi repo can.

## What stays consumer-side

Triggers, concurrency groups, test matrices, the Makefile, the `.github/`
manifests (`labels.json`, `labeler.yml`, `actionlint.yaml`, `CODEOWNERS`,
`dependabot.yml`, `zizmor.yml`), the Flutter SDK pin (`.fvmrc`), the two-lane
changelogs, and any genuinely package-specific machinery (a native build, its
pins, its `release_hooks.sh`). whuppi/ci owns the jobs and the shared supply
chain; the consumer owns what to run them on and what to run.

The git hooks (`.githooks/`) and `tool/commit-types.txt` sit in each consumer
for standalone-clone integrity but are NOT hand-maintained there — the
canonical copies live in this repo (`hooks/`, `tool/commit-types.txt`) and the
workspace's `stamp-hooks.sh` re-stamps every consumer when they change.

## The release surface

`tool/ci/release.sh` (consumer releases) and `tool/ci/self_release.sh` (this
repo's own) share the same changelog-driven shape — a two-lane
(`CHANGELOG.md` + `CHANGELOG.pre.md`) model for packages, single-lane for this
repo. Both gate on "one new version at the top; every heading below is tagged",
discover the version, stamp a tag commit, and create the release. The mode
tables live in each script's header — read those, not a copy here.

## Tag + release discipline for this repo

Cut a release by merging a PR to `main` whose `CHANGELOG.md` gains a new top
heading; `self-release.yml` does the rest. Never hand-tag `main` — the tag must
point at the stamped detached commit, not at `main` (whose internal refs still
say `@main`).

## First-push runbook

The one-time sequence when this repo goes to GitHub:

1. Create `whuppi/ci` → push `main` → add the `RELEASE_TOKEN` secret to the
   `release` environment (a fine-grained PAT for this repo, contents +
   workflows RW — the stamp commit touches workflow files, which
   `GITHUB_TOKEN` can't push). Then a `self-release.yml` dispatch cuts
   `v1.0.0` from the seeded changelog heading — never hand-tag.
2. Org Actions access: if the repo is private, Settings → Actions → Access →
   "Accessible from repositories in the whuppi organization" (public needs
   nothing).
3. Per consumer: create dev/prod GitHub environments (prod with required
   reviewers) + the `PUB_CREDENTIALS` secret per environment; apply the
   repo-setup branch protection with the new required checks (`CI Gate`,
   `Full Test Gate`, the pr-checks job names); run the labels workflow once
   via dispatch.

Steady-state upgrade flow: merge a changelog PR here → self-release cuts
`vX.Y.Z` → each consumer's Dependabot opens ONE grouped PR bumping every
whuppi/ci pin → that PR's fast gate runs automatically; add `ready-to-test`
for the full matrix when the release touches test-path behavior → merge when
green. Consumers upgrade independently; old pins work forever.
