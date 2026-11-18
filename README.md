# generic-infra

Infrastructure as Code repository with two Terraform projects that follow the
same engineering standards, and a shared CI/CD pipeline that blocks any
deployment that has not passed the quality, security and approval gates.

| Path | Content |
|---|---|
| [`az-infra-generic/`](az-infra-generic/README.md) | Generic Azure infrastructure: reusable AKS and Storage Account modules, Azure Blob Storage remote state, `dev` environment |
| [`tp-local/`](tp-local/README.md) | Local Kubernetes: MicroK8s inside WSL2 provisioned by Terraform, Kubernetes and Helm layers |
| [`az-infra-generic/docs/runbooks/`](az-infra-generic/docs/runbooks/README.md) | Azure operational runbooks: setup, state, AKS module, deployments, CI/CD, troubleshooting, security and maintenance |
| [`tp-local/docs/runbooks/`](tp-local/docs/runbooks/README.md) | Local cluster operational runbooks: WSL setup, MicroK8s, Terraform, Kubernetes/Helm, CI/CD, troubleshooting, maintenance |
| [`docs/ci-cd.md`](docs/ci-cd.md) | Pipeline architecture, quality and security gates, deployment authorization, setup, troubleshooting |
| [`ci/`](ci) | Shared pipeline scripts, pinned tool versions, project manifests, policies, tests |
| [`.github/workflows/`](.github/workflows) | `az-infra-generic.yml`, `tp-local.yml` (callers) and the reusable `_terraform-quality.yml`, `_terraform-plan.yml`, `_terraform-apply.yml` |

Common standards: Terraform 1.17.2 pinned per project, committed provider lock
files, modules declaring minimum versions only, `terraform test` suites with
mocked providers, SHA-pinned GitHub Actions and checksum-verified CI tools,
LF line endings, no credentials in the repository.

Quick start for the checks (Linux/WSL, repository root):

```bash
ci/scripts/install-tools.sh
ci/scripts/run-local.sh az-infra-generic
ci/scripts/run-local.sh tp-local
```
