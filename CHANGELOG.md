# Changelog

Releases are cut from the top heading here by `self-release.yml`; consumers pin
an exact version and upgrade through grouped Dependabot PRs. Versioning rules
live in the README. Newest first.

## 2.7.3

- `android-emulator`: Windows resumes its AVD snapshot from the ghcr
  backend like Linux and macOS. The earlier Windows resume failure was a
  snapshot taken on a system image the SDK archive never pinned (2.7.2
  fixed both); a miss now cold-boots with snapshots on so the quick-boot
  snapshot is written on kill and archived.

## 2.7.2

- `android-emulator`'s ghcr SDK archive was never saved: its paths were
  built from `${{ env.ANDROID_HOME }}`, which is empty inside a composite
  action (a runner process variable, like `ImageVersion`), so every run
  logged "nothing to save" and re-installed the SDK. The root is now read
  in a step as a POSIX path.
- The AVD snapshot key carries the system-image revision. A snapshot is
  guest RAM taken on one build of `system-images;android-N;aosp_atd;x86_64`;
  resumed onto a re-published build it comes up with dead system services
  (the action's first `adb shell input keyevent 82` failed with "No service
  published for: input" on 3 of 4 Linux rows). The emulator-version step
  installs the image alongside the emulator and reads its `Pkg.Revision`;
  with the SDK archive hitting, the pair stays matched run to run.

## 2.7.1

- `android-emulator`'s SDK cache key read `ImageVersion` from the `env`
  context, where it does not exist (it is a runner process variable), so
  the key ended in `-img` and would never roll with a runner-image update.
  Read in a step; fail loudly if empty.

## 2.7.0

- `android-emulator` gains `sdk-cache-backend: ghcr`: the emulator,
  platform-tools and the API level's system image (~1 GB) are restored from
  the GitHub Container Registry before anything touches the SDK, keyed on
  the runner image version (a new image rolls the key), and saved after the
  emulator is down. Every Linux/macOS row otherwise re-downloaded them
  through sdkmanager (1–2 min). `make-target` forwards it from
  `cache-backend: ghcr`.

## 2.6.3

- `oci-cache`: an archive that cannot be extracted is a miss with a warning,
  never a red job; Windows archives store symlink targets (Git-bash tar
  cannot create symlinks — the Flutter SDK has a few, and every Windows row
  failed on restore); a format version now sits in every tag and is bumped
  with this change, so the existing archives re-save under the new rules.
- `android-emulator` reads the emulator version from the SDK's
  `source.properties` (no execution needed); `emulator -version` on a fresh
  Linux runner printed nothing parseable and failed the row twice.

## 2.6.2

- `oci-cache` refuses to run in a private repository (a package first pushed
  from one is private and counts against the plan's package storage — the
  opposite of what the capability is for). README documents the one-time
  visibility flip a public repo's owner makes after the first push.

## 2.6.1

- `android-emulator` reads the emulator version from the whole
  `emulator -version` output (stderr included) instead of its first line:
  a fresh install prints an `.ini` warning first, which left the version
  empty and failed the row before any AVD work started.

- `fvm` keys the SDK cache on the version named in `.fvmrc`, not on
  `hashFiles('.fvmrc')`: `fvm install` rewrites the file, so the save
  landed under a key no restore ever asked for and every run pushed a
  fresh ~780 MB copy (the duplicate SDK entries on the Actions cache).

## 2.6.0

- Added the `oci-cache` capability: actions/cache semantics (restore / save
  phases, exact key, a floating fallback tag in place of restore-keys) with
  the GitHub Container Registry as the store, via a pinned, sha256-verified
  `oras` on every OS. GitHub Packages is free and uncapped for public
  packages and Actions pulls with GITHUB_TOKEN are free, so the big, stable
  archives leave the 10 GB Actions-cache quota. Credential-bearing paths
  are refused by name. Needs `packages: write` on the job that saves.
- `gradle-cache` (`backend`), `fvm` (`sdk-cache-backend` + `cache-save`) and
  `android-emulator` (`avd-cache-backend`) can store on ghcr; `make-target`
  forwards one `cache-backend`. Default stays `gha` — no consumer changes
  behaviour until it opts in.
- Added the `oci-cache-prune.yml` reusable workflow: deletes cache-package
  versions older than `retention-days` (default 14) and untagged ones;
  fallback tags are never pruned.
- Self Check gains an oci-cache round-trip job on all three OSes (save,
  wipe, exact restore, fallback restore) — the one capability lint cannot
  prove.

## 2.5.1

- `gradle-cache` no longer runs its save phase after an exact-key restore
  hit. GitHub never overwrites an existing key, so the save tarred ~1 GB
  (two minutes on Windows) only to be refused with "Unable to reserve
  cache". A `restore-keys` prefix hit is not exact and still saves.

## 2.5.0

- Added a `save` gate to every cache capability — `gradle-cache`,
  `pods-cache` (auto-saving `actions/cache` vs restore-only) and `android-emulator`
  (`avd-cache-save`) — and one `cache-save` input on the shared
  `make-target` that forwards to all four. Restores are unchanged. GitHub
  scopes a cache to the ref that wrote it and lets a PR read only its base
  and the default branch, so an archive written from `refs/pull/N/merge`
  is invisible to every other PR and only spends quota (a Gradle home is
  ~1 GB per OS, an AVD snapshot ~1 GB). Callers pass
  `cache-save: ${{ github.event_name != 'pull_request' }}` so the default
  branch is the one warm source everyone reads; the defaults keep the old
  save-always behaviour for callers that pass nothing.
- `android-emulator` no longer caches or restores an AVD snapshot on
  Windows: the first warm Windows row (emulator 37.1.11, WHPX) loaded the
  snapshot and then never answered adb for the whole 600 s boot wait, while
  the same row cold-boots fine. Windows cold-boots every run (~5 min, green)
  until the resume is root-caused; Linux/macOS warm boots are unchanged.
- Added the `cache-cleanup.yml` reusable workflow: on `pull_request:
  closed` it deletes every cache entry on the PR's merge ref, so dead
  archives never push live default-branch caches out of the quota.
  Owner-guarded; skipped for fork PRs (read-only token).

## 2.4.2

- Fixed the `android-emulator` AVD snapshot cache key never carrying the
  emulator version on Linux and macOS. The version was read before the
  snapshot step installed the emulator, so the key was
  `avd-<os>-<arch>-<api>-emunot-installed` on every run: a runner-image
  emulator bump could not roll the key, the incompatible snapshot failed to
  load, the emulator cold-booted (the ~5 min the cache exists to avoid) and
  re-saved under the same key, forever. The version step now installs
  `emulator` + `platform-tools` first (idempotent) and fails loudly if a
  version still cannot be read, instead of keying on a constant.

## 2.4.1

- Fixed the `action-refs` job failing on every run that had no `pinact` changes
  to make — which, since 2.4.0 shipped, has been almost every run. The staging
  loop ended in `[ -n "$f" ] && git add -- "$f"`, so on the blank line an empty
  `PINNED_FILES` contributes, the test is false, `&&` short-circuits to exit 1,
  and that becomes the loop's status. The loop runs inside a pipeline, so under
  `set -e -o pipefail` the step died before it could commit, push, or update the
  PR. The sweep itself had already rewritten the files correctly every time; only
  the staging step fell over. Consumers saw a red daily radar and an action-refs
  PR frozen at whatever commit the last run with pin changes produced.
- Bumped pinned tools: fvm 4.1.2 → 4.3.0, zizmor 1.28.0 → 1.29.0, pinact
  4.1.0 → 4.1.1, Chrome 151 → 152.
- Bumped pinned actions: checkout v7.0.1, labeler v7.0.0, setup-java v5.7.0,
  stale v11.0.0.

## 2.4.0

- The opt-in composite sweep now owns **every** action `uses:` ref, not just the
  composite blind spot — renamed `composite-refs` → `action-refs`. It sweeps
  every whuppi/ci ref (workflows + composites, uniform) to the latest release AND
  pins every third-party action (workflows AND composites) to the latest SHA via
  `pinact`. No more split between Dependabot and a sweep across workflow-vs-composite.
- This leaves Dependabot owning **only pub deps**. Consumers drop the whole
  `github-actions` ecosystem from `dependabot.yml` (not just `whuppi/ci*`), keep
  `sweepActions: true` + `CI_ACTIONS_TOKEN`, and get one PR for all action bumps.
- The label/branch changed with the rename (`upgrade-action-refs` /
  `chore/action-refs`); a consumer on 2.3.0's short-lived `composite-refs` shape
  just re-points its wrapper.

## 2.3.0

- Reverted Renovate (added in 2.2.0). Deleted the reusable `renovate.yml`. The
  self-hosted Renovate machine — a dashboard issue, a per-consumer `renovate.json5`,
  a status-check/token-scope surface — was far more than the one gap that
  actually bit us: composite `action.yml` refs Dependabot can't see
  ([dependabot-core#6704](https://github.com/dependabot/dependabot-core/issues/6704)).
- Closed that gap in the existing radar instead. New opt-in `composite-refs` job
  in the reusable `upgrade-check.yml`: sweeps every whuppi/ci ref across `.github`
  (workflows AND composites) to the latest release — uniform, so the pin never
  splits — and pins third-party actions inside composites to the latest SHA via
  `pinact`. Dependabot keeps pub deps + third-party actions in workflow files;
  the two never overlap. A consumer opts in with `sweepActions: true` +
  `CI_ACTIONS_TOKEN` and adds `whuppi/ci*` to its Dependabot `ignore`.
- Added `pinact` to the pinned tool supply chain (`PINACT_VERSION`), owned by
  `self-upgrade.yml` like actionlint/zizmor.
- Renamed the org secret `RENOVATE_TOKEN` → `CI_ACTIONS_TOKEN` (same
  Workflows-scope PAT; `GITHUB_TOKEN` still can't write `.github/workflows/`).
  `secrets.sh`'s `org` scope stays — it's generic.

## 2.2.0

- Added a reusable `renovate.yml` — self-hosted Renovate that each consumer calls
  from a thin wrapper (same shape as `upgrade-check.yml`), running against the
  calling repo. It reads composite `action.yml`
  ([dependabot-core#6704](https://github.com/dependabot/dependabot-core/issues/6704)
  blind spot), so it keeps whuppi/ci refs uniform and bumps third-party actions
  hidden in composites. Needs a `RENOVATE_TOKEN` org secret (Contents + Workflows +
  Pull-requests + Issues: write) — Renovate must write `.github/workflows/`, which
  `GITHUB_TOKEN` can't.
- `secrets.sh` gained an `org` scope for org-wide secrets (`set org/KEY`).
- Removed the `whuppi-ci-refs` job from `upgrade-check.yml`. Renovate replaces it:
  the sweep needed a Workflows-scope token `GITHUB_TOKEN` couldn't provide, and
  Renovate reads composites natively. Consumers migrate to the `renovate.yml`
  wrapper and drop their Dependabot `github-actions` + `pub` config.

## 2.1.0

- Added a `whuppi-ci-refs` job to the reusable `upgrade-check.yml`. It sweeps
  every `whuppi/ci/…@vX.Y.Z` ref across a consumer's `.github` (workflow files
  and vendored composite `action.yml`s alike) to the latest release, in one
  reviewed PR. Dependabot's github-actions updater never reads `uses:` refs
  inside composite actions
  ([dependabot-core#6704](https://github.com/dependabot/dependabot-core/issues/6704),
  open), so a grouped bump moved only the workflow refs and split the pin, which
  `pin-availability` then rejected. The new job owns that bump and keeps the pin
  uniform by construction. Consumers drop `whuppi/ci*` from their Dependabot
  `github-actions` group.

## 2.0.5

- Bumped the Chrome-for-testing pin to 150.0.7871.115 (with chromedriver),
  sha256s recomputed from the upstream release assets and re-verified by
  `fetch_verified`. The CDN prunes old versions, so consumers on the stale
  pin would start 404ing on web-test downloads.

## 2.0.4

- Fixed `--stamp-changelog` crashing on a package's first-ever release.
  `get_published_versions` piped pub.dev's response straight into jq; for a
  never-published package pub.dev returns 404 with an XML body, jq exits 5,
  and pipefail killed the publish job (device_io's first publish). A 404 now
  means "zero published versions" — the legitimate first-release state —
  while any other non-200 still fails loudly, since treating pub.dev
  downtime as "nothing published" would misfile real published versions
  under the unpublished collapsible.

## 2.0.3

- The 2.0.2 mention escape didn't actually work: GitHub decodes HTML
  entities before scanning release notes for mentions, so `&#64;immutable`
  still credited the `immutable` org as a release contributor. Commit-list
  `@word` tokens are now wrapped in code spans instead — GitHub never
  mention-parses code — which also reads better, since these tokens are
  code annotations in the first place.

## 2.0.2

- Release notes no longer mention-bomb strangers. The auto-generated commits
  collapsible embedded commit subjects verbatim, so a subject containing a
  bare `@word` (`@immutable`, `@override`, ...) became a GitHub mention and
  credited that account as a release contributor — device_io's first release
  listed the `immutable` org. Commit-list `@`s are now escaped as `&#64;`,
  which renders the same and mentions nobody.

## 2.0.1

- Fixed the `release-tool` action swallowing every output release.sh writes.
  The v2.0.0 move from a workspace checkout to a composite action lost the
  output plumbing: composite actions only expose inner-step outputs through an
  explicit `outputs:` mapping, and the action had none. The gate would decide
  `should_run=true`, the caller's `steps.<id>.outputs.should_run` read back
  empty, and every downstream job (discover, git-install-note, publish)
  skipped — a release run that goes green while releasing nothing. The action
  now maps `should_run`, `version`, `tag`, and `has_release` outward.

## 2.0.0

Two gate changes. **MAJOR**: a consumer must update its Makefile to adopt.

- Added `tool/verify_web_gate.sh`, the shared dual-compiler web gate. It compiles
  a consumer's example under both `flutter build web` (dart2js) and `--wasm`
  (dart2wasm). The two compilers have different type models, so js-interop code
  dart2js accepts (a non-exhaustive JSAny switch, an unsound interop cast)
  dart2wasm can reject, and nothing else in the toolchain compiles wasm (the
  analyzer and dart2js use the JS model; pana's wasm tag is an import heuristic).
  A JS-only build is a false green. Registered in `stamped-files.txt`.
- The stamped gates no longer default their SDK/config env vars. A
  `${VAR:-fvm dart}` fallback silently diverges a laptop from CI, so
  `analyze_core`, `platforms_gate`, and `verify_web_gate` now require
  `DART` / `FLUTTER` / `EXPECTED_PLATFORMS` and fail loud if unset. The one
  default lives in the consumer's Makefile, which passes them explicitly.

Adopting: re-stamp all gates, pass `EXPECTED_PLATFORMS` from `make platforms`,
and wire `make verify-web` to the new gate.

## 1.0.8

Hardens the stamp quadrant — the one place local-shared files can drift, and
where this cluster's mistakes came from:

- Added `tool/stamped-files.txt`, the manifest of tool/ gates stamped verbatim
  into consumers (analyze_core, lint_shell, platforms_gate) — the single source
  of truth for "what is stamped", read by the workspace stamper and the guard
  below.
- pr-checks' workflow-lint now fails a consumer PR whose stamped gate drifted
  from the whuppi/ci version it pins. Content drift is caught in CI, not by
  hand. Skipped on whuppi/ci itself (the canonical can't drift from itself). On
  adopting this version a consumer must re-stamp its gates, or the check flags
  the mismatch.
- The three stamped gates now carry one standardized `do not edit` header naming
  the canonical and the re-stamp rule.

## 1.0.7

Additive + internal — a new shared script plus two internal cleanups, no change
to any existing action or workflow contract, so a consumer already pinned gets
a no-op Dependabot bump until it adopts the script:

- Added `tool/platforms_gate.sh`, the shared pub.dev platform-support gate:
  runs pana pinned to `PANA_VERSION` on a lean snapshot and fails if any
  expected platform drops. Packages stamp it into their own `tool/` and call it
  from `make platforms`, so the gate stops being reimplemented per repo.
- `tool/lint_shell.sh` no longer sources `lib.sh` (it used none of its helpers)
  — self-contained now, so it stamps into a package cleanly without dragging
  `lib.sh` along.
- `self-upgrade.yml`: the pin-bump PR body no longer names specific assets
  (which over-claimed when only one moved); it points at the diff instead.

## 1.0.6

Additive — a new shared script, no change to any existing action or workflow
contract, so a consumer already pinned gets a no-op Dependabot bump until it
adopts the script:

- Added `tool/analyze_core.sh`, the shared Dart static-analysis gate: a
  suppression-comment ban plus `dart analyze --fatal-infos` over the package's
  source and its example. Packages stamp it verbatim into their own `tool/`
  and call it from `make analyze`, so analyzer strictness — an INFO like
  `deprecated_member_use` failing the build the same as an error — can never
  drift between consumers again.

## 1.0.5

Internal fix — no change to the caller / Makefile contract, so consumers get a
no-op Dependabot bump. But Windows CI now builds Flutter plugins that ship
Kotlin sources (file_picker, etc.) correctly:

- The `fvm` capability pins `PUB_CACHE` to the workspace drive on Windows
  runners. GitHub checks out on `D:` while pub's default cache sits on `C:`,
  and Kotlin's incremental compiler calls `File.relativeTo` across the two
  drive roots — it throws `this and base files have different roots` and fails
  `assembleDebug` / `assembleRelease` for any plugin carrying Kotlin sources
  (flutter/flutter#105395, #88234, #136160). Pinning the cache to the checkout
  drive gives plugin sources and build output one shared root. The pub-cache
  cache-key path follows the same drive so caching still hits on Windows.

## 1.0.4

Supply-chain pin bump — no change to the caller / Makefile contract, so
consumers get a no-op Dependabot bump:

- Chrome-for-Testing bumped `150.0.7871.24` → `150.0.7871.46` (Chrome's ~4-week
  Stable cadence); the Chrome + ChromeDriver sha256s across Linux/macOS/Windows
  were recomputed and re-verified. Chrome's CDN prunes old versions, so a stale
  pin eventually 404s the download — keeping it fresh keeps the `chrome`
  capability working for every consumer.

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
