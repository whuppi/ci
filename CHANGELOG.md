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
- `upgrade-check` — daily consumer Flutter-SDK + lockfile refresh PRs.
- `release` — gate → discover → git-install-note → publish for a pure-Dart /
  Flutter package (no binary compile/upload jobs).

### Composite actions

- `make-target` — provisions capabilities as declarative booleans, then runs a
  Makefile target; the run command is authored once so the direct and emulator
  paths can't drift.
- Capabilities — fvm, chrome, java, gradle-cache, xcode-cache, pods-cache,
  headless-display, hw-accel, ios-simulator, android-emulator (teardown
  watchdog + JSON reconciler), free-disk-space.
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
