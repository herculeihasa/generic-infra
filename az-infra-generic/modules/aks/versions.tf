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
      # 5.x schema (node_provisioning_profile, enabled_metric, ...) and the
      # AKS API version shipped with 5.14.
      version = ">= 5.14.0, < 6.0.0"
    }
  }
}
