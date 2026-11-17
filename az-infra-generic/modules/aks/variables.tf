# =============================================================================
# General
# =============================================================================

variable "name" {
  description = "Name of the AKS cluster (1-63 characters: letters, digits, hyphens, underscores; must start and end with a letter or digit)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 1-63 characters (letters, digits, '-', '_') and start/end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region of the cluster (e.g. francecentral)."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group in which the cluster and its module-managed resources are created."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix of the API server FQDN. Defaults to a sanitised version of the cluster name. Forces a new cluster when changed."
  type        = string
  default     = null

  validation {
    condition     = var.dns_prefix == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,52}[a-zA-Z0-9])?$", var.dns_prefix))
    error_message = "dns_prefix must be 1-54 characters (letters, digits, hyphens) and start/end with a letter or digit."
  }
}

variable "node_resource_group_name" {
  description = "Name of the AKS-managed node resource group (must not exist yet). Defaults to the AKS naming (MC_<rg>_<cluster>_<region>). Forces a new cluster when changed."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}
