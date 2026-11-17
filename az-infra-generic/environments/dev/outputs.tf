output "resource_group_name" {
  description = "Resource group of the dev environment."
  value       = azurerm_resource_group.this.name
}

output "virtual_network_id" {
  description = "Resource ID of the environment virtual network."
  value       = azurerm_virtual_network.this.id
}

output "aks_nodes_subnet_id" {
  description = "Resource ID of the AKS node subnet."
  value       = azurerm_subnet.aks_nodes.id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving AKS logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "aks_id" {
  description = "Resource ID of the AKS cluster."
  value       = module.aks.id
}

output "aks_name" {
  description = "Name of the AKS cluster."
  value       = module.aks.name
}

output "aks_kubernetes_version" {
  description = "Kubernetes version running on the cluster."
  value       = module.aks.current_kubernetes_version
}

output "aks_api_server_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = module.aks.api_server_endpoint
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation."
  value       = module.aks.oidc_issuer_url
}

output "aks_cluster_identity" {
  description = "Control plane managed identity."
  value       = module.aks.cluster_identity
}

output "aks_kubelet_identity" {
  description = "Kubelet managed identity (grant it AcrPull on registries)."
  value       = module.aks.kubelet_identity
}

output "aks_get_credentials_command" {
  description = "Command to fetch an Entra ID based kubeconfig (the raw kubeconfig is intentionally not re-exported here)."
  value       = module.aks.get_credentials_command
}
