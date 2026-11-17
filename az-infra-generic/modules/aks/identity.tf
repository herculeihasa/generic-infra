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

# Bring-your-own VNet: the control plane manages load balancers, public IPs
# and egress in the node/pod subnets. Keys are static so that for_each works
# even when the subnet IDs are only known after apply.
resource "azurerm_role_assignment" "network_contributor" {
  for_each = local.cluster_user_assigned_identity == null ? {} : var.network_contributor_subnet_ids

  scope                            = each.value
  role_definition_name             = "Network Contributor"
  principal_id                     = local.cluster_user_assigned_identity.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "AKS ${var.name} control plane: manage networking in subnet '${each.key}'."
}
