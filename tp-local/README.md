# tp-local

Local Kubernetes infrastructure as code: a **MicroK8s** cluster inside **WSL2
Ubuntu**, provisioned and configured with Terraform, plus a Kubernetes/Helm
layer ready for DevOps experiments.

> **Status:** implemented and validated offline (formatting and `terraform
> validate`; CI adds TFLint, ShellCheck and the security scanners). It has not
> yet been executed on a real WSL instance: the authoring machine had no WSL
> distribution. See [§11](#11-known-limitations).

Operational procedures (WSL setup, MicroK8s, Terraform, Kubernetes and
Helm, CI/CD, troubleshooting and recovery, maintenance) are in the
[runbooks](docs/runbooks/README.md); this README stays the reference.

## Contents

1. [Architecture](#1-architecture)
2. [Directory structure](#2-directory-structure)
3. [WSL prerequisites](#3-wsl-prerequisites)
4. [MicroK8s installation](#4-microk8s-installation)
5. [Terraform configuration](#5-terraform-configuration)
6. [Kubernetes access](#6-kubernetes-access)
7. [Modules and add-ons](#7-modules-and-add-ons)
8. [Deployment workflow](#8-deployment-workflow)
9. [Validation commands](#9-validation-commands)
10. [Troubleshooting](#10-troubleshooting)
11. [Known limitations](#11-known-limitations)
12. [CI/CD](#12-cicd)

---

## 1. Architecture

| Layer | Runs in | Managed by | Why |
|---|---|---|---|
| WSL2 + Ubuntu distribution, VM resources | **Windows** (PowerShell) | Manual, once (`wsl --install`, `.wslconfig`) | Terraform runs *inside* the distribution and cannot create it |
| systemd, snapd, Terraform CLI | **WSL Ubuntu** (root) | [`scripts/wsl/prepare-wsl.sh`](scripts/wsl/prepare-wsl.sh), idempotent | OS bootstrap; enabling systemd needs a WSL restart |
| MicroK8s: install, channel, add-ons, readiness, kubeconfig | **WSL Ubuntu** | Terraform **stage 1** [`bootstrap/`](bootstrap) → [`modules/microk8s`](modules/microk8s) | Reproducible, versioned cluster configuration |
| Namespaces, RBAC, service accounts, quotas, network policies, storage | **WSL Ubuntu** | Terraform **stage 2** [`environments/dev/`](environments/dev) (`main.tf`) → [`modules/k8s-namespace`](modules/k8s-namespace) | Platform baseline through the Kubernetes provider |
| Applications (Helm charts) | **WSL Ubuntu** | Terraform stage 2 (`helm.tf`), Helm provider | Application layer, applied on top of the baseline |

```text
Windows host
└── WSL2 VM ── Ubuntu 24.04 (systemd)
    ├── snap: microk8s ◄── stage 1: tp-local/bootstrap (terraform_data + scripts)
    │     ├── add-ons: dns, rbac, hostpath-storage, metrics-server, ingress
    │     └── API server https://127.0.0.1:16443
    ├── ~/.kube/tp-local-microk8s.yaml (0600) ──► kubernetes + helm providers
    │                                              stage 2: tp-local/environments/dev
    │                                              ├── namespaces apps / sandbox (+ RBAC, quotas, netpol)
    │                                              ├── StorageClass microk8s-hostpath-retain
    │                                              └── helm_release podinfo (smoke test)
    └── ~/.local/state/tp-local/{bootstrap,environments-dev}.tfstate (local state)
```

**Why two stages?** The Kubernetes provider documentation advises against
creating a cluster and its Kubernetes resources in the same apply: provider
configuration would depend on resources not yet created. Stage 1 creates the
cluster and exports a kubeconfig; stage 2 reads it.

**Why `terraform_data` + scripts for MicroK8s?** No Terraform provider manages
snaps or WSL. Each step is an idempotent script executed at **apply** time
only, so `terraform plan` never touches the machine (and can run in CI).
Terraform does **not** assume MicroK8s exists: stage 1 installs it.

**State:** local backend (the cluster and its state live on the same
machine), stored outside the repository by
[`scripts/tf-init.sh`](scripts/tf-init.sh) in
`${TP_LOCAL_STATE_DIR:-~/.local/state/tp-local}/<root>.tfstate`, so manual
runs and a self-hosted CI runner (same Linux user) share one state.

## 2. Directory structure

```text
tp-local/
├── .terraform-version   .tflint.hcl   .gitignore   .gitattributes (LF: scripts run in WSL)
├── bootstrap/                     # stage 1 (no provider, no lock file)
│   └── versions.tf | variables.tf | main.tf | outputs.tf
├── environments/
│   ├── dev/                       # stage 2
│   │   ├── backend.tf             # local backend, path from scripts/tf-init.sh
│   │   ├── versions.tf | providers.tf | variables.tf | locals.tf
│   │   ├── main.tf                # platform baseline
│   │   ├── helm.tf                # Helm releases
│   │   └── outputs.tf | terraform.tfvars | .terraform.lock.hcl
│   └── rec/                       # empty, reserved
├── modules/
│   ├── microk8s/                  # install, channel, add-ons, readiness, kubeconfig
│   │   └── scripts/               # lib, preflight, install, set-channel, addon, wait-ready,
│   │                              #   export-kubeconfig, uninstall
│   └── k8s-namespace/             # namespace security baseline
└── scripts/
    ├── host/Test-WslHost.ps1      # Windows: read-only host check
    ├── host/wslconfig.example     # Windows: %UserProfile%\.wslconfig sample
    ├── wsl/prepare-wsl.sh         # WSL: one-time OS preparation (sudo)
    ├── tf-init.sh                 # WSL: terraform init with the canonical state path
    └── verify-cluster.sh          # WSL: post-deployment health checks
```

## 3. WSL prerequisites

**Windows host** (PowerShell; *administrator* only for `wsl --install`):

| Requirement | Command |
|---|---|
| Windows 10 22H2+ / Windows 11 with virtualization enabled | — |
| WSL up to date | `wsl --update` |
| Ubuntu 24.04 distribution, WSL **2** | `wsl --install -d Ubuntu-24.04` |
| Enough resources (recommended 6-8 GB RAM, 4 CPUs) | copy [`scripts/host/wslconfig.example`](scripts/host/wslconfig.example) to `%UserProfile%\.wslconfig`, then `wsl --shutdown` |
| Check everything (read-only) | `.\tp-local\scripts\host\Test-WslHost.ps1` |

**Inside Ubuntu** (handled by `prepare-wsl.sh`): systemd as PID 1 (required
by snapd), snapd, Terraform 1.17.2 from the signed HashiCorp repository,
optionally `kubectl`/`helm`. MicroK8s needs about 20 GB of free disk.

Clone the repository **inside the WSL filesystem** (e.g. `~/src`) for speed.
A checkout on `/mnt/c` or `/mnt/e` also works: `.gitattributes` keeps LF line
endings, and scripts are always invoked through `bash`.

## 4. MicroK8s installation

What is automated, and by what:

| Step | Automated by | Privileges |
|---|---|---|
| Distribution install, `.wslconfig` | **manual** (Windows) | Windows admin |
| systemd in `/etc/wsl.conf`, packages, Terraform | `prepare-wsl.sh` | `sudo` |
| `snap install microk8s --channel=…`, group membership | Terraform `bootstrap` (`install.sh`) | cached `sudo -v` (non-interactive `sudo -n`) |
| Channel changes (`snap refresh`) | Terraform `bootstrap` (`set-channel.sh`) | cached `sudo -v` |
| Add-ons, readiness, kubeconfig export | Terraform `bootstrap` | none once in the `microk8s` group |

Terraform cannot answer a password prompt. When root is needed and no
credentials are cached, the scripts stop with an explicit message
("Run 'sudo -v' …") instead of hanging. In the session that just joined the
`microk8s` group, `microk8s` calls fall back to `sudo -n`; later sessions need
no sudo at all.

## 5. Terraform configuration

| Item | Value |
|---|---|
| Terraform | 1.17.2 (`.terraform-version`), roots require `~> 1.17`, modules `>= 1.9` |
| Providers (stage 2) | `hashicorp/kubernetes ~> 3.5` (3.5.0 locked), `hashicorp/helm ~> 3.3` (3.3.0 locked); lock file for 4 platforms |
| Providers (stage 1) | none (built-in `terraform_data`) |
| State | local, `~/.local/state/tp-local/<root>.tfstate` via `scripts/tf-init.sh` |

**Stage 1 (`bootstrap`) inputs:** `microk8s_channel` (`1.35/stable`),
`addons` (recommended set, §7), `kubeconfig_path`
(`~/.kube/tp-local-microk8s.yaml`), `api_server_address` (`127.0.0.1`),
`wait_timeout_seconds` (`600`), `uninstall_on_destroy` (`false`).
Outputs: channel, add-ons, kubeconfig path/context, API URL, next steps.

**Stage 2 (`environments/dev`) inputs** (see `terraform.tfvars`):
`environment`, `kubeconfig_path` / `kubeconfig_context`, `namespaces`
(baseline per namespace), `retain_storage_class_enabled`, `node_labels`,
`helm_releases` (pinned charts, `values_yaml`). Outputs: node health, namespaces,
Helm release status, storage classes.

Nothing sensitive is committed. The kubeconfig (cluster-admin certificate) is
written outside the repository with mode 0600 and never stored in state.

## 6. Kubernetes access

```bash
# WSL Ubuntu
export KUBECONFIG=~/.kube/tp-local-microk8s.yaml   # context "microk8s"
kubectl get nodes                                  # or: microk8s kubectl get nodes
```

* The exported kubeconfig points to `https://127.0.0.1:16443`. The WSL IP
  changes at every restart; 127.0.0.1 is in the API certificate SANs.
* **From Windows:** copy the file
  (`cp ~/.kube/tp-local-microk8s.yaml /mnt/c/Users/<you>/.kube/`) and use
  `kubectl --kubeconfig $HOME\.kube\tp-local-microk8s.yaml get nodes`; WSL
  forwards localhost ports to Windows.
* **Least privilege:** the kubeconfig is cluster-admin. Workloads use the
  namespace-scoped service accounts created in stage 2 (e.g.
  `apps/app-deployer` with `edit` on `apps` only).
* After `microk8s refresh-certs`, re-export:
  `terraform apply -replace='module.microk8s.terraform_data.kubeconfig'` (in `bootstrap/`).

## 7. Modules and add-ons

* [`modules/microk8s`](modules/microk8s/README.md): install, channel, add-ons, readiness, kubeconfig.
* [`modules/k8s-namespace`](modules/k8s-namespace/README.md): Pod Security
  Admission, quota, limits, ingress isolation, service accounts, RBAC.

**Add-ons** (stage 1 `addons`, one Terraform resource each: removing an entry
disables the add-on, keeping volume data):

| Add-on | Default | Why |
|---|---|---|
| `dns` | ✅ | CoreDNS: service discovery, needed by almost everything |
| `rbac` | ✅ | RBAC authorization, so stage 2 Roles/RoleBindings are enforced |
| `hostpath-storage` | ✅ | Dynamic PersistentVolumes (`microk8s-hostpath`, default class) |
| `metrics-server` | ✅ | `kubectl top`, HorizontalPodAutoscaler |
| `ingress` | ✅ | NGINX ingress controller (namespace `ingress`, class `public`) |
| `registry` | ❌ | Local image registry on `localhost:32000`: enable with `registry = { args = ["--size", "20Gi"] }` when building images |
| `dashboard` | ❌ | Extra attack surface and resources; prefer `kubectl`/k9s |
| `observability` | ❌ | Prometheus/Grafana/Loki: heavy for a laptop VM |
| `cert-manager`, `metallb` | ❌ | Useful for specific experiments only |

**Helm:** stage 2 `helm_releases` installs pinned charts (exact version,
https/oci repository) into managed namespaces only, atomically. The default
release, **podinfo 6.17.0** in `apps`, is the Helm and ingress smoke test.

## 8. Deployment workflow

| # | Step | Where | Commands |
|---|---|---|---|
| 1 | Prepare WSL | Windows PowerShell | `wsl --update`; `wsl --install -d Ubuntu-24.04`; optional `.wslconfig` + `wsl --shutdown`; `.\tp-local\scripts\host\Test-WslHost.ps1` |
| 2 | Install dependencies | WSL Ubuntu (repo root) | `sudo tp-local/scripts/wsl/prepare-wsl.sh --with-kubectl-helm`. If it enabled systemd: `wsl --shutdown` in PowerShell, reopen Ubuntu, run it again |
| 3 | Initialise MicroK8s | WSL, `tp-local/bootstrap` | `sudo -v`<br>`../scripts/tf-init.sh bootstrap`<br>`terraform validate`<br>`terraform plan -out=bootstrap.tfplan`<br>`terraform apply bootstrap.tfplan` |
| 4 | Configure Kubernetes access | WSL | `newgrp microk8s` (or reopen the terminal)<br>`export KUBECONFIG=~/.kube/tp-local-microk8s.yaml && kubectl get nodes` |
| 5 | Initialise Terraform (stage 2) | WSL, `tp-local/environments/dev` | `../../scripts/tf-init.sh environments/dev` |
| 6 | Validate | WSL, `tp-local/environments/dev` | `terraform fmt -check -recursive ../..`<br>`terraform validate` |
| 7 | Plan and review | WSL, `tp-local/environments/dev` | `terraform plan -out=dev.tfplan` |
| 8 | Apply | WSL, `tp-local/environments/dev` | `terraform apply dev.tfplan` |
| 9 | Verify cluster health | WSL (repo root) | `tp-local/scripts/verify-cluster.sh` |
| 10 | Kubernetes / Helm connectivity | WSL, `tp-local/environments/dev` | `terraform output nodes helm_releases`<br>`kubectl -n apps get pods,ingress`<br>``curl -H 'Host: podinfo.localtest.me' http://$(hostname -I \| awk '{print $1}')/`` |
| 11 | Destroy safely | WSL | see below |

**Destroying (stage 2 first, then stage 1):**

```bash
# WSL: Kubernetes resources and Helm releases
cd tp-local/environments/dev
terraform plan -destroy -out=destroy.tfplan && terraform apply destroy.tfplan

# WSL: add-ons disabled (data kept), kubeconfig removed, MicroK8s KEPT
cd ../../bootstrap
terraform plan -destroy -out=destroy.tfplan && terraform apply destroy.tfplan

# Full removal including MicroK8s and ALL its data: record the choice in
# state first (destroy-time actions read the stored value), then destroy.
sudo -v
terraform apply -var uninstall_on_destroy=true
terraform destroy -var uninstall_on_destroy=true
```

## 9. Validation commands

Offline (no cluster, no root; also run by CI), from `tp-local/`:

```bash
terraform fmt -check -recursive
for d in bootstrap modules/microk8s modules/k8s-namespace environments/dev; do
  (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform validate)
done
```

Results at the time of writing: validate passes for the 4 configurations.

Live (WSL with the cluster): `terraform plan` in both stages (expect "No
changes" after apply) and `scripts/verify-cluster.sh`, which checks the
kubeconfig, the API server, the nodes, the add-ons, the namespaces, Helm
releases and podinfo through the ingress.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `systemd is not PID 1` | `sudo tp-local/scripts/wsl/prepare-wsl.sh`, then `wsl --shutdown` (PowerShell) and reopen Ubuntu |
| `root privileges are required … Run 'sudo -v'` | `sudo -v`, then re-run the same `terraform apply` (steps are idempotent) |
| `MicroK8s requires Linux` / `/bin/bash` not found | Terraform was run from Windows: run it inside WSL Ubuntu |
| `$'\r': command not found` | CRLF checkout: clone the repository inside WSL (`.gitattributes` forces LF for new checkouts) |
| `permission denied` on `microk8s` | Group membership not active yet: `newgrp microk8s` or reopen the terminal |
| `could not acquire …/tp-local-microk8s.lock` | No other Terraform run active? `rmdir "${XDG_RUNTIME_DIR:-/tmp}/tp-local-microk8s.lock"` |
| `MicroK8s did not become ready` | `microk8s inspect`; `journalctl -u snap.microk8s.daemon-kubelite`; check RAM in `.wslconfig` |
| Snap/image downloads fail behind VPN/proxy | Fix DNS in WSL (`/etc/wsl.conf` `[network] generateResolvConf`), configure the snap proxy (`sudo snap set system proxy.https=…`) |
| Stage 2 plan: `connection refused` or missing kubeconfig | Apply stage 1; after a WSL restart wait for `microk8s status --wait-ready` |
| Cluster stopped after a while | WSL shut the VM down when idle: open a terminal, MicroK8s restarts with systemd |
| Pods rejected: `violates PodSecurity` / `must specify limits` | Namespace baseline at work: add a `securityContext`, or relax `pod_security`; LimitRange provides default resources |
| Helm release failed and was rolled back | `atomic` rollback: `helm history <release> -n apps`, `kubectl get events -n apps` |
| Add-on changed by hand (drift) | Terraform cannot read MicroK8s state: `terraform apply -replace='module.microk8s.terraform_data.addon["ingress"]'` |
| podinfo not reachable from a Windows browser | The ingress listens on the WSL IP (hostPort): `curl -H 'Host: podinfo.localtest.me' http://<WSL IP>/`, or `kubectl -n apps port-forward svc/podinfo 9898` then browse `http://localhost:9898` |

## 11. Known limitations

* **Not yet executed against real WSL/MicroK8s**: validated offline only (no
  WSL distribution was available). The first real run is the acceptance test.
* Single node, no high availability; one environment (`dev`, `rec` reserved).
* Terraform does not detect drift in MicroK8s itself (snap, add-ons):
  `terraform_data` has no read step. Use `verify-cluster.sh` and `-replace`.
* Root operations need cached sudo credentials; a CI runner therefore never
  installs MicroK8s (by design, see [§12](#12-cicd)).
* `uninstall_on_destroy` must be applied before `destroy` (destroy-time
  actions only see the stored value).
* Switching between classic and strict confinement requires a reinstall.
* The exported kubeconfig is cluster-admin; access from Windows relies on WSL
  localhost forwarding; hostPort ingress is reached through the WSL IP.

## 12. CI/CD

Workflow `.github/workflows/tp-local.yml`, documented in
[`../docs/ci-cd.md`](../docs/ci-cd.md) (§9 for the WSL runner):

* **GitHub-hosted runners** (every PR/push): formatting, init with the
  read-only lock file, validate (all 4 configurations), the minimum
  Terraform version job on the modules, TFLint, ShellCheck, Gitleaks, Trivy,
  Checkov. They never touch a cluster.
* **Self-hosted runner inside WSL** (manual *Run workflow* from `main` with
  `local-deploy: true`, repository variable `TP_LOCAL_RUNNER_ENABLED=true`):
  preflight → plan `bootstrap` → approval (`tp-local` environment) → apply
  the saved plan → plan `environments/dev` → approval → apply →
  post-deployment verification (`scripts/verify-cluster.sh`).
* Steps needing root (first install, channel change) cannot run unattended
  and stay interactive (`sudo -v` then `terraform apply` in WSL).

Run the same gates locally: `ci/scripts/run-local.sh tp-local` (repository root).
Commits and pushes made from WSL also run the repository's pre-commit hooks
(formatting, ShellCheck, secrets, Markdown, module references; `validate` and
TFLint on push): see [`docs/pre-commit.md`](../docs/pre-commit.md).
