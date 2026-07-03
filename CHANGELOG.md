# Changelog

Releases are cut from the top heading here by `self-release.yml`; consumers pin
an exact version and upgrade through grouped Dependabot PRs. Versioning rules
live in the README. Newest first.

## 1.0.3

Internal only — no change to the caller / Makefile contract, so consumers get
a no-op Dependabot bump:

- ci now releases itself through the shared `release.sh` (the same engine
  consumers run via the release-tool action); `self_release.sh` is deleted.
  The internal-ref freeze became the `release_stamp_tree` hook in
  `tool/ci/release_hooks.sh` — the same per-repo extension mechanism
  pdf_manipulator uses for asset hashing. ci release notes now carry the same
  commits-since-last-release collapsible as every consumer release.
- `release.sh`: `release_stamp_tree` hook point in `--discover`; runs on
  repos without a `pubspec.yaml` (title falls back to the repo slug, version
  stamp skips, pub.dev-only modes refuse); the `main` branch maps to the
  stable changelog lane; release commits use a per-commit bot identity
  (`git -c`) instead of persisting it into the repo config.

## 1.0.2

Internal only — no change to the caller / Makefile contract, so consumers get a
no-op Dependabot bump:

- Auto-release: `self-release.yml` cuts the tag on a changelog-PR merge, via a
  `RELEASE_TOKEN` fine-grained PAT (the stamp commit edits workflow files, which
  the default token can't push). `make release` stays as a manual fallback.
- Deploy secrets tooling (`deploy/.deploy/secrets.sh`) for the `release`
  environment.
- Canonical `.gitignore` stamped.
- Release stamp is now block-aware: every `whuppi/ci` checkout `ref` is frozen
  to the tag (previously a checkout missing a marker comment could leak
  `ref: main` into the release — a consumer's pinned `pr-checks` then pulled
  `main`'s tool scripts). The stamp self-verifies no `@main` / `ref: main`
  survives.
- Release stamp identity is applied per-commit (`git -c`), never persisted to
  the repo config — a local `make release` no longer re-authors the
  maintainer's later commits as the bot.

## 1.0.1

- fvm capability now runs `flutter pub get` after installing the SDK, so
  every make target runs against a resolved package. Fixes a cold-cache flake
  where a bare `dart analyze` (no `.dart_tool`) couldn't resolve dependency
  types and `strict-inference` flooded with spurious "can't infer" failures.

## 1.0.0

Initial release — shared CI for whuppi's Flutter/Dart package repos:

- Reusable workflows: pr-checks, triage, auto-close, labels, retry,
  upgrade-check, release.
- Composite actions: make-target + its capabilities, release-tool,
  matrix-filter, debug-ssh.
- Pinned, sha256-verified tool supply chain (`tool/versions.env`) with its own
  daily upgrade radar, and versioned releases via internal-ref stamping.
