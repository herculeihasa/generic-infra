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
