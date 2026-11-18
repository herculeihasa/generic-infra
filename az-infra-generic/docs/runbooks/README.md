# az-infra-generic runbooks

Operational documentation for the generic Azure Terraform project and its
reusable AKS module. It is written for DevOps engineers and infrastructure
operators who need to set up, deploy, operate, troubleshoot, maintain and
recover the infrastructure without prior knowledge of the project.

> [!IMPORTANT]
> **Deployment status: never deployed.** No Azure subscription was available
> while the project was built. Every procedure that calls Azure is marked
> *Pending external prerequisites*: the commands match the Terraform code,
> but none of them has been executed against Azure yet. The first operator
> to run them should report any deviation and update these runbooks.

## How to use these runbooks

* Start with [01 Architecture](01-architecture.md) if the project is new to you.
* Each procedure has an identifier (e.g. `BS-03`), a status, and the
  sections *Purpose, Scope, Prerequisites, Execution context, Procedure,
  Expected result, Validation, Troubleshooting, Rollback, References*
  (sections that do not apply are omitted).
* Commands are shown for **bash** (Linux, WSL, Git Bash, CI) unless marked
  **PowerShell**. Values in `<angle-brackets>` are placeholders to replace.
* The code is the source of truth. Exhaustive reference tables live in the
  [project README](../../README.md) and the
  [pipeline documentation](../../../docs/ci-cd.md); the runbooks link to
  them instead of duplicating them.

## Status legend

| Status | Meaning |
|---|---|
| **Validated** | Executed successfully during development (offline checks: `terraform validate`, `terraform test` with mocked providers, scripts) |
| **Implemented** | Supported by the code; not yet executed end to end |
| **Pending external prerequisites** | Requires Azure access or GitHub configuration that does not exist yet |
| **Not implemented** | Not supported by the code; do not attempt |
| **Planned** | Recommended evolution, not implemented |

## Document map

| # | Runbook | Covers |
|---|---|---|
| 01 | [Architecture](01-architecture.md) | Components, diagrams, files, providers, environments, naming, lifecycle |
| 02 | [Prerequisites and initial setup](02-prerequisites-and-setup.md) | Tools, Azure authentication, permissions, environment variables, initialization |
| 03 | [Backend and state management](03-backend-and-state-management.md) | State bootstrap (Storage Account module), bootstrap state, locking, isolation, inspection, backup, recovery, migration |
| 04 | [AKS module operations](04-aks-module-operations.md) | Module interface, create, update, scale, upgrade, access, destroy |
| 05 | [Deployment procedures](05-deployment-procedures.md) | Full Terraform lifecycle, local and pipeline execution |
| 06 | [CI/CD operations](06-cicd-operations.md) | Pipeline stages, gates, approvals, Azure authentication, troubleshooting |
| 07 | [Troubleshooting and recovery](07-troubleshooting-and-recovery.md) | Diagnosis and resolution by symptom, rollback, partial deployments |
| 08 | [Security and maintenance](08-security-and-maintenance.md) | Credentials, upgrades, versioning, scanning, access reviews, drift |

## Environment reference

Names below are **derived from the code** (`locals.tf` naming
`<abbreviation>-<project>-<environment>-<region code>` with
`project = "azinfra"`, `location = "francecentral"` → `frc`). Values that only
exist after deployment are placeholders.

| Item | Value | Source |
|---|---|---|
| Terraform CLI | 1.17.2 | `.terraform-version` |
| `hashicorp/azurerm` | 5.14.0 (constraint `~> 5.14`) | `environments/dev/.terraform.lock.hcl` |
| Region | `francecentral` | `environments/dev/terraform.tfvars` |
| State resource group | `rg-azinfra-tfstate-frc` | `bootstrap/main.tf` |
| State storage account | `stazinfratfstate<hash6>` (hash of subscription ID, known after bootstrap) | `bootstrap/main.tf` (name), `modules/storage_account/main.tf` (account) |
| State container / key (dev) | `tfstate-dev` / `az-infra-generic/aks.tfstate` | `environments/dev/backend.tf` |
| dev resource group | `rg-azinfra-dev-frc` | `environments/dev/locals.tf` |
| dev AKS cluster | `aks-azinfra-dev-frc` | `environments/dev/locals.tf` |
| dev virtual network / subnet | `vnet-azinfra-dev-frc` (`10.10.0.0/16`) / `snet-aks-nodes` (`10.10.0.0/22`) | `environments/dev/locals.tf`, `terraform.tfvars` |
| dev Log Analytics workspace | `log-azinfra-dev-frc` | `environments/dev/locals.tf` |
| AKS control plane identity | `id-aks-azinfra-dev-frc` | `modules/aks/identity.tf` |
| Pipeline | `.github/workflows/az-infra-generic.yml` | [pipeline documentation](../../../docs/ci-cd.md) |

## Quick reference

| I need to… | Go to |
|---|---|
| Understand what gets deployed | [01 Architecture](01-architecture.md) |
| Prepare a workstation and log in to Azure | [02 SETUP-01..04](02-prerequisites-and-setup.md) |
| Check my Azure permissions | [02 §2](02-prerequisites-and-setup.md#2-required-azure-permissions) |
| Create the Terraform state storage (first time) | [03 BS-01](03-backend-and-state-management.md#bs-01-bootstrap-the-backend) |
| Connect an environment to its state | [03 BS-05](03-backend-and-state-management.md#bs-05-initialize-an-environment-against-the-backend) |
| Back up or recover the bootstrap state | [03 BS-11](03-backend-and-state-management.md#bs-11-store-back-up-and-recover-the-bootstrap-state) |
| Upgrade a bootstrap applied before the storage module | [03 BS-15](03-backend-and-state-management.md#bs-15-upgrade-an-existing-bootstrap-state-to-the-storage-module) |
| Release a stuck state lock | [03 BS-10](03-backend-and-state-management.md#bs-10-release-a-stuck-state-lock) |
| Restore a previous state version | [03 BS-08](03-backend-and-state-management.md#bs-08-restore-a-previous-state-version) |
| Deploy or change dev from my workstation | [05 DEP-01..08](05-deployment-procedures.md) |
| Review a plan for destructive changes | [05 DEP-05](05-deployment-procedures.md#dep-05-review-the-plan) |
| Create the AKS cluster | [04 AKS-01](04-aks-module-operations.md#aks-01-create-the-cluster) |
| Scale or add node pools | [04 AKS-03 / AKS-04](04-aks-module-operations.md#aks-03-scale-node-pools) |
| Upgrade Kubernetes | [04 AKS-05](04-aks-module-operations.md#aks-05-upgrade-kubernetes) |
| Get kubectl access | [04 AKS-07](04-aks-module-operations.md#aks-07-configure-kubernetes-access) |
| Grant cluster access | [04 AKS-08](04-aks-module-operations.md#aks-08-grant-or-revoke-kubernetes-access) |
| Destroy dev | [05 DEP-10](05-deployment-procedures.md#dep-10-destroy-the-environment) |
| Know which checks block a deployment | [06 §2](06-cicd-operations.md#2-checks-that-must-pass-before-a-deployment-is-authorized) |
| Turn on the Azure pipeline stages | [06 CI-01](06-cicd-operations.md#ci-01-enable-the-azure-stages-one-time) |
| Deploy through the pipeline / approve | [06 CI-03..05](06-cicd-operations.md#ci-03-deploy-dev) |
| Authorize a deletion in the pipeline | [06 CI-06](06-cicd-operations.md#ci-06-authorize-a-destructive-change) |
| Diagnose an error message | [07 Troubleshooting and recovery](07-troubleshooting-and-recovery.md) |
| Recover from a failed apply | [07 R-01](07-troubleshooting-and-recovery.md#r-01-recover-from-a-failed-or-partial-apply) |
| Upgrade Terraform or the provider | [08 SEC-03 / SEC-04](08-security-and-maintenance.md#sec-04-upgrade-the-azurerm-provider) |
| Plan recurring maintenance | [08 §2](08-security-and-maintenance.md#2-maintenance-calendar) |
