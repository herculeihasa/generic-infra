# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

variable "resource_providers_to_register" {
  description = "Azure Resource Providers the azurerm provider registers on the subscription at start-up (azurerm 5.x registers none by default). Set to [] when Resource Provider registration is managed outside Terraform or the identity lacks the */register/action permission."
  type        = list(string)
  default = [
    "Microsoft.Compute",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
  ]
}
