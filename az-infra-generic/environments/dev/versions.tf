terraform {
  # Root configuration: pinned to the toolchain the project is validated with.
  # The exact CLI version used locally/CI is set in ../../.terraform-version.
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Any 5.x release from 5.14 onwards. The exact build (and its checksums)
      # is pinned in .terraform.lock.hcl, which is committed.
      version = "~> 5.14"
    }
  }
}
