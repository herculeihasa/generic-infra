# =============================================================================
# Generic Azure Kubernetes Service (AKS) module
#
# File layout:
#   versions.tf    Terraform / provider minimum versions (no provider block)
#   variables.tf   Module interface (inputs, defaults, validations)
#   locals.tf      Derived values
#   main.tf        The AKS cluster
#   outputs.tf     Module outputs
#   tests/         Offline `terraform test` suites (mocked azurerm provider)
#
# The module never creates the resource group, virtual network, Log Analytics
# workspace or Key Vault: those are owned by the calling configuration and
# passed in by ID, so the module can be reused across projects/environments.
# =============================================================================
