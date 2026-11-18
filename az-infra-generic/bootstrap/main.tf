# =============================================================================
# Remote state bootstrap
#
# Creates the Azure Blob Storage that every other Terraform configuration of
# this project uses as its "azurerm" backend:
#   - one resource group (owned here),
#   - one hardened StorageV2 account through the reusable storage_account
#     module (../modules/storage_account), with one private blob container
#     per environment (tfstate-<env>) plus one (tfstate-bootstrap) that can
#     receive this configuration's own state,
#   - Entra ID data-plane role assignments (no access keys, no SAS),
#   - deletion protection (prevent_destroy in the module + optional
#     CanNotDelete lock).
#
# This configuration runs with LOCAL state because the backend does not exist
# yet. See README "Backend storage bootstrap procedure". Existing states that
# predate the module are migrated by moved.tf.
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

  # Role assignment keys are part of the resource addresses: "current-principal"
  # and "<environment>/<principal_id>" (an environment name never contains "/",
  # so the two families cannot collide). Do not rename them.
  role_assignments = merge(
    {
      for key, enabled in { "current-principal" = var.grant_current_principal_access } : key => {
        # Lets the operator who runs the bootstrap use the backend immediately.
        principal_id         = data.azurerm_client_config.current.object_id
        role_definition_name = "Storage Blob Data Contributor"
        container_key        = null
        description          = "Terraform state access for the identity that ran the bootstrap."
      } if enabled
    },
    {
      # Least privilege for CI/CD identities: access to ONE environment's container.
      for key, pair in local.state_contributor_assignments : key => {
        principal_id         = pair.principal_id
        role_definition_name = "Storage Blob Data Contributor"
        container_key        = pair.container
        description          = "Terraform state access to tfstate-${pair.container} only."
      }
    },
  )

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

module "state_storage" {
  source = "../modules/storage_account"

  # --- Placement: the resource group dependency is implicit through these
  # references, so the group always exists before the account. -----------------
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tags                = local.tags

  # --- Account ------------------------------------------------------------------
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  access_tier              = "Hot"

  # --- Security: Microsoft Entra ID only, matching the backends' and the
  # provider's use_azuread settings. ----------------------------------------------
  shared_access_key_enabled         = false
  blob_public_access_enabled        = false
  infrastructure_encryption_enabled = true
  allowed_copy_scope                = "AAD"

  # --- Network: the public endpoint stays reachable (Entra ID still required)
  # until runner/operator IPs or private endpoints are defined; listing IPs
  # switches the firewall to Deny. ---------------------------------------------------
  public_network_access = var.public_network_access
  network_rules = {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }

  # --- Consistency and recovery --------------------------------------------------
  # State locking relies on native blob leases (no extra resource needed).
  # Versioning + soft delete allow recovering any previous state revision.
  blob_properties = {
    versioning_enabled              = true
    delete_retention_days           = var.blob_soft_delete_retention_days
    container_delete_retention_days = var.container_soft_delete_retention_days
  }

  # Keys = environment names (stable addresses: moved.tf relies on them).
  containers = {
    for env in local.state_containers : env => {
      name        = "tfstate-${env}"
      access_type = "private"
    }
  }

  role_assignments = local.role_assignments

  delete_lock_enabled = var.delete_lock_enabled
  delete_lock_notes   = "Protects the Terraform remote state of every environment. Remove deliberately (delete_lock_enabled = false) before any decommissioning."
}
