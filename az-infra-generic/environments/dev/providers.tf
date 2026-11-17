provider "azurerm" {
  # Authentication is never configured in code. It is resolved from the
  # environment (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID,
  # ARM_USE_OIDC, ...) or from an authenticated Azure CLI session (`az login`).
  # No subscription ID, tenant ID or secret is ever committed.

  # azurerm 5.x registers no Resource Provider by default: register only the
  # ones this configuration needs (or none, see the variable description).
  resource_providers_to_register = var.resource_providers_to_register

  features {
    resource_group {
      # Refuse to delete a resource group that still holds resources Terraform
      # does not know about (e.g. created by hand or by AKS add-ons).
      prevent_deletion_if_contains_resources = true
    }
  }
}
