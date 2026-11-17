# =============================================================================
# Control plane identity
#
# A user-assigned identity is created unless the caller brings one or chooses
# SystemAssigned. Because it exists before the cluster, permissions it needs
# (e.g. Network Contributor on the node subnet) are granted BEFORE the cluster
# is created, which avoids the classic BYO-VNet race of system identities.
# =============================================================================

resource "azurerm_user_assigned_identity" "cluster" {
  count = local.create_cluster_identity ? 1 : 0

  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}
