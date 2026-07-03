# Local gates for the whuppi/ci repo itself. CI mirrors these in self-check.yml.
SHELL := /usr/bin/env bash

.PHONY: check hooks lint-shell lint-actions pins-check release

check: lint-shell lint-actions

# Cut a release LOCALLY (manual fallback — self-release.yml is the normal
# path). Runs the SAME shared tool/ci/release.sh the workflow runs; the
# internal-ref stamp is the release_stamp_tree hook in tool/ci/release_hooks.sh.
# Uses your own credentials (they carry the workflows scope the stamped push
# needs). Detaches HEAD so the stamp never lands on main, then returns.
# Run from an up-to-date main after merging the changelog PR.
release:
	@[ -z "$$(git status --porcelain)" ] || { echo "working tree not clean — commit or stash first"; exit 1; }
	@current=$$(git branch --show-current); \
	git checkout --detach -q; \
	GITHUB_REPOSITORY=whuppi/ci GH_TOKEN=$$(gh auth token) BRANCH=main bash tool/ci/release.sh --discover; \
	rc=$$?; git checkout -q "$$current"; exit $$rc

# This repo uses its own canonical hooks directly (the same files stamped into
# every consumer's .githooks/). Run once after cloning. Idempotent.
hooks:
	@git config core.hooksPath hooks
	@echo "✓ git hooks active (core.hooksPath → hooks)"

# Shell portability + correctness (shellcheck + bash 3.2 + BSD scans).
lint-shell:
	bash tool/lint_shell.sh

# Workflow + composite-action YAML parse, then actionlint + zizmor if present.
# Each external tool degrades to a note when missing — CI enforces the full set.
lint-actions:
	@files=$$(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml'); \
	if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then \
	  python3 -c 'import sys, yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]; print("YAML parse: OK (%d files)" % (len(sys.argv)-1))' $$files; \
	elif command -v yq >/dev/null 2>&1; then \
	  for f in $$files; do yq -e '.' "$$f" >/dev/null || exit 1; done; echo "YAML parse: OK (yq)"; \
	else \
	  echo "no python3+yaml or yq — CI enforces the YAML parse"; \
	fi
	@command -v actionlint >/dev/null 2>&1 && { actionlint -color && echo "actionlint: OK"; } || echo "actionlint not installed — CI enforces it"
	@if command -v pipx >/dev/null 2>&1; then source tool/versions.env && pipx run "zizmor==$$ZIZMOR_VERSION" --persona=auditor .github/ actions/; else echo "pipx/zizmor not installed — CI enforces it"; fi

# HEAD every pinned asset — flags a pruned pin before it breaks a build.
pins-check:
	bash tool/ci/upgrade.sh check-availability
