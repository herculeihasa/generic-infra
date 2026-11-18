# tp-local runbooks

Operational documentation for the local Kubernetes infrastructure: a
**MicroK8s** cluster inside **WSL2 Ubuntu**, provisioned and configured with
Terraform, with a Kubernetes and Helm layer on top. Written for DevOps
engineers who need to build, operate, troubleshoot and rebuild the
environment on a Windows workstation.

> [!IMPORTANT]
> **Execution status: never run on a real WSL instance.** The authoring
> machine had WSL installed but no Linux distribution. Terraform
> configurations, plans and the provisioning scripts were validated offline
> (mocked providers, stubbed `snap`/`microk8s`/`sudo`); every command that
> needs WSL Ubuntu, MicroK8s, kubectl or Helm is marked *Pending external
> prerequisites*. The first operator to run them should report deviations and
> update these runbooks.

## How to use these runbooks

* New to the project: read [01 Architecture](01-architecture.md) first, then
  follow the setup runbook in order.
* Every command block states its **execution context**:
  **PowerShell** (Windows host), **WSL** (Ubuntu shell, as your user),
  **WSL (sudo)** (elevated), or a **Terraform root** directory. Paths such as
  `tp-local/...` are relative to the repository root.
* Procedures have an identifier (e.g. `MK-04`) and a status, and follow the
  sections *Purpose, Prerequisites, Context, Procedure, Expected result,
  Validation, Troubleshooting, Rollback, References* where applicable.
* The code is the source of truth; the [project README](../../README.md)
  holds reference tables that these runbooks do not duplicate.

## Status legend

| Status | Meaning |
|---|---|
| **Validated** | Executed successfully during development (offline: `terraform validate`/`test`, stubbed script suite, Windows host check) |
| **Implemented** | Supported by the code; not executed end to end |
| **Pending external prerequisites** | Requires a WSL Ubuntu distribution, the running cluster, a self-hosted runner or GitHub configuration |
| **Not implemented** | Not supported; do not attempt |
| **Planned** | Recommended evolution, not implemented |

## Document map

| # | Runbook | Covers |
|---|---|---|
| 01 | [Architecture](01-architecture.md) | Windows/WSL/MicroK8s/Terraform/Kubernetes/Helm layers, state, kubeconfig, add-ons, ownership |
| 02 | [WSL initial setup](02-wsl-initial-setup.md) | Windows prerequisites, WSL2, Ubuntu, packages, Terraform, first cluster bootstrap, access |
| 03 | [MicroK8s operations](03-microk8s-operations.md) | Readiness, services, nodes, pods, logs, add-ons, start/stop |
| 04 | [Terraform operations](04-terraform-operations.md) | Both stages: init, plan, apply, outputs, state, destroy, ordering |
| 05 | [Kubernetes and Helm](05-kubernetes-and-helm.md) | Namespaces, RBAC, resources, Helm releases, health |
| 06 | CI/CD and local deployment (in progress) | Hosted vs self-hosted runner, WSL runner, approvals |
| 07 | Troubleshooting and recovery (in progress) | Diagnosis by symptom, cluster/state recovery, rebuild |
| 08 | Maintenance and lifecycle (in progress) | Upgrades, backups, reset, full recreation |

## Environment reference

Values come from the code (defaults of `bootstrap/variables.tf`,
`environments/dev/terraform.tfvars`, `scripts/tf-init.sh`).

| Item | Value | Source |
|---|---|---|
| Windows distribution | `Ubuntu-24.04` (WSL 2) | `scripts/host/Test-WslHost.ps1` |
| Terraform CLI | 1.17.2 | `.terraform-version` |
| Providers (stage 2) | `hashicorp/kubernetes` 3.5.0, `hashicorp/helm` 3.3.0 | `environments/dev/.terraform.lock.hcl` |
| MicroK8s snap channel | `1.35/stable` (classic confinement) | `bootstrap/variables.tf` |
| Add-ons managed by Terraform | `dns`, `rbac`, `hostpath-storage`, `metrics-server`, `ingress` | `bootstrap/variables.tf` |
| Kubeconfig | `~/.kube/tp-local-microk8s.yaml` (mode 0600), context `microk8s`, server `https://127.0.0.1:16443` | `modules/microk8s/scripts/export-kubeconfig.sh` |
| Terraform state | `~/.local/state/tp-local/bootstrap.tfstate`, `~/.local/state/tp-local/environments-dev.tfstate` | `scripts/tf-init.sh` |
| Namespaces | `apps` (isolated, quota), `sandbox` (open) | `environments/dev/terraform.tfvars` |
| StorageClasses | `microk8s-hostpath` (add-on), `microk8s-hostpath-retain` (Terraform) | `environments/dev/main.tf` |
| Smoke-test release | `podinfo` 6.17.0 in `apps`, host `podinfo.localtest.me`, ingress class `public` | `environments/dev/terraform.tfvars` |
| Pipeline | `.github/workflows/tp-local.yml` | [pipeline documentation](../../../docs/ci-cd.md) |

## Quick reference

| I need to… | Go to |
|---|---|
| Understand the layers and who manages what | [01 Architecture](01-architecture.md) |
| Set up a new workstation from scratch | [02 SET-01..11](02-wsl-initial-setup.md) |
| Install MicroK8s the first time | [02 SET-07](02-wsl-initial-setup.md#set-07-install-microk8s-with-terraform-stage-1) |
| Use kubectl (WSL or Windows) | [02 SET-10](02-wsl-initial-setup.md#set-10-configure-kubernetes-access) |
| Check that the cluster is healthy | [03 MK-01](03-microk8s-operations.md#mk-01-check-cluster-readiness) |
| Look at services, pods and logs | [03 MK-02..05](03-microk8s-operations.md#mk-02-check-microk8s-services) |
| Stop, start or restart MicroK8s | [03 MK-06 / MK-07](03-microk8s-operations.md#mk-06-stop-and-start-the-cluster) |
| Enable or disable an add-on | [03 MK-08](03-microk8s-operations.md#mk-08-manage-add-ons) |
| Initialize Terraform with the right state | [04 TF-01](04-terraform-operations.md#tf-01-initialize-a-root) |
| Know what a plan will change | [04 TF-03](04-terraform-operations.md#tf-03-plan-stage-1), [TF-05](04-terraform-operations.md#tf-05-plan-and-apply-stage-2) |
| Re-run a provisioning step (kubeconfig, add-on) | [04 TF-08](04-terraform-operations.md#tf-08-re-run-a-provisioning-step) |
| Destroy the environment | [04 TF-10](04-terraform-operations.md#tf-10-destroy) |
| Add a namespace or change quotas/isolation | [05 K8S-01 / K8S-02](05-kubernetes-and-helm.md#k8s-01-add-change-or-remove-a-namespace) |
| Grant permissions to a service account | [05 K8S-03](05-kubernetes-and-helm.md#k8s-03-manage-rbac) |
| Install, upgrade or roll back a Helm release | [05 K8S-06..08](05-kubernetes-and-helm.md#k8s-06-install-a-release) |
| Check an application's health | [05 K8S-10](05-kubernetes-and-helm.md#k8s-10-check-deployment-health) |
