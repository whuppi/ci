# Capability Roadmap

What the shared CI covers, what's deliberately consumer-side, and what's
planned. Statuses: **DONE** · **PLANNED** · **WONT_DO** (with reason).

---

## Reusable workflows

| Capability | Status | Notes |
|---|---|---|
| PR quality gates (title, promotion, changelog, workflow+shell lint) | DONE | `pr-checks.yml`; consumer commit-types override wins over the shared list |
| Issue/PR triage (label, assign, revoke ready-to-test, dependabot notice) | DONE | `triage.yml`; owner-guarded privileged jobs |
| Resolved-issue lifecycle | DONE | `auto-close.yml` |
| Label sync to `labels.json` | DONE | `labels.yml` |
| One auto-retry of failed runs | DONE | `retry.yml` |
| Consumer Flutter-SDK + lockfile refresh PRs | DONE | `upgrade-check.yml`; `upgrade-sdk` / `upgrade-locks` labels |
| Package release: gate → discover → git-note → publish | DONE | `release.yml`, built on `release-tool`; no-binary packages only |
| Compile/upload jobs for binary-shipping packages | WONT_DO | Reusable workflows can't interleave caller jobs between callee jobs; a binary shipper authors its own workflow around the same `release-tool` steps (pdf_manipulator is the reference) |

## Composite actions

| Capability | Status | Notes |
|---|---|---|
| make-target orchestrator + capability provisioning | DONE | fvm always; java/chrome/displays/hw-accel/caches/emulator/simulator/free-disk on demand |
| Android emulator with teardown watchdog + JSON reconciler | DONE | `report-json` input, default `test-results/int-android.json` |
| Shared release script runner | DONE | `release-tool` — action-cache execution, Dependabot-bumpable |
| Full-test row gating | DONE | `matrix-filter` |
| SSH debugging tunnel | DONE | `debug-ssh` (bore, key-only) |
| Rust / WASM build capabilities | WONT_DO | Package-specific native machinery stays in the package (pdf_manipulator keeps rust, wasm-build, wasm-cache) |

## Supply chain + release model

| Capability | Status | Notes |
|---|---|---|
| Pinned, sha256-verified tool downloads | DONE | `versions.env` + `fetch_verified.sh`; single-writer `set_kv` |
| Daily pin radar with repoint alarm | DONE | `self-upgrade.yml` |
| Immutable versioned releases with internal-ref stamping | DONE | `self-release.yml` + `self_release.sh`; guarded by self-check |
| Grouped consumer upgrade PRs | DONE | each consumer's Dependabot `whuppi-ci` group (pattern `whuppi/ci*`) |
| Canonical git hooks + commit-types, stamped to consumers | DONE | `hooks/` + the workspace stamp-hooks script |
| Moving major tag (`@v1`) | WONT_DO | A moving tag updates every consumer at once, untested — the exact failure the versioned model exists to prevent |

## Planned

| Capability | Status | Notes |
|---|---|---|
| Shared pana platform-gate | PLANNED | pdf (`tool/platforms.sh`) and device_io (`tool/check_platforms.dart`) implement the same six-platform gate differently; standardize when the next package needs one |
| Org-level `.github` repo for default issue/PR templates | PLANNED | GitHub-native dedup for community-health defaults; per-repo overrides keep working. Needs a new repo — maintainer decision |
| AGENTS.md placeholder data freshness check | PLANNED | The workspace stamper's per-repo data can go stale against a repo's committed AGENTS.md (observed for pdf_manipulator); a drift check would catch it |
