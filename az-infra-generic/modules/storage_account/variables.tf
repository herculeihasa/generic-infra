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
