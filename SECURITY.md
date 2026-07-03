# Security Policy

## Reporting a vulnerability

Report privately via [GitHub Security Advisories](https://github.com/whuppi/ci/security/advisories/new). Do not open a public issue.

## What's in scope

This repo IS supply chain — every whuppi package's CI runs code from here. Valid reports:

- **Pinned-binary supply chain** — the capability actions download fvm, Chrome + ChromeDriver, and bore, verified against the sha256 pins in `tool/versions.env` through `tool/fetch_verified.sh` (fail-closed: a missing or mismatched hash refuses the download). A way to run an unverified binary through these paths, or to write `versions.env` outside `set_kv`'s validation, is a valid report.

- **Release stamping integrity** — `self-release.yml` cuts tags from detached stamped commits. A way to make a consumer's pinned `@vX.Y.Z` ref resolve to content other than that stamped commit, or to leak a stamped ref back onto `main`, is a valid report.

- **Privileged reusable workflows** — `triage.yml` and `retry.yml` run under privileged triggers in consumer repos (`pull_request_target`, `workflow_run`). They are hardened to the workflow-security doctrine: no PR checkout, fork-controlled data flows through `env:` only, least-privilege per-job tokens, owner-guarded. A bypass — fork data reaching a shell inline, a write the guards don't cover — is a valid report.

- **Release-tree pollution** — a way to get shared-CI files (a `.whuppi-ci` checkout, action-cache content) into a consumer's stamped release tag or pub.dev tarball.

## What's NOT in scope

- **Compromise of a third-party action we pin** — every third-party action is SHA-pinned and bumped by Dependabot with a 7-day cooldown; a vulnerability in the action itself goes to that action's maintainers.
- **A consumer repo mis-granting permissions in its caller stubs** — caller-side configuration is the consumer's; the reusable jobs declare least privilege regardless.
- **Failures of the gates** (a flaky retry, a missed lint) — bugs, not vulnerabilities. Report as [regular issues](https://github.com/whuppi/ci/issues).

## Operational notes (known, accepted)

Conscious trade-offs, documented so they aren't mistaken for oversights:

- **Some pinned hashes are self-computed, not upstream-published.** fvm and Chrome for Testing publish no digests, so their `versions.env` sha256 pins come from the assets we first downloaded. The pins still catch any later swap (`self-upgrade.yml` re-hashes daily via `verify-pinned`; `self-check.yml` HEADs them on every PR), but the first download defines trust — inherent to the first-to-download problem, not closable without upstream digests.
- **First-party refs are tag-pinned, not SHA-pinned.** `whuppi/ci/*` refs use `@vX.Y.Z` (consumers) / `@main` (internal, stamped at release) under a zizmor `ref-pin` policy. Tags here are cut only by `self-release.yml` from reviewed merges; moving a tag would require write access to this repo, which is the same trust boundary as the SHA.
- **CI runs Chrome with `--no-sandbox` where consumers configure it** — standard for ephemeral CI runners loading only the trusted example app.
- **`debug-ssh` opens an inbound tunnel to a runner.** Key-only auth restricted to the triggering user's GitHub keys, tokens stripped from the session env, ephemeral runner — but do not use it on workflows triggered by untrusted fork PRs (its header says the same).

## Response

Valid reports are fixed and shipped as patch releases; consumers pick them up through their grouped Dependabot PR.
