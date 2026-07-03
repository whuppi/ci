# Changelog

Releases are cut from the top heading here by `self-release.yml`; consumers pin
an exact version and upgrade through grouped Dependabot PRs. Versioning rules
live in the README. Newest first.

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
