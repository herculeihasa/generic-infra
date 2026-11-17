# azure-infra

Infrastructure as Code repository with two Terraform projects that follow the
same engineering standards, and a shared CI/CD pipeline.

| Path | Content |
|---|---|
| [`az-infra-generic/`](az-infra-generic/README.md) | Generic Azure infrastructure: reusable AKS module, Azure Blob Storage remote state, `dev` environment |
| [`tp-local/`](tp-local/README.md) | Local Kubernetes: MicroK8s inside WSL2 provisioned by Terraform, Kubernetes and Helm layers |
| [`docs/ci-cd.md`](docs/ci-cd.md) | Pipeline architecture, quality and security gates, deployment authorization |
| [`ci/`](ci) | Shared pipeline scripts, pinned tool versions, project manifests, policies |
| `.github/workflows/` | GitHub Actions workflows |

Common standards: Terraform 1.17.2 pinned per project, committed provider lock
files, modules declaring minimum versions only, `terraform test` suites with
mocked providers, LF line endings, no credentials in the repository.
