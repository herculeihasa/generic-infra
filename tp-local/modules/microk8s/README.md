# Module `microk8s`

Installs and configures a single-node **MicroK8s** cluster on the machine that
runs Terraform: a WSL2 Ubuntu distribution, or any systemd-based Ubuntu host.

No Terraform provider manages snaps, so each step is a `terraform_data`
resource running an idempotent script from [`scripts/`](scripts) at **apply**
time. Plans have no side effects; there is no provider and no lock file.

| Resource | Action on create | Action on destroy |
|---|---|---|
| `terraform_data.install` | preflight, `snap install microk8s` (once), `microk8s` group membership, readiness wait | `snap remove --purge` **only if** `uninstall_on_destroy = true` |
| `terraform_data.channel` | `snap refresh --channel` when `channel` changes (in place) | none |
| `terraform_data.addon["<name>"]` | `microk8s enable <name> <args>` | `microk8s disable <name>` (data kept) |
| `terraform_data.ready` | services up, node Ready, Deployments Available, DaemonSets rolled out | none |
| `terraform_data.kubeconfig` | admin kubeconfig exported 0600, server rewritten to `127.0.0.1:16443` | file removed |

Root operations (`snap`, `usermod`) use non-interactive `sudo -n`: run
`sudo -v` before `terraform apply` (credentials cached ~15 minutes). Once the
user is in the `microk8s` group, add-on and kubeconfig changes need no sudo.

## Usage

```hcl
module "microk8s" {
  source = "../modules/microk8s"

  channel = "1.35/stable"
  addons = {
    dns              = {}
    rbac             = {}
    hostpath-storage = {}
    registry         = { args = ["--size", "20Gi"] }
  }
  kubeconfig_path = "~/.kube/tp-local-microk8s.yaml"
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `channel` | string | `"1.35/stable"` | Snap channel `<track>/<risk>` (e.g. `1.36/stable`, `1.35-strict/stable`). Changes are applied with `snap refresh`. |
| `addons` | map(object({ args = list(string) })) | `{}` | Add-ons to enable; removing an entry disables it. Names and arguments are validated (no shell metacharacters). |
| `kubeconfig_path` | string | `"~/.kube/tp-local-microk8s.yaml"` | Exported admin kubeconfig (0600). |
| `api_server_address` | string | `"127.0.0.1"` | Address written in the kubeconfig (stable across WSL IP changes, in the certificate SANs). |
| `wait_timeout_seconds` | number | `600` | Timeout of each readiness wait (60-3600). |
| `uninstall_on_destroy` | bool | `false` | Remove MicroK8s and **all cluster data** on destroy. |

## Outputs

| Name | Description |
|---|---|
| `channel` | Tracked snap channel. |
| `addons` | Managed add-ons (sorted). |
| `kubeconfig_path` | Absolute kubeconfig path. |
| `kubeconfig_context` | `microk8s`. |
| `api_server_url` | `https://<api_server_address>:16443`. |
| `install_id` | ID of the install step, to sequence dependent steps. |

## Tests

```bash
terraform init -backend=false && terraform test   # plan-mode, no side effects
bash scripts/tests/run.sh                         # script behaviour with stubbed snap/microk8s/sudo
```
