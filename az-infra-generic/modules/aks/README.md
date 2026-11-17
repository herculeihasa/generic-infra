# Module `aks`

Generic, reusable Terraform module that provisions an Azure Kubernetes Service
(AKS) cluster with secure, production-oriented defaults:

* user-assigned control plane identity, Entra ID integration with Azure RBAC, no local accounts;
* Azure CNI Overlay powered by Cilium, optional bring-your-own subnets, private API server or authorized IP ranges;
* autoscaled, zone-redundant system pool dedicated to system pods, plus any number of User/System/Spot pools;
* Workload Identity, Azure Policy, Key Vault CSI driver, Image Cleaner; optional KMS, disk encryption set, Defender;
* opt-in Azure Monitor: Container Insights (managed identity + data collection rule) and control plane diagnostics.

The module creates the cluster and what belongs to it (identity, node pools,
monitoring wiring, role assignments). It never creates the resource group,
virtual network, Log Analytics workspace or Key Vault: the calling
configuration owns those and passes them in by ID.

## Usage

```hcl
module "aks" {
  source = "../../modules/aks"

  name                = "aks-demo-dev-frc"
  location            = "francecentral"
  resource_group_name = azurerm_resource_group.demo.name

  default_node_pool              = { vnet_subnet_id = azurerm_subnet.aks_nodes.id }
  network_contributor_subnet_ids = { nodes = azurerm_subnet.aks_nodes.id }
  node_pools                     = { apps = { vm_size = "Standard_D4ds_v5" } }

  entra_id_rbac = { admin_group_object_ids = ["<aks-admins-group-object-id>"] }
  monitoring    = { log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id }
}
```

Full input/output reference and more examples: project
[README §9](../../README.md#9-aks-module-inputs-and-outputs) and
[§10](../../README.md#10-usage-examples).

## Requirements

| Name | Version |
|---|---|
| Terraform | `>= 1.9.0, < 2.0.0` |
| `hashicorp/azurerm` | `>= 5.14.0, < 6.0.0` |

The module has no provider block: configure `azurerm` in the root module.

## Files

| File | Content |
|---|---|
| `versions.tf` | Minimum Terraform / `azurerm` versions |
| `variables.tf` | Module interface: inputs, defaults, validations |
| `locals.tf` | Derived values |
| `identity.tf` | Control plane identity, subnet / cluster-admin / registry role assignments, admin access check |
| `main.tf` | AKS cluster |
| `node_pools.tf` | Additional node pools, workload capacity check |
| `monitoring.tf` | Container Insights data collection rule, control plane diagnostic settings |
| `outputs.tf` | Outputs |
| `tests/` | Offline `terraform test` suites using a mocked `azurerm` provider |

## Tests

```bash
terraform init -backend=false
terraform test   # 70 plan-mode runs, no Azure credentials needed
```
