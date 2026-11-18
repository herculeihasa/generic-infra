locals {
  tags = merge(var.tags, {
    managed_by = "terraform"
    module     = "storage_account"
  })

  # Premium (BlockBlobStorage) accounts have no blob access tier: leaving the
  # argument unset avoids a permanent diff against the value Azure reports.
  access_tier = var.account_tier == "Premium" ? null : var.access_tier
}
