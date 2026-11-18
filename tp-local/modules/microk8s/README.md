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

## Inputs and outputs

Types, defaults and descriptions: [Reference (generated)](#reference-generated).

## Tests

```bash
terraform init -backend=false && terraform test   # plan-mode, no side effects
bash scripts/tests/run.sh                         # script behaviour with stubbed snap/microk8s/sudo
```

## Reference (generated)

Generated from the module code by [terraform-docs](https://terraform-docs.io/)
(configuration: `.terraform-docs.yml` at the repository root). Do not edit
between the markers: change the code, then run
`pre-commit run terraform-docs --all-files`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |

### Providers

| Name | Version |
| ---- | ------- |
| terraform | n/a |

### Modules

No modules.

### Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.addon](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.channel](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.install](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.kubeconfig](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| addons | MicroK8s add-ons to enable (name => { args }). args are passed verbatim after the add-on name, e.g. registry = { args = ["--size", "40Gi"] }. Removing an entry disables that add-on (volume data kept). Add-ons not listed here are left untouched. Names and arguments are validated (no shell metacharacters). | ```map(object({ args = optional(list(string), []) }))``` | `{}` | no |
| api\_server\_address | Address written in the exported kubeconfig. 127.0.0.1 (default) survives WSL IP changes and is part of the MicroK8s certificate SANs. | `string` | `"127.0.0.1"` | no |
| channel | MicroK8s snap channel, i.e. Kubernetes minor version and risk level (e.g. "1.35/stable"). Changing it refreshes the snap in place (`snap refresh`), keeping cluster data. "-strict" tracks select strict confinement. | `string` | `"1.35/stable"` | no |
| kubeconfig\_path | Where the admin kubeconfig is exported (`~` is expanded). Created with 0600 permissions; removed on destroy. Keep it outside Git repositories: it embeds the cluster admin certificate. | `string` | `"~/.kube/tp-local-microk8s.yaml"` | no |
| uninstall\_on\_destroy | Remove the MicroK8s snap AND all cluster data on `terraform destroy`. False (default) keeps MicroK8s installed and only removes what Terraform added on top of it. | `bool` | `false` | no |
| wait\_timeout\_seconds | Timeout of every readiness wait (MicroK8s services, node Ready, add-ons), 60-3600 seconds. | `number` | `600` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| addons | Add-ons managed by the module (sorted). |
| api\_server\_url | Kubernetes API server URL written in the kubeconfig. |
| channel | MicroK8s snap channel tracked by the cluster. |
| install\_id | ID of the install step (changes when MicroK8s is reinstalled); useful to sequence dependent steps. |
| kubeconfig\_context | Context name inside the exported kubeconfig. |
| kubeconfig\_path | Absolute path of the exported admin kubeconfig (known at plan time; the file exists after apply). |
<!-- END_TF_DOCS -->
