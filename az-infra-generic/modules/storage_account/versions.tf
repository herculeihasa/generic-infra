terraform {
  # Child module: declare the MINIMUM versions it needs and let the root
  # configuration pin exact versions (lock file). No provider block here, so
  # callers keep full control over provider configuration and aliases.
  #
  # 1.9 is required for input validations that reference other variables.
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.x schema: public_network_access (string), storage_account_id on
      # azurerm_storage_container (management-plane container API).
      version = ">= 5.14.0, < 6.0.0"
    }
  }
}
