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
  description = "Primary blob service endpoint (https://<name>.blob.core.windows.net/)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Primary blob service host name, e.g. for firewall or private DNS rules."
  value       = azurerm_storage_account.this.primary_blob_host
}
