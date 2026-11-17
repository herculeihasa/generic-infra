# az-infra-generic

Reusable Terraform foundation for Azure, centred on a generic Azure Kubernetes
Service (AKS) module.

> Documentation is being written incrementally alongside the implementation.
> Sections not yet present are added by later commits.

## 6. Remote backend architecture

Terraform state is stored in **Azure Blob Storage** with the `azurerm` backend.
Two configurations play distinct roles:

| | `bootstrap/` | `environments/<env>/` |
|---|---|---|
| Role | **Creates** the backend storage | **Consumes** the backend |
| State | Local `terraform.tfstate` (the backend does not exist yet) | Remote blob `az-infra-generic/aks.tfstate` in container `tfstate-<env>` |
| Run | Once per subscription/tenant, by an operator | Every deployment (operator or CI/CD) |
| Required rights | Contributor + role-assignment and lock rights (Owner, or Contributor + User Access Administrator) | Contributor on the target scope + *Storage Blob Data Contributor* on its state container |

```
Subscription
└── rg-<project>-tfstate-<region>                 created by bootstrap/
    └── st<project>tfstate<hash6>                 StorageV2, ZRS, Entra ID only
        ├── tfstate-bootstrap                     optional home of the bootstrap state (option B)
        ├── tfstate-dev   └── az-infra-generic/aks.tfstate   ← environments/dev
        ├── tfstate-rec   └── az-infra-generic/aks.tfstate   ← environments/rec
        ├── tfstate-ppr   └── az-infra-generic/aks.tfstate   ← environments/ppr
        └── tfstate-prod  └── az-infra-generic/aks.tfstate   ← environments/prod
```

`<hash6>` is the first 6 characters of `sha1("<subscription_id>/<project>")`:
deterministic and globally unique in practice, while the subscription ID never
appears in a resource name. Set `storage_account_name` to choose a name yourself.

### Controls

| Concern | Implementation |
|---|---|
| Environment isolation | One container per environment; the container and key are hardcoded in each `environments/<env>/backend.tf`, so a copied `backend.hcl` can never point one environment at another's state. CI/CD identities get *Storage Blob Data Contributor* on **their** container only (`state_contributors`). |
| Authentication | Microsoft Entra ID only: `shared_access_key_enabled = false` (no account keys, no key-based SAS), backend `use_azuread_auth = true`. Credentials come from `az login`, OIDC/workload identity federation, managed identity or a service principal through `ARM_*` variables, never from files. |
| Locking | Native blob **lease** taken by the `azurerm` backend on every state-writing operation. A lock left by a killed process is released with `terraform force-unlock <LOCK_ID>`. |
| Consistency and recovery | Blob versioning plus 30-day soft delete for blobs and containers: any previous state revision can be restored. |
| Encryption at rest | Always-on Azure Storage Service Encryption (AES-256, Microsoft-managed keys) **plus** infrastructure (double) encryption. Customer-managed keys can be added with a `customer_managed_key` block if policy requires it. |
| Encryption in transit | HTTPS only, TLS 1.2 minimum. |
| Exposure | No public blob access, no cross-tenant replication, copy scope limited to the tenant (`AAD`). Public endpoint enabled by default (still Entra ID-authenticated); restrict it with `allowed_ip_ranges` or set `public_network_access = "Disabled"` and use a private endpoint. |
| Deletion protection | `prevent_destroy` on the storage account (Terraform) plus a `CanNotDelete` management lock (Azure). |

## 7. Backend storage bootstrap procedure

The backend must exist **before** any environment can run `terraform init`.
This is a one-time operation per subscription.

**Prerequisites:** a current Azure CLI, Terraform 1.17.x, and an identity with
*Owner* (or *Contributor* + *User Access Administrator*) on the subscription.
Role assignments and management locks need the `Microsoft.Authorization/*/write`
permissions that Contributor alone lacks.

```bash
# 1. Authenticate (interactive operator)
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# 2. Create the backend storage (local state)
cd bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
#    optional: -var 'state_contributors={dev=["<ci-dev-object-id>"]}' \
#              -var 'allowed_ip_ranges=["<your-public-ip>"]'
terraform apply bootstrap.tfplan

# 3. Generate the backend settings consumed by each environment
terraform output -raw backend_hcl > ../environments/dev/backend.hcl
```

PowerShell users: use PowerShell 7+ (Windows PowerShell 5.1 writes UTF-16 with
`>`, which Terraform cannot parse):
`terraform output -raw backend_hcl | Set-Content -Encoding utf8NoBOM ..\environments\dev\backend.hcl`.

**RBAC propagation:** the *Storage Blob Data Contributor* assignment can take
several minutes to apply. A `403 AuthorizationPermissionMismatch` during the
first `terraform init` of an environment usually means you need to wait and
retry.

### Bootstrap state

The bootstrap's own state is local (`bootstrap/terraform.tfstate`, ignored by
Git). It holds sensitive attributes (the storage account keys, even though
key-based access is disabled), so choose one of:

* **Option A: keep it local.** Store the file in a secured location (vault,
  restricted ops share). If it is lost, re-import the handful of resources with
  `terraform import`.
* **Option B: migrate it into the backend it created.** Add the block below to
  the `terraform {}` block of `bootstrap/versions.tf`, then migrate:

  ```hcl
  backend "azurerm" {
    use_azuread_auth = true
    container_name   = "tfstate-bootstrap"
    key              = "bootstrap.tfstate"
  }
  ```

  ```bash
  terraform init -migrate-state \
    -backend-config="storage_account_name=$(terraform output -raw storage_account_name)"
  # verify with `terraform plan` (no changes expected), then delete the local
  # terraform.tfstate and terraform.tfstate.backup files
  ```

### Removing the backend

Deliberately multi-step: set `delete_lock_enabled = false` and apply, remove the
`prevent_destroy` lifecycle rule, then destroy. The lock also blocks deleting
child resources (state containers), which is intended.
