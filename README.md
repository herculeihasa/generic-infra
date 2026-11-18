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
| [`docs/pre-commit.md`](docs/pre-commit.md) | Local Git hooks (pre-commit): what runs when, installation (Linux/WSL/Windows), manual runs, generated documentation, bypass policy |
| [`docs/history-rewrite.md`](docs/history-rewrite.md) | 2026-11-18 history rewrite that removed the test suites: scope, verification, what clones and forks must do |
| [`ci/`](ci) | Shared pipeline scripts, pinned tool versions, project manifests, policies |
| [`.github/workflows/`](.github/workflows) | `az-infra-generic.yml`, `tp-local.yml` (callers), the reusable `_terraform-quality.yml`, `_terraform-plan.yml`, `_terraform-apply.yml`, and the repository-wide `pre-commit.yml` |

Common standards: Terraform 1.17.2 pinned per project, committed provider lock
files, modules declaring minimum versions only, `terraform validate` with
read-only lock files, SHA-pinned GitHub Actions and checksum-verified CI
tools, LF line endings, no credentials in the repository, pre-commit hooks
for formatting, linting, secrets and generated documentation.

Quick start for the checks (Linux/WSL, repository root):

```bash
ci/scripts/install-tools.sh
ci/scripts/run-local.sh az-infra-generic
ci/scripts/run-local.sh tp-local
```

## Developer workflow

Install the Git hooks once per clone (Linux/WSL; details and Windows notes in
[`docs/pre-commit.md`](docs/pre-commit.md)):

```bash
pipx install "pre-commit==4.7.0"
pre-commit install                                 # commit + push hooks
pre-commit run --hook-stage manual --all-files     # every hook incl. scanners, on demand
```

Commits then check formatting, syntax, secrets, Markdown and the generated
module documentation; pushes validate and lint the affected Terraform roots
and run the repository policy checks.
CI repeats every check and remains authoritative.

## Documentation map

| Kind | Where | Maintained |
|---|---|---|
| Generated reference of the Terraform modules (requirements, providers, resources, inputs, outputs) | `<project>/modules/<module>/README.md`, between the `BEGIN_TF_DOCS` / `END_TF_DOCS` markers | by terraform-docs (pre-commit hook; CI fails when stale) |
| Technical documentation (architecture, usage, examples, reference explanations) | project and module READMEs (outside the markers), `docs/` | by hand |
| Operational runbooks (procedures with status, validation, rollback) | `<project>/docs/runbooks/` | by hand, links and references checked by `ci/scripts/check-repo.py docs` |
