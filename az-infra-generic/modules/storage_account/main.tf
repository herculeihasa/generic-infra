# =============================================================================
# Generic Azure Storage Account module
#
# File layout:
#   versions.tf    Terraform / provider minimum versions (no provider block)
#   variables.tf   Module interface (inputs, defaults, validations)
#   locals.tf      Derived values
#   main.tf        The storage account, its blob containers, optional Azure
#                  RBAC role assignments and optional CanNotDelete lock
#   outputs.tf     Module outputs (no access keys, no connection strings)
#   tests/         Offline `terraform test` suites (mocked azurerm provider)
#
# The module never creates the resource group: it is owned by the calling
# configuration and passed in by name, so the module can be reused across
# projects and environments.
# =============================================================================

resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags

  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = local.access_tier

  # --- Authentication: Microsoft Entra ID by default ----------------------------
  # With Shared Key disabled there are no usable account keys, key-based SAS or
  # connection strings: every data-plane call needs an Entra ID token and an
  # Azure RBAC data role (e.g. Storage Blob Data Contributor).
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true  # portal uses Entra ID too
  local_user_enabled              = false # no SFTP/local users
  sftp_enabled                    = false

  # --- Transport ----------------------------------------------------------------
  # Not configurable: secure transfer is always required, and TLS1_2 is the
  # only minimum version Azure Storage and azurerm 5.x accept (TLS 1.0/1.1 are
  # retired). Expose a variable once a higher minimum becomes available.
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # --- Data exposure --------------------------------------------------------------
  allow_nested_items_to_be_public  = var.blob_public_access_enabled
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = var.allowed_copy_scope

  # --- Encryption at rest -------------------------------------------------------
  # Azure Storage always encrypts at rest (AES-256, Microsoft-managed keys).
  # Infrastructure encryption adds a second, independent encryption layer.
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled

  # --- Network ------------------------------------------------------------------
  # Management-plane operations (this resource, containers through
  # storage_account_id, role assignments, locks) go through Azure Resource
  # Manager and are not affected by these settings; data-plane access (blob
  # read/write, e.g. a Terraform azurerm backend) is.
  public_network_access = var.public_network_access

  network_rules {
    default_action             = var.network_rules.default_action
    bypass                     = var.network_rules.bypass
    ip_rules                   = var.network_rules.ip_rules
    virtual_network_subnet_ids = var.network_rules.virtual_network_subnet_ids
  }

  # --- Recovery -----------------------------------------------------------------
  # Versioning + soft delete allow recovering any previous revision of a blob
  # and a deleted container. 0 days omits the policy (soft delete disabled).
  blob_properties {
    versioning_enabled = var.blob_properties.versioning_enabled

    dynamic "delete_retention_policy" {
      for_each = var.blob_properties.delete_retention_days > 0 ? [var.blob_properties.delete_retention_days] : []

      content {
        days = delete_retention_policy.value
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.blob_properties.container_delete_retention_days > 0 ? [var.blob_properties.container_delete_retention_days] : []

      content {
        days = container_delete_retention_policy.value
      }
    }
  }

  lifecycle {
    # A storage account holds data: destroying one is always a deliberate
    # decommissioning step that starts by editing this line (prevent_destroy
    # cannot be driven by a variable).
    prevent_destroy = true
  }
}

# Containers are created through Azure Resource Manager (storage_account_id),
# so they need neither Shared Key nor data-plane network access.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = coalesce(each.value.name, each.key)
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = each.value.access_type
  metadata              = each.value.metadata
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = each.value.container_key == null ? azurerm_storage_account.this.id : azurerm_storage_container.this[each.value.container_key].id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  description          = each.value.description
}

resource "azurerm_management_lock" "this" {
  count = var.delete_lock_enabled ? 1 : 0

  name       = "lock-${azurerm_storage_account.this.name}-nodelete"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = var.delete_lock_notes

  # Create the lock last so it never blocks the initial provisioning (a
  # CanNotDelete lock also blocks container deletion).
  depends_on = [
    azurerm_storage_container.this,
    azurerm_role_assignment.this,
  ]
}
