# Pre-commit framework

Local quality gates for the whole repository (`az-infra-generic` and
`tp-local`), run by [pre-commit](https://pre-commit.com/) from
`.pre-commit-config.yaml` at the repository root. They catch formatting,
syntax, documentation and secret problems **before** a commit or a push.

They complement the CI pipeline, they do not replace it: hooks can be
skipped on a workstation, so every security and validation gate still runs
in CI ([`ci-cd.md`](ci-cd.md)), which stays authoritative.

## Contents

1. [What runs when](#1-what-runs-when)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Daily workflow](#4-daily-workflow)
5. [Running hooks manually](#5-running-hooks-manually)
6. [Generated and hand-written documentation](#6-generated-and-hand-written-documentation)
7. [CI integration](#7-ci-integration)
8. [Troubleshooting](#8-troubleshooting)
9. [Bypassing a hook (exceptional)](#9-bypassing-a-hook-exceptional)
10. [Maintenance](#10-maintenance)

## 1. What runs when

| Stage | Trigger | Files checked | Purpose |
|---|---|---|---|
| `pre-commit` | `git commit` | staged files | fast checks, offline once the hook environments exist |
| `pre-push` | `git push` | files changed by the pushed commits | Terraform init + validate, TFLint, CI unit tests on what changed |
| `manual` | `pre-commit run --hook-stage manual` | the files you pass (`--all-files` for everything) | every hook above plus `terraform test`, Trivy and Checkov |
| CI | pull request, push to `main` | everything | all of the above and more (minimum Terraform version, plans, approvals) |

Each hook only runs when files matching its filter are part of the change:
a Markdown-only commit does not start Terraform, a `tp-local` change does not
validate `az-infra-generic`.

| Category | Hook | Stage | Rewrites files | Notes |
|---|---|---|---|---|
| Hygiene | `trailing-whitespace`, `end-of-file-fixer`, `mixed-line-ending` (LF, except `.ps1`) | commit | yes | Markdown line breaks (two trailing spaces) are kept |
| Hygiene | `check-merge-conflict`, `check-added-large-files` (> 500 KB), `check-case-conflict` | commit | no | |
| Syntax | `check-yaml`, `check-json`, `check-toml` | commit | no | |
| Scripts | `check-executables-have-shebangs`, `check-shebang-scripts-are-executable` | commit | no | uses the mode recorded in Git (works on Windows checkouts) |
| Scripts | `shellcheck` (ShellCheck 0.11, severity ≥ warning) | commit | no | same options as `ci/scripts/lint.sh` and `.shellcheckrc` |
| Secrets | `detect-private-key`, `gitleaks` (staged changes, `.gitleaks.toml`) | commit | no | same Gitleaks version as CI |
| Secrets | `forbid-sensitive-files` | commit | no | state, plans, `.env`, `.terraformrc`, kubeconfigs, keys, secret tfvars, even when force-added |
| Terraform | `terraform-fmt` | commit | yes | `.tf`, `.tfvars`, `.tftest.hcl` |
| Terraform | `azure-config` (`ci.py azure-config`) | commit | no | no credential in code, backend settings, 4-platform lock files, local bootstrap state |
| Terraform | `terraform-validate` (init with read-only lock files + validate) | push | no | affected roots only (`ci.py` change detection), `-backend=false` |
| Terraform | `tflint` | push | no | affected projects; skipped with a warning if TFLint is not installed |
| Terraform | `terraform-test` (mocked providers) | manual | no | affected roots |
| Documentation | `terraform-docs` | commit | yes | regenerates the reference block of the module READMEs ([§6](#6-generated-and-hand-written-documentation)) |
| Documentation | `markdownlint-cli2` (`.markdownlint-cli2.yaml`) | commit | no | |
| Documentation | `docs-consistency` (`ci/tests/test_docs.py`) | commit | no | relative links and anchors, Mermaid syntax, referenced files and Terraform addresses, runbook structure |
| Workflows | `actionlint` (`.github/actionlint.yaml`) | commit | no | same version as CI |
| CI helpers | `ci-unit-tests` (`ci/tests`) | push | no | workflow, security-policy, pre-commit and documentation tests |
| Security scans | `trivy`, `checkov` | manual | no | CI configuration; skipped with a warning if the tool is not installed |

**No hook needs Azure credentials, a Terraform backend, a cluster or a
deployment.** Network access is only needed the first time a hook
environment is built, and by `terraform init` / `tflint --init` to download
providers and plugins (then cached). Checks that need real infrastructure
(plans, applies, integration tests) only run in CI or through the runbooks.

Measured on the reference workstation (WSL, repository on `/mnt/d`, warm
caches): a commit touching one `.tf` and one `.md` file about 35 s, a push
changing one module about 100 s (4 roots validated + TFLint). Both are much
faster on the WSL filesystem (`~/src/...`).

## 2. Requirements

| Tool | Version | Needed for |
|---|---|---|
| Git | any recent version | everything |
| Python | ≥ 3.11 with `venv` | pre-commit itself and the Python hooks |
| pre-commit | **4.7.0** (`PRE_COMMIT_VERSION` in `ci/tool-versions.env`; config requires ≥ 4.0.0) | everything |
| Terraform | the project's `.terraform-version` (1.17.2) | `terraform-fmt`, push and manual Terraform hooks |
| bash, `python3` on `PATH` | — | the hooks implemented by `ci/scripts/*.sh` |
| TFLint, Trivy, Checkov | `ci/tool-versions.env` | optional: `tflint`, `trivy`, `checkov` hooks (skipped when absent) |

pre-commit installs the other tools itself, at the pinned versions of
`.pre-commit-config.yaml`, on first use: Python packages, ShellCheck (wheel),
Node.js through nodeenv if it is not installed (markdownlint-cli2), and a Go
toolchain if Go is not installed, to build Gitleaks, terraform-docs and
actionlint. **The first run takes several minutes** (about 8 minutes for
Gitleaks on the reference workstation); later runs reuse the environments
from `~/.cache/pre-commit`.

## 3. Installation

### Linux and WSL (recommended)

```bash
sudo apt-get install -y pipx python3-venv     # Ubuntu / Debian
pipx install "pre-commit==4.7.0"

cd ~/src/generic-infra
pre-commit install          # installs the pre-commit AND pre-push hooks (default_install_hook_types)
pre-commit install-hooks    # optional: build every hook environment now instead of at the first commit
ci/scripts/install-tools.sh # optional: TFLint, Trivy, Gitleaks, actionlint, Checkov (checksum-verified)
```

`install-tools.sh` installs into `~/.cache/generic-infra-ci/bin`; the hooks
find the tools there through `ci/scripts/lib.sh`.

Without `sudo` (no `python3-venv` / `ensurepip` on the system): create the
environment without pip and bootstrap pip from PyPA:

```bash
python3 -m venv --without-pip ~/.local/share/pre-commit-venv
curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
~/.local/share/pre-commit-venv/bin/python3 /tmp/get-pip.py
~/.local/share/pre-commit-venv/bin/python3 -m pip install "pre-commit==4.7.0"
mkdir -p ~/.local/bin && ln -sf ~/.local/share/pre-commit-venv/bin/pre-commit ~/.local/bin/pre-commit
```

### Windows

Commit from **WSL** (where `tp-local` runs anyway). Native Git for Windows
can work (`py -m pip install --user pre-commit==4.7.0`; hooks run with the
`bash` shipped with Git), but application control policies such as Smart App
Control or WDAC can block the unsigned executables pre-commit creates for the
hook environments: the hooks then fail with `[WinError 4551]`. This happens on
the reference workstation, where every hook was therefore validated in WSL.

### One working tree used from Windows and WSL

The hook script written to `.git/hooks/` starts the pre-commit that installed
it, and falls back to the `pre-commit` found on `PATH` when that interpreter
does not exist in the current environment. Install pre-commit in each
environment you commit from. Hook environments are cached per environment.
A clone on the WSL filesystem is much faster than the same tree on `/mnt/c`
or `/mnt/d`.

## 4. Daily workflow

```bash
git add <files>
git commit -m "feat(...): ..."   # commit-stage hooks on the staged files
git push                         # push-stage hooks on the pushed changes
```

* **A hook rewrote a file** (`files were modified by this hook`: whitespace,
  end of file, line endings, `terraform fmt`, terraform-docs): the commit is
  stopped. Review with `git diff`, `git add` the files and commit again.
* Unstaged changes are stashed while the commit hooks run and restored
  afterwards, so only what you commit is checked.
* **Push hooks read the working tree**: commit or stash local changes before
  pushing, otherwise they check files that are not part of the push.
* A warning `local Terraform X differs from the pinned Y` means your CLI is
  not the one CI uses: install the version of `<project>/.terraform-version`
  (tfenv/tenv read it).
* A warning `tflint is not installed: 'tflint' skipped locally` (or Trivy,
  Checkov) is informational: CI runs the check; install the tool with
  `ci/scripts/install-tools.sh` to run it locally.

## 5. Running hooks manually

| Goal | Command |
|---|---|
| Commit-stage hooks on the staged files | `pre-commit run` |
| Commit-stage hooks on every file | `pre-commit run --all-files` |
| One hook | `pre-commit run markdownlint-cli2 --all-files` (or `--files a.md b.md`) |
| Push-stage hooks on your branch | `pre-commit run --hook-stage pre-push --from-ref origin/main --to-ref HEAD` |
| **Complete local suite** (commit + push + manual hooks) | `pre-commit run --hook-stage manual --all-files` |
| Terraform tests or scans only | `pre-commit run terraform-test --hook-stage manual --all-files` (`trivy`, `checkov`) |
| Regenerate the Terraform module references | `pre-commit run terraform-docs --all-files` |
| Check them without writing (terraform-docs on `PATH`) | `ci/scripts/terraform-docs.sh --check` |
| Same gates as CI, project by project | `ci/scripts/run-local.sh az-infra-generic`, `ci/scripts/run-local.sh tp-local` |
| Update hook versions | `pre-commit autoupdate`, then [§10](#10-maintenance) |
| Rebuild the hook environments | `pre-commit clean && pre-commit install-hooks` |

## 6. Generated and hand-written documentation

| Kind | Where | Written by | Checked by |
|---|---|---|---|
| **Generated** module reference: requirements, providers, modules, resources, inputs, outputs | between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` in `<project>/modules/<module>/README.md` | terraform-docs, from the module code (`.terraform-docs.yml`) | `terraform-docs` hook; the CI `pre-commit` job fails when a block is stale |
| **Hand-written technical documentation** | READMEs (outside the markers), `docs/ci-cd.md`, this document | people | `markdownlint-cli2`, `docs-consistency` |
| **Operational runbooks** | `<project>/docs/runbooks/` | people (procedures, statuses) | `markdownlint-cli2`, `docs-consistency` (structure, links, Mermaid, files and Terraform addresses that must exist in the code) |

Rules:

* Never edit between the markers: change the variable or output
  `description` in the code, then run the `terraform-docs` hook. The tool
  never writes outside the markers.
* Every reusable module (a directory `<project>/modules/<name>/` with a
  `versions.tf`) needs a README with exactly one marker pair
  (`ci/tests/test_precommit.py`).
* Placeholders in descriptions go in backticks (`` `MC_<rg>_<cluster>` ``):
  bare `<rg>` would be rendered as an HTML tag and disappear.
* The project README §9 (AKS inputs and outputs) is a hand-written, grouped
  explanation; the generated block of `modules/aks/README.md` is the complete
  reference.

**Mermaid diagrams** are validated structurally by `docs-consistency` in the
runbooks (known diagram type, quoted node labels, balanced blocks and
brackets) and rendered by GitHub. Rendering them in CI (mermaid-cli, which
needs a headless Chromium) was evaluated and not adopted: the extra toolchain
would not catch more errors than the structural check plus GitHub's preview.

## 7. CI integration

* The **`pre-commit` workflow** (`.github/workflows/pre-commit.yml`) runs the
  commit-stage hooks on every file for every pull request and every push to
  `main`, with the same configuration files. A hook that rewrites a file
  fails the job: unformatted files and stale generated documentation cannot
  be merged. Gitleaks and actionlint are skipped there because the project
  pipelines run them.
* Terraform validation, TFLint, tests and security scans are **not**
  repeated: the per-project pipelines run them on every change, with the
  same `ci/scripts` the push and manual hooks call.
* Make `pre-commit / hygiene, formatting, docs, lint (pre-commit)` a
  required status check next to the project quality gates
  ([`ci-cd.md` §11](ci-cd.md#11-executing-the-pipelines)).

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `files were modified by this hook` | A fixer or terraform-docs rewrote a file | `git diff`, `git add`, commit again |
| `[INFO] Installing environment for ...` takes minutes | First use of a hook (Go toolchain, Node.js, Python packages) | Wait once; `pre-commit install-hooks` does it in advance |
| `[WinError 4551]` on Windows | Application control blocks the hook executables | Commit from WSL ([§3](#windows)) |
| `` `pre-commit` not found. Did you forget to activate your virtualenv? `` | Hooks installed from another environment (Windows vs WSL) | Install pre-commit in the current environment |
| `Your pre-commit configuration is unstaged` | `.pre-commit-config.yaml` modified but not staged | `git add .pre-commit-config.yaml` |
| `Executable terraform not found` | Terraform not on `PATH` | Install the version of `<project>/.terraform-version` |
| `init failed ... lock file inconsistent` | Provider constraint changed without updating the lock file | As in CI: [`ci-cd.md` §12](ci-cd.md#12-troubleshooting) |
| `Detect hardcoded secrets ... Failed` | Gitleaks found a secret in the staged changes | Remove it from the change; if it was ever pushed, rotate it ([`ci-cd.md` §5](ci-cd.md#secret-exposure-procedure)). A false positive goes into `.gitleaks.toml` with a description (reviewed) |
| `forbid state, plan, credential and kubeconfig files ... Failed` | A sensitive file is staged | `git restore --staged <file>`; keep it out of Git |
| markdownlint `MDxxx` | Markdown style issue | Fix it; a justified exception: `<!-- markdownlint-disable-next-line MDxxx -->` with a reason, or a reviewed change of `.markdownlint-cli2.yaml` |
| `docs-consistency` failure | Broken link/anchor, unknown file or Terraform address in a runbook, malformed Mermaid | Fix the reference (the message names file and line) |
| Checkov or Trivy manual hook fails | Same findings as the CI gate | Fix or accept them as in CI ([`ci-cd.md` §5](ci-cd.md#accepting-a-finding)) |
| Hooks slow on `/mnt/c` or `/mnt/d` | Cross-filesystem access from WSL | Work in a clone on the WSL filesystem |

## 9. Bypassing a hook (exceptional)

> [!WARNING]
> Bypassing is for emergencies, not for convenience. CI runs every check
> anyway, so a bypassed problem still blocks the pull request; never bypass
> `gitleaks` or `forbid-sensitive-files` to commit a real secret or a state
> file.

Acceptable cases: a broken hook environment or an unavailable tool while an
urgent fix must be committed, or a confirmed false positive whose fix (rule
change, allowlist entry) is in progress. Then:

1. Skip only the affected hook: `SKIP=<hook-id> git commit -m "..."`
   (comma-separated IDs for several).
2. Only if pre-commit itself is broken: `git commit --no-verify` skips every
   hook.
3. Say which hook was skipped and why in the commit message or the pull
   request, and fix the cause right after (repair the environment with
   `pre-commit clean`, or correct the configuration).

## 10. Maintenance

**Updating hook versions** (dedicated pull request):

1. `pre-commit autoupdate` (writes the latest release tags), or edit `rev:`
   by hand to choose a version; read the release notes.
2. Gitleaks and actionlint must keep the versions of `ci/tool-versions.env`:
   update both files together (with the new SHA-256 there).
3. pre-commit itself: `PRE_COMMIT_VERSION` in `ci/tool-versions.env`.
4. terraform-docs: the `@vX.Y.Z` of the `terraform-docs` hook dependency and,
   if needed, the `version` constraint of `.terraform-docs.yml`; run
   `pre-commit run terraform-docs --all-files` and commit any regenerated
   block.
5. Validate: `pre-commit run --hook-stage manual --all-files` and
   `python3 -m unittest discover -s ci/tests`.

**Conventions** (enforced by `ci/tests/test_precommit.py`):

* Remote hooks are pinned to a release tag or a commit SHA, extra
  dependencies to an exact version.
* Commit-stage hooks must stay fast and work offline once installed.
  Anything that downloads providers, runs Terraform or scans goes to
  `pre-push` or `manual`, and calls `ci/scripts` rather than reimplementing
  a CI gate.
* A new project in `ci/projects/` is picked up by `ci/scripts/pre-commit-hook.sh`
  automatically, but must be added to the `files:` filter of the Terraform
  and scanner hooks.
* A new reusable module needs a README with the generated-docs markers.
