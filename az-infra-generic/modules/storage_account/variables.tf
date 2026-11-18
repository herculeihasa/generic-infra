# =============================================================================
# General
# =============================================================================

variable "name" {
  description = "Globally unique name of the storage account (3-24 lowercase letters and digits). Forces a new account when changed."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Existing resource group in which the storage account is created. The module never creates the resource group."
  type        = string

  validation {
    condition     = can(regex("^[-\\w.()]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be 1-90 characters (letters, digits, '-', '_', '.', '(', ')') and must not end with a period."
  }
}

variable "location" {
  description = "Azure region of the storage account, in its short form (e.g. francecentral)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name in its short form (lowercase, no spaces), e.g. francecentral."
  }
}

variable "tags" {
  description = "Tags applied to the storage account. The module adds managed_by and module."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Account kind, performance and redundancy
# =============================================================================

variable "account_kind" {
  description = "Account kind: StorageV2 (general-purpose v2, Standard performance) or BlockBlobStorage (Premium block blobs, low latency). Forces a new account when changed."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage"], var.account_kind)
    error_message = "account_kind must be StorageV2 or BlockBlobStorage (the module manages blob containers; FileStorage and legacy kinds are not supported)."
  }
}

variable "account_tier" {
  description = "Performance tier. Must match account_kind: Standard for StorageV2, Premium for BlockBlobStorage. Forces a new account when changed."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }

  validation {
    condition     = var.account_tier == (var.account_kind == "BlockBlobStorage" ? "Premium" : "Standard")
    error_message = "account_tier must be Standard with account_kind StorageV2 and Premium with BlockBlobStorage (premium page blob accounts are not supported by this module)."
  }
}

variable "account_replication_type" {
  description = "Redundancy: LRS (one datacenter), ZRS (three zones, survives a zone outage), GRS/RAGRS (LRS + secondary region), GZRS/RAGZRS (ZRS + secondary region). Premium accounts support LRS and ZRS only. ZRS/GZRS require a region with availability zones."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }

  validation {
    condition     = var.account_tier == "Standard" || contains(["LRS", "ZRS"], var.account_replication_type)
    error_message = "Premium accounts only support LRS or ZRS replication."
  }
}

variable "access_tier" {
  description = "Default access tier of blobs in a Standard account: Hot (frequent access), Cool (30+ days) or Cold (90+ days). Ignored for Premium (BlockBlobStorage) accounts, which have no access tier."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Cold"], var.access_tier)
    error_message = "access_tier must be Hot, Cool or Cold."
  }
}

# =============================================================================
# Authentication and data security
# =============================================================================

variable "shared_access_key_enabled" {
  description = "Allow Shared Key authorization (account keys, key-based SAS, connection strings). Default false: every data-plane request must use Microsoft Entra ID (Azure RBAC data roles). Callers then need `storage_use_azuread = true` in their azurerm provider and `use_azuread_auth = true` in an azurerm backend."
  type        = bool
  default     = false
  nullable    = false
}

variable "blob_public_access_enabled" {
  description = "Allow containers to be configured for anonymous public read access (allow_nested_items_to_be_public). Default false; required only if a container uses access_type \"blob\" or \"container\"."
  type        = bool
  default     = false
  nullable    = false
}

variable "infrastructure_encryption_enabled" {
  description = "Add a second, infrastructure-level encryption layer (double encryption) on top of the always-on service encryption. Forces a new account when changed."
  type        = bool
  default     = true
  nullable    = false
}

variable "allowed_copy_scope" {
  description = "Restrict copy operations (Copy Blob, AzCopy) to sources in the same Microsoft Entra tenant (\"AAD\") or reachable through private links to the same virtual network (\"PrivateLink\"). Null allows any source."
  type        = string
  default     = "AAD"

  validation {
    condition     = contains(["AAD", "PrivateLink"], coalesce(var.allowed_copy_scope, "AAD"))
    error_message = "allowed_copy_scope must be AAD, PrivateLink or null."
  }
}

# =============================================================================
# Network access
# =============================================================================

variable "public_network_access" {
  description = "Public endpoint exposure: Disabled (default, private endpoints only: clients, CI runners and Terraform itself need private connectivity for data-plane access), Enabled (public endpoint filtered by network_rules) or SecuredByPerimeter (governed by a Network Security Perimeter)."
  type        = string
  default     = "Disabled"

  validation {
    condition     = contains(["Enabled", "Disabled", "SecuredByPerimeter"], var.public_network_access)
    error_message = "public_network_access must be Enabled, Disabled or SecuredByPerimeter."
  }
}

variable "network_rules" {
  description = <<-EOT
    Firewall of the public endpoint (effective when public_network_access = "Enabled"):
    - default_action: Deny (default, only the listed sources are allowed) or Allow.
    - bypass: trusted traffic allowed regardless of the rules: AzureServices, Logging, Metrics, or None alone.
    - ip_rules: public IPv4 addresses or CIDR ranges (prefix /30 at most; Azure rejects /31 and /32, use the bare address; private ranges are not accepted by Azure).
    - virtual_network_subnet_ids: subnets allowed through a Microsoft.Storage service endpoint.
  EOT
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(set(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "network_rules.default_action must be Allow or Deny."
  }

  validation {
    condition = (
      length(setsubtract(var.network_rules.bypass, ["AzureServices", "Logging", "Metrics", "None"])) == 0 &&
      (!contains(var.network_rules.bypass, "None") || length(var.network_rules.bypass) == 1)
    )
    error_message = "network_rules.bypass must contain AzureServices, Logging and/or Metrics, or None alone."
  }

  validation {
    condition = alltrue([
      for ip in var.network_rules.ip_rules :
      # try(): a bare address has no prefix (Terraform < 1.12 does not
      # short-circuit && / ||, so every operand must evaluate safely).
      can(cidrhost(strcontains(ip, "/") ? ip : "${ip}/32", 0)) && try(tonumber(split("/", ip)[1]), 0) <= 30
    ])
    error_message = "network_rules.ip_rules must be IPv4 addresses or CIDR ranges with a prefix of /30 or shorter (Azure rejects /31 and /32: use the bare address)."
  }

  validation {
    condition = alltrue([
      for id in var.network_rules.virtual_network_subnet_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "network_rules.virtual_network_subnet_ids must be subnet resource IDs."
  }
}
