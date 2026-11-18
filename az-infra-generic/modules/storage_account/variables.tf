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

  # try(): a bare address has no prefix (Terraform < 1.12 does not
  # short-circuit && / ||, so every operand must evaluate safely). Comments stay
  # outside expressions: Checkov's HCL parser rejects them there.
  validation {
    condition = alltrue([
      for ip in var.network_rules.ip_rules :
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

# =============================================================================
# Blob data protection
# =============================================================================

variable "blob_properties" {
  description = <<-EOT
    Blob service data protection:
    - versioning_enabled: keep every previous version of a blob when it is overwritten or deleted (default true).
    - delete_retention_days: soft delete of blobs and versions, 1-365 days; 0 disables it (default 30).
    - container_delete_retention_days: soft delete of containers, 1-365 days; 0 disables it (default 30).
  EOT
  type = object({
    versioning_enabled              = optional(bool, true)
    delete_retention_days           = optional(number, 30)
    container_delete_retention_days = optional(number, 30)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for days in [var.blob_properties.delete_retention_days, var.blob_properties.container_delete_retention_days] :
      days == 0 || (days >= 1 && days <= 365 && floor(days) == days)
    ])
    error_message = "blob_properties retention days must be whole numbers between 1 and 365, or 0 to disable soft delete."
  }
}

# =============================================================================
# Blob containers
# =============================================================================

variable "containers" {
  description = <<-EOT
    Blob containers, keyed by a stable identifier (used in resource addresses and in role_assignments[*].container_key, so renaming a key recreates the container):
    - name: container name, 3-63 characters (lowercase letters, digits, single hyphens); defaults to the key.
    - access_type: private (default, Entra ID-authorized access only), blob (anonymous read of blobs) or container (anonymous read and list). Anything but private requires blob_public_access_enabled = true.
    - metadata: name/value pairs; names must be lowercase identifiers (letters, digits, underscores, not starting with a digit).
  EOT
  type = map(object({
    name        = optional(string)
    access_type = optional(string, "private")
    metadata    = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for key, c in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", coalesce(c.name, key))) && !strcontains(coalesce(c.name, key), "--")
    ])
    error_message = "Container names (name, or the key when name is omitted) must be 3-63 lowercase letters, digits or single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(distinct([for key, c in var.containers : coalesce(c.name, key)])) == length(var.containers)
    error_message = "Two containers resolve to the same name."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : contains(["private", "blob", "container"], c.access_type)])
    error_message = "Container access_type must be private, blob or container."
  }

  validation {
    condition     = var.blob_public_access_enabled || alltrue([for c in values(var.containers) : c.access_type == "private"])
    error_message = "Public container access (access_type blob or container) requires blob_public_access_enabled = true."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [for k in keys(c.metadata) : can(regex("^[a-z_][a-z0-9_]*$", k))]
    ]))
    error_message = "Container metadata names must be lowercase identifiers: letters, digits and underscores, not starting with a digit."
  }
}

# =============================================================================
# Access control (Azure RBAC)
# =============================================================================

variable "role_assignments" {
  description = <<-EOT
    Azure RBAC role assignments, keyed by a stable identifier. With Shared Key disabled, data-plane access requires a data role such as "Storage Blob Data Contributor" (read/write, e.g. Terraform state) or "Storage Blob Data Reader".
    - principal_id: object ID of the user, group, service principal or managed identity.
    - role_definition_name: built-in or custom role name.
    - container_key: key in var.containers to scope the assignment to that container only (least privilege); null scopes it to the whole account.
    - description: optional free text stored on the assignment.
  EOT
  type = map(object({
    principal_id         = string
    role_definition_name = string
    container_key        = optional(string)
    description          = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for ra in values(var.role_assignments) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", ra.principal_id))
    ])
    error_message = "role_assignments principal_id values must be object IDs (GUIDs)."
  }

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : length(trimspace(ra.role_definition_name)) > 0])
    error_message = "role_assignments role_definition_name must not be empty."
  }

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : ra.container_key == null || contains(keys(var.containers), coalesce(ra.container_key, "-"))])
    error_message = "role_assignments container_key must be null (account scope) or a key of var.containers."
  }
}

# =============================================================================
# Deletion protection
# =============================================================================

variable "delete_lock_enabled" {
  description = "Place a CanNotDelete management lock on the storage account, in addition to the module's prevent_destroy. Needs Microsoft.Authorization/locks/* (Owner or User Access Administrator). While it exists, deleting the account or one of its containers through Azure Resource Manager fails; blob data-plane operations are not affected."
  type        = bool
  default     = false
  nullable    = false
}

variable "delete_lock_notes" {
  description = "Notes stored on the management lock (why it exists, how to remove it)."
  type        = string
  default     = "Protects the storage account and its containers from deletion. Remove deliberately (delete_lock_enabled = false) before any decommissioning."
  nullable    = false

  validation {
    condition     = length(var.delete_lock_notes) <= 512
    error_message = "delete_lock_notes must be at most 512 characters."
  }
}
