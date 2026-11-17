# =============================================================================
# Environment: dev
#
# Owns the environment-level resources (resource group, network, Log
# Analytics workspace) and instantiates the generic AKS module with them.
# =============================================================================

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = local.names.virtual_network
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = local.names.aks_subnet
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_nodes_subnet_prefix]

  # No implicit internet egress: nodes leave through the cluster's explicit
  # outbound path (standard load balancer outbound rules by default).
  default_outbound_access_enabled = false
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.names.log_analytics
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  # Entra ID only: Container Insights uses managed identity authentication.
  local_authentication_enabled = false

  tags = local.tags
}

# -----------------------------------------------------------------------------
# AKS
# -----------------------------------------------------------------------------

module "aks" {
  source = "../../modules/aks"

  name                = local.names.aks_cluster
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  sku_tier           = var.aks_sku_tier
  kubernetes_version = var.kubernetes_version

  # Upgrades happen in a weekend night window (Europe/Paris winter offset).
  maintenance_windows = {
    auto_upgrade = {
      frequency   = "Weekly"
      day_of_week = "Sunday"
      start_time  = "02:00"
      utc_offset  = "+01:00"
    }
    node_os = {
      frequency   = "Weekly"
      day_of_week = "Saturday"
      start_time  = "02:00"
      utc_offset  = "+01:00"
    }
  }

  # Networking: Azure CNI Overlay + Cilium (module defaults) in our subnet.
  network_contributor_subnet_ids = {
    nodes = azurerm_subnet.aks_nodes.id
  }
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges

  default_node_pool = {
    vm_size        = var.system_node_pool.vm_size
    vnet_subnet_id = azurerm_subnet.aks_nodes.id
    min_count      = var.system_node_pool.min_count
    max_count      = var.system_node_pool.max_count
    zones          = var.system_node_pool.zones
  }

  node_pools = var.workload_node_pools

  # Access: Entra ID + Azure RBAC, no local accounts (module defaults).
  entra_id_rbac = {
    admin_group_object_ids = var.aks_admin_group_object_ids
  }
  cluster_admin_principal_ids = var.grant_deployer_cluster_admin ? {
    deployer = data.azurerm_client_config.current.object_id
  } : {}

  monitoring = {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }
}
