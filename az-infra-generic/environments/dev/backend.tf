terraform {
  # Remote state in Azure Blob Storage, created by ../../bootstrap.
  #
  # Partial configuration: only the storage account name is environment-
  # agnostic and unknown until the bootstrap has run, so it is supplied at
  # init time:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # (backend.hcl is generated from `terraform -chdir=../../bootstrap output
  # -raw backend_hcl`; see backend.hcl.example.) Credentials are NEVER put
  # here: they come from ARM_* environment variables or `az login`.
  backend "azurerm" {
    # Microsoft Entra ID data-plane authentication (Storage Blob Data
    # Contributor role); account keys and SAS are disabled on the account.
    use_azuread_auth = true

    # Environment isolation: dev state lives in its own container, so RBAC
    # can be granted per environment at container scope.
    container_name = "tfstate-dev"
    key            = "az-infra-generic/aks.tfstate"

    # Locking: native blob lease, taken automatically for every operation
    # that writes state. Consistency/recovery: blob versioning + soft delete.
  }
}
