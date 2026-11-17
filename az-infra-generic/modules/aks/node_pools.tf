# =============================================================================
# Additional node pools (User or System, Regular or Spot, Linux)
# =============================================================================

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = local.node_pools

  name                        = each.key
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  mode                        = each.value.mode
  temporary_name_for_rotation = each.value.temporary_name_for_rotation
  vm_size                     = each.value.vm_size
  os_type                     = "Linux"
  os_sku                      = each.value.os_sku
  vnet_subnet_id              = each.value.vnet_subnet_id
  pod_subnet_id               = each.value.pod_subnet_id
  zones                       = each.value.zones

  # Same autoscaling contract as the system pool: null node_count when the
  # autoscaler owns the size.
  auto_scaling_enabled = each.value.auto_scaling_enabled
  node_count           = each.value.auto_scaling_enabled ? null : each.value.node_count
  min_count            = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count            = each.value.auto_scaling_enabled ? each.value.max_count : null
  max_pods             = each.value.max_pods

  os_disk_type            = each.value.os_disk_type
  os_disk_size_gb         = each.value.os_disk_size_gb
  host_encryption_enabled = each.value.host_encryption_enabled
  orchestrator_version    = each.value.orchestrator_version
  node_labels             = each.value.node_labels
  node_taints             = each.value.node_taints
  tags                    = merge(local.tags, each.value.tags)

  priority        = each.value.priority
  eviction_policy = each.value.is_spot ? each.value.eviction_policy : null
  spot_max_price  = each.value.is_spot ? each.value.spot_max_price : null

  # Surge upgrades are not available for Spot pools.
  dynamic "upgrade_settings" {
    for_each = each.value.is_spot ? [] : [each.value.upgrade_settings]
    iterator = upgrade

    content {
      max_surge                     = upgrade.value.max_surge
      drain_timeout_in_minutes      = upgrade.value.drain_timeout_in_minutes
      node_soak_duration_in_minutes = upgrade.value.node_soak_duration_in_minutes
    }
  }
}

# The system pool is tainted CriticalAddonsOnly by default: without a User
# pool, application pods would stay Pending. Reported as a plan warning.
check "workload_node_pool" {
  assert {
    condition     = !var.default_node_pool.only_critical_addons_enabled || anytrue([for pool in values(var.node_pools) : pool.mode == "User"])
    error_message = "The system node pool only accepts critical add-ons (only_critical_addons_enabled = true) and no User node pool is defined: application pods cannot be scheduled. Add a User pool to node_pools or set default_node_pool.only_critical_addons_enabled = false."
  }
}
