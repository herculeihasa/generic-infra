# =============================================================================
# Generic Azure Kubernetes Service (AKS) module
#
# File layout:
#   versions.tf    Terraform / provider minimum versions (no provider block)
#   variables.tf   Module interface (inputs, defaults, validations)
#   locals.tf      Derived values
#   identity.tf    Control plane identity
#   main.tf        The AKS cluster
#   outputs.tf     Module outputs
#   tests/         Offline `terraform test` suites (mocked azurerm provider)
#
# The module never creates the resource group, virtual network, Log Analytics
# workspace or Key Vault: those are owned by the calling configuration and
# passed in by ID, so the module can be reused across projects/environments.
# =============================================================================

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.dns_prefix
  node_resource_group = var.node_resource_group_name
  tags                = local.tags

  # --- Version, tier and upgrades -----------------------------------------------
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.sku_tier
  support_plan              = var.support_plan
  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  dynamic "maintenance_window_auto_upgrade" {
    for_each = var.maintenance_windows.auto_upgrade == null ? [] : [var.maintenance_windows.auto_upgrade]
    iterator = window

    content {
      frequency    = window.value.frequency
      interval     = window.value.interval
      duration     = window.value.duration
      day_of_week  = window.value.day_of_week
      day_of_month = window.value.day_of_month
      week_index   = window.value.week_index
      start_time   = window.value.start_time
      utc_offset   = window.value.utc_offset

      dynamic "not_allowed" {
        for_each = window.value.not_allowed
        content {
          start = not_allowed.value.start
          end   = not_allowed.value.end
        }
      }
    }
  }

  dynamic "maintenance_window_node_os" {
    for_each = var.maintenance_windows.node_os == null ? [] : [var.maintenance_windows.node_os]
    iterator = window

    content {
      frequency    = window.value.frequency
      interval     = window.value.interval
      duration     = window.value.duration
      day_of_week  = window.value.day_of_week
      day_of_month = window.value.day_of_month
      week_index   = window.value.week_index
      start_time   = window.value.start_time
      utc_offset   = window.value.utc_offset

      dynamic "not_allowed" {
        for_each = window.value.not_allowed
        content {
          start = not_allowed.value.start
          end   = not_allowed.value.end
        }
      }
    }
  }

  # --- Identity -------------------------------------------------------------------
  identity {
    type         = var.identity_type
    identity_ids = local.cluster_user_assigned_identity == null ? null : [local.cluster_user_assigned_identity.id]
  }

  # --- Access control ---------------------------------------------------------------
  # Kubernetes RBAC is always on (turning it off later forces a new cluster).
  role_based_access_control_enabled = true
  local_account_disabled            = var.local_account_disabled
  run_command_enabled               = var.run_command_enabled

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.entra_id_rbac == null ? [] : [var.entra_id_rbac]
    iterator = entra

    content {
      azure_rbac_enabled     = entra.value.azure_rbac_enabled
      admin_group_object_ids = entra.value.admin_group_object_ids
      tenant_id              = entra.value.tenant_id
    }
  }

  # --- Node provisioning --------------------------------------------------------------
  # Required block in azurerm 5.x. Node pools are declared explicitly
  # (default_node_pool + node pools); Node Auto-Provisioning is not used.
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name       = var.default_node_pool.name
    vm_size    = var.default_node_pool.vm_size
    node_count = var.default_node_pool.node_count
  }

  # Azure CNI Overlay. Made configurable in the networking layer of the module.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }
}
