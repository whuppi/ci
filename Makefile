# Local gates for the whuppi/ci repo itself. CI mirrors these in self-check.yml.
SHELL := /usr/bin/env bash

.PHONY: check hooks lint-shell lint-actions pins-check release

check: lint-shell lint-actions

# Cut a release LOCALLY (the maintainer, from their own machine). The stamp
# commit rewrites @main → @vX.Y.Z inside .github/workflows/, which GitHub
# forbids the CI GITHUB_TOKEN from pushing — so releasing runs here, on the
# maintainer's own credentials, not in a workflow. Detaches HEAD so the stamp
# never lands on main, then returns. Bump CHANGELOG.md's top heading first.
release:
	@current=$$(git branch --show-current); \
	git checkout --detach -q; \
	GITHUB_REPOSITORY=whuppi/ci GH_TOKEN=$$(gh auth token) bash tool/ci/self_release.sh --discover; \
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
