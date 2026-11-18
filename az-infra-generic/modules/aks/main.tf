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

  # --- System node pool --------------------------------------------------------------
  default_node_pool {
    name                        = var.default_node_pool.name
    temporary_name_for_rotation = local.default_pool_temporary_name
    vm_size                     = var.default_node_pool.vm_size
    vnet_subnet_id              = var.default_node_pool.vnet_subnet_id
    pod_subnet_id               = var.default_node_pool.pod_subnet_id
    zones                       = var.default_node_pool.zones

    # With autoscaling, node_count is left to the autoscaler (Optional+Computed:
    # null means "not managed", so there is no drift and no ignore_changes).
    auto_scaling_enabled = var.default_node_pool.auto_scaling_enabled
    node_count           = var.default_node_pool.auto_scaling_enabled ? null : var.default_node_pool.node_count
    min_count            = var.default_node_pool.auto_scaling_enabled ? var.default_node_pool.min_count : null
    max_count            = var.default_node_pool.auto_scaling_enabled ? var.default_node_pool.max_count : null
    max_pods             = var.default_node_pool.max_pods

    os_sku                       = var.default_node_pool.os_sku
    os_disk_type                 = var.default_node_pool.os_disk_type
    os_disk_size_gb              = var.default_node_pool.os_disk_size_gb
    only_critical_addons_enabled = var.default_node_pool.only_critical_addons_enabled
    host_encryption_enabled      = var.default_node_pool.host_encryption_enabled
    orchestrator_version         = var.default_node_pool.orchestrator_version
    node_labels                  = var.default_node_pool.node_labels
    tags                         = merge(local.tags, var.default_node_pool.tags)

    upgrade_settings {
      max_surge                     = var.default_node_pool.upgrade_settings.max_surge
      drain_timeout_in_minutes      = var.default_node_pool.upgrade_settings.drain_timeout_in_minutes
      node_soak_duration_in_minutes = var.default_node_pool.upgrade_settings.node_soak_duration_in_minutes
    }
  }

  dynamic "auto_scaler_profile" {
    for_each = var.auto_scaler_profile == null ? [] : [var.auto_scaler_profile]
    iterator = autoscaler

    content {
      balance_similar_node_groups      = autoscaler.value.balance_similar_node_groups
      expander                         = autoscaler.value.expander
      max_graceful_termination_sec     = autoscaler.value.max_graceful_termination_sec
      max_node_provisioning_time       = autoscaler.value.max_node_provisioning_time
      scan_interval                    = autoscaler.value.scan_interval
      scale_down_delay_after_add       = autoscaler.value.scale_down_delay_after_add
      scale_down_unneeded              = autoscaler.value.scale_down_unneeded
      scale_down_utilization_threshold = autoscaler.value.scale_down_utilization_threshold
      skip_nodes_with_local_storage    = autoscaler.value.skip_nodes_with_local_storage
      skip_nodes_with_system_pods      = autoscaler.value.skip_nodes_with_system_pods
    }
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

  # --- Workload security -------------------------------------------------------------
  oidc_issuer_enabled          = var.oidc_issuer_enabled
  workload_identity_enabled    = var.workload_identity_enabled
  azure_policy_enabled         = var.azure_policy_enabled
  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_enabled ? var.image_cleaner_interval_hours : null
  disk_encryption_set_id       = var.disk_encryption_set_id

  dynamic "key_vault_secrets_provider" {
    for_each = var.key_vault_secrets_provider.enabled ? [var.key_vault_secrets_provider] : []
    iterator = kv

    content {
      secret_rotation_enabled  = kv.value.secret_rotation_enabled
      secret_rotation_interval = kv.value.secret_rotation_enabled ? kv.value.secret_rotation_interval : null
    }
  }

  dynamic "key_management_service" {
    for_each = var.key_management_service == null ? [] : [var.key_management_service]
    iterator = kms

    content {
      key_vault_key_id         = kms.value.key_vault_key_id
      key_vault_network_access = kms.value.key_vault_network_access
      key_vault_id             = kms.value.key_vault_id
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.microsoft_defender_enabled ? [1] : []

    content {
      log_analytics_workspace_id = var.monitoring.log_analytics_workspace_id
    }
  }

  # --- Observability -------------------------------------------------------------------
  # Container Insights with managed identity authentication. The data
  # collection rule and its association are declared in monitoring.tf.
  dynamic "oms_agent" {
    for_each = local.container_insights_enabled ? [1] : []

    content {
      log_analytics_workspace_id      = var.monitoring.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # With a user-assigned identity, subnet permissions must exist before the
  # cluster creates its load balancer / egress resources in the subnet.
  depends_on = [azurerm_role_assignment.network_contributor]
}
