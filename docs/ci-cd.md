# CI/CD for the Terraform projects

Pipeline architecture shared by [`az-infra-generic`](../az-infra-generic) (Azure, AKS)
and [`tp-local`](../tp-local) (MicroK8s in WSL).

**Principle:** no Terraform change reaches an environment unless it passed
every quality and security gate, produced a reviewed plan, and was approved
by an authorized person. A successful plan never implies an apply.

## 1. Platform decision

The repository is hosted on **GitHub** and had no pipeline. **GitHub Actions**
is used because it gives, without extra infrastructure:

| Need | GitHub Actions feature |
|---|---|
| Shared logic for two projects | Reusable workflows (`workflow_call`) + shared scripts |
| Manual approval, per-environment permissions, production rules | **Environments**: required reviewers, prevent self-review, deployment branch rules, wait timers, environment-scoped secrets/variables |
| Secretless Azure authentication | OpenID Connect federation (`id-token: write`), consumed by Terraform through `ARM_USE_OIDC` |
| Local MicroK8s cluster | **Self-hosted runner** installed in the WSL distribution, targeted by labels |
| Plan reuse between approval and apply | Workflow artifacts (saved plan + readable plan + summary + metadata) |

Azure DevOps Pipelines would offer equivalent features (stages, environments
with checks, service connections); it would only be preferable if the
repository moved to Azure Repos.

## 2. Architecture

```
.github/workflows/
├── az-infra-generic.yml      caller: triggers + Azure-specific plan/apply jobs
├── tp-local.yml              caller: triggers + WSL self-hosted jobs
├── _terraform-quality.yml    reusable: stages 1-3 (validation, lint, security)
├── _terraform-plan.yml       reusable: stage 4 (plan, destructive-change report)
└── _terraform-apply.yml      reusable: stage 5 (approved apply of the saved plan)
ci/
├── tool-versions.env         pinned tool versions + SHA-256
├── projects/<project>.json   per-project manifest (roots, compat checks, script tests, deployments)
├── scripts/                  logic shared by CI and local runs (bash + Python stdlib)
├── policies/                 policy-as-code (custom Checkov policies)
└── tests/                    unit tests (helpers, plan report, apply guard) + workflow/security policy tests
.github/dependabot.yml        weekly PRs for action SHA pins and Terraform providers
.gitleaks.toml  .checkov.yaml  .shellcheckrc        repository-level scanner configuration
<project>/.tflint.hcl  .checkov.yaml  .checkov-<env>.yaml  .trivyignore.yaml   project-level configuration
docs/ci-cd.md                 this document
```

* **One implementation, two projects.** Callers only declare triggers and
  project-specific jobs; everything else is parameterised by the project
  name and its manifest.
* **Scripts over inline YAML.** Every gate is a script in `ci/scripts/`, so
  the exact same checks run locally (`ci/scripts/run-local.sh`), in WSL, and
  in GitHub Actions.
* **Pinned supply chain.** Actions are referenced by full commit SHA; tools
  are downloaded by version and verified against a pinned SHA-256.

## 3. Stages and quality gates

| Stage | Gate | Tool | Failure condition | Blocking |
|---|---|---|---|---|
| 1 Source & configuration | Change detection | `ci.py changes` (git diff) | — (selects the Terraform roots to check) | — |
| | Formatting | `terraform fmt -check -recursive` | any unformatted file | yes |
| | Initialisation + lock-file consistency | `terraform init -backend=false -lockfile=readonly` | committed lock file missing a provider or inconsistent with the constraints (4-platform `azurerm` coverage is checked by the Azure static checks) | yes |
| | Validation | `terraform validate` | any error | yes |
| | Unit tests | `terraform test` (mocked providers), script suites | any failed run | yes |
| | Version compatibility | validate + test with the oldest supported Terraform (`TERRAFORM_MIN_VERSION`) on modules | any failure | yes |
| 2 Static analysis | Terraform lint | TFLint (`terraform` recommended preset, `azurerm` ruleset for Azure) | any issue of severity ≥ warning | yes |
| | Shell lint | ShellCheck | any finding | yes |
| | Workflow lint | actionlint | any finding | yes |
| 3 Security & compliance | Secrets | Gitleaks (Git history of the change) | any finding | yes |
| | IaC misconfiguration | Trivy `config` | any **HIGH** or **CRITICAL** finding not explicitly accepted | yes (MEDIUM/LOW reported only) |
| | Compliance policies | Checkov (built-in + custom policies, Terraform/Kubernetes/GitHub Actions) | any failed check not explicitly accepted | yes |
| 4 Plan | Plan | `terraform plan -out` + `terraform show -json` | plan error | yes |
| | Destructive changes | `ci.py plan-report` | delete/replace detected | blocks the apply unless explicitly allowed |
| | Plan policies | Checkov on the plan JSON | any failed check | yes |
| 5 Deployment | Authorization | GitHub environment (reviewers, branch rule) | not approved | yes |
| | Apply | `terraform apply <saved plan>` | stale plan or error | yes |

Gate thresholds are deliberately strict: a finding is either **fixed** or
**accepted explicitly** in a reviewed suppression file with a justification
(see §5); thresholds are never lowered to make a pipeline pass.

## 4. Tool selection and overlap

| Concern | Selected | Not duplicated by | Rationale |
|---|---|---|---|
| Terraform syntax/semantics | `terraform validate` / `test` | — | Native, authoritative |
| Terraform & provider lint | **TFLint** | — | Catches provider-specific errors (invalid VM sizes, deprecated syntax, unused declarations) that security scanners ignore |
| Secrets in Git history | **Gitleaks** | Trivy/Checkov secret scanners disabled | Scans commits, not just the working tree |
| Misconfiguration, severity-ranked | **Trivy** `config` | — | Built-in severities give a clear HIGH/CRITICAL threshold; covers Terraform and Kubernetes |
| Compliance & policy-as-code | **Checkov** | — | Largest Azure/Kubernetes policy set, custom YAML policies, scans GitHub Actions workflows and **Terraform plan JSON** |

Trivy and Checkov overlap on Terraform misconfiguration. Both are kept, with
distinct roles: Trivy is the **severity gate** (open-source Checkov has no
severities), Checkov is the **policy-as-code gate** (custom rules, workflow
hardening, plan-level checks on resolved values). Each finding is triaged in
the tool that reported it.

## 5. Security policy

### Failure conditions

| Scanner | Scope | Blocking condition | Reports |
|---|---|---|---|
| Gitleaks | Commits of the PR (`base..head`) or push (`before..sha`); full history on manual/scheduled runs | any secret | `gitleaks.sarif` |
| Trivy `config` | Project directory (Terraform; Kubernetes manifests when present) | any HIGH/CRITICAL not accepted in `<project>/.trivyignore.yaml` | `trivy.sarif` (all severities), HIGH/CRITICAL and LOW/MEDIUM tables |
| Checkov | Project directory (`terraform` framework) + custom policies | any failed check not accepted in `<project>/.checkov.yaml` | `checkov-<project>.sarif` |
| Checkov | `.github/workflows` (`github_actions` framework) | any failed check not accepted in `/.checkov.yaml` | `checkov-workflows.sarif` |
| Checkov | Terraform plan JSON (stage 4) | any failed check | `checkov-<project>-plan.sarif` |

Reports are uploaded as the `security-reports-<project>` artifact (14 days).
All scanners run even when an earlier one failed, so one run lists every
finding. Secret scanning runs on every change, documentation included.

### Policy-as-code (custom Checkov policies, `ci/policies/checkov/`)

| ID | Rule |
|---|---|
| `CKV2_AZINFRA_1` | Storage accounts: Shared Key disabled, TLS 1.2, infrastructure encryption |
| `CKV2_AZINFRA_2` | AKS: Kubernetes RBAC, OIDC issuer, local accounts disabled |
| `CKV2_AZINFRA_3` | Helm releases: explicit repository and pinned chart version |
| `CKV2_AZINFRA_4` | Kubernetes service accounts: no API token automount |

### Accepting a finding

A finding is **fixed** by default. Accepting it is a reviewed code change:

* **Checkov:** add the check ID to `skip-check` in the relevant
  `.checkov.yaml`, preceded by a comment explaining why (enforced by
  `ci/tests/test_security_config.py`).
* **Trivy:** add an entry to `<project>/.trivyignore.yaml` with `id`,
  `paths` (scoped), `statement` (justification) and `expired_at`. When it
  expires the finding fails the pipeline again (also enforced by tests).
* Thresholds are never lowered; scanners are never disabled to pass.

Currently accepted (all about optional hardening the code supports but `dev`
does not enable yet):

| Where | Finding | Reason | Exit path |
|---|---|---|---|
| az-infra-generic (Checkov) | AKS authorized IP ranges / private cluster (`CKV_AZURE_6`, `CKV_AZURE_115`), Free SKU (`CKV_AZURE_170`), CMK disks, host encryption, ephemeral OS disk, max pods (`CKV_AZURE_117/227/226/168`) | Module inputs exist; dev keeps cost-effective, reachable defaults | Enable in the environment; production plan check (stage 4) |
| az-infra-generic (Checkov) | State storage CMK, private endpoint, default Deny, public access, queue logging, SAS policy (`CKV2_AZURE_1/33`, `CKV_AZURE_35/59/33`, `CKV2_AZURE_41`) | Entra ID-only account, Shared Key disabled, no queue usage | `allowed_ip_ranges` / private endpoint when runner IPs exist |
| az-infra-generic (Trivy) | `AVD-AZU-0041` (AKS API authorized IPs), `AVD-AZU-0012` (storage default action) | Same as above | Expire 2027-03-31 |
| repository (Checkov) | `CKV_GHA_7` (workflow_dispatch inputs) | Typed inputs needed for manual, authorized operations; never interpolated into scripts | — |

### Secret exposure procedure

If Gitleaks reports a real secret: revoke/rotate it immediately (the
history is already exposed to anyone with read access), then remove it from
history and re-run the scan. Never allowlist a real secret.

## 6. Deployment authorization

A plan never deploys by itself. An apply needs **all** of the following:

| Layer | Mechanism |
|---|---|
| Quality gates passed | Plan jobs depend on the `quality` gate (and on `azure-config` for Azure); any failed gate skips plan and apply |
| Trusted ref and event | Apply jobs run only on `push`/`workflow_dispatch` from `refs/heads/main` (never on pull requests or other branches); enforced in the callers, re-checked by `ci.py apply-guard`, and by policy tests |
| Manual approval | Apply jobs are bound to a GitHub **environment** with required reviewers (`azure-dev`, `azure-prod`, `tp-local`) |
| Environment-specific permissions | Each environment holds its own identity (`AZURE_CLIENT_ID`…): read-only identity in `*-plan` environments, deployment identity in the approval environments; deployment branch rule `main` |
| Production rules | `prod` only on manual dispatch with `environment: prod`; `azure-prod` requires reviewers (≥ 2 recommended, *prevent self-review*, optional wait timer); stricter plan policies (`.checkov-prod.yaml`) |
| Reviewed plan reused | The plan job uploads the saved plan; the apply job downloads **that** file and runs `terraform apply <planfile>` |
| Plan/commit consistency | The guard refuses a plan produced for another commit; Terraform refuses a stale plan (state changed since review) |
| Destructive changes | `ci.py plan-report` lists deletions/replacements in the run summary; the guard refuses them unless the run was dispatched with `allow-destroy: true` |
| No concurrent applies | Per-environment concurrency group, never cancelled |

### Plan review

Each plan job publishes, in the run summary, the change counts and every
destructive change, and uploads an artifact `tfplan-<project>-<root>-<env>`
(saved plan, readable `tfplan.txt`, `summary.md`, `plan-meta.json`; 5-day
retention). Reviewers approve the environment deployment after reading it.
The JSON plan is used inside the job only (Checkov plan scan, report),
because it can contain sensitive values in clear text; the binary plan can
too, hence the short retention and the private-repository requirement.

### Azure identities (to create when Azure access exists)

| GitHub environment | Identity roles (least privilege) | Branch rule | Reviewers |
|---|---|---|---|
| `azure-dev-plan` | Reader on the dev resource group(s) or subscription, *Azure Kubernetes Service Cluster User Role* (the provider reads cluster credentials during refresh), *Storage Blob Data Reader* on `tfstate-dev` (plans run with `-lock=false`) | any (PR plans) | none |
| `azure-dev` | Contributor + *Role Based Access Control Administrator* on the subscription (creates the resource group and role assignments), *Storage Blob Data Contributor* on `tfstate-dev` | `main` | ≥ 1 |
| `azure-prod-plan` / `azure-prod` | Same pattern on the production scope and `tfstate-prod` | `main` | ≥ 2, prevent self-review |

Each identity is a user-assigned managed identity (or app registration) with
a **federated credential** for `repo:<owner>/<repository>:environment:<github-environment>`.
No client secret is created. Environment variables: `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `TF_STATE_STORAGE_ACCOUNT`
unless `environments/<env>/backend.hcl` is committed. Then set the repository
variable `AZURE_DEPLOYMENT_ENABLED=true`.

### tp-local

`tp-local-plan` (no reviewer) and `tp-local` (required reviewer: you) are
GitHub environments used by the self-hosted jobs; no secret is needed (local
state, kubeconfig in the runner user's home).

## 7. Runners

| Work | Runner | Why |
|---|---|---|
| Stages 1-3 for both projects | GitHub-hosted `ubuntu-24.04` | Nothing environment-specific; isolated, ephemeral |
| Azure plan/apply (`az-infra-generic`) | GitHub-hosted, OIDC to Azure | Azure APIs are reachable from the internet |
| MicroK8s plan/apply/integration (`tp-local`) | **Self-hosted runner inside the WSL distribution** (`[self-hosted, linux, wsl, microk8s]`) | A hosted runner cannot reach a cluster on a laptop; the local state also lives there |

## 8. az-infra-generic pipeline

Workflow: [`.github/workflows/az-infra-generic.yml`](../.github/workflows/az-infra-generic.yml).

| Trigger | What runs |
|---|---|
| Pull request touching the project or shared CI | Stages 1-3 on the affected roots + Azure static checks |
| Push to `main` | Stages 1-3 on every root + Azure static checks; Azure plan/apply when enabled |
| `workflow_dispatch` (`environment`, `allow-destroy`) | Same as push, for the chosen environment |
| Weekly schedule | Full validation, security re-scan, drift-detection plan when enabled |

**Azure static checks** (`ci.py azure-config`, no credentials needed, every run):
no `client_secret`/`access_key`/`sas_token`/hardcoded subscription or tenant
ID in any `.tf`; each deployable root uses the `azurerm` backend with
`use_azuread_auth = true`, the `tfstate-<environment>` container, a state
key and no `storage_account_name` in `backend.tf`; `backend.hcl` (when
committed) contains only `storage_account_name`; `azurerm` is locked for the
four platforms; the bootstrap creates the environment's state container.

**Azure stages are disabled until configured.** The `azure-readiness` job
only lets plan/apply run when the repository variable
`AZURE_DEPLOYMENT_ENABLED` is `true`; otherwise it reports, in the run
summary, that no Azure stage was executed. Nothing is ever reported as
deployed without an actual apply.

## 9. tp-local pipeline and the self-hosted WSL runner

Workflow: [`.github/workflows/tp-local.yml`](../.github/workflows/tp-local.yml).

| Part | Runner | When |
|---|---|---|
| Stages 1-3 (validation, lint, script tests, security) | GitHub-hosted | Every PR / push touching tp-local or shared CI |
| Readiness decision | GitHub-hosted | Always; explains in the summary why local stages did or did not run |
| Preflight, plan, approval, apply, integration tests | **Self-hosted, in WSL** (`[self-hosted, linux, wsl, microk8s]`) | Only `workflow_dispatch` from `main` with `local-deploy: true`, and only if `TP_LOCAL_RUNNER_ENABLED=true` |

A GitHub-hosted runner never targets the local cluster: it cannot reach it,
and the local state lives on the WSL machine.

### Setting up the self-hosted runner (WSL Ubuntu)

Prerequisites: the tp-local WSL setup is done (`prepare-wsl.sh`), the
cluster was bootstrapped once **interactively** (first install needs
`sudo`), and the runner user is the cluster owner (member of the
`microk8s` group, same `$HOME`, so it shares
`~/.local/state/tp-local` and `~/.kube/tp-local-microk8s.yaml`).

```bash
# WSL Ubuntu, as the cluster owner (not root)
mkdir -p ~/actions-runner && cd ~/actions-runner
# Download the Linux x64 runner package shown in GitHub:
#   Settings > Actions > Runners > New self-hosted runner (verify its SHA-256)
./config.sh --url https://github.com/<owner>/<repository> --token <registration-token> \
  --name wsl-tp-local --labels wsl,microk8s --unattended
sudo ./svc.sh install "$USER" && sudo ./svc.sh start   # systemd service, runs as $USER
```

Then set the repository variable `TP_LOCAL_RUNNER_ENABLED=true`.

**Runner security rules:**

* Use it with a **private repository** only: workflows from pull requests
  could otherwise target the runner and execute code on your machine.
* Jobs on the runner only run on `workflow_dispatch` from `main`
  (enforced in the workflow and by `ci/tests/test_workflows.py`).
* Do not grant the runner user passwordless sudo: steps needing root
  (first install, channel change, uninstall) stay interactive and fail with
  an explicit "run sudo -v" message in CI.
* The machine must be on (and WSL running) for the job to start; queued jobs
  expire after 24 hours.

## 10. Required configuration (GitHub)

No secret is required by the pipelines. Identifiers are **variables**.

| Name | Kind | Scope | Purpose |
|---|---|---|---|
| `AZURE_DEPLOYMENT_ENABLED` | variable (`true`) | repository | Enables Azure plan/apply jobs |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | variables | environments `azure-<env>-plan`, `azure-<env>` | OIDC identity of the job (different per environment) |
| `TF_STATE_STORAGE_ACCOUNT` | variable | same environments | State account, if `environments/<env>/backend.hcl` is not committed |
| `TP_LOCAL_RUNNER_ENABLED` | variable (`true`) | repository | A self-hosted WSL runner is registered |
| Environments | `azure-dev-plan`, `azure-dev`, `azure-prod-plan`, `azure-prod`, `tp-local-plan`, `tp-local` | repository settings | Approvals and deployment branch rules (§6) |
| `GITHUB_TOKEN` | automatic | — | Read-only (`contents: read`); also used by TFLint to download plugins |

Workflow permissions are `contents: read` by default; only plan/apply jobs
add `id-token: write` (OIDC).

## 11. Executing the pipelines

| Goal | How |
|---|---|
| Validate a change | Open a pull request: stages 1-3 run for the affected project(s); same-repo PRs also get a dev plan when Azure is enabled |
| Deploy Azure dev | Merge to `main` (or *Run workflow* → `az-infra-generic`, `environment: dev`) → review the plan summary/artifact → approve `azure-dev` |
| Deploy Azure prod | *Run workflow* → `az-infra-generic`, `environment: prod` (from `main`) → review → approval by the `azure-prod` reviewers |
| Authorize deletions/replacements | Re-run via *Run workflow* with `allow-destroy: true` (still requires approval) |
| Deploy tp-local | WSL runner online → *Run workflow* → `tp-local`, `local-deploy: true` → approve `tp-local` for each stage → integration tests |
| Drift detection (Azure) | Weekly schedule: plan only, summary shows any drift; nothing is applied |

### Running the gates locally

```bash
# Linux / WSL (x86_64): install the pinned, checksum-verified tools once
ci/scripts/install-tools.sh            # tflint trivy gitleaks actionlint checkov
ci/scripts/run-local.sh az-infra-generic
ci/scripts/run-local.sh tp-local
python3 -m unittest discover -s ci/tests
```

`run-local.sh` runs the same scripts as CI; gates whose tool is missing are
shown as SKIPPED (they still run in CI).

### Recommended branch protection for `main`

Require a pull request with at least one approval, require the status checks
`az-infra-generic / quality / quality gate`, `tp-local / quality / quality gate`
and `az-infra-generic / 2 · Azure provider & backend checks`, dismiss stale
approvals, block force pushes. Add a CODEOWNERS file so that changes to
`ci/`, `.github/`, `.checkov*.yaml` and `.trivyignore.yaml` (the security
policy itself) require the platform owner's review.

## 12. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `terraform fmt` gate fails | Run `terraform fmt -recursive <project>` and commit |
| `init failed … lock file inconsistent` | Provider constraint changed without updating the lock: `terraform init -upgrade -backend=false` then `terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64` |
| Minimum-version job fails, latest passes | A feature newer than `TERRAFORM_MIN_VERSION` is used: raise the module `required_version` (and `TERRAFORM_MIN_VERSION`) or avoid the feature |
| TFLint/ShellCheck/actionlint finding | Fix it; for an intentional exception use the tool's inline ignore with a comment explaining why |
| Trivy HIGH/CRITICAL | Fix, or accept in `<project>/.trivyignore.yaml` (path-scoped, justified, with `expired_at`) |
| Checkov failed check | Fix, or add the ID to the relevant `.checkov*.yaml` with a justification comment |
| Gitleaks finding | Treat as a leaked secret: rotate first, then clean the history (§5) |
| `Azure authentication not configured` | Environment variables `AZURE_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` missing on the GitHub environment, or federated credential subject mismatch (`repo:<owner>/<repo>:environment:<name>`) |
| `backend not configured` | Commit `environments/<env>/backend.hcl` (bootstrap output) or set `TF_STATE_STORAGE_ACCOUNT` |
| `AuthorizationPermissionMismatch` at init | Missing *Storage Blob Data* role on `tfstate-<env>`, or not yet propagated |
| Plan 403 on `listClusterUserCredential` | Plan identity lacks *Azure Kubernetes Service Cluster User Role* |
| Apply refused: `plan was produced for …` | Re-run the pipeline: plans are tied to a commit |
| Apply refused: destructive plan | Check the listed resources; re-run with `allow-destroy: true` if intended |
| `Saved plan is stale` | The state changed after review: re-run to plan again |
| Local stages skipped | See the readiness summary: not a dispatch from `main`, `local-deploy` unchecked, or `TP_LOCAL_RUNNER_ENABLED` not set |
| Self-hosted job queued forever | The WSL runner is offline: start WSL (`wsl -d Ubuntu-24.04`) and check `sudo ./svc.sh status` in `~/actions-runner` |
| `root privileges are required … sudo -v` on the runner | Expected for install/channel changes: run that bootstrap apply interactively in WSL |

## 13. Status

| Item | State |
|---|---|
| Workflows, scripts, policies, configuration | Implemented |
| Validated locally | Python suites (helpers, plan report incl. a real Terraform plan, apply guard, workflow and security policy tests); every Terraform gate of both projects through `run-local.sh`; plan + guard end to end on `tp-local/bootstrap`; script behaviour suites |
| Not executable here (no tool / access) | TFLint, ShellCheck, actionlint, Gitleaks, Trivy, Checkov, the minimum-version job: their **first GitHub Actions run** is their first execution and establishes the findings baseline (fix or explicitly accept, §5) |
| Pending Azure access | Azure identities, GitHub environments, `AZURE_DEPLOYMENT_ENABLED`; no Azure plan or apply has ever run |
| Pending WSL runner | Self-hosted runner registration, `TP_LOCAL_RUNNER_ENABLED`; no local deployment has run through CI |
