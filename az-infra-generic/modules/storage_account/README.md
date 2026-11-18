# Module `storage_account`

Generic, reusable Terraform module that provisions an Azure Storage Account for
blob data, with secure defaults:

* Microsoft Entra ID only: Shared Key (account keys, key-based SAS, connection strings) disabled, OAuth by default in the portal, no local users or SFTP;
* HTTPS only with TLS 1.2 minimum, no anonymous blob access, no cross-tenant replication, copies restricted to the tenant;
* infrastructure (double) encryption on top of the always-on service encryption;
* public endpoint disabled and firewall denying by default;
* blob versioning plus 30-day soft delete for blobs and containers;
* private blob containers, optional Azure RBAC role assignments at account or container scope, optional `CanNotDelete` lock, `prevent_destroy`.

The module creates the account and what belongs to it (containers, role
assignments, lock). It never creates the resource group, private endpoints,
virtual network rules' subnets or Key Vault keys: the calling configuration
owns those and passes them in.

It is used by [`bootstrap/`](../../bootstrap/main.tf) to create the Azure Blob
storage that holds the Terraform remote state of every environment.

## Contents

1. [Architecture](#architecture)
2. [Usage](#usage)
3. [Inputs](#inputs)
4. [Outputs](#outputs)
5. [Security configuration](#security-configuration)
6. [Blob containers](#blob-containers)
7. [Network access and Terraform connectivity](#network-access-and-terraform-connectivity)
8. [Authentication and required permissions](#authentication-and-required-permissions)
9. [Deletion protection](#deletion-protection)
10. [Requirements, files and tests](#requirements-files-and-tests)
11. [Troubleshooting](#troubleshooting)

## Architecture

```
module "<name>"  (modules/storage_account)
├── azurerm_storage_account.this                StorageV2/Standard (default) or BlockBlobStorage/Premium
│     ├── blob_properties                       versioning, blob + container soft delete
│     └── network_rules                         default action, bypass, IP rules, subnets
├── azurerm_storage_container.this["<key>"]     one per entry of var.containers (private by default)
├── azurerm_role_assignment.this["<key>"]       one per entry of var.role_assignments
│                                               (scope: the account, or one container)
└── azurerm_management_lock.this[0]             CanNotDelete, when delete_lock_enabled = true
                                                (created after containers and role assignments)
```

Every resource is created through **Azure Resource Manager** (containers use
`storage_account_id`), so the module works with Shared Key disabled and with
the public endpoint disabled. Only data-plane clients (applications, a
Terraform `azurerm` backend reading and writing state blobs) need network
access to the blob endpoint and a data role.

Map keys (`containers`, `role_assignments`) are chosen by the caller and are
part of the resource addresses. Keep them stable: renaming a key destroys and
recreates the object.

## Usage

### Terraform remote state storage

What [`bootstrap/main.tf`](../../bootstrap/main.tf) does, simplified: one
private container per environment, the operator on the whole account, each CI
identity on its own container only.

```hcl
module "state_storage" {
  source = "../modules/storage_account"

  name                = "stazinfratfstate1a2b3c"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_replication_type = "ZRS"

  # Backend clients reach the public endpoint (Entra ID still required);
  # list runner/operator IPs to switch the firewall to Deny.
  public_network_access = "Enabled"
  network_rules = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.10"]
  }

  containers = {
    dev  = { name = "tfstate-dev" }
    prod = { name = "tfstate-prod" }
  }

  role_assignments = {
    operator = {
      principal_id         = data.azurerm_client_config.current.object_id
      role_definition_name = "Storage Blob Data Contributor"
    }
    "dev/ci" = {
      principal_id         = "<ci-dev-principal-object-id>"
      role_definition_name = "Storage Blob Data Contributor"
      container_key        = "dev"
    }
  }

  delete_lock_enabled = true
}
```

### Private application data store

Defaults only: no public endpoint (reach it through a private endpoint created
by the caller), private containers, read access for an application identity.

```hcl
module "app_data" {
  source = "../../modules/storage_account"

  name                = "stappdatadevfrc01"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  containers = {
    uploads = {}
    reports = { metadata = { data_owner = "finance" } }
  }

  role_assignments = {
    "reports/app" = {
      principal_id         = azurerm_user_assigned_identity.app.principal_id
      role_definition_name = "Storage Blob Data Reader"
      container_key        = "reports"
    }
  }
}

resource "azurerm_private_endpoint" "app_data_blob" {
  name                = "pe-stappdatadevfrc01-blob"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = module.app_data.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
```

### Premium block blob account restricted to a subnet

```hcl
module "ingest" {
  source = "../../modules/storage_account"

  name                     = "stingestdevfrc01"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_kind             = "BlockBlobStorage"
  account_tier             = "Premium"
  account_replication_type = "ZRS"

  public_network_access = "Enabled"
  network_rules = {
    virtual_network_subnet_ids = [azurerm_subnet.workers.id] # Microsoft.Storage service endpoint required
  }

  containers = { landing = {} }
}
```

The calling configuration needs an `azurerm` provider with
`storage_use_azuread = true` (as in [`bootstrap/versions.tf`](../../bootstrap/versions.tf)),
so that any data-plane call the provider makes uses Entra ID.

## Inputs

Only `name`, `resource_group_name` and `location` are required.

**General**

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Globally unique account name, 3-24 lowercase letters/digits. Forces a new account. |
| `resource_group_name` | `string` | required | Existing resource group (1-90 characters, no trailing period). |
| `location` | `string` | required | Region, short form (`francecentral`). |
| `tags` | `map(string)` | `{}` | Tags of the account. The module adds `managed_by = "terraform"` and `module = "storage_account"`. |

**Account**

| Name | Type | Default | Description |
|---|---|---|---|
| `account_kind` | `string` | `"StorageV2"` | `StorageV2` or `BlockBlobStorage`. Forces a new account. |
| `account_tier` | `string` | `"Standard"` | Must match the kind: `Standard` with `StorageV2`, `Premium` with `BlockBlobStorage`. Forces a new account. |
| `account_replication_type` | `string` | `"ZRS"` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS`, `RAGZRS`. Premium: `LRS` or `ZRS` only. ZRS/GZRS need a region with availability zones. |
| `access_tier` | `string` | `"Hot"` | `Hot`, `Cool` or `Cold`. Not sent for Premium accounts. |

**Authentication and data security**

| Name | Type | Default | Description |
|---|---|---|---|
| `shared_access_key_enabled` | `bool` | `false` | Allow Shared Key authorization (account keys, key-based SAS). |
| `blob_public_access_enabled` | `bool` | `false` | Allow containers with anonymous access (`allow_nested_items_to_be_public`). |
| `infrastructure_encryption_enabled` | `bool` | `true` | Double encryption. Forces a new account. |
| `allowed_copy_scope` | `string` | `"AAD"` | `AAD` (same tenant), `PrivateLink`, or `null` (any source). |

**Network access**

| Name | Type | Default | Description |
|---|---|---|---|
| `public_network_access` | `string` | `"Disabled"` | `Disabled` (private endpoints only), `Enabled` (filtered by `network_rules`), `SecuredByPerimeter`. |
| `network_rules` | `object` | `{}` | `default_action` (`"Deny"`), `bypass` (`["AzureServices"]`; `Logging`, `Metrics`, or `None` alone), `ip_rules` (`[]`; public IPv4 addresses or CIDRs up to `/30`), `virtual_network_subnet_ids` (`[]`; service-endpoint subnets). |

**Blob data protection**

| Name | Type | Default | Description |
|---|---|---|---|
| `blob_properties` | `object` | `{}` | `versioning_enabled` (`true`), `delete_retention_days` (`30`), `container_delete_retention_days` (`30`). Days: 1-365, `0` disables that soft delete policy. |

**Containers, access control, protection**

| Name | Type | Default | Description |
|---|---|---|---|
| `containers` | `map(object)` | `{}` | Keyed by a stable identifier: `name` (defaults to the key), `access_type` (`"private"`, `"blob"`, `"container"`), `metadata` (`{}`). See [Blob containers](#blob-containers). |
| `role_assignments` | `map(object)` | `{}` | Keyed by a stable identifier: `principal_id` (object ID), `role_definition_name`, `container_key` (`null` = account scope), `description`. |
| `delete_lock_enabled` | `bool` | `false` | `CanNotDelete` management lock on the account. |
| `delete_lock_notes` | `string` | generic text | Notes stored on the lock (max 512 characters). |

Every input is validated at plan time (names, enumerations, kind/tier and
tier/replication combinations, IP and subnet formats, container names and
metadata, role assignment principals and container keys).

## Outputs

No output exposes an access key, SAS token or connection string.

| Name | Description |
|---|---|
| `id` | Account resource ID (scope for role assignments, private endpoints). |
| `name`, `resource_group_name`, `location` | Account placement. |
| `primary_location`, `secondary_location` | Regions reported by Azure (secondary only for geo-redundant accounts). |
| `account_kind`, `account_tier`, `account_replication_type`, `access_tier` | Account settings. |
| `primary_blob_endpoint`, `primary_blob_host`, `secondary_blob_endpoint` | Blob endpoints (secondary only for RA-GRS/RA-GZRS). |
| `security_configuration` | Effective security settings: Shared Key, OAuth default, HTTPS, TLS, anonymous access, double encryption, cross-tenant replication, copy scope, public network access, firewall default action and IP rules. |
| `data_protection` | Versioning and soft delete retention days (`0` = disabled). |
| `containers` | Map of container key => `name`, `id` (Resource Manager ID, scope for role assignments), `access_type`. |
| `container_names` | Sorted list of container names. |
| `role_assignments` | Map of role assignment key => `id`, `scope`, `principal_id`, `role_definition_name`. |
| `management_lock_id` | Lock ID, `null` when there is no lock. |

## Security configuration

| Setting | Module behaviour | Why |
|---|---|---|
| Secure transfer (`https_traffic_only_enabled`) | Always `true` | No plain HTTP. |
| Minimum TLS (`min_tls_version`) | Always `TLS1_2` | Azure Storage retired TLS 1.0/1.1; azurerm 5.14 accepts no other value, so there is no input. |
| Shared Key (`shared_access_key_enabled`) | `false`, input | No long-lived keys or key-based SAS: every request carries an Entra ID token and is authorized by Azure RBAC. |
| OAuth default (`default_to_oauth_authentication`) | Always `true` | The portal uses Entra ID too. |
| Local users / SFTP | Always disabled | No separate credential store. |
| Anonymous access (`allow_nested_items_to_be_public`) | `false`, input `blob_public_access_enabled` | A container can only become public through two explicit opt-ins. |
| Cross-tenant replication | Always disabled | No object replication to other tenants. |
| Copy scope (`allowed_copy_scope`) | `AAD`, input | Copy sources limited to the tenant (or private links). |
| Infrastructure encryption | `true`, input | Second encryption layer with a different key. Customer-managed keys are not supported by the module. |
| Public endpoint (`public_network_access`) | `Disabled`, input | Private endpoints only unless explicitly opened. |
| Firewall (`network_rules`) | `Deny` + `AzureServices` bypass, input | When the endpoint is opened, only listed IPs/subnets get through. |
| Versioning and soft delete | Enabled, 30 days, input | Any overwritten or deleted blob or container can be recovered. |
| Destruction | `prevent_destroy`, optional lock | See [Deletion protection](#deletion-protection). |

### Settings that affect Terraform backend connectivity

When the account holds Terraform state (`backend "azurerm"`):

| Setting | Effect on `terraform init/plan/apply` of the environments | Required backend / client setting |
|---|---|---|
| `shared_access_key_enabled = false` | Key-based backend access fails with `KeyBasedAuthenticationNotPermitted`. | `use_azuread_auth = true` in the backend, no `ARM_ACCESS_KEY`; the identity needs *Storage Blob Data Contributor* (read/write) or *Reader* (plan only). |
| `public_network_access = "Disabled"` | The backend cannot reach the blob endpoint from the internet (`403 AuthorizationFailure` / `This request is not authorized to perform this operation`). | A private endpoint (`blob`) plus private DNS resolution from every operator and runner. |
| `network_rules.default_action = "Deny"` with `public_network_access = "Enabled"` | Only listed IPs/subnets reach the data plane; others get `403`. | Every operator and runner egress IP in `ip_rules` (GitHub-hosted runners have changing IPs), or runners in a listed subnet. |
| Role assignment propagation | A new data role can take several minutes to apply: first `init` may get `403 AuthorizationPermissionMismatch`. | Wait and retry. |
| `delete_lock_enabled = true` | No effect on state reads/writes or blob leases (locks are management-plane only). | — |

The account and its containers themselves are always managed through Azure
Resource Manager, so these settings never prevent the configuration that owns
the account (for example the bootstrap) from planning or applying it.

## Blob containers

```hcl
containers = {
  tfstate = {}                                          # name "tfstate", private
  logs    = { name = "app-logs", metadata = { owner_team = "platform" } }
  assets  = { access_type = "blob" }                    # anonymous read of blobs
}
blob_public_access_enabled = true                       # required by "assets" only
```

* **Names** (`name`, or the key): 3-63 characters, lowercase letters, digits and single hyphens, starting and ending with a letter or digit; unique within the account.
* **Access levels**: `private` (default; Entra ID-authorized access only), `blob` (anonymous read of blobs whose URL is known), `container` (anonymous read and listing). For Terraform state, keep `private`.
* **Metadata**: names are lowercase identifiers (letters, digits, underscores, not starting with a digit), as required by the provider.
* **Container-scoped RBAC**: set `container_key` in `role_assignments` to give an identity access to one container only.
* Deleted containers are recoverable during `container_delete_retention_days`.

## Network access and Terraform connectivity

| Plane | Operations | Affected by `public_network_access` / `network_rules` |
|---|---|---|
| Management (Azure Resource Manager) | Create/update the account, containers, role assignments, lock (everything this module does) | No |
| Data (blob endpoint) | Read/write blobs: applications, `az storage blob ... --auth-mode login`, Terraform `azurerm` backend | Yes |

Typical choices:

* **Private only** (default): `public_network_access = "Disabled"`, plus a private endpoint and private DNS zone `privatelink.blob.core.windows.net` created by the caller.
* **Public, filtered**: `public_network_access = "Enabled"`, `network_rules = { ip_rules = [...], virtual_network_subnet_ids = [...] }` (default action stays `Deny`).
* **Public, open** (authentication still required): `network_rules = { default_action = "Allow" }`. The bootstrap uses this until runner IPs or private endpoints are known.

Azure rejects `/31` and `/32` prefixes and private (RFC 1918) ranges in IP
rules: give single public addresses without a mask.

## Authentication and required permissions

The module needs no secret. Terraform authenticates as usual (`az login`,
OIDC/workload identity federation, managed identity) through `ARM_*`
environment variables; see the [project README §5](../../README.md#5-azure-authentication-setup).

| Who | Scope | Role | Needed for |
|---|---|---|---|
| Identity applying the module | Resource group (or subscription) | *Contributor* (or *Storage Account Contributor*) | Account and containers |
| Same identity | Account (or resource group) | *Role Based Access Control Administrator* or *User Access Administrator* | `role_assignments` |
| Same identity | Account (or resource group) | *Owner* or *User Access Administrator* (`Microsoft.Authorization/locks/*`) | `delete_lock_enabled = true` |
| Data-plane clients | Account or container | *Storage Blob Data Contributor* (read/write) or *Storage Blob Data Reader* (read) | Blob access with Shared Key disabled |

The subscription must have the `Microsoft.Storage` resource provider
registered (the bootstrap registers it through `resource_providers_to_register`).

## Deletion protection

* `prevent_destroy = true` on the storage account, in the module code: any plan that would destroy or replace the account fails. `prevent_destroy` cannot be driven by a variable, so this applies to every caller. To decommission an account, either edit the module on a dedicated branch (remove the block, destroy, revert), or stop managing it with a `removed { from = module.<name>.azurerm_storage_account.this ... lifecycle { destroy = false } }` block and delete it outside Terraform.
* Inputs that **force a new account** in the azurerm provider (and therefore hit `prevent_destroy`): `name`, `location`, `resource_group_name`, `account_tier`, `infrastructure_encryption_enabled`, and `account_kind` (between `StorageV2` and `BlockBlobStorage`). Some `account_replication_type` transitions are also performed as a replacement by the provider: always read the plan.
* `delete_lock_enabled = true` adds an Azure `CanNotDelete` lock, which also blocks deleting containers (and may block revoking role assignments scoped to them) through Resource Manager. Set it to `false` and apply before such changes.
* Versioning and soft delete protect the data itself.

## Requirements, files and tests

| Name | Version |
|---|---|
| Terraform | `>= 1.9.0, < 2.0.0` (validated with 1.17.2 and 1.9.8) |
| `hashicorp/azurerm` | `>= 5.14.0, < 6.0.0` (validated with 5.14.0) |

The module has no provider block and no lock file: configure `azurerm` and pin
its version in the root module.

| File | Content |
|---|---|
| `versions.tf` | Minimum Terraform / `azurerm` versions |
| `variables.tf` | Module interface: inputs, defaults, validations |
| `locals.tf` | Derived values (tags, access tier) |
| `main.tf` | Storage account, containers, role assignments, lock |
| `outputs.tf` | Outputs |
| `tests/` | Offline `terraform test` suites using a mocked `azurerm` provider |

```bash
cd modules/storage_account
terraform init -backend=false
terraform validate
terraform test   # 41 plan-mode runs, no Azure credentials needed
```

| Suite | Runs | Covers |
|---|---|---|
| `tests/account.tftest.hcl` | 13 | Placement, tags, kind/tier/replication/access tier, naming validations |
| `tests/security.tftest.hcl` | 10 | Secure defaults, network rules, explicit opt-outs, rejected inputs |
| `tests/containers.tftest.hcl` | 11 | Data protection, private and public containers, name/metadata validations |
| `tests/access.tftest.hcl` | 7 | Role assignments, lock, security output, rejected inputs |

Resource IDs are only known after apply, and Terraform 1.9 cannot tear down an
apply-mode test of a `prevent_destroy` resource, so the role assignment scope
wiring is asserted in `bootstrap/tests` (mocked apply, Terraform 1.17).

Security scanners (run through the bootstrap, which calls the module):
Checkov passes the account checks (including the project policy
`CKV2_AZINFRA_1`: Shared Key disabled, TLS 1.2, infrastructure encryption);
`CKV_AZURE_34` is a false positive (Checkov cannot resolve `access_type`
through `for_each`) and is accepted in `../../.checkov.yaml` with
`CKV_AZURE_206` and `CKV2_AZURE_21`. Trivy reports no HIGH/CRITICAL finding
beyond the accepted `AVD-AZU-0012` (bootstrap's public endpoint). See the
project [README §12](../../README.md#12-validation-commands). Keep comments
outside multi-line expressions: Checkov's parser skips the whole file
otherwise.

Azure-dependent validation (not executed yet, needs a subscription): a real
`terraform plan`/`apply` of a caller (the bootstrap is the first one, see
[runbook 03 BS-01](../../docs/runbooks/03-backend-and-state-management.md#bs-01-bootstrap-the-backend)),
then `terraform plan` again to confirm there is no drift.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `StorageAccountAlreadyTaken` / `AccountNameInvalid` | Name used elsewhere in Azure (global namespace) | Choose another `name` |
| `Instance cannot be destroyed` (`prevent_destroy`) | A changed input forces a new account (see [Deletion protection](#deletion-protection)) | Revert the input; replacing a storage account is a data migration, not a plan |
| `KeyBasedAuthenticationNotPermitted` | A client or backend uses account keys / SAS | Use Entra ID (`--auth-mode login`, `use_azuread_auth = true`, `storage_use_azuread = true`) |
| `403 AuthorizationPermissionMismatch` on blob access | No data role, or still propagating | Add a `role_assignments` entry (*Storage Blob Data ...*); wait a few minutes |
| `403 AuthorizationFailure` / `This request is not authorized to perform this operation` | Firewall or public endpoint disabled | Add the client IP/subnet to `network_rules`, or use a private endpoint |
| `AuthorizationFailed` on `azurerm_role_assignment` or `azurerm_management_lock` | Deployer lacks `Microsoft.Authorization/*/write` | Grant *Role Based Access Control Administrator* / *User Access Administrator* (locks: *Owner* or *User Access Administrator*) |
| `ScopeLocked` when removing a container or role assignment | `CanNotDelete` lock | `delete_lock_enabled = false`, apply, make the change, re-enable |
| Validation error on `account_tier` / `account_replication_type` | Unsupported combination | `StorageV2` + `Standard`; `BlockBlobStorage` + `Premium` with `LRS`/`ZRS` |
| Azure rejects the network rules (e.g. `NetworkAclsValidationFailure`) | Private (RFC 1918) range in `ip_rules`, or a subnet without the `Microsoft.Storage` service endpoint | Public addresses only; enable the service endpoint on the subnet |
| Replication type rejected at creation | ZRS/GZRS/RAGZRS in a region without availability zones | `account_replication_type = "LRS"` or `"GRS"` |
| Blob service properties rejected (e.g. `FeatureNotSupportedForAccount`) | Versioning or soft delete unavailable for the account kind/region | Set `blob_properties` accordingly (`versioning_enabled = false`, `0` days) |
