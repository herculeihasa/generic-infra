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
