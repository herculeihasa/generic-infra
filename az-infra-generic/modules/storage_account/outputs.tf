# =============================================================================
# Storage account
# =============================================================================

output "id" {
  description = "Resource ID of the storage account (scope for Azure RBAC role assignments)."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource_group_name" {
  description = "Resource group of the storage account."
  value       = azurerm_storage_account.this.resource_group_name
}

output "location" {
  description = "Azure region of the storage account, as configured."
  value       = azurerm_storage_account.this.location
}

output "primary_location" {
  description = "Primary region reported by Azure."
  value       = azurerm_storage_account.this.primary_location
}

output "secondary_location" {
  description = "Secondary (paired) region for GRS/RAGRS/GZRS/RAGZRS accounts, empty otherwise."
  value       = azurerm_storage_account.this.secondary_location
}

output "account_kind" {
  description = "Account kind (StorageV2 or BlockBlobStorage)."
  value       = azurerm_storage_account.this.account_kind
}

output "account_tier" {
  description = "Performance tier (Standard or Premium)."
  value       = azurerm_storage_account.this.account_tier
}

output "account_replication_type" {
  description = "Redundancy of the account (LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS)."
  value       = azurerm_storage_account.this.account_replication_type
}

output "access_tier" {
  description = "Default blob access tier (Hot, Cool or Cold; reported by Azure for Premium accounts)."
  value       = azurerm_storage_account.this.access_tier
}

# =============================================================================
# Endpoints (non-sensitive; access keys and connection strings are never
# exposed: the module disables Shared Key authentication by default)
# =============================================================================

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint (`https://<name>.blob.core.windows.net/`)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Primary blob service host name, e.g. for firewall or private DNS rules."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "secondary_blob_endpoint" {
  description = "Secondary blob endpoint for RAGRS/RAGZRS accounts (read access), empty otherwise."
  value       = azurerm_storage_account.this.secondary_blob_endpoint
}

# =============================================================================
# Security posture (as applied; useful for compliance reports and audits)
# =============================================================================

output "security_configuration" {
  description = "Effective security settings of the account."
  value = {
    shared_access_key_enabled         = azurerm_storage_account.this.shared_access_key_enabled
    default_to_oauth_authentication   = azurerm_storage_account.this.default_to_oauth_authentication
    https_traffic_only_enabled        = azurerm_storage_account.this.https_traffic_only_enabled
    min_tls_version                   = azurerm_storage_account.this.min_tls_version
    blob_public_access_enabled        = azurerm_storage_account.this.allow_nested_items_to_be_public
    infrastructure_encryption_enabled = azurerm_storage_account.this.infrastructure_encryption_enabled
    cross_tenant_replication_enabled  = azurerm_storage_account.this.cross_tenant_replication_enabled
    allowed_copy_scope                = azurerm_storage_account.this.allowed_copy_scope
    public_network_access             = azurerm_storage_account.this.public_network_access
    network_default_action            = azurerm_storage_account.this.network_rules[0].default_action
    network_ip_rules                  = azurerm_storage_account.this.network_rules[0].ip_rules
  }
}

output "data_protection" {
  description = "Blob versioning and soft delete retention (0 = soft delete disabled)."
  value = {
    versioning_enabled              = azurerm_storage_account.this.blob_properties[0].versioning_enabled
    delete_retention_days           = try(azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days, 0)
    container_delete_retention_days = try(azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days, 0)
  }
}

# =============================================================================
# Containers, access control, protection
# =============================================================================

output "containers" {
  description = "Map of container key => name, resource ID (Azure Resource Manager ID, scope for container-level role assignments) and access type."
  value = {
    for key, container in azurerm_storage_container.this : key => {
      name        = container.name
      id          = container.id
      access_type = container.container_access_type
    }
  }
}

output "container_names" {
  description = "Sorted list of the container names."
  value       = sort([for container in azurerm_storage_container.this : container.name])
}

output "role_assignments" {
  description = "Map of role assignment key => ID, scope, principal and role."
  value = {
    for key, ra in azurerm_role_assignment.this : key => {
      id                   = ra.id
      scope                = ra.scope
      principal_id         = ra.principal_id
      role_definition_name = ra.role_definition_name
    }
  }
}

output "management_lock_id" {
  description = "ID of the CanNotDelete management lock, null when delete_lock_enabled = false."
  value       = one(azurerm_management_lock.this[*].id)
}
