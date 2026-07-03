<!--
============================================================================
AUTO-GENERATED — DO NOT EDIT
============================================================================
This file is rendered by:
  /Users/deepanshu/personal1/whuppi/.claude/scripts/stamp-agents.sh
from:
  /Users/deepanshu/personal1/whuppi/AGENTS.template.md
  with per-repo data inlined in the stamper itself.

To change content:
  - Workspace-wide: edit AGENTS.template.md, then re-run the stamper.
  - One repo only:  edit the `repo_data` case for "ci" in stamp-agents.sh,
                    then re-run the stamper.
Manual edits to this file will be overwritten on the next stamp.
============================================================================
-->

# ci

> **Public AI agent contract** for ci — read by Cursor, OpenAI Codex, Aider, Devin, JetBrains Junie, and any AI tool that follows the [agents.md](https://agents.md) convention.
>
> Claude Code reads the deeper workspace config at `whuppi/.claude/rules/` and `whuppi/.claude/memory/` automatically — this AGENTS.md exists for every *other* AI tool.
>
> Stamped from `whuppi/AGENTS.template.md`. Per-repo content lives in the placeholder sections; everything else is identical workspace-wide.

---

## What this tool does

**whuppi/ci** is the shared CI for whuppi's Flutter/Dart package repos: reusable workflows (consumers own thin caller stubs with the triggers; the jobs live here), composite actions (`make-target` provisions capabilities and runs a Makefile target; `release-tool` runs the shared release script from the action cache; `matrix-filter`, `debug-ssh`), and a pinned, sha256-verified tool supply chain (`tool/versions.env` + `tool/fetch_verified.sh`). Releases are immutable version tags cut from `CHANGELOG.md` by `self-release.yml`, which stamps every internal `@main` ref to the release tag in a detached commit — consumers pin exact versions and upgrade through grouped Dependabot PRs tested by their own CI.

This repo is one tool inside the **whuppi** workspace — a multi-tool monorepo. The workspace ships shared engineering standards, code conventions, brand identity, and build patterns that apply across every tool. They're documented in three layers:

- **Repo-specific architecture, design, reference:** `./docs/`
- **Workspace human-readable standards:** `../docs/` (when this repo is cloned as part of the whuppi workspace) — engineering principles, decision frameworks, secret/CI patterns
- **Workspace AI-only directives:** `../.claude/rules/` (Claude Code reads these automatically; other AI tools can read them as supplementary context)

If you're working on this tool standalone (cloned outside the workspace), the in-repo `./docs/` is your authority; ignore the workspace pointers.

---

## Build and test commands

Run these after every code change. A failing test or analyzer error means the task is not done — don't suppress with `// ignore:`, `# noqa`, or `--no-verify`. Fix the underlying issue.

```bash
# Setup
make hooks        # activate git hooks (once after cloning)
make check        # shell portability gate + workflow/action YAML parse + actionlint + zizmor

# Individual gates
make lint-shell   # shellcheck + bash-3.2 + BSD-portability scans (tool/lint_shell.sh)
make lint-actions # YAML parse + actionlint + zizmor (auditor persona)
make pins-check   # HEAD every pinned asset — flags a pruned pin before it breaks a build
```

---

## Code style

Match the style of existing code in this repo first. Workspace-wide standards live at:

- **Engineering standards** (seven questions before every decision, env-blind code, twelve-factor checklist): `../docs/universal/development-standards.md`
- **Secrets and environments** (GitHub Environments, branch=env, security walls, files-not-env-vars): `../docs/universal/secrets-and-environments.md`
- **Python tools** (SDK/CLI/MCP three-layer pattern, ruff config, hatchling): `../.claude/rules/python-shared/sdk-cli-mcp-pattern.md`
- **Flutter packages** (opaque boundaries, async at edges, dependency flow): `../.claude/rules/flutter-shared/package-design.md`
- **Comments and doc-comments** (what earns a comment, what doesn't): `../.claude/rules/universal/comments.md`
- **Renaming anything** (sweep all references in one session): `../.claude/rules/universal/rename-hygiene.md`

When in doubt, read existing code in this repo and match it. Per-repo style consistency beats general-best-practice consistency.

---

## Tool-specific notes

**Internal refs on `main` say `@main` — never a version tag.** `self-release.yml` stamps them to the exact tag in a detached release commit; a hand-written tag would freeze internals at an old release. `self-check.yml`'s internal-refs-are-main job fails the PR if you do it.

**Never hand-tag `main`.** Releases are cut by merging a changelog PR (new top heading in `CHANGELOG.md`); the tag must point at the stamped detached commit.

**Composite actions read repo files via `$GITHUB_ACTION_PATH`**, never the consumer workspace — capabilities are three levels up from the root, `debug-ssh`/`release-tool` two. `make-target` and `matrix-filter` read no repo files.

**Every downloaded binary goes through `tool/fetch_verified.sh`** (fail-closed sha256), pinned in `tool/versions.env`, whose ONLY writer is `set_kv` in `tool/ci/upgrade.sh` (lint-enforced). Consumers' Flutter SDK + lockfiles are theirs (reusable upgrade-check bumps them); the tool pins here are bumped by `self-upgrade.yml`.

**The canonical git hooks live in `hooks/`** and are stamped into consumer repos by the workspace's `stamp-hooks.sh` — edit them here, restamp everywhere. Same for `tool/commit-types.txt`.

**Docs:** `docs/ARCHITECTURE.md` (consumption, stamping, release model, first-push runbook), `docs/UPDATING.md` (maintenance recipes), `docs/CAPABILITY_ROADMAP.md` (shared vs consumer-side, planned), `docs/MIGRATION.md` (consumer onboarding + majors).

---

## Data, secrets, and gitignore

This repo's `.gitignore` is stamped from `../.gitignore.template` (workspace canonical). It already covers:

- `data/.env` and every other `.env` flavor (only `.env.example` / `.env.template` / `.env.sample` are committed)
- `data/auth/` (captured tokens, cookies, OAuth credentials)
- `data/db/*.sqlite*` (full app state — irreplaceable)
- `cookies*.json`, `*.token`, `*.pem`, `*.key`
- `output/`, `debug/`, `logs/`, `cache/`

Never commit a sensitive file even if it's somehow not gitignored — surface to the maintainer instead. The gitignore is defense-in-depth, not the only check.

---

## Working with AI agents

- **Run the test suite before claiming completion.** Always.
- **Don't add `TODO` comments as a substitute for fixing things.** If you found it, you own it — fix in this pass or surface to the maintainer.
- **Don't add backwards-compat shims** for code that hasn't shipped. Code assumes the latest schema and contracts; migrations handle old data once.
- **Don't refactor "for cleanliness" without a stated reason.** Surface the suggestion before changing surrounding code.
- **No co-authored-by AI in commits.** The maintainer is the author.
- **Never force-push protected branches** (`prod`, `main`, `dev`). Never skip pre-commit hooks.

For the engineering philosophy that informs every line of code in this workspace, see `../.claude/rules/universal/dc-engineering-philosophy.md` if available.

---

*This file is stamped from `whuppi/AGENTS.template.md`. The placeholder sections (`{{...}}`) are the only parts customized per repo. Re-stamping refreshes the shared content; per-repo placeholders are preserved.*
