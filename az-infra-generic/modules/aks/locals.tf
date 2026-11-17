locals {
  # DNS prefix: lowercase, only letters/digits/hyphens, max 54 characters,
  # no leading/trailing hyphen.
  dns_prefix = coalesce(
    var.dns_prefix,
    trim(substr(replace(lower(var.name), "/[^a-z0-9-]/", "-"), 0, 54), "-"),
  )

  tags = merge(var.tags, {
    managed_by = "terraform"
    module     = "aks"
  })
}
