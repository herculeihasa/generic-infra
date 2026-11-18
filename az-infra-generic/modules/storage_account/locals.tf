locals {
  tags = merge(var.tags, {
    managed_by = "terraform"
    module     = "storage_account"
  })
}
