# Migration — onboarding a consumer, upgrading between majors

Two audiences: a new package repo adopting the shared CI, and an existing
consumer crossing a MAJOR version boundary.

---

## Onboarding a new package repo

The reference consumers are `device_io` (pure-plugin package, fully on the
shared surface) and `pdf_manipulator` (native-build package that keeps its
rust/wasm machinery local). Copy from device_io unless you ship binaries.

1. **Caller stubs** (`.github/workflows/`) — thin callers for pr-checks,
   triage, auto-close, labels, retry, upgrade-check, release, plus a
   debug-ssh dispatch workflow. Each owns its triggers + concurrency, grants
   the union of the callee jobs' permissions, and pins
   `whuppi/ci/...@vX.Y.Z` (current release, exact — never `@main`).
2. **Own workflows** — `ci.yml` (fast PR gate: jobs = make targets via
   `make-target`) and `full-test.yml` (label-triggered matrix; rows gate
   through `matrix-filter`). The Makefile is the contract: CI runs nothing a
   contributor can't run locally.
3. **Repo config** (`.github/`) — `labels.json` (include `upgrade-sdk`,
   `upgrade-locks`, `ready-to-test`, `resolved`, `bot-closing-soon`),
   `labeler.yml`, `actionlint.yaml` (copy from here), `CODEOWNERS`,
   `zizmor.yml` (the `whuppi/ci/*: ref-pin` policy), and `dependabot.yml`
   with the grouped bump channel:

   ```yaml
   groups:
     whuppi-ci:
       patterns: ["whuppi/ci*"]   # the * matters — action names include paths
   ```

4. **Hooks** — add the repo to the workspace `stamp-hooks.sh` REPOS list and
   stamp; add a `make hooks` target (`git config core.hooksPath .githooks`).
5. **Changelogs** — two-lane (`CHANGELOG.md` + `CHANGELOG.pre.md`), one
   untagged version max at the top of each. The release pipeline is driven
   entirely by these files.
6. **After push** — dev/prod GitHub environments (prod with required
   reviewers), `PUB_CREDENTIALS` per environment, branch protection with the
   gate job names, one `labels.yml` dispatch run.

Binary-shipping packages additionally: keep native capabilities local, author
a release workflow around `release-tool` steps with your compile/upload jobs
(pdf_manipulator's `create-release.yml` is the shape), and put any extra
asset hashing in `tool/ci/release_hooks.sh`.

---

## Upgrading between MAJOR versions

A MAJOR release means a caller stub or the Makefile contract must change; the
grouped Dependabot PR will go red on your own CI until you adapt. Each major
gets a section here listing exactly what to change.

*(None yet — v1 is the initial release.)*
