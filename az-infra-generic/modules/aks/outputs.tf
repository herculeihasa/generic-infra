# =============================================================================
# Cluster
# =============================================================================

output "id" {
  description = "Resource ID of the AKS cluster (scope for Azure RBAC role assignments)."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  description = "Resource group of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.resource_group_name
}

output "location" {
  description = "Azure region of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.location
}

output "kubernetes_version" {
  description = "Kubernetes version requested for the control plane (as configured, or the AKS default selected at creation)."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

output "current_kubernetes_version" {
  description = "Kubernetes version actually running (moves with auto-upgrades)."
  value       = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "node_resource_group" {
  description = "Name of the AKS-managed node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "node_resource_group_id" {
  description = "Resource ID of the AKS-managed node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group_id
}

output "node_pool_ids" {
  description = "Map of additional node pool name => node pool resource ID."
  value       = { for name, pool in azurerm_kubernetes_cluster_node_pool.this : name => pool.id }
}

# =============================================================================
# API server access
# =============================================================================

output "fqdn" {
  description = "Public FQDN of the API server (empty for private clusters without public FQDN)."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "private_fqdn" {
  description = "Private FQDN of the API server (private clusters only)."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "api_server_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server (private FQDN for private clusters)."
  value       = local.api_server_fqdn == null ? null : "https://${local.api_server_fqdn}:443"
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL, used to federate Workload Identity credentials."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "get_credentials_command" {
  description = "Recommended way to obtain a kubeconfig: Entra ID based, nothing secret is written to Terraform state or outputs. With local accounts disabled, convert it for non-interactive use with `kubelogin convert-kubeconfig -l azurecli`."
  value       = "az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --name ${azurerm_kubernetes_cluster.this.name}"
}

output "kube_config_raw" {
  description = "Raw kubeconfig of the (non-admin) cluster user. SENSITIVE: with local accounts enabled it embeds credentials. Prefer get_credentials_command."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, e.g. to configure the kubernetes/helm providers with exec-based (kubelogin) authentication. Marked sensitive because the provider exposes it inside the kube_config block."
  value       = one(azurerm_kubernetes_cluster.this.kube_config[*].cluster_ca_certificate)
  sensitive   = true
}

# =============================================================================
# Identities
# =============================================================================

output "cluster_identity" {
  description = "Control plane managed identity: type, principal (object) ID and, for user-assigned identities, the resource ID."
  value = {
    type                      = var.identity_type
    principal_id              = local.cluster_user_assigned_identity != null ? local.cluster_user_assigned_identity.principal_id : one(azurerm_kubernetes_cluster.this.identity[*].principal_id)
    user_assigned_identity_id = try(local.cluster_user_assigned_identity.id, null)
  }
}

output "kubelet_identity" {
  description = "Kubelet managed identity ({ client_id, object_id, user_assigned_identity_id }) used by nodes, e.g. to pull images."
  value       = one(azurerm_kubernetes_cluster.this.kubelet_identity)
}

output "key_vault_secrets_provider_identity" {
  description = "Identity of the Key Vault Secrets Store CSI driver add-on ({ client_id, object_id, user_assigned_identity_id }), null when the add-on is disabled. Grant it Key Vault access when not using Workload Identity."
  value       = one(flatten(azurerm_kubernetes_cluster.this.key_vault_secrets_provider[*].secret_identity))
}

# =============================================================================
# Observability
# =============================================================================

output "container_insights_data_collection_rule_id" {
  description = "Resource ID of the Container Insights data collection rule (null when disabled)."
  value       = one(azurerm_monitor_data_collection_rule.container_insights[*].id)
}
