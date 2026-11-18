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
