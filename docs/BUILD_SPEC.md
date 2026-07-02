# BUILD SPEC — `whuppi/ci` shared CI repo + device_io as first consumer

> Implementation spec for a worker model. Everything needed to finish this build
> is in this file plus the referenced source files. Read the whole spec before
> writing anything. When this spec and a source file disagree about a mechanical
> detail (a SHA pin, an option name), the source file wins — copy from source,
> don't retype from memory.

---

## 0. Context, constraints, and the prime directives

**Goal.** Build `whuppi/ci` — a shared GitHub Actions repo (reusable workflows +
composite actions + CI shell tooling) generalized from
`/Users/deepanshu/personal1/whuppi/pdf_manipulator`'s battle-tested CI — then wire
`/Users/deepanshu/personal1/whuppi/device_io` as its first consumer.

**Hard constraints (violating any of these is failure):**

1. **NEVER push anything to GitHub.** No `git push`, no `gh repo create`, no remote
   configuration. Both repos are built and committed locally only.
2. **Do NOT modify `/Users/deepanshu/personal1/whuppi/pdf_manipulator`** in any way.
   It is the read-only reference. It migrates to whuppi/ci later, separately.
3. **No TODOs, no placeholder comments, no empty stubs, no "for now" hacks.** Every
   file you write must be complete and correct. If something can't be finished,
   say so explicitly in your final report instead of leaving a marker.
4. **Commit in logical chunks with Conventional Commit messages** (`feat:`, `fix:`,
   `ci:`, `docs:`, `chore:`). The `whuppi/ci` repo and `device_io` are separate git
   repos — commit each in its own repo.
5. The workspace repo at `/Users/deepanshu/personal1/whuppi` is a PRIVATE workspace.
   `device_io` and `ci` are their own nested git repos, not tracked files of it.
   Never `git add` from the workspace root.
6. Shell code must pass `tool/lint_shell.sh` (bash 3.2 compatible, BSD-portable,
   shellcheck-clean). Read that script's header — it documents every rule it
   enforces. Notably: no `sed -i` without a suffix, no `mapfile`, no `${var^^}`,
   no GNU-only flags, digests computed from stdin not path args, `versions.env`
   written ONLY through `set_kv`.
7. Every `run:` step in every workflow you write must be bash (`shell: bash` on the
   step or `defaults.run.shell: bash` on the workflow) — lint_shell check 3.
8. Untrusted event data (PR titles, branch names, comment bodies) flows into
   scripts through `env:`, never interpolated `${{ }}` inside `run:` blocks. Every
   source workflow already does this — preserve the pattern when adapting.
9. All third-party actions are SHA-pinned with a `# vX.Y.Z` comment. Reuse the
   exact pins already present in the pdf_manipulator source files. Do not bump.

**Current state (already done — verify, don't redo):**

`/Users/deepanshu/personal1/whuppi/ci` exists, `git init`'d on branch `main`, zero
commits yet, with these files copied verbatim from pdf_manipulator:

```
.github/actionlint.yaml            ← verbatim, keep as-is
.gitignore                         ← stamped from whuppi/.gitignore.template, keep
LICENSE                            ← copied; verify it's MIT; keep
actions/capabilities/{java,gradle-cache,pods-cache,headless-display,hw-accel,ios-simulator}/action.yml
                                   ← verbatim, KEEP AS-IS (they are fully generic)
actions/capabilities/{fvm,chrome,xcode-cache,android-emulator,free-disk-space}/action.yml
                                   ← copied, NEED THE EDITS in §3
actions/make-target/action.yml     ← copied, NEEDS THE REWRITE in §3.6
actions/debug-ssh/action.yml       ← copied, NEEDS THE EDITS in §3.5
tool/fetch_verified.sh             ← verbatim, keep as-is
tool/lint_shell.sh                 ← copied, NEEDS THE EDIT in §3.9
tool/commit-types.txt              ← verbatim, keep as-is
tool/ci/reconcile_test_json.sh     ← copied; read it; it is generic apart from
                                     comments — keep as-is unless a comment names
                                     pdf_manipulator, in which case genericize the
                                     comment text only
tool/ci/release.sh                 ← copied, NEEDS THE EDITS in §3.7
tool/lib.sh                        ← copied, NEEDS THE TRIM in §3.8
```

Source repo for everything: `/Users/deepanshu/personal1/whuppi/pdf_manipulator`
(referred to below as `$SRC`). Consumer: `/Users/deepanshu/personal1/whuppi/device_io`
(referred to as `$DIO`).

---

## 1. The design in one page

**Consumption model.** Consumers call `whuppi/ci` two ways:

- **Reusable workflows** — consumer `.github/workflows/*.yml` files are thin
  callers: they own the `on:` triggers, the concurrency group, and any
  privileged-trigger `zizmor: ignore` comments; the shared repo owns the jobs.
  `uses: whuppi/ci/.github/workflows/<name>.yml@v1.0.0` — exact pins, see the
  version contract below.
- **Composite actions** — consumer-authored workflows (the repo-specific `ci.yml`
  and `full-test.yml`) use `whuppi/ci/actions/make-target@v1.0.0`, which provisions
  capabilities and runs a Makefile target. The Makefile stays the single source
  of truth for what CI actually runs — same commands locally and in CI.

**Version contract — exact-version pinning, PR-tested upgrades.** whuppi/ci
cuts real, immutable releases (`v1.0.0`, `v1.1.0`, …) from its own
`CHANGELOG.md`, the same changelog-driven model the packages use. There is NO
moving major tag — a moving tag changes under every consumer at once, which is
exactly the breakage this design exists to prevent. Consumers pin an exact
version everywhere (`whuppi/ci/...@v1.0.0`) and upgrade individually:
Dependabot's github-actions ecosystem detects a new whuppi/ci release, opens a
PR in each consumer bumping the pin, and that PR runs the consumer's own CI —
the fast gate automatically, the full cross-target matrix via `ready-to-test`
— before anyone merges. A Dependabot **group** in each consumer bundles every
`whuppi/ci` ref into ONE bump PR, so make-target, capabilities, and reusable
workflows can never sit at mixed versions inside one repo.

**Internal-ref self-consistency (the stamping rule).** whuppi/ci's own
cross-references — make-target → capability actions, reusable workflows →
their `checkout whuppi/ci` tools step — must always resolve to the SAME
version the consumer pinned. Mechanism: on `main`, every internal ref says
`@main` (and `ref: main`), so the repo is self-consistent for anyone consuming
`@main` and for its own PR checks. At release time, `self-release.yml` (§4.10)
stamps every internal `@main` → `@vX.Y.Z` in a release commit, tags THAT
commit, and main never sees the stamp — so a consumer calling any file
`@v1.2.0` gets internal refs that also say `v1.2.0`, byte-for-byte. This is
the same stamped-tag-commit pattern pdf_manipulator's release.sh `--discover`
already uses for version stamping. Nothing resolves until the repo is pushed —
expected; nothing in this build runs CI.

**Pins ownership split.**

| Pin | Lives in | Bumped by |
|---|---|---|
| fvm tool, Chrome+driver, actionlint, zizmor, bore (+ every sha256) | `ci/tool/versions.env` | ci's own `self-upgrade.yml` (daily PR **in the ci repo**) — one bump updates every consumer |
| Flutter SDK (`.fvmrc`, `example/.fvmrc`) | consumer repo | reusable `upgrade-check.yml` (daily PR in the consumer repo) |
| pubspec.lock files | consumer repo | reusable `upgrade-check.yml` |
| pub deps + action SHAs | consumer repo | Dependabot |

**Script access.** Composite actions read their own repo's files via
`$GITHUB_ACTION_PATH` (GitHub materializes the whole action repo on the runner).
Reusable-workflow jobs that need `tool/` scripts check out `whuppi/ci` to the
fixed path `.whuppi-ci/` beside the consumer checkout.

**Repo guard.** Privileged workflows (triage, retry, labels) generalize
pdf_manipulator's `github.repository == 'whuppi/pdf_manipulator'` guard to
`github.repository_owner == 'whuppi'` — blocks forks, works for every whuppi repo.

**ci repo branch model.** `main` + version tags only — no dev/prod promotion
chain. Rationale: consumers pin tags, never branches, so a promotion chain
guards nothing here. This is a documented deviation from
`whuppi/docs/universal/repo-setup.md` §2; note it in the ci README.

**What deliberately does NOT move into whuppi/ci** (pdf_manipulator-specific;
it keeps its own until it migrates): `rust`, `wasm-build`, `wasm-cache`
capabilities; `compile_rust.sh`, `analyze.sh`, `run_web_test.sh`,
`generate_fixtures.dart`, `platforms.sh`, `check_alignment.sh`; the binaryen
pins; the create-release compile/upload-assets jobs; `build.json`.

---

## 2. Target layout of `whuppi/ci`

```
ci/
├── README.md                          ← §5.1
├── LICENSE                            ← already present
├── .gitignore                         ← already present
├── Makefile                           ← §5.2 (local gates: make check)
├── CHANGELOG.md                       ← §5.4 (drives self-release versions)
├── .github/
│   ├── actionlint.yaml                ← already present
│   ├── dependabot.yml                 ← §5.3
│   └── workflows/
│       ├── pr-checks.yml              ← reusable  (§4.1)
│       ├── triage.yml                 ← reusable  (§4.2)
│       ├── auto-close.yml             ← reusable  (§4.3)
│       ├── labels.yml                 ← reusable  (§4.4)
│       ├── retry.yml                  ← reusable  (§4.5)
│       ├── upgrade-check.yml          ← reusable  (§4.6)
│       ├── release.yml                ← reusable  (§4.7)
│       ├── self-check.yml             ← ci's own PR gate      (§4.8)
│       ├── self-upgrade.yml           ← ci's own pin radar    (§4.9)
│       └── self-release.yml           ← ci's own release cut  (§4.10)
├── actions/
│   ├── make-target/action.yml         ← §3.6
│   ├── debug-ssh/action.yml           ← §3.5
│   └── capabilities/
│       ├── fvm/            ← §3.1     ├── chrome/          ← §3.2
│       ├── xcode-cache/    ← §3.3     ├── android-emulator/← §3.4
│       ├── free-disk-space/← §3.10    └── java/ gradle-cache/ pods-cache/
│                                          headless-display/ hw-accel/
│                                          ios-simulator/   ← keep verbatim
├── tool/
│   ├── versions.env                   ← §3.11 (new)
│   ├── fetch_verified.sh              ← keep verbatim
│   ├── lib.sh                         ← §3.8
│   ├── lint_shell.sh                  ← §3.9
│   ├── commit-types.txt               ← keep verbatim
│   └── ci/
│       ├── release.sh                 ← §3.7
│       ├── upgrade.sh                 ← §3.12 (new, derived from $SRC)
│       ├── self_release.sh            ← §3.13 (new — this repo's release cut)
│       └── reconcile_test_json.sh     ← keep (genericize comments only)
└── docs/
    ├── BUILD_SPEC.md                  ← this file (keep; it is the build record)
    └── ARCHITECTURE.md                ← §5.5
```

---

## 3. Part A — file edits in `whuppi/ci`

General rule for every action edit: composite actions can reference their own
repo's files via the `GITHUB_ACTION_PATH` environment variable (set for the
duration of each step of that action). Depth math:

- `actions/capabilities/<name>/action.yml` → repo root is
  `"$GITHUB_ACTION_PATH/../../.."`
- `actions/make-target/action.yml`, `actions/debug-ssh/action.yml` → repo root is
  `"$GITHUB_ACTION_PATH/../.."`

Convention: at the top of each `run:` block that needs it, set
`CI_ROOT="$GITHUB_ACTION_PATH/../../.."` (or `../..`) and use
`source "$CI_ROOT/tool/versions.env"` / `bash "$CI_ROOT/tool/fetch_verified.sh" …`.
Always quote — the path contains runner-generated segments.

### 3.1 `actions/capabilities/fvm/action.yml`

- In the `Install FVM + project SDK` step, replace `source tool/versions.env`
  with the `CI_ROOT` pattern above, and both `bash tool/fetch_verified.sh`
  occurrences with `bash "$CI_ROOT/tool/fetch_verified.sh"`.
- Update the description line "Version + per-platform sha256 live in
  tool/versions.env" to say they live in **this repo's** `tool/versions.env`.
- The two `actions/cache` steps use `hashFiles('pubspec.yaml', 'example/pubspec.yaml')`
  and `hashFiles('.fvmrc')` — these evaluate against the CONSUMER workspace,
  which is correct. Leave them.

### 3.2 `actions/capabilities/chrome/action.yml`

Same conversion in all three OS steps (`source tool/versions.env` → CI_ROOT
pattern; every `bash tool/fetch_verified.sh` → `"$CI_ROOT/tool/fetch_verified.sh"`).
Update the description's "live in tool/versions.env" sentence the same way.

### 3.3 `actions/capabilities/xcode-cache/action.yml`

The cache key references `${{ env.SUBMODULE_PDF_OXIDE }}` (a pdf_manipulator
env). Replace with an optional input:

```yaml
inputs:
  target:
    description: "ios or macos — used in cache key"
    required: true
  key-extra:
    description: "Optional extra cache-key segment (e.g. a dependency revision)"
    required: false
    default: ''
```

and key `xcode-${{ runner.os }}-${{ runner.arch }}-${{ inputs.target }}-${{ inputs.key-extra }}`
with the same restore-keys prefix as the source (without the extra segment).

### 3.4 `actions/capabilities/android-emulator/action.yml`

Two changes:

1. New input:

   ```yaml
     report-json:
       description: "Machine JSON test report the reconciler reads (workspace-relative)"
       required: false
       default: 'test-results/int-android.json'
   ```

2. The teardown-watchdog heredoc (`<< 'EMUSCRIPT'`) is single-quoted, so nothing
   expands at write time. The reconciler line inside it currently reads:

   ```bash
   bash "$WS/tool/ci/reconcile_test_json.sh" "$WS/test-results/int-android.json" "$OUT"
   ```

   Replace it inside the heredoc with placeholders:

   ```bash
   bash "__CI_TOOL_DIR__/reconcile_test_json.sh" "$WS/__REPORT_JSON__" "$OUT"
   ```

   and immediately after the heredoc's `chmod +x`, substitute them at
   action-execution time (this runs in OUR composite step, where
   `GITHUB_ACTION_PATH` points at this action):

   ```bash
   sed -i.bak \
     -e "s|__CI_TOOL_DIR__|$GITHUB_ACTION_PATH/../../../tool/ci|" \
     -e "s|__REPORT_JSON__|$INPUTS_REPORT_JSON|" \
     /tmp/emulator-run.sh && rm -f /tmp/emulator-run.sh.bak
   ```

   with `INPUTS_REPORT_JSON: ${{ inputs.report-json }}` added to that step's
   `env:`. (`sed -i.bak` — never bare `-i` — per lint_shell.) Note the watchdog
   step runs only on Linux/macOS (`if: runner.os != 'Windows'`) so the sed
   stays in that same step.

Header comments are already generic — leave them.

### 3.5 `actions/debug-ssh/action.yml`

In all three OS steps, apply the CI_ROOT pattern (root depth `../..` here):
`source tool/versions.env` → `source "$CI_ROOT/tool/versions.env"`, and the
three `bash tool/fetch_verified.sh` → `bash "$CI_ROOT/tool/fetch_verified.sh"`.
Also update the header's usage example: `uses: ./.github/actions/debug-ssh` →
`uses: whuppi/ci/actions/debug-ssh@v1.0.0` and
`uses: ./.github/actions/make-target` → `uses: whuppi/ci/actions/make-target@v1.0.0`
(consumer-facing examples always show an exact pin).

### 3.6 `actions/make-target/action.yml` — the orchestrator rewrite

Start from the copy and:

1. **Delete** the `rust`, `free-disk` → keep `free-disk` (generic; useful for any
   build-heavy job) — delete only `rust`, `wasm-cache`, `wasm-build` inputs and
   their steps.
2. **Add** two passthrough inputs: `xcode-key-extra` (default `''`, forwarded to
   xcode-cache's `key-extra`) and `report-json` (default
   `'test-results/int-android.json'`, forwarded to android-emulator).
3. **Convert every sibling reference** from
   `uses: ./.github/actions/capabilities/<x>` to
   `uses: whuppi/ci/actions/capabilities/<x>@main`. Same for the
   android-emulator step at the bottom. (`@main` is the on-main convention;
   `self-release.yml` stamps these to the exact tag in every release commit —
   see §1 "Internal-ref self-consistency" and §3.13.)
4. Update the header comment: remove the rust/wasm sentence, add two lines
   stating (a) internal refs say `@main` on main and get stamped to the release
   tag at release time, so they can never skew from the version the consumer
   pinned, and (b) never hand-write a version tag into an internal ref.
5. Keep the `/tmp/make-run.sh` compose step, the direct path, the emulator path,
   and the gradle-cache save step exactly as in the source — they are the core
   contract (doctor + make authored once, no drift between direct and emulator
   paths).

### 3.7 `tool/ci/release.sh` — generalization

Read the whole file first. It is 1030 lines; the edits are surgical. Everything
not listed here stays byte-identical.

1. **Header (lines ~1–49):** update the mode list comment — the "Tree stamping"
   parenthetical becomes "version bump + generic submodule de-registration";
   remove the sentence about "raw vendor source". Update "Pipeline flow" to note
   compile/upload are consumer-side jobs that pure-Dart packages skip.
2. **Line ~64–69:**
   ```bash
   source "$SCRIPT_DIR/../lib.sh"
   ensure_jq
   REPO="${GITHUB_REPOSITORY:-$(json_get '.repo')}"
   REPO_URL="https://github.com/$REPO"
   PKG_NAME="pdf_manipulator"
   ```
   becomes:
   ```bash
   source "$SCRIPT_DIR/../lib.sh"
   ensure_jq

   # The consumer package is the CURRENT WORKING DIRECTORY; this script lives in
   # the whuppi/ci checkout. Identity comes from the environment + the pubspec.
   REPO="${GITHUB_REPOSITORY:?release.sh requires GITHUB_REPOSITORY (owner/repo)}"
   REPO_URL="https://github.com/$REPO"
   PKG_NAME="$(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml | head -1)"
   [ -n "$PKG_NAME" ] || { echo "::error::no 'name:' in pubspec.yaml — run from the package root" >&2; exit 1; }
   ```
   For local dry runs, callers export `GITHUB_REPOSITORY` themselves — document
   that in the usage() text (add one line).
3. **`stamp_version` (~line 184):** make the `lib/src/version.dart` sed
   conditional: `if [ -f lib/src/version.dart ]; then … fi` (some packages
   won't carry the constant). pubspec + README seds stay unconditional (the
   README seds already no-op harmlessly when the patterns are absent).
4. **`stamp_asset_hashes` (~lines 200–280):** generalize:
   - At the top, add: `[ -f "$hash_file" ] || { echo "  no $hash_file — nothing to stamp"; return 1; }`
   - **Delete the entire "Hand-written web assets" block** (the `web_entries`
     loop and its `build.json` process substitution) and the `web_entries`
     variable — that is pdf_manipulator-specific. `all_entries` becomes just the
     release-API entries.
   - Everything else (Release-API digest loop, marker-replace awk) stays.
5. **`cmd_discover` (~lines 619–649):** replace the hardcoded
   `for sub in vendor/pdf_oxide vendor/office_oxide` block AND the
   `false_secrets /vendor/**` block with a generic sweep driven by
   `.gitmodules` (no-op when the file is absent):
   ```bash
   # De-register every submodule so the tag is self-contained raw source —
   # `git: ref:` consumers can't fetch submodules through pub.
   if [ -f .gitmodules ]; then
     local sub
     while IFS= read -r sub; do
       [ -n "$sub" ] || continue
       if [ -d "$sub/.git" ] || [ -f "$sub/.git" ]; then
         git rm --cached "$sub" 2>/dev/null || true
         rm -rf "$sub/.git"
         git add --force "$sub/"
         echo "  $sub → raw source (de-registered submodule)"
       fi
       # Vendored source trips pub's secret scanner on upstream test fixtures.
       if ! grep -qF "  - /$sub/**" pubspec.yaml; then
         if grep -q '^false_secrets:' pubspec.yaml; then
           fs_path="/$sub/**" awk '/^false_secrets:/{print; print "  - " ENVIRON["fs_path"]; next} 1' \
             pubspec.yaml > pubspec.yaml.tmp
         else
           { cat pubspec.yaml; printf 'false_secrets:\n  - /%s/**\n' "$sub"; } > pubspec.yaml.tmp
         fi
         mv pubspec.yaml.tmp pubspec.yaml
         echo "  pubspec.yaml += false_secrets /$sub/**"
       fi
     done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

     git rm --cached .gitmodules 2>/dev/null || true
     rm -f .gitmodules
     echo "  .gitmodules removed"
   fi
   ```
   (Value flows through `ENVIRON`, matching the repo's awk-injection discipline.)
6. `--stamp-readme`, `--stamp-changelog`, `--check-versions`, `--gate`,
   `--github-notes`, `--update-tag-hashes`, `--add-git-install`,
   `--add-pub-install`, both changelog builders, and all helpers: **unchanged.**

### 3.8 `tool/lib.sh` — trim

Keep: `require_present`, `ensure_jq`, `sha256_file`, `json_get`.
Delete: `ensure_target`, `provide_tool`, `latest_version_subdir` (rust/NDK
helpers with no caller in this repo).
`json_get`: remove the `build.json` default — the file argument becomes
required: `local expr="$1" file="${2:?json_get requires a file argument}"`.
Update the header comment ("Requires: PKG_ROOT…" sentence goes away).

### 3.9 `tool/lint_shell.sh` — lint the caller's tree, not this repo's

The script currently does `ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"`,
which would always lint the whuppi/ci checkout. Change to:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tool/lib.sh
source "$SCRIPT_DIR/lib.sh"
# Lints the git repo at the CURRENT DIRECTORY — cd to the repo to lint first.
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "lint_shell: run inside a git repo" >&2; exit 2; }
```

(and delete the old ROOT/cd/source lines). Everything below already operates on
`git ls-files` relative to CWD — no other change. Update the header's first
sentence to say it lints the current repo and is invoked both by `make check`
in whuppi/ci (linting itself) and by the reusable pr-checks workflow (linting
the consumer).

### 3.10 `actions/capabilities/free-disk-space/action.yml`

Genericize the two comments only: the description's "vendored-engine cargo
test" sentence → "build-heavy jobs that overrun a stock runner's ~14 GB free";
the `tool-cache: false` comment → "Keep the hosted tool cache: capabilities may
install tools there before this step runs"; keep the `swap-storage: false`
comment as-is minus the rust-lld mention (say "parallel linkers lean on the
4 GB swapfile"). No functional change.

### 3.11 `tool/versions.env` — new file

Derive from `$SRC/tool/versions.env`: copy it, then **delete** the
`BINARYEN_VERSION` + all `BINARYEN_SHA256_*` entries and the `PANA_VERSION`
entry (pana is consumer-owned — device_io's Makefile manages its own). Keep,
with their comments updated to name the whuppi/ci consumer file:

- `FVM_VERSION` + 4 `FVM_SHA256_*` — consumed by `actions/capabilities/fvm`
- `ACTIONLINT_VERSION` — consumed by the reusable `pr-checks.yml`
- `ZIZMOR_VERSION` — consumed by the reusable `pr-checks.yml`
- `BORE_VERSION` + 3 `BORE_SHA256_*` — consumed by `actions/debug-ssh`
- `CHROME_VERSION` + 6 `CHROME*_SHA256_*` — consumed by `actions/capabilities/chrome`

Rewrite the header: who bumps what is now — `tool/ci/upgrade.sh` via
`self-upgrade.yml` (everything in this file); Dependabot (action SHAs);
consumer repos own their Flutter SDK + lockfiles via the reusable
`upgrade-check.yml`. Keep the "sourced by scripts, bump in ONE place" and
"plain KEY=value" sentences.

### 3.12 `tool/ci/upgrade.sh` — new file, derived from `$SRC/tool/ci/upgrade.sh`

Copy the source, then:

1. **Delete** the Flutter-SDK section (lines ~175–194 — `.fvmrc` bumping moves
   to the reusable consumer workflow, §4.6), the binaryen section (~246–268),
   and the pana section (~236–244).
2. **Delete** the binaryen entries from `asset_urls()`.
3. Rewrite the header comment: watched here = fvm, Chrome, bore, zizmor,
   actionlint (this repo's `versions.env`); owned elsewhere = consumer Flutter
   SDK + lockfiles (reusable upgrade-check), action SHAs (Dependabot).
4. Everything else (set_kv, sha256_of, verify_pinned, check-availability, the
   fvm/zizmor/actionlint/bore/chrome bump blocks, the drift/blocked exit logic)
   stays byte-identical.

### 3.13 `tool/ci/self_release.sh` — new file (~120 lines): this repo's release cut

Modeled on release.sh's `--gate`/`--discover` shape (reuse its idioms:
`gh_output`, `git_ci_identity`-equivalent, `valid_semver`, `extract_entry`,
`get_changelog_versions` — source `lib.sh` and copy the small helpers you need
from release.sh rather than sourcing release.sh, which is package-oriented).
Single lane: `CHANGELOG.md` on `main`. Modes:

- **`--gate`** — env `BEFORE`/`AFTER` optional. Same semantics as release.sh's
  gate against `CHANGELOG.md`: outputs `should_run` + `version` when the push
  added a new top heading (tag-existence fallback when BEFORE is empty).
- **`--check-versions`** — the release.sh §10 rule reduced to one lane and NO
  pub.dev clause: top heading may be untagged; every heading below must have
  its `v<version>` git tag. (No `no-tag` directive here — this repo has no
  pub.dev to prove a phantom against.)
- **`--discover`** — read the top heading version; `valid_semver` it; skip if
  the GitHub release exists (idempotent). Otherwise, **the stamp**: rewrite
  every internal ref in `.github/workflows/` and `actions/`:

  ```bash
  tag="v$version"
  while IFS= read -r f; do
    sed -i.bak \
      -e "s|\(whuppi/ci[^@[:space:]]*\)@main|\1@$tag|g" \
      /dev/null 2>/dev/null; rm -f "$f.bak"   # (structure only — see note)
  done < <(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml')
  ```

  Implement it properly: one `sed -i.bak` per file applying BOTH rewrites —
  `whuppi/ci<anything>@main` → `@$tag`, and the checkout pair
  `repository: whuppi/ci` + `ref: main` → `ref: $tag` (the ref line rewrite
  can be a plain `s|^\([[:space:]]*ref:\) main *# stamped.*$|\1 $tag|` if the
  §4 snippet's comment marker is kept EXACTLY as written — anchor on the
  comment so unrelated `ref: main` lines are untouched; verify by grepping
  after the sweep that zero `@main` internal refs remain). Then: commit
  `release: $tag` (the same ephemeral stamped-commit pattern as release.sh
  `--discover`: push to a `_release-staging-$version` branch with the EXIT
  trap, `gh release create "$tag" --target <stamped-sha>` with notes from
  `extract_entry CHANGELOG.md $version`, delete the staging branch). `main`
  itself is never touched. Outputs `tag`, `version`, `has_release`.

The version-tag discipline follows the packages: bump MAJOR when a consumer
must change its caller stubs or Makefile targets; MINOR for new
capabilities/inputs/workflows; PATCH for fixes and pin bumps. State this in
the file header AND the README.

---

## 4. Part A — reusable workflows in `whuppi/ci/.github/workflows/`

Shared mechanics for ALL of §4.1–4.7 (the `workflow_call` files):

- `on: workflow_call:` with the inputs/secrets listed per file. **No other
  triggers** — consumers own triggers.
- Every workflow declares top-level `permissions: {}` and per-job least
  privilege (copy the per-job `permissions:` blocks from the source workflows —
  they are already minimal and commented).
- **No `concurrency:` blocks in the callee** — callers set concurrency (the
  group keys need caller event context).
- Keep the source's `inputs`-resolving job pattern where a runner choice
  exists: here it simplifies to a `runner` input
  (`type: string, default: 'ubuntu-24.04'`) used directly in `runs-on:` — the
  indirection job is only needed for `workflow_dispatch` choice menus, which
  live caller-side now. Drop the `inputs:` job entirely in callee files.
- Where a job needs the ci repo's `tool/` scripts, add this step after the
  consumer checkout:

  ```yaml
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
    with:
      repository: whuppi/ci
      ref: main   # stamped to the exact release tag by self-release.yml
      path: .whuppi-ci
      persist-credentials: false
  ```

  and call scripts as `bash .whuppi-ci/tool/…`. The `ref: main` is the on-main
  convention (§1) — a consumer calling this workflow `@v1.2.0` receives the
  stamped file whose ref is `v1.2.0`, so the tools always match the workflow
  that invokes them. When the CONSUMER checkout must
  stay pristine for a `git diff`/publish, the `.whuppi-ci` directory is inside
  the workspace — that is fine for every job below except release's publish
  job, which must `rm -rf .whuppi-ci` before `dart pub publish` (or the tarball
  picks it up; `.pubignore` can't be assumed to cover it).
- `github.repository`, `github.event.*` inside a called workflow are the
  CALLER's context — the source workflows' expressions keep working.

### 4.1 `pr-checks.yml`

Derived from `$SRC/.github/workflows/pr-lint.yml`. Callee inputs:

```yaml
on:
  workflow_call:
    inputs:
      runner:            { type: string,  required: false, default: 'ubuntu-24.04' }
      changelog-check:   { type: boolean, required: false, default: true }
      shell-lint:        { type: boolean, required: false, default: true }
```

Jobs (each `runs-on: ${{ inputs.runner }}`, timeouts as in source):

1. **conventional-commit** — as source, but: checkout consumer, checkout ci to
   `.whuppi-ci`, and pick the types file with
   `types_file=tool/commit-types.txt; [ -f "$types_file" ] || types_file=.whuppi-ci/tool/commit-types.txt`
   so a consumer override wins and the shared list is the fallback.
2. **promotion-check** — copy verbatim (no checkout; the dev/prod/hotfix rules
   are the whuppi standard).
3. **changelog-check** — `if: inputs.changelog-check`; as source but the two
   release.sh calls become `bash .whuppi-ci/tool/ci/release.sh --check-versions`
   (with `BRANCH=dev` / `BRANCH=prod` env as in source; consumer checkout keeps
   `fetch-depth: 0`, `fetch-tags: true`). Add
   `GITHUB_REPOSITORY: ${{ github.repository }}` explicitly? Not needed — it is
   always set by the runner. release.sh runs from the consumer root (CWD), which
   §3.7 made the contract.
4. **workflow-lint** — as source with paths adapted:
   `source .whuppi-ci/tool/versions.env` before the zizmor and actionlint
   invocations (replacing `source tool/versions.env`); zizmor and actionlint
   still scan the CONSUMER's `.github/`. The shell-lint step becomes
   `if: inputs.shell-lint` … `run: bash .whuppi-ci/tool/lint_shell.sh` (runs in
   the consumer workspace per §3.9 — but note `git ls-files '.github'` in the
   consumer repo does NOT include `.whuppi-ci/`, so the consumer tree alone is
   linted, which is correct).
5. **pin-availability** from the source file does NOT move here — it belongs to
   the ci repo's own self-check (§4.8), because the pins live here now.

### 4.2 `triage.yml`

Derived from `$SRC/.github/workflows/triage.yml`. Callee:

```yaml
on:
  workflow_call:
    inputs:
      assignee:  { type: string, required: false, default: 'chaudharydeepanshu' }
```

- Replace every `github.repository == 'whuppi/pdf_manipulator'` guard with
  `github.repository_owner == 'whuppi'`.
- Drop the `inputs` job; jobs run on `ubuntu-24.04` directly (this workflow was
  never runner-configurable in substance).
- `assign` job: assignee comes from `${{ inputs.assignee }}` via `env:`.
- All five jobs move over: label-by-files (actions/labeler, reads the
  consumer's `.github/labeler.yml`), label-by-title, assign,
  revoke-ready-to-test, dependabot-needs-recreate. Keep the env-only fork-data
  discipline exactly.
- The `# zizmor: ignore[dangerous-triggers]` comment does NOT come here (no
  dangerous trigger in the callee) — it lives in the caller stub (§6.2).

### 4.3 `auto-close.yml`

Derived from `$SRC/.github/workflows/auto-close.yml`. Callee inputs:

```yaml
on:
  workflow_call:
    inputs:
      runner:              { type: string, required: false, default: 'ubuntu-24.04' }
      maintainers-mention: { type: string, required: false, default: '@chaudharydeepanshu' }
```

- Drop the `inputs` job; `runs-on: ${{ inputs.runner }}`.
- The three jobs (arm / keep-open / sweep) move as-is; their `if:` conditions on
  `github.event_name` keep working (caller passes issues/issue_comment/schedule/
  dispatch events through).
- In keep-open's final `gh issue comment` body, the hardcoded
  `@chaudharydeepanshu @slopfairy` becomes the `maintainers-mention` input,
  passed via `env:` (it reaches a printf — keep it out of inline interpolation).

### 4.4 `labels.yml`

Derived from `$SRC/.github/workflows/labels.yml`. Callee: no inputs. Repo guard
→ `github.repository_owner == 'whuppi'`. Drop the `inputs` job. The sync job is
verbatim otherwise (reads the consumer's `.github/labels.json`).

### 4.5 `retry.yml`

Derived from `$SRC/.github/workflows/retry.yml`. Callee: no inputs. Repo guard
→ owner check. Drop the `inputs` job. The retry job's `if:` keeps
`github.event.workflow_run.conclusion == 'failure' && github.event.workflow_run.run_attempt == 1`
(the caller carries the `workflow_run` trigger and its zizmor ignore).

### 4.6 `upgrade-check.yml` (the consumer flavor)

Derived from `$SRC/.github/workflows/upgrade-check.yml`, restructured: the
shared-tool pins job is GONE (that is §4.9 in the ci repo). Callee inputs:

```yaml
on:
  workflow_call:
    inputs:
      runner:  { type: string, required: false, default: 'ubuntu-24.04' }
      branch:  { type: string, required: false, default: 'dev' }
```

Two jobs:

1. **flutter-sdk** — a `chore/flutter-sdk` PR bumping `.fvmrc` +
   `example/.fvmrc` (when present). Logic lifted from the deleted flutter
   section of `$SRC/tool/ci/upgrade.sh` (lines ~175–194), inlined as a step:
   fetch `releases_linux.json`, resolve `current_release.stable` → version,
   validate `^[0-9]+\.[0-9]+\.[0-9]+$` (keep the injection-guard comment),
   `sed -i.bak` both `.fvmrc` files guarded by `[ -f … ]`. Branch/PR plumbing
   copies the source's `pins` job shape verbatim (git identity, `gh auth
   setup-git`, label `upgrade-pins` — reuse that label — existing-PR detection,
   force-push rules, draft PR with a body that names the SDK bump and tells the
   maintainer to add `ready-to-test`). Base branch: `${{ inputs.branch }}`.
2. **lockfiles** — copy the source's `lockfiles` job with two changes: the fvm
   capability step becomes `uses: whuppi/ci/actions/capabilities/fvm@main`
   (internal ref — stamped at release), and the base branch is
   `${{ inputs.branch }}`. Keep the `--no-example` root
   resolve + `example/` flutter resolve, the `:(glob)**/pubspec.lock` staging,
   and the backtick-via-printf trick exactly.

### 4.7 `release.yml`

Derived from `$SRC/.github/workflows/create-release.yml` MINUS the compile and
upload-assets jobs (pure-Dart/Flutter plugin packages ship no binaries). Callee:

```yaml
on:
  workflow_call:
    inputs:
      branch:  { type: string, required: true }   # dev or prod — the lane
      runner:  { type: string, required: false, default: 'ubuntu-24.04' }
    secrets:
      pub-credentials:
        required: true
```

`defaults: { run: { shell: bash } }` at the workflow level, as in source.
Every `bash tool/ci/release.sh` becomes `bash .whuppi-ci/tool/ci/release.sh`
(each job checks out the consumer THEN ci to `.whuppi-ci`). `BRANCH` env comes
from `${{ inputs.branch }}` (the caller resolves `github.ref_name` vs dispatch
input — callee never guesses).

Jobs:

1. **gate** — consumer checkout `fetch-depth: 0` at `ref: ${{ inputs.branch }}`;
   `--check-versions` then `--gate` (with `BEFORE: ${{ github.event.before }}`,
   `AFTER: ${{ github.sha }}` — on a dispatch these are empty/irrelevant and
   release.sh already handles that). Outputs `should_run`, `version`.
2. **discover** — `if: needs.gate.outputs.should_run == 'true'`; job-level
   `concurrency: { group: release-${{ needs.gate.outputs.version || github.run_id }}, cancel-in-progress: true }`
   (this one stays callee-side — it dedups by discovered version, which only
   exists here); `permissions: contents: write`; runs `--discover`; outputs
   `tag`, `version`, `has_release`.
3. **git-install-note** — small job after discover
   (`permissions: contents: write`): checkout consumer at the tag, checkout ci,
   run `--add-git-install "$TAG"`. (In the source this rode upload-assets;
   with no binaries it gets its own 5-minute job.)
4. **publish** — `if: needs.discover.outputs.has_release == 'true'`,
   `environment: ${{ inputs.branch }}`, `permissions: contents: write`;
   checkout consumer at `ref: ${{ needs.discover.outputs.tag }}` with
   `fetch-depth: 0`; checkout ci;
   `uses: whuppi/ci/actions/capabilities/fvm@main` (internal ref — stamped);
   then exactly the source publish sequence: `--stamp-changelog "$TAG"`,
   `--stamp-readme`, **`rm -rf .whuppi-ci`** (see §4 shared mechanics), the
   ephemeral stamp commit, materialize `${{ secrets.pub-credentials }}` to
   `~/.config/dart/pub-credentials.json`, `fvm dart pub get --no-example`,
   `fvm dart pub publish --force`, then re-checkout ci and
   `--add-pub-install "$TAG"`. (Order matters: the stamp commit must happen
   AFTER the rm so the tree is clean and ci files never enter the tarball.)

Keep the source's `--update-tag-hashes` OUT of this workflow (no assets).
release.sh keeps the mode for future binary-shipping consumers.

### 4.8 `self-check.yml` — the ci repo's own PR gate (normal triggers)

```yaml
on:
  pull_request:
    branches: [main]
  workflow_dispatch:
```

`permissions: {}`; caller-style concurrency
(`group: ${{ github.workflow }}-${{ github.ref }}`, cancel-in-progress true).
Jobs, all on `ubuntu-24.04`, all `contents: read`, all with plain
`actions/checkout` (`persist-credentials: false`):

1. **conventional-commit** — the pr-checks job body against this repo's own
   `tool/commit-types.txt` (no second checkout needed).
2. **workflow-lint** — zizmor (auditor persona, `.github/` — note: zizmor scans
   reusable workflows fine) + actionlint + `bash tool/lint_shell.sh` run from
   the repo root. Versions from `source tool/versions.env`.
3. **action-lint-actions** — actionlint only covers `.github/workflows/`; the
   `actions/**/action.yml` files get: a YAML parse check
   (`python3 -c 'import sys,yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]' $(git ls-files 'actions/*/action.yml' 'actions/*/*/action.yml')`)
   — runners ship PyYAML — plus zizmor, which does scan composite actions.
4. **pin-availability** — `bash tool/ci/upgrade.sh check-availability` (HEADs
   every pinned asset; this is the job that moved out of consumer pr-checks).
5. **internal-refs-are-main** — the stamping guard: fail if any internal
   whuppi/ci reference on main carries a version tag (a stamped ref leaking
   back into main would freeze internals at an old version forever):

   ```bash
   bad=$(grep -rnE 'whuppi/ci[^@[:space:]]*@' .github/workflows/ actions/ \
     | grep -v '@main' || true)
   [ -z "$bad" ] || { printf '%s\n' "$bad"; echo "::error::internal whuppi/ci refs on main must be @main (self-release stamps tags)"; exit 1; }
   ref_bad=$(grep -rn -A3 'repository: whuppi/ci' .github/workflows/ \
     | grep -E 'ref:' | grep -v 'ref: main' || true)
   [ -z "$ref_bad" ] || { printf '%s\n' "$ref_bad"; echo "::error::checkout of whuppi/ci on main must use ref: main"; exit 1; }
   ```

   (Exclude `docs/` — prose examples show pinned versions on purpose.)

### 4.9 `self-upgrade.yml` — the ci repo's pin radar (normal triggers)

Derived from the `pins` job of `$SRC/.github/workflows/upgrade-check.yml`:

```yaml
on:
  schedule: [{ cron: '0 8 * * *' }]
  workflow_dispatch:
```

One job, exactly the source `pins` job with: base branch `main` (not dev);
`bash tool/ci/upgrade.sh verify-pinned` first (repoint alarm), then `apply`,
then commit `tool/versions.env` only (no `.fvmrc` glob — that left with the
flutter section) and open/update the `chore/pins` draft PR with the
`upgrade-pins` label. PR body: keep the source's hash-review framing; replace
the Flutter-SDK bullet with "tool + binary pins consumed by every whuppi/ci
consumer" and drop the `ready-to-test` sentence (this repo has no full-test) —
say "merge once self-check is green; cut a release so consumers' Dependabot
PRs pick it up" (pin bumps reach consumers only through a tagged release —
another reason the PATCH release after a pins merge matters).

### 4.10 `self-release.yml` — the ci repo's release cut (normal triggers)

Modeled on the gate/discover frame of `$SRC/.github/workflows/create-release.yml`
(no compile/upload/publish — a GitHub release IS the artifact here):

```yaml
on:
  push:
    branches: [main]
    paths: ['CHANGELOG.md']
  workflow_dispatch:
```

`permissions: {}` top-level; concurrency `${{ github.workflow }}` with
`cancel-in-progress: false` (a release must finish). Two jobs on ubuntu-24.04:

1. **gate** — checkout main `fetch-depth: 0` + tags, `persist-credentials:
   false`; run `bash tool/ci/self_release.sh --check-versions` then `--gate`
   (env `BEFORE: ${{ github.event.before }}`, `AFTER: ${{ github.sha }}`).
   Outputs `should_run`, `version`. `permissions: contents: read`.
2. **release** — `if: needs.gate.outputs.should_run == 'true'`;
   `permissions: contents: write`; checkout `fetch-depth: 0`; run
   `bash tool/ci/self_release.sh --discover` (GH_TOKEN from
   `${{ secrets.GITHUB_TOKEN }}`). This stamps internal refs, tags, and
   creates the GitHub release — which is what consumers' Dependabot watches.

Cutting a release = merge a PR to main whose `CHANGELOG.md` gains a new top
heading. Same muscle memory as the package repos.

### 5.1 `README.md`

Author it. Keep it under ~120 lines, plain technical register, no marketing.
Sections:

1. **What this is** — shared CI for whuppi Flutter/Dart package repos: reusable
   workflows (thin caller stubs in each consumer own the triggers; jobs live
   here), composite actions (capability provisioning + `make-target`), and the
   pinned-tool supply chain (`tool/versions.env`, every binary sha256-verified
   through `tool/fetch_verified.sh`).
2. **Consuming** — a table of the seven reusable workflows (name → what it does
   → required caller trigger) and a minimal caller example (the device_io
   pr-checks stub, inline). A second short example of a consumer ci.yml job
   using `make-target` with capabilities.
3. **The version contract** — releases are cut from `CHANGELOG.md` by
   `self-release.yml`; tags are immutable exact versions (`v1.0.0`); consumers
   pin exact versions and upgrade through per-repo Dependabot PRs (grouped so
   every whuppi/ci ref bumps together), tested by that PR's own CI before
   merge; internal refs are `@main` on main and stamped to the tag at release;
   MAJOR = caller stubs or Makefile contract changes, MINOR = additive,
   PATCH = fixes + pin bumps. No moving major tag, ever — say why in one
   sentence (a moving tag updates every consumer at once, untested).
4. **Pins ownership** — the §1 table, prose form.
5. **Repo model** — `main` + tags, no dev/prod chain, with the one-sentence
   rationale and the pointer to repo-setup.md as the standard it deviates from.
6. **Local gates** — `make check` (what it runs, what it needs installed).

### 5.2 `Makefile`

```make
# Local gates for the whuppi/ci repo itself. CI mirrors these in self-check.yml.
SHELL := /usr/bin/env bash

.PHONY: check lint-shell lint-actions

check: lint-shell lint-actions

lint-shell:
	bash tool/lint_shell.sh

lint-actions:
	@python3 -c 'import sys,yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]; print("YAML parse: OK (%d files)" % (len(sys.argv)-1))' \
	  $$(git ls-files '.github/workflows/*.yml' 'actions/*/action.yml' 'actions/*/*/action.yml')
	@command -v actionlint >/dev/null 2>&1 && actionlint -color || echo "actionlint not installed — CI enforces it"
	@command -v pipx >/dev/null 2>&1 && { source tool/versions.env && pipx run "zizmor==$$ZIZMOR_VERSION" --persona=auditor .github/ actions/; } || echo "pipx/zizmor not installed — CI enforces it"
```

(Adjust quoting so it survives `make`'s `$$` escaping — verify by running it.)

### 5.3 `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    labels: [dependencies]
```

Note: Dependabot's github-actions ecosystem also scans `actions/**/action.yml`
composite steps? It scans workflow files and action.yml in the repo root's
action — to cover the nested `actions/**` directories, add one `directory:`
entry per action directory is NOT needed with `directories:` support; use:
`directories: ["/", "/actions/*", "/actions/capabilities/*"]` on a single
entry (Dependabot supports glob directories for github-actions since 2024).
Verify the syntax against `$SRC/.github/dependabot.yml` and current Dependabot
docs offline knowledge; if unsure, enumerate the directories explicitly.

### 5.4 `CHANGELOG.md` (ci repo)

Single lane, newest-first, same heading shape as the package changelogs
(`## X.Y.Z` + bullet groups). Seed it with a `## 1.0.0` top heading whose
bullets summarize the initial surface (reusable workflows, capability actions,
make-target, pinned-tool supply chain, self-release stamping). This heading is
what the first post-push `self-release.yml` run cuts `v1.0.0` from.

### 5.5 `docs/ARCHITECTURE.md`

Author ~150 lines covering: the two consumption mechanisms and when each is
used; the versioned-release model and the stamping rule (§1) with the
consumer-upgrade flow (Dependabot group PR → consumer CI → optional
`ready-to-test` → merge); the `$GITHUB_ACTION_PATH` script-access pattern (with the depth table
from §3); the `.whuppi-ci/` checkout pattern for reusable-workflow jobs and the
release-publish `rm -rf` requirement; the pins ownership split; the make-target
orchestration contract (capabilities as declarative booleans, `/tmp/make-run.sh`
authored once, emulator vs direct path can't drift); the repo-guard convention;
what stays consumer-side (triggers, concurrency, matrices, Makefiles, labels
manifest, labeler config, `.fvmrc`, changelogs); and the release model
(two-lane changelogs, release.sh mode table — reference the script, don't
duplicate its header). End with the tag/release discipline for this repo.

---

## 6. Part B — device_io consumer wiring

All paths relative to `$DIO`. device_io already has: `Makefile` (targets:
check/hooks/format/analyze/analyze-floor/platforms/test-guards/test-unit/
test-web/test-example-matrix/test-example-macos/test-example-device/clean),
`.githooks/{commit-msg,pre-commit}`, `.github/{dependabot.yml,ISSUE_TEMPLATE,
PULL_REQUEST_TEMPLATE.md}`, `CHANGELOG.md` + `CHANGELOG.pre.md` (two-lane),
`tool/check_platforms.dart`, `.fvmrc` (3.44.4) — and `example/` with
`test/journeys`, `integration_test/device_io_smoke_test.dart`,
`test_driver/integration_test.dart`.

### 6.1 Fix the commit-types drift (do this FIRST, it unblocks commits)

`.githooks/commit-msg` reads `tool/commit-types.txt`, which does not exist in
device_io — with hooks active the type list is empty and every commit would be
rejected. Create `tool/commit-types.txt` as an exact copy of
`whuppi/ci/tool/commit-types.txt` (feat fix docs chore ci test refactor perf
build deps — one per line). Commit as `fix: add the commit-types list the
commit-msg hook reads`.

### 6.2 Caller workflow stubs (`.github/workflows/`)

**Consumer ref convention:** every whuppi/ci reference in device_io — reusable
workflows AND actions — is pinned to the exact first release,
`@v1.0.0` (matching the seed heading in ci's CHANGELOG, §5.4). Never `@main`,
never a bare `@v1`. Dependabot bumps these pins as ci cuts releases (§6.6.5).

Each stub: `permissions: {}` top-level, caller-owned concurrency, one job
`uses: whuppi/ci/.github/workflows/<name>.yml@v1.0.0`. A caller job that uses a
reusable workflow needs the UNION of the callee's job permissions granted at
the caller job level — copy the per-workflow permission sets from the callee
jobs you authored in §4 (e.g. triage caller job needs
`permissions: { contents: read, issues: write, pull-requests: write }`).
Write these seven files:

1. **`pr-checks.yml`** — triggers
   `pull_request: { types: [opened, edited, synchronize, reopened], branches: [dev, prod] }`
   + `workflow_dispatch`; concurrency
   `${{ github.workflow }}-${{ github.ref }}` cancel-in-progress true; job
   `checks: uses: whuppi/ci/.github/workflows/pr-checks.yml@v1.0.0` (all defaults —
   changelog-check and shell-lint stay on; device_io has both changelog lanes
   and shell scripts under `.githooks/`... note: lint_shell lints
   `git ls-files '*.sh'` — device_io's hooks have no `.sh` extension so only
   the `.github` YAML + any future scripts are scanned; that is fine).
2. **`triage.yml`** — triggers exactly as `$SRC` triage (issues opened;
   `pull_request_target` opened/synchronize with the
   `# zizmor: ignore[dangerous-triggers]` comment AND the full PRIVILEGED
   doctrine header comment copied from the source file — the ignore is only
   safe with the doctrine documented beside it); concurrency per PR/issue
   number, cancel-in-progress false; job calls the reusable triage.
3. **`auto-close.yml`** — triggers as source (daily cron 09:00, issues labeled,
   issue_comment created, dispatch); concurrency as source; calls reusable.
4. **`labels.yml`** — trigger: push to dev with paths `.github/labels.json` +
   `.github/workflows/labels.yml`, + dispatch; concurrency as source; calls
   reusable.
5. **`retry.yml`** — trigger `workflow_run: { workflows: [CI, Full Test], types: [completed] }`
   with the zizmor ignore + doctrine comment from source; concurrency per run
   id, cancel false; calls reusable.
6. **`upgrade-check.yml`** — triggers: daily cron 08:00 + dispatch; concurrency
   group `${{ github.workflow }}` cancel false; calls reusable with
   `branch: dev`.
7. **`release.yml`** — triggers: push to dev/prod on paths CHANGELOG.md /
   CHANGELOG.pre.md + dispatch with a branch choice input (dev/prod, default
   dev); concurrency `${{ github.workflow }}-${{ github.ref }}` cancel false;
   job calls reusable release with
   `branch: ${{ inputs.branch || github.ref_name }}` and
   `secrets: { pub-credentials: ${{ secrets.PUB_CREDENTIALS }} }`.

Plus one direct-action workflow:

8. **`debug-ssh.yml`** — copy `$SRC/.github/workflows/debug-ssh.yml`, replace
   `uses: ./.github/actions/debug-ssh` with
   `uses: whuppi/ci/actions/debug-ssh@v1.0.0` and drop `submodules: recursive`
   from the checkout (device_io has none).

### 6.3 `ci.yml` — device_io's own fast PR gate

Model on `$SRC/.github/workflows/ci.yml` (triggers, permissions, concurrency,
inputs job, changes job, gate job — copy those frames). Jobs between `changes`
and `gate`, each `uses: whuppi/ci/actions/make-target@v1.0.0` after a plain
checkout (`persist-credentials: false`, NO submodules):

| Job | make-target | capabilities | timeout |
|---|---|---|---|
| analyze | `analyze` | none | 15 |
| analyze-floor | `analyze-floor` | none | 15 |
| platforms | `platforms` | none | 15 |
| test-guards | `test-guards` | none | 10 |
| test-unit | `test-unit` | none | 20 |
| test-web | `test-web` | `chrome: true`, `headless-display: true` | 30 |

`changes` filters for device_io: `code:` = `lib/**, test/**, example/**,
tool/**, pubspec.yaml, analysis_options.yaml, Makefile, .github/**`. There is
no `rust:` filter — remove that output and the rust job entirely; the `gate`
job's evaluate script checks the six results above (adapt the env list; keep
the "changes must succeed before trusting its output" guard verbatim).

NOTE on make-target's fvm capability: it runs unconditionally and needs
`.fvmrc` — device_io has it. The `platforms` target runs pana — read
`$DIO/Makefile` first; if `platforms` shells into `dart pub global activate
pana` it works on CI as-is. Do not change how device_io pins pana.

### 6.4 `full-test.yml` — device_io's cross-target matrix

Model on `$SRC/.github/workflows/full-test.yml` (label trigger + dispatch with
portability toggle + filter, the filter-check step, artifact upload, gate).
Filter choice list: `all, android, ios, macos, linux, windows, web, pkg, int,
verify`. Matrix rows (name → runner → make target → capabilities):

```
# ── Package tests ──
pkg: Linux (ubuntu-x64)        ubuntu-24.04         test-unit            timeout 20
pkg: macOS (macos-arm64)       macos-14             test-unit            timeout 20
pkg: Windows (win-x64)         windows-2025-vs2026  test-unit            timeout 30
pkg: Web (ubuntu-x64)          ubuntu-24.04         test-web             timeout 30  chrome, headless-display
pkg: Web (macos-arm64) [P]     macos-14             test-web             timeout 30  chrome                    portability
pkg: Web (win-x64) [P]         windows-2025-vs2026  test-web             timeout 40  chrome                    portability

# ── Example journey matrix (host VM, in-memory) ──
int: Journeys (ubuntu-x64)     ubuntu-24.04         test-example-matrix  timeout 20
int: Journeys (macos-arm64) [P] macos-14            test-example-matrix  timeout 20                            portability
int: Journeys (win-x64) [P]    windows-2025-vs2026  test-example-matrix  timeout 30                            portability

# ── Integration smokes (real plugins, real devices) ──
int: Android (ubuntu-x64)      ubuntu-24.04         test-example-android timeout 40  java, hw-accel, gradle-cache, emulator
int: iOS (macos-arm64)         macos-14             test-example-ios     timeout 60  xcode-cache (target ios), pods-cache, simulator
int: Linux (ubuntu-x64)        ubuntu-24.04         test-example-linux   timeout 30  headless-display
int: macOS (macos-arm64)       macos-14             test-example-macos   timeout 30  xcode-cache (target macos)
int: Windows (win-x64)         windows-2025-vs2026  test-example-windows timeout 40
int: Web (ubuntu-x64)          ubuntu-24.04         test-example-web     timeout 40  chrome, headless-display

# ── Verify (release builds of the example) ──
verify: Android (ubuntu-x64)   ubuntu-24.04         verify-android       timeout 40  java, gradle-cache
verify: iOS (macos-arm64)      macos-14             verify-ios           timeout 40  xcode-cache (ios), pods-cache
verify: Linux (ubuntu-x64)     ubuntu-24.04         verify-linux         timeout 30
verify: macOS (macos-arm64)    macos-14             verify-macos         timeout 40  xcode-cache (macos)
verify: Web (ubuntu-x64)       ubuntu-24.04         verify-web           timeout 30
verify: Windows (win-x64)      windows-2025-vs2026  verify-windows       timeout 40
```

The make-target step forwards the same capability booleans the source file
does, minus wasm/rust which no longer exist, plus nothing new. android row
passes no `report-json` override IF §6.5 writes the report to the default path
`test-results/int-android.json`; otherwise pass the actual path.

### 6.5 Makefile additions (device_io)

Read `$DIO/Makefile` and `$SRC/Makefile` (pdf_manipulator) first — mirror the
pdf_manipulator mechanics for each new target, adapted to device_io's layout
(no fixtures, no wasm, integration test file is
`integration_test/device_io_smoke_test.dart`). Add, styled like the existing
targets and registered in `.PHONY`:

- `test-example-android` / `test-example-ios` / `test-example-linux` /
  `test-example-windows` — run the integration smoke on that device:
  `cd example && fvm flutter test integration_test/device_io_smoke_test.dart -d <device> [--machine → test-results/int-android.json for android]`.
  Copy pdf_manipulator's exact per-platform device flags and, for android, its
  `--machine` report plumbing (the emulator watchdog's reconciler consumes it).
- `test-example-web` — the web integration path needs `flutter drive` with
  chromedriver (integration_test on web cannot use `flutter test`): mirror
  pdf_manipulator's `test-example-web` recipe (chromedriver launch, port,
  `flutter drive --driver=test_driver/integration_test.dart
  --target=integration_test/device_io_smoke_test.dart -d web-server`... copy
  the ACTUAL recipe from `$SRC/Makefile`, do not invent flags).
- `verify-{android,ios,macos,linux,windows,web}` — release builds of the
  example (`cd example && fvm flutter build <apk|ios --no-codesign|macos|linux|windows|web>`),
  again mirroring `$SRC/Makefile`'s exact verify recipes.
- Update `test-example` aggregate and the Makefile's header comment table if it
  lists targets.
- device_io's existing `test-example-macos` already runs the macOS smoke — keep
  it; the new targets follow its shape.

Then update `example/README.md`'s Tests section to mention the per-platform
`make test-example-<platform>` targets in one sentence (do not restructure the
file).

### 6.6 Repo-config files (`.github/`)

1. **`labels.json`** — device_io's manifest. Take the pdf_manipulator set,
   drop `web` and `upstream` (pdf-specific), keep: bug, feature, ci,
   dependencies, upgrade-pins, upgrade-locks, ready-to-test, release,
   needs-info, wont-fix, resolved, bot-closing-soon. Add `docs`
   (`0075CA`, "Documentation change (auto)") to match the repo-setup §7
   baseline. Keep the exact description style (terse phrase + applier tag).
2. **`labeler.yml`** — path-label map for device_io:
   `ci:` → `.github/**`, `.githooks/**`, `Makefile`, `tool/**`;
   `docs:` → `docs/**`, `**/*.md`.
3. **`actionlint.yaml`** — copy verbatim from whuppi/ci (the runner-label
   registrations).
4. **`CODEOWNERS`** — read `$SRC/.github/CODEOWNERS` and mirror its exact
   pattern with device_io's team name (`* @whuppi/device_io-maintainers`,
   `.github/` + CI-config guard-rail lines to the repo owner, per
   repo-setup.md §5).
5. **`dependabot.yml`** — device_io already has one; verify it covers both
   `pub` (root + `/example`) and `github-actions` ecosystems with the
   `dependencies` label; extend if a piece is missing, preserving what's there.
   Then add the whuppi/ci upgrade group to the `github-actions` entry — this is
   the consumer's shared-CI upgrade channel (one PR per ci release, all refs
   moving together, tested by that PR's own gates before merge):

   ```yaml
     - package-ecosystem: github-actions
       directory: /
       schedule: { interval: daily }
       labels: [dependencies]
       groups:
         whuppi-ci:
           patterns: ["whuppi/ci"]
   ```

   (Merge with the existing entry rather than duplicating it; the group means a
   new ci release bumps make-target, every capability, and every reusable
   workflow ref in a single PR — mixed internal versions are impossible.)

### 6.7 Docs updates (device_io)

1. `docs/CAPABILITY_ROADMAP.md` — flip the row
   `| CI via the shared workflow repo | PLANNED | … |` to `DONE` with a note:
   thin callers over `whuppi/ci` pinned at `v1.0.0`, upgraded by grouped
   Dependabot PRs; fast gate in `ci.yml`;
   label-triggered cross-target `full-test.yml`; release via the reusable
   release workflow (gate → discover → publish, no binaries).
2. `docs/UPDATING.md` — in "Releasing", replace "(the shared-workflow setup)"
   with the concrete reference: the reusable `whuppi/ci` release workflow, and
   one sentence: pushing a new top heading to a lane changelog on its branch
   triggers gate → discover → publish; publish waits on the branch-named
   GitHub environment approval.
3. `CHANGELOG.pre.md` — under the existing untagged top version's `### CI`
   (or add the lane section if absent, matching the file's existing section
   style): one bullet — wired as the first consumer of the whuppi/ci shared
   workflows (fast PR gate, cross-target full test, triage/auto-close/labels/
   retry hygiene, pin radar, release pipeline). ONE untagged version max per
   lane file — do not add a new heading if one exists.

### 6.8 What device_io does NOT get

No consumer copies of: versions.env, fetch_verified.sh, lint_shell.sh,
release.sh, upgrade.sh, capability actions. That is the whole point. If while
wiring you find yourself copying a shared file into device_io, stop — the
design has a hole; report it instead.

---

## 7. Verification protocol (run all; report what could not run)

In `whuppi/ci`:

1. `bash -n` every `*.sh` under `tool/` — must parse.
2. `bash tool/lint_shell.sh` from the repo root — must pass (this also
   validates the §3.9 edit runs the current-dir contract; it needs
   `shellcheck`/`yq` for full coverage — report any skip notes it prints).
3. `make check` — YAML parse of every workflow + action must pass;
   actionlint/zizmor legs run only if installed (report).
4. `python3` YAML-load every `.yml` you touched (also covered by make check).
5. Grep gates — all must return nothing:
   - `grep -rn "pdf_manipulator\|pdf_oxide\|vendor/\|wasm\|binaryen\|build\.json" actions/ tool/ .github/workflows/ | grep -v BUILD_SPEC` (allow hits only in
     `reconcile_test_json.sh` comments if genuinely generic phrasing was kept —
     better: zero hits).
   - `grep -rn "tool/versions.env" actions/ | grep -v GITHUB_ACTION_PATH` —
     every read must go through the CI_ROOT pattern.
   - `grep -rn "\./\.github/actions" actions/ .github/workflows/` — no local
     action refs may survive in this repo.
   - the §4.8.5 internal-refs-are-main greps, run locally — every internal
     whuppi/ci ref says `@main` / `ref: main`; zero hand-written version tags.
6. `git log --oneline` — conventional titles, logical chunks.

In `device_io`:

7. `python3` YAML-load every new/changed workflow file.
8. `bash .githooks/commit-msg` self-test: `printf 'feat: x\n' > /tmp/m && bash .githooks/commit-msg /tmp/m; echo $?`
   must be 0, and `printf 'bad msg\n' > /tmp/m && bash .githooks/commit-msg /tmp/m; echo $?`
   must be 1 (proves §6.1 fixed the drift).
9. `make check` — the full existing device_io gate must stay green
   (`export PATH="$HOME/fvm/default/bin:$PATH"` style env may be needed — use
   whatever the repo's existing sessions used; check `fvm` is on PATH via
   `fvm --version`). The new Makefile targets must parse
   (`make -n test-example-android` etc. — dry-run only; do NOT boot emulators
   locally). `make -n verify-macos` etc. likewise.
10. Run the macOS-runnable subset for real if time allows:
    `make test-example-matrix` (host journeys) must stay green.
11. Grep gate: `grep -rn "whuppi/ci" .github/workflows/ | grep -v "@v1\.0\.0"`
    → nothing (every shared ref carries the exact pin; no `@main`, no bare
    major).

Nothing that requires GitHub (zizmor ref checks may hit the network for
cross-repo refs and will fail to resolve the `whuppi/ci@v1.0.0` refs before push — if zizmor
flags unresolvable refs, note it in the report; it is expected pre-push).

---

## 8. Acceptance checklist

- [ ] whuppi/ci: all §3 edits done (including §3.13 self_release.sh);
      §4.1–4.10 workflows authored; §5 README, Makefile, dependabot,
      CHANGELOG (seeded `## 1.0.0`), ARCHITECTURE written; everything
      committed.
- [ ] Versioning invariants hold: internal refs all `@main` on main
      (§4.8.5 greps clean); every device_io ref pinned `@v1.0.0`; the
      Dependabot whuppi-ci group present in device_io.
- [ ] Zero pdf_manipulator-specific tokens left in whuppi/ci (verification 5).
- [ ] device_io: commit-types drift fixed; 10 workflow files
      (pr-checks, triage, auto-close, labels, retry, upgrade-check, release,
      debug-ssh, ci, full-test); labels.json, labeler.yml, actionlint.yaml,
      CODEOWNERS; Makefile targets; docs + changelog updated; committed.
- [ ] All verification steps run; every skip explicitly reported.
- [ ] NOTHING pushed. pdf_manipulator untouched
      (`git -C $SRC status --short` → empty).
- [ ] Final report lists: files created/changed per repo, verification results,
      anything this spec got wrong or that you had to decide yourself (state
      the decision and why).

---

## 9. Post-push runbook (NOT part of this build — for the maintainer, later)

Recorded here so the knowledge isn't lost: create the `whuppi/ci` repo on
GitHub → push main → the `self-release.yml` push run (or a dispatch) cuts
`v1.0.0` from the seeded changelog heading — the tag is a STAMPED commit, so
never hand-tag main directly → org Actions setting must allow whuppi repos to
use whuppi/ci's reusable workflows/actions (Settings → Actions → Access:
"Accessible from repositories in the whuppi organization" if the repo is
private; public needs nothing) → device_io: create dev/prod GitHub
environments (prod with required reviewers) + `PUB_CREDENTIALS` secret per
environment → apply repo-setup.md §2 branch protection with the new required
checks (`CI Gate`, `Full Test Gate`, the pr-checks job names) → create the
`device_io-maintainers` team → run the labels workflow once via dispatch.

Upgrade flow once live: merge a changelog PR in whuppi/ci → self-release cuts
`vX.Y.Z` → each consumer's Dependabot opens ONE grouped PR bumping every
whuppi/ci pin → that PR's fast gate runs automatically; add `ready-to-test`
for the full cross-target matrix when the release touches test-path behavior →
merge when green. Consumers upgrade independently, on their own time; an old
pin keeps working forever because tags are immutable.
