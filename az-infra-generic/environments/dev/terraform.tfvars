# -----------------------------------------------------------------------------
# dev environment: NON-SENSITIVE values only (this file is committed).
# Subscription, tenant and credentials are never set here: they come from the
# ARM_* environment variables or the Azure CLI session (see README).
# -----------------------------------------------------------------------------

project     = "azinfra"
environment = "dev"
location    = "francecentral"

tags = {}

# Network (Azure CNI Overlay: pods use 10.244.0.0/16 and services
# 172.16.0.0/16 by default, outside of this VNet).
vnet_address_space      = ["10.10.0.0/16"]
aks_nodes_subnet_prefix = "10.10.0.0/22"

# AKS
aks_sku_tier = "Free" # no uptime SLA: acceptable for dev only

# TODO(azure-access): pin MAJOR.MINOR after checking the supported versions:
#   az aks get-versions --location francecentral --output table
kubernetes_version = null

system_node_pool = {
  vm_size   = "Standard_D2ds_v5"
  min_count = 1
  max_count = 3
}

workload_node_pools = {
  apps = {
    vm_size   = "Standard_D4ds_v5"
    min_count = 1
    max_count = 3
  }
}

# TODO(azure-access): object IDs of the Entra ID group(s) administering the
# cluster, e.g. az ad group show --group "<group name>" --query id -o tsv
aks_admin_group_object_ids = []

# dev only: the identity running Terraform becomes cluster admin so the
# cluster is usable before admin groups exist.
grant_deployer_cluster_admin = true

# TODO(azure-access): restrict the public API server to known egress IPs.
api_server_authorized_ip_ranges = []

log_analytics_retention_days = 30
