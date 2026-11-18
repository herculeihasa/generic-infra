# =============================================================================
# State migration to modules/storage_account
#
# The state storage used to be declared directly in this configuration. These
# blocks tell Terraform that the existing objects now live in
# module.state_storage, so a bootstrap state created before the module
# existed is migrated on the next plan/apply without destroying or
# recreating anything (the plan reports "has moved to" for each object).
# Keys are unchanged: containers stay keyed by environment, contributor role
# assignments by "<environment>/<principal_id>".
#
# They are no-ops for a new bootstrap. Keep them until every existing
# bootstrap state has been applied with this version: removing them earlier
# would make Terraform plan to destroy the state account (blocked by
# prevent_destroy) and recreate its containers.
# =============================================================================

moved {
  from = azurerm_storage_account.tfstate
  to   = module.state_storage.azurerm_storage_account.this
}

moved {
  from = azurerm_storage_container.tfstate
  to   = module.state_storage.azurerm_storage_container.this
}

moved {
  from = azurerm_role_assignment.state_contributors
  to   = module.state_storage.azurerm_role_assignment.this
}

moved {
  from = azurerm_role_assignment.current_principal_state_access[0]
  to   = module.state_storage.azurerm_role_assignment.this["current-principal"]
}

moved {
  from = azurerm_management_lock.tfstate
  to   = module.state_storage.azurerm_management_lock.this
}
