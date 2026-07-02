# Changelog

Shared CI for whuppi Flutter/Dart package repos. Releases are cut from the top
heading here by `self-release.yml`; consumers pin an exact version and upgrade
through grouped Dependabot PRs. Newest first.

Version discipline:
- **MAJOR** — a consumer must change its caller stubs or Makefile contract.
- **MINOR** — new capability, input, or reusable workflow (additive).
- **PATCH** — fixes and pinned tool/binary bumps.

## 1.0.0

### Reusable workflows

- `pr-checks` — conventional-commit title, promotion chain, changelog-version
  sanity (both lanes), and workflow lint (zizmor + actionlint + shell
  portability) over the consumer's tree.
- `triage` — auto-label by changed files + title, auto-assign, revoke stale
  `ready-to-test`, dependabot recreate notice.
- `auto-close` — resolved-issue lifecycle (arm, keep-open opt-out, daily sweep).
- `labels` — sync repo labels to the consumer's `.github/labels.json`.
- `retry` — one auto-retry of a failed CI/full-test run's failed jobs.
- `upgrade-check` — daily consumer Flutter-SDK (`upgrade-sdk` label) +
  lockfile (`upgrade-locks`) refresh PRs.
- `release` — gate → discover → git-install-note → publish for a pure-Dart /
  Flutter package (no binary compile/upload jobs), built on `release-tool`.

### Shared consumer files

- `hooks/` — the canonical commit-msg + pre-commit git hooks, stamped into
  each package repo (with `tool/commit-types.txt`) by the workspace's
  stamp-hooks script.

### Composite actions

- `make-target` — provisions capabilities as declarative booleans, then runs a
  Makefile target; the run command is authored once so the direct and emulator
  paths can't drift.
- Capabilities — fvm, chrome, java, gradle-cache, xcode-cache, pods-cache,
  headless-display, hw-accel, ios-simulator, android-emulator (teardown
  watchdog + JSON reconciler), free-disk-space.
- `release-tool` — runs the shared release.sh from the action cache in the
  consumer's working directory; the Dependabot-bumpable way for a
  consumer-authored release workflow (one with its own compile/upload jobs) to
  use the shared release logic. A consumer `tool/ci/release_hooks.sh` extends
  asset hashing.
- `matrix-filter` — the full-test row gate (portability toggle + name filter)
  as one reusable step.
- `debug-ssh` — non-blocking bore tunnel into any runner, key-only auth.

### Supply chain

- `tool/versions.env` pins fvm, Chrome + ChromeDriver, bore, zizmor, and
  actionlint, every binary sha256-verified through `tool/fetch_verified.sh`.
- `self-upgrade.yml` opens a daily pin-bump PR; `self-check.yml` gates PRs
  (lint + pin availability + the internal-refs-are-@main stamping guard).

### Release mechanism

- `self-release.yml` + `tool/ci/self_release.sh` cut immutable version tags from
  this changelog and stamp every internal `@main` reference to the release tag
  in a detached commit — so a consumer calling any file `@vX.Y.Z` gets internal
  refs that also resolve to `vX.Y.Z`.
