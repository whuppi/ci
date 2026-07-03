# Contributing

Contributions are welcome. Remember the blast radius: every whuppi package's CI
runs what lands here, so changes are reviewed against the consumers, not just
this repo.

---

## Setup

```bash
git clone https://github.com/whuppi/ci.git
cd ci
make hooks     # activates commit-msg + pre-commit (run once)
make check     # the full local gate
```

**Requires:** bash, git, `yq` or python3+PyYAML for the YAML parse. `shellcheck`
and `actionlint` sharpen the local gate when installed; CI enforces them (and
zizmor) regardless.

---

## Before submitting a PR

```bash
make check
```

Runs the shell portability gate (`tool/lint_shell.sh` — shellcheck, bash-3.2
scan, BSD-coreutils scan, workflow-shell check, versions.env single-writer) plus
the workflow/action YAML parse, actionlint, and zizmor. Must pass. Don't
suppress findings — fix the underlying issue.

---

## PR workflow

All PRs target `main` (this repo has no dev/prod chain — consumers pin release
tags, so the tag IS the promotion gate).

```
your branch ──PR──► main
                     ↓ CI: self-check (title, workflow lint, action YAML,
                     ↓      pin availability, internal-refs-are-@main)
                     ↓ PR title: Conventional Commits (feat: / fix: / etc.)
                     ↓ squash-merge when green
                     ↓ a release reaches consumers only when the maintainer
                       cuts one (changelog PR → self-release)
```

Merging to `main` ships nothing by itself — consumers pin `@vX.Y.Z`. That's
deliberate: a bad merge can't break anyone until a release is cut, and each
consumer adopts the release through its own tested Dependabot PR.

---

## The rules that will fail your PR

- **Internal refs say `@main`, never a version tag** — `self-release.yml`
  stamps them at release; `self-check.yml` rejects hand-written tags.
- **Every `run:` step is bash** (per-step `shell: bash` or workflow defaults);
  bash 3.2 + BSD-portable per `tool/lint_shell.sh`'s header.
- **Untrusted event data flows through `env:`**, never interpolated `${{ }}`
  inside `run:` blocks.
- **Third-party actions are SHA-pinned** with a version comment; only
  `whuppi/ci/*` refs may use tag/branch refs (zizmor `ref-pin` policy).
- **`tool/versions.env` is written only by `set_kv`** in `tool/ci/upgrade.sh` —
  it's a sourced file; an unvalidated write executes.

---

## Where things go

- New capability → `actions/capabilities/<name>/action.yml`, wired into
  `make-target` as an `if:`-gated call. Recipes in
  [`docs/UPDATING.md`](docs/UPDATING.md).
- New reusable workflow → `.github/workflows/`, `workflow_call` only —
  consumers own triggers and concurrency.
- Hook or commit-types change → `hooks/` / `tool/commit-types.txt` (the
  canonical copies), then the workspace stamp script updates every consumer.

---

## Releases

Handled by the maintainer: a PR adding a new top heading to `CHANGELOG.md`;
`self-release.yml` stamps, tags, and publishes the release. Never hand-tag.
Details in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
