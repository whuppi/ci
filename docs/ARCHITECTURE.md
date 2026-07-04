# whuppi/ci — Architecture

How the shared CI is put together. For the consumer-facing surface see the
README. (This repo was generalized from pdf_manipulator's battle-tested CI;
that history lives in git, not in a doc.)

## Where each thing lives — the map

Everything in a consumer repo answers to one question, and the answer forces
both where it sits and how it's shared:

> **Does a human run this locally, or does only CI run it?**

```
                 RUN LOCALLY (via make)          CI-ONLY
                 ──────────────────────          ─────────────────────
 SHARED          stamped .sh                     referenced @v
 (whuppi/ci       analyze_core, lint_shell,       reusable workflows,
  is the truth)   platforms_gate                  make-target, capabilities,
                  copied into each repo →          release-tool, matrix-filter
                  CAN drift; needs a guard         uses: whuppi/ci/…@v; can't drift

 SPECIFIC        owned tool/*.sh + Makefile       owned .github/workflows +
 (the repo        the build, tests, fixtures      tool/ci/*.sh (release_hooks,
  is the truth)                                    the upgrade radar, reconcilers)
```

- **CI-only + shared → reference `@v`.** GitHub delivers it; nothing is copied,
  so it can't drift. This is most of whuppi/ci and where it earns its keep
  (elaborated in *Two consumption mechanisms* and *The release surface*).
- **Local + shared → stamp.** A `make` target can't call a reusable workflow, so
  a locally-runnable shared gate has to be a real file in the repo, copied from
  the canonical one here. The ONE quadrant that can drift.
- **Specific → own it** (enumerated in *What stays consumer-side*).

The naming boundary is load-bearing:
- **`tool/*.sh`** — a human runs it via a `make` target; CI runs the same target.
- **`tool/ci/*.sh`** — CI-only; never run by hand (release_hooks, the upgrade
  radar, the emulator reconciler). May `source` a `tool/*.sh`, but is not a gate.

The folder is the line: never wire a `tool/ci/*.sh` into a `make` gate, and never
drop a CI-only helper into `tool/` root.

Discipline for the stamp quadrant — file-copy stamping, the only drift-prone one
(the workspace stampers copy analyze_core / lint_shell / platforms_gate, the git
hooks, and commit-types into each repo; distinct from the release-time
internal-ref stamping in *The versioned-release model*):
- The canonical copy lives here; the stamped copy in a consumer is never authored
  there — it carries a `# GENERATED from whuppi/ci — do not edit` header.
- One workspace stamper is the single writer; a consistency guard fails a PR
  whose whuppi/ci refs or stamped copies have drifted.
- Prefer reference over stamp: stamp only when it MUST run locally. If it's
  CI-only, make it a workflow or action and reference `@v`.

### Two boundary calls — decided

1. **The stamped local gates stay stamped, hardened.** analyze_core, lint_shell,
   and platforms_gate are genuinely identical across consumers and evolve
   occasionally, so one canonical source guarded against drift beats N per-repo
   copies that diverge silently. Per-repo doesn't kill drift — it hides it. The
   hardening that makes stamping safe (and would have caught every stamp mistake
   this session):
   - every stamped file carries a `# GENERATED from whuppi/ci — do not edit`
     header;
   - `tool/stamped-files.txt` is the manifest of what's stamped — the workspace
     stamper and the drift guard both read it, so neither can disagree about the
     set;
   - the shared pr-checks lint fails any consumer PR whose stamped copy differs
     from the whuppi/ci canonical it pins. Content drift is now caught in CI, not
     discovered by hand.
2. **pdf's make-target fork stays, for now.** It works, and its only real flaw —
   drift — is fixed (one whuppi/ci ref instead of a dozen, plus the
   version-consistency guard). Folding Rust into the shared make-target as a
   first-class capability toggle (deleting the fork) is the right end state, but
   it is built only WHEN a second Rust package makes Rust a shared concern, and
   merged only after a green macos-intel matrix run proven more than once — a
   delegating-wrapper attempt regressed that runner this session and the
   mechanism was never fully pinned.

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
release time, `self-release.yml` (or `make release` locally) runs the shared
`tool/ci/release.sh --discover`, whose `release_stamp_tree` hook (in
`tool/ci/release_hooks.sh`) rewrites every `@main` → `@vX.Y.Z` and every
`whuppi/ci` checkout's `ref: main` → `ref: vX.Y.Z` in a detached commit, tags
that commit, and creates the release.
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

One engine — `tool/ci/release.sh` — releases every repo: consumers run it via
the release-tool action, and this repo runs it directly. It's changelog-driven —
a two-lane (`CHANGELOG.md` + `CHANGELOG.pre.md`) model for packages, single-lane
(`CHANGELOG.md` on `main`) for this repo. It gates on "one new version at the
top; every heading below is tagged", discovers the version, stamps a tag commit,
and creates the release. Per-repo tree edits at stamp time are the
`release_stamp_tree` hook in each repo's `tool/ci/release_hooks.sh` (this repo:
the internal-ref freeze; pdf_manipulator: extra asset hashes). The mode
tables live in each script's header — read those, not a copy here.

## Tag + release discipline for this repo

Cut a release by bumping `CHANGELOG.md`'s top heading (via a merged PR to
`main`), then running `make release` locally. It stamps internal refs, tags the
detached stamped commit, and creates the GitHub release. Never hand-tag `main` —
the tag must point at the stamped detached commit, not at `main` (whose internal
refs still say `@main`).

Why local, not a workflow: the stamp commit edits `.github/workflows/` files,
and GitHub forbids the CI `GITHUB_TOKEN` from pushing workflow-file changes (so
a workflow can't rewrite itself). Running `make release` on the maintainer's own
credentials sidesteps that — no stored PAT, no `release` environment, no
release CI job. The maintainer is the only releaser, so a local command is the
simplest correct shape.

## First-push runbook

The one-time sequence when this repo goes to GitHub:

1. Create `whuppi/ci` → push `main` → add the `RELEASE_TOKEN` secret to the
   `release` environment (a fine-grained PAT for this repo, Contents +
   Workflows RW; store it via `deploy/.deploy/secrets.sh set
   release/RELEASE_TOKEN <pat>`). Then dispatch `self-release.yml` (or run
   `make release` locally) to cut `v1.0.0` from the seeded changelog heading —
   never hand-tag.
2. Org Actions access: if the repo is private, Settings → Actions → Access →
   "Accessible from repositories in the whuppi organization" (public needs
   nothing).
3. Per consumer: create dev/prod GitHub environments (prod with required
   reviewers) + the `PUB_CREDENTIALS` secret per environment; apply the
   repo-setup branch protection with the new required checks (`CI Gate`,
   `Full Test Gate`, the pr-checks job names); run the labels workflow once
   via dispatch.
4. Slopfairy (the shared AI review bot — part of CI/CD, easy to miss because it
   lives outside the repo's own files): add the repo to the `slopfairy-bot` org
   team with push
   (`gh api orgs/whuppi/teams/slopfairy-bot/repos/whuppi/<repo> -X PUT -f permission=push`),
   install the `slopfairy-prod` GitHub App on the repo (org **Settings → GitHub
   Apps → slopfairy-prod → Configure →** add it — the REST install endpoint is
   org-owner-only, so this is a web step), and add `.github/slopfairy.yml` (copy
   device_io's for a pure package, pdf_manipulator's for a native one). Without
   the team + app she can't see the repo's PRs at all.

Steady-state upgrade flow: merge a changelog PR here → `self-release.yml`
cuts `vX.Y.Z` → each consumer's Dependabot opens ONE grouped PR bumping every
whuppi/ci pin → that PR's fast gate runs automatically; add `ready-to-test`
for the full matrix when the release touches test-path behavior → merge when
green. Consumers upgrade independently; old pins work forever.
