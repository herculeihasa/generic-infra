# Module `aks`

Generic, reusable Terraform module that provisions an Azure Kubernetes Service
(AKS) cluster.

The module creates the cluster and the resources that belong to it (identity,
node pools, monitoring wiring, role assignments). It never creates the
resource group, virtual network, Log Analytics workspace or Key Vault: the
calling configuration owns those and passes them in by ID.

| File | Content |
|---|---|
| `versions.tf` | Minimum Terraform / `azurerm` versions (no provider block) |
| `variables.tf` | Module interface: inputs, defaults, validations |
| `locals.tf` | Derived values |
| `identity.tf` | Control plane user-assigned identity |
| `main.tf` | AKS cluster |
| `outputs.tf` | Outputs |
| `tests/` | Offline `terraform test` suites using a mocked `azurerm` provider |

The full input/output reference is in the project [README](../../README.md#9-aks-module-inputs-and-outputs).
