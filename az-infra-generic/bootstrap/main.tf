# =============================================================================
# Remote state bootstrap
#
# Creates the Azure Blob Storage that every other Terraform configuration of
# this project uses as its "azurerm" backend:
#   - one resource group and one hardened StorageV2 account,
#   - one private blob container per environment (tfstate-<env>) plus one
#     (tfstate-bootstrap) that can receive this configuration's own state,
#   - Entra ID data-plane role assignments (no access keys, no SAS),
#   - deletion protection (prevent_destroy + optional CanNotDelete lock).
#
# This configuration runs with LOCAL state because the backend does not exist
# yet. See README "Backend storage bootstrap procedure".
# =============================================================================

data "azurerm_client_config" "current" {}

locals {
  # Short region codes keep names readable; unknown regions fall back to the
  # full region name.
  location_abbreviations = {
    francecentral      = "frc"
    francesouth        = "frs"
    westeurope         = "weu"
    northeurope        = "neu"
    germanywestcentral = "gwc"
    switzerlandnorth   = "chn"
    belgiumcentral     = "bec"
    uksouth            = "uks"
    swedencentral      = "sdc"
    eastus             = "eus"
    eastus2            = "eus2"
  }
  location_short = lookup(local.location_abbreviations, var.location, var.location)

  resource_group_name = coalesce(var.resource_group_name, "rg-${var.project}-tfstate-${local.location_short}")

  # Deterministic suffix derived from the subscription: unique enough for a
  # global namespace, stable across runs, and the subscription ID itself never
  # appears in a resource name.
  storage_account_name = coalesce(
    var.storage_account_name,
    "st${var.project}tfstate${substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.project}"), 0, 6)}",
  )

  # "bootstrap" container: optional destination for this configuration's own
  # state once the account exists (README, option B).
  state_containers = toset(concat(["bootstrap"], var.environments))

  state_contributor_assignments = {
    for pair in flatten([
      for container, principal_ids in var.state_contributors : [
        for principal_id in principal_ids : {
          container    = container
          principal_id = principal_id
        }
      ]
    ]) : "${pair.container}/${pair.principal_id}" => pair
  }

  tags = merge(var.tags, {
    project    = var.project
    purpose    = "terraform-remote-state"
    managed_by = "terraform"
    stack      = "bootstrap"
  })
}

resource "azurerm_resource_group" "tfstate" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tags                = local.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  access_tier              = "Hot"

  # --- Authentication: Microsoft Entra ID only --------------------------------
  shared_access_key_enabled       = false # no account keys, no key-based SAS
  default_to_oauth_authentication = true  # portal uses Entra ID too
  local_user_enabled              = false # no SFTP/local users
  sftp_enabled                    = false

  # --- Transport and exposure ---------------------------------------------------
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = "AAD"
  public_network_access            = var.public_network_access

  # --- Encryption at rest -------------------------------------------------------
  # Azure Storage always encrypts at rest (AES-256, Microsoft-managed keys).
  # Infrastructure encryption adds a second, independent encryption layer.
  infrastructure_encryption_enabled = true

  # --- Consistency and recovery ---------------------------------------------------
  # State locking relies on native blob leases (no extra resource needed).
  # Versioning + soft delete allow recovering any previous state revision.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }

  network_rules {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }

  lifecycle {
    # Losing this account means losing every environment's state.
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  for_each = local.state_containers

  name                  = "tfstate-${each.key}"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Lets the operator who runs the bootstrap use the backend immediately.
resource "azurerm_role_assignment" "current_principal_state_access" {
  count = var.grant_current_principal_access ? 1 : 0

  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Terraform state access for the identity that ran the bootstrap."
}

# Least privilege for CI/CD identities: access to ONE environment's container.
resource "azurerm_role_assignment" "state_contributors" {
  for_each = local.state_contributor_assignments

  scope                = azurerm_storage_container.tfstate[each.value.container].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  description          = "Terraform state access to tfstate-${each.value.container} only."
}

resource "azurerm_management_lock" "tfstate" {
  count = var.delete_lock_enabled ? 1 : 0

  name       = "lock-${azurerm_storage_account.tfstate.name}-nodelete"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Protects the Terraform remote state of every environment. Remove deliberately (delete_lock_enabled = false) before any decommissioning."

  # Create the lock last so it never blocks the initial provisioning.
  depends_on = [
    azurerm_storage_container.tfstate,
    azurerm_role_assignment.current_principal_state_access,
    azurerm_role_assignment.state_contributors,
  ]
}
