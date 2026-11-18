output "resource_group_name" {
  description = "Resource group holding the Terraform state storage."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "State storage account name: the value expected by -backend-config in every environment."
  value       = module.state_storage.name
}

output "storage_account_id" {
  description = "Resource ID of the state storage account (scope for additional role assignments)."
  value       = module.state_storage.id
}

output "blob_endpoint" {
  description = "Primary blob endpoint of the state storage account."
  value       = module.state_storage.primary_blob_endpoint
}

output "state_containers" {
  description = "Map of environment => state container name and resource ID."
  value = {
    for env, container in module.state_storage.containers : env => {
      name = container.name
      id   = container.id
    }
  }
}

output "backend_hcl" {
  description = "Ready-to-use content of environments/<env>/backend.hcl. The container and key stay in each environment's backend.tf, so a copied file can never point one environment at another's state."
  value       = <<-EOT
    # Generated from the bootstrap outputs (terraform output -raw backend_hcl).
    # Non-sensitive identifier only: safe to commit.
    storage_account_name = "${module.state_storage.name}"
  EOT
}

output "security_configuration" {
  description = "Effective security settings of the state storage account (from the storage_account module), for audits."
  value       = module.state_storage.security_configuration
}
