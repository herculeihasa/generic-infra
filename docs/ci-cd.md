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
| Plan reuse between approval and apply | Workflow artifacts (plan file + JSON + summary) |

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
└── tests/                    unit tests of the Python helpers
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
| | Initialisation + lock-file consistency | `terraform init -backend=false -lockfile=readonly` | lock file missing a provider/platform or inconsistent with constraints | yes |
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

Defined with the plan and apply stages implementation.

## 7. Runners

| Work | Runner | Why |
|---|---|---|
| Stages 1-3 for both projects | GitHub-hosted `ubuntu-24.04` | Nothing environment-specific; isolated, ephemeral |
| Azure plan/apply (`az-infra-generic`) | GitHub-hosted, OIDC to Azure | Azure APIs are reachable from the internet |
| MicroK8s plan/apply/integration (`tp-local`) | **Self-hosted runner inside the WSL distribution** (`[self-hosted, linux, wsl, microk8s]`) | A hosted runner cannot reach a cluster on a laptop; the local state also lives there |

## 8. Status

The pipeline definitions are implemented incrementally; see the following
sections of this document as they are added.
