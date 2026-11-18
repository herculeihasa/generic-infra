# =============================================================================
# Generic Azure Storage Account module
#
# File layout:
#   versions.tf    Terraform / provider minimum versions (no provider block)
#   variables.tf   Module interface (inputs, defaults, validations)
#   locals.tf      Derived values
#   main.tf        The storage account
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

  # --- Authentication: Microsoft Entra ID only --------------------------------
  shared_access_key_enabled       = false # no account keys, no key-based SAS
  default_to_oauth_authentication = true  # portal uses Entra ID too
  local_user_enabled              = false # no SFTP/local users
  sftp_enabled                    = false

  # --- Transport and exposure ---------------------------------------------------
  # Not configurable: secure transfer is always required, and TLS1_2 is the
  # only minimum version Azure Storage and azurerm 5.x accept (TLS 1.0/1.1 are
  # retired). Expose a variable once a higher minimum becomes available.
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = "AAD"
  public_network_access            = "Disabled"

  # --- Encryption at rest -------------------------------------------------------
  # Azure Storage always encrypts at rest (AES-256, Microsoft-managed keys).
  # Infrastructure encryption adds a second, independent encryption layer.
  infrastructure_encryption_enabled = true

  # --- Recovery -----------------------------------------------------------------
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  lifecycle {
    # A storage account holds data: destroying one is always a deliberate
    # decommissioning step that starts by editing this line (prevent_destroy
    # cannot be driven by a variable).
    prevent_destroy = true
  }
}
