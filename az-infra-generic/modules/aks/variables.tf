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

# =============================================================================
# Cluster version, tier and upgrades
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane. Null = AKS default at creation. With automatic_upgrade_channel = \"patch\" use MAJOR.MINOR (e.g. \"1.33\"); with \"stable\"/\"rapid\" leave null, since AKS then moves the minor version itself."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like MAJOR.MINOR or MAJOR.MINOR.PATCH (e.g. 1.33 or 1.33.2)."
  }

  validation {
    condition = (
      var.kubernetes_version == null ? true :
      contains(["stable", "rapid"], coalesce(var.automatic_upgrade_channel, "none")) ? false :
      var.automatic_upgrade_channel == "patch" ? can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version)) :
      true
    )
    error_message = "Avoid upgrade drift: with automatic_upgrade_channel = \"patch\" set kubernetes_version to MAJOR.MINOR (no patch); with \"stable\" or \"rapid\" leave kubernetes_version null."
  }
}

variable "sku_tier" {
  description = "AKS control plane tier: Free (no SLA, dev/test), Standard (financially backed SLA, recommended for production) or Premium (Standard + Long Term Support)."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "support_plan" {
  description = "Support plan: KubernetesOfficial or AKSLongTermSupport (requires sku_tier = Premium)."
  type        = string
  default     = "KubernetesOfficial"

  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be KubernetesOfficial or AKSLongTermSupport."
  }

  validation {
    condition     = var.support_plan != "AKSLongTermSupport" || var.sku_tier == "Premium"
    error_message = "support_plan = AKSLongTermSupport requires sku_tier = Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "Cluster auto-upgrade channel: patch (recommended), stable, rapid, node-image, or null for no automatic Kubernetes upgrades."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["patch", "stable", "rapid", "node-image", "none"], coalesce(var.automatic_upgrade_channel, "none"))
    error_message = "automatic_upgrade_channel must be patch, stable, rapid, node-image or null."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS image upgrade channel: NodeImage (recommended), SecurityPatch, Unmanaged or None."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be NodeImage, SecurityPatch, Unmanaged or None."
  }

  validation {
    condition     = coalesce(var.automatic_upgrade_channel, "none") != "node-image" || var.node_os_upgrade_channel == "NodeImage"
    error_message = "node_os_upgrade_channel must be NodeImage when automatic_upgrade_channel = \"node-image\"."
  }
}

variable "maintenance_windows" {
  description = <<-EOT
    Planned maintenance windows. `auto_upgrade` constrains cluster auto-upgrades,
    `node_os` constrains node OS image updates. A null window means "any time".
    Each window: frequency (Daily | Weekly | AbsoluteMonthly | RelativeMonthly),
    interval, duration in hours (4-24), day_of_week (Weekly, RelativeMonthly),
    day_of_month (AbsoluteMonthly), week_index (RelativeMonthly: First..Last),
    start_time ("HH:mm"), utc_offset ("+01:00"), not_allowed periods (RFC3339).
  EOT
  type = object({
    auto_upgrade = optional(object({
      frequency    = string
      interval     = optional(number, 1)
      duration     = optional(number, 4)
      day_of_week  = optional(string)
      day_of_month = optional(number)
      week_index   = optional(string)
      start_time   = optional(string)
      utc_offset   = optional(string)
      not_allowed  = optional(list(object({ start = string, end = string })), [])
    }))
    node_os = optional(object({
      frequency    = string
      interval     = optional(number, 1)
      duration     = optional(number, 4)
      day_of_week  = optional(string)
      day_of_month = optional(number)
      week_index   = optional(string)
      start_time   = optional(string)
      utc_offset   = optional(string)
      not_allowed  = optional(list(object({ start = string, end = string })), [])
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] :
      contains(["Daily", "Weekly", "AbsoluteMonthly", "RelativeMonthly"], w.frequency) && w.duration >= 4 && w.duration <= 24 && w.interval >= 1
      if w != null
    ])
    error_message = "Maintenance window frequency must be Daily, Weekly, AbsoluteMonthly or RelativeMonthly; duration 4-24 hours; interval >= 1."
  }

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] : (
        w.frequency == "Weekly" ? w.day_of_week != null :
        w.frequency == "AbsoluteMonthly" ? w.day_of_month != null :
        w.frequency == "RelativeMonthly" ? (w.day_of_week != null && w.week_index != null) :
        true
      )
      if w != null
    ])
    error_message = "Weekly windows need day_of_week, AbsoluteMonthly needs day_of_month, RelativeMonthly needs day_of_week and week_index."
  }

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] :
      w.start_time == null ? true : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", w.start_time))
      if w != null
    ])
    error_message = "Maintenance window start_time must use the HH:mm format."
  }
}

# =============================================================================
# Identity
# =============================================================================

variable "identity_type" {
  description = "Control plane managed identity: UserAssigned (recommended: its principal exists before the cluster, so network/DNS permissions can be granted first) or SystemAssigned."
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["UserAssigned", "SystemAssigned"], var.identity_type)
    error_message = "identity_type must be UserAssigned or SystemAssigned."
  }
}

variable "user_assigned_identity" {
  description = "Existing user-assigned identity for the control plane ({ id, principal_id }). Null with identity_type = UserAssigned makes the module create one named id-<cluster name>. Bring your own when it must hold permissions before the module runs (e.g. Private DNS Zone Contributor on a custom zone)."
  type = object({
    id           = string
    principal_id = string
  })
  default = null

  validation {
    condition     = var.user_assigned_identity == null || var.identity_type == "UserAssigned"
    error_message = "user_assigned_identity can only be set when identity_type = \"UserAssigned\"."
  }

  validation {
    condition     = var.user_assigned_identity == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", var.user_assigned_identity.id))
    error_message = "user_assigned_identity.id must be the resource ID of a user-assigned managed identity."
  }
}

# =============================================================================
# Access control
# =============================================================================

variable "entra_id_rbac" {
  description = "AKS-managed Microsoft Entra ID integration. azure_rbac_enabled = true authorises Kubernetes access with Azure role assignments; admin_group_object_ids get cluster-admin. tenant_id defaults to the provider's tenant. Null disables the integration (only possible with local accounts enabled)."
  type = object({
    azure_rbac_enabled     = optional(bool, true)
    admin_group_object_ids = optional(list(string), [])
    tenant_id              = optional(string)
  })
  default = {}

  validation {
    condition = var.entra_id_rbac == null ? true : alltrue([
      for id in var.entra_id_rbac.admin_group_object_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "entra_id_rbac.admin_group_object_ids must contain Entra ID group object IDs (GUIDs)."
  }
}

variable "local_account_disabled" {
  description = "Disable the static local admin kubeconfig so every access goes through Microsoft Entra ID (recommended). Requires entra_id_rbac."
  type        = bool
  default     = true

  validation {
    condition     = !var.local_account_disabled || var.entra_id_rbac != null
    error_message = "local_account_disabled = true requires entra_id_rbac (Entra ID integration) to be enabled."
  }
}

variable "run_command_enabled" {
  description = "Allow `az aks command invoke` (runs kubectl through the Azure API). Useful for private clusters without network line of sight; disabled by default to reduce the attack surface."
  type        = bool
  default     = false
}

# =============================================================================
# Default (system) node pool
# =============================================================================

variable "default_node_pool" {
  description = "System node pool configuration."
  type = object({
    name       = optional(string, "system")
    vm_size    = optional(string, "Standard_D4ds_v5")
    node_count = optional(number, 3)
  })
  default  = {}
  nullable = false
}
