# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

variable "resource_providers_to_register" {
  description = "Azure Resource Providers the azurerm provider registers on the subscription at start-up (azurerm 5.x registers none by default). Set to [] when Resource Provider registration is managed outside Terraform or the identity lacks the */register/action permission."
  type        = list(string)
  default     = ["Microsoft.Storage"]
}

# -----------------------------------------------------------------------------
# Naming and placement
# -----------------------------------------------------------------------------

variable "project" {
  description = "Short project code used in resource names (lowercase letters and digits, 2-9 characters so that the generated storage account name stays within 24 characters)."
  type        = string
  default     = "azinfra"

  validation {
    condition     = can(regex("^[a-z0-9]{2,9}$", var.project))
    error_message = "project must be 2-9 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region hosting the Terraform state storage (e.g. francecentral)."
  type        = string
  default     = "francecentral"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name in its short form (lowercase, no spaces), e.g. francecentral."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group holding the state storage. Defaults to rg-<project>-tfstate-<region>."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Globally unique name of the state storage account. Defaults to st<project>tfstate<6-char hash of the subscription ID>, which is deterministic, collision-resistant and does not reveal the subscription ID."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters or digits."
  }
}

variable "tags" {
  description = "Additional tags applied to every bootstrap resource."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# State isolation
# -----------------------------------------------------------------------------

variable "environments" {
  description = "Environments that get their own state container (tfstate-<environment>). One container per environment allows least-privilege RBAC at container scope."
  type        = list(string)
  default     = ["dev", "rec", "ppr", "prod"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : can(regex("^[a-z0-9-]{2,20}$", e))])
    error_message = "environments must be a non-empty list of 2-20 character lowercase names (letters, digits, hyphens)."
  }

  validation {
    condition     = !contains(var.environments, "bootstrap")
    error_message = "\"bootstrap\" is reserved for the tfstate-bootstrap container."
  }
}

variable "state_contributors" {
  description = "Map of environment (or \"bootstrap\") => list of Entra ID principal object IDs (CI/CD identities, operators) granted \"Storage Blob Data Contributor\" on that container only."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.state_contributors) : contains(concat(var.environments, ["bootstrap"]), k)])
    error_message = "Every key of state_contributors must be one of var.environments or \"bootstrap\"."
  }

  validation {
    condition = alltrue(flatten([
      for ids in values(var.state_contributors) : [
        for id in ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
      ]
    ]))
    error_message = "state_contributors values must be principal object IDs (GUIDs)."
  }
}

variable "grant_current_principal_access" {
  description = "Grant the identity running the bootstrap \"Storage Blob Data Contributor\" on the whole state account, so it can run terraform init/plan/apply for every environment right away."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Storage hardening
# -----------------------------------------------------------------------------

variable "account_replication_type" {
  description = "Replication of the state storage account. ZRS survives a zone outage; GZRS/RAGZRS add a secondary region."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "blob_soft_delete_retention_days" {
  description = "Days a deleted or overwritten state blob (and its versions) can be recovered."
  type        = number
  default     = 30

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "blob_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Days a deleted state container can be recovered."
  type        = number
  default     = 30

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "container_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "public_network_access" {
  description = "Public network access to the state account: Enabled (optionally restricted by allowed_ip_ranges), Disabled (private endpoint only; runners need private connectivity) or SecuredByPerimeter."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled", "SecuredByPerimeter"], var.public_network_access)
    error_message = "public_network_access must be Enabled, Disabled or SecuredByPerimeter."
  }
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses/CIDRs allowed to reach the state account. Empty = no IP filtering (authentication is still Entra ID only). /31 and /32 are not accepted by Azure: use the bare address instead."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges :
      can(cidrhost(strcontains(ip, "/") ? ip : "${ip}/32", 0)) && try(tonumber(split("/", ip)[1]), 0) <= 30
    ])
    error_message = "allowed_ip_ranges must contain IPv4 addresses or CIDR ranges with a prefix of /30 or shorter (Azure rejects /31 and /32: use the bare address)."
  }
}

variable "delete_lock_enabled" {
  description = "Place a CanNotDelete management lock on the state storage account (Azure-side protection in addition to Terraform's prevent_destroy)."
  type        = bool
  default     = true
}
