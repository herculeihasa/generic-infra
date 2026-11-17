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
    name           = var.default_node_pool.name
    vm_size        = var.default_node_pool.vm_size
    node_count     = var.default_node_pool.node_count
    vnet_subnet_id = var.default_node_pool.vnet_subnet_id
    pod_subnet_id  = var.default_node_pool.pod_subnet_id
  }

  # --- Networking -------------------------------------------------------------------
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = var.network.cni_mode == "overlay" ? "overlay" : null
    network_data_plane  = var.network.data_plane
    network_policy      = local.network_policy
    pod_cidr            = var.network.cni_mode == "overlay" ? var.network.pod_cidr : null
    service_cidr        = var.network.service_cidr
    dns_service_ip      = var.network.dns_service_ip
    outbound_type       = var.network.outbound_type
    load_balancer_sku   = "standard"

    dynamic "load_balancer_profile" {
      for_each = var.network.load_balancer_profile == null ? [] : [var.network.load_balancer_profile]
      iterator = lb

      content {
        managed_outbound_ip_count = lb.value.managed_outbound_ip_count
        outbound_ip_address_ids   = lb.value.outbound_ip_address_ids
        outbound_ip_prefix_ids    = lb.value.outbound_ip_prefix_ids
        idle_timeout_in_minutes   = lb.value.idle_timeout_in_minutes
        outbound_ports_allocated  = lb.value.outbound_ports_allocated
      }
    }

    dynamic "nat_gateway_profile" {
      for_each = var.network.nat_gateway_profile == null ? [] : [var.network.nat_gateway_profile]
      iterator = nat

      content {
        managed_outbound_ip_count = nat.value.managed_outbound_ip_count
        idle_timeout_in_minutes   = nat.value.idle_timeout_in_minutes
      }
    }
  }

  # --- API server exposure -----------------------------------------------------------
  private_cluster_enabled             = var.private_cluster_enabled
  private_dns_zone_id                 = var.private_cluster_enabled ? var.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = var.private_cluster_enabled ? var.private_cluster_public_fqdn_enabled : null

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []

    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # With a user-assigned identity, subnet permissions must exist before the
  # cluster creates its load balancer / egress resources in the subnet.
  depends_on = [azurerm_role_assignment.network_contributor]
}
