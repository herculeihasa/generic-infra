terraform {
  # Root configuration: pinned to the toolchain the project is validated with.
  # The exact CLI version used locally/CI is set in ../.terraform-version.
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Any 5.x release from 5.14 onwards. The exact build (and its checksums)
      # is pinned in .terraform.lock.hcl, which is committed.
      version = "~> 5.14"
    }
  }

  # No backend block on purpose: the bootstrap creates the remote backend
  # storage, so its own state is LOCAL (chicken-and-egg). See README,
  # "Backend storage bootstrap procedure".
}

provider "azurerm" {
  # Authentication is never configured in code. It is resolved from the
  # environment (ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID,
  # ARM_USE_OIDC, ...) or from an authenticated Azure CLI session (`az login`).

  # The storage account is created with Shared Key access disabled, so any
  # data-plane call the provider makes must use Microsoft Entra ID.
  storage_use_azuread = true

  # azurerm 5.x registers no Resource Provider by default.
  resource_providers_to_register = var.resource_providers_to_register

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
