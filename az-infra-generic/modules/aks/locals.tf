locals {
  # DNS prefix: lowercase, only letters/digits/hyphens, max 54 characters,
  # no leading/trailing hyphen.
  dns_prefix = coalesce(
    var.dns_prefix,
    trim(substr(replace(lower(var.name), "/[^a-z0-9-]/", "-"), 0, 54), "-"),
  )

  tags = merge(var.tags, {
    managed_by = "terraform"
    module     = "aks"
  })

  # --- Networking -----------------------------------------------------------------
  # "none" is an explicit sentinel because optional() defaults cannot be
  # overridden with null. null lets AKS run without a network policy engine.
  network_policy = var.network.policy == "none" ? null : var.network.policy

  # --- Node pools -----------------------------------------------------------------
  # Rotation names: "t" + 11 hex characters of a hash of the pool name, so they
  # are valid (lowercase alphanumeric, <= 12 chars) and unique per pool.
  default_pool_temporary_name = coalesce(
    var.default_node_pool.temporary_name_for_rotation,
    "t${substr(sha1("rotation/${var.default_node_pool.name}"), 0, 11)}",
  )

  # AKS adds this label and taint to every Spot node; declaring them avoids a
  # permanent diff on Spot pools.
  spot_label = { "kubernetes.azure.com/scalesetpriority" = "spot" }
  spot_taint = "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

  node_pools = {
    for name, pool in var.node_pools : name => merge(pool, {
      temporary_name_for_rotation = "t${substr(sha1("rotation/${name}"), 0, 11)}"
      is_spot                     = pool.priority == "Spot"
      vnet_subnet_id              = pool.vnet_subnet_id != null ? pool.vnet_subnet_id : var.default_node_pool.vnet_subnet_id
      pod_subnet_id               = pool.pod_subnet_id != null ? pool.pod_subnet_id : var.default_node_pool.pod_subnet_id
      node_labels                 = pool.priority == "Spot" ? merge(pool.node_labels, local.spot_label) : pool.node_labels
      node_taints                 = pool.priority == "Spot" ? distinct(concat(pool.node_taints, [local.spot_taint])) : pool.node_taints
    })
  }

  # --- Observability ----------------------------------------------------------------
  # Decided from static flags only (never from IDs that may be unknown at plan).
  container_insights_enabled  = var.monitoring != null && try(var.monitoring.container_insights_enabled, false)
  diagnostic_settings_enabled = var.monitoring != null && try(var.monitoring.diagnostic_settings_enabled, false)

  data_collection_rule_location = coalesce(try(var.monitoring.data_collection_rule_location, null), var.location)

  # --- API server endpoint ------------------------------------------------------------
  # Private clusters: the private FQDN (falls back to the public FQDN when
  # private_dns_zone_id = "None" and only the public record exists).
  api_server_fqdn = (
    var.private_cluster_enabled ?
    try(coalesce(azurerm_kubernetes_cluster.this.private_fqdn, azurerm_kubernetes_cluster.this.fqdn), null) :
    azurerm_kubernetes_cluster.this.fqdn
  )

  # --- Control plane identity ---------------------------------------------------
  create_cluster_identity = var.identity_type == "UserAssigned" && var.user_assigned_identity == null

  # { id, principal_id } of the user-assigned control plane identity, or null
  # for SystemAssigned (its principal is only known after the cluster exists).
  cluster_user_assigned_identity = (
    var.identity_type != "UserAssigned" ? null :
    local.create_cluster_identity ? {
      id           = azurerm_user_assigned_identity.cluster[0].id
      principal_id = azurerm_user_assigned_identity.cluster[0].principal_id
    } :
    var.user_assigned_identity
  )
}
