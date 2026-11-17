# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

variable "resource_providers_to_register" {
  description = "Azure Resource Providers the azurerm provider registers on the subscription at start-up (azurerm 5.x registers none by default). Set to [] when Resource Provider registration is managed outside Terraform or the identity lacks the */register/action permission."
  type        = list(string)
  default = [
    "Microsoft.Compute",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
  ]
}

# -----------------------------------------------------------------------------
# Naming and placement
# -----------------------------------------------------------------------------

variable "project" {
  description = "Short project code used in resource names (lowercase letters and digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.project))
    error_message = "project must be 2-12 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment name used in resource names and tags. Must match the state container of backend.tf (tfstate-<environment>)."
  type        = string

  validation {
    condition     = contains(["dev", "rec", "ppr", "prod"], var.environment)
    error_message = "environment must be one of dev, rec, ppr, prod."
  }
}

variable "location" {
  description = "Azure region of the environment (e.g. francecentral)."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to every resource of the environment."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space of the environment virtual network. Must not overlap the AKS pod and service CIDRs."
  type        = list(string)
}

variable "aks_nodes_subnet_prefix" {
  description = "CIDR of the AKS node subnet (Azure CNI Overlay: only nodes consume VNet IPs; plan for max nodes + surge)."
  type        = string

  validation {
    condition     = can(cidrhost(var.aks_nodes_subnet_prefix, 0))
    error_message = "aks_nodes_subnet_prefix must be a valid CIDR."
  }
}

# -----------------------------------------------------------------------------
# AKS
# -----------------------------------------------------------------------------

variable "aks_sku_tier" {
  description = "AKS control plane tier (Free for dev/test, Standard for SLA-backed environments)."
  type        = string
  default     = "Standard"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version as MAJOR.MINOR (patch upgrades are automatic). Null = AKS default at creation."
  type        = string
  default     = null
}

variable "system_node_pool" {
  description = "System node pool sizing."
  type = object({
    vm_size   = optional(string, "Standard_D2ds_v5")
    min_count = optional(number, 1)
    max_count = optional(number, 3)
    zones     = optional(list(string), ["1", "2", "3"])
  })
  default  = {}
  nullable = false
}

variable "workload_node_pools" {
  description = "User node pools for application workloads, keyed by pool name."
  type = map(object({
    vm_size     = string
    min_count   = optional(number, 1)
    max_count   = optional(number, 3)
    zones       = optional(list(string), ["1", "2", "3"])
    priority    = optional(string, "Regular")
    node_labels = optional(map(string), {})
    node_taints = optional(list(string), [])
  }))
  default = {}
}

variable "aks_admin_group_object_ids" {
  description = "Object IDs of the Entra ID groups granted cluster-admin on the cluster."
  type        = list(string)
  default     = []
}

variable "grant_deployer_cluster_admin" {
  description = "Grant the identity running Terraform \"Azure Kubernetes Service RBAC Cluster Admin\" on the cluster (avoids lock-out before admin groups exist). Prefer admin groups beyond dev."
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = "Public CIDRs allowed to reach the API server. Empty = unrestricted (Entra ID authentication still required)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "log_analytics_retention_days" {
  description = "Retention of the environment Log Analytics workspace (30-730 days)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}
