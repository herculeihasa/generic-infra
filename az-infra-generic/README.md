# az-infra-generic

Reusable Terraform foundation for Azure, centred on a **generic Azure Kubernetes
Service (AKS) module** and a **secure Azure Storage Account module**, with
remote state in **Azure Blob Storage** provisioned through that storage module.

> **Status: ready for deployment, not yet deployed.** No Azure account was
> available while this was built. Every check that does not need Azure has been
> run (see [§12](#12-validation-commands)); what remains is listed in
> [§14](#14-known-limitations-and-pending-azure-dependent-validation).

Operational procedures (setup, backend and state, deployments, CI/CD,
troubleshooting and recovery, security and maintenance) are in the
[runbooks](docs/runbooks/README.md); this README stays the reference.

## Contents

1. [Project overview](#1-project-overview)
2. [Architecture and directory structure](#2-architecture-and-directory-structure)
3. [Terraform and provider versions](#3-terraform-and-provider-versions)
4. [Azure prerequisites](#4-azure-prerequisites)
5. [Azure authentication setup](#5-azure-authentication-setup)
6. [Remote backend architecture](#6-remote-backend-architecture)
7. [Backend storage bootstrap procedure](#7-backend-storage-bootstrap-procedure)
8. [Required credentials and configuration variables](#8-required-credentials-and-configuration-variables)
9. [AKS module inputs and outputs](#9-aks-module-inputs-and-outputs)
10. [Usage examples](#10-usage-examples)
11. [Deployment procedure](#11-deployment-procedure)
12. [Validation commands](#12-validation-commands)
13. [Troubleshooting](#13-troubleshooting)
14. [Known limitations and pending Azure-dependent validation](#14-known-limitations-and-pending-azure-dependent-validation)

---

## 1. Project overview

| Component | Purpose |
|---|---|
| `bootstrap/` | One-time creation of the Terraform state storage: resource group plus the `storage_account` module (hardened account, one private container per environment, Entra ID-only access). Runs with local state. |
| `modules/aks/` | Generic AKS module: cluster, identity, Azure CNI networking, node pools, security add-ons, Azure Monitor wiring, role assignments. Reusable across projects and environments without modifying it. |
| `modules/storage_account/` | Generic Storage Account module: Entra ID-only, TLS 1.2, private-by-default account with versioning/soft delete, private blob containers, optional RBAC role assignments and delete lock. Reference: [module README](modules/storage_account/README.md). |
| `environments/<env>/` | One root configuration per environment. It owns the resource group, network and Log Analytics workspace, and calls the AKS module. `dev` is implemented; `rec`, `ppr`, `prod` are ready to be created from it ([§2](#adding-an-environment-rec-ppr-prod)). |

Design principles:

* **Secure by default.** Entra ID everywhere: no storage keys, no local Kubernetes accounts, no secret inputs. Managed identities, least-privilege role assignments, Azure Policy, Workload Identity, Key Vault CSI driver.
* **Generic module, opinionated defaults.** It exposes a curated interface (38 inputs) rather than every provider argument; sensible production defaults; validations that fail fast at plan time.
* **No hidden drift.** Autoscaled node counts and auto-upgraded versions are left to Azure through Optional+Computed attributes, with no blanket `ignore_changes`.
* **Checked offline.** Formatting, `terraform validate` with read-only lock files, TFLint, Trivy and Checkov run without Azure credentials, locally and in CI.

## 2. Architecture and directory structure

```text
az-infra-generic/
├── .terraform-version        # exact Terraform CLI version (tfenv / tenv / CI)
├── .tflint.hcl               # TFLint configuration (terraform + azurerm rulesets)
├── .checkov.yaml             # Checkov policy configuration (+ .checkov-prod.yaml for production plans)
├── .trivyignore.yaml         # Trivy accepted findings (justified, expiring)
├── .gitignore / .gitattributes
├── bootstrap/                # remote state storage, LOCAL state (no backend block)
│   ├── versions.tf           # Terraform/provider constraints + provider block
│   ├── variables.tf | outputs.tf
│   ├── main.tf               # resource group + module "state_storage" (modules/storage_account)
│   ├── moved.tf              # migration of pre-module states to the module addresses
│   └── .terraform.lock.hcl
├── environments/
│   ├── dev/                  # implemented
│   │   ├── backend.tf        # azurerm backend: container tfstate-dev, key, Entra ID auth
│   │   ├── backend.hcl.example
│   │   ├── versions.tf | providers.tf
│   │   ├── variables.tf | locals.tf | main.tf | outputs.tf
│   │   ├── terraform.tfvars  # non-sensitive values only (committed)
│   │   └── .terraform.lock.hcl
│   ├── rec/  ppr/  prod/     # empty: to be created from dev
└── modules/
    ├── aks/
    │   ├── versions.tf       # minimum versions only, no provider block
    │   ├── variables.tf      # interface + validations
    │   ├── locals.tf
    │   ├── main.tf           # azurerm_kubernetes_cluster
    │   ├── identity.tf       # control plane identity, role assignments, access check
    │   ├── node_pools.tf     # additional node pools + workload capacity check
    │   ├── monitoring.tf     # Container Insights DCR, diagnostic settings
    │   ├── outputs.tf
    │   └── README.md
    └── storage_account/
        ├── versions.tf       # minimum versions only, no provider block
        ├── variables.tf      # interface + validations
        ├── locals.tf
        ├── main.tf           # account, containers, role assignments, lock
        ├── outputs.tf        # no keys / connection strings
        └── README.md         # full module reference
```

Layering and dependencies:

```text
bootstrap/  (local state)
   ├── azurerm_resource_group            rg-<project>-tfstate-<region>
   └── module "state_storage"  (modules/storage_account)
         ├── azurerm_storage_account     st<project>tfstate<hash6>
         ├── azurerm_storage_container   tfstate-<env> (+ tfstate-bootstrap)
         ├── azurerm_role_assignment     Storage Blob Data Contributor (account / container scope)
         └── azurerm_management_lock     CanNotDelete
                                   │
bootstrap/ ──creates──▶ Storage account + tfstate-<env> containers
                                   ▲
                                   │ backend "azurerm" (Entra ID, blob lease lock)
environments/dev/ ─────────────────┘
   ├── azurerm_resource_group            rg-<project>-<env>-<region>
   ├── azurerm_virtual_network           vnet-<project>-<env>-<region>
   │     └── azurerm_subnet              snet-aks-nodes   (no default outbound access)
   ├── azurerm_log_analytics_workspace   log-<project>-<env>-<region> (Entra ID only)
   └── module "aks"  (modules/aks)
         ├── azurerm_user_assigned_identity           id-aks-...   (control plane)
         ├── azurerm_role_assignment                  Network Contributor on the node subnet
         ├── azurerm_kubernetes_cluster               aks-<project>-<env>-<region>
         ├── azurerm_kubernetes_cluster_node_pool     user pools (e.g. "apps")
         ├── azurerm_role_assignment                  AKS RBAC Cluster Admin / AcrPull
         ├── azurerm_monitor_data_collection_rule     MSCI-<region>-<cluster> (+ association)
         └── azurerm_monitor_diagnostic_setting       control plane logs → workspace
```

**Naming convention:** `<CAF abbreviation>-<project>-<environment>-<region code>`,
for example `aks-azinfra-dev-frc`. Region codes are defined in `locals.tf`
(`francecentral` → `frc`, ...). All resources are tagged with `project`,
`environment`, `managed_by = terraform` and `stack`.

### Adding an environment (rec, ppr, prod)

The `rec`, `ppr` and `prod` directories exist but are empty by design: each is
created from `dev` once its parameters are known.

```bash
cd environments
cp dev/*.tf dev/terraform.tfvars dev/backend.hcl.example dev/.terraform.lock.hcl rec/
```

Then in `rec/`:

1. `backend.tf`: set `container_name = "tfstate-rec"` (the key stays the same).
2. `terraform.tfvars`: `environment = "rec"`, a **non-overlapping** `vnet_address_space` / `aks_nodes_subnet_prefix`, `aks_sku_tier = "Standard"`, real `aks_admin_group_object_ids`, `grant_deployer_cluster_admin = false`, authorized IP ranges or a private cluster.
3. Generate `backend.hcl` from the bootstrap outputs ([§7](#7-backend-storage-bootstrap-procedure)).

For `prod`, also consider a dedicated subscription and its own state storage
account (run the bootstrap there).

## 3. Terraform and provider versions

| Item | Constraint | Pinned / validated version | Where |
|---|---|---|---|
| Terraform CLI (root configs) | `~> 1.17` | **1.17.2** | `required_version` in `bootstrap/` and `environments/*/versions.tf`; exact version in `.terraform-version` |
| Terraform CLI (AKS module) | `>= 1.9.0, < 2.0.0` | exercised with 1.17.2 only | `modules/aks/versions.tf` (1.9 is the first version supporting validations that reference other variables) |
| `hashicorp/azurerm` (root configs) | `~> 5.14` | **5.14.0** | `required_providers` + committed `.terraform.lock.hcl` |
| `hashicorp/azurerm` (AKS module) | `>= 5.14.0, < 6.0.0` | 5.14.0 | `modules/aks/versions.tf` |
| Terraform CLI (Storage Account module) | `>= 1.9.0, < 2.0.0` | 1.17.2 and 1.9.8 (validate) | `modules/storage_account/versions.tf` |
| `hashicorp/azurerm` (Storage Account module) | `>= 5.14.0, < 6.0.0` | 5.14.0 | `modules/storage_account/versions.tf` |

Version policy:

* **Root configurations pin**, child modules declare minimums only. The modules have no provider block and no lock file, so callers keep control of provider configuration and versions.
* **Lock files are committed** for `bootstrap/` and `environments/dev/`, with hashes for `windows_amd64`, `linux_amd64`, `darwin_amd64` and `darwin_arm64`, so CI on Linux and workstations on Windows/macOS install the exact same provider build.
* **Upgrading the provider** is a reviewed change (lock file diff):

  ```bash
  terraform init -upgrade -backend=false
  terraform providers lock \
    -platform=windows_amd64 -platform=linux_amd64 \
    -platform=darwin_amd64 -platform=darwin_arm64
  terraform validate
  ```

azurerm **5.x** specifics that this code relies on:

* No Resource Provider is registered by default. The needed ones are listed in `resource_providers_to_register` (a variable; set it to `[]` when registration is handled by a platform team).
* `azurerm_kubernetes_cluster` requires a `node_provisioning_profile` block (set to `Manual`: node pools are explicit). `oidc_issuer_enabled` defaults to `true`.
* `azurerm_storage_container` uses `storage_account_id` (management plane). That is why Shared Key can be disabled on the state account.
* `azurerm_storage_account` takes `public_network_access` as a string (`Enabled`, `Disabled`, `SecuredByPerimeter`; the boolean `public_network_access_enabled` is deprecated) and accepts only `TLS1_2` as `min_tls_version`.
* `azurerm_monitor_diagnostic_setting` uses `enabled_metric` (the `metric` block was removed).

## 4. Azure prerequisites

**Subscription and quotas**

* An Azure subscription in a tenant where you can create Entra ID groups (cluster admins).
* vCPU quota for the **Standard DDSv5 family** in the target region (`francecentral` by default). dev needs at least 6 vCPUs (1 × D2ds_v5 + 1 × D4ds_v5) and up to about 24 during scale-out with surge upgrades. Check with `az vm list-usage --location francecentral -o table`.
* A region with availability zones for the default 3-zone pools (otherwise set `zones = []`).

**Resource providers** (registered automatically by the provider if the identity has `*/register/action`, otherwise beforehand by an administrator):

```bash
for rp in Microsoft.Storage Microsoft.Compute Microsoft.ContainerService Microsoft.Insights \
          Microsoft.ManagedIdentity Microsoft.Network Microsoft.OperationalInsights \
          Microsoft.OperationsManagement Microsoft.PolicyInsights; do
  az provider register --namespace "$rp"
done
# Only if host_encryption_enabled = true is used:
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

**Permissions**

| Who | Scope | Roles |
|---|---|---|
| Operator running `bootstrap/` (once) | Subscription | *Owner*, or *Contributor* + *User Access Administrator* (role assignments, management lock) |
| Identity deploying an environment | Subscription (it creates the resource group) | *Contributor* + *Role Based Access Control Administrator* (or *User Access Administrator*): the module creates role assignments (Network Contributor on the subnet, AKS RBAC Cluster Admin, AcrPull) |
| Same identity | State container `tfstate-<env>` | *Storage Blob Data Contributor* (granted by the bootstrap) |

**Workstation tools:** Terraform 1.17.2, a current Azure CLI, `kubectl` and
`kubelogin` (`az aks install-cli` installs both).

## 5. Azure authentication setup

Credentials are **never** written in Terraform files. The `azurerm` provider and
the `azurerm` backend read the same `ARM_*` environment variables, or the Azure
CLI session.

**Workstation (interactive), Azure CLI:**

```bash
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

```powershell
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
```

**CI/CD, recommended: OpenID Connect / workload identity federation (no secret).**
Create a user-assigned managed identity (or app registration) with a federated
credential for your pipeline, grant it the roles of [§4](#4-azure-prerequisites)
(and `state_contributors` in the bootstrap), then expose:

```yaml
# GitHub Actions example
permissions:
  id-token: write
  contents: read
env:
  ARM_USE_OIDC: "true"
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

The repository pipeline (`.github/workflows/_terraform-plan.yml` and
`_terraform-apply.yml`) does exactly this, with one identity per GitHub
environment: a read-only plan identity and an approval-gated deployment
identity. Setup and roles: [`docs/ci-cd.md`](../docs/ci-cd.md) §6 and §10.

Azure DevOps works the same way with an OIDC service connection
(`ARM_USE_OIDC=true`, `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID`).

**Other supported methods:** managed identity of a self-hosted runner
(`ARM_USE_MSI=true`, `ARM_CLIENT_ID` for a user-assigned one); service principal
with a secret (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`), which is
discouraged; if used, keep the secret in the CI secret store, never in a file.

## 6. Remote backend architecture

Terraform state is stored in **Azure Blob Storage** with the `azurerm` backend.
Two configurations play distinct roles:

| | `bootstrap/` | `environments/<env>/` |
|---|---|---|
| Role | **Creates** the backend storage | **Consumes** the backend |
| State | Local `terraform.tfstate` (the backend does not exist yet) | Remote blob `az-infra-generic/aks.tfstate` in container `tfstate-<env>` |
| Run | Once per subscription/tenant, by an operator | Every deployment (operator or CI/CD) |
| Required rights | Owner, or Contributor + User Access Administrator | Contributor (+ RBAC Administrator) on the target scope + *Storage Blob Data Contributor* on its state container |

```text
Subscription
└── rg-<project>-tfstate-<region>                 created by bootstrap/
    └── st<project>tfstate<hash6>                 modules/storage_account: StorageV2, ZRS, Entra ID only
        ├── tfstate-bootstrap                     reserved; never the bootstrap's backend (§7)
        ├── tfstate-dev   └── az-infra-generic/aks.tfstate   ← environments/dev
        ├── tfstate-rec   └── az-infra-generic/aks.tfstate   ← environments/rec
        ├── tfstate-ppr   └── az-infra-generic/aks.tfstate   ← environments/ppr
        └── tfstate-prod  └── az-infra-generic/aks.tfstate   ← environments/prod
```

`<hash6>` is the first 6 characters of `sha1("<subscription_id>/<project>")`:
deterministic and globally unique in practice, while the subscription ID never
appears in a resource name. Set `storage_account_name` to choose a name yourself.

`environments/dev/backend.tf` is a **partial configuration**: it hardcodes
`use_azuread_auth = true`, `container_name = "tfstate-dev"` and the `key`. Only
the storage account name, unknown until the bootstrap runs, comes from
`backend.hcl` at `terraform init -backend-config=backend.hcl`. That file holds a
non-sensitive identifier and can be committed.

### Controls

| Concern | Implementation |
|---|---|
| Environment isolation | One container per environment; container and key hardcoded in each `backend.tf`, so a copied `backend.hcl` can never point one environment at another's state. CI/CD identities get *Storage Blob Data Contributor* on **their** container only (`state_contributors`). |
| Authentication | Microsoft Entra ID only: `shared_access_key_enabled = false` (no account keys, no key-based SAS), backend `use_azuread_auth = true`. |
| Locking | Native blob **lease** taken by the `azurerm` backend on every state-writing operation. A lock left by a killed process is released with `terraform force-unlock <LOCK_ID>`. |
| Consistency and recovery | Blob versioning plus 30-day soft delete for blobs and containers: any previous state revision can be restored. |
| Encryption at rest | Always-on Storage Service Encryption (AES-256, Microsoft-managed keys) **plus** infrastructure (double) encryption. Customer-managed keys are not supported by the storage module yet ([§14](#14-known-limitations-and-pending-azure-dependent-validation)). |
| Encryption in transit | HTTPS only, TLS 1.2 minimum. |
| Exposure | No public blob access, no cross-tenant replication, copy scope limited to the tenant (`AAD`). The module defaults to no public endpoint and a `Deny` firewall; the bootstrap opens the public endpoint (still Entra ID-authenticated) so that operators and hosted runners can reach the state. Restrict it with `allowed_ip_ranges`, or set `public_network_access = "Disabled"` and use a private endpoint. |
| Deletion protection | `prevent_destroy` on the storage account (in the module) plus a `CanNotDelete` management lock (Azure). |
| Implementation | Every control above is a setting of [`modules/storage_account`](modules/storage_account/README.md), called by `bootstrap/main.tf` with every input passed explicitly. |

## 7. Backend storage bootstrap procedure

The backend must exist **before** any environment can run `terraform init`.
This is a one-time operation per subscription.

```bash
# 1. Authenticate (§5) with an Owner (or Contributor + User Access Administrator)
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# 2. Create the backend storage (local state)
cd bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
#   optional inputs, e.g.:
#   -var 'state_contributors={dev=["<ci-dev-principal-object-id>"]}'
#   -var 'allowed_ip_ranges=["<your-public-ip>"]'
terraform apply bootstrap.tfplan

# 3. Generate the backend settings consumed by each environment
terraform output -raw backend_hcl > ../environments/dev/backend.hcl
```

PowerShell: use PowerShell 7+ (Windows PowerShell 5.1 writes UTF-16 with `>`,
which Terraform cannot parse):
`terraform output -raw backend_hcl | Set-Content -Encoding utf8NoBOM ..\environments\dev\backend.hcl`.

With default inputs the plan adds **9** resources: the resource group, and in
`module.state_storage` the storage account, 5 containers (`tfstate-bootstrap`,
`-dev`, `-rec`, `-ppr`, `-prod`), the current-principal role assignment and the
lock (+1 role assignment per `state_contributors` entry).

Bootstrap inputs (all optional): `project` (`azinfra`), `location`
(`francecentral`), `resource_group_name`, `storage_account_name`,
`environments` (`["dev","rec","ppr","prod"]`), `state_contributors`,
`grant_current_principal_access` (`true`), `account_replication_type` (`ZRS`),
`blob_soft_delete_retention_days` / `container_soft_delete_retention_days`
(`30`), `public_network_access` (`Enabled`), `allowed_ip_ranges` (`[]`; public
IPv4 addresses or CIDRs up to `/30`), `delete_lock_enabled` (`true`), `tags`,
`resource_providers_to_register`. How each maps to the module inputs:
[runbook 03 §2](docs/runbooks/03-backend-and-state-management.md#2-bootstrap-configuration-reference).
The bootstrap outputs `security_configuration` for audits, besides the names and
IDs listed above.

**RBAC propagation:** the *Storage Blob Data Contributor* assignment can take
several minutes to apply. A `403 AuthorizationPermissionMismatch` during the
first `terraform init` of an environment usually means you need to wait and
retry.

### Bootstrap independence and state

The bootstrap **creates** the backend, so it never **uses** it:

* `bootstrap/versions.tf` has no `backend` block: `terraform init` needs no
  storage account, and the configuration stays usable when the state account is
  misconfigured, unreachable (firewall, `public_network_access = "Disabled"`,
  missing role) or being rebuilt. `ci.py azure-config` fails the pipeline if a
  `backend` or `cloud` block is added to `bootstrap/*.tf`.
* Every object it manages goes through Azure Resource Manager (the module
  creates containers with `storage_account_id`), so it needs no data-plane
  access to the account either.

Its state is the local file `bootstrap/terraform.tfstate` (ignored by Git). It
holds sensitive attributes (the storage account keys, even though key-based
access is disabled) and changes only when the bootstrap is applied. Keep it
**outside** the state account it describes:

1. After each bootstrap apply, copy `terraform.tfstate` to a secured location
   that does not depend on this account: secret vault, restricted operations
   share, or a storage account in another subscription.
2. Before the next bootstrap change, restore the latest copy into `bootstrap/`
   and check it with `terraform plan` (no unexpected change).
3. If every copy is lost, the resources can be adopted again with `import`
   blocks (runbook 03, BS-11): the names are deterministic.

The `tfstate-bootstrap` container is reserved. Do not configure it as the
bootstrap's backend: a bootstrap apply that removed your access to the account
would then also lock you out of the state needed to repair it.

**Transition of the other configurations to the Azure Blob backend:** each
environment declares `backend "azurerm"` (partial configuration) and is
initialised **after** the bootstrap, with the account name from
`terraform output -raw backend_hcl` ([§6](#6-remote-backend-architecture),
runbook 03 BS-02 and BS-05). Nothing is migrated: environments start directly
on the remote backend.

### Upgrading an existing bootstrap to the storage module

Before the module existed, the bootstrap declared the account, containers,
role assignments and lock directly. `bootstrap/moved.tf` maps those addresses
to `module.state_storage.*`, keeping the same keys. On a state created by the
earlier version, `terraform plan` reports each object as
`has moved to module.state_storage...` and shows **0 to add, 0 to destroy**,
with one in-place update: the module's `module = "storage_account"` tag on
the account. This was verified offline during development, against a state
produced by the previous configuration.

### Removing the backend

Deliberately multi-step: set `delete_lock_enabled = false` and apply, then lift
the module's `prevent_destroy` (runbook 03, BS-14), then destroy. The lock also
blocks deleting child resources (state containers) and may block removing role
assignments scoped to them, which is intended. Lift it temporarily for such
changes.

## 8. Required credentials and configuration variables

### Credentials and Azure identifiers (environment variables, never committed)

| Variable | Needed for | Sensitive | How to obtain |
|---|---|---|---|
| `ARM_SUBSCRIPTION_ID` | provider + backend | no (but not committed) | `az account show --query id -o tsv` |
| `ARM_TENANT_ID` | CI/CD (inferred from `az login` locally) | no | `az account show --query tenantId -o tsv` |
| `ARM_CLIENT_ID` | CI/CD identity | no | client ID of the federated identity / app registration |
| `ARM_USE_OIDC=true` | CI/CD with workload identity federation | no | pipeline configuration |
| `ARM_CLIENT_SECRET` | only with a service principal secret (discouraged) | **yes** | CI secret store |

### Configuration files

| File | Content | Committed | Status |
|---|---|---|---|
| `environments/dev/backend.hcl` | `storage_account_name` of the state account | yes (non-sensitive) | **pending**: generated after the bootstrap |
| `environments/dev/terraform.tfvars` | project, environment, region, network ranges, pool sizes, access settings | yes (non-sensitive only) | ready, with `TODO(azure-access)` placeholders |
| `bootstrap` inputs | defaults suit most cases; `state_contributors` for CI identities | optional (`-var` / tfvars of your choice) | ready |

### Placeholders to fill once Azure access exists

| Setting | File | Why |
|---|---|---|
| `aks_admin_group_object_ids` | `environments/dev/terraform.tfvars` | Entra ID group(s) of cluster admins. Until then `grant_deployer_cluster_admin = true` keeps dev accessible. |
| `api_server_authorized_ip_ranges` | same | Restrict the public API server to your egress IPs. |
| `kubernetes_version` | same | Pin `MAJOR.MINOR` from `az aks get-versions -l francecentral -o table` (optional; `null` = AKS default). |
| `state_contributors` | bootstrap `-var` | Object IDs of the CI/CD identities per environment. |

### Sensitive data handling

* The module needs **no secret input**: control plane, kubelet, add-ons and pipelines all use managed identities or federated credentials.
* Sensitive **outputs** (`kube_config_raw`, `cluster_ca_certificate`) are marked `sensitive`. The dev environment does not re-export the raw kubeconfig; use `aks_get_credentials_command`.
* Terraform **state** still contains sensitive attributes (kubeconfig, storage keys). It lives in the Entra ID-protected, encrypted, versioned backend. Grant state access as you would grant cluster-admin.
* Never commit `*.tfstate`, `*.tfplan`, `.env` files or exported kubeconfigs (enforced by `.gitignore`).

## 9. AKS module inputs and outputs

Module path: `modules/aks`. All inputs except the first three are optional.
This section groups and explains them; the complete list generated from the
code is in the [module reference](modules/aks/README.md#reference-generated).

### Inputs

**General**

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | required | Cluster name (1-63 chars). |
| `location` | string | required | Azure region. |
| `resource_group_name` | string | required | Existing resource group. |
| `dns_prefix` | string | derived from `name` | API server DNS prefix (forces new cluster). |
| `node_resource_group_name` | string | `null` (AKS naming) | Name of the AKS-managed node resource group. |
| `tags` | map(string) | `{}` | Tags for every module resource. |

**Version, tier and upgrades**

| Name | Type | Default | Description |
|---|---|---|---|
| `kubernetes_version` | string | `null` | `MAJOR.MINOR` with the `patch` channel; `null` with `stable`/`rapid` (validated to avoid drift). |
| `sku_tier` | string | `"Standard"` | `Free`, `Standard` (SLA), `Premium` (LTS). |
| `support_plan` | string | `"KubernetesOfficial"` | `AKSLongTermSupport` requires `Premium`. |
| `automatic_upgrade_channel` | string | `"patch"` | `patch`, `stable`, `rapid`, `node-image` or `null`. |
| `node_os_upgrade_channel` | string | `"NodeImage"` | `NodeImage`, `SecurityPatch`, `Unmanaged`, `None`. |
| `maintenance_windows` | object | `{}` | `auto_upgrade` / `node_os` windows: `frequency`, `interval`, `duration`, `day_of_week`, `day_of_month`, `week_index`, `start_time`, `utc_offset`, `not_allowed`. |

**Identity and access**

| Name | Type | Default | Description |
|---|---|---|---|
| `identity_type` | string | `"UserAssigned"` | Control plane identity: `UserAssigned` (module creates `id-<name>` unless provided) or `SystemAssigned`. |
| `user_assigned_identity` | object `{ id, principal_id }` | `null` | Bring your own control plane identity (e.g. pre-authorised on a custom private DNS zone or KMS key). |
| `entra_id_rbac` | object | `{}` (enabled) | `azure_rbac_enabled` (`true`), `admin_group_object_ids` (`[]`), `tenant_id`. `null` disables Entra ID integration. |
| `cluster_admin_principal_ids` | map(string) | `{}` | Static key => principal object ID granted *AKS RBAC Cluster Admin*. |
| `local_account_disabled` | bool | `true` | No static admin kubeconfig. |
| `run_command_enabled` | bool | `false` | `az aks command invoke`. |

**Networking**

| Name | Type | Default | Description |
|---|---|---|---|
| `network` | object | `{}` | See below. |
| `private_cluster_enabled` | bool | `false` | Private API server (forces new cluster). |
| `private_dns_zone_id` | string | `"System"` | `System`, `None` or a private DNS zone ID (private clusters). |
| `private_cluster_public_fqdn_enabled` | bool | `false` | Public FQDN for a private cluster. |
| `api_server_authorized_ip_ranges` | list(string) | `[]` | CIDRs allowed to reach a public API server. |
| `network_contributor_subnet_ids` | map(string) | `{}` | Static key => subnet ID; Network Contributor for the control plane identity, granted before cluster creation. |

`network` attributes: `cni_mode` (`overlay` \| `vnet`, default `overlay`),
`data_plane` (`cilium` \| `azure`, default `cilium`), `policy` (`cilium` \|
`calico` \| `azure` \| `none`, default `cilium`), `pod_cidr` (`10.244.0.0/16`,
overlay only), `service_cidr` (`172.16.0.0/16`), `dns_service_ip`
(`172.16.0.10`), `outbound_type` (`loadBalancer` \| `managedNATGateway` \|
`userAssignedNATGateway` \| `userDefinedRouting` \| `none`),
`load_balancer_profile` (`managed_outbound_ip_count`, `outbound_ip_address_ids`,
`outbound_ip_prefix_ids`, `idle_timeout_in_minutes`, `outbound_ports_allocated`),
`nat_gateway_profile` (`managed_outbound_ip_count`, `idle_timeout_in_minutes`).

**Node pools**

| Name | Type | Default | Description |
|---|---|---|---|
| `default_node_pool` | object | `{}` | System pool, see below. |
| `node_pools` | map(object) | `{}` | Additional Linux pools keyed by name (1-12 lowercase chars). |
| `auto_scaler_profile` | object | `null` | Cluster autoscaler tuning (`expander`, `scale_down_*`, `skip_nodes_with_*`, ...). |

`default_node_pool` attributes (defaults): `name` (`system`), `vm_size`
(`Standard_D4ds_v5`), `vnet_subnet_id`, `pod_subnet_id`, `zones`
(`["1","2","3"]`), `auto_scaling_enabled` (`true`), `min_count` (`3`),
`max_count` (`5`), `node_count` (`3`, fixed size only), `max_pods`, `os_sku`
(`AzureLinux`), `os_disk_type` (`Managed`), `os_disk_size_gb` (`128`),
`only_critical_addons_enabled` (`true`), `host_encryption_enabled` (`false`),
`orchestrator_version`, `node_labels`, `temporary_name_for_rotation` (generated),
`upgrade_settings` (`max_surge = "10%"`, `drain_timeout_in_minutes`,
`node_soak_duration_in_minutes`), `tags`.

`node_pools` attributes (defaults): `vm_size` (required), `mode` (`User`),
`os_sku` (`AzureLinux`), `vnet_subnet_id` / `pod_subnet_id` (inherited from the
system pool), `zones` (`["1","2","3"]`), `auto_scaling_enabled` (`true`),
`min_count` (`1`, `0` allowed for User pools), `max_count` (`3`), `node_count`
(`1`), `max_pods`, `os_disk_type` (`Managed`), `os_disk_size_gb` (`128`),
`node_labels`, `node_taints` (`key=value:Effect`), `priority` (`Regular` \|
`Spot`), `eviction_policy` (`Delete`), `spot_max_price` (`-1`),
`host_encryption_enabled`, `orchestrator_version`, `upgrade_settings`, `tags`.

**Security**

| Name | Type | Default | Description |
|---|---|---|---|
| `oidc_issuer_enabled` | bool | `true` | OIDC issuer (cannot be disabled once enabled). |
| `workload_identity_enabled` | bool | `true` | Microsoft Entra Workload ID. |
| `azure_policy_enabled` | bool | `true` | Azure Policy add-on. |
| `key_vault_secrets_provider` | object | `{}` (enabled) | `enabled`, `secret_rotation_enabled` (`true`), `secret_rotation_interval` (`2m`). |
| `key_management_service` | object | `null` | KMS etcd encryption: `key_vault_key_id`, `key_vault_network_access` (`Public`), `key_vault_id`. |
| `disk_encryption_set_id` | string | `null` | Customer-managed keys for node disks. |
| `image_cleaner_enabled` / `image_cleaner_interval_hours` | bool / number | `true` / `168` | Remove unused images from nodes. |
| `microsoft_defender_enabled` | bool | `false` | Defender for Containers sensor (needs `monitoring`). |
| `container_registry_ids` | map(string) | `{}` | Static key => ACR ID; AcrPull for the kubelet identity. |

**Observability**

| Name | Type | Default | Description |
|---|---|---|---|
| `monitoring` | object | `null` (off) | `log_analytics_workspace_id` (required), `container_insights_enabled` (`true`), `container_insights_streams`, `data_collection_rule_location` (workspace region, defaults to the cluster region), `data_collection_interval` (`1m`), `namespace_filtering_mode` (`Off`), `namespaces`, `diagnostic_settings_enabled` (`true`), `diagnostic_log_categories` (apiserver, audit-admin, controller-manager, scheduler, autoscaler, guard), `diagnostic_metrics_enabled` (`true`). |

### Outputs

| Name | Sensitive | Description |
|---|---|---|
| `id`, `name`, `resource_group_name`, `location` | no | Cluster identification. |
| `kubernetes_version`, `current_kubernetes_version` | no | Requested and running versions. |
| `node_resource_group`, `node_resource_group_id` | no | AKS-managed node resource group. |
| `node_pool_ids` | no | Map pool name => node pool ID. |
| `fqdn`, `private_fqdn`, `api_server_endpoint` | no | API server addresses (`https://<fqdn>:443`). |
| `oidc_issuer_url` | no | For Workload Identity federation. |
| `get_credentials_command` | no | `az aks get-credentials ...` (recommended access path). |
| `kube_config_raw` | **yes** | Raw user kubeconfig. |
| `cluster_ca_certificate` | **yes** | Base64 CA, e.g. for kubernetes/helm providers with `kubelogin`. |
| `cluster_identity` | no | `{ type, principal_id, user_assigned_identity_id }`. |
| `kubelet_identity` | no | `{ client_id, object_id, user_assigned_identity_id }`. |
| `key_vault_secrets_provider_identity` | no | Identity of the Key Vault CSI add-on. |
| `container_insights_data_collection_rule_id` | no | DCR ID (or `null`). |

Plan-time **checks** (warnings, they do not block): no User pool while the
system pool is tainted; no cluster administrator while local accounts are
disabled.

## 10. Usage examples

**Minimal** (AKS-managed VNet, no monitoring). Reference the module from
another repository with a Git source pinned to a tag, e.g.
`git::https://<git-host>/<org>/generic-infra.git//az-infra-generic/modules/aks?ref=v1.0.0`.

```hcl
module "aks" {
  source = "../../modules/aks"

  name                = "aks-demo-dev-frc"
  location            = "francecentral"
  resource_group_name = azurerm_resource_group.demo.name

  entra_id_rbac = { admin_group_object_ids = ["<aks-admins-group-object-id>"] }
  node_pools    = { apps = { vm_size = "Standard_D4ds_v5" } }
}
```

**Production-like** (bring-your-own VNet, private API server, NAT egress,
monitoring, Defender, KMS):

```hcl
module "aks" {
  source = "../../modules/aks"

  name                = "aks-shop-prod-frc"
  location            = "francecentral"
  resource_group_name = azurerm_resource_group.prod.name
  tags                = local.tags

  sku_tier           = "Standard"
  kubernetes_version = "1.33" # MAJOR.MINOR: patches are applied automatically
  maintenance_windows = {
    auto_upgrade = { frequency = "Weekly", day_of_week = "Sunday", start_time = "01:00", utc_offset = "+01:00" }
    node_os      = { frequency = "Weekly", day_of_week = "Saturday", start_time = "01:00", utc_offset = "+01:00" }
  }

  # Identity pre-authorised on the KMS key (Key Vault Crypto User)
  user_assigned_identity = {
    id           = azurerm_user_assigned_identity.aks.id
    principal_id = azurerm_user_assigned_identity.aks.principal_id
  }
  entra_id_rbac = { admin_group_object_ids = [var.aks_admins_group_id] }

  private_cluster_enabled = true
  network = {
    outbound_type = "userAssignedNATGateway" # NAT gateway attached to the node subnet
  }
  network_contributor_subnet_ids = { nodes = azurerm_subnet.aks_nodes.id }

  default_node_pool = {
    vm_size          = "Standard_D4ds_v5"
    vnet_subnet_id   = azurerm_subnet.aks_nodes.id
    os_disk_type     = "Ephemeral" # the VM size's temp disk must fit os_disk_size_gb
    os_disk_size_gb  = 128
    upgrade_settings = { max_surge = "33%" }
  }
  node_pools = {
    apps  = { vm_size = "Standard_D8ds_v5", min_count = 3, max_count = 20 }
    batch = {
      vm_size     = "Standard_D8ds_v5"
      priority    = "Spot"
      min_count   = 0
      max_count   = 10
      node_taints = ["workload=batch:NoSchedule"]
    }
  }

  key_management_service = {
    key_vault_key_id = azurerm_key_vault_key.etcd.versionless_id
    key_vault_id     = azurerm_key_vault.platform.id
  }
  container_registry_ids     = { shared = azurerm_container_registry.shared.id }
  microsoft_defender_enabled = true
  monitoring = {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.prod.id
  }
}
```

(The `ref`, version and IDs above are illustrative; adapt them to your
environment.)

**Reference implementation:** [`environments/dev/main.tf`](environments/dev/main.tf)
wires the module with its own network and Log Analytics workspace.

**Consuming outputs**, e.g. the Helm/Kubernetes providers in a separate stack
with Entra ID authentication through `kubelogin`:

```hcl
provider "kubernetes" {
  host                   = module.aks.api_server_endpoint
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
  }
}
```

(`6dae42f8-...` is the well-known AKS Entra ID server application ID.)

## 11. Deployment procedure

First deployment of **dev**, once Azure access exists:

```bash
# 0. Tooling: Terraform 1.17.2 (tfenv/tenv read .terraform-version), Azure CLI, kubectl, kubelogin
# 1. Authenticate (§5)
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# 2. Bootstrap the remote state (once per subscription, §7)
cd az-infra-generic/bootstrap
terraform init && terraform plan -out=bootstrap.tfplan && terraform apply bootstrap.tfplan
terraform output -raw backend_hcl > ../environments/dev/backend.hcl

# 3. Fill the TODO(azure-access) placeholders of environments/dev/terraform.tfvars (§8)

# 4. Deploy dev
cd ../environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=dev.tfplan
terraform apply dev.tfplan

# 5. Access the cluster (Entra ID)
$(terraform output -raw aks_get_credentials_command)
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -o wide
```

Subsequent changes: `terraform plan -out=dev.tfplan`, review, then
`terraform apply dev.tfplan`. In CI/CD, run `fmt -check`, `validate`, TFLint
and the security scanners on every change, publish the plan for review, and
apply the **saved** plan only after approval.

Tear-down of dev: `terraform destroy` (the AKS-managed node resource group is
removed by AKS; the state storage is unaffected).

## 12. Validation commands

### Offline checks (no Azure account needed)

Run from `az-infra-generic/`:

```bash
terraform fmt -check -recursive

for d in bootstrap environments/dev modules/aks modules/storage_account; do
  (cd "$d" && terraform init -backend=false -input=false >/dev/null \
            && terraform validate)
done
```

Results at the time of writing (Terraform 1.17.2, azurerm 5.14.0):

| Check | Scope | Result |
|---|---|---|
| `terraform fmt -check -recursive` | all | pass |
| `terraform validate` | bootstrap, environments/dev, modules/aks, modules/storage_account | pass |
| Storage module README examples | the three `module` blocks of `modules/storage_account/README.md` (+ private endpoint), planned in a temporary harness with the mocked provider | fmt + validate + plan pass |
| Lock files | init with the committed lock file | unchanged, 4 platforms |
| README examples ([§10](#10-usage-examples)) | the two `module "aks"` blocks, planned in a temporary harness with the mocked provider (placeholder group ID replaced by a GUID, `container_registry_ids` line excluded, see [§14](#14-known-limitations-and-pending-azure-dependent-validation)) | validate + plan pass |
| Declaration lint (ad-hoc script: unused/undeclared variables and locals, naming, descriptions, types) | all | 0 findings |

### Pre-commit hooks

The repository's pre-commit hooks ([`docs/pre-commit.md`](../docs/pre-commit.md))
run the fast checks above at each commit (formatting, `ci.py azure-config`,
Markdown, generated module references, secrets), `init` + `validate` and
TFLint on the affected roots at each push, and everything, scanners
included, with `pre-commit run --hook-stage manual --all-files`.

### Static analysis and security scanning (CI pipeline)

TFLint (`.tflint.hcl`), Gitleaks, Trivy (`.trivyignore.yaml`) and Checkov
(`.checkov.yaml`, stricter `.checkov-prod.yaml` for production plans) run in
the `az-infra-generic` GitHub Actions workflow, together with Azure static
checks of the provider/backend configuration. See
[`docs/ci-cd.md`](../docs/ci-cd.md). Locally, on Linux/WSL:

```bash
ci/scripts/install-tools.sh && ci/scripts/run-local.sh az-infra-generic   # from the repository root
```

First local run (WSL, pinned tool versions of `ci/tool-versions.env`, fresh
clone), when the Storage Account module was added:

| Tool | Result |
|---|---|
| TFLint 0.66.0 | pass (every root, local modules included) |
| Gitleaks 8.30.1 | no leak (full history) |
| Trivy 0.76.2 | HIGH/CRITICAL gate passes (`AVD-AZU-0012` accepted, path `modules/storage_account/main.tf`). Non-blocking LOW/MEDIUM findings on the state account: `AZU-0057` (no blob logging), `AZU-0058` (ZRS, not geo-redundant), `AZU-0060` (no customer-managed key), all known limitations below |
| Checkov 3.4.5 | storage account and containers: no unaccepted finding (account checks such as `CKV_AZURE_190`, `CKV_AZURE_36`, `CKV_AZURE_44` and the custom `CKV2_AZINFRA_1` pass; `CKV_AZURE_206`, `CKV2_AZURE_21` and the `CKV_AZURE_34` false positive are accepted in `.checkov.yaml`). **The gate still fails** on 3 findings that predate the module: `CKV_AZURE_232` and `CKV_AZURE_172` (AKS module), `CKV2_AZURE_31` (dev node subnet without NSG): fix or accept them |
| actionlint 1.7.12 | fails on the custom self-hosted runner labels `wsl` / `microk8s` of `.github/workflows/tp-local.yml` (an `actionlint.yaml` declaring them is missing); unrelated to this project |
| ShellCheck | not run (not installed on the validation machine) |

Checkov parses Terraform with python-hcl2, which rejects comments inside
multi-line expressions: keep comments outside expressions, or the whole file is
skipped (`Parsing errors: 1`).

### Azure-dependent validation (pending)

```bash
cd bootstrap        && terraform plan                                   # needs credentials
cd environments/dev && terraform init -backend-config=backend.hcl       # needs the backend
cd environments/dev && terraform plan -out=dev.tfplan                   # needs credentials
cd environments/dev && terraform apply dev.tfplan                       # real deployment
```

Module minimum version check (declared `>= 1.9.0`): the pipeline's
"minimum Terraform version" job validates `modules/aks` and
`modules/storage_account` with Terraform 1.9.8; locally:
`tfenv use 1.9.8 && cd modules/storage_account && terraform init -backend=false && terraform validate`
(same for `modules/aks`).

Storage Account module checks that need Azure (pending): the bootstrap's
first `terraform plan`/`apply` (9 resources), `terraform plan` again (no
drift: Optional+Computed attributes such as `access_tier`, network rule sets
and blob properties must not show a diff), the `az` checks of
[runbook 03 BS-01](docs/runbooks/03-backend-and-state-management.md#bs-01-bootstrap-the-backend),
and a first `terraform init` of `environments/dev` against the new account.

## 13. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `403 AuthorizationPermissionMismatch` on `terraform init` | Data-plane role not yet propagated or missing; IP filtering on the state account | Wait a few minutes; check *Storage Blob Data Contributor* on `tfstate-<env>`; add your IP to `allowed_ip_ranges` |
| `KeyBasedAuthenticationNotPermitted` from the backend | Backend trying key-based authentication | Keep `use_azuread_auth = true` in `backend.tf`; do not set `ARM_ACCESS_KEY` |
| Bootstrap plan: `Instance cannot be destroyed` on `module.state_storage.azurerm_storage_account.this`, or containers to create | An input that replaces the account changed, the bootstrap state is missing, or a pre-module state without `moved.tf` | Revert the input; restore the bootstrap state; runbook 03 BS-11 / BS-15 |
| Storage module validation error (kind/tier, replication, IP rule, container name) | Unsupported combination or Azure naming rule | See [module README](modules/storage_account/README.md#troubleshooting) |
| `Error acquiring the state lock` | Another run in progress, or a killed run left a lease | Make sure nothing runs, then `terraform force-unlock <LOCK_ID>` |
| `MissingSubscriptionRegistration` | Resource provider not registered | Register it ([§4](#4-azure-prerequisites)) or let the provider do it via `resource_providers_to_register` |
| `AuthorizationFailed` on `azurerm_role_assignment` | Deployer lacks role-assignment rights | Grant *Role Based Access Control Administrator* / *User Access Administrator* |
| `QuotaExceeded` / `OperationNotAllowed` for VM size | vCPU quota or SKU not available in a zone | Request quota; `az vm list-skus -l francecentral --size Standard_D2ds_v5 -o table`; change `vm_size` or `zones` |
| Error about ephemeral OS disk size | VM cache/temp disk smaller than `os_disk_size_gb` | Use `Managed`, a smaller disk, or a VM size with a larger temp disk |
| `EncryptionAtHost feature is not enabled` | Subscription feature missing | `az feature register --namespace Microsoft.Compute --name EncryptionAtHost`, or keep `host_encryption_enabled = false` |
| `kubectl`: `Forbidden` / prompts for device login | Azure RBAC assignment missing/propagating; kubeconfig not converted | Configure admin groups or `cluster_admin_principal_ids`; `kubelogin convert-kubeconfig -l azurecli` |
| Pods stay `Pending` | System pool tainted `CriticalAddonsOnly`, no User pool | Add a User pool (`node_pools`) — the module warns about this at plan time |
| No data in Container Insights | DCR/association missing or workspace access type | Check `container_insights_data_collection_rule_id` output and the DCR association; the workspace must accept Entra ID ingestion |
| Recurrent diff on `microsoft_defender`, `azure_policy_enabled` or `oms_agent` | Defender for Cloud / Azure Policy auto-provisioning modifies the cluster | Align the module inputs with the enforced policy (e.g. `microsoft_defender_enabled = true`) |
| Validation error on `kubernetes_version` | Patch pinned with the `patch` channel, or pinned with `stable`/`rapid` | Use `MAJOR.MINOR`, or `null` with `stable`/`rapid` |
| `terraform fmt -check` fails only on Windows | Files checked out with CRLF before `.gitattributes` existed | `.gitattributes` enforces LF on checkout: clone the repository again |
| `Invalid character` / BOM error reading `backend.hcl` | File written as UTF-16 by Windows PowerShell 5.1 | Recreate it with PowerShell 7 `Set-Content -Encoding utf8NoBOM` ([§7](#7-backend-storage-bootstrap-procedure)) |

## 14. Known limitations and pending Azure-dependent validation

> ### ⚠️ Azure account not available
>
> This project was implemented **without access to an Azure subscription**.
> Nothing has been initialised against the remote backend, planned with real
> credentials, or deployed. The configuration is complete and validated offline
> ([§12](#12-validation-commands)); the steps below complete the first deployment.

### Ready vs pending

| Area | Ready | Pending (needs Azure) |
|---|---|---|
| Version pinning, lock files | ✅ | — |
| Bootstrap configuration | ✅ validated; uses the Storage Account module; `moved.tf` maps pre-module states to the module addresses | `terraform apply` |
| Storage Account module | ✅ validated (Terraform 1.17.2 and 1.9.8); README examples planned | real plan/apply through the bootstrap, drift check, `az` checks (runbook 03 BS-01) |
| Backend configuration (`backend.tf`) | ✅ | `backend.hcl` (from bootstrap output), first `terraform init` |
| AKS module | ✅ validated | real plan/apply; Azure-side checks (quotas, SKU/zone availability, policy compliance, RBAC propagation) |
| dev environment | ✅ validated | `TODO(azure-access)` values, plan/apply, `kubectl` smoke test |
| rec / ppr / prod | directories only | created from dev ([§2](#adding-an-environment-rec-ppr-prod)) |
| TFLint, Gitleaks, Trivy, Checkov | run locally on WSL ([§12](#12-validation-commands)): TFLint, Gitleaks and the Trivy gate pass; Checkov has 3 pre-existing findings outside the storage scope | first CI run; decision on `CKV_AZURE_232`, `CKV_AZURE_172`, `CKV2_AZURE_31` |
| Modules on Terraform 1.9.x | `modules/storage_account` and `modules/aks` validate locally with 1.9.8; CI minimum-version job for both | first CI run |
| CI/CD plan/apply | implemented ([`docs/ci-cd.md`](../docs/ci-cd.md)) | Azure identities + GitHub environments, then `AZURE_DEPLOYMENT_ENABLED=true` |

### Steps to complete the initial deployment when Azure access is granted

1. Obtain an identity with the rights of [§4](#4-azure-prerequisites) and authenticate ([§5](#5-azure-authentication-setup)).
2. Check region capacity: DDSv5 vCPU quota and availability zones in `francecentral` ([§4](#4-azure-prerequisites)).
3. Run the bootstrap and generate `environments/dev/backend.hcl` ([§7](#7-backend-storage-bootstrap-procedure)); commit `backend.hcl`; copy the bootstrap state to a secured location outside the state account.
4. Fill the placeholders of `environments/dev/terraform.tfvars` ([§8](#8-required-credentials-and-configuration-variables)): admin group(s), authorized IP ranges, optionally the Kubernetes version.
5. `terraform init -backend-config=backend.hcl`, `terraform plan -out=dev.tfplan`, review, `terraform apply dev.tfplan` ([§11](#11-deployment-procedure)).
6. Smoke test: `kubectl get nodes`, `kubectl get pods -A`, data visible in Container Insights, control plane logs in the `AKSAuditAdmin` / `AKSControlPlane` tables.
7. Run `terraform plan` again: it must report **no changes** (drift check).
8. Run TFLint and a security scanner ([§12](#12-validation-commands)), and set up CI/CD with OIDC and `state_contributors`.

### Known limitations (by design, can be extended)

* Linux node pools only. Windows pools would need a `windows_profile` (admin password) and are not supported by the Cilium data plane.
* Not included: Managed Prometheus / Grafana, API server VNet integration, Istio service mesh, application routing, a bring-your-own kubelet identity, Node Auto-Provisioning, a custom NSG on the node subnet, a private endpoint for the state account.
* Single region per environment; multi-region or disaster-recovery topology is out of scope.
* The `CanNotDelete` lock on the state account also blocks deleting state containers (and possibly revoking role assignments scoped to them) until it is lifted.
* Storage Account module: no private endpoint or private DNS (the caller creates them), no customer-managed keys, no diagnostic settings (blob logging), no lifecycle management or immutability policies, no hierarchical namespace (ADLS Gen2), SFTP, NFS or static website. `prevent_destroy` is part of the module and applies to every caller. Minimum TLS version is fixed at `TLS1_2` (the only value azurerm 5.14 accepts).
* The AcrPull assignment (`container_registry_ids`) is only covered by `terraform validate`: its principal is the object ID of the computed `kubelet_identity` block, known after the first apply.
